(define-library (cache-fixture)
  (export Cell
          Slot
          one
          bounded
          pair-cell
          snapshot
          float-cell
          slot
          memo-slot
          external-none
          external-nil)
  (import
   (snail core base))
  (begin
    (struct Cell
      ((value I64)))
    (struct (Slot T)
      ((value (Option T))))
    (define (external-none) (→ (Option I64)) (None))
    (define (external-nil) (→ (List I64)) (Nil))
    (define (one) (→ Cell) (Cell 1))
    (define (bounded (key I64)) (→ Cell) (Cell key))
    (define (pair-cell (key I64) (text String)) (→ Cell) (Cell key))
    (define (snapshot (key Cell)) (→ Cell) (Cell (● key value)))
    (define (float-cell (key F64)) (→ Cell) (Cell (f64->bits key)))
    (define (slot) (→ (Slot T)) (∀ (T)) (Slot (None)))
    (define (memo-slot) (→ (Fn → (Slot I64))) (cache slot))))
