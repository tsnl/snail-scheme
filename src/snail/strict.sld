;; Syntax and typed library functions for the concrete compiler. Macros use the
;; hygienic expander; ordinary functions specialize through the same pipeline
;; as user code and call native storage operations without a dynamic runtime.
(define-library (snail strict)
  (export define define-syntax syntax-rules lambda quote if begin set!
          let let* letrec letrec* and or when unless
          : ann inst All -> Rest => define-class define-instance define-extern
          I32 I64 F32 F64 Bool Char Unit Top Never Ref List Vector
          Arithmetic Comparison Integral Floating
          + - * / sqrt quotient remainder = < <= > >= not unit unreachable
          i32-add i32-sub i32-mul i32-eq i32-lt i32-le i32-gt i32-ge i32-quotient i32-remainder
          i64-add i64-sub i64-mul i64-eq i64-lt i64-le i64-gt i64-ge i64-quotient i64-remainder
          f32-add f32-sub f32-mul f32-div f32-eq f32-lt f32-le f32-gt f32-ge f32-sqrt
          f64-add f64-sub f64-mul f64-div f64-eq f64-lt f64-le f64-gt f64-ge f64-sqrt
          i64->f64 i32->i64 i64->i32 f32->f64 f64->f32 f64->i64
          ref ref-get ref-set! ref-eq? cons car cdr null?
          empty-vector make-vector vector-length vector-ref vector-set! vector-eq? vector-copy!
          vector vector-copy vector-append vector->list list->vector)
  (import (snail-scheme core))
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

    ;; These classes are resolved before emission. Each method names a native
    ;; primitive, so direct calls need no dictionary, closure or tagged operand.
    ;; Values never coerce implicitly; unconstrained literals default to I64/F64.
    (define-class (Arithmetic T)
      (: + (-> T T T)) (: - (-> T T T)) (: * (-> T T T)))
    (define-class (Comparison T)
      (: = (-> T T Bool)) (: < (-> T T Bool)) (: <= (-> T T Bool))
      (: > (-> T T Bool)) (: >= (-> T T Bool)))
    (define-class (Integral T)
      (: quotient (-> T T T)) (: remainder (-> T T T)))
    (define-class (Floating T)
      (: / (-> T T T)) (: sqrt (-> T T)))
    (define-instance (Arithmetic I32)
      (+ i32-add) (- i32-sub) (* i32-mul))
    (define-instance (Comparison I32)
      (= i32-eq) (< i32-lt) (<= i32-le) (> i32-gt) (>= i32-ge))
    (define-instance (Integral I32)
      (quotient i32-quotient) (remainder i32-remainder))
    (define-instance (Arithmetic I64)
      (+ i64-add) (- i64-sub) (* i64-mul))
    (define-instance (Comparison I64)
      (= i64-eq) (< i64-lt) (<= i64-le) (> i64-gt) (>= i64-ge))
    (define-instance (Integral I64)
      (quotient i64-quotient) (remainder i64-remainder))
    (define-instance (Arithmetic F32)
      (+ f32-add) (- f32-sub) (* f32-mul))
    (define-instance (Comparison F32)
      (= f32-eq) (< f32-lt) (<= f32-le) (> f32-gt) (>= f32-ge))
    (define-instance (Floating F32)
      (/ f32-div) (sqrt f32-sqrt))
    (define-instance (Arithmetic F64)
      (+ f64-add) (- f64-sub) (* f64-mul))
    (define-instance (Comparison F64)
      (= f64-eq) (< f64-lt) (<= f64-le) (> f64-gt) (>= f64-ge))
    (define-instance (Floating F64)
      (/ f64-div) (sqrt f64-sqrt))

    ;; ---- Homogeneous vectors ----

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
