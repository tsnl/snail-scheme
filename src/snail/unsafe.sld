;; Opt-in concrete storage and Wasm operations. GC references remain managed
;; references, never integer addresses. Normal Scheme arithmetic is unchanged.
(define-library (snail unsafe)
  (export : ann inst All -> U
          (rename WasmI32 I32) (rename ExactInteger I64)
          (rename WasmF32 F32) (rename InexactReal F64)
          (rename Any Eqref) (rename Vector VectorRef) (rename Pair PairRef)
          (rename Bytevector BytevectorRef) (rename String StringRef) (rename Procedure ClosureRef)
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
          (rename %wasm.vector.ref vector.ref) (rename %wasm.vector.set! vector.set!)
          (rename %wasm.vector.copy! vector.copy!))
  (import (only (snail-scheme core)
                : ann inst All -> U WasmI32 WasmF32 ExactInteger InexactReal Any
                Vector Pair Bytevector String Procedure
                %wasm.i32.wrap_i64 %wasm.i64.extend_i32 %wasm.f32.demote_f64 %wasm.f64.promote_f32
                %wasm.i32.add %wasm.i32.sub %wasm.i32.mul %wasm.i32.eq %wasm.i32.lt_s %wasm.i32.lt_u
                %wasm.i64.add %wasm.i64.sub %wasm.i64.mul
                %wasm.f32.add %wasm.f32.sub %wasm.f32.mul %wasm.f32.div
                %wasm.f64.add %wasm.f64.sub %wasm.f64.mul %wasm.f64.div
                %wasm.vector.length %wasm.vector.new %wasm.vector.ref %wasm.vector.set! %wasm.vector.copy!)))
