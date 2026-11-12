(import
 (snail core base)
 (snail core io))

;; An Any's TypeId has no rows, so a yielding function converted to Any
;; could come back as a total one, and a call through it would not be
;; tested for a yield: the body would run on with a placeholder. An Any
;; never holds a function that performs effects.
(effect Gen
  ((ctl yield (Fn I64 → I64))))

(define (gen) (→ I64) (! Gen) (+ 1 (yield 1)))

(define boxed (→ Any) (type-convert gen Any))

(define hidden (→ (Fn → I64)) (type-convert boxed (Fn → I64)))

(display (handle Gen ((yield (lambda (v resume) (+ 1000 (resume (* v 10))))))
           (let ((a (hidden)))
             (write-line (string-append "a = " (show a)))
             (+ a 5))))
(newline)
