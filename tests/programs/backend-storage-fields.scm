(import (scheme base) (scheme write) (scheme process-context) (snail typing))

;; ---- Fixed pair fields and shared identity ----

(define (check expected actual)
  (unless (equal? expected actual)
    (error "field storage disagreement" expected actual)))
(define (opaque procedure) (vector-ref (vector procedure) 0))
(define pair (cons 2147483648 -0.0))
(define pair-alias pair)
(set-car! pair-alias (+ (car pair) 7))
(check 2147483655 (car pair))
(check (string->number "-inf.0") (/ 1.0 (cdr pair)))
(check #t (eq? pair pair-alias))

;; Equal physical widths must not confuse the field's boxing recipe.
(define boolean-pair (cons #t 4294967296))
(define character-pair (cons #\a 4294967296))
((opaque set-car!) boolean-pair #f)
((opaque set-car!) character-pair #\z)
(check #f ((opaque car) boolean-pair))
(check #\z ((opaque car) character-pair))

;; A reference field admits every physical pair layout and retains its alias.
(define mixed (cons 'old 'tail))
(set-car! mixed "changed")
(define references (cons pair pair))
(set-car! references mixed)
(set-cdr! references references)
(check #t (eq? mixed (car references)))
(check #t (eq? references (cdr references)))
(set-car! (car references) #\x)
(check #\x (car mixed))

;; ---- Record contracts and omitted fields ----

(define-record-type <point> (point x y) point?
                    (x : InexactReal point-x point-x-set!)
                    (y : ExactInteger point-y point-y-set!))
(define-record-type <other-point> (other-point x y) other-point?
                    (x : InexactReal other-point-x)
                    (y : ExactInteger other-point-y))
(define origin (point -0.0 2147483648))
(define origin-alias origin)
((opaque point-y-set!) origin-alias (+ (point-y origin) 3))
(check #t (eq? origin origin-alias))
(check 2147483651 (point-y origin))
(check (string->number "-inf.0") (/ 1.0 (point-x origin)))
(check #f (other-point? origin))

;; An omitted unannotated field initially holds Unspecified, not a native zero.
(define-record-type <partial> (partial x) partial?
                    (x : InexactReal partial-x)
                    (y partial-y partial-y-set!))
(define incomplete (partial 1.25))
(define-record-type <mixed> (make-mixed value) mixed?
                    (value mixed-value mixed-value-set!))
(define mixed-record (make-mixed 1.5))
(mixed-value-set! mixed-record "changed")
(check "changed" (mixed-value mixed-record))

;; Managed record fields retain references without narrowing physical layouts.
(define-record-type <owner> (owner value) owner?
                    (value : Pair owner-value owner-value-set!))
(define record-owner (owner pair))
(owner-value-set! record-owner mixed)
(check #t (eq? mixed (owner-value record-owner)))

(define mode (if (null? (cdr (command-line))) "pass" (cadr (command-line))))
(cond ((string=? mode "omitted") (ann (partial-y incomplete) InexactReal))
      ((string=? mode "nominal") ((opaque point-x) (other-point 1.0 2)))
      ((string=? mode "write") ((opaque point-x-set!) origin "bad"))
      (else (partial-y-set! incomplete 2.5)
            (check 2.5 (partial-y incomplete))
            (display "field storage checks passed\n")))
