;; An initial Scheme surface over the typed Lofi kernel. Conditions are Bool;
;; branches and collection elements obey Lofi's types. This is not R7RS base.
(define-library (scheme base)
  (import (lofi base)
          (rename (lofi core) (def core-def) (lambda core-lambda) (let core-let)
                  (begin core-begin) (if core-if)))
  (export define define-syntax syntax-rules lambda let let* letrec letrec*
          begin if and or when unless cond else
          + - * / = < <= > >= quotient remainder not unit
          cons car cdr null? empty-list
          vector make-vector vector-length vector-ref vector-set!
          string make-string string-length string-ref string-set!
          char=? char<? char->integer integer->char)
  (begin

    ;; ---- Definitions and lexical bindings ----

    (def define
         (syntax-rules ()
           ((_ (name . parameters) body ...)
            (core-def name (core-lambda parameters (core-begin body ...))))
           ((_ name value) (core-def name value))))
    (def lambda
         (syntax-rules ()
           ((_ parameters body ...) (core-lambda parameters (core-begin body ...)))))
    (def let
         (syntax-rules ()
           ((_ ((name value) ...) body ...)
            ((core-lambda (name ...) (core-begin body ...)) value ...))
           ((_ loop ((name value) ...) body ...)
            (core-begin
             (core-def loop (core-lambda (name ...) (core-begin body ...)))
             (loop value ...)))))
    (def let*
         (syntax-rules ()
           ((_ ((name value) ...) body ...)
            (core-begin (core-let name value) ... body ...))))
    (def letrec
         (syntax-rules ()
           ((_ ((name value) ...) body ...)
            (core-begin (core-def name value) ... body ...))))
    (def letrec*
         (syntax-rules ()
           ((_ bindings body ...) (letrec bindings body ...))))

    ;; ---- Typed control forms ----

    (def begin
         (syntax-rules () ((_ body ...) (core-begin body ...))))
    (def if
         (syntax-rules ()
           ((_ test consequent alternative) (core-if test consequent alternative))
           ((_ test consequent) (core-if test (core-begin consequent (unit)) (unit)))))
    (def and
         (syntax-rules ()
           ((_) #t)
           ((_ value) value)
           ((_ first rest ...) (core-if first (and rest ...) #f))))
    (def or
         (syntax-rules ()
           ((_) #f)
           ((_ value) value)
           ((_ first rest ...)
            (core-begin (core-let value first) (core-if value value (or rest ...))))))
    (def when
         (syntax-rules ()
           ((_ test body ...) (core-if test (core-begin body ... (unit)) (unit)))))
    (def unless
         (syntax-rules ()
           ((_ test body ...) (core-if test (unit) (core-begin body ... (unit))))))
    (def else (syntax-rules () ((_ ) #t)))
    (def cond
         (syntax-rules (else)
           ((_) (unit))
           ((_ (else body ...)) (core-begin body ...))
           ((_ (test body ...) rest ...)
            (core-if test (core-begin body ...) (cond rest ...)))))))
