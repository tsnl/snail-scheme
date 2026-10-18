(import
 (lofi primitive)
 (macro requires))

(data Copy (T)
  (shadow-copy
   (value T)))
(def T 999)
(define-copy duplicate)
(duplicate 42)
