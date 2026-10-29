(import
 (snail core base)
 (snail core io))

;; A `FnOnce` is called like the procedure it holds, and the call consumes it.
(let ((greet (once (lambda () (write-line "called once")))))
  (greet))

;; `once` makes one from any thunk, and calling it answers what the thunk
;; does.
(let ((answer (once (lambda () 42))))
  (write-line (show (answer))))

;; A `FnOnce` may hold any procedure, not only a thunk; a resumption is one.
(: apply-once (-> (FnOnce I64 I64) I64 I64))
(define (apply-once procedure value)
  (procedure value))

(write-line "done")
