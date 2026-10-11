;; The comparator constructors and accessors used by (scheme hash-table).
;; Composite/default ordering and the rest of SRFI 128 are not implemented yet.
(define-library (scheme comparator)
  (export make-comparator comparator? comparator-ordered? comparator-hashable?
          comparator-type-test-predicate comparator-equality-predicate
          comparator-ordering-predicate comparator-hash-function
          comparator-test-type comparator-check-type comparator-hash
          make-eq-comparator make-eqv-comparator make-equal-comparator)
  (import (scheme base)
          (only (snail-scheme core) %hash-by-identity %eqv-hash %equal-hash))
  (begin
    (define-record-type <comparator>
      (comparator type equality ordering hash) comparator?
      (type comparator-type-test-predicate) (equality comparator-equality-predicate)
      (ordering comparator-ordering-predicate) (hash comparator-hash-function))

    (define (make-comparator type equality ordering hash)
      (unless (and (or (eq? type #t) (procedure? type))
                   (or (procedure? equality) (and (eq? equality #t) (procedure? ordering)))
                   (or (not ordering) (procedure? ordering)) (or (not hash) (procedure? hash)))
        (error "invalid comparator procedures"))
      (comparator (if (eq? type #t) (lambda (value) #t) type)
                  (if (eq? equality #t)
                      (lambda (a b) (and (not (ordering a b)) (not (ordering b a)))) equality)
                  ordering hash))

    (define (comparator-ordered? value) (if (comparator-ordering-predicate value) #t #f))
    (define (comparator-hashable? value) (if (comparator-hash-function value) #t #f))
    (define (comparator-test-type comparator value) ((comparator-type-test-predicate comparator) value))
    (define (comparator-check-type comparator value)
      (if (comparator-test-type comparator value) #t (error "comparator key type mismatch" value)))
    (define (comparator-hash comparator value) ((comparator-hash-function comparator) value))
    (define (make-eq-comparator) (make-comparator #t eq? #f %hash-by-identity))
    (define (make-eqv-comparator) (make-comparator #t eqv? #f %eqv-hash))
    (define (make-equal-comparator) (make-comparator #t equal? #f %equal-hash))))
