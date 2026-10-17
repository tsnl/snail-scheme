(import
 (lofi core))

(def target (lambda (value) value))
(data Flag ()
  (flag)
  (deriving target))
42
