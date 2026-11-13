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
  (unsafe-total
   (lambda ()
     (let* ((cell (new Cell (value 3))) (previous (replace! (● cell value) 7)))
       (set! (● cell value) 9)
       (new Shared (left cell) (right cell) (previous previous))))))

(define (folded) (→ String) (string-foldcase "Straße Σςİ ﬃ"))
(define (upper) (→ String) (string-upcase "λß"))
(define (digit) (→ (Option I64)) (char-digit-value #\٣))

(define (main) (→ Unit) (! mut output-port)
  (let ((first (prepared)) (second (prepared)))
    (set! (● first left value) 12)
    (write-line (show (● first right value)))
    (write-line (show (● second right value)))
    (write-line (show (● second previous))))
  (write-line (folded))
  (write-line (upper))
  (match (digit) ((Some value) (write-line (show value))) ((None) (panic "missing digit")))
  (unit))
