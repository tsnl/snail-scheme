(define-library (snail-scheme wasm-binary)
  (export read-wasm read-wasm-file read-wasm-instruction wasm-code-copy wasm-code-end?)
  (import (scheme base) (scheme cxr) (scheme file))
  (begin

    ;; ---- Bounded binary input ----

    ;; This reader consumes validated, canonicalized Wasm, as produced by our
    ;; Binaryen link step. It checks byte boundaries and rejects unsupported
    ;; encodings; it does not duplicate the Wasm type validator. Declarations
    ;; use numeric indices. Function bodies remain slices of the input bytes,
    ;; so lowering never builds a text file or a tree of instruction operands.

    (define-record-type <wasm-code>
      (make-code bytes position end) wasm-code?
      (bytes code-bytes) (position code-position set-code-position!) (end code-end))

    (define (wasm-code-copy code)
      (make-code (code-bytes code) (code-position code) (code-end code)))

    (define (wasm-code-end? code) (= (code-position code) (code-end code)))

    (define (take-code code count)
      (let* ((start (code-position code)) (end (+ start count)))
        (when (> end (code-end code)) (error "truncated Wasm binary" start count))
        (set-code-position! code end)
        (make-code (code-bytes code) start end)))

    (define (peek-byte code)
      (when (wasm-code-end? code) (error "unexpected end of Wasm binary" (code-position code)))
      (bytevector-u8-ref (code-bytes code) (code-position code)))

    (define (read-byte code)
      (let ((byte (peek-byte code)))
        (set-code-position! code (+ 1 (code-position code)))
        byte))

    ;; Validate the last payload before folding from most to least significant.
    ;; Sign extension starts at -1; neither positive 2^63 nor 2^64 is needed.
    (define (leb-terminal-valid? payload signed? remaining)
      (or (> remaining 7)
          (let ((limit (vector-ref '#(1 2 4 8 16 32 64 128) remaining)))
            (if signed? (or (< payload (quotient limit 2))
                            (>= payload (- 128 (quotient limit 2))))
                (< payload limit)))))

    (define (fold-leb payloads negative?)
      (let loop ((rest payloads) (value (if negative? -1 0)))
        (if (null? rest) value
            (loop (cdr rest) (+ (* value 128) (car rest))))))

    (define (read-leb code signed? width)
      (let loop ((remaining width) (payloads '()))
        (let* ((byte (read-byte code)) (payload (modulo byte 128))
               (payloads (cons payload payloads)))
          (cond ((< byte 128)
                 (unless (leb-terminal-valid? payload signed? remaining)
                   (error "Wasm integer overflow"))
                 (fold-leb payloads (and signed? (>= payload 64))))
                ((<= remaining 7) (error "Wasm integer encoding is too long"))
                (else (loop (- remaining 7) payloads))))))

    (define (read-index code)
      (if (< (peek-byte code) 128) (read-byte code) (read-leb code #f 32)))

    (define (read-u32 code)
      (let loop ((remaining 4) (scale 1) (word 0))
        (if (= remaining 0) word
            (let ((byte (read-byte code)))
              (loop (- remaining 1) (* scale 256) (+ word (* byte scale)))))))

    ;; A raw 64-bit word is a signed integer carrying the same bits. Compose
    ;; two halves so the sign bit never overflows the compiler's exact integers.
    (define (read-word code count)
      (let ((low (read-u32 code)))
        (if (= count 4) low
            (let* ((high (read-u32 code))
                   (signed-high (if (>= high 2147483648) (- high 4294967296) high)))
              (+ (* signed-high 4294967296) low)))))

    (define (read-items reader code)
      (let loop ((count (read-index code)) (items '()))
        (if (= count 0) (reverse items)
            (let ((item (reader code))) (loop (- count 1) (cons item items))))))

    (define (read-bytes code)
      (let ((part (take-code code (read-index code))))
        (bytevector-copy (code-bytes part) (code-position part) (code-end part))))

    (define (read-name code) (utf8->string (read-bytes code)))

    ;; ---- Types ----

    ;; Composite types have fixed positions: (func parameters results),
    ;; (struct field ...), and (array element). A mutable field is (mut type).

    (define heap-types
      '((-16 . func) (-18 . any) (-19 . eq) (-20 . i31)
        (-21 . struct) (-22 . array) (-13 . nofunc) (-15 . none)))

    (define (read-heap-type code)
      (let ((type (read-leb code #t 33)))
        (if (>= type 0) type
            (let ((entry (assv type heap-types)))
              (if entry (cdr entry) (error "unsupported Wasm heap type" type))))))

    (define (read-value-type code)
      (case (peek-byte code)
        ((127 126 125 124 120 119)
         (cdr (assv (read-byte code) '((127 . i32) (126 . i64) (125 . f32)
                                       (124 . f64) (120 . i8) (119 . i16)))))
        ((99) (read-byte code) (list 'ref 'null (read-heap-type code)))
        ((100) (read-byte code) (list 'ref (read-heap-type code)))
        (else (list 'ref 'null (read-heap-type code)))))

    (define (read-mutable-type code)
      (let* ((type (read-value-type code)) (mutable (read-byte code)))
        (case mutable ((0) type) ((1) (list 'mut type))
              (else (error "invalid Wasm mutability" mutable)))))

    (define (read-composite-type code)
      (case (read-byte code)
        ((96) (let* ((params (read-items read-value-type code))
                     (results (read-items read-value-type code)))
                (list 'func params results)))
        ((95) (cons 'struct (read-items read-mutable-type code)))
        ((94) (list 'array (read-mutable-type code)))
        (else (error "unsupported native Wasm composite type"))))

    (define (read-subtype code)
      (case (peek-byte code)
        ((79) (read-byte code)
         (unless (null? (read-items read-index code)) (error "native Wasm subtyping is unsupported")))
        ((80) (error "native nonfinal Wasm types are unsupported")))
      (read-composite-type code))

    (define (read-type-group code)
      (if (= (peek-byte code) 78)
          (begin (read-byte code) (read-items read-subtype code))
          (list (read-subtype code))))

    (define (read-block-type code)
      (case (peek-byte code)
        ((64) (read-byte code) 'void)
        ((127 126 125 124 99 100 110 111 112 113 115 109 108 107 106)
         (read-value-type code))
        (else (read-index code))))

    (define (read-limits code maximum)
      (let* ((flags (read-byte code)) (minimum (read-index code)))
        (case flags
          ((0) (list minimum maximum))
          ((1) (list minimum (read-index code)))
          (else (error "native requires unshared wasm32 limits" flags)))))

    ;; ---- Instruction decoding ----

    ;; Numeric entries carry their machine type, operation and operand count.
    ;; The lowering pass never parses an opcode name back out of a string.
    (define numeric-opcodes
      '#((numeric "i32" eqz 1) (numeric "i32" eq 2)
         (numeric "i32" ne 2) (numeric "i32" lt_s 2)
         (numeric "i32" lt_u 2) (numeric "i32" gt_s 2)
         (numeric "i32" gt_u 2) (numeric "i32" le_s 2)
         (numeric "i32" le_u 2) (numeric "i32" ge_s 2)
         (numeric "i32" ge_u 2) (numeric "i64" eqz 1)
         (numeric "i64" eq 2) (numeric "i64" ne 2)
         (numeric "i64" lt_s 2) (numeric "i64" lt_u 2)
         (numeric "i64" gt_s 2) (numeric "i64" gt_u 2)
         (numeric "i64" le_s 2) (numeric "i64" le_u 2)
         (numeric "i64" ge_s 2) (numeric "i64" ge_u 2)
         (numeric "f32" eq 2) (numeric "f32" ne 2)
         (numeric "f32" lt 2) (numeric "f32" gt 2)
         (numeric "f32" le 2) (numeric "f32" ge 2)
         (numeric "f64" eq 2) (numeric "f64" ne 2)
         (numeric "f64" lt 2) (numeric "f64" gt 2)
         (numeric "f64" le 2) (numeric "f64" ge 2)
         (numeric "i32" clz 1) (numeric "i32" ctz 1)
         (numeric "i32" popcnt 1) (numeric "i32" add 2)
         (numeric "i32" sub 2) (numeric "i32" mul 2)
         (numeric "i32" div_s 2) (numeric "i32" div_u 2)
         (numeric "i32" rem_s 2) (numeric "i32" rem_u 2)
         (numeric "i32" and 2) (numeric "i32" or 2)
         (numeric "i32" xor 2) (numeric "i32" shl 2)
         (numeric "i32" shr_s 2) (numeric "i32" shr_u 2)
         (numeric "i32" rotl 2) (numeric "i32" rotr 2)
         (numeric "i64" clz 1) (numeric "i64" ctz 1)
         (numeric "i64" popcnt 1) (numeric "i64" add 2)
         (numeric "i64" sub 2) (numeric "i64" mul 2)
         (numeric "i64" div_s 2) (numeric "i64" div_u 2)
         (numeric "i64" rem_s 2) (numeric "i64" rem_u 2)
         (numeric "i64" and 2) (numeric "i64" or 2)
         (numeric "i64" xor 2) (numeric "i64" shl 2)
         (numeric "i64" shr_s 2) (numeric "i64" shr_u 2)
         (numeric "i64" rotl 2) (numeric "i64" rotr 2)
         (numeric "f32" abs 1) (numeric "f32" neg 1)
         (numeric "f32" ceil 1) (numeric "f32" floor 1)
         (numeric "f32" trunc 1) (numeric "f32" nearest 1)
         (numeric "f32" sqrt 1) (numeric "f32" add 2)
         (numeric "f32" sub 2) (numeric "f32" mul 2)
         (numeric "f32" div 2) #f
         #f (numeric "f32" copysign 2)
         (numeric "f64" abs 1) (numeric "f64" neg 1)
         (numeric "f64" ceil 1) (numeric "f64" floor 1)
         (numeric "f64" trunc 1) (numeric "f64" nearest 1)
         (numeric "f64" sqrt 1) (numeric "f64" add 2)
         (numeric "f64" sub 2) (numeric "f64" mul 2)
         (numeric "f64" div 2) #f
         #f (numeric "f64" copysign 2)
         (numeric "i32" wrap_i64 1) (numeric "i32" trunc_f32_s 1)
         (numeric "i32" trunc_f32_u 1) (numeric "i32" trunc_f64_s 1)
         (numeric "i32" trunc_f64_u 1) (numeric "i64" extend_i32_s 1)
         (numeric "i64" extend_i32_u 1) (numeric "i64" trunc_f32_s 1)
         (numeric "i64" trunc_f32_u 1) (numeric "i64" trunc_f64_s 1)
         (numeric "i64" trunc_f64_u 1) (numeric "f32" convert_i32_s 1)
         (numeric "f32" convert_i32_u 1) (numeric "f32" convert_i64_s 1)
         (numeric "f32" convert_i64_u 1) (numeric "f32" demote_f64 1)
         (numeric "f64" convert_i32_s 1) (numeric "f64" convert_i32_u 1)
         (numeric "f64" convert_i64_s 1) (numeric "f64" convert_i64_u 1)
         (numeric "f64" promote_f32 1) (numeric "i32" reinterpret_f32 1)
         (numeric "i64" reinterpret_f64 1) (numeric "f32" reinterpret_i32 1)
         (numeric "f64" reinterpret_i64 1) (numeric "i32" extend8_s 1)
         (numeric "i32" extend16_s 1) (numeric "i64" extend8_s 1)
         (numeric "i64" extend16_s 1) (numeric "i64" extend32_s 1)))

    (define memory-opcodes
      '#(("i32" "i32" 4 #f #f) ("i64" "i64" 8 #f #f)
         ("float" "float" 4 #f #f) ("double" "double" 8 #f #f)
         ("i32" "i8" 1 #t #f) ("i32" "i8" 1 #f #f)
         ("i32" "i16" 2 #t #f) ("i32" "i16" 2 #f #f)
         ("i64" "i8" 1 #t #f) ("i64" "i8" 1 #f #f)
         ("i64" "i16" 2 #t #f) ("i64" "i16" 2 #f #f)
         ("i64" "i32" 4 #t #f) ("i64" "i32" 4 #f #f)
         ("i32" "i32" 4 #f #t) ("i64" "i64" 8 #f #t)
         ("float" "float" 4 #f #t) ("double" "double" 8 #f #t)
         ("i32" "i8" 1 #f #t) ("i32" "i16" 2 #f #t)
         ("i64" "i8" 1 #f #t) ("i64" "i16" 2 #f #t) ("i64" "i32" 4 #f #t)))

    (define (read-memory-instruction code opcode)
      (let* ((alignment (read-index code)) (offset (read-index code)))
        (when (>= alignment 64) (error "native multiple memories are unsupported"))
        (list 'memory (vector-ref memory-opcodes (- opcode 40)) offset)))

    (define (indexed-op name code count)
      (let loop ((left count) (arguments '()))
        (if (= left 0) (cons name (reverse arguments))
            (let ((index (read-index code))) (loop (- left 1) (cons index arguments))))))

    (define (read-gc-instruction code)
      (let ((opcode (read-index code)))
        (cond ((<= 0 opcode 17)
               (let ((entry (vector-ref gc-opcodes opcode)))
                 (unless entry (error "unsupported native Wasm GC instruction" opcode))
                 (indexed-op (car entry) code (cadr entry))))
              ((<= 20 opcode 23)
               (let ((type (read-heap-type code)))
                 (list (if (< opcode 22) 'ref.test 'ref.cast)
                       (if (not (zero? (modulo opcode 2))) (list 'ref 'null type) (list 'ref type)))))
              ((<= 28 opcode 30) (list (vector-ref '#(ref.i31 i31.get_s i31.get_u) (- opcode 28))))
              (else (error "unsupported native Wasm GC instruction" opcode)))))

    (define gc-opcodes
      '#((struct.new 1) (struct.new_default 1) (struct.get 2) (struct.get_s 2)
         (struct.get_u 2) (struct.set 2) (array.new 1) (array.new_default 1)
         (array.new_fixed 2) #f #f (array.get 1) (array.get_s 1) (array.get_u 1)
         (array.set 1) (array.len 0) #f (array.copy 2)))

    (define (read-bulk-instruction code)
      (case (read-index code)
        ((10) (unless (and (= (read-index code) 0) (= (read-index code) 0))
                (error "native multiple memories are unsupported")) '(memory.copy))
        ((11) (unless (= (read-index code) 0) (error "native multiple memories are unsupported"))
         '(memory.fill))
        ((15) (indexed-op 'table.grow code 1))
        ((16) (indexed-op 'table.size code 1))
        (else (error "unsupported native Wasm bulk instruction"))))

    (define (read-wasm-instruction code)
      (let ((opcode (read-byte code)))
        (cond ((<= 69 opcode 196)
               (or (vector-ref numeric-opcodes (- opcode 69))
                   (error "unsupported native Wasm numeric opcode" opcode)))
              ((<= 40 opcode 62) (read-memory-instruction code opcode))
              (else
               (case opcode
                 ((32 33 34 35 36 37 38)
                  (indexed-op (vector-ref '#(local.get local.set local.tee global.get global.set table.get table.set)
                                          (- opcode 32)) code 1))
                 ((65) (list 'i32.const (read-leb code #t 32)))
                 ((66) (list 'i64.const (read-leb code #t 64)))
                 ((2 3 4) (list (vector-ref '#(block loop if) (- opcode 2)) (read-block-type code)))
                 ((5) '(else))
                 ((11) '(end))
                 ((0) '(unreachable))
                 ((1) '(nop))
                 ((12) (indexed-op 'br code 1))
                 ((13) (indexed-op 'br_if code 1))
                 ((14) (let* ((targets (read-items read-index code)) (default (read-index code)))
                         (cons 'br_table (cons default targets))))
                 ((15) '(return))
                 ((16 18) (indexed-op (if (= opcode 16) 'call 'return_call) code 1))
                 ((17 19) (let* ((type (read-index code)) (table (read-index code)))
                            (list (if (= opcode 17) 'call_indirect 'return_call_indirect) table type)))
                 ((20 21) (indexed-op (if (= opcode 20) 'call_ref 'return_call_ref) code 1))
                 ((26) '(drop))
                 ((27) '(select))
                 ((28) (read-items read-value-type code) '(select))
                 ((63 64) (unless (= (read-index code) 0) (error "native multiple memories are unsupported"))
                  (list (if (= opcode 63) 'memory.size 'memory.grow)))
                 ((67) (list 'f32.const (read-word code 4)))
                 ((68) (list 'f64.const (read-word code 8)))
                 ((208) (list 'ref.null (read-heap-type code)))
                 ((209) '(ref.is_null))
                 ((210) (indexed-op 'ref.func code 1))
                 ((211) '(ref.eq))
                 ((212) '(ref.as_non_null))
                 ((251) (read-gc-instruction code))
                 ((252) (read-bulk-instruction code))
                 (else (error "unsupported native Wasm opcode" opcode (code-position code))))))))

    (define (read-expression code)
      (let loop ((instructions '()))
        (let ((instruction (read-wasm-instruction code)))
          (if (eq? (car instruction) 'end) (reverse instructions)
              (loop (cons instruction instructions))))))

    ;; ---- Module sections ----

    (define (read-import code)
      (let* ((module (read-name code)) (name (read-name code)) (kind (read-byte code)))
        (unless (= kind 0) (error "native nonfunction imports are unsupported" module name))
        (list module name (read-index code))))

    (define (read-table code)
      (let* ((type (read-value-type code)) (limits (read-limits code 4294967295)))
        (unless (and (pair? type) (eq? (cadr type) 'null))
          (error "native requires nullable tables without initializers"))
        (append limits (list type))))

    (define (read-global code)
      (let ((type (read-mutable-type code))) (list type (read-expression code))))

    (define (read-export code)
      (let* ((name (read-name code)) (kind (read-byte code)) (index (read-index code)))
        (unless (< kind 4) (error "unsupported native export kind" kind))
        (list 'export name (list (vector-ref '#(func table memory global) kind) index))))

    (define (read-local-group code)
      (let* ((count (read-index code)) (type (read-value-type code))) (make-list count type)))

    (define (read-body code)
      (let* ((body (take-code code (read-index code)))
             (locals (apply append (read-items read-local-group body))))
        (list locals body)))

    (define (read-data code)
      (let* ((mode (read-index code))
             (memory (case mode ((0) 0) ((2) (read-index code))
                           (else (error "native passive data segments are unsupported"))))
             (offset (read-expression code)))
        (unless (= memory 0) (error "native multiple memories are unsupported"))
        (list offset (read-bytes code))))

    (define (read-element code)
      (let ((mode (read-index code)))
        (case mode
          ((3) (read-byte code) (read-items read-index code) '())
          ((7) (read-value-type code) (read-items read-expression code) '())
          (else
           (let* ((table (case mode ((0) 0) ((2) (read-index code))
                               (else (error "unsupported native element segment" mode))))
                  (offset (read-expression code)))
             (when (= mode 2)
               (unless (= (read-byte code) 0) (error "unsupported native element type")))
             (list (list 'elem table offset (read-items read-index code))))))))

    (define (read-section id code)
      (case id
        ((1) (apply append (read-items read-type-group code)))
        ((2) (read-items read-import code)) ((3) (read-items read-index code))
        ((4) (read-items read-table code))
        ((5) (read-items (lambda (code) (read-limits code 65536)) code))
        ((6) (read-items read-global code)) ((7) (read-items read-export code))
        ((8) (list (list 'start (read-index code)))) ((9) (apply append (read-items read-element code)))
        ((10) (read-items read-body code)) ((11) (read-items read-data code))
        ((12) (read-index code) '())
        (else (error "unsupported native Wasm section" id))))

    (define (indexed-items tag entries start)
      (let loop ((entries entries) (index start) (result '()))
        (if (null? entries) (reverse result)
            (loop (cdr entries) (+ index 1)
                  (cons (cons tag (cons index (car entries))) result)))))

    (define (import-declarations imports)
      (let loop ((imports imports) (index 0) (declarations '()))
        (if (null? imports) (reverse declarations)
            (let ((entry (car imports)))
              (loop (cdr imports) (+ index 1)
                    (cons (list 'import (car entry) (cadr entry) (list 'func index (caddr entry)))
                          declarations))))))

    (define (module-declarations sections)
      (let* ((imports (vector-ref sections 2)) (signatures (vector-ref sections 3))
             (bodies (vector-ref sections 10)))
        (unless (= (length signatures) (length bodies)) (error "Wasm function/code count mismatch"))
        (append
         (indexed-items 'type (map list (vector-ref sections 1)) 0)
         (import-declarations imports)
         (indexed-items 'func (map cons signatures bodies) (length imports))
         (indexed-items 'table (vector-ref sections 4) 0)
         (indexed-items 'memory (vector-ref sections 5) 0)
         (indexed-items 'global (vector-ref sections 6) 0)
         (vector-ref sections 7) (vector-ref sections 8) (vector-ref sections 9)
         (indexed-items 'data (vector-ref sections 11) 0))))

    (define (read-wasm bytes)
      (let ((code (make-code bytes 0 (bytevector-length bytes))) (sections (make-vector 13 '())))
        (unless (= (read-word code 8) 6131245312)
          (error "invalid Wasm header"))
        (let loop ()
          (unless (wasm-code-end? code)
            (let* ((id (read-byte code)) (section (take-code code (read-index code))))
              (unless (= id 0)
                (let ((entries (read-section id section)))
                  (unless (wasm-code-end? section) (error "Wasm section size mismatch" id))
                  (vector-set! sections id entries)))
              (loop))))
        (module-declarations sections)))

    (define (read-wasm-file path)
      (call-with-port
          (open-binary-input-file path)
        (lambda (port)
          (let loop ((chunks '()))
            (let ((bytes (read-bytevector 65536 port)))
              (if (eof-object? bytes) (read-wasm (apply bytevector-append (reverse chunks)))
                  (loop (cons bytes chunks)))))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm-binary)
    (import (snail-scheme test-utils))
    (begin
      (define (input-code . bytes)
        (make-code (apply bytevector bytes) 0 (length bytes)))

      (define (test-binary-integers)
        (expect (read-leb (input-code 229 142 38) #f 32) 624485)
        (expect (read-leb (input-code 155 241 89) #t 32) -624485)
        (expect (read-index (input-code 255 255 255 255 15)) (- (expt 2 32) 1))
        (expect (read-leb (input-code 128 128 128 128 120) #t 32) (- (expt 2 31)))
        (expect (read-leb (input-code 128 128 128 128 128 128 128 128 128 127) #t 64)
                (- (expt 2 63)))
        (expect (read-leb (input-code 255 255 255 255 255 255 255 255 255 0) #t 64)
                (string->number "9223372036854775807"))
        (expect (read-leb (input-code 255 255 255 255 255 255 255 255 255 127) #t 64) -1)
        (expect (read-word (input-code 0 0 0 0 0 0 0 128) 8)
                (string->number "-9223372036854775808"))
        (expect (read-word (input-code 255 255 255 255 255 255 255 255) 8) -1)
        (for-each
         (lambda (last)
           (expect (guard (error (else #t))
                     (read-leb (input-code 128 128 128 128 128 128 128 128 128 last) #t 64) #f) #t))
         '(1 64 126 128))
        (expect (read-index (input-code 128 0)) 0)
        (for-each
         (lambda (bytes)
           (expect (guard (error (else #t)) (read-index (apply input-code bytes)) #f) #t))
         '((128) (255 255 255 255 16) (128 128 128 128 128 0))))

      (define (test-binary-boundaries)
        (expect (read-wasm (bytevector 0 97 115 109 1 0 0 0)) '())
        (expect (read-wasm-instruction (input-code 65 127)) '(i32.const -1))
        (expect (read-block-type (input-code 113)) '(ref null none))
        (let* ((parent (input-code 11 1)) (child (take-code parent 1))
               (copy (wasm-code-copy child)))
          (expect (read-wasm-instruction child) '(end))
          (expect (read-wasm-instruction copy) '(end))
          (expect (read-wasm-instruction parent) '(nop))
          (expect (guard (error (else #t)) (read-byte child) #f) #t))
        (for-each
         (lambda (bytes)
           (expect (guard (error (else #t)) (read-wasm (apply bytevector bytes)) #f) #t))
         '((0 97) (0 97 115 109 1 0 0 0 1 2 0)
           (0 97 115 109 1 0 0 0 1 2 0 0)
           (0 97 115 109 1 0 0 0 3 2 1 0))))

      (define (test-binary-rejections)
        (for-each
         (lambda (instruction)
           (expect (guard (error (else #t))
                     (read-wasm-instruction (apply input-code instruction)) #f) #t))
         '((253) (251 9) (252 8) (63 1) (150)))
        (expect (guard (error (else #t)) (read-subtype (input-code 80 0 95 0)) #f) #t)
        (expect (guard (error (else #t)) (read-value-type (input-code 111)) #f) #t)
        (expect (guard (error (else #t)) (read-limits (input-code 4 1) 65536) #f) #t))

      (define (test-wasm-binary)
        (run-test test-binary-integers)
        (run-test test-binary-boundaries)
        (run-test test-binary-rejections))))))
