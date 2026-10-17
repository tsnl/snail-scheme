(import
 (lofi core)
 (lofi base))

;; Later declarations bind their whole groups before earlier bodies resolve.
(def answer (lambda () (identity (stock-ore (stock 42)))))
(begin
  (data Stock ()
    (stock
     (ore I32 stock-ore)))
  (begin
    (typeclass Identity (T)
               (: identity (-> T T)))
    (instance identity-i32 (Identity I32)
              (identity (lambda (value) value)))))
(answer)
