(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (dyn (FnOnce -> Unit ! console)))))

(: title (impl (Fn (Borrow Model) -> String)))
(define (title model)
  (::title model))

(: forward (All (M) (impl (Fn (Borrow M) (dyn (Fn (Borrow M) -> String)) -> String))))
(define (forward model read)
  (read model))

;; A function accepting Borrow is owned: storage retains its code, not a loan.
(struct Reader
  ((read (dyn (Fn (Borrow Model) -> String)))))

(: identity (All (T) (impl (Fn T -> T))))
(define (identity value) value)

;; The callback owns the copied text; it does not retain the borrowed model.
(: callback (impl (Fn (Borrow Model) -> (dyn (Fn -> String)))))
(define (callback model)
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
