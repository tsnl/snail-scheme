;; An initial Scheme surface over the typed Lofi kernel. Conditions are Bool;
;; branches and collection elements obey Lofi's types. This is not R7RS base.
(define-library (scheme base)
  (import
   (lofi base)
   (rename (lofi core) (def core-def) (lambda core-lambda) (let core-let)
           (begin core-begin) (if core-if)))
  (export define define-syntax syntax-rules lambda let let* letrec letrec*
          begin if and or when unless cond else
          + - * / = < <= > >= quotient remainder not unit
          cons car cdr null? empty-list list
          vector make-vector vector-length vector-ref vector-set!
          string make-string string-length string-ref string-set!
          char=? char<? char->integer integer->char)
  (begin

    ;; ---- Definitions and lexical bindings ----

    ;; The typed surface uses proper parameter lists, like the kernel.
    ;; Collection syntax packs its operands before calling a fixed-arity worker.

    (define-syntax define
         (syntax-rules ()
           ((_ (name . parameters) body ...)
            (core-def name (core-lambda parameters (core-begin body ...))))
           ((_ name value) (core-def name value))))
    (define-syntax lambda
         (syntax-rules ()
           ((_ parameters body ...) (core-lambda parameters (core-begin body ...)))))
    (define-syntax let
         (syntax-rules ()
           ((_ ((name value) ...) body ...)
            ((core-lambda (name ...) (core-begin body ...)) value ...))
           ((_ loop ((name value) ...) body ...)
            (core-begin
             (core-def loop (core-lambda (name ...) (core-begin body ...)))
             (loop value ...)))))
    (define-syntax let*
         (syntax-rules ()
           ((_ ((name value) ...) body ...)
            (core-begin (core-let name value) ... body ...))))
    (define-syntax letrec
         (syntax-rules ()
           ((_ ((name value) ...) body ...)
            (core-begin (core-def name value) ... body ...))))
    (define-syntax letrec*
         (syntax-rules ()
           ((_ bindings body ...) (letrec bindings body ...))))

    ;; ---- Typed control forms ----

    (define-syntax begin
         (syntax-rules () ((_ body ...) (core-begin body ...))))
    (define-syntax if
         (syntax-rules ()
           ((_ test consequent alternative) (core-if test consequent alternative))
           ((_ test consequent) (core-if test (core-begin consequent (unit)) (unit)))))
    (define-syntax and
         (syntax-rules ()
           ((_) #t)
           ((_ value) value)
           ((_ first rest ...) (core-if first (and rest ...) #f))))
    (define-syntax or
         (syntax-rules ()
           ((_) #f)
           ((_ value) value)
           ((_ first rest ...)
            (core-begin (core-let value first) (core-if value value (or rest ...))))))
    (define-syntax when
         (syntax-rules ()
           ((_ test body ...) (core-if test (core-begin body ... (unit)) (unit)))))
    (define-syntax unless
         (syntax-rules ()
           ((_ test body ...) (core-if test (unit) (core-begin body ... (unit))))))
    (define-syntax else (syntax-rules () ((_ ) #t)))
    (define-syntax cond
         (syntax-rules (else)
           ((_) (unit))
           ((_ (else body ...)) (core-begin body ...))
           ((_ (test body ...) rest ...)
            (core-if test (core-begin body ...) (cond rest ...)))))))
