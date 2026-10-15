(import (snail strict) (snail integer))

;; ---- Scalar test transport leaves exact values in Scheme ----

(define-extern argument-length "oracle" "argument_length" (-> I32 I64))
(define-extern argument-character "oracle" "argument_character" (-> I32 I64 Char))
(define-extern emit-character "oracle" "emit_character" (-> Char Unit))
(define (argument index)
  (let* ((count (argument-length index)) (text (make-string count)))
    (let loop ((at 0))
      (if (= at count) text
          (begin (string-set! text at (argument-character index at)) (loop (+ at 1)))))))
(define (emit text)
  (let loop ((at 0))
    (unless (= at (string-length text))
      (emit-character (string-ref text at)) (loop (+ at 1)))))

;; ---- Public conversion and rounding contracts ----

(: probe (-> I64 F64 F64))
(define (probe operation value)
  (let ((a (integer-from-string (argument (ann 0 I32))))
        (b (integer-from-string (argument (ann 1 I32)))))
    (if (= operation 0) (integer-ratio->f64 a b)
        (if (= operation 5) (integer->f64 a)
            (begin
              (emit (integer->string
                     (if (= operation 1) (integer-from-f64 value)
                         (if (= operation 2) (integer-truncate-f64 value)
                             (if (= operation 3) (integer-floor-quotient a b)
                                 (if (= operation 4) (integer-modulo a b)
                                     (integer-gcd a b)))))))
              0.0)))))
(unit)
