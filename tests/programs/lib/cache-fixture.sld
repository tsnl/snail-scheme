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
    (record Cell
      ((value I64)))
    (record (Slot T)
      ((value (Option T))))
    (define (external-none) (→ (Option I64)) (None))
    (define (external-nil) (→ (List I64)) (Nil))
    (define (one) (→ Cell) (new Cell (value 1)))
    (define (bounded (key I64)) (→ Cell) (new Cell (value key)))
    (define (pair-cell (key I64) (text String)) (→ Cell) (new Cell (value key)))
    (define (snapshot (key Cell)) (→ Cell) (new Cell (value (● key value))))
    (define (float-cell (key F64)) (→ Cell) (new Cell (value (f64->bits key))))
    (define (slot) (→ (Slot T)) (∀ (T)) (new Slot (value (None))))
    (define (memo-slot) (→ (Fn → (Slot I64))) (cache slot))))
