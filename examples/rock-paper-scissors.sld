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
  (define (show (action Action)) (→ String)
    (match action
      ((Rock) "Rock")
      ((Paper) "Paper")
      ((Scissors) "Scissors"))))

(define (decode-action (raw-action I64)) (→ Action)
  (match raw-action
    (0 (Rock))
    (1 (Paper))
    (2 (Scissors))
    (_ (panic "Invalid raw-action"))))

(define (random-action (rng Random)) (→ Action)
  (let* ((action (modulo (random-value rng) 3))
         (action (decode-action action)))
    action))

(define (main) (→ Unit) (! input-port output-port)
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
         (_ (display (repr text)))
         (_ (display "\n")))

    (display "Hello, world\n")))
