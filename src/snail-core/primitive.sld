;; The operations the backend implements directly, each declared with its
;; type. `(primitive name type)` is accepted only here: as `extern` declares
;; a foreign function, it declares an operation the compiler supplies, and
;; binds `name` to the global `prim:name`, the name the checker, mono and the
;; backend know it by. Other libraries import the names they build on, as
;; (snail-core base) does. The library has no module of its own, since
;; nothing it declares has a body.
;;
;; A generic type quantifies its variables in the order they first occur,
;; A for a type and e for the rest of a row. `mut` marks operations on
;; mutable storage and `tasks` those that reach the runtime's scheduler;
;; everything else is total, though some can trap.
(define-library (snail-core primitive)
  (export
   unit panic unsafe-total unsafe-cast dynamic-cast
   once call-once drop-owned dispatch-local yield-task sleep-task park-task unpark-task current-task
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
   make-array array-length array-ref array-set! array->vector vector->array array-copy! vector-copy!
   ref ref-get ref-set!)
  (import
   (snail-core core))
  (begin

    ;; ---- Control ----

    ;; `unsafe-total` calls a thunk and discards its effects, unchecked: the
    ;; standard library uses it where the checker cannot confirm that
    ;; mutation stays in storage the function allocates. `unsafe-cast` makes
    ;; a function of whatever type is expected from a Funcref, a function
    ;; another module exports (`(snail-core wasm)`), checking only its Wasm
    ;; type. `dynamic-cast` is its checked counterpart, for a function exposed
    ;; with `dynamic`: it calls the importer's policy with the signature the
    ;; expected type has, and makes the function only if the policy accepts
    ;; it, as a vector of one; otherwise the vector is empty, since Option is
    ;; declared later, in (snail-core base). The function checks the TypeId
    ;; of each value it receives.
    (primitive unit (-> Unit))
    (primitive panic (All (A) (-> String A)))
    (primitive unsafe-total (All (A e) (-> (-> A ! e) A)))
    (primitive unsafe-cast (All (A) (-> Funcref A)))
    (primitive dynamic-cast (All (A) (-> Funcref (-> (Vector I64) Bool) (Vector A))))

    ;; ---- Once and tasks ----

    ;; A Once owns a thunk that runs at most once. `drop-owned` takes any
    ;; value, affine ones included, unchecked: the ownership pass calls it
    ;; where a path drops a value it owns, and it releases what an affine
    ;; value holds.
    (primitive once (All (e) (-> (-> Unit ! e) (Once (-> Unit ! e)))))
    (primitive call-once (All (e) (-> (Once (-> Unit ! e)) Unit ! e)))
    (primitive drop-owned (All (A) (-> A Unit)))
    (primitive dispatch-local (All (e) (-> (Once (-> Unit ! e)) Unit ! tasks e)))
    (primitive yield-task (-> Unit ! tasks))
    (primitive sleep-task (-> I64 Unit ! tasks))

    ;; A parked task waits until `unpark-task` names its `current-task` id;
    ;; unparking answers whether that task was parked. They are the wait
    ;; and the wake a queue kept in Snail-Core needs, as `(snail-core task)`'s
    ;; Mailbox keeps one.
    (primitive park-task (-> Unit ! tasks))
    (primitive unpark-task (-> I64 Bool ! tasks))
    (primitive current-task (-> I64 ! tasks))

    ;; ---- Integers ----

    (primitive i32-add (-> I32 I32 I32))
    (primitive i32-sub (-> I32 I32 I32))
    (primitive i32-mul (-> I32 I32 I32))
    (primitive i32-quotient (-> I32 I32 I32))
    (primitive i32-remainder (-> I32 I32 I32))
    (primitive i32-and (-> I32 I32 I32))
    (primitive i32-or (-> I32 I32 I32))
    (primitive i32-xor (-> I32 I32 I32))
    (primitive i32-shift-left (-> I32 I32 I32))
    (primitive i32-shift-right (-> I32 I32 I32))
    (primitive i32-shift-right/logical (-> I32 I32 I32))
    (primitive i32-eq (-> I32 I32 Bool))
    (primitive i32-lt (-> I32 I32 Bool))
    (primitive i32-le (-> I32 I32 Bool))
    (primitive i32-gt (-> I32 I32 Bool))
    (primitive i32-ge (-> I32 I32 Bool))
    (primitive i64-add (-> I64 I64 I64))
    (primitive i64-sub (-> I64 I64 I64))
    (primitive i64-mul (-> I64 I64 I64))
    (primitive i64-quotient (-> I64 I64 I64))
    (primitive i64-remainder (-> I64 I64 I64))
    (primitive i64-and (-> I64 I64 I64))
    (primitive i64-or (-> I64 I64 I64))
    (primitive i64-xor (-> I64 I64 I64))
    (primitive i64-shift-left (-> I64 I64 I64))
    (primitive i64-shift-right (-> I64 I64 I64))
    (primitive i64-shift-right/logical (-> I64 I64 I64))
    (primitive i64-eq (-> I64 I64 Bool))
    (primitive i64-lt (-> I64 I64 Bool))
    (primitive i64-le (-> I64 I64 Bool))
    (primitive i64-gt (-> I64 I64 Bool))
    (primitive i64-ge (-> I64 I64 Bool))

    ;; ---- Floats ----

    (primitive f32-add (-> F32 F32 F32))
    (primitive f32-sub (-> F32 F32 F32))
    (primitive f32-mul (-> F32 F32 F32))
    (primitive f32-div (-> F32 F32 F32))
    (primitive f32-min (-> F32 F32 F32))
    (primitive f32-max (-> F32 F32 F32))
    (primitive f32-eq (-> F32 F32 Bool))
    (primitive f32-lt (-> F32 F32 Bool))
    (primitive f32-le (-> F32 F32 Bool))
    (primitive f32-gt (-> F32 F32 Bool))
    (primitive f32-ge (-> F32 F32 Bool))
    (primitive f32-sqrt (-> F32 F32))
    (primitive f32-abs (-> F32 F32))
    (primitive f32-negate (-> F32 F32))
    (primitive f32-floor (-> F32 F32))
    (primitive f32-ceiling (-> F32 F32))
    (primitive f32-truncate (-> F32 F32))
    (primitive f32-round (-> F32 F32))
    (primitive f64-add (-> F64 F64 F64))
    (primitive f64-sub (-> F64 F64 F64))
    (primitive f64-mul (-> F64 F64 F64))
    (primitive f64-div (-> F64 F64 F64))
    (primitive f64-min (-> F64 F64 F64))
    (primitive f64-max (-> F64 F64 F64))
    (primitive f64-eq (-> F64 F64 Bool))
    (primitive f64-lt (-> F64 F64 Bool))
    (primitive f64-le (-> F64 F64 Bool))
    (primitive f64-gt (-> F64 F64 Bool))
    (primitive f64-ge (-> F64 F64 Bool))
    (primitive f64-sqrt (-> F64 F64))
    (primitive f64-abs (-> F64 F64))
    (primitive f64-negate (-> F64 F64))
    (primitive f64-floor (-> F64 F64))
    (primitive f64-ceiling (-> F64 F64))
    (primitive f64-truncate (-> F64 F64))
    (primitive f64-round (-> F64 F64))

    ;; ---- Conversions ----

    (primitive i32->i64 (-> I32 I64))
    (primitive i64->i32 (-> I64 I32))
    (primitive i64->f64 (-> I64 F64))
    (primitive f64->i64 (-> F64 I64))
    (primitive i32->f64 (-> I32 F64))
    (primitive f64->i32 (-> F64 I32))
    (primitive i32->f32 (-> I32 F32))
    (primitive f32->i32 (-> F32 I32))
    (primitive i64->f32 (-> I64 F32))
    (primitive f32->i64 (-> F32 I64))
    (primitive f32->f64 (-> F32 F64))
    (primitive f64->f32 (-> F64 F32))
    (primitive f32->bits (-> F32 I32))
    (primitive bits->f32 (-> I32 F32))
    (primitive f64->bits (-> F64 I64))
    (primitive bits->f64 (-> I64 F64))
    (primitive bool->i32 (-> Bool I32))
    (primitive i32->bool (-> I32 Bool))
    (primitive u8->i32 (-> U8 I32))
    (primitive i32->u8 (-> I32 U8))
    (primitive char->i32 (-> Char I32))
    (primitive i32->char (-> I32 Char))

    ;; ---- Text ----

    (primitive string-length (-> String I64))
    (primitive string-ref (-> String I64 Char))
    (primitive string-append (-> String String String))
    (primitive substring (-> String I64 I64 String))
    (primitive string=? (-> String String Bool))
    (primitive string-compare (-> String String I32))
    (primitive make-string (-> I64 Char String))
    (primitive string-generate (All (e) (-> I64 (-> I64 Char ! e) String ! e)))
    (primitive string->vector (-> String (Vector Char)))
    (primitive vector->string (-> (Vector Char) String))

    ;; ---- Vectors ----

    (primitive vector-length (All (A) (-> (Vector A) I64)))
    (primitive vector-ref (All (A) (-> (Vector A) I64 A)))
    (primitive vector-append (All (A) (-> (Vector A) (Vector A) (Vector A))))
    (primitive subvector (All (A) (-> (Vector A) I64 I64 (Vector A))))
    (primitive make-vector (All (A) (-> I64 A (Vector A))))
    (primitive vector-set (All (A) (-> (Vector A) I64 A (Vector A))))
    (primitive vector-generate (All (A e) (-> I64 (-> I64 A ! e) (Vector A) ! e)))

    ;; ---- Mutable storage ----

    (primitive make-array (All (A) (-> I64 A (Array A) ! mut)))
    (primitive array-length (All (A) (-> (Array A) I64)))
    (primitive array-ref (All (A) (-> (Array A) I64 A ! mut)))
    (primitive array-set! (All (A) (-> (Array A) I64 A Unit ! mut)))
    (primitive array->vector (All (A) (-> (Array A) (Vector A) ! mut)))
    (primitive vector->array (All (A) (-> (Vector A) (Array A) ! mut)))
    (primitive array-copy! (All (A) (-> (Array A) I64 (Array A) I64 I64 Unit ! mut)))
    (primitive vector-copy! (All (A) (-> (Array A) I64 (Vector A) I64 I64 Unit ! mut)))
    (primitive ref (All (A) (-> A (Ref A) ! mut)))
    (primitive ref-get (All (A) (-> (Ref A) A ! mut)))
    (primitive ref-set! (All (A) (-> (Ref A) A Unit ! mut)))))
