(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (dyn (FnOnce → Unit ! console)))))

(define (title (model (Borrow Model))) (→ String)
  (::title model))

(define (forward (model (Borrow M)) (read (dyn (Fn (Borrow M) → String)))) (→ String) (∀ M)
  (read model))

;; A function accepting Borrow is owned: storage retains its code, not a loan.
(struct Reader
  ((read (dyn (Fn (Borrow Model) → String)))))

(define (identity (value T)) (→ T) (∀ T) value)

;; The callback owns the copied text; it does not retain the borrowed model.
(define (callback (model (Borrow Model))) (→ (dyn (Fn → String)))
  (let ((text (::title model)))
    (lambda () text)))

(let ((model (Model "ready" (once (lambda () (write-line "finished"))))))
  (let ((read (with-borrow (borrowed model)
                           (let ((alias borrowed))
                             (write-line (title alias))
                             (write-line (forward borrowed (::read (identity (Reader title)))))
                             (callback alias)))))
    (match model
      ((Model _ work) (work)))
    (write-line (read))))
