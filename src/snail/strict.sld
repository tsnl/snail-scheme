;; Syntax and typed library functions for the concrete compiler. Macros use the
;; hygienic expander; ordinary functions specialize through the same pipeline
;; as user code and call native storage operations without a dynamic runtime.
(define-library (snail strict)
  (export define define-syntax syntax-rules lambda quote if begin set!
          let let* letrec letrec* and or when unless
          : ann inst All -> Rest => define-class define-instance define-extern
          I32 I64 F32 F64 Bool Char Unit Top Never Ref List Vector
          + - * quotient remainder = < <= > >= not unit unreachable
          i32-add i32-sub i32-mul i32-eq i32-lt
          i64-add i64-sub i64-mul i64-eq i64-lt
          f32-add f32-sub f32-mul f32-div f32-eq f32-lt
          f64-add f64-sub f64-mul f64-div f64-eq f64-lt
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
