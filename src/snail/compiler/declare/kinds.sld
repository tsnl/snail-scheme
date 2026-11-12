;; The kind of each of a class's parameters: a row when a method's type
;; ends a row with it, as `e` in `(: fetch-object (impl (Fn S String ->
;; String ! e)))`, and a type otherwise, as the old compiler's `class-rows`
;; and `declare-class` (src/snail/shell/compiler/expand.sld) find a row's
;; kind from its use. It looks at each method's own type, operational
;; already, and not at its requirements, so a row written only in the arrow
;; of an `impl` parameter, which becomes a callable requirement, makes no
;; row. A parameter is one kind or the other: one a method's type ends a
;; row with and also writes as a type is refused, and an output, which is
;; always a type, may not end a row. The old compiler finds the rows among
;; the written parameters and the outputs alike, refuses the first row
;; written as a type, in that order, and then an output that is a row.
;;
;; What a type writes as types, and the variable a row ends with, are read
;; here, as the old compiler reads them for kinds and for what an
;; instance's head determines.
(define-library (snail compiler declare kinds)
  (export
   class-parameters
   type-variables
   arrow-variables
   row-variable)
  (import
   (snail core base)
   (snail compiler declare language)
   (snail compiler declare equality))
  (begin

    ;; ---- Parameters ----

    ;; Each of the written `parameters` with its kind, in order, given the
    ;; class's `outputs` and the types of its methods; or the old
    ;; compiler's refusal.
    (: class-parameters
       (impl (Fn (List String) (List String) (List Type) -> (Result (List ClassParameter) String))))
    (define (class-parameters parameters outputs types)
      (let* ((used (concatenate (map row-names types)))
             (rows (filter (lambda (name) (member? name used)) (append parameters outputs)))
             (written (concatenate (map type-variables types))))
        (match (find (lambda (row) (variable-among? (Written row) written)) rows)
          ((Some row)
           (Err
            (string-append "the class parameter " row " is written both as a row and as a type")))
          ((None)
           (if (any? (lambda (output) (member? output rows)) outputs)
               (Err "an associated type must have kind Type, not an effect row")
               (Ok (map (lambda (name)
                          (if (member? name rows) (RowParameter name) (TypeParameter name)))
                        parameters)))))))

    ;; ---- Rows ----

    ;; The variables a type ends a row with: a function's effects, and a
    ;; row as a type argument, followed through a tail that is a row
    ;; itself, as an alias's argument may write it.
    (: row-names (impl (Fn Type -> (List String))))
    (define (row-names type)
      (match type
        ((Callable _ _ arrow) (arrow-row-names arrow))
        ((Code arrow) (arrow-row-names arrow))
        ((Con _ arguments) (concatenate (map row-names arguments)))
        ((Row effects) (effects-row-names effects))
        ((Var _) (Nil))))

    (: arrow-row-names (impl (Fn Arrow -> (List String))))
    (define (arrow-row-names arrow)
      (append (concatenate (map row-names (::parameters arrow)))
              (append (row-names (::result arrow)) (effects-row-names (::effects arrow)))))

    (: effects-row-names (impl (Fn Effects -> (List String))))
    (define (effects-row-names effects)
      (match (::tail effects)
        ((Some (Var (Written name))) (list name))
        ((Some tail) (row-names tail))
        ((None) (Nil))))

    ;; ---- Types ----

    ;; The variables a type writes as types: itself, when it is one, and
    ;; those of a Con's arguments and of an arrow's parameters and result,
    ;; but none a row holds, as the old compiler's `type-names` reads them.
    (: type-variables (impl (Fn Type -> (List TypeVariable))))
    (define (type-variables type)
      (match type
        ((Var variable) (list variable))
        ((Callable _ _ arrow) (arrow-variables arrow))
        ((Code arrow) (arrow-variables arrow))
        ((Con _ arguments) (concatenate (map type-variables arguments)))
        ((Row _) (Nil))))

    (: arrow-variables (impl (Fn Arrow -> (List TypeVariable))))
    (define (arrow-variables arrow)
      (append (concatenate (map type-variables (::parameters arrow)))
              (type-variables (::result arrow))))

    ;; The variable a row given as an argument ends with, when it ends with
    ;; one, as the old compiler's `row-variable` reads it; not one a row it
    ;; ends with holds.
    (: row-variable (impl (Fn Type -> (List TypeVariable))))
    (define (row-variable type)
      (match type
        ((Row (Effects _ (Some (Var variable)))) (list variable))
        (_ (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-kinds)
    (import
     (only (snail compiler expand language) Impl Dyn FnContract FnMutContract)
     (only (snail compiler names globals) Global)
     (snail stage0 testing))
    (begin
      (define (test-kinds)
        (test-rows)
        (test-variables)
        (test-parameters)
        (test-problems))

      ;; Every variable written as a type, the compiler's among them, but
      ;; none in a row; and a row argument's own tail, when a variable.
      (define (test-variables)
        (expect (type-variables (Con io
                                     (list (var "a")
                                           (Row (ending (Some (var "e"))))
                                           (Var (Associated 0 "Out")))))
                (list (Written "a") (Associated 0 "Out")))
        (expect (type-variables (fetch (var "S") (ending (Some (var "e"))))) (list (Written "S")))
        (expect (row-variable (Row (ending (Some (var "e"))))) (list (Written "e")))
        (expect (row-variable (Row (ending (Some (Row (ending (Some (var "e")))))))) (list))
        (expect (row-variable (Row (ending (None)))) (list))
        (expect (row-variable (var "e")) (list)))

      (define text-type (Con (Global (list "snail" "core" "forms") "String" 0) (list)))
      (define io (Global (list "main") "io" 0))

      (define (var name)
        (Var (Written name)))

      (define (ending tail)
        (Effects (list io) tail))

      (define (fetch parameter effects)
        (Callable (Dyn) (FnContract) (Arrow (list parameter text-type) text-type effects)))

      ;; A function's row, a row argument, a row a callable within holds,
      ;; and a row's tail written as a row; never a variable as a type.
      (define (test-rows)
        (expect (row-names (fetch (var "S") (ending (Some (var "e"))))) (list "e"))
        (expect (row-names (fetch (var "S") (ending (None)))) (list))
        (expect (row-names (Con io (list (Row (ending (Some (var "r")))) (var "S")))) (list "r"))
        (expect (row-names (Code (Arrow (list (Callable (Impl)
                                                        (FnMutContract)
                                                        (Arrow (list)
                                                               text-type
                                                               (ending (Some (var "a"))))))
                                        (var "b")
                                        (ending (Some (var "c"))))))
                (list "a" "c"))
        (expect (row-names (Row (ending (Some (Row (ending (Some (var "e")))))))) (list "e"))
        (expect (row-names (Row (ending (Some (Var (Associated 0 "Out")))))) (list)))

      ;; Written order, each parameter's kind from every method's type.
      (define (test-parameters)
        (expect (class-parameters (list "e" "S")
                                  (list)
                                  (list (fetch (var "S") (ending (None)))
                                        (fetch (var "S") (ending (Some (var "e"))))))
                (Ok (list (RowParameter "e") (TypeParameter "S"))))
        (expect
         (class-parameters (list "a") (list "Out") (list (fetch (var "Out") (ending (None)))))
         (Ok (list (TypeParameter "a"))))
        (expect (class-parameters (list "a") (list) (list)) (Ok (list (TypeParameter "a"))))
        ;; A row in a row argument's tail is a row, and no type.
        (expect (class-parameters (list "e")
                                  (list)
                                  (list (Con io (list (Row (ending (Some (var "e"))))))))
                (Ok (list (RowParameter "e")))))

      ;; Read off error-class-row-kind.sld and error-associated-row.sld: a
      ;; row written as a type, where a parameter, a Con's argument and a
      ;; callable's result write types; then an output that is a row; the
      ;; first row in the class's order of parameters, outputs last.
      (define (test-problems)
        (expect
         (class-parameters (list "e") (list) (list (fetch (var "e") (ending (Some (var "e"))))))
         (Err "the class parameter e is written both as a row and as a type"))
        (expect (class-parameters (list "a" "e")
                                  (list)
                                  (list (fetch (var "a") (ending (Some (var "e"))))
                                        (Code (Arrow (list)
                                                     (Con io (list (var "e")))
                                                     (Effects (list) (None))))))
                (Err "the class parameter e is written both as a row and as a type"))
        (expect (class-parameters (list "a" "e")
                                  (list)
                                  (list (fetch (var "a")
                                               (ending (Some (var "e"))))
                                        (Callable (Dyn)
                                                  (FnContract)
                                                  (Arrow (list (var "a"))
                                                         (Callable (Dyn)
                                                                   (FnContract)
                                                                   (Arrow (list)
                                                                          (var "e")
                                                                          (Effects (list) (None))))
                                                         (Effects (list) (None))))))
                (Err "the class parameter e is written both as a row and as a type"))
        (expect (class-parameters (list "b" "a")
                                  (list)
                                  (list (fetch (var "S") (ending (Some (var "a"))))
                                        (fetch (var "S") (ending (Some (var "b"))))
                                        (Code (Arrow (list (var "a") (var "b"))
                                                     text-type
                                                     (Effects (list) (None))))))
                (Err "the class parameter b is written both as a row and as a type"))
        (expect (class-parameters (list "A")
                                  (list "Output")
                                  (list (fetch (var "A") (ending (Some (var "Output"))))))
                (Err "an associated type must have kind Type, not an effect row"))
        (expect (class-parameters (list "A")
                                  (list "Output")
                                  (list (fetch (var "Output") (ending (Some (var "Output"))))))
                (Err "the class parameter Output is written both as a row and as a type"))
        ;; A row holds no type: a row argument's variable is no type.
        (expect (class-parameters (list "e")
                                  (list)
                                  (list (fetch (var "S") (ending (Some (var "e"))))
                                        (Con io (list (Row (Effects (list) (Some (var "e"))))))))
                (Ok (list (RowParameter "e")))))))
   (else)))
