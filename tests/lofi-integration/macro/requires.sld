(define-library (macro requires)
  (import
   (lofi primitive)
   (rename (only (lofi core) All requires) (All Forall) (requires needs)))
  (export define-copy)
  (begin
    (typeclass Copy (T) (: copy-value (-> T T)))
    (instance copy-i32 (Copy I32) (copy-value (lambda (value) value)))
    (def define-copy
         (syntax-rules ()
           ((_ name)
            (def name (Forall (T) (needs (Copy T)) (-> T T))
                 (lambda (value)
                   (begin (def same T value) (copy-value same)))))))))
