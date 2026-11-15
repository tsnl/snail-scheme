;; The operations the backend implements directly, each declared with its
;; type. `(primitive name type)` is accepted only here: as `extern` declares
;; a foreign function, it declares an operation the compiler supplies, and
;; binds `name` to the global `prim:name`, the name the checker, mono and the
;; backend know it by. Other libraries import the names they build on, as
;; (snail core base) does. The library has no module of its own, since
;; nothing it declares has a body.
;;
;; A generic type quantifies its variables in the order they first occur,
;; A for a type and e for the rest of a row. `mut` marks operations on
;; mutable storage; everything else is total, though some can trap.
(define-library (snail core primitive)
  (export
   unit panic unsafe-total unsafe-cast
   cache lru-cache unsafe-effectful-cache unsafe-effectful-lru-cache
   inherit-handlers
   i32-add i32-sub i32-mul i32-quotient i32-remainder i32-and i32-or i32-xor
   i32-shift-left i32-shift-right i32-shift-right/logical i32-eq i32-lt i32-le i32-gt i32-ge
   i64-add i64-sub i64-mul i64-quotient i64-remainder i64-and i64-or i64-xor
   i64-shift-left i64-shift-right i64-shift-right/logical i64-eq i64-lt i64-le i64-gt i64-ge
   f32-add f32-sub f32-mul f32-div f32-min f32-max f32-eq f32-lt f32-le f32-gt f32-ge
   f32-sqrt f32-abs f32-negate f32-floor f32-ceiling f32-truncate f32-round
   f64-add f64-sub f64-mul f64-div f64-min f64-max f64-eq f64-lt f64-le f64-gt f64-ge
   f64-sqrt f64-abs f64-negate f64-floor f64-ceiling f64-truncate f64-round
   i32->i64
   i64->i32
   i64->f64
   f64->i64
   i32->f64
   f64->i32
   i32->f32
   f32->i32
   i64->f32
   f32->i64
   f32->f64
   f64->f32
   f32->bits bits->f32 f64->bits bits->f64 bool->i32 i32->bool u8->i32 i32->u8 char->i32 i32->char
   string-length
   string-ref
   string-append
   substring
   string=?
   string-compare
   make-string
   string-generate
   string->vector vector->string
   vector-length vector-ref vector-append subvector make-vector vector-set vector-generate
   vector vector-set! vector-copy vector-copy!
   set!)
  (import
   (snail core forms))
  (begin

    ;; ---- Control ----

    ;; `unsafe-total` calls a thunk and discards its effects, unchecked: the
    ;; standard library uses it where the checker cannot confirm that
    ;; mutation stays in storage the function allocates. `unsafe-cast` makes
    ;; a function of whatever type is expected from a Funcref, a function
    ;; another module exports (`(snail shell wasm)`), checking only its Wasm
    ;; type. It constructs a closure that calls the exported code.
    (primitive unit (Fn → Unit))
    (primitive panic (∀ (A) (Fn String → A)))
    (primitive unsafe-total (∀ (A e) (Fn (Fn → A ! e) → A)))
    (primitive unsafe-cast (∀ (A) (Fn Funcref → A)))

    ;; ---- Memoized functions ----

    ;; F stands for an entire function signature of any arity. The checker
    ;; requires an empty outward effect row for the safe wrappers, before
    ;; specialization erases ordinary effects. Preparation checks all four
    ;; wrappers' keys can be compared and callbacks cannot suspend.
    (primitive cache (∀ (F) (Fn F → F)))
    (primitive lru-cache (∀ (F) (Fn I64 F → F)))
    (primitive unsafe-effectful-cache (∀ (F) (Fn F → F)))
    (primitive unsafe-effectful-lru-cache (∀ (F) (Fn I64 F → F)))

    ;; ---- Inherited handlers ----

    ;; `inherit-handlers` closes a thunk over the handlers in scope where it
    ;; is called: the function it makes runs the thunk under those handlers,
    ;; wherever it is called. The caller is charged the thunk's row, as
    ;; dispatching is. The handlers answer the effects
    ;; the row declares; what remains, `mut` and the effects the host
    ;; implements, happens when the function runs, so it performs `host`,
    ;; which only code that may run anything the host implements, such as a
    ;; scheduler, can perform. The thunk may not yield to a control effect,
    ;; since the handles it would yield to may have returned by then.
    (primitive inherit-handlers
               (∀ (A e) (Fn (Fn → A ! e) → (Fn → A ! host) ! e)))

    ;; ---- Integers ----

    (primitive i32-add (Fn I32 I32 → I32))
    (primitive i32-sub (Fn I32 I32 → I32))
    (primitive i32-mul (Fn I32 I32 → I32))
    (primitive i32-quotient (Fn I32 I32 → I32))
    (primitive i32-remainder (Fn I32 I32 → I32))
    (primitive i32-and (Fn I32 I32 → I32))
    (primitive i32-or (Fn I32 I32 → I32))
    (primitive i32-xor (Fn I32 I32 → I32))
    (primitive i32-shift-left (Fn I32 I32 → I32))
    (primitive i32-shift-right (Fn I32 I32 → I32))
    (primitive i32-shift-right/logical (Fn I32 I32 → I32))
    (primitive i32-eq (Fn I32 I32 → Bool))
    (primitive i32-lt (Fn I32 I32 → Bool))
    (primitive i32-le (Fn I32 I32 → Bool))
    (primitive i32-gt (Fn I32 I32 → Bool))
    (primitive i32-ge (Fn I32 I32 → Bool))
    (primitive i64-add (Fn I64 I64 → I64))
    (primitive i64-sub (Fn I64 I64 → I64))
    (primitive i64-mul (Fn I64 I64 → I64))
    (primitive i64-quotient (Fn I64 I64 → I64))
    (primitive i64-remainder (Fn I64 I64 → I64))
    (primitive i64-and (Fn I64 I64 → I64))
    (primitive i64-or (Fn I64 I64 → I64))
    (primitive i64-xor (Fn I64 I64 → I64))
    (primitive i64-shift-left (Fn I64 I64 → I64))
    (primitive i64-shift-right (Fn I64 I64 → I64))
    (primitive i64-shift-right/logical (Fn I64 I64 → I64))
    (primitive i64-eq (Fn I64 I64 → Bool))
    (primitive i64-lt (Fn I64 I64 → Bool))
    (primitive i64-le (Fn I64 I64 → Bool))
    (primitive i64-gt (Fn I64 I64 → Bool))
    (primitive i64-ge (Fn I64 I64 → Bool))

    ;; ---- Floats ----

    (primitive f32-add (Fn F32 F32 → F32))
    (primitive f32-sub (Fn F32 F32 → F32))
    (primitive f32-mul (Fn F32 F32 → F32))
    (primitive f32-div (Fn F32 F32 → F32))
    (primitive f32-min (Fn F32 F32 → F32))
    (primitive f32-max (Fn F32 F32 → F32))
    (primitive f32-eq (Fn F32 F32 → Bool))
    (primitive f32-lt (Fn F32 F32 → Bool))
    (primitive f32-le (Fn F32 F32 → Bool))
    (primitive f32-gt (Fn F32 F32 → Bool))
    (primitive f32-ge (Fn F32 F32 → Bool))
    (primitive f32-sqrt (Fn F32 → F32))
    (primitive f32-abs (Fn F32 → F32))
    (primitive f32-negate (Fn F32 → F32))
    (primitive f32-floor (Fn F32 → F32))
    (primitive f32-ceiling (Fn F32 → F32))
    (primitive f32-truncate (Fn F32 → F32))
    (primitive f32-round (Fn F32 → F32))
    (primitive f64-add (Fn F64 F64 → F64))
    (primitive f64-sub (Fn F64 F64 → F64))
    (primitive f64-mul (Fn F64 F64 → F64))
    (primitive f64-div (Fn F64 F64 → F64))
    (primitive f64-min (Fn F64 F64 → F64))
    (primitive f64-max (Fn F64 F64 → F64))
    (primitive f64-eq (Fn F64 F64 → Bool))
    (primitive f64-lt (Fn F64 F64 → Bool))
    (primitive f64-le (Fn F64 F64 → Bool))
    (primitive f64-gt (Fn F64 F64 → Bool))
    (primitive f64-ge (Fn F64 F64 → Bool))
    (primitive f64-sqrt (Fn F64 → F64))
    (primitive f64-abs (Fn F64 → F64))
    (primitive f64-negate (Fn F64 → F64))
    (primitive f64-floor (Fn F64 → F64))
    (primitive f64-ceiling (Fn F64 → F64))
    (primitive f64-truncate (Fn F64 → F64))
    (primitive f64-round (Fn F64 → F64))

    ;; ---- Conversions ----

    (primitive i32->i64 (Fn I32 → I64))
    (primitive i64->i32 (Fn I64 → I32))
    (primitive i64->f64 (Fn I64 → F64))
    (primitive f64->i64 (Fn F64 → I64))
    (primitive i32->f64 (Fn I32 → F64))
    (primitive f64->i32 (Fn F64 → I32))
    (primitive i32->f32 (Fn I32 → F32))
    (primitive f32->i32 (Fn F32 → I32))
    (primitive i64->f32 (Fn I64 → F32))
    (primitive f32->i64 (Fn F32 → I64))
    (primitive f32->f64 (Fn F32 → F64))
    (primitive f64->f32 (Fn F64 → F32))
    (primitive f32->bits (Fn F32 → I32))
    (primitive bits->f32 (Fn I32 → F32))
    (primitive f64->bits (Fn F64 → I64))
    (primitive bits->f64 (Fn I64 → F64))
    (primitive bool->i32 (Fn Bool → I32))
    (primitive i32->bool (Fn I32 → Bool))
    (primitive u8->i32 (Fn U8 → I32))
    (primitive i32->u8 (Fn I32 → U8))
    (primitive char->i32 (Fn Char → I32))
    (primitive i32->char (Fn I32 → Char))

    ;; ---- Text ----

    (primitive string-length (Fn String → I64))
    (primitive string-ref (Fn String I64 → Char))
    (primitive string-append (Fn String String → String))
    (primitive substring (Fn String I64 I64 → String))
    (primitive string=? (Fn String String → Bool))
    (primitive string-compare (Fn String String → I32))
    (primitive make-string (Fn I64 Char → String))
    (primitive string-generate (∀ (e) (Fn I64 (Fn I64 → Char ! e) → String ! e)))
    (primitive string->vector (Fn String → (Vector Char)))
    (primitive vector->string (Fn (Vector Char) → String))

    ;; ---- Vectors ----

    ;; A vector shares its mutable slots.
    (primitive vector (∀ (A) (Fn → (Vector A))))
    (primitive vector-length (∀ (A) (Fn (Vector A) → I64)))
    (primitive vector-ref (∀ (A) (Fn (Vector A) I64 → A)))
    (primitive vector-append (∀ (A) (Fn (Vector A) (Vector A) → (Vector A))))
    (primitive subvector (∀ (A) (Fn (Vector A) I64 I64 → (Vector A))))
    (primitive make-vector (∀ (A) (Fn I64 A → (Vector A))))
    (primitive vector-set (∀ (A) (Fn (Vector A) I64 A → (Vector A))))
    (primitive vector-generate (∀ (A e) (Fn I64 (Fn I64 → A ! e) → (Vector A) ! e)))

    (primitive vector-set! (∀ (A) (Fn (Vector A) I64 A → Unit ! mut)))
    (primitive vector-copy (∀ (A) (Fn (Vector A) → (Vector A))))
    (primitive vector-copy! (∀ (A) (Fn (Vector A) I64 (Vector A) I64 I64 → Unit ! mut)))

    ;; `set!` writes a place: a declared field, `(● record count)`, which
    ;; the checker resolves directly.
    (primitive set! (∀ (A) (Fn A A → Unit ! mut)))))
