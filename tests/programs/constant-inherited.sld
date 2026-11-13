(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers))

(effect Log ((record-drop (Fn I64 → Unit))))

(struct Counter
  ((value I64)))

(struct Resource
  ((value I64)))

(instance (Drop (! Log) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Log)
    (match resource ((Resource value) (record-drop value)))))

(define (make-work) (→ (Pair Counter (Rc (FnOnce → Unit ! host))))
  (unsafe-total
   (lambda ()
     (let ((counter (Counter 0)) (resource (Resource 41)))
       (Pair counter
             (handle Log ((record-drop (lambda (value) (set! (● counter value) value))))
               (rc (inherit-handlers (once (lambda () (drop resource)))))))))))

(define frozen (→ (Pair Counter (Rc (FnOnce → Unit ! host)))) (make-work))

(define (observe (make (Fn → (Pair Counter (Rc (FnOnce → Unit ! host))))))
  (→ I64) (! mut host)
  (handle Log ((record-drop (lambda (value) (panic "wrong finalizer handler"))))
    (let ((counter (let ((pair (make)))
                     (match pair ((Pair counter work) (drop work) counter)))))
      (● counter value))))

(define (main) (→ Unit) (! mut host output-port)
  (write-line (show (observe (lambda () frozen))))
  (write-line (show (observe make-work)))
  (unit))
