;; A builtin has one semantic contract and one concrete Wasm entry. Generic
;; adapters decode Scheme values; proved calls pass scalars and GC references.
;; Storage types never determine boxing: Boolean and Char both occupy i32.
(define-library (snail-scheme wasm-intrinsics)
  (export find-intrinsic intrinsic-name intrinsic-domains intrinsic-result intrinsic-checked?
          intrinsic-entry intrinsic-argument-names intrinsic-unsafe-names intrinsic-definitions
          checked-intrinsic-argument)
  (import (scheme base) (scheme cxr) (snail-scheme types) (snail-scheme wasm-representation))
  (begin

    ;; ---- Semantic contracts and concrete operations ----

    ;; Rows are name, domains, result, source-contract?, and the Wasm body.
    ;; A ? result is a heap read: its eqref can contain a multiple-value envelope.
    ;; Existing dynamic builtins gain no new source rejection from optimization.
    (define intrinsics
      '((vector-length (Vector) ExactInteger #t
                       (i64.extend_i32_u (array.len (local.get $a))))
        (vector-ref (Vector ExactInteger) ? #t
                    (array.get $vector (local.get $a) (call $checked_index (local.get $b))))
        (vector-set! (Vector ExactInteger Any) Unspecified #t
                     (block (result eqref)
                            (array.set $vector (local.get $a) (call $checked_index (local.get $b)) (local.get $c))
                            (global.get $unspecified)))
        (make-vector (ExactInteger) Vector #f
                     (array.new $vector (global.get $unspecified) (call $checked_index (local.get $a))))
        (make-vector (ExactInteger Any) Vector #f
                     (array.new $vector (local.get $b) (call $checked_index (local.get $a))))
        (bytevector-length (Bytevector) ExactInteger #t
                           (i64.extend_i32_u (array.len (struct.get $bytevector 0 (local.get $a)))))
        (bytevector-u8-ref (Bytevector ExactInteger) ExactInteger #t
                           (i64.extend_i32_u (array.get_u $bytes (struct.get $bytevector 0 (local.get $a))
                                                          (call $checked_index (local.get $b)))))
        (char->integer (Char) ExactInteger #t (i64.extend_i32_u (local.get $a)))
        (char=? (Char Char) Boolean #f (i32.eq (local.get $a) (local.get $b)))
        (char<? (Char Char) Boolean #f (i32.lt_u (local.get $a) (local.get $b)))
        (char<=? (Char Char) Boolean #f (i32.le_u (local.get $a) (local.get $b)))
        (char>? (Char Char) Boolean #f (i32.gt_u (local.get $a) (local.get $b)))
        (char>=? (Char Char) Boolean #f (i32.ge_u (local.get $a) (local.get $b)))
        (%wasm.i32.wrap_i64 (ExactInteger) WasmI32 #t (i32.wrap_i64 (local.get $a)))
        (%wasm.i64.extend_i32 (WasmI32) ExactInteger #t (i64.extend_i32_s (local.get $a)))
        (%wasm.f32.demote_f64 (InexactReal) WasmF32 #t (f32.demote_f64 (local.get $a)))
        (%wasm.f64.promote_f32 (WasmF32) InexactReal #t (f64.promote_f32 (local.get $a)))
        (%wasm.i32.add (WasmI32 WasmI32) WasmI32 #t (i32.add (local.get $a) (local.get $b)))
        (%wasm.i32.sub (WasmI32 WasmI32) WasmI32 #t (i32.sub (local.get $a) (local.get $b)))
        (%wasm.i32.mul (WasmI32 WasmI32) WasmI32 #t (i32.mul (local.get $a) (local.get $b)))
        (%wasm.i32.eq (WasmI32 WasmI32) Boolean #t (i32.eq (local.get $a) (local.get $b)))
        (%wasm.i32.lt_s (WasmI32 WasmI32) Boolean #t (i32.lt_s (local.get $a) (local.get $b)))
        (%wasm.i32.lt_u (WasmI32 WasmI32) Boolean #t (i32.lt_u (local.get $a) (local.get $b)))
        (%wasm.i64.add (ExactInteger ExactInteger) ExactInteger #t (i64.add (local.get $a) (local.get $b)))
        (%wasm.i64.sub (ExactInteger ExactInteger) ExactInteger #t (i64.sub (local.get $a) (local.get $b)))
        (%wasm.i64.mul (ExactInteger ExactInteger) ExactInteger #t (i64.mul (local.get $a) (local.get $b)))
        (%wasm.f32.add (WasmF32 WasmF32) WasmF32 #t (f32.add (local.get $a) (local.get $b)))
        (%wasm.f32.sub (WasmF32 WasmF32) WasmF32 #t (f32.sub (local.get $a) (local.get $b)))
        (%wasm.f32.mul (WasmF32 WasmF32) WasmF32 #t (f32.mul (local.get $a) (local.get $b)))
        (%wasm.f32.div (WasmF32 WasmF32) WasmF32 #t (f32.div (local.get $a) (local.get $b)))
        (%wasm.f64.add (InexactReal InexactReal) InexactReal #t (f64.add (local.get $a) (local.get $b)))
        (%wasm.f64.sub (InexactReal InexactReal) InexactReal #t (f64.sub (local.get $a) (local.get $b)))
        (%wasm.f64.mul (InexactReal InexactReal) InexactReal #t (f64.mul (local.get $a) (local.get $b)))
        (%wasm.f64.div (InexactReal InexactReal) InexactReal #t (f64.div (local.get $a) (local.get $b)))
        (%wasm.vector.length (Vector) WasmI32 #t (array.len (local.get $a)))
        (%wasm.vector.new (WasmI32 Any) Vector #t (array.new $vector (local.get $b) (local.get $a)))
        (%wasm.vector.ref (Vector WasmI32) ? #t (array.get $vector (local.get $a) (local.get $b)))
        (%wasm.vector.set! (Vector WasmI32 Any) Unspecified #t
                           (block (result eqref) (array.set $vector (local.get $a) (local.get $b) (local.get $c))
                                  (global.get $unspecified)))
        (%wasm.vector.copy! (Vector WasmI32 Vector WasmI32 WasmI32) Unspecified #t
                            (block (result eqref)
                                   (array.copy $vector $vector (local.get $a) (local.get $b)
                                               (local.get $c) (local.get $d) (local.get $e))
                                   (global.get $unspecified)))))

    (define (intrinsic-name entry) (car entry))
    (define (intrinsic-domains entry) (cadr entry))
    (define (intrinsic-result entry) (caddr entry))
    (define (intrinsic-checked? entry) (cadddr entry))
    (define (intrinsic-body entry) (car (cddddr entry)))
    (define (intrinsic-unsafe? entry)
      (char=? (string-ref (symbol->string (intrinsic-name entry)) 0) #\%))
    (define (find-intrinsic name count)
      (let find ((entries intrinsics))
        (cond ((null? entries) #f)
              ((and (eq? name (intrinsic-name (car entries)))
                    (= count (length (intrinsic-domains (car entries))))) (car entries))
              (else (find (cdr entries))))))
    (define (intrinsic-entry entry)
      (string->symbol (string-append "$intrinsic:" (symbol->string (intrinsic-name entry))
                                     ":" (number->string (length (intrinsic-domains entry))))))
    (define (intrinsic-argument-names entry)
      (let take ((names '($a $b $c $d $e)) (types (intrinsic-domains entry)))
        (if (null? types) '() (cons (car names) (take (cdr names) (cdr types))))))
    (define intrinsic-unsafe-names
      (let collect ((entries intrinsics))
        (cond ((null? entries) '())
              ((intrinsic-unsafe? (car entries)) (cons (intrinsic-name (car entries)) (collect (cdr entries))))
              (else (collect (cdr entries))))))

    ;; ---- Generic Scheme boundaries ----

    ;; Call only after the source operand and operator evaluations. Decoding
    ;; proceeds left to right, retaining the builtin's cast/index error order.
    ;; It deliberately does not interpret an Any argument as a single value:
    ;; foreign callers can pass an envelope as a stored vector element.
    (define (checked-intrinsic-argument value type)
      (case type
        ((Any ?) value)
        ((ExactInteger) `(call $integer_value ,value))
        ((WasmI32) `(call $wasm_i32_value ,value))
        ((WasmF32) `(call $wasm_f32_value ,value))
        ((Char) `(call $character_value ,value))
        (else (unbox-representation value (type-representation type)))))

    (define (intrinsic-function entry)
      `(func ,(intrinsic-entry entry)
             ,@(map (lambda (name type) `(param ,name ,(representation-wasm (type-representation type))))
                    (intrinsic-argument-names entry) (intrinsic-domains entry))
             (result ,(representation-wasm (type-representation (intrinsic-result entry)))) ,(intrinsic-body entry)))

    (define (intrinsic-adapter entry)
      (let ((count (length (intrinsic-domains entry))))
        `(func ,(string->symbol (string-append "$builtin:" (symbol->string (intrinsic-name entry))))
               (param $arguments (ref $vector)) (result eqref)
               (call $arity (local.get $arguments) (i32.const ,count) (i32.const 0))
               ,(box-representation
                 `(call ,(intrinsic-entry entry)
                        ,@(let arguments ((types (intrinsic-domains entry)) (index 0))
                            (if (null? types) '()
                                (cons (checked-intrinsic-argument
                                       `(array.get $vector (local.get $arguments) (i32.const ,index)) (car types))
                                      (arguments (cdr types) (+ index 1))))))
                 (type-representation (intrinsic-result entry))))))

    ;; These checks establish semantic subsets, separate from Wasm storage.
    ;; NaNs, infinities, and both zero signs inhabit F32; finite values must
    ;; survive the round trip exactly. Explicit demotion performs rounding.
    (define intrinsic-boundaries
      '((func $checked_index (param $value i64) (result i32)
              (if (i64.gt_u (local.get $value) (i64.const 2147483647)) (then (call $fail (i32.const 3))))
              (i32.wrap_i64 (local.get $value)))
        (func $wasm_i32_value (param $value eqref) (result i32) (local $integer i64)
              (local.set $integer (call $integer_value (local.get $value)))
              (if (i64.gt_u (i64.add (local.get $integer) (i64.const 2147483648)) (i64.const 4294967295))
                  (then (call $fail (i32.const 8))))
              (i32.wrap_i64 (local.get $integer)))
        (func $is_f32 (param $value eqref) (result i32) (local $number f64)
              (if (i32.eqz (ref.test (ref $float) (local.get $value))) (then (return (i32.const 0))))
              (local.set $number (struct.get $float 0 (ref.cast (ref $float) (local.get $value))))
              (i32.or (f64.ne (local.get $number) (local.get $number))
                      (f64.eq (local.get $number) (f64.promote_f32 (f32.demote_f64 (local.get $number))))))
        (func $wasm_f32_value (param $value eqref) (result f32)
              (if (i32.eqz (call $is_f32 (local.get $value))) (then (call $fail (i32.const 8))))
              (f32.demote_f64 (struct.get $float 0 (ref.cast (ref $float) (local.get $value)))))))

    (define intrinsic-definitions
      (append intrinsic-boundaries (map intrinsic-function intrinsics)
              (let adapters ((entries intrinsics))
                (cond ((null? entries) '())
                      ((intrinsic-unsafe? (car entries)) (cons (intrinsic-adapter (car entries)) (adapters (cdr entries))))
                      (else (adapters (cdr entries)))))))))
