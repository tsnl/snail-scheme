(import
 (snail core base)
 (snail core io))

(struct Model
  ((title String)
   (work (FnOnce → Unit ! output-port))))

(define (title (model (Rc Model))) (→ String) (! mut output-port)
  (● model title))

(define (forward (value T) (read (Fn T → String ! e)))
  (→ String) (! e) (∀ T e) (⊨ (Copy T) (Drop e T))
  (read value))

(struct Reader
  ((read (Fn (Rc Model) → String ! mut output-port))))

;; This callback keeps the copied text and can outlive the model.
(define (callback (model (Rc Model))) (→ (Fn → String)) (! mut output-port)
  (let ((text (● model title)))
    (lambda () text)))

(define (main) (→ Unit) (! mut output-port)
  (let ((read
         (let ((model (rc (Model "ready" (once (lambda () (write-line "finished")))))))
           (write-line (title model))
           (write-line (forward model (● (Reader title) read)))
           ((replace! (● model work) (once (lambda () (unit)))))
           (callback model))))
    (write-line (read)))
  (unit))
