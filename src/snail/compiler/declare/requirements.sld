;; What a class requirement gives its class, as the old compiler checks a
;; constraint (`checked-constraint` and `check-constraint`,
;; src/snail/shell/compiler/expand.sld): the equation that gives each of
;; the class's outputs, if one does; that its equations name distinct
;; outputs of the class; and that it gives each of the class's parameters,
;; each row parameter a row or a variable, as far as the class's rows are
;; known where it is written. The old compiler checks in that order: the
;; equations once every type is resolved, then the parameters.
(define-library (snail compiler declare requirements)
  (export
   given-outputs
   equations-problem
   requirement-problem
   requirements-problem)
  (import
   (snail core base)
   (prefix (only (snail compiler expand language) Equation) expanded-)
   (snail compiler declare language)
   (snail compiler declare known))
  (begin

    ;; ---- Outputs ----

    ;; For each of the class's outputs, in the class's order, the first
    ;; equation that names it, or none, which leaves the output to a
    ;; variable of the scheme. Only these equations' types are resolved: an
    ;; equation for no output, or for one an earlier equation gives, is
    ;; refused before its type is looked at.
    (: given-outputs
       (impl (Fn ClassShape (List expanded-Equation) -> (List (Option expanded-Equation)))))
    (define (given-outputs shape equations)
      (map (lambda (output)
             (find (lambda (equation) (string=? (::name (::label equation)) output)) equations))
           (::outputs shape)))

    ;; Each equation names an output of the class, and no two the same.
    (: equations-problem (impl (Fn ClassShape (List expanded-Equation) -> (Option String))))
    (define (equations-problem shape equations)
      (let ((names (map (lambda (equation) (::name (::label equation))) equations)))
        (if (and (= (length names) (length (delete-duplicates string=? names)))
                 (every? (lambda (name) (member? name (::outputs shape))) names))
            (None)
            (Some "constraint has an unknown or repeated associated type equality"))))

    ;; ---- Parameters ----

    ;; `types` gives each of the class's parameters, its outputs last, and
    ;; each parameter known to be a row a row or a variable. The message
    ;; names the class and its parameters, its outputs among them, as the
    ;; old compiler spells a class's parameters.
    (: requirement-problem (impl (Fn ClassShape (List Type) -> (Option String))))
    (define (requirement-problem shape types)
      (if (= (length types) (+ (length (::parameters shape)) (length (::outputs shape))))
          (row-problem shape types)
          (Some (string-append "a constraint gives each of the class's parameters, as in "
                               (written-class shape)))))

    (: row-problem (impl (Fn ClassShape (List Type) -> (Option String))))
    (define (row-problem shape types)
      (match (find (lambda (pair) (not (gives-row? (::first pair) (::second pair))))
                   (zip (::parameters shape) types))
        ((Some pair)
         (Some (string-append "a constraint gives the class's row parameter "
                              (parameter-name (::first pair))
                              " a row")))
        ((None) (None))))

    ;; A type parameter takes any type; a row parameter a row or a
    ;; variable, which may stand for one.
    (: gives-row? (impl (Fn ClassParameter Type -> Bool)))
    (define (gives-row? parameter type)
      (match parameter
        ((TypeParameter _) #t)
        ((RowParameter _)
         (match type
           ((Row _) #t)
           ((Var _) #t)
           (_ #f)))))

    ;; ---- Converted requirements ----

    ;; The first of a scheme's class requirements that does not give its
    ;; class what it takes, each class as `known` knows it, as the old
    ;; compiler checks a definition's signature again once every class of
    ;; the library is declared (`check-signature`). A callable requirement
    ;; gives the compiler's class its receiver and its arrow, and is never
    ;; refused.
    (: requirements-problem (impl (Fn Known (List Requirement) -> (Option String))))
    (define (requirements-problem known requirements)
      (match requirements
        ((Nil) (None))
        ((Cons (ClassRequirement class types) rest)
         (match (requirement-problem (class-shape known class) types)
           ((Some message) (Some message))
           ((None) (requirements-problem known rest))))
        ((Cons (CallableRequirement _ _ _) rest) (requirements-problem known rest))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-requirements)
    (import
     (snail core table)
     (snail compiler source)
     (only (snail compiler expand language) Global Label ClassGlobal FieldClass FnContract)
     (prefix (only (snail compiler expand language) Variable) expanded-)
     (snail compiler declare offer)
     (snail stage0 testing))
    (begin
      (define (test-requirements)
        (test-outputs)
        (test-equations)
        (test-parameters)
        (test-converted))

      (define loc (Loc "t.sld" 1 1))

      (define (equation name variable)
        (expanded-Equation (Label name loc) (expanded-Variable variable loc)))

      ;; (Collect c) with outputs Item and Key; (Store e s), e a row.
      (define collect
        (ClassShape "Collect" (list (TypeParameter "c")) (list "Item" "Key")))

      (define store
        (ClassShape "Store" (list (RowParameter "e") (TypeParameter "s")) (list)))

      (define unit-type (Con (Global (list "snail" "core" "forms") "Unit" 0) (list)))

      ;; In the class's order of outputs, the first equation for each.
      (define (test-outputs)
        (let ((key (equation "Key" "k"))
              (item (equation "Item" "i"))
              (again (equation "Item" "j")))
          (expect (given-outputs collect (list key item again)) (list (Some item) (Some key)))
          (expect (given-outputs collect (list key)) (list (None) (Some key)))
          (expect (given-outputs store (list key)) (list))))

      (define (test-equations)
        (expect (equations-problem collect (list (equation "Key" "k") (equation "Item" "i")))
                (None))
        (expect (equations-problem collect (list)) (None))
        (expect (equations-problem collect (list (equation "Item" "i") (equation "Item" "j")))
                (Some "constraint has an unknown or repeated associated type equality"))
        (expect (equations-problem collect (list (equation "Size" "s")))
                (Some "constraint has an unknown or repeated associated type equality")))

      ;; The count first, outputs included, then each row parameter.
      (define (test-parameters)
        (let ((c (Var (Written "c")))
              (item (Var (Associated 0 "Item"))))
          (expect (requirement-problem collect (list c item item)) (None))
          (expect (requirement-problem collect (list c c item item))
                  (Some
                   "a constraint gives each of the class's parameters, as in (Collect c Item Key)"))
          (expect (requirement-problem store (list (Row (Effects (list) (None))) c)) (None))
          (expect (requirement-problem store (list (Var (Written "e")) c)) (None))
          (expect (requirement-problem store (list unit-type c))
                  (Some "a constraint gives the class's row parameter e a row"))
          (expect (requirement-problem (ClassShape "count"
                                                   (list (TypeParameter "R") (TypeParameter "T"))
                                                   (list))
                                       (list c))
                  (Some "a constraint gives each of the class's parameters, as in (count R T)"))))

      ;; A scheme's requirements with each class as known: (main)'s Store,
      ;; whose e is a row once its declaration is reached, and a type
      ;; before, as its scan finds it. The first problem, in order; a
      ;; callable requirement is never one.
      (define (test-converted)
        (let* ((main (list "main"))
               (store-global (Global main "Store" 0))
               (scanned (Scanned empty-table
                                 (by-name empty-table
                                          "Store"
                                          (ScannedClass store-global (list "e" "S") (list)))))
               (store-class (Class store-global
                                   (list (RowParameter "e") (TypeParameter "S"))
                                   (list)
                                   (list)
                                   (list)
                                   loc))
               (before
                (Known main scanned (Declarations main empty-table empty-table empty-table) (list)))
               (after (Known main
                             scanned
                             (Declarations main
                                           empty-table
                                           (by-name empty-table "Store" store-class)
                                           empty-table)
                             (list)))
               (s (Var (Written "S")))
               (given (lambda (row) (ClassRequirement (ClassGlobal store-global) (list row s))))
               (callable (CallableRequirement (FnContract)
                                              s
                                              (Arrow (list) unit-type (Effects (list) (None))))))
          (expect (requirements-problem before (list callable (given unit-type))) (None))
          (expect (requirements-problem after (list callable (given unit-type)))
                  (Some "a constraint gives the class's row parameter e a row"))
          (expect
           (requirements-problem after (list (given (Row (Effects (list) (None)))) (given s)))
           (None))
          (expect (requirements-problem after
                                        (list (ClassRequirement (FieldClass "x") (list s))
                                              (given unit-type)))
                  (Some "a constraint gives each of the class's parameters, as in (x R T)"))))))
   (else)))
