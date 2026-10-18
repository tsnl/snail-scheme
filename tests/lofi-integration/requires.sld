(import
 (lofi base))

(typeclass Identity (T) (: identity (-> T T)))
(instance identity-i32 (Identity I32) (identity (lambda (value) value)))
(instance identity-bool (Identity Bool) (identity (lambda (value) value)))

(def twice (All (T) (requires (Identity T) (Default T)) (-> T T))
     (lambda (value)
       (begin (ann (default) T) (identity (identity value)))))
(def count (All (T) (requires (Default T)) (-> I32))
     (lambda () (begin (ann (default) T) 22)))
(def ground (All () (requires (Identity I32)) (-> I32 I32))
     (lambda (value) (identity value)))

(if (twice #t)
    (+ (ground ((inst twice I32) 20)) ((inst count I32)))
    0)
