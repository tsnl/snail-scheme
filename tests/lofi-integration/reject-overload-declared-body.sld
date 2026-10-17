(import
 (lofi base))

(def bridge (-> I64 I64)
     (lambda (value) (i64-add (countdown value) #t)))
(define-overload countdown (-> I64 I64)
  (lambda (value) (if (= value (ann 0 I64)) (ann 42 I64) (bridge (- value (ann 1 I64))))))
42
