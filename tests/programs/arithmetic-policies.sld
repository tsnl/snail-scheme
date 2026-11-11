(import
 (snail core base)
 (snail core io)
 (snail shell integer)
 (snail shell rational)
 (snail shell arithmetic)
 (snail shell arithmetic dynamic))

(define big (→ Integer) (integer-from-i64 9223372036854775807))
(define one (→ Integer) (integer-from-i64 1))
(define half (→ Rational) (make-rational one (integer-from-i64 2)))

(with-instances (arithmetic-base)
                (write-line (show (add big one)))
                (write-line (rational->string (divide one (integer-from-i64 2))))
                (write-line (rational->string (add one half)))
                (write-line (rational->string (subtract half one)))
                (write-line (rational->string (multiply half (integer-from-i64 3)))))

(with-instances (arithmetic-base inexact-promotion)
                (display (add one 2.5))
                (newline)
                (display (subtract 2.5 one))
                (newline)
                (display (divide one 2.0))
                (newline))

(define erased (→ Any) one)
(with-instances (dynamic-arithmetic)
                (handle dyn-cast
                    ((conversion-failed (lambda (_) (write-line "unsupported pair"))))
                  ;; This one-sided adapter retains its concrete F64 result.
                  (display (add erased 2.5))
                  (newline)
                  (display (subtract 2.5 erased))
                  (newline)
                  ;; Both erased inputs return Any because the domain has several outputs.
                  (write-line
                   (rational->string (ann (divide erased (ann (integer-from-i64 2) Any)) Rational)))
                  (add erased (ann #t Any))
                  (unit)))
