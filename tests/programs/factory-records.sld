(import
 (snail core base)
 (snail core io)
 (snail shell text))

(record Cell
  ((value I64)))

(record Shared
  ((left Cell)
   (right Cell)
   (previous I64)))

;; Scratch mutation is confined by an explicit trusted boundary. The
;; factory preserves aliases inside each fresh graph.
(define (prepared) (→ Shared)
  (let* ((cell (new Cell (value 3))) (previous (● cell value)))
    (set! (● cell value) 9)
    (new Shared (left cell) (right cell) (previous previous))))

(define (folded) (→ String) (string-foldcase "Straße Σςİ ﬃ"))
(define (upper) (→ String) (string-upcase "λß"))
(define (digit) (→ (Option I64)) (char-digit-value #\٣))

(define (main (out OutputPort)) (→ Unit)
  (let ((first (prepared)) (second (prepared)))
    (set! (● first left value) 12)
    (write-line out (show (● first right value)))
    (write-line out (show (● second right value)))
    (write-line out (show (● second previous))))
  (write-line out (folded))
  (write-line out (upper))
  (match (digit) ((Some value) (write-line out (show value))) ((None) (panic "missing digit")))
  (unit))
