(import
 (lofi base))

(data Type (T)
  (Kind->
   (value T)))
(typeclass Constraint (T) (: Evidence (-> T I32)))
(instance type-i32 (Constraint (Type I32))
          (Evidence (lambda (value) (match value ((Kind-> item) item)))))
(def => (-> I32 I32) (lambda (value) value))
(def consume (All (T) (requires (Constraint T)) (-> T I32))
     (lambda (value) (Evidence value)))

(=> (consume (Kind-> 42)))
