;; Base64 data URLs for in-memory images and other linked byte resources.
(define-library (snail shell base64)
  (export data-url)
  (import
   (snail core base))
  (begin
    (define (octet (b Bytes) (i I64)) (→ I32)
      (if (< i (array-length b)) (u8->i32 (array-ref b i)) 0))
    (define (letter (bytes Bytes) (i I64)) (→ Char)
      (let* ((base (* 3 (quotient i 4))) (slot (modulo i 4)))
        (if (> (+ base slot) (array-length bytes)) #\=
            (let* ((bits (i32-or (i32-shift-left (octet bytes base) 16)
                                 (i32-or (i32-shift-left (octet bytes (+ base 1)) 8)
                                         (octet bytes (+ base 2)))))
                   (digit (i32-and 63 (i32-shift-right/logical bits (i64->i32 (- 18 (* 6 slot)))))))
              (string-ref "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
                          (i32->i64 digit))))))
    (define (data-url (mime String) (bytes Bytes)) (→ String)
      (string-append "data:" mime ";base64,"
                     (string-generate (* 4 (quotient (+ (array-length bytes) 2) 3))
                                      (lambda (i) (letter bytes i)))))))
