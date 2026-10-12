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
            ((type-subtype? type 'ExactInteger) 'i64)
            ((eq? type 'InexactReal) 'f64)
            ((type-subtype? type 'Boolean) 'boolean)
            ((eq? type 'Char) 'character)
            ((nominal-type? type) '(ref $record))
            (else (case type
                    ((String) '(ref $text_object)) ((Pair) '(ref $pair))
                    ((Vector) '(ref $vector)) ((Bytevector) '(ref $bytevector))
                    ((Procedure) '(ref $closure)) ((Record) '(ref $record))
                    ((Complex) '(ref $complex)) (else 'eqref)))))

    (define (representation-wasm representation)
      (if (memq representation '(boolean character)) 'i32 representation))

    (define (box-representation value representation)
      (case representation
        ((i64) `(call $pack_integer ,value))
        ((f64) `(struct.new $float ,value))
        ((boolean) `(call $pack_boolean ,value))
        ((character) `(call $pack_character ,value))
        (else value)))

    ;; Call sites establish semantic membership and single-value cardinality.
    ;; These visible casts/unpacks only cross representations; they never infer
    ;; membership, weaken a checked i32 range, or normalize a result envelope.
    (define (unbox-representation value representation)
      (case representation
        ((eqref) value)
        ((i64) `(call $known_integer_value ,value))
        ((f64) `(struct.get $float 0 (ref.cast (ref $float) ,value)))
        ((boolean) `(call $truthy ,value))
        ((character) `(i32.sub (struct.get $atom 0 (ref.cast (ref $atom) ,value)) (i32.const 256)))
        (else `(ref.cast ,representation ,value))))

    (define (convert-representation value from to)
      (if (equal? from to) value
          (unbox-representation (box-representation value from) to)))))
