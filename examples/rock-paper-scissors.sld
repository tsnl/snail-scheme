;; Play with ./snail-scheme run --target node examples/rock-paper-scissors.sld
(import
 (snail core base)
 (snail core io)
 (snail shell random))

(enum Action
  (Rock)
  (Paper)
  (Scissors))

(enum Outcome
  (Win)
  (Tie)
  (Loss))

(instance (Show Action)
  (define (show (action Action)) (→ String)
    (match action
      ((Rock) "Rock")
      ((Paper) "Paper")
      ((Scissors) "Scissors"))))

(define (string->action (text String)) (→ (Option Action))
  (if (= (string-length text) 0)
      (None)
      (case (string-ref text 0)
        ((#\r #\R) (Some (Rock)))
        ((#\p #\P) (Some (Paper)))
        ((#\s #\S) (Some (Scissors)))
        (else (None)))))

(define (random-action (rng Random)) (→ Action)
  (case (modulo (random-value rng) 3)
    ((0) (Rock))
    ((1) (Paper))
    (else (Scissors))))

(define (compute-outcome (player-action Action) (computer-action Action)) (→ Outcome)
  (match (new Pair (first player-action) (second computer-action))
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

(define (read-action (in InputPort) (out OutputPort)) (→ (Option Action))
  (let loop ((attempt 1))
    (display out
             (string-append "[" (show attempt) "] Choose: rock (r), paper (p), or scissors (s): "))
    (match (read-line in)
      ((None) (None))
      ((Some text)
       (match (string->action text)
         ((Some action) (Some action))
         ((None)
          (write-line out "Invalid choice, try again")
          (loop (+ attempt 1))))))))

(define (report-turn (out OutputPort) (player Action) (computer Action)) (→ Unit)
  (write-line out (string-append "You chose: " (show player)))
  (write-line out (string-append "Computer chose: " (show computer)))
  (write-line out (string-append "Outcome: " (outcome->string (compute-outcome player computer)))))

(define (main (in InputPort) (out OutputPort)) (→ Unit)
  (let loop ((game 1)
             (rng (make-random 42)))
    (write-line out (string-append "Game " (show game)))
    (match (read-action in out)
      ((None) (unit))
      ((Some player)
       (report-turn out player (random-action rng))
       (loop (+ game 1) (random-next rng))))))
