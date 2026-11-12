(import
 (snail core base)
 (snail core io))

(type Work (FnOnce → Unit ! output-port))

(struct Queue
  ((work (List Work))))

(define (enqueue! (queue (Rc Queue)) (work Work)) (→ Unit) (! mut output-port)
  (drop (replace! (● queue work) (append (replace! (● queue work) (Nil)) (list work)))))

(define (run-all! (queue (Rc Queue))) (→ Unit) (! mut output-port)
  (match (replace! (● queue work) (Nil))
    ((Nil) (unit))
    ((Cons work rest)
     (drop (replace! (● queue work) rest))
     (work)
     (run-all! queue))))

(define (main) (→ Unit) (! mut output-port)
  (let ((queue (rc (Queue (Nil)))))
    (enqueue! queue (once (lambda () (write-line "one"))))
    (enqueue! queue (once (lambda () (write-line "two"))))
    (run-all! queue)
    (run-all! queue)
    (write-line "done"))
  (unit))
