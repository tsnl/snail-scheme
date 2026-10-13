(define-library (snail-scheme wasm-abi)
  (export abi-definitions)
  (import (scheme base))
  (begin

    ;; ---- Value categories ----

    ;; A membership query tests the requested shape, not every other category.
    ;; Keep its predicates shared with classification so successful checks and
    ;; failure diagnostics agree. The integer predicate accepts both layouts.
    (define object-kind-tests
      '((4 (call $is_integer (local.get $value)))
        (9 (ref.test (ref $text_object) (local.get $value)))
        (5 (ref.test (ref $float) (local.get $value)))
        (7 (ref.test (ref $pair) (local.get $value)))
        (8 (i32.or (ref.test (ref $slots) (local.get $value)) (ref.test (ref $vector_object) (local.get $value))))
        (11 (ref.test (ref $bytevector) (local.get $value)))
        (12 (ref.test (ref $closure) (local.get $value)))
        (13 (i32.or (ref.test (ref $record) (local.get $value))
                    (ref.test (ref $record_type) (local.get $value))))
        (14 (ref.test (ref $extension) (local.get $value)))
        (15 (ref.test (ref $values) (local.get $value)))
        (17 (ref.test (ref $complex) (local.get $value)))))

    (define (classify-object test)
      `(if ,(cadr test) (then (return (i32.const ,(car test))))))
    (define (test-object-kind test)
      `(if (i32.eq (local.get $kind) (i32.const ,(car test)))
           (then (return ,(cadr test)))))

    (define kind-definitions
      `((func $abi_atom_kind (param $tag i32) (result i32)
              ;; ABI categories describe tags; scalar validity is checked on
              ;; extraction. Preserve Character for every nonnegative tag >= 6.
              (if (i32.lt_s (local.get $tag) (i32.const 0)) (then (return (i32.const 10))))
              (if (i32.lt_u (local.get $tag) (i32.const 2)) (then (return (i32.const 1))))
              (if (i32.eq (local.get $tag) (i32.const 2)) (then (return (i32.const 2))))
              (if (i32.eq (local.get $tag) (i32.const 3)) (then (return (i32.const 0))))
              (if (i32.eq (local.get $tag) (i32.const 4)) (then (return (i32.const 3))))
              (if (i32.eq (local.get $tag) (i32.const 5)) (then (return (i32.const 16))))
              (i32.const 6))
        (func (export "kind") (param $handle i32) (result i32)
              (local $value eqref)
              (local.set $value (call $abi_get (local.get $handle)))
              ,(classify-object (car object-kind-tests))
              (if (ref.test (ref $atom) (local.get $value))
                  (then (return (call $abi_atom_kind
                                      (struct.get $atom 0 (ref.cast (ref $atom) (local.get $value)))))))
              ,@(map classify-object (cdr object-kind-tests))
              unreachable)
        (func (export "is_kind") (param $handle i32) (param $kind i32) (result i32)
              (local $value eqref)
              ;; Resolve even for an unknown category: stale handles still trap.
              (local.set $value (call $abi_get (local.get $handle)))
              ,@(map test-object-kind object-kind-tests)
              (if (result i32) (ref.test (ref $atom) (local.get $value))
                  (then (i32.eq (local.get $kind)
                                (call $abi_atom_kind
                                      (struct.get $atom 0 (ref.cast (ref $atom) (local.get $value))))))
                  (else (i32.const 0))))))

    (define core-definitions
      '(
        ;; ABI v0: owned integer handles into a GC-reference table. Each exported
        ;; getter returning a handle allocates a distinct root; callers release it.
        ;; A released slot is reusable, so raw handles are unsafe, instance-local
        ;; capabilities. The Rust SDK prevents duplication and use after release.

        ;; ---- Root ownership ----

        (type $abi_links (array (mut i32)))
        (table $abi_roots 16 eqref)
        (global $abi_links (mut (ref $abi_links)) (array.new $abi_links (i32.const -2) (i32.const 16)))
        (global $abi_used (mut i32) (i32.const 0))
        (global $abi_free (mut i32) (i32.const -2))
        (global $abi_live (export "abi_live_roots") (mut i32) (i32.const 0))

        (func $abi_get (param $handle i32) (result eqref)
              (if (i32.ge_u (local.get $handle) (global.get $abi_used)) (then unreachable))
              (if (i32.ne (array.get $abi_links (global.get $abi_links) (local.get $handle)) (i32.const -1))
                  (then unreachable))
              (table.get $abi_roots (local.get $handle)))

        (func $abi_grow
              (local $old i32) (local $links (ref $abi_links))
              (local.set $old (table.size $abi_roots))
              (local.set $links (array.new $abi_links (i32.const -2) (i32.mul (local.get $old) (i32.const 2))))
              (array.copy $abi_links $abi_links (local.get $links) (i32.const 0)
                          (global.get $abi_links) (i32.const 0) (local.get $old))
              (if (i32.eq (table.grow $abi_roots (ref.null eq) (local.get $old)) (i32.const -1))
                  (then unreachable))
              (global.set $abi_links (local.get $links)))

        (func $abi_root (param $value eqref) (result i32)
              (local $slot i32)
              (if (i32.ne (global.get $abi_free) (i32.const -2))
                  (then
                   (local.set $slot (global.get $abi_free))
                   (global.set $abi_free (array.get $abi_links (global.get $abi_links) (local.get $slot))))
                  (else
                   (local.set $slot (global.get $abi_used))
                   (if (i32.eq (local.get $slot) (table.size $abi_roots)) (then (call $abi_grow)))
                   (global.set $abi_used (i32.add (local.get $slot) (i32.const 1)))))
              (array.set $abi_links (global.get $abi_links) (local.get $slot) (i32.const -1))
              (table.set $abi_roots (local.get $slot) (local.get $value))
              (global.set $abi_live (i32.add (global.get $abi_live) (i32.const 1)))
              (local.get $slot))

        (func $abi_release (export "release") (param $handle i32)
              (drop (call $abi_get (local.get $handle)))
              (table.set $abi_roots (local.get $handle) (ref.null eq))
              (array.set $abi_links (global.get $abi_links) (local.get $handle) (global.get $abi_free))
              (global.set $abi_free (local.get $handle))
              (global.set $abi_live (i32.sub (global.get $abi_live) (i32.const 1))))

        (func $abi_take (param $handle i32) (result eqref)
              (local $value eqref)
              (local.set $value (call $abi_get (local.get $handle)))
              (call $abi_release (local.get $handle))
              (local.get $value))

        (func (export "retain") (param $handle i32) (result i32)
              (call $abi_root (call $abi_get (local.get $handle))))
        (func (export "same") (param $a i32) (param $b i32) (result i32)
              (call $same (call $abi_get (local.get $a)) (call $abi_get (local.get $b))))
        (func (export "identity_hash") (param $handle i32) (result i32)
              (call $identity_hash (call $abi_get (local.get $handle))))
        (func (export "literal_symbol_names") (result i32)
              (call $abi_root (global.get $symbol_names)))

        ;; ---- Constructors ----

        (func (export "integer") (param $value i64) (result i32)
              (call $abi_root (call $pack_integer (local.get $value))))
        (func (export "real") (param $value f64) (result i32)
              (call $abi_root (struct.new $float (local.get $value))))

        (func (export "complex") (param $real i32) (param $imag i32) (result i32)
              (call $abi_root (call $make_complex (call $abi_get (local.get $real)) (call $abi_get (local.get $imag)))))

        (func (export "real_part") (param $root i32) (result i32)
              (call $abi_root (call $real_part (call $abi_get (local.get $root)))))

        (func (export "imag_part") (param $root i32) (result i32)
              (call $abi_root (call $imag_part (call $abi_get (local.get $root)))))
        (func (export "atom") (param $tag i32) (result i32)
              (if (i32.eqz (local.get $tag)) (then (return (call $abi_root (global.get $false)))))
              (if (i32.eq (local.get $tag) (i32.const 1)) (then (return (call $abi_root (global.get $true)))))
              (if (i32.eq (local.get $tag) (i32.const 2)) (then (return (call $abi_root (global.get $nil)))))
              (if (i32.eq (local.get $tag) (i32.const 3)) (then (return (call $abi_root (global.get $unspecified)))))
              (if (i32.eq (local.get $tag) (i32.const 4)) (then (return (call $abi_root (global.get $eof)))))
              (call $abi_root (struct.new $atom (local.get $tag))))
        (func (export "pair") (param $car i32) (param $cdr i32) (result i32)
              (call $abi_root (struct.new $pair:boxed (call $abi_get (local.get $car)) (call $abi_get (local.get $cdr)))))

        (func (export "pair_set_car") (param $root i32) (param $value i32)
              (call $pair_set_car (ref.cast (ref $pair) (call $abi_get (local.get $root))) (call $abi_get (local.get $value))))

        (func (export "pair_set_cdr") (param $root i32) (param $value i32)
              (call $pair_set_cdr (ref.cast (ref $pair) (call $abi_get (local.get $root))) (call $abi_get (local.get $value))))
        (func (export "extension") (param $kind i32) (param $id i32) (result i32)
              (local $object (ref $extension))
              (local.set $object (struct.new $extension (local.get $kind) (local.get $id)))
              (call $host_register_finalizer (local.get $object) (local.get $kind) (local.get $id))
              (call $abi_root (local.get $object)))
        (func (export "vector_new") (param $length i32) (result i32)
              (call $abi_root (call $vector_new:boxed (local.get $length) (global.get $unspecified))))

        (func (export "values") (param $root i32) (result i32)
              (call $abi_root (struct.new $values (call $abi_get (local.get $root)))))
        (func (export "vector_set") (param $root i32) (param $index i32) (param $value i32)
              (local $object eqref) (local.set $object (call $abi_get (local.get $root)))
              (if (ref.test (ref $vector_object) (local.get $object))
                  (then (call $vector_set (ref.cast (ref $vector_object) (local.get $object)) (local.get $index) (call $abi_get (local.get $value))))
                  (else (array.set $slots (ref.cast (ref $slots) (local.get $object)) (local.get $index) (call $abi_get (local.get $value))))))
        (func (export "string_new") (param $length i32) (result i32)
              (call $abi_root (struct.new $text_object (i32.const 0) (array.new $text (i32.const 0) (local.get $length)))))
        (func (export "string_set") (param $root i32) (param $index i32) (param $value i32)
              (array.set $text (struct.get $text_object 1 (ref.cast (ref $text_object) (call $abi_get (local.get $root)))) (local.get $index) (local.get $value)))
        (func (export "bytes_new") (param $length i32) (result i32)
              (call $abi_root (struct.new $bytevector (array.new $bytes (i32.const 0) (local.get $length)))))
        (func (export "byte_set") (param $root i32) (param $index i32) (param $value i32)
              (array.set $bytes (struct.get $bytevector 0 (ref.cast (ref $bytevector) (call $abi_get (local.get $root)))) (local.get $index) (local.get $value)))

        ;; ---- Accessors ----

        (func (export "as_integer") (param $root i32) (result i64)
              (call $integer_value (call $abi_get (local.get $root))))
        (func (export "as_real") (param $root i32) (result f64)
              (call $float_value (call $abi_get (local.get $root))))
        (func (export "atom_value") (param $root i32) (result i32)
              (struct.get $atom 0 (ref.cast (ref $atom) (call $abi_get (local.get $root)))))
        (func (export "length") (param $root i32) (result i32)
              (local $value eqref)
              (local.set $value (call $abi_get (local.get $root)))
              (if (ref.test (ref $vector_object) (local.get $value))
                  (then (return (call $vector_length (ref.cast (ref $vector_object) (local.get $value))))))
              (if (ref.test (ref $slots) (local.get $value))
                  (then (return (array.len (ref.cast (ref $slots) (local.get $value))))))
              (if (ref.test (ref $values) (local.get $value))
                  (then (return (call $sequence_length (struct.get $values 0 (ref.cast (ref $values) (local.get $value)))))))
              (if (ref.test (ref $text_object) (local.get $value))
                  (then (return (array.len (struct.get $text_object 1 (ref.cast (ref $text_object) (local.get $value)))))))
              (if (call $is_symbol (local.get $value))
                  (then (return (call $rust_symbol_length
                                      (i32.and (struct.get $atom 0 (ref.cast (ref $atom) (local.get $value)))
                                               (i32.const 2147483647))))))
              (array.len (struct.get $bytevector 0 (ref.cast (ref $bytevector) (local.get $value)))))
        (func (export "at") (param $root i32) (param $index i32) (result i32)
              (local $value eqref) (local $items eqref)
              (local.set $value (call $abi_get (local.get $root)))
              (local.set $items (if (result eqref) (ref.test (ref $values) (local.get $value))
                                    (then (struct.get $values 0 (ref.cast (ref $values) (local.get $value))))
                                    (else (local.get $value))))
              (call $abi_root (call $sequence_ref (local.get $items) (local.get $index))))
        (func (export "char_at") (param $root i32) (param $index i32) (result i32)
              (local $value eqref)
              (local.set $value (call $abi_get (local.get $root)))
              (if (call $is_symbol (local.get $value))
                  (then (return (call $rust_symbol_character
                                      (i32.and (struct.get $atom 0 (ref.cast (ref $atom) (local.get $value)))
                                               (i32.const 2147483647)) (local.get $index)))))
              (array.get $text (struct.get $text_object 1 (ref.cast (ref $text_object) (local.get $value))) (local.get $index)))
        (func (export "byte_at") (param $root i32) (param $index i32) (result i32)
              (array.get_u $bytes (struct.get $bytevector 0 (ref.cast (ref $bytevector) (call $abi_get (local.get $root)))) (local.get $index)))
        (func (export "car") (param $root i32) (result i32)
              (call $abi_root (call $pair_car (ref.cast (ref $pair) (call $abi_get (local.get $root))))))
        (func (export "cdr") (param $root i32) (result i32)
              (call $abi_root (call $pair_cdr (ref.cast (ref $pair) (call $abi_get (local.get $root))))))
        (func (export "extension_kind") (param $root i32) (result i32)
              (struct.get $extension 0 (ref.cast (ref $extension) (call $abi_get (local.get $root)))))
        (func (export "extension_id") (param $root i32) (result i32)
              (struct.get $extension 1 (ref.cast (ref $extension) (call $abi_get (local.get $root)))))

        ;; Ordinary Rust-to-Scheme callback. Both incoming handles remain borrowed;
        ;; the returned root is owned. Future continuation transfers must not cross
        ;; this call boundary. Scheme callbacks can allocate: all Rust roots stay live.
        ;; Reentry has its own return obligations; it never inherits the host caller's.
        (func (export "call") (param $procedure i32) (param $arguments i32) (result i32)
              (call $abi_root (call $apply (call $abi_get (local.get $procedure))
                                    (call $sequence_slots (call $abi_get (local.get $arguments))) (ref.null $result_context))))
        ))

    (define abi-definitions (append core-definitions kind-definitions))
    ))
