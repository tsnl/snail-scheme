;; Surface syntax for the concrete compiler. These macros use the existing
;; hygienic expander; they introduce no dynamic runtime library dependencies.
(define-library (snail strict)
  (export define define-syntax syntax-rules lambda quote if begin set!
          let let* letrec letrec* and or when unless
          : ann inst All -> Rest => define-class define-instance
          I32 I64 F32 F64 Bool Char Unit Top Never Ref List
          + - * quotient remainder = < <= > >= not unreachable
          i32-add i32-sub i32-mul i32-eq i32-lt
          i64-add i64-sub i64-mul i64-eq i64-lt
          f32-add f32-sub f32-mul f32-div f32-eq f32-lt
          f64-add f64-sub f64-mul f64-div f64-eq f64-lt
          ref ref-get ref-set! ref-eq? cons car cdr null?)
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
      (syntax-rules () ((_ test body ...) (if test (begin body ... (begin))))))
    (define-syntax unless
      (syntax-rules () ((_ test body ...) (if test (begin) (begin body ... (begin))))))))
