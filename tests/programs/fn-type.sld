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
   (on-press (fn I64 → String))))

(define (shout (count I64)) (→ String)
  (string-append "pressed " (i64->string count) " times"))

(define buttons (→ (List Button))
  (list (Button "named" shout)
        (Button "fn" (fn (count) (string-append "a fn saw " (i64->string count))))))

;; Calling an Fn calls its code.
(define (press (button Button) (count I64)) (→ String)
  ((::on-press button) count))
;; ANCHOR_END: fn-type

;; A signature or an annotation also gives a function the type Fn.
(define twice (→ (fn I64 → I64))
  (lambda (x) (* 2 x)))

(define (apply-all (functions (List (fn I64 → I64))) (x I64)) (→ (List I64))
  (match functions
    ((Nil) (Nil))
    ((Cons f rest) (Cons (f x) (apply-all rest x)))))

;; An imported function is code too, and an Fn performs what its row says
;; under the handlers where it is called.
(define (log-with (logger (fn String → Unit ! console))) (→ Unit) (! console)
  (logger "logged through an Fn"))

;; A call through an Fn may yield to a control handler.
(effect Stop
  ((ctl stop (dyn (Fn I64 → Unit)))))

(define (stop-at-two (n I64)) (→ Unit) (! Stop console)
  (write-line (string-append "checked " (i64->string n)))
  (when (= n 2) (stop n)))

(define (until-stop (check (fn I64 → Unit ! Stop console))) (→ I64) (! console)
  (handle Stop ((stop (lambda (value resume) (drop resume) value)))
    (check 1)
    (check 2)
    (check 3)
    -1))

(for-each (lambda (button) (write-line (press button 3))) buttons)
(for-each (lambda (n) (write-line (i64->string n)))
          (apply-all (list twice (ann (fn (x) (+ x 1)) (fn I64 → I64))) 10))
(log-with write-line)
(write-line (string-append "stopped at " (i64->string (until-stop stop-at-two))))
