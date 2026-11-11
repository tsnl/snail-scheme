(import
 (snail core base)
 (snail core io))

(struct Token
  ((number I64)
   (label String)))

(instance (Drop (! console) Token)
  (define drop
    (lambda (token) (match token
                      ((Token _ label) (write-line label))))))

(define (shared (function F))
  (→ I64)
  (! console)
  (∀ F)
  (⊨ (Fn F I64 → I64 ! console) (Drop (! console) F))
  (let ((answer (+ (function 1) (function 2))))
    (drop function)
    answer))

(let* ((token (Token 10 "shared drop"))
       (function (ann (lambda (value) (+ (::number token) value))
                      (impl (Fn I64 → I64 ! console)))))
  (write-line (show (shared function))))

(define (exclusive (function F))
  (→ I64)
  (! console)
  (∀ F)
  (⊨ (FnMut F I64 → I64 ! console) (Drop (! console) F))
  (let ((answer (function 5)))
    (drop function)
    answer))

(let* ((token (Token 20 "exclusive drop"))
       (function (ann (lambda (value) (+ (::number token) value))
                      (impl (FnMut I64 → I64 ! console)))))
  (write-line (show (exclusive function))))

(let* ((token (Token 30 "one-shot drop"))
       (function (ann (lambda (value) (drop token) (+ value 1))
                      (impl (FnOnce I64 → I64 ! console)))))
  (write-line (show (function 6))))

(let* ((token (Token 40 "uncalled drop"))
       (function (ann (lambda (value) (drop token) (+ value 1))
                      (impl (FnOnce I64 → I64 ! console)))))
  (drop function))

(define (consume (function F)) (→ I64) (! console) (∀ F) (⊨ (FnOnce F I64 → I64 ! console))
  (function 7))

(let* ((token (Token 50 "consumed shared"))
       (function (ann (lambda (value) (+ (::number token) value))
                      (impl (Fn I64 → I64 ! console)))))
  (write-line (show (consume function))))

(let* ((token (Token 60 "adapted shared"))
       (function (ann (lambda (value) (+ (::number token) value))
                      (impl (Fn I64 → I64 ! console))))
       (single (once function)))
  (write-line (show (single 8))))

(let* ((token (Token 70 "abandoned shared"))
       (function (ann (lambda (value) (+ (::number token) value))
                      (impl (Fn I64 → I64 ! console))))
       (single (once function)))
  (drop single))

(let* ((token (Token 80 "erased shared"))
       (function (ann (lambda (value) (+ (::number token) value))
                      (impl (Fn I64 → I64 ! console))))
       (single (ann function (dyn (FnOnce I64 → I64 ! console)))))
  (write-line (show (single 9))))
