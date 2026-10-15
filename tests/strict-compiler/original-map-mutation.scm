;; R7RS leaves map callback order unspecified. Record the original Chez behavior
;; as a diagnostic control; do not use its observed order as a language rule.
(let* ((input (list 1 2 3)) (old-tail (cdr input)) (replacement (list 4 5)) (trace 0)
       (output (map (lambda (value)
                      (set! trace (+ (* 10 trace) value))
                      (when (= value 1) (set-cdr! input replacement))
                      value)
                    input)))
  (write (list trace input output old-tail (eq? input output) (eq? replacement (cdr output))))
  (newline))
