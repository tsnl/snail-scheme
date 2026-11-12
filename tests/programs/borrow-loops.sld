(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce → Unit))))

;; A named let's parameters are inferred, so a read through one annotates
;; the borrow; a lambda checked against a signature has typed parameters.
(define (count-to (model (Borrow Model)) (limit I64)) (→ I64)
  (let loop ((n 0) (b model))
    (if (< n limit) (loop (+ n 1) b) (string-length (● (ann b (Borrow Model)) title)))))

(define read (→ (Fn (Borrow Model) → String)) (lambda (r) (● r title)))

(define main
  (lambda ()
    (let ((model (Model "abcd" (once (lambda () (unit))))))
      (write-line (show (with-borrow (b model) (count-to b 3))))
      (write-line (with-borrow (b model) (read b)))
      (drop model))
    (unit)))
