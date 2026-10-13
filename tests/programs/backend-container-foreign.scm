(import (scheme base) (scheme write)
        (only (snail-scheme extensions)
              container-exchange! container-envelope container-call container-pair-exchange!))

;; ---- Foreign aliases and callback arguments ----

(define (check expected actual)
  (unless (equal? expected actual)
    (error "foreign container disagreement" expected actual)))
(define numbers (vector 2147483648 4294967296))
(define number-alias (container-exchange! numbers "changed" 1))
(check #t (eq? numbers number-alias))
(check '#(2147483648 "changed") numbers)
(define floats (make-vector 2 1.25))
(check #t (eq? floats (container-exchange! floats #f 0)))
(check '#(#f 1.25) floats)

;; The callback receives captured argument values even if it mutates their source.
(define arguments (vector 1.25 2.5))
(check 3.75 (container-call
             (lambda (a b) (vector-set! arguments 1 "changed") (+ a b)) arguments))
(check '#(1.25 "changed") arguments)
(check 2 (container-call - (vector 2147483650 2147483648)))

(define pair (cons 2147483648 1.25))
(check #t (eq? pair (container-pair-exchange! pair "changed")))
(check "changed" (car pair))
(check #t (eq? pair (cdr pair)))

;; ---- Live envelopes and captured snapshots ----

;; A raw copy retains the envelope. Its later consumption follows the owner's
;; current elements after mutation through any alias. Foreign mutation requires
;; an appropriately broad allocation layout before this boundary is reached.
(define backing (vector 2147483648))
(define carrier (container-envelope backing))
(define carrier-copy (vector-copy carrier))
(define replacement (cons 'replacement 'value))
(vector-set! backing 0 replacement)
(check #t (eq? replacement (vector-ref carrier-copy 0)))

;; vector-map consumes the envelope while building its pre-callback snapshot.
;; That snapshot retains the extracted reference, not a later view of the slot.
(define other-backing (vector 1.25))
(define other-carrier (container-envelope other-backing))
(check '#(1.25)
       (vector-map (lambda (value) (vector-set! other-backing 0 "later") value)
                   other-carrier))
(check '#("later") other-backing)
(check "later" (vector-ref other-carrier 0))
(display "foreign container checks passed\n")
