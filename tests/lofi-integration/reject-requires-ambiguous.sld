(import
 (lofi primitive))

(typeclass Token (T) (: token (-> T)))
(instance token-i32 (Token I32) (token (lambda () 0)))
(def count (All (T) (requires (Token T)) (-> I32))
     (lambda () (begin (ann (token) T) 42)))
(def expected (-> I32) count)
(expected)
