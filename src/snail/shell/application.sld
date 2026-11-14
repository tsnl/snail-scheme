;; A program's entry contract. The empty Entry carries only the selected
;; type, so starting an application never requires constructing its state.
;; Instances and their effect rows use the ordinary typeclass rules.
(define-library (snail shell application)
  (export
   Application
   Entry
   start)
  (import
   (snail core base))
  (begin

    (record (Entry A)
      ())

    (typeclass (Application e A)
      (declare (start (entry (Entry A))) (→ Unit) (! e)))))
