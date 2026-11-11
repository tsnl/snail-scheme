(import
 (snail core base)
 (snail shell task)
 (snail shell future)
 (snail shell ui)
 (snail shell dom)
 (snail shell dom memory))

(: update (impl (Fn I64 (Option I64) -> I64 ! tasks)))
(define (update model message)
  (yield)
  model)

(: view (impl (Fn (Borrow I64) -> (Html I64))))
(define (view model)
  (Text (show (borrow-copy model))))

(: window (impl (Fn (Borrow I64) -> (List (Attribute I64)))))
(define (window model)
  (Nil))

(drop (with-memory-dom (Nil)
                       (lambda ()
                         (run-reactor 0 (list 1) update view window
                                      (lambda (model) (unit))
                                      (lambda (saved) (unit))
                                      (lambda (saved) (unit))))))
