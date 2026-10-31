(import
 (snail core base)
 (snail core io)
 (snail shell slot))

;; The runtime's slot is the one shared place a linear value rests between
;; frames: a queue of work items in a global, taken out and put back around
;; each change. A cell could not hold it, since a cell holds no linear
;; value.
(type Work (FnOnce Unit ! console))

(: queue (UnsafeSlot (List Work)))
(define queue (unsafe-slot (Nil)))

(: enqueue! (-> Work Unit ! mut))
(define (enqueue! work)
  (put! queue (append (take! queue) (list work))))

(: run-all! (-> Unit ! mut console))
(define (run-all!)
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
