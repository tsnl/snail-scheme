(import
 (snail core base)
 (snail core io))

;; A `fn` reads no local of the code around it, so it has no environment:
;; it may read its parameters, its own locals, globals, and its own name
;; when a definition binds it, and it may perform effects. The book's
;; ownership chapter includes the text between ANCHOR and ANCHOR_END.
;; ANCHOR: fn
(: greeting String)
(define greeting "hello")

(: shout (-> String Unit ! console))
(define (shout name)
  (let ((say (fn (text) (write-line (string-append greeting ", " text)))))
    (say name)))

(: count-down (-> I64 Unit ! console))
(define (count-down from)
  (define step
    (fn (n)
      (when (> n 0)
        (write-line (i64->string n))
        (step (- n 1)))))
  (step from))
;; ANCHOR_END: fn

(shout "world")
(count-down 3)
(for-each (fn (n) (write-line (i64->string (* n n)))) (list 1 2 3))
(call-once (once (fn () (write-line "once"))))
