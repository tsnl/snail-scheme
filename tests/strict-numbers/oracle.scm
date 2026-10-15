(import (snail strict) (snail integer) (snail rational))

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

;; Fixture fractions are decimal and intentionally independent of the reader.
(define (rational-input text)
  (let loop ((at 0))
    (if (= at (string-length text)) (rational-from-integer (integer-from-string text))
        (if (char=? (string-ref text at) #\/)
            (make-rational (integer-from-string (substring text 0 at))
                           (integer-from-string (substring text (+ at 1) (string-length text))))
            (loop (+ at 1))))))
(define (rational-operation operation left right)
  (if (= operation 8) (rational->string (+ left right))
      (if (= operation 9) (rational->string (- left right))
          (if (= operation 10) (rational->string (* left right))
              (if (= operation 11) (rational->string (/ left right))
                  (integer->string
                   (if (= operation 12) (integer-from-i64 (rational-compare left right))
                       (if (= operation 13) (truncate left) (rational-floor left)))))))))
(define (rational-probe operation value)
  (if (= operation 15) (rational->f64 (rational-from-f64 value))
      (begin
        (emit (if (= operation 14) (rational->string (rational-from-f64 value))
                  (rational-operation operation (rational-input (argument (ann 0 I32)))
                                      (rational-input (argument (ann 1 I32))))))
        0.0)))
(: probe (-> I64 F64 F64))
(define (probe operation value)
  (if (>= operation 8) (rational-probe operation value)
      (let ((a (integer-from-string (argument (ann 0 I32))))
            (b (integer-from-string (argument (ann 1 I32)))))
        (if (= operation 0) (integer-ratio->f64 a b)
            (if (= operation 5) (integer->f64 a)
                (if (= operation 7) (begin (emit (rational->string (make-rational a b))) 0.0)
                    (begin
                      (emit (integer->string
                             (if (= operation 1) (integer-from-f64 value)
                                 (if (= operation 2) (integer-truncate-f64 value)
                                     (if (= operation 3) (integer-floor-quotient a b)
                                         (if (= operation 4) (integer-modulo a b)
                                             (integer-gcd a b)))))))
                      0.0)))))))
(unit)
