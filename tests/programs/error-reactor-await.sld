(import
 (snail core base)
 (snail shell task)
 (snail shell future)
 (snail shell ui)
 (snail shell dom)
 (snail shell dom memory))

(define (update (model I64) (message (Option I64))) (→ I64) (! tasks)
  (yield)
  model)

(define (view (model (Borrow I64))) (→ (Html I64))
  (Text (show (borrow-copy model))))

(define (window (model (Borrow I64))) (→ (List (Attribute I64)))
  (Nil))

(define main
  (lambda ()
    (drop (with-memory-dom (Nil)
                           (lambda ()
                             (run-reactor 0 (list 1) update view window
                                          (lambda (model) (unit))
                                          (lambda (saved) (unit))
                                          (lambda (saved) (unit))))))
    (unit)))
