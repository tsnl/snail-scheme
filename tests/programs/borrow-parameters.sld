(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce → Unit ! output-port))))

(define (title (model (Borrow Model))) (→ String)
  (● model title))

(define (forward (model (Borrow M)) (read (Fn (Borrow M) → String))) (→ String) (∀ M)
  (read model))

;; A function accepting Borrow is owned: storage retains its code, not a loan.
(struct Reader
  ((read (Fn (Borrow Model) → String))))

(define (identity (value T)) (→ T) (∀ T) value)

;; The callback owns the copied text; it does not retain the borrowed model.
(define (callback (model (Borrow Model))) (→ (Fn → String))
  (let ((text (● model title)))
    (lambda () text)))

(define main
  (lambda ()
    (let ((model (Model "ready" (once (lambda () (write-line "finished"))))))
      (let ((read (with-borrow (borrowed model)
                               (let ((alias borrowed))
                                 (write-line (title alias))
                                 (write-line (forward borrowed (● (identity (Reader title)) read)))
                                 (callback alias)))))
        (match model
          ((Model _ work) (work)))
        (write-line (read))))
    (unit)))
