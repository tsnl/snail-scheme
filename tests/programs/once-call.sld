(import
 (snail-core base)
 (snail-core io))

;; A `Once` is called like the procedure it holds, and the call consumes it.
(let ((greet (once (lambda () (write-line "called once")))))
  (greet))

;; A `Once` may hold any procedure, not only a thunk; a resumption is one.
(: apply-once (-> (Once (-> I64 I64)) I64 I64))
(define (apply-once procedure value)
  (procedure value))

(write-line "done")
