(import
 (snail core base)
 (snail core io))

(struct Token
  ((number I64)
   (label String)))

(instance (Drop (! output-port) Token)
  (define drop
    (lambda (token) (match token
                      ((Token _ label) (write-line label))))))

(define (shared (function F))
  (→ I64)
  (! output-port)
  (∀ F)
  (⊨ (Fn F I64 → I64 ! output-port) (Drop (! output-port) F))
  (let ((answer (+ (function 1) (function 2))))
    (drop function)
    answer))

(let* ((token (Token 10 "shared drop"))
       (function (ann (lambda (value) (+ (● token number) value))
                      (impl (Fn I64 → I64 ! output-port)))))
  (write-line (show (shared function))))

(define (exclusive (function F))
  (→ I64)
  (! output-port)
  (∀ F)
  (⊨ (FnMut F I64 → I64 ! output-port) (Drop (! output-port) F))
  (let ((answer (function 5)))
    (drop function)
    answer))

(let* ((token (Token 20 "exclusive drop"))
       (function (ann (lambda (value) (+ (● token number) value))
                      (impl (FnMut I64 → I64 ! output-port)))))
  (write-line (show (exclusive function))))

(let* ((token (Token 30 "one-shot drop"))
       (function (ann (lambda (value) (drop token) (+ value 1))
                      (impl (FnOnce I64 → I64 ! output-port)))))
  (write-line (show (function 6))))

(let* ((token (Token 40 "uncalled drop"))
       (function (ann (lambda (value) (drop token) (+ value 1))
                      (impl (FnOnce I64 → I64 ! output-port)))))
  (drop function))

(define (consume (function F)) (→ I64) (! output-port) (∀ F) (⊨ (FnOnce F I64 → I64 ! output-port))
  (function 7))

(let* ((token (Token 50 "consumed shared"))
       (function (ann (lambda (value) (+ (● token number) value))
                      (impl (Fn I64 → I64 ! output-port)))))
  (write-line (show (consume function))))

(let* ((token (Token 60 "adapted shared"))
       (function (ann (lambda (value) (+ (● token number) value))
                      (impl (Fn I64 → I64 ! output-port))))
       (single (once function)))
  (write-line (show (single 8))))

(let* ((token (Token 70 "abandoned shared"))
       (function (ann (lambda (value) (+ (● token number) value))
                      (impl (Fn I64 → I64 ! output-port))))
       (single (once function)))
  (drop single))

(let* ((token (Token 80 "erased shared"))
       (function (ann (lambda (value) (+ (● token number) value))
                      (impl (Fn I64 → I64 ! output-port))))
       (single (ann function (dyn (FnOnce I64 → I64 ! output-port)))))
  (write-line (show (single 9))))
