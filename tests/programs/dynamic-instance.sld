(import
 (snail core base)
 (snail core io)
 (gradual describe))

(instance (Num (! dyn-cast) Any)
  (dispatch I64 F64))

(define (describe-twice (value T)) (→ String) (! e) (∀ T e) (⊨ (Describe e T) (Copy T))
  (string-append (describe value) (describe value)))

(define (sum (a T) (b T)) (→ T) (! e) (∀ T e) (⊨ (Num e T)) (+ a b))

(define left (→ Any) 20)

(define right (→ Any) 22)

(define word (→ Any) "ok")

(define numbers (→ Any) (list 1 2 3))

(define main
  (lambda ()
    (display (sum 20 22))
    (newline)
    (handle dyn-cast
        ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
      (write-line (describe (sum left right)))
      (write-line (describe-twice word))
      (write-line (describe numbers))
      (display (ann (+ (ann 1.5 Any) (ann 2.5 Any)) F64))
      (newline))
    (unit)))
