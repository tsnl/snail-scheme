(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task))

;; `tasks` is an ordinary effect, so a program may schedule its own work.
;; This handler runs work in logical time: a sleep advances its clock at
;; once rather than waiting, so what the work prints depends on the
;; program alone, as a test of it needs. Nothing here wakes a ticket, so
;; awaiting one abandons the work.
(struct Clock
  ((elapsed I64)))

(define (logical (work (FnOnce → Unit ! mut output-port tasks))) (→ Unit) (! output-port mut)
  (let ((clock (Clock 0)))
    (handle tasks
        ((yield (lambda (resume) (resume (unit))))
         (sleep (lambda (delay resume)
                  (set! (● clock elapsed) (+ (● clock elapsed) delay))
                  (write-line (string-append "at " (show (● clock elapsed))))
                  (resume (unit))))
         (await (lambda (ticket resume)
                  (drop resume)
                  (panic "no ticket wakes under a logical clock")))
         (ticket (lambda () 0))
         (current-scheduler (lambda () (panic "the logical handler cannot dispatch work"))))
      (work))))

(define (countdown (name String) (count I64)) (→ Unit) (! output-port tasks)
  (when (> count 0)
    (write-line (string-append name " " (show count)))
    (sleep 100)
    (countdown name (- count 1))))

(define (main) (→ Unit) (! host mut output-port tasks)

  ;; The same function under the logical clock, at once, and under the
  ;; scheduler, in real time, once main returns.
  (logical (lambda () (countdown "logical" 2)))
  (dispatch-local (once (lambda () (countdown "real" 2))))
  (write-line "main returns")
  (unit))
