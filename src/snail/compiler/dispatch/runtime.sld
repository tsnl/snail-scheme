;; Rule: the type the code `dispatch` writes erases a value to, `Any`, of
;; (snail core forms), which every erased value has. What else of the
;; runtime that code names, its constructors and operations, the
;; vocabulary (snail compiler builtins base) names.
(define-library (snail compiler dispatch runtime)
  (export
   any-type
   any-type?)
  (import
   (snail core base)
   (only (snail compiler names globals) same-global?)
   (only (snail compiler builtins forms) any-global)
   (only (snail compiler declare language) Type Con))
  (begin

    ;; ---- Any ----

    (: any-type Type)
    (define any-type
      (Con any-global (Nil)))

    (: any-type? (impl (Fn Type -> Bool)))
    (define (any-type? type)
      (match type
        ((Con global (Nil)) (same-global? global any-global))
        (_ #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-runtime)
    (import
     (snail compiler names libraries)
     (only (snail compiler names globals) Global)
     (snail stage0 testing))
    (begin
      (define (test-runtime)
        (expect (any-type? any-type) #t)
        (expect (any-type? (Con (Global forms-library "I64" 0) (list))) #f)
        (expect (any-type? (Con (Global (list "main") "Any" 0) (list))) #f)
        (expect (any-type? (Con any-global (list any-type))) #f))))
   (else)))
