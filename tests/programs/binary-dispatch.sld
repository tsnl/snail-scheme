(import
 (snail core base)
 (snail core io))

(effect log ((message (dyn (Fn String → Unit)))))
(typeclass (Subtract e A B)
  (type Output)
  (: subtract (impl (Fn A B → Output ! e))))
(define-instance-set ordinary
  (instance (Subtract (!) I64 I64)
    (type Output I64)
    (define subtract (lambda (a b) (- a b))))
  (instance (Subtract (! log) I64 F64)
    (type Output F64)
    (define subtract (lambda (a b) (message "source") (- (i64->f64 a) b))))
  (instance (Subtract (!) F64 I64)
    (type Output F64)
    (define subtract (lambda (a b) (- a (i64->f64 b))))))

(with-instances (ordinary)
                (define-instance-set erased
                  (dynamic-instances Subtract (I64 I64) (I64 F64) (F64 I64))))

;; A competing source policy cannot change the captured implementation.
(define-instance-set alternate
  (instance (Subtract (!) I64 F64)
    (type Output F64)
    (define subtract (lambda (a b) (+ (i64->f64 a) b)))))

(define (ordered (label String) (value Any)) (→ Any) (! console) (write-line label) value)

(with-instances (erased alternate)
                (handle dyn-cast ((conversion-failed (lambda (error)
                                                       (write-line "unsupported")
                                                       (display (● error argument))
                                                       (newline)
                                                       (write-line
                                                        (string-join (● error expected)
                                                                     ",")))))
                  (handle log ((message (lambda (text) (write-line text))))
                    (display (subtract (ann 10 Any) 2.5))
                    (newline)
                    (display (subtract 10.5 (ann 2 Any)))
                    (newline)
                    (display (ann (subtract (ann 10 Any) (ann 2 Any)) I64))
                    (newline)
                    ;; Output Any is retained when one-sided branches disagree.
                    (display (ann (subtract (ann 10 I64) (ann 2.5 Any)) F64))
                    (newline)
                    ;; The domain is a relation: F64,F64 is deliberately absent.
                    ;; Both operands finish before the failed dispatch.
                    (subtract (ordered "left" 10.5) (ordered "right" 2.5))
                    (unit))))

;; Naming associated evidence does not execute its row.
(define (keep (value (Subtract.Output e A B)))
  (→ (Subtract.Output e A B))
  (∀ A B e)
  (⊨ (Subtract e A B))
  value)
