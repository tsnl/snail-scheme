(import
 (snail core base)
 (snail core io)
 (snail shell slot))

;; The runtime's slot is the one shared place a linear value rests between
;; frames: a queue of work items in a global, taken out and put back around
;; each change. A cell could not hold it, since a cell holds no linear
;; value.
(type Work (dyn (FnOnce → Unit ! output-port)))

(define queue (→ (UnsafeSlot (List Work))) (unsafe-slot (Nil)))

(define (enqueue! (work Work)) (→ Unit) (! mut)
  (put! queue (append (take! queue) (list work))))

(define (run-all!) (→ Unit) (! mut output-port)
  (match (take! queue)
    ((Nil) (put! queue (Nil)))
    ((Cons work rest)
     (put! queue rest)
     (call-once work)
     (run-all!))))

(enqueue! (once (lambda () (write-line "one"))))
(enqueue! (once (lambda () (write-line "two"))))
(run-all!)
(run-all!)
(write-line "done")
