;; Storage choices and explicit conversions shared by every emitted procedure.
;; Semantic types retain their contracts even when they use identical storage.
(define-library (snail-scheme wasm-representation)
  (export representation-optimizations-enabled type-representation representation-wasm box-representation unbox-representation
          convert-representation)
  (import (scheme base) (snail-scheme types))
  (begin

    ;; ---- Storage and the generic Scheme boundary ----

    (define representation-optimizations-enabled (make-parameter #t))

    (define (type-representation type)
      (cond ((type-subtype? type 'Never) 'eqref)
            ((eq? type 'WasmI32) '(i32 integer))
            ((eq? type 'WasmF32) 'f32)
            ((type-subtype? type 'ExactInteger) 'i64)
            ((eq? type 'InexactReal) 'f64)
            ((type-subtype? type 'Boolean) '(i32 boolean))
            ((eq? type 'Char) '(i32 character))
            ((nominal-type? type) '(ref $record))
            (else (case type
                    ((String) '(ref $text_object)) ((Pair) '(ref $pair))
                    ((Vector) '(ref $vector_object)) ((Bytevector) '(ref $bytevector))
                    ((Procedure) '(ref $closure)) ((Record) '(ref $record))
                    ((Complex) '(ref $complex)) (else 'eqref)))))

    (define (representation-wasm representation)
      (if (and (pair? representation) (eq? (car representation) 'i32)) 'i32 representation))

    (define (representation-meaning representation)
      (if (and (pair? representation) (eq? (car representation) 'i32))
          (cadr representation) representation))

    (define (box-representation value representation)
      (case (representation-meaning representation)
        ((integer) `(call $pack_integer (i64.extend_i32_s ,value)))
        ((i64) `(call $pack_integer ,value))
        ((f32) `(struct.new $float (f64.promote_f32 ,value)))
        ((f64) `(struct.new $float ,value))
        ((boolean) `(call $pack_boolean ,value))
        ((character) `(call $pack_character ,value))
        (else value)))

    ;; Call sites establish semantic membership and single-value cardinality.
    ;; These visible casts/unpacks only cross representations; they never infer
    ;; membership, weaken a checked i32 range, or normalize a result envelope.
    (define (unbox-representation value representation)
      (case (representation-meaning representation)
        ((eqref) value)
        ((integer) `(i32.wrap_i64 (call $known_integer_value ,value)))
        ((i64) `(call $known_integer_value ,value))
        ((f32) `(f32.demote_f64 (struct.get $float 0 (ref.cast (ref $float) ,value))))
        ((f64) `(struct.get $float 0 (ref.cast (ref $float) ,value)))
        ((boolean) `(call $truthy ,value))
        ((character) `(i32.sub (struct.get $atom 0 (ref.cast (ref $atom) ,value)) (i32.const 256)))
        (else `(ref.cast ,representation ,value))))

    (define (convert-representation value from to)
      (cond ((equal? from to) value)
            ((and (equal? from '(i32 integer)) (eq? to 'i64)) `(i64.extend_i32_s ,value))
            ((and (eq? from 'i64) (equal? to '(i32 integer))) `(i32.wrap_i64 ,value))
            ((and (eq? from 'f32) (eq? to 'f64)) `(f64.promote_f32 ,value))
            ((and (eq? from 'f64) (eq? to 'f32)) `(f32.demote_f64 ,value))
            (else (unbox-representation (box-representation value from) to))))))
