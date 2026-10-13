(import (scheme base) (scheme write) (snail typing))

;; ---- Shared mutable containers ----

(define (check expected actual)
  (unless (equal? expected actual)
    (error "container alias disagreement" expected actual)))
(define (opaque procedure) (vector-ref (vector procedure) 0))
(define write-element! (opaque vector-set!))
(define copy-elements! (opaque vector-copy!))
(define append-vectors (opaque vector-append))
(define (identity value) value)
(: typed-identity (All (A) (-> A A)))
(define (typed-identity value) value)

;; Every write contributes to one shared element type before storage selection.
(define integers (vector 2147483648 4294967296 8589934592))
(define integer-alias ((inst typed-identity Vector) integers))
(write-element! integer-alias 1 "changed")
(check #t (eq? integers integer-alias))
(check '#(2147483648 "changed" 8589934592) integers)
(write-element! integer-alias 0 1.5)
(check #f (exact? (vector-ref integers 0)))
(check #t (exact? (vector-ref integers 2)))

(define floats (make-vector 3 1.25))
(define float-alias (identity floats))
(vector-set! floats 0 -0.0)
(write-element! float-alias 2 #f)
(check #t (eq? floats float-alias))
(check '#(-0.0 1.25 #f) floats)
(check (string->number "-inf.0") (/ 1.0 (vector-ref floats 0)))

;; Boolean and character slots can have the same Wasm width, but differ in meaning.
(define booleans (vector #f #t #f))
(define characters (vector #\a #\b #\c))
(copy-elements! characters 1 booleans 0 2)
(check '#(#\a #f #t) characters)
(write-element! booleans 0 #\x)
(check '#(#\x #t #f) booleans)
(check '#(#\x #t #f #\a #f #t) (append-vectors booleans characters))

;; Typed reference slots retain the objects themselves, including new cycles.
(define shared (cons 1 2))
(define references (make-vector 3 shared))
(define references-copy (vector-copy references))
(check #f (eq? references references-copy))
(check #t (eq? (vector-ref references 0) (vector-ref references-copy 2)))
(set-car! shared "shared")
(check "shared" (car (vector-ref references-copy 1)))
(write-element! references 1 references)
(check #t (eq? references (vector-ref references 1)))
(check #t (eq? shared (vector-ref references-copy 1)))

;; Copies remain shallow and use the original source slice when ranges overlap.
(define overlap (vector 0.25 1.25 2.25 3.25 4.25))
(define overlap-alias (identity overlap))
(copy-elements! overlap-alias 1 overlap 0 4)
(check '#(0.25 0.25 1.25 2.25 3.25) overlap)
(copy-elements! overlap 0 overlap-alias 1 5)
(check '#(0.25 1.25 2.25 3.25 3.25) overlap)
(write-element! overlap-alias 2 shared)
(copy-elements! overlap 1 overlap-alias 0 4)
(check #t (eq? shared (vector-ref overlap 3)))
(check 0.25 (vector-ref overlap 1))

(define empty (vector))
(define appended (append-vectors empty (vector 1.25 2.25) empty (vector 3.25)))
(check '#(1.25 2.25 3.25) appended)
(check #f (eq? empty (append-vectors empty)))
(check '#(1 2 3.5 4.5) (apply vector-append (list (vector 1 2) (vector 3.5 4.5))))
(check '#() (apply vector-append '()))

;; Pair fields have the same shared alias constraints as vector elements.
(define cell (cons 2147483648 1.25))
(define cell-alias (identity cell))
((opaque set-car!) cell-alias "changed")
((opaque set-cdr!) cell-alias cell)
(check "changed" (car cell))
(check #t (eq? cell (cdr cell)))

;; Existing typed record contracts still govern fields after an opaque call.
(define-record-type <point> (point x y) point?
                    (x : InexactReal point-x point-x-set!)
                    (y : ExactInteger point-y point-y-set!))
(define point-value (point 1.25 2147483648))
(define point-alias (identity point-value))
((opaque point-x-set!) point-alias 2.5)
((opaque point-y-set!) point-alias 4294967296)
(check #t (eq? point-value point-alias))
(check 2.5 (point-x point-value))
(check 4294967296 (point-y point-value))
(display "container alias checks passed\n")
