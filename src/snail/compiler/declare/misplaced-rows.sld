;; Query: the refusal of an instance's head that gives one of its class's
;; type parameters a row, `(! label ...)`, which the old compiler's
;; `check-head-argument` (src/snail/shell/compiler/expand.sld) makes of a
;; written head and of each head `dynamic-instances` generates. `declare`
;; asks it of each written instance, and `dispatch` of each generated one,
;; whose head holds a domain's types and a source's output, so the message
;; is written once. A class's outputs are type parameters too.
;;
;; An instance is named in messages by its class's name, `a C instance`.
(define-library (snail compiler declare misplaced-rows)
  (export
   instance-noun-of
   misplaced-row-problem)
  (import
   (snail core base)
   (only (snail compiler declare language) ClassParameter TypeParameter RowParameter)
   (only (snail compiler types type) Type Row))
  (begin

    ;; ---- Messages ----

    ;; An instance of the class named `class`, as a message names it.
    (: instance-noun-of (impl (Fn String -> String)))
    (define (instance-noun-of class)
      (string-append "a " class " instance"))

    ;; The refusal of `type` for `parameter` of the class named `class`,
    ;; when the parameter is a type and the type a row.
    (: misplaced-row-problem (impl (Fn String ClassParameter Type -> (Option String))))
    (define (misplaced-row-problem class parameter type)
      (match (Pair parameter type)
        ((Pair (TypeParameter name) (Row _))
         (Some (string-append (instance-noun-of class)
                              " gives its type parameter "
                              name
                              " a row, not a type")))
        (_ (None))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-misplaced-rows)
    (import
     (only (snail compiler names globals) Global)
     (only (snail compiler types type) Con Effects)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-misplaced-rows)
        (let ((row (Row (Effects (list) (None))))
              (i64 (Con (Global forms-library "I64" 0) (list))))
          (expect (misplaced-row-problem "Combine" (TypeParameter "A") row)
                  (Some "a Combine instance gives its type parameter A a row, not a type"))
          (expect (misplaced-row-problem "Combine" (TypeParameter "A") i64) (None))
          (expect (misplaced-row-problem "Combine" (RowParameter "e") row) (None))
          (expect (misplaced-row-problem "Combine" (RowParameter "e") i64) (None))))))
   (else)))
