(import
 (snail core base)
 (snail core io))

(struct Model
  ((count (Ref I64))
   (work (dyn (FnOnce -> Unit)))))

;; A Copy field holding a cell leaves the borrow as the cell itself, so a
;; borrowed model can be counted through: the loan is read-only one level
;; deep, and a shared cell is writable from every holder.
(: bump (impl (Fn (Borrow Model) -> Unit ! mut)))
(define (bump model)
  (let ((cell (::count model)))
    (ref-set! cell (+ 1 (ref-get cell)))))

(let ((model (Model (ref 0) (once (lambda () (unit))))))
  (with-borrow (read model) (bump read) (bump read))
  (match model
    ((Model count work)
     (work)
     (write-line (show (ref-get count))))))
