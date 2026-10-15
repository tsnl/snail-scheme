;; Concrete primitive contracts are shared by inference and Wasm emission.
;; Numeric widths are siblings: selecting an opcode never inserts a coercion.
(define-library (snail-scheme strict-primitives)
  (export primitive-names primitive-scheme primitive-opcode)
  (import (scheme base) (scheme cxr) (snail-scheme strict-types))
  (begin

    ;; ---- Concrete numeric operations ----

    (define numeric-primitives
      '((+ I64 I64 i64.add) (- I64 I64 i64.sub) (* I64 I64 i64.mul)
        (quotient I64 I64 i64.div_s) (remainder I64 I64 i64.rem_s)
        (= I64 Bool i64.eq) (< I64 Bool i64.lt_s) (<= I64 Bool i64.le_s)
        (> I64 Bool i64.gt_s) (>= I64 Bool i64.ge_s)
        (i32-add I32 I32 i32.add) (i32-sub I32 I32 i32.sub) (i32-mul I32 I32 i32.mul)
        (i32-eq I32 Bool i32.eq) (i32-lt I32 Bool i32.lt_s)
        (i64-add I64 I64 i64.add) (i64-sub I64 I64 i64.sub) (i64-mul I64 I64 i64.mul)
        (i64-eq I64 Bool i64.eq) (i64-lt I64 Bool i64.lt_s)
        (f32-add F32 F32 f32.add) (f32-sub F32 F32 f32.sub)
        (f32-mul F32 F32 f32.mul) (f32-div F32 F32 f32.div)
        (f32-eq F32 Bool f32.eq) (f32-lt F32 Bool f32.lt)
        (f64-add F64 F64 f64.add) (f64-sub F64 F64 f64.sub)
        (f64-mul F64 F64 f64.mul) (f64-div F64 F64 f64.div)
        (f64-eq F64 Bool f64.eq) (f64-lt F64 Bool f64.lt)))
    (define primitive-names
      (append (map car numeric-primitives) '(not unit ref ref-get ref-set! ref-eq? cons car cdr null? unreachable)))
    (define (primitive-opcode name)
      (let ((entry (assq name numeric-primitives))) (if entry (cadddr entry) name)))
    (define (primitive-scheme name)
      (let ((entry (assq name numeric-primitives)))
        (cond (entry (make-scheme '() (function-type (list (cadr entry) (cadr entry)) #f (caddr entry)) '()))
              ((eq? name 'not) (make-scheme '() (function-type '(Bool) #f 'Bool) '()))
              ((eq? name 'unit) (make-scheme '() (function-type '() #f 'Unit) '()))
              ((eq? name 'unreachable) (make-scheme '() (function-type '() #f 'Never) '()))
              (else (container-scheme name)))))

    ;; ---- Invariant references and immutable lists ----

    (define (container-scheme name)
      (let* ((a (fresh-variable)) (ref (list 'Ref a)) (list-type (list 'List a))
             (signature
              (case name
                ((ref) (function-type (list a) #f ref))
                ((ref-get) (function-type (list ref) #f a))
                ((ref-set!) (function-type (list ref a) #f 'Unit))
                ((ref-eq?) (function-type (list ref ref) #f 'Bool))
                ((cons) (function-type (list a list-type) #f list-type))
                ((car) (function-type (list list-type) #f a))
                ((cdr) (function-type (list list-type) #f list-type))
                ((null?) (function-type (list list-type) #f 'Bool))
                (else (error "unknown strict primitive" name)))))
        (make-scheme (list a) signature '())))))
