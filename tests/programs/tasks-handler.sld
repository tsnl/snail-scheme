(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; `tasks` is an ordinary effect, so a program may schedule its own work.
;; This handler runs work in logical time: a sleep advances its clock at
;; once rather than waiting, so what the work prints depends on the
;; program alone, as a test of it needs. Nothing here wakes a ticket, so
;; awaiting one abandons the work.
(: logical (-> (-> Unit ! console tasks) Unit ! console mut))
(define (logical work)
  (let ((clock (ref (ann 0 I64))))
    (handle tasks
        ((yield (lambda (resume) (resume (unit))))
         (sleep (lambda (delay resume)
                  (ref-set! clock (+ (ref-get clock) delay))
                  (write-line (string-append "at " (show (ref-get clock))))
                  (resume (unit))))
         (await (lambda (ticket resume)
                  (drop resume)
                  (panic "no ticket wakes under a logical clock")))
         (ticket (lambda () 0)))
      (work))))

(: countdown (-> String I64 Unit ! console tasks))
(define (countdown name count)
  (when (> count 0)
    (write-line (string-append name " " (show count)))
    (sleep 100)
    (countdown name (- count 1))))

;; The same function under the logical clock, at once, and under the
;; scheduler, in real time, once main returns.
(logical (lambda () (countdown "logical" 2)))
(dispatch-local (once (lambda () (countdown "real" 2))))
(write-line "main returns")
