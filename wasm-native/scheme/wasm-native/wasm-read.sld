;; Adapt configured Binaryen spellings to the host Scheme datum reader.
;; Name/type resolution stays in wasm-resolve; this is not a general WAT parser.
(define-library (wasm-native wasm-read)
  (export read-binaryen-module)
  (import
   (scheme base)
   (scheme file)
   (scheme char)
   (scheme write)
   (rename (only (chibi) read) (read read-wasm-datum)))
  (begin

    ;; ---- Buffered bytes ----

    ;; Keep lookahead within a bounded buffer. In the installed runtime, indexing
    ;; a whole UTF-8 string repeatedly would traverse its prefix for every byte.
    (define-record-type <wat-input>
      (make-wat-input port bytes offset) wat-input?
      (port wat-port)
      (bytes wat-bytes set-wat-bytes!)
      (offset wat-offset set-wat-offset!))

    (define (fill-wat-input input)
      (let ((bytes (read-bytevector 65536 (wat-port input))))
        (set-wat-bytes! input (and (not (eof-object? bytes)) bytes))
        (set-wat-offset! input 0)))

    (define (peek-wat-byte input)
      (when (and (wat-bytes input) (= (wat-offset input) (bytevector-length (wat-bytes input))))
        (fill-wat-input input))
      (and (wat-bytes input) (bytevector-u8-ref (wat-bytes input) (wat-offset input))))

    (define (take-wat-byte input)
      (let ((byte (peek-wat-byte input)))
        (unless byte (error "unfinished Binaryen text"))
        (set-wat-offset! input (+ 1 (wat-offset input)))
        byte))

    (define (wat-space? byte) (memv byte '(9 10 13 32)))

    (define (wat-bytes->text reversed)
      (utf8->string (apply bytevector (reverse reversed))))

    ;; ---- Atoms and quoted names ----

    ;; Tokens keep their spelling until their constant opcode gives context.
    (define (read-wat-token input)
      (let loop ((bytes '()))
        (let ((next (peek-wat-byte input)))
          (if (or (not next) (wat-space? next) (memv next '(40 41 59)))
              (wat-bytes->text bytes)
              (begin
                (when (= next 34) (error "unsupported Binaryen atom"))
                (loop (cons (take-wat-byte input) bytes)))))))

    (define (wat-hex-digit byte)
      (cond ((<= 48 byte 57) (- byte 48))
            ((<= 65 byte 70) (- byte 55))
            ((<= 97 byte 102) (- byte 87))
            (else (error "invalid Binaryen byte escape" byte))))

    (define (read-wat-escape input)
      (let ((first (take-wat-byte input)))
        (case first
          ((116) 9) ((110) 10) ((114) 13) ; t, n, r
          ((34 39 92) first) ; quote, apostrophe, backslash
          (else (+ (* 16 (wat-hex-digit first)) (wat-hex-digit (take-wat-byte input)))))))

    ;; WAT escapes encode bytes, not Unicode characters. Decode UTF-8 only after
    ;; gathering the complete name, including any escaped multibyte sequence.
    (define (read-wat-string input)
      (take-wat-byte input)
      (let loop ((bytes '()))
        (let ((next (take-wat-byte input)))
          (case next
            ((34) (wat-bytes->text bytes))
            ((92) (loop (cons (read-wat-escape input) bytes)))
            (else (loop (cons next bytes)))))))

    (define (decimal-integer-token? text)
      (let* ((length (string-length text))
             (start (if (and (> length 0) (memv (string-ref text 0) '(#\+ #\-))) 1 0)))
        (and (> length start)
             (let loop ((index start))
               (or (= index length)
                   (and (char<=? #\0 (string-ref text index) #\9) (loop (+ index 1))))))))

    ;; Integer-spelled floats may exceed the reader's signed integer range.
    ;; A decimal point requests f64 parsing and also preserves the sign of -0.
    ;; Binaryen prints i64 constants as signed decimals; leave them unchanged.
    (define (scheme-wat-token previous text)
      (if (and (member previous '("f32.const" "f64.const")) (decimal-integer-token? text))
          (string-append text ".0") text))

    ;; ---- Comments are whitespace ----

    ;; Binaryen describes opaque custom sections in line comments. Block
    ;; comments may nest; quotes and escapes inside comments have no meaning.
    (define (skip-wat-line-comment input)
      (let ((next (peek-wat-byte input)))
        (when (and next (not (memv next '(10 13))))
          (take-wat-byte input) (skip-wat-line-comment input))))

    (define (skip-wat-block-comment input)
      (let loop ((depth 1))
        (unless (peek-wat-byte input) (error "unfinished Binaryen block comment"))
        (let* ((byte (take-wat-byte input)) (next (peek-wat-byte input)))
          (cond ((and (= byte 40) (eqv? next 59))
                 (take-wat-byte input) (loop (+ depth 1)))
                ((and (= byte 59) (eqv? next 41))
                 (take-wat-byte input) (unless (= depth 1) (loop (- depth 1))))
                (else (loop depth))))))

    ;; ---- WAT spellings to Scheme text ----

    ;; This exhaustive lexical loop preserves module structure. Its only atom
    ;; rewrite is integer-spelled floats; WAT bytes become Scheme strings.
    ;; Comments preserve the preceding token, just like ordinary whitespace.
    (define (normalize-binaryen-text port output)
      (let ((input (make-wat-input port (bytevector) 0)))
        (let loop ((previous #f))
          (let ((next (peek-wat-byte input)))
            (cond ((not next) #t)
                  ((= next 34) (write (read-wat-string input) output) (loop #f))
                  ((= next 40)
                   (take-wat-byte input)
                   (if (eqv? (peek-wat-byte input) 59)
                       (begin (take-wat-byte input) (skip-wat-block-comment input)
                              (write-char #\space output) (loop previous))
                       (begin (write-char #\( output) (loop #f))))
                  ((or (wat-space? next) (= next 41))
                   (write-char (integer->char (take-wat-byte input)) output)
                   (loop (and (wat-space? next) previous)))
                  ((= next 59)
                   (take-wat-byte input)
                   (unless (eqv? (peek-wat-byte input) 59) (error "unexpected Binaryen semicolon"))
                   (take-wat-byte input) (skip-wat-line-comment input)
                   (write-char #\space output) (loop previous))
                  (else (let ((text (read-wat-token input)))
                          (display (scheme-wat-token previous text) output)
                          (loop text))))))))

    ;; ---- One declaration at a time ----

    ;; A single module read would keep every temporary reader root alive until
    ;; the largest datum finishes. Declarations need no shared Scheme labels.
    ;; Chibi's core reader also avoids its slower SRFI-38 shared-structure parser.
    (define (skip-reader-space port)
      (let ((next (peek-char port)))
        (when (and (char? next) (char-whitespace? next))
          (read-char port) (skip-reader-space port))))

    (define (read-wasm-declarations port)
      (let loop ((declarations '()))
        (skip-reader-space port)
        (let ((next (peek-char port)))
          (cond ((eof-object? next) (error "unfinished Binaryen module"))
                ((eqv? next #\)) (read-char port) (cons 'module (reverse declarations)))
                (else (loop (cons (read-wasm-datum port) declarations)))))))

    (define (read-wasm-module port)
      (skip-reader-space port)
      (unless (and (eqv? (read-char port) #\() (eq? (read-wasm-datum port) 'module))
        (error "expected Binaryen module header"))
      (let ((module (read-wasm-declarations port)))
        (skip-reader-space port)
        (unless (eof-object? (peek-char port)) (error "expected one complete Binaryen module"))
        module))

    (define (read-binaryen-module input reader-text)
      (call-with-port (open-binary-input-file input)
        (lambda (port)
          (call-with-output-file reader-text
            (lambda (output) (normalize-binaryen-text port output)))))
      (call-with-input-file reader-text read-wasm-module)))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm-read)
    (import
     (scheme inexact)
     (wasm-native test-utils))
    (begin
      (define (read-text text)
        (let ((output (open-output-string)))
          (normalize-binaryen-text (open-input-bytevector (string->utf8 text)) output)
          (read-wasm-module (open-input-string (get-output-string output)))))

      (define (test-wat-comments)
        (expect (read-text "(; prefix (; nested ;) ;) (module;; opaque custom section\n(f64.const(; token gap ;)-0)) ;; trailing")
                '(module (f64.const -0.0)))
        (expect (read-text "(module (export \";; (; literal ;)\" (func 0)))")
                '(module (export ";; (; literal ;)" (func 0))))
        (expect (read-text (string-append "(module (;" (make-string 65536 #\x) "(; split ;) ;) )")) '(module))
        (let ((zero (cadr (cadr (read-text "(module (f64.const;; comment\r-0))")))))
          (expect (negative? (/ 1.0 zero)) #t))
        (for-each (lambda (text) (expect (guard (failure (else #t)) (read-text text) #f) #t))
                  '("(module (; unfinished)" "(module (; nested (; ;) )" "(module ;)")))

      (define (test-wasm-read)
        (run-test test-wat-comments)
        (expect (read-text "(module (type $t (struct)) (i32.const -0))")
                '(module (type $t (struct)) (i32.const 0)))
        (expect (read-text "(module (export \"\\ce\\bb\\00\\n\\t\\r\\\"\\\\\" (func $f)))")
                `(module (export ,(string-append "λ" (string (integer->char 0)) "\n\t\r\"\\") (func $f))))
        (let ((zero (cadr (cadr (read-text "(module (f64.const -0))")))))
          (expect (negative? (/ 1.0 zero)) #t))
        (expect (read-text "(module (f64.const 9223372036854775808))")
                `(module (f64.const ,(string->number "9223372036854775808.0"))))
        (expect (read-text "(module (f64.const -nan:0x8000000000005))")
                '(module (f64.const -nan:0x8000000000005)))
        (for-each (lambda (text)
                    (expect (guard (failure (else #t)) (read-text text) #f) #t))
                  '("(module" "(module) (module)" "(module ;comment\n)" "(module \"\\zz\")")))))
   (else)))
