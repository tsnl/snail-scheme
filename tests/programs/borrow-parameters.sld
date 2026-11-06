(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce Unit ! console))))

(: title (-> (Borrow Model) String))
(define (title model)
  (Model-title model))

(: forward (All (M) (-> (Borrow M) (-> (Borrow M) String) String)))
(define (forward model read)
  (read model))

;; A function accepting Borrow is owned: storage retains its code, not a loan.
(struct Reader
  ((read (-> (Borrow Model) String))))

(: identity (All (T) (-> T T)))
(define (identity value) value)

;; The callback owns the copied text; it does not retain the borrowed model.
(: callback (-> (Borrow Model) (-> String)))
(define (callback model)
  (let ((text (Model-title model)))
    (lambda () text)))

(let ((model (Model "ready" (once (lambda () (write-line "finished"))))))
  (let ((read (with-borrow (borrowed model)
                           (let ((alias borrowed))
                             (write-line (title alias))
                             (write-line (forward borrowed (Reader-read (identity (Reader title)))))
                             (callback alias)))))
    (match model
      ((Model _ work) (work)))
    (write-line (read))))
