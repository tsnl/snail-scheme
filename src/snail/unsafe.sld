;; Opt-in concrete storage and Wasm operations. GC references remain managed
;; references, never integer addresses. Normal Scheme arithmetic is unchanged.
(define-library (snail unsafe)
  (export : ann inst All -> U Array Storage Boolean Char
          array.empty array.new array.length array.ref array.set! array.copy! array.append
          storage.eqref storage.i32 storage.i64 storage.f32 storage.f64
          storage.boolean storage.character storage.pair storage.vector storage.string
          storage.bytevector storage.closure storage.record storage.complex
          (rename WasmI32 I32) (rename ExactInteger I64)
          (rename WasmF32 F32) (rename InexactReal F64)
          (rename Any Eqref) (rename Vector VectorRef) (rename Pair PairRef)
          (rename Bytevector BytevectorRef) (rename String StringRef) (rename Procedure ClosureRef)
          (rename Record RecordRef) (rename Complex ComplexRef)
          (rename %wasm.i32.wrap_i64 i32.wrap_i64) (rename %wasm.i64.extend_i32 i64.extend_i32)
          (rename %wasm.f32.demote_f64 f32.demote_f64) (rename %wasm.f64.promote_f32 f64.promote_f32)
          (rename %wasm.i32.add i32.add) (rename %wasm.i32.sub i32.sub) (rename %wasm.i32.mul i32.mul)
          (rename %wasm.i32.eq i32.eq) (rename %wasm.i32.lt_s i32.lt_s) (rename %wasm.i32.lt_u i32.lt_u)
          (rename %wasm.i64.add i64.add) (rename %wasm.i64.sub i64.sub) (rename %wasm.i64.mul i64.mul)
          (rename %wasm.f32.add f32.add) (rename %wasm.f32.sub f32.sub)
          (rename %wasm.f32.mul f32.mul) (rename %wasm.f32.div f32.div)
          (rename %wasm.f64.add f64.add) (rename %wasm.f64.sub f64.sub)
          (rename %wasm.f64.mul f64.mul) (rename %wasm.f64.div f64.div)
          (rename %wasm.vector.length vector.length) (rename %wasm.vector.new vector.new)
          (rename %wasm.vector.new-like vector.new-like)
          (rename %wasm.vector.ref vector.ref) (rename %wasm.vector.set! vector.set!)
          (rename %wasm.vector.copy! vector.copy!))
  (import (scheme base)
          (only (snail-scheme core)
                : ann inst All -> U Array Storage WasmI32 WasmF32 ExactInteger InexactReal Any
                Boolean Char Record Complex Unspecified
                %storage.boxed %storage.integer %storage.real %storage.boolean %storage.character
                %storage.pair %storage.vector %storage.string %storage.bytevector %storage.closure
                %storage.record %storage.complex %storage.i32 %storage.f32
                %array.empty %array.new %array.new-like %array.ref %array.set! %array.copy!
                Vector Pair Bytevector String Procedure
                %wasm.i32.wrap_i64 %wasm.i64.extend_i32 %wasm.f32.demote_f64 %wasm.f64.promote_f32
                %wasm.i32.add %wasm.i32.sub %wasm.i32.mul %wasm.i32.eq %wasm.i32.lt_s %wasm.i32.lt_u
                %wasm.i64.add %wasm.i64.sub %wasm.i64.mul
                %wasm.f32.add %wasm.f32.sub %wasm.f32.mul %wasm.f32.div
                %wasm.f64.add %wasm.f64.sub %wasm.f64.mul %wasm.f64.div
                %wasm.vector.length %wasm.vector.new %wasm.vector.new-like %wasm.vector.ref %wasm.vector.set! %wasm.vector.copy!))
  (begin

    ;; ---- Trusted managed storage witnesses ----

    (: storage.eqref (Storage Any))
    (define storage.eqref (%storage.boxed))
    (: storage.i32 (Storage WasmI32))
    (define storage.i32 (%storage.i32))
    (: storage.i64 (Storage ExactInteger))
    (define storage.i64 (%storage.integer))
    (: storage.f32 (Storage WasmF32))
    (define storage.f32 (%storage.f32))
    (: storage.f64 (Storage InexactReal))
    (define storage.f64 (%storage.real))
    (: storage.boolean (Storage Boolean))
    (define storage.boolean (%storage.boolean))
    (: storage.character (Storage Char))
    (define storage.character (%storage.character))
    (: storage.pair (Storage Pair))
    (define storage.pair (%storage.pair))
    (: storage.vector (Storage Vector))
    (define storage.vector (%storage.vector))
    (: storage.string (Storage String))
    (define storage.string (%storage.string))
    (: storage.bytevector (Storage Bytevector))
    (define storage.bytevector (%storage.bytevector))
    (: storage.closure (Storage Procedure))
    (define storage.closure (%storage.closure))
    (: storage.record (Storage Record))
    (define storage.record (%storage.record))
    (: storage.complex (Storage Complex))
    (define storage.complex (%storage.complex))

    ;; ---- Parametric fixed arrays ----

    (: array.empty (All (A) (-> (Storage A) (Array A))))
    (define (array.empty storage) (%array.empty storage))
    (: array.new (All (A) (-> (Storage A) WasmI32 A (Array A))))
    (define (array.new storage length fill) (%array.new storage length fill))
    (: array.length (All (A) (-> (Array A) WasmI32)))
    (define (array.length array) (%wasm.vector.length array))
    (: array.ref (All (A) (-> (Array A) WasmI32 A)))
    (define (array.ref array index) (%array.ref array index))
    (: array.set! (All (A) (-> (Array A) WasmI32 A Unspecified)))
    (define (array.set! array index value) (%array.set! array index value))
    (: array.copy! (All (A) (-> (Array A) WasmI32 (Array A) WasmI32 WasmI32 Unspecified)))
    (define (array.copy! destination at source start count)
      (%array.copy! destination at source start count))

    ;; The witness supplies the empty result's codec too. Positive lengths use
    ;; a nonempty source as raw initialization; the following copies overwrite
    ;; all slots without calling Scheme or consuming an element envelope.
    (: array.append (All (A) (-> (Storage A) (Array A) (Array A) (Array A))))
    (define (array.append storage left right)
      (let* ((left-size (%wasm.vector.length left))
             (right-size (%wasm.vector.length right))
             (size (%wasm.i32.add left-size right-size))
             (result (%array.new-like storage size (if (= left-size 0) right left))))
        (%array.copy! result 0 left 0 left-size)
        (%array.copy! result left-size right 0 right-size)
        result))))
