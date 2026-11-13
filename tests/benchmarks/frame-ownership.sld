(import
 (snail core base))

(struct Counter
  ((closed I64)))

(struct Resource
  ((counter Counter)
   (number I64)))

(instance (Drop (! mut) Resource)
  (define (drop (resource Resource)) (→ Unit) (! mut)
    (match resource
      ((Resource counter number) (set! (● counter closed) (+ (● counter closed) 1))))))

(effect Pause ((ctl pause (Fn I64 → I64))))

;; Every non-tail caller owns a counted parameter across the suspension.
;; Cancelling consumes all those credits; resuming uses them before cleanup.
(define (nested (depth I64) (resource (Rc Resource))) (→ I64) (! Pause mut)
  (if (= depth 0) (pause 1)
      (let ((answer (nested (- depth 1) resource)))
        (+ answer (● resource number)))))

(define (iteration (depth I64) (cancel Bool) (counter Counter)) (→ I64) (! mut)
  (let ((resource (rc (Resource counter 1))))
    (handle Pause
        ((pause (lambda (number resume)
                  (if cancel (begin (drop resume) number) (resume number)))))
      (nested depth resource))))

(define (measure (count I64) (depth I64) (cancel Bool)) (→ I64) (! mut)
  (let ((counter (Counter 0)))
    (let loop ((left count) (sum 0))
      (if (= left 0) (if (= (● counter closed) count) sum -1)
          (loop (- left 1) (+ sum (iteration depth cancel counter)))))))

(expose measure "measure")
(define (main) (→ Unit) (unit))
