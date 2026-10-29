(import
 (snail core base)
 (snail core io))

;; `(Fn A B ! e)` is a function without an environment, by type: a
;; reference to its code, which takes no closure. A `fn` and the name of a
;; top-level function have that type where it is expected. The book's
;; ownership chapter includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: fn-type
(struct Button
  ((label String)
   (on-press (Fn I64 String))))

(: shout (-> I64 String))
(define (shout count)
  (string-append "pressed " (i64->string count) " times"))

(: buttons (List Button))
(define buttons
  (list (Button "named" shout)
        (Button "fn" (fn (count) (string-append "a fn saw " (i64->string count))))))

;; Calling an Fn calls its code.
(: press (-> Button I64 String))
(define (press button count)
  ((Button-on-press button) count))
;; ANCHOR_END: fn-type

;; A signature or an annotation also gives a function the type Fn.
(: twice (Fn I64 I64))
(define (twice x)
  (* 2 x))

(: apply-all (-> (List (Fn I64 I64)) I64 (List I64)))
(define (apply-all functions x)
  (match functions
    ((Nil) (Nil))
    ((Cons f rest) (Cons (f x) (apply-all rest x)))))

;; An imported function is code too, and an Fn performs what its row says
;; under the handlers where it is called.
(: log-with (-> (Fn String Unit ! console) Unit ! console))
(define (log-with logger)
  (logger "logged through an Fn"))

;; A call through an Fn may yield to a control handler.
(effect Stop
  ((ctl stop (-> I64 Unit))))

(: stop-at-two (-> I64 Unit ! Stop console))
(define (stop-at-two n)
  (write-line (string-append "checked " (i64->string n)))
  (when (= n 2) (stop n)))

(: until-stop (-> (Fn I64 Unit ! Stop console) I64 ! console))
(define (until-stop check)
  (handle Stop ((stop (lambda (value resume) (drop resume) value)))
    (check 1)
    (check 2)
    (check 3)
    -1))

(for-each (lambda (button) (write-line (press button 3))) buttons)
(for-each (lambda (n) (write-line (i64->string n)))
          (apply-all (list twice (ann (fn (x) (+ x 1)) (Fn I64 I64))) 10))
(log-with write-line)
(write-line (string-append "stopped at " (i64->string (until-stop stop-at-two))))
