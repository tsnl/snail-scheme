(import
  (snail core base)
  (snail core io)
  (snail shell random))

(enum Action
  (Rock)
  (Paper)
  (Scissors))

(: decode-action (impl (Fn I64 -> Action)))
(define (decode-action raw-action)
  (match raw-action
    (0 (Rock))
    (1 (Paper))
    (2 (Scissors))
    (_ (panic "Invalid raw-action"))))

(: random-action (impl (Fn Random -> Action)))
(define (random-action rng)
  (let* ((raw-action (modulo (random-value rng) 3))
         (action (decode-action raw-action)))
    action))

(: main (impl (Fn -> Unit ! console)))
(define (main)
  (let* ((rng (make-random 128))
         (rand-val (random-value rng))
         (rng (random-next rng)))
    (display rand-val)
    (display "\n")
    (display "Hello, world\n")))

(main)
