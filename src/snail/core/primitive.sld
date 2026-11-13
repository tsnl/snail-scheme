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
   unit panic unsafe-total unsafe-cast dynamic-cast any-type-id
   rc rc-get rc-downgrade weak-rc-upgrade
   once call-once inherit-handlers inherit-handlers-1
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
   set!
   replace!)
  (import
   (snail core forms))
  (begin

    (primitive any-type-id (Fn Any → I64))

    ;; ---- Control ----

    ;; `unsafe-total` calls a thunk and discards its effects, unchecked: the
    ;; standard library uses it where the checker cannot confirm that
    ;; mutation stays in storage the function allocates. `unsafe-cast` makes
    ;; a function of whatever type is expected from a Funcref, a function
    ;; another module exports (`(snail shell wasm)`), checking only its Wasm
    ;; type: a closure that calls it, or, at a fn, the code itself. `dynamic-cast` is its checked counterpart, for a function exposed
    ;; with `dynamic`: it calls the importer's policy with the signature the
    ;; expected type has, and makes the function only if the policy accepts
    ;; it, as a vector of one; otherwise the vector is empty, since Option is
    ;; declared later, in (snail core base). The function checks the TypeId
    ;; of each value it receives.
    (primitive unit (Fn → Unit))
    (primitive panic (∀ (A) (Fn String → A)))
    (primitive unsafe-total (∀ (A e) (Fn (Fn → A ! e) → A)))
    (primitive unsafe-cast (∀ (A) (Fn Funcref → A)))
    (primitive dynamic-cast
               (∀ (A)
                  (⊨ (Copy A))
                  (Fn Funcref (Fn (Vector I64) → Bool) → (Vector A))))

    ;; ---- Counted ownership ----

    (primitive rc (∀ (T) (Fn T → (Rc T))))
    (primitive rc-get (∀ (T) (⊨ (Copy T)) (Fn (Rc T) → T)))
    (primitive rc-downgrade (∀ (T) (Fn (Rc T) → (WeakRc T))))
    (primitive weak-rc-upgrade weak-upgrade-signature)

    ;; Lifetime lowering inserts these operations after types are concrete.
    ;; They are deliberately absent from this library's exports.
    (primitive constant-record (∀ (T) (Fn String → T)))
    (primitive constant-vector-shell (∀ (T) (Fn I64 → (Vector T))))
    (primitive constant-vector-fill (∀ (T) (Fn (Vector T) → Unit)))
    (primitive constant-dead-weak (∀ (T) (Fn → (WeakRc T))))
    (primitive constant-vector (∀ (T) (Fn → (Vector T))))
    (primitive current-closure (∀ (T) (Fn → T)))
    (primitive pattern-retain (∀ (T) (Fn T → T)))
    (primitive retain (∀ (T) (Fn T → T)))
    (primitive release (∀ (T) (Fn T → Unit)))
    (primitive rc-new (∀ (T D) (Fn T D → (Rc T))))

    ;; ---- One-shot procedures ----

    ;; A FnOnce owns a procedure that runs once: it is linear, so each one is
    ;; called or dropped exactly once. `once` preserves any procedure signature, and a
    ;; control handler is handed `resume` as another. `discard` releases a
    ;; value and runs nothing: it is what (snail core base)'s `drop` becomes
    ;; for a value whose release runs nothing. Mono names it `prim:discard`,
    ;; so it is not exported: called anywhere else, it would lose a value
    ;; whose release runs something.
    ;; A signature family: F: FnOnce<Signature> becomes dyn FnOnce<Signature>.
    ;; The expander binds this intrinsic with ordinary callable evidence.
    (primitive once callable-once)
    (primitive call-once (∀ (e) (Fn (FnOnce → Unit ! e) → Unit ! e)))
    (primitive discard (∀ (A) (Fn A → Unit)))
    ;; Cleanup inserted by prepare.sld: `with-cleanup` marks a let's value
    ;; with unevaluated cancellation code for the frame saved there;
    ;; it is not an ordinary call. `once-dropping` builds a FnOnce carrying
    ;; the dropper of what it captured, and `drop-once` drops a FnOnce
    ;; unrun, running its dropper. None is written by a program.
    (primitive with-cleanup (∀ (A) (Fn A Unit → A)))
    (primitive once-dropping
               (∀ (A e)
                  (Fn (Fn → A ! e) (Fn → Unit) → (FnOnce → A ! e))))
    (primitive drop-once (∀ (A e) (Fn (FnOnce → A ! e) → Unit ! e)))

    ;; `inherit-handlers` closes a one-shot thunk over the handlers in scope
    ;; where it is called, and `inherit-handlers-1` a procedure of one
    ;; argument, such as a `resume`: the FnOnce it makes runs the procedure
    ;; under those handlers, wherever it is called. The caller is charged
    ;; the procedure's row, as dispatching is. The handlers answer the
    ;; effects the row declares; what remains, `mut` and the effects the
    ;; host implements, happens when the FnOnce runs, so it performs `host`,
    ;; which only code that may run anything the host implements, such as
    ;; a scheduler, can perform. The procedure may not yield to a control
    ;; effect, since the handles it would yield to may have returned by then.
    (primitive inherit-handlers
               (∀ (A e) (Fn (FnOnce → A ! e) → (FnOnce → A ! host) ! e)))
    (primitive inherit-handlers-1
               (∀ (A B e)
                  (Fn (FnOnce A → B ! e) → (FnOnce A → B ! host) ! e)))

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

    ;; A vector shares its mutable slots. Elements must be duplicable; Rc
    ;; lets a slot own a linear resource through a counted, duplicable handle.
    (primitive vector (∀ (A) (⊨ (Copy A)) (Fn → (Vector A))))
    (primitive vector-length (∀ (A) (⊨ (Copy A)) (Fn (Vector A) → I64)))
    (primitive vector-ref (∀ (A) (⊨ (Copy A)) (Fn (Vector A) I64 → A)))
    (primitive vector-append
               (∀ (A) (⊨ (Copy A)) (Fn (Vector A) (Vector A) → (Vector A))))
    (primitive subvector (∀ (A) (⊨ (Copy A)) (Fn (Vector A) I64 I64 → (Vector A))))
    (primitive make-vector (∀ (A) (⊨ (Copy A)) (Fn I64 A → (Vector A))))
    (primitive vector-set (∀ (A) (⊨ (Copy A)) (Fn (Vector A) I64 A → (Vector A))))
    (primitive vector-generate
               (∀ (A e)
                  (⊨ (Copy A))
                  (Fn I64 (Fn I64 → A ! e) → (Vector A) ! e)))

    (primitive vector-set! (∀ (A) (⊨ (Copy A)) (Fn (Vector A) I64 A → Unit ! mut)))
    (primitive vector-copy (∀ (A) (⊨ (Copy A)) (Fn (Vector A) → (Vector A))))
    (primitive vector-copy!
               (∀ (A) (⊨ (Copy A)) (Fn (Vector A) I64 (Vector A) I64 I64 → Unit ! mut)))



    ;; `set!` writes a place and `replace!` swaps a value into one and
    ;; answers the old. A place is a declared field, `(● record count)`,
    ;; which the checker resolves directly. Setting discards the old content, so
    ;; it must be unrestricted; a swap moves it out.
    (primitive set! (∀ (A) (⊨ (Copy A)) (Fn A A → Unit ! mut)))
    (primitive replace! (∀ (A) (Fn A A → A ! mut)))))
