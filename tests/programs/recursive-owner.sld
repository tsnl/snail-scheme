(import
 (snail core base)
 (snail core io))

(effect Pausing ((ctl pause (Fn I64 → I64))))
(effect Finalized ((finalized (Fn I64 → Unit))))
(record Counter
  ((value I64)))
(record Resource
  ((value I64)))
(instance (Drop (! Finalized) Resource)
  (define (drop (value Resource)) (→ Unit) (! Finalized)
    (match value ((Resource value) (finalized value)))))

(define (probe (cancel? Bool) (tail? Bool)) (→ (Pair I64 I64))
  (unsafe-total
   (lambda ()
     (let* ((counter (new Counter (value 0)))
            (answer
             (handle Finalized
                 ((finalized (lambda (value) (set! (● counter value) (+ (● counter value) value)))))
               (let ((owner (rc (new Resource (value 7)))))
                 (define (loop (left I64)) (→ I64) (! Pausing mut Finalized)
                   (if (= left 0) (● owner value)
                       (let ((again loop))
                         (if tail? (again (pause (- left 1)))
                             (+ 1 (again (pause (- left 1))))))))
                 (handle Pausing
                     ((pause (lambda (value resume)
                               (if (and cancel? (= value 2))
                                   (begin (drop resume) 99)
                                   (resume value)))))
                   (loop 4))))))
       (new Pair (first answer) (second (● counter value)))))))

(define (main) (→ Unit) (! output-port)
  (match (probe #f #t) ((Pair answer count) (write-line (show answer)) (write-line (show count))))
  (match (probe #t #t) ((Pair answer count) (write-line (show answer)) (write-line (show count))))
  (match (probe #f #f) ((Pair answer count) (write-line (show answer)) (write-line (show count))))
  (match (probe #t #f) ((Pair answer count) (write-line (show answer)) (write-line (show count)))))
