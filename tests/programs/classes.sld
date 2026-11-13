(import
 (snail core base)
 (snail core io))

(typeclass (Describe T)
  (: describe (Fn T → String)))

(instance (Describe I64)
  (define describe (lambda (n) (string-append "int " (show n)))))

(instance (Describe Bool)
  (define describe (lambda (b) (if b "true" "false"))))

(instance (Describe (List T))
  (⊨ (Describe T))
  (define describe
    (lambda (items)
      (string-append "[" (string-append (string-join (map describe items) ", ") "]")))))

(instance (Describe (Option T))
  (⊨ (Describe T))
  (define describe
    (lambda (value) (match value
                      ((None) "nothing")
                      ((Some x) (string-append "just " (describe x)))))))

(define (describe-twice (value T)) (→ String) (∀ (T)) (⊨ (Describe T) (Copy T) (Drop (!) T))
  (string-append (describe value) (string-append " / " (describe value))))

(define (sum (items (List T)) (zero T)) (→ T) (∀ (T)) (⊨ (Num (!) T))
  (fold-left + zero items))

(define main
  (lambda ()
    (write-line (describe (list 1 2 3)))
    (write-line (describe (list (Some #t) (None))))
    (write-line (describe-twice (list (list 1) (list))))
    (display (sum (list 1 2 3) 0))
    (newline)
    (display (sum (list 1.5 2.5) 0.0))
    (newline)
    (display (max 3 9))
    (newline)
    (write-line (show (< "apple" "banana")))
    (unit)))
