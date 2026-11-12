;; The builtin types of (snail core forms) the passes write by name, as
;; Types, each a builtin Global of (snail compiler builtins forms) at no
;; arguments: Any, the type every erased value has, which the code
;; `dispatch` writes erases a value to; Unit, a setter's result; and I32,
;; a case's TypeId and a linked file's handle.
(define-library (snail compiler types builtins)
  (export
   any-type
   any-type?
   unit-type
   i32-type)
  (import
   (snail core base)
   (only (snail compiler names globals) same-global?)
   (only (snail compiler builtins forms) any-global unit-global i32-global)
   (only (snail compiler types type) Type Con))
  (begin

    ;; ---- Builtin types ----

    (: any-type Type)
    (define any-type
      (Con any-global (Nil)))

    (: any-type? (impl (Fn Type -> Bool)))
    (define (any-type? type)
      (match type
        ((Con global (Nil)) (same-global? global any-global))
        (_ #f)))

    (: unit-type Type)
    (define unit-type
      (Con unit-global (Nil)))

    (: i32-type Type)
    (define i32-type
      (Con i32-global (Nil)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-builtins)
    (import
     (snail compiler names libraries)
     (only (snail compiler names globals) Global)
     (snail stage0 testing))
    (begin
      (define (test-builtins)
        (expect (any-type? any-type) #t)
        (expect (any-type? (Con (Global forms-library "I64" 0) (list))) #f)
        (expect (any-type? (Con (Global (list "main") "Any" 0) (list))) #f)
        (expect (any-type? (Con any-global (list any-type))) #f)
        (expect (any-type? unit-type) #f)
        (expect i32-type (Con (Global forms-library "I32" 0) (list))))))
   (else)))
