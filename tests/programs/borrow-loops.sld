(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (dyn (FnOnce -> Unit)))))

;; A named let's parameters are inferred, so a read through one annotates
;; the borrow; a lambda checked against a signature has typed parameters.
(: count-to (impl (Fn (Borrow Model) I64 -> I64)))
(define (count-to model limit)
  (let loop ((n 0) (b model))
    (if (< n limit) (loop (+ n 1) b) (string-length (::title (ann b (Borrow Model)))))))

(: read (impl (Fn (Borrow Model) -> String)))
(define read (lambda (r) (::title r)))

(let ((model (Model "abcd" (once (lambda () (unit))))))
  (write-line (show (with-borrow (b model) (count-to b 3))))
  (write-line (with-borrow (b model) (read b)))
  (drop model))
