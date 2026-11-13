(import
  (snail core base)
  (snail core io)
  (snail shell random)
  (snail shell compiler))

(enum Action
  (Rock)
  (Paper)
  (Scissors))

(instance (Show (!) Action)
  (define (show action)
    (match action
      ((Rock) "Rock")
      ((Paper) "Paper")
      ((Scissors) "Scissors"))))

(: decode-action (impl (Fn I64 -> Action)))
(define (decode-action raw-action)
  (match raw-action
    (0 (Rock))
    (1 (Paper))
    (2 (Scissors))
    (_ (panic "Invalid raw-action"))))

(: random-action (impl (Fn Random -> Action)))
(define (random-action rng)
  (let* ((action (modulo (random-value rng) 3))
         (action (decode-action action)))
    action))

(: main (impl (Fn -> Unit ! console)))
(define (main)
  (let* ((rng (make-random 128))

         (_ (display (random-action rng)))
         (_ (display "\n"))
         (rng (random-next rng))

         (_ (display (random-action rng)))
         (_ (display "\n"))
         (rng (random-next rng))

         (_ (display (random-action rng)))
         (_ (display "\n"))
         (rng (random-next rng))

         (_ (display (random-action rng)))
         (_ (display "\n"))
         (rng (random-next rng))

         (_ (display (random-action rng)))
         (_ (display "\n"))
         (rng (random-next rng))

         (_ (display (random-action rng)))
         (_ (display "\n"))
         (rng (random-next rng))

         (_ (display "Enter a string: "))
         (text (read-line))
         (_ (display (datum->string (DString text))))
         (_ (display "\n"))
         )

    (display "Hello, world\n")))

(main)
