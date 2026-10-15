;; Concrete text input and output. Rust owns file payloads; each wrapper's
;; shared Ref makes explicit close idempotent across aliases. No GC finalizer
;; owns these files. Stdout is borrowed; invocation cleanup only closes files.
(define-library (snail io)
  (export InputPort OutputPort LineResult end-of-file line line-text eof-object?
          CharacterResult character-end character-value character-text character-end?
          read-char peek-char
          file-exists? delete-file open-input-file close-input-port
          call-with-input-file read-line open-output-file close-output-port
          call-with-output-file current-output-port output-port=?
          write-char write-string write-i64 newline)
  (import (snail strict))
  (begin

    ;; ---- Scalar resource boundary ----

    (define-data OutputPort
      (output-port (handle (Ref I32) output-handle)))
    (define-data InputPort
      (input-port (handle (Ref I32) input-handle)))
    (define-data LineResult (end-of-file) (line (text String line-text)))
    (define-data CharacterResult
      (character-end) (character-value (text Char character-text)))
    (define-extern path-begin "snail.library" "snail:io/path-begin" (-> Unit))
    (define-extern path-character "snail.library" "snail:io/path-character" (-> Char Unit))
    (define-extern path-exists "snail.library" "snail:io/file-exists" (-> I32))
    (define-extern path-delete "snail.library" "snail:io/delete-file" (-> Unit))
    (define-extern path-open-output "snail.library" "snail:io/open-output-file" (-> I32))
    (define-extern path-open-input "snail.library" "snail:io/open-input-file" (-> I32))
    (define-extern port-read "snail.library" "snail:io/read-character" (-> I32 I32))
    (define-extern port-peek "snail.library" "snail:io/peek-character" (-> I32 I32))
    (define-extern port-write "snail.library" "snail:io/write-character" (-> I32 Char Unit))
    (define-extern port-close "snail.library" "snail:io/close" (-> I32 Unit))
    (define-extern standard-output-handle "snail.library" "snail:io/standard-output" (-> I32))
    (define-extern port-check-output "snail.library" "snail:io/check-output" (-> I32 Unit))

    ;; This singleton borrows stdout. Its reserved scalar ID never names an
    ;; owned file, and neither explicit close nor trap cleanup closes the stream.
    ;; Current output is fixed here; dynamic rebinding is not implemented.
    (define standard-output (output-port (ref (standard-output-handle))))
    (: current-output-port (-> OutputPort))
    (define (current-output-port) standard-output)
    (: output-port=? (-> OutputPort OutputPort Bool))
    (define (output-port=? left right) (ref-eq? (output-handle left) (output-handle right)))

    ;; No user callback occurs between begin and the consuming file operation.
    ;; UTF-8 encoding happens in Rust; String traversal stays in Scheme.
    (: stage-path (-> String Unit))
    (define (stage-path pathname)
      (path-begin)
      (let ((count (string-length pathname)))
        (let loop ((index 0))
          (unless (= index count)
            (path-character (string-ref pathname index))
            (loop (+ index 1))))))
    (: file-exists? (-> String Bool))
    (define (file-exists? pathname)
      (stage-path pathname)
      (i32-eq (path-exists) (ann 1 I32)))
    (: delete-file (-> String Unit))
    (define (delete-file pathname) (stage-path pathname) (path-delete))
    (: open-output-file (-> String OutputPort))
    (define (open-output-file pathname)
      (stage-path pathname)
      (output-port (ref (path-open-output))))
    (: open-input-file (-> String InputPort))
    (define (open-input-file pathname)
      (stage-path pathname)
      (input-port (ref (path-open-input))))

    ;; ---- Explicit close and a normally returning callback ----

    (: close-output-port (-> OutputPort Unit))
    (define (close-output-port port)
      (close-handle (output-handle port)))
    (: close-input-port (-> InputPort Unit))
    (define (close-input-port port)
      (close-handle (input-handle port)))
    (: close-handle (-> (Ref I32) Unit))
    (define (close-handle cell)
      (let ((handle (ref-get cell)))
        (unless (or (i32-eq handle (ann -1 I32)) (i32-eq handle (ann -2 I32)))
          (ref-set! cell (ann -1 I32))
          (port-close handle))))
    (: call-with-output-file (All (T) (-> String (-> OutputPort T) T)))
    (define (call-with-output-file pathname procedure)
      (let* ((port (open-output-file pathname)) (result (procedure port)))
        (close-output-port port)
        result))
    (: call-with-input-file (All (T) (-> String (-> InputPort T) T)))
    (define (call-with-input-file pathname procedure)
      (let* ((port (open-input-file pathname)) (result (procedure port)))
        (close-input-port port)
        result))

    ;; ---- Complete lines distinguish an empty line from end of file ----

    (: character-end? (-> CharacterResult Bool))
    (define (character-end? result)
      (match result ((character-end) #t) ((character-value text) #f)))
    (: character-result (-> I32 CharacterResult))
    (define (character-result code)
      (if (i32-eq code (ann -1 I32)) (character-end)
          (character-value (integer->char (i32->i64 code)))))
    (: read-char (-> InputPort CharacterResult))
    (define (read-char port)
      (character-result (port-read (ref-get (input-handle port)))))
    (: peek-char (-> InputPort CharacterResult))
    (define (peek-char port)
      (character-result (port-peek (ref-get (input-handle port)))))

    (: eof-object? (-> LineResult Bool))
    (define (eof-object? result)
      (match result ((end-of-file) #t) ((line text) #f)))
    (: read-line (-> InputPort LineResult))
    (define (read-line port)
      (let* ((handle (ref-get (input-handle port))) (code (port-read handle)))
        (if (i32-eq code (ann -1 I32)) (end-of-file)
            (line (read-line-text handle code (make-string 0) 0)))))
    ;; Rust validates UTF-8 and keeps one lookahead in the input port. CR, LF,
    ;; and CRLF terminate one line. A non-LF lookahead belongs to the next read.
    (: consume-line-feed (-> I32 Unit))
    (define (consume-line-feed handle)
      (when (i32-eq (port-peek handle) (ann 10 I32)) (port-read handle) (unit)))
    (: read-line-text (-> I32 I32 String I64 String))
    (define (read-line-text handle code buffer count)
      (if (or (i32-eq code (ann -1 I32))
              (i32-eq code (ann 10 I32)) (i32-eq code (ann 13 I32)))
          (begin
            (when (i32-eq code (ann 13 I32)) (consume-line-feed handle))
            (if (= count (string-length buffer)) buffer (substring buffer 0 count)))
          (let ((buffer (line-capacity buffer count)))
            (string-set! buffer count (integer->char (i32->i64 code)))
            (read-line-text handle (port-read handle) buffer (+ count 1)))))
    ;; Only the first count characters are initialized text. Doubling capacity
    ;; bounds total copying by a geometric series; no character needs a GC node.
    ;; The final substring trims spare capacity once, and exact fits reuse it.
    (: line-capacity (-> String I64 String))
    (define (line-capacity buffer count)
      (if (< count (string-length buffer)) buffer
          (if (= count 4294967294) (unreachable)
              (let* ((size (if (= count 0) 64
                               (if (> count 2147483647) 4294967294 (* count 2))))
                     (grown (make-string size)))
                (string-copy! grown 0 buffer 0 count)
                grown))))

    ;; ---- Character iteration and decimal integer formatting ----

    (: write-char-to (-> Char OutputPort Unit))
    (define (write-char-to character port)
      (port-write (ref-get (output-handle port)) character))
    (: write-string-to (-> String OutputPort Unit))
    (define (write-string-to text port)
      ;; Even an empty write checks direction and lifetime without emitting text.
      (port-check-output (ref-get (output-handle port)))
      (let ((count (string-length text)))
        (let loop ((index 0))
          (unless (= index count)
            (write-char (string-ref text index) port)
            (loop (+ index 1))))))
    (: newline-to (-> OutputPort Unit))
    (define (newline-to port) (write-char #\newline port))
    (define-overload write-char (-> Char OutputPort Unit) write-char-to)
    (define-overload write-char (-> Char Unit)
      (lambda (character) (write-char-to character (current-output-port))))
    (define-overload write-string (-> String OutputPort Unit) write-string-to)
    (define-overload write-string (-> String Unit)
      (lambda (text) (write-string-to text (current-output-port))))
    (define-overload newline (-> OutputPort Unit) newline-to)
    (define-overload newline (-> Unit) (lambda () (newline-to (current-output-port))))
    (: write-i64 (-> I64 OutputPort Unit))
    (define (write-i64 number port)
      (when (< number 0) (write-char #\- port))
      (write-negative-digits (if (> number 0) (- 0 number) number) port))
    ;; Nonpositive digits avoid negating I64_MIN. Remainders are in [-9, 0],
    ;; recursion has at most 19 levels, and zero still emits one digit.
    (: write-negative-digits (-> I64 OutputPort Unit))
    (define (write-negative-digits number port)
      (let ((prefix (quotient number 10)))
        (unless (= prefix 0) (write-negative-digits prefix port))
        (write-char (integer->char (- 48 (remainder number 10))) port)))))
