;; Syntax and typed library functions for the concrete compiler. Macros use the
;; hygienic expander; ordinary functions specialize through the same pipeline
;; as user code and call native storage operations without a dynamic runtime.
(define-library (snail strict)
  (export define define-syntax syntax-rules lambda quote if begin set!
          let let* letrec letrec* and or when unless
          : ann inst All -> Rest => define-class define-instance define-overload define-extern
          I32 I64 F32 F64 Bool Char Unit Top Never Ref List Vector
          Default default
          + - * / sqrt truncate quotient remainder = < <= > >= not unit unreachable
          i32-add i32-sub i32-mul i32-eq i32-lt i32-le i32-gt i32-ge i32-quotient i32-remainder
          i64-add i64-sub i64-mul i64-eq i64-lt i64-le i64-gt i64-ge i64-quotient i64-remainder
          f32-add f32-sub f32-mul f32-div f32-eq f32-lt f32-le f32-gt f32-ge f32-sqrt
          f64-add f64-sub f64-mul f64-div f64-eq f64-lt f64-le f64-gt f64-ge f64-sqrt
          f32-truncate f64-truncate
          i64->f64 i32->i64 i64->i32 f32->f64 f64->f32 f64->i64
          ref ref-get ref-set! ref-eq? cons car cdr null?
          empty-vector make-vector vector-length vector-ref vector-set! vector-eq? vector-copy!
          vector vector-copy vector-append vector->list list->vector)
  (import (rename (snail-scheme core) (make-vector make-filled-vector)))
  (begin

    ;; ---- Immutable binding forms ----

    (define-syntax let
      (syntax-rules ()
        ((_ ((name initializer) ...) body ...)
         ((lambda (name ...) body ...) initializer ...))
        ((_ loop ((name initializer) ...) body ...)
         (((lambda () (define (loop name ...) body ...) loop)) initializer ...))))
    (define-syntax let*
      (syntax-rules ()
        ((_ () body ...) (let () body ...))
        ((_ ((name initializer) remaining ...) body ...)
         (let ((name initializer)) (let* (remaining ...) body ...)))))
    (define-syntax letrec*
      (syntax-rules () ((_ ((name initializer) ...) body ...)
                        (let () (define name initializer) ... body ...))))
    (define-syntax letrec
      (syntax-rules () ((_ bindings body ...) (letrec* bindings body ...))))

    ;; ---- Boolean control forms ----

    (define-syntax and
      (syntax-rules () ((_) #t) ((_ expression) expression)
        ((_ first rest ...) (if first (and rest ...) #f))))
    (define-syntax or
      (syntax-rules () ((_) #f) ((_ expression) expression)
        ((_ first rest ...) (let ((value first)) (if value value (or rest ...))))))
    (define-syntax when
      (syntax-rules () ((_ test body ...) (if test (begin body ... (unit)) (unit)))))
    (define-syntax unless
      (syntax-rules () ((_ test body ...) (if test (unit) (begin body ... (unit))))))

    ;; ---- Static numeric operators ----

    ;; Each signature becomes a static class instance. Argument and result
    ;; context select a unique row before any concrete function is emitted.
    ;; Numeric promotion is ordinary source code and calls a selected float row.
    (define-overload + (-> I32 I32 I32) i32-add)
    (define-overload - (-> I32 I32 I32) i32-sub)
    (define-overload * (-> I32 I32 I32) i32-mul)
    (define-overload = (-> I32 I32 Bool) i32-eq)
    (define-overload < (-> I32 I32 Bool) i32-lt)
    (define-overload <= (-> I32 I32 Bool) i32-le)
    (define-overload > (-> I32 I32 Bool) i32-gt)
    (define-overload >= (-> I32 I32 Bool) i32-ge)
    (define-overload quotient (-> I32 I32 I32) i32-quotient)
    (define-overload remainder (-> I32 I32 I32) i32-remainder)

    (define-overload + (-> I64 I64 I64) i64-add)
    (define-overload - (-> I64 I64 I64) i64-sub)
    (define-overload * (-> I64 I64 I64) i64-mul)
    (define-overload = (-> I64 I64 Bool) i64-eq)
    (define-overload < (-> I64 I64 Bool) i64-lt)
    (define-overload <= (-> I64 I64 Bool) i64-le)
    (define-overload > (-> I64 I64 Bool) i64-gt)
    (define-overload >= (-> I64 I64 Bool) i64-ge)
    (define-overload quotient (-> I64 I64 I64) i64-quotient)
    (define-overload remainder (-> I64 I64 I64) i64-remainder)

    (define-overload + (-> F32 F32 F32) f32-add)
    (define-overload - (-> F32 F32 F32) f32-sub)
    (define-overload * (-> F32 F32 F32) f32-mul)
    (define-overload = (-> F32 F32 Bool) f32-eq)
    (define-overload < (-> F32 F32 Bool) f32-lt)
    (define-overload <= (-> F32 F32 Bool) f32-le)
    (define-overload > (-> F32 F32 Bool) f32-gt)
    (define-overload >= (-> F32 F32 Bool) f32-ge)
    (define-overload / (-> F32 F32 F32) f32-div)
    (define-overload sqrt (-> F32 F32) f32-sqrt)
    (define-overload truncate (-> F32 F32) f32-truncate)

    (define-overload + (-> F64 F64 F64) f64-add)
    (define-overload - (-> F64 F64 F64) f64-sub)
    (define-overload * (-> F64 F64 F64) f64-mul)
    (define-overload = (-> F64 F64 Bool) f64-eq)
    (define-overload < (-> F64 F64 Bool) f64-lt)
    (define-overload <= (-> F64 F64 Bool) f64-le)
    (define-overload > (-> F64 F64 Bool) f64-gt)
    (define-overload >= (-> F64 F64 Bool) f64-ge)
    (define-overload / (-> F64 F64 F64) f64-div)
    (define-overload sqrt (-> F64 F64) f64-sqrt)
    (define-overload truncate (-> F64 F64) f64-truncate)

    (define-overload + (-> I64 F64 F64)
      (lambda (left right) (+ (i64->f64 left) right)))
    (define-overload + (-> F64 I64 F64)
      (lambda (left right) (+ left (i64->f64 right))))
    (define-overload - (-> I64 F64 F64)
      (lambda (left right) (- (i64->f64 left) right)))
    (define-overload - (-> F64 I64 F64)
      (lambda (left right) (- left (i64->f64 right))))
    (define-overload * (-> I64 F64 F64)
      (lambda (left right) (* (i64->f64 left) right)))
    (define-overload * (-> F64 I64 F64)
      (lambda (left right) (* left (i64->f64 right))))
    (define-overload / (-> I64 F64 F64)
      (lambda (left right) (/ (i64->f64 left) right)))
    (define-overload / (-> F64 I64 F64)
      (lambda (left right) (/ left (i64->f64 right))))
    (define-overload = (-> I64 F64 Bool)
      (lambda (left right) (= (i64->f64 left) right)))
    (define-overload = (-> F64 I64 Bool)
      (lambda (left right) (= left (i64->f64 right))))
    (define-overload < (-> I64 F64 Bool)
      (lambda (left right) (< (i64->f64 left) right)))
    (define-overload < (-> F64 I64 Bool)
      (lambda (left right) (< left (i64->f64 right))))
    (define-overload <= (-> I64 F64 Bool)
      (lambda (left right) (<= (i64->f64 left) right)))
    (define-overload <= (-> F64 I64 Bool)
      (lambda (left right) (<= left (i64->f64 right))))
    (define-overload > (-> I64 F64 Bool)
      (lambda (left right) (> (i64->f64 left) right)))
    (define-overload > (-> F64 I64 Bool)
      (lambda (left right) (> left (i64->f64 right))))
    (define-overload >= (-> I64 F64 Bool)
      (lambda (left right) (>= (i64->f64 left) right)))
    (define-overload >= (-> F64 I64 Bool)
      (lambda (left right) (>= left (i64->f64 right))))

    ;; ---- Default values and homogeneous vectors ----

    (define-class (Default T) (: default (-> T)))
    (define-instance (Default I32) (default (lambda () (ann 0 I32))))
    (define-instance (Default I64) (default (lambda () 0)))
    (define-instance (Default F32) (default (lambda () (ann 0.0 F32))))
    (define-instance (Default F64) (default (lambda () 0.0)))
    (define-instance (Default Bool) (default (lambda () #f)))
    (define-instance (Default Char) (default (lambda () #\null)))
    (define-instance (Default Unit) (default (lambda () (unit))))

    (define-overload make-vector (All (T) (-> I64 T (Vector T))) make-filled-vector)
    (define-overload make-vector (All (T) (=> ((Default T)) (-> I64 (Vector T))))
      (lambda (count)
        ;; Validate before user code runs. The private vector cannot escape
        ;; until each slot has its own default; zero invokes no default at all.
        (if (or (< count 0) (> count 4294967295)) (unreachable)
            (if (= count 0) (empty-vector)
                (let ((result (make-filled-vector count (default))))
                  (let loop ((index 1))
                    (unless (= index count)
                      (vector-set! result index (default))
                      (loop (+ index 1))))
                  result)))))

    ;; These are ordinary polymorphic Scheme functions. Specialization keeps
    ;; each element type through native allocation and bulk copying. Constructors
    ;; return fresh vectors while preserving the identity of referenced elements.
    (define (vector . elements) (list->vector elements))
    (define (list->vector elements)
      (if (null? elements) (empty-vector)
          (let ((result (make-vector (element-count elements) (car elements))))
            (let loop ((tail elements) (index 0))
              (unless (null? tail)
                (vector-set! result index (car tail))
                (loop (cdr tail) (+ index 1))))
            result)))
    (define (element-count elements)
      (let loop ((tail elements) (count 0))
        (if (null? tail) count
            (if (= count 4294967295) (unreachable)
                (loop (cdr tail) (+ count 1))))))
    (define (vector->list source)
      (let loop ((index (vector-length source)) (result '()))
        (if (= index 0) result
            (loop (- index 1) (cons (vector-ref source (- index 1)) result)))))
    (define (vector-copy source)
      (let ((count (vector-length source)))
        (if (= count 0) (empty-vector)
            (let ((result (make-vector count (vector-ref source 0))))
              (vector-copy! result 0 source 0 count)
              result))))
    (define (vector-append . sources)
      (let ((count (appended-length sources)))
        (if (= count 0) (empty-vector)
            (let ((result (make-vector count (first-element sources))))
              (append-into! result sources 0)
              result))))
    (define (appended-length sources)
      ;; Check every prefix before adding another bounded native length.
      ;; The addition is at most twice U32_MAX, so it cannot overflow I64.
      (let loop ((tail sources) (count 0))
        (if (> count 4294967295) (unreachable)
            (if (null? tail) count
                (loop (cdr tail) (+ count (vector-length (car tail))))))))
    (define (first-element sources)
      ;; A positive combined length guarantees a nonempty source will be found.
      (if (= (vector-length (car sources)) 0) (first-element (cdr sources))
          (vector-ref (car sources) 0)))
    (define (append-into! result sources offset)
      (unless (null? sources)
        (let ((count (vector-length (car sources))))
          (vector-copy! result offset (car sources) 0 count)
          (append-into! result (cdr sources) (+ offset count)))))))
