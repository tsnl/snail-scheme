;; The one place a linear value may rest outside a frame: a slot the
;; runtime owns, shared by tasks that are never on the stack at the same
;; time. `take!` moves the content out and leaves the slot empty, and
;; `put!` fills an empty slot; each traps in the other state, "taken while
;; out" or "changed while out", which catches a host callback reentering a
;; slot whose content is out. An instance is single-threaded, so no other
;; check is needed. The language refuses a cell of a linear value
;; (ownership.sld), and this library alone declares a mutable field beside
;; `Ref`; `(snail shell task)` builds the scheduler's queues and the
;; mailboxes on it. Nothing finalizes a slot's content: whoever put a value
;; in takes it out, or the owner's `close` drains the slot.
(define-library (snail shell slot)
  (export
   UnsafeSlot
   unsafe-slot
   empty-slot
   take!
   put!)
  (import
   (snail core base))
  (begin
    (struct (UnsafeSlot A)
      ((content mut (Option A))))

    (: unsafe-slot (All (A) (-> A (UnsafeSlot A))))
    (define (unsafe-slot value)
      (UnsafeSlot (Some value)))

    (: empty-slot (All (A) (-> (UnsafeSlot A))))
    (define (empty-slot)
      (UnsafeSlot (None)))

    (: take! (All (A) (-> (UnsafeSlot A) A ! mut)))
    (define (take! slot)
      (match (UnsafeSlot-content-replace! slot (None))
        ((Some value) value)
        ((None) (panic "a slot was taken while its content was out"))))

    (: put! (All (A) (-> (UnsafeSlot A) A Unit ! mut)))
    (define (put! slot value)
      (match (UnsafeSlot-content-replace! slot (Some value))
        ((None) (unit))
        ((Some held) (panic "a slot changed while its content was out"))))))
