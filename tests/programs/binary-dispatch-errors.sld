(import
 (snail core base)
 (snail core io))

(typeclass (Combine e A B)
  (type Output)
  (: combine (Fn A B → Output ! e)))

(define-instance-set ordinary
  (instance (Combine (!) I64 I64)
    (type Output I64)
    (define combine (lambda (a b) (+ a b))))
  (instance (Combine (!) I64 F64)
    (type Output F64)
    (define combine (lambda (a b) (+ (i64->f64 a) b))))
  (instance (Combine (!) F64 I64)
    (type Output F64)
    (define combine (lambda (a b) (+ a (i64->f64 b))))))

(define (expect-domain (argument I64) (domain String) (body (Fn → Unit ! dyn-cast))) (→ Unit)
  (handle dyn-cast
      ((conversion-failed
        (lambda (error)
          (unless (and (= argument (● error argument))
                       (string=? domain (string-join (● error expected) ","))
                       (match (● error reason) ((UnsupportedInstance) #t) (_ #f)))
            (panic "wrong dispatch failure")))))
    (body)
    (panic "expected dispatch failure")))

(with-instances (ordinary)
                (define-instance-set erased
                  (dynamic-instances Combine (I64 I64) (I64 F64) (F64 I64))))

(define main
  (lambda ()

    ;; Missing a left type reports its full domain. A supported left type
    ;; restricts the right domain, even when the missing pair is otherwise valid.
    ;; Partially erased heads restrict the domain before dispatch begins.
    (with-instances (erased)
                    (expect-domain 0
                                   "I64,F64"
                                   (lambda () (combine (ann #t Any) (ann 1 Any)) (unit)))
                    (expect-domain 1
                                   "I64,F64"
                                   (lambda () (combine (ann 1 Any) (ann #t Any)) (unit)))
                    (expect-domain 1 "I64" (lambda () (combine (ann 1.0 Any) (ann 2.0 Any)) (unit)))
                    (expect-domain 0 "I64" (lambda () (combine (ann #t Any) 2.0) (unit)))
                    (expect-domain 1 "I64" (lambda () (combine 1.0 (ann 2.0 Any)) (unit))))
    (write-line "dispatch domains preserved")
    (unit)))
