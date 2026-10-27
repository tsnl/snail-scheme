(import
 (snail-core base)
 (snail-core io))

(enum Tree
  (Leaf ((text String)))
  (Branch ((children (List Tree)))))

(: transfer (All (T) (requires (Send T) (Sync T)) (-> T T)))
(define (transfer value) value)

(: nested (All (T) (requires (Send T) (Sync T)) (-> T (List T))))
(define (nested value) (transfer (list value)))

(: checked (All () (requires (Send I64) (Sync I64)) (List I64)))
(define checked (transfer (list (ann 9 I64))))

(display (length (nested (Branch (list (Leaf "safe"))))))
(newline)
(display (vector-ref (transfer (make-vector 3 (ann 7 I64))) 1))
(newline)
(display (length checked))
(newline)
