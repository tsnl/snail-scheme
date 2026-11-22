(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task))

;; `tasks` is an ordinary effect, so a program may schedule its own work.
;; This handler runs work in logical time: a sleep advances its clock at
;; once rather than waiting, so what the work prints depends on the
;; program alone, as a test of it needs. Nothing here wakes a ticket, so
;; awaiting one panics.
(record Clock
  ((elapsed I64)))

(define (logical (out OutputPort) (work (Fn → Unit ! mut tasks))) (→ Unit) (! mut)
  (let ((clock (new Clock (elapsed 0))))
    (handle tasks
        ((yield (lambda (resume) (resume (unit))))
         (sleep (lambda (delay resume)
                  (set! (● clock elapsed) (+ (● clock elapsed) delay))
                  (write-line out (string-append "at " (show (● clock elapsed))))
                  (resume (unit))))
         (await (lambda (ticket resume)
                  (panic "no ticket wakes under a logical clock")))
         (ticket (lambda () 0))
         (current-scheduler (lambda () (panic "the logical handler cannot dispatch work"))))
      (work))))

(define (countdown (out OutputPort) (name String) (count I64)) (→ Unit) (! mut tasks)
  (when (> count 0)
    (write-line out (string-append name " " (show count)))
    (sleep 100)
    (countdown out name (- count 1))))

(define (main (out OutputPort)) (→ Unit) (! host mut tasks)

  ;; The same function under the logical clock, at once, and under the
  ;; scheduler, in real time, once main returns.
  (logical out (lambda () (countdown out "logical" 2)))
  (dispatch (lambda () (countdown out "real" 2)))
  (write-line out "main returns")
  (unit))
