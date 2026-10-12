(import (chezscheme))

;; ---- Representative source expressions ----

;; These are small examples, not the full cat benchmark or its hot binary.
(define examples
  '((copy-characters
     . (lambda (input output)
         (let loop ((character (read-char input)))
           (unless (eof-object? character)
             (write-char character output)
             (loop (read-char input))))))
    (invoke-callback . (lambda (callback value) (callback value)))))

;; ---- Safe compilation and loaded code extraction ----

;; Chez 10.4.1 s/cmacros.ss:1551 defines the code object as eight 8-byte
;; header fields followed by octets. Typed-object pointers have tag 7 and
;; point one byte before the header: length is at +9, code bytes at +65.
;; Copying uses the current Scheme object reference and briefly disables
;; interrupts so a GC cannot relocate linked targets partway through the copy.
(define (code-bytes procedure)
  (let* ((code (((inspect/object procedure) 'code) 'value))
         (length (#%$object-ref 'iptr code 9))
         (bytes (make-bytevector length)))
    (unless (and (eq? (machine-type) 'ta6le) (= (logand (#%$object-ref 'iptr code 1) #xff) 190)
                 (< 0 length 65536))
      (error 'code-bytes "unexpected Chez code layout" length))
    (with-interrupts-disabled
      (do ((index 0 (+ index 1))) ((= index length))
        (bytevector-u8-set! bytes index (#%$object-ref 'unsigned-8 code (+ 65 index)))))
    bytes))

(define (capture example)
  (let* ((name (symbol->string (car example)))
         (prefix (string-append "audit/chez/" name))
         (procedure
          (call-with-port (open-output-file (string-append prefix ".compiler.asm") 'replace)
            (lambda (port)
              (parameterize ((optimize-level 2) (debug-level 1)
                             (enable-unsafe-application #f)
                             (enable-unsafe-variable-reference #f)
                             (#%$assembly-output port))
                (compile `(let ((,(car example) ,(cdr example))) ,(car example)))))))
         (bytes (code-bytes procedure)))
    (call-with-port (open-file-output-port (string-append prefix ".bin") (file-options no-fail))
      (lambda (port) (put-bytevector port bytes)))
    (printf "~s: ~s code bytes~%" (car example) (bytevector-length bytes))
    procedure))

;; ---- Small correctness checks ----

(printf "~a; machine ~s; safe optimize-level 2~%" (scheme-version) (machine-type))
(define procedures (map capture examples))
(let ((input (open-input-string "ASCII and \x3bb;\n")) (output (open-output-string)))
  ((car procedures) input output)
  (unless (string=? (get-output-string output) "ASCII and \x3bb;\n")
    (error 'copy-characters "unexpected copied text")))
(unless (= ((cadr procedures) (lambda (value) (+ value 1)) 41) 42)
  (error 'invoke-callback "unexpected callback result"))
(unless (guard (condition ((assertion-violation? condition) #t) (else #f))
          ((cadr procedures) 42 41) #f)
  (error 'invoke-callback "nonprocedure was not rejected"))
(display "representative checks passed\n")
