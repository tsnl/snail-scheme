(import
 (snail core base)
 (snail core io)
 (snail shell random)
 (snail shell text))

(enum Action
  (Rock)
  (Paper)
  (Scissors))

(enum Outcome
  (Win)
  (Tie)
  (Loss))

(instance (Show (!) Action)
  (define (show (action Action)) (→ String)
    (match action
      ((Rock) "Rock")
      ((Paper) "Paper")
      ((Scissors) "Scissors"))))

(define (starts-with? (text String) (prefix String)) (→ Bool)
  (and (<= (string-length prefix) (string-length text))
       (string=? (substring text 0 (string-length prefix)) prefix)))

(define (string->action (raw-action String)) (→ (Option Action))
  (let ((raw-action (string-downcase raw-action)))
    (cond
     ((starts-with? raw-action "r") (Some (Rock)))
     ((starts-with? raw-action "p") (Some (Paper)))
     ((starts-with? raw-action "s") (Some (Scissors)))
     (else (None)))))

(define (action->string (action Action)) (→ String)
  (match action
    ((Rock) "Rock")
    ((Paper) "Paper")
    ((Scissors) "Scissors")))

(define (i64->action (raw-action I64)) (→ Action)
  (match raw-action
    (0 (Rock))
    (1 (Paper))
    (2 (Scissors))
    (_ (panic "Invalid raw-action in i64->action"))))

(define (random-action (rng Random)) (→ Action)
  (let* ((action (modulo (random-value rng) 3))
         (action (i64->action action)))
    action))

(define (compute-outcome (player-action Action) (computer-action Action)) (→ Outcome)
  (match (Pair player-action computer-action)
    ((Pair (Rock) (Scissors)) (Win))
    ((Pair (Paper) (Rock)) (Win))
    ((Pair (Scissors) (Paper)) (Win))
    ((Pair (Rock) (Rock)) (Tie))
    ((Pair (Paper) (Paper)) (Tie))
    ((Pair (Scissors) (Scissors)) (Tie))
    (_ (Loss))))

(define (outcome->string (outcome Outcome)) (→ String)
  (match outcome
    ((Win) "You won")
    ((Tie) "You tied")
    ((Loss) "You lost")))

(define (read-action) (→ (Option Action)) (! input-port output-port)
  (let loop ((i 0))
    (begin
      (display "[")
      (display (+ i 1))
      (display "]")
      (display " ")

      (display "Choose: rock (r), paper (p), or scissors (s): ")

      (match (read-line)
        ((None) (None))
        ((Some raw-action)
         (match (string->action raw-action)
           ((None) (begin (display "Invalid choice, try again\n") (loop (+ i 1))))
           ((Some action) (Some action))))))))

(define (turn (rng Random)) (→ Bool) (! input-port output-port)
  (match (read-action)
    ((None) #f)
    ((Some player-action)
     (let* ((computer-action (random-action rng))
            (outcome (compute-outcome player-action computer-action)))
       (begin
         (display "You chose: ")
         (display (action->string player-action))
         (display "\n")

         (display "Computer chose: ")
         (display (action->string computer-action))
         (display "\n")

         (display "Outcome: ")
         (display (outcome->string outcome))
         (display "\n")

         #t)))))

(define (main) (→ Unit) (! input-port output-port)
  (let ((SEED 42))
    (let loop ((i 0)
               (rng (make-random SEED)))
      (begin
        (display "Game ")
        (display (+ 1 i))
        (display "\n")

        (if (turn rng)
          (loop (+ i 1) (random-next rng))
          (unit))))))
