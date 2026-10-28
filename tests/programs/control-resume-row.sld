(import
 (snail core base)
 (snail core io))

;; `resume` performs the handle's context row, so a stored resumption says
;; Log, and is resumed under a Log handler: the one in scope where it is
;; called, not the one around `start`.
(effect Gen
  ((ctl yield (-> I64 I64))))

(effect Log
  ((log (-> String Unit))))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Once (-> I64 Step ! Log))))))

(: start (-> (-> Unit ! Gen) Step ! Log))
(define (start body)
  (handle Gen ((yield (lambda (v resume)
                        (log (string-append "handler saw " (show v)))
                        (Yielded v resume))))
    (body)
    (Done)))

(: counter (-> Unit ! Gen))
(define (counter)
  (yield 1)
  (yield 2)
  (unit))

;; Each handler prints the lines it is given under its own name.
(match (handle Log ((log (lambda (line) (write-line (string-append "first: " line)))))
         (start counter))
  ((Yielded value next)
   (write-line (string-append "got " (show value)))
   (match (handle Log ((log (lambda (line) (write-line (string-append "second: " line)))))
            (next 10))
     ((Yielded value rest)
      (drop rest)
      (write-line (string-append "got " (show value))))
     ((Done) (write-line "done"))))
  ((Done) (write-line "done at once")))
