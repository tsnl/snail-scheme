;; The type a projection, `(Class.Output argument ...)`, stands for: what
;; the one requirement of its class in scope gives the output. A
;; requirement matches when the arguments it gives the class's selecting
;; parameters, the written ones known not to be rows, are the projection's
;; own, compared as types are; outputs and rows are given by the evidence,
;; never used to choose it. This is the old compiler's
;; `resolve-projection` (src/snail/shell/compiler/expand.sld), which
;; counts the matches among every requirement in scope, the innermost
;; first, so where one is written decides nothing but whether it is in
;; scope.
(define-library (snail compiler declare projections)
  (export
   projected)
  (import
   (snail core base)
   (only (snail compiler expand language) Global ClassGlobal FieldClass)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare equality))
  (begin

    ;; The type `(class.output argument ...)` stands for, where the class
    ;; has `shape` and `requirements` are in scope, or the old compiler's
    ;; refusal of it.
    (: projected
       (impl (Fn ClassShape Global String (List Type) (List Requirement) -> (Result Type String))))
    (define (projected shape class output arguments requirements)
      (if (= (length arguments) (length (::parameters shape)))
          (match (concatenate (map (lambda (requirement)
                                     (matching-types shape class arguments requirement))
                                   requirements))
            ((Cons found (Nil)) (Ok (output-type shape output found)))
            ((Nil) (Err "associated projection needs a matching requires constraint"))
            (_ (Err "associated projection matches multiple requirements")))
          (Err "associated projection gives each declared class parameter")))

    ;; The types `requirement` gives the class, when it is a requirement of
    ;; the class that matches the projection's arguments.
    (: matching-types (impl (Fn ClassShape Global (List Type) Requirement -> (List (List Type)))))
    (define (matching-types shape class arguments requirement)
      (match requirement
        ((ClassRequirement (ClassGlobal global) types)
         (if (and (same-global? global class)
                  (same-types? (selecting shape arguments) (selecting shape types)))
             (list types)
             (Nil)))
        ((ClassRequirement (FieldClass _) _) (Nil))
        ((CallableRequirement _ _ _) (Nil))))

    ;; What a requirement's `types` give `output`: the type after the
    ;; written parameters, at the output's position among the class's
    ;; outputs. `expand` resolves `Class.Output` only to an output of the
    ;; class, and a requirement in scope gives each of its class's
    ;; parameters, outputs included (`requirement-problem`), so the type is
    ;; there.
    (: output-type (impl (Fn ClassShape String (List Type) -> Type)))
    (define (output-type shape output types)
      (match (list-index (lambda (name) (string=? name output)) (::outputs shape))
        ((Some index)
         (match (nth types (+ (length (::parameters shape)) index))
           ((Some type) type)
           ((None) (panic "declare: a requirement in scope gives each of its class's outputs"))))
        ((None) (panic (string-append "declare: not an output of the class: " output)))))

    (: nth (All (T) (requires (Copy T)) (impl (Fn (List T) I64 -> (Option T)))))
    (define (nth items index)
      (match items
        ((Nil) (None))
        ((Cons item rest) (if (= index 0) (Some item) (nth rest (- index 1))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-projections)
    (import
     (only (snail compiler expand language) FnContract)
     (snail stage0 testing))
    (begin
      (define (test-projections)
        (test-matching)
        (test-refusals))

      (define main (list "main"))
      (define collect-global (Global main "Collect" 0))
      (define other-global (Global main "Other" 0))
      (define io (Global main "io" 0))

      ;; (Collect e c) with outputs Item and Key, e a row.
      (define collect
        (ClassShape "Collect" (list (RowParameter "e") (TypeParameter "c")) (list "Item" "Key")))

      (define (var name)
        (Var (Written name)))

      (define (row labels tail)
        (Row (Effects labels tail)))

      (define (collect-requirement e c item key)
        (ClassRequirement (ClassGlobal collect-global) (list e c item key)))

      ;; The selecting argument decides; a row argument does not, nor does
      ;; a requirement of another class, a field class or a callable.
      (define (test-matching)
        (let ((a-requirement (collect-requirement (row (list io) (None))
                                                  (var "a")
                                                  (Var (Associated 0 "Item"))
                                                  (var "k")))
              (b-requirement (collect-requirement (var "e")
                                                  (var "b")
                                                  (var "i")
                                                  (Var (Associated 1 "Key")))))
          (expect (projected collect
                             collect-global
                             "Item"
                             (list (row (list) (None)) (var "a"))
                             (list b-requirement a-requirement))
                  (Ok (Var (Associated 0 "Item"))))
          (expect (projected collect
                             collect-global
                             "Key"
                             (list (var "f") (var "b"))
                             (list b-requirement
                                   (ClassRequirement (ClassGlobal other-global)
                                                     (list (var "e") (var "b") (var "x") (var "y")))
                                   (ClassRequirement (FieldClass "count")
                                                     (list (var "b") (var "b")))
                                   (CallableRequirement (FnContract)
                                                        (var "b")
                                                        (Arrow (list)
                                                               (var "b")
                                                               (Effects (list) (None))))
                                   a-requirement))
                  (Ok (Var (Associated 1 "Key"))))
          ;; Before its rows are known, every written parameter selects.
          (expect (projected (ClassShape "Collect"
                                         (list (TypeParameter "e") (TypeParameter "c"))
                                         (list "Item" "Key"))
                             collect-global
                             "Key"
                             (list (row (list io) (None)) (var "a"))
                             (list a-requirement))
                  (Ok (var "k")))))

      (define (test-refusals)
        (let ((requirement (collect-requirement (var "e")
                                                (var "a")
                                                (var "i")
                                                (var "k"))))
          (expect (projected collect collect-global "Item" (list (var "a")) (list requirement))
                  (Err "associated projection gives each declared class parameter"))
          (expect
           (projected collect collect-global "Item" (list (var "e") (var "b")) (list requirement))
           (Err "associated projection needs a matching requires constraint"))
          (expect (projected collect collect-global "Item" (list (var "e") (var "a")) (list))
                  (Err "associated projection needs a matching requires constraint"))
          (expect (projected collect
                             collect-global
                             "Item"
                             (list (var "e") (var "a"))
                             (list requirement
                                   (collect-requirement (var "f") (var "a") (var "j") (var "l"))))
                  (Err "associated projection matches multiple requirements"))))))
   (else)))
