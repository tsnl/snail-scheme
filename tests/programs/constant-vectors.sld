;; Constant vectors: tables of scalar literals built once and shared, read
;; and copied as vectors are, and never written. A table is data of any
;; size; a float table is a table of the floats' bits.
(import
 (snail core base)
 (snail core io))

(define (bytes) (→ (ConstantVector U8)) (constant-vector U8 (0 1 127 255)))

(define (words) (→ (ConstantVector I32)) (constant-vector I32 (-2147483648 -1 0 2147483647)))

(define (longs) (→ (ConstantVector I64))
  (constant-vector I64 (-9223372036854775808 -4294967297 -1 4294967296 9223372036854775807)))

(define (floats) (→ (ConstantVector I64))
  (constant-vector I64 (4602678819172646912 -4611123068473966592 4613937818241073152)))

(define (flags) (→ (ConstantVector Bool)) (constant-vector Bool (#t #f #t)))

(define (letters) (→ (ConstantVector Char)) (constant-vector Char (#\a #\λ #\z)))

(define (all (table (ConstantVector A)) (text (Fn A → String))) (→ String) (∀ (A))
  (string-join (map (lambda (index) (text (constant-vector-ref table index)))
                    (iota (constant-vector-length table)))
               " "))

(define (main) (→ Unit) (! output-port mut)
  (write-line (all (bytes) (lambda (byte) (show (u8->i32 byte)))))
  (write-line (all (words) show))
  (write-line (all (longs) show))
  (write-line (all (floats) (lambda (bits) (show (bits->f64 bits)))))
  (write-line (all (flags) (lambda (flag) (if flag "yes" "no"))))
  (write-line (all (letters) (lambda (letter) (list->string (list letter)))))
  (let ((copy (constant-vector->vector (bytes))))
    (vector-set! copy 0 (i32->u8 42))
    (write-line (string-append (show (u8->i32 (vector-ref copy 0)))
                               " "
                               (show (u8->i32 (constant-vector-ref (bytes) 0)))))))
