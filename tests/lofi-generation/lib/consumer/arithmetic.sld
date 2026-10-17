(define-library (consumer arithmetic)
  (import
   (only (lofi primitive) i32-add))
  (export add)
  (begin
    (define-extern tick "tests.consumer" "tick" (-> I32))
    (let initialized (tick))
    (def add (-> I32 I32 I32) (lambda (left right) (i32-add left right)))))
