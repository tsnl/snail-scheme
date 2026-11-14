(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell ui)
 (snail shell dom)
 (snail shell dom memory))

;; Updating a shared model can suspend. Its owned arguments and the loop's
;; counted copy survive in their continuations without a source borrow.
(define (update (model I64) (message (Option I64))) (→ I64) (! tasks)
  (yield)
  (match message ((Some delta) (+ model delta)) ((None) model)))

(define (main) (→ Unit) (! mut host tasks output-port)
  (let ((result (with-memory-dom
                 (Nil)
                 (lambda ()
                   (run-reactor 0 (list 1)
                                (lambda (model message) (update model message))
                                (lambda (model) (Text (show model)))
                                (lambda (model) (Nil))
                                (lambda (model) (unit))
                                (lambda (saved) (unit))
                                (lambda (saved) (unit)))))))
    (write-line (document->html (● result second))))
  (unit))
