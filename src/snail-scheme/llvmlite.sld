(define-library (snail-scheme llvmlite)
  (export llvm-name llvm-quoted llvm-hex llvm-join write-llvm)
  (import (scheme base) (scheme char) (only (scheme write) display write-simple))
  (begin

    ;; ---- Immutable operands and serialization ----

    ;; Values in the lowering pass are (type . operand). Operands keep integer
    ;; IDs, constants and references intact until this writer sees them. Lists
    ;; concatenate fragments without building intermediate strings; a function
    ;; can be written independently, without retaining a second module AST.

    (define-record-type <llvm-name>
      (llvm-name prefix index) llvm-name?
      (prefix name-prefix) (index name-index))

    (define-record-type <llvm-quoted>
      (llvm-quoted bytes) llvm-quoted?
      (bytes quoted-bytes))

    (define-record-type <llvm-hex>
      (llvm-hex bits) llvm-hex?
      (bits hex-bits))

    (define (llvm-join items separator)
      (if (null? items) '()
          (cons (car items)
                (map (lambda (item) (list separator item)) (cdr items)))))

    (define escaped-bytes
      (list->vector
       (let loop ((byte 0) (result '()))
         (if (= byte 256) (reverse result)
             (let ((digits (string-upcase (number->string byte 16))))
               (loop (+ byte 1)
                     (cons (if (and (<= 32 byte 126) (not (memv byte '(34 92))))
                               (string (integer->char byte))
                               (string-append "\\" (if (< byte 16) "0" "") digits))
                           result)))))))

    (define (write-quoted bytes port)
      (let ((bytes (if (string? bytes) (string->utf8 bytes) bytes)))
        (write-char #\" port)
        (let loop ((index 0))
          (when (< index (bytevector-length bytes))
            (write-string (vector-ref escaped-bytes (bytevector-u8-ref bytes index)) port)
            (loop (+ index 1))))
        (write-char #\" port)))

    (define (write-hex bits port)
      (let ((digits (string-upcase (number->string bits 16))))
        (write-string "0x" port)
        (write-string (make-string (- 16 (string-length digits)) #\0) port)
        (write-string digits port)))

    (define (write-llvm value port)
      (cond ((string? value) (display value port))
            ((number? value) (write-simple value port))
            ((pair? value) (write-llvm (car value) port) (write-llvm (cdr value) port))
            ((null? value) #f)
            ((llvm-name? value)
             (display (name-prefix value) port)
             (write-simple (name-index value) port))
            ((llvm-quoted? value) (write-quoted (quoted-bytes value) port))
            ((llvm-hex? value) (write-hex (hex-bits value) port))
            ((symbol? value) (write-string (symbol->string value) port))
            (else (error "unsupported LLVM fragment" value)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-llvmlite)
    (import (snail-scheme test-utils))
    (begin
      (define (llvm-string value)
        (let ((port (open-output-string)))
          (write-llvm value port)
          (get-output-string port)))

      (define (test-llvmlite)
        (expect (llvm-string (list "add i32 " (llvm-name "%v" 12) ", " -3))
                "add i32 %v12, -3")
        (expect (llvm-string (llvm-quoted (bytevector 65 0 255 34 92)))
                "\"A\\00\\FF\\22\\5C\"")
        (expect (llvm-string (llvm-hex (expt 2 63))) "0x8000000000000000")
        (expect (llvm-string (llvm-join '(1 2 3) ", ")) "1, 2, 3"))))))
