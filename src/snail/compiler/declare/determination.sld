;; What determines an instance's outputs, as the old compiler's
;; `check-instance-determination` and `determined-requirement`
;; (src/snail/shell/compiler/expand.sld) decide it, for an instance of a
;; class with outputs. An instance is chosen from the types its head gives
;; the selecting parameters, so the variables those write are known first.
;; Its requirements are found in order: each needs what its own selecting
;; parameters are given known already, and makes known what it gives its
;; outputs and rows, so only an earlier requirement determines a variable.
;; The instance's outputs, and the variables its rows end with, must all
;; be known then, and no output may be a variable a row ends with. A
;; variable is what a type writes as a type (`type-variables`), compared
;; as variables are.
(define-library (snail compiler declare determination)
  (export
   determination-problem)
  (import
   (snail core base)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare equality)
   (snail compiler declare kinds))
  (begin

    ;; ---- Outputs ----

    ;; `types` are the instance's head, `outputs` the types its equations
    ;; give, and `requirements` its requirements with evidence, in order;
    ;; the class has `shape` where the instance is.
    (: determination-problem
       (impl (Fn Known ClassShape (List Type) (List Type) (List Requirement) -> (Option String))))
    (define (determination-problem known shape types outputs requirements)
      (if (null? (::outputs shape))
          (None)
          (match (determined known (variables-of (selecting shape types)) requirements)
            ((Err message) (Some message))
            ((Ok known-variables)
             (outputs-problem known-variables
                              (variables-of outputs)
                              (concatenate (map row-variable (row-arguments shape types))))))))

    (: outputs-problem
       (impl (Fn (List TypeVariable) (List TypeVariable) (List TypeVariable) -> (Option String))))
    (define (outputs-problem known-variables needed rows)
      (cond ((not (every? (lambda (variable) (variable-among? variable known-variables))
                          (append needed rows)))
             (Some "instance outputs must be determined by its inputs and earlier requirements"))
            ((any? (lambda (variable) (variable-among? variable rows)) needed)
             (Some "an associated output cannot use an effect row as a type"))
            (else (None))))

    ;; ---- Requirements ----

    ;; The variables known once each requirement is found, in order, from
    ;; those `inputs` make known.
    (: determined
       (impl
        (Fn Known (List TypeVariable) (List Requirement) -> (Result (List TypeVariable) String))))
    (define (determined known inputs requirements)
      (match requirements
        ((Nil) (Ok inputs))
        ((Cons requirement rest)
         (if (every? (lambda (variable) (variable-among? variable inputs))
                     (requirement-inputs known requirement))
             (determined known (append inputs (requirement-outputs known requirement)) rest)
             (Err "a prerequisite input must be determined before that prerequisite")))))

    ;; What choosing the requirement's evidence needs: the variables its
    ;; selecting arguments write, as its class is known here; a callable's
    ;; receiver and arrow, its class's two parameters.
    (: requirement-inputs (impl (Fn Known Requirement -> (List TypeVariable))))
    (define (requirement-inputs known requirement)
      (match requirement
        ((ClassRequirement class types) (variables-of (selecting (class-shape known class) types)))
        ((CallableRequirement _ receiver arrow)
         (append (type-variables receiver) (arrow-variables arrow)))))

    ;; What its evidence gives: the variables its outputs and rows write. A
    ;; callable class has neither.
    (: requirement-outputs (impl (Fn Known Requirement -> (List TypeVariable))))
    (define (requirement-outputs known requirement)
      (match requirement
        ((ClassRequirement class types)
         (let ((shape (class-shape known class)))
           (variables-of (append (output-arguments shape types) (row-arguments shape types)))))
        ((CallableRequirement _ _ _) (Nil))))

    (: variables-of (impl (Fn (List Type) -> (List TypeVariable))))
    (define (variables-of types)
      (concatenate (map type-variables types)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-determination)
    (import
     (snail core table)
     (snail compiler source)
     (only (snail compiler expand language) Global ClassGlobal FnContract Label)
     (snail compiler declare offer)
     (snail stage0 testing))
    (begin
      (define (test-determination)
        (test-inputs)
        (test-requirements)
        (test-rows))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define lib (list "lib"))
      (define iter-global (Global lib "Iter" 0))
      (define show-global (Global lib "Show" 0))
      (define store-global (Global lib "Store" 0))

      ;; (lib) offers (Iter c) with the output Item, (Show a), and (Store e
      ;; S) with e a row and the output Out.
      (define (class global parameters outputs)
        (Class global
               parameters
               (map (lambda (name) (Output (Label name loc) (list))) outputs)
               (list)
               (list)
               loc))

      (define known
        (Known main
               (Scanned empty-table empty-table)
               (Declarations main empty-table empty-table empty-table)
               (list (Declarations lib
                                   empty-table
                                   (by-name (by-name (by-name empty-table
                                                              "Iter"
                                                              (class iter-global
                                                                     (list (TypeParameter "c"))
                                                                     (list "Item")))
                                                     "Show"
                                                     (class show-global
                                                            (list (TypeParameter "a"))
                                                            (list)))
                                            "Store"
                                            (class store-global
                                                   (list (RowParameter "e") (TypeParameter "S"))
                                                   (list "Out")))
                                   empty-table))))

      (define iter (ClassShape "Iter" (list (TypeParameter "c")) (list "Item")))
      (define store (ClassShape "Store" (list (RowParameter "e") (TypeParameter "S")) (list "Out")))

      (define (var name)
        (Var (Written name)))

      (define (box type)
        (Con (Global main "Box" 0) (list type)))

      (define (requirement global types)
        (ClassRequirement (ClassGlobal global) types))

      (define undetermined
        "instance outputs must be determined by its inputs and earlier requirements")
      (define prerequisite "a prerequisite input must be determined before that prerequisite")

      ;; An output the head writes is determined, another is not, as the
      ;; probe determination-input.sld shows; a class with no outputs has
      ;; no such rule.
      (define (test-inputs)
        (expect (determination-problem known iter (list (box (var "a"))) (list (var "a")) (list))
                (None))
        (expect (determination-problem known iter (list (box (var "a"))) (list (var "b")) (list))
                (Some undetermined))
        (expect (determination-problem known
                                       (ClassShape "Show" (list (TypeParameter "a")) (list))
                                       (list (var "a"))
                                       (list)
                                       (list))
                (None)))

      ;; A requirement's outputs make its variables known to the ones after
      ;; it, never to the ones before (the probes determination-order.sld
      ;; and determination-prerequisite.sld).
      (define (test-requirements)
        (let ((first (requirement iter-global (list (var "a") (var "b"))))
              (second (requirement iter-global (list (var "b") (var "c")))))
          (expect
           (determination-problem known iter (list (var "a")) (list (var "c")) (list first second))
           (None))
          (expect
           (determination-problem known iter (list (var "a")) (list (var "c")) (list second first))
           (Some prerequisite))
          (expect (determination-problem known iter (list (var "a")) (list (var "c")) (list first))
                  (Some undetermined))
          ;; A requirement of a class with no outputs needs its argument
          ;; and gives nothing.
          (expect (determination-problem known
                                         iter
                                         (list (var "a"))
                                         (list (var "a"))
                                         (list (requirement show-global (list (var "z")))))
                  (Some prerequisite))
          ;; A callable needs its receiver and arrow, and gives nothing.
          (expect (determination-problem known
                                         iter
                                         (list (var "a"))
                                         (list (var "a"))
                                         (list (CallableRequirement (FnContract)
                                                                    (var "a")
                                                                    (Arrow (list (var "a"))
                                                                           (var "r")
                                                                           (Effects (list)
                                                                                    (None))))))
                  (Some prerequisite))))

      ;; The variable a row ends with is known from a requirement's row,
      ;; and is no output's type.
      (define (test-rows)
        (let ((ending (Row (Effects (list) (Some (var "e")))))
              (closed (Row (Effects (list) (None)))))
          (expect
           (determination-problem known store (list ending (var "s")) (list (var "s")) (list))
           (Some undetermined))
          (expect (determination-problem known
                                         store
                                         (list ending (var "s"))
                                         (list (var "s"))
                                         (list (requirement store-global
                                                            (list (var "e") (var "s") (var "t")))))
                  (None))
          (expect (determination-problem known
                                         store
                                         (list ending (var "s"))
                                         (list (var "e"))
                                         (list (requirement store-global
                                                            (list (var "e") (var "s") (var "t")))))
                  (Some "an associated output cannot use an effect row as a type"))
          (expect
           (determination-problem known store (list closed (var "s")) (list (var "s")) (list))
           (None))))))
   (else)))
