(import
 (snail-core base)
 (snail-core io))

;; An Any's TypeId has no rows, so a yielding function converted to Any
;; could come back as a total one, and a call through it would not be
;; tested for a yield: the body would run on with a placeholder. An Any
;; never holds a function that performs effects.
(effect Gen
  ((ctl yield (-> I64 I64))))

(: gen (-> I64 ! Gen))
(define (gen) (+ 1 (yield 1)))

(: boxed Any)
(define boxed (type-convert gen Any))

(: hidden (-> I64))
(define hidden (type-convert boxed (-> I64)))

(display (handle Gen ((yield (lambda (v resume) (+ 1000 (resume (* v 10))))))
           (let ((a (hidden)))
             (write-line (string-append "a = " (show a)))
             (+ a 5))))
(newline)
