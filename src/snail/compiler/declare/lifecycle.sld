;; What a lifecycle instance may be, and what a Drop instance says of its
;; type, as the old compiler's `instance-program`, `check-head-label`,
;; `check-lifecycle-requirements`, `lifecycle-program` and
;; `check-lifecycle-head` (src/snail/shell/compiler/expand.sld) decide it.
;; The lifecycle classes are Drop and Clone, `(Drop e T)` and `(Clone e T)`,
;; whose instance says how a value of T is dropped or cloned, performing
;; the row e. A drop or a clone must run to completion, so its row performs
;; no control effect. It finds what it runs from its type alone, so it
;; requires nothing but its own class at its variables, `(Drop e A)`, whose
;; row its own row ends with; a row that ends with a variable needs such a
;; requirement. It is declared beside its type, for the type at distinct
;; variables, so a type has one of each class, and in no named instance
;; set, since it must be found wherever a value of the type is.
;;
;; A Drop instance makes the values of its type moved, never copied, as
;; the old compiler makes the type owned, and decides who may take them
;; apart.
(define-library (snail compiler declare lifecycle)
  (export
   set-problem
   control-problem
   lifecycle-usage
   lifecycle-requirements-problem
   lifecycle-head-problem
   drop-type
   with-drops)
  (import
   (snail core base)
   (snail compiler names libraries)
   (only (snail compiler expand language) Dyn FnContract)
   (snail compiler declare language)
   (snail compiler declare known)
   (only (snail compiler builtins base)
         drop-class
         clone-class
         Lifecycle
         Dropping
         Cloning
         lifecycle-class)
   (snail compiler declare equality)
   (only (snail compiler names globals) Global ClassGlobal same-global?))
  (begin

    ;; ---- Sets ----

    ;; `in-set?` says that the instance is written in a named instance set.
    (: set-problem (impl (Fn (Option Lifecycle) Bool -> (Option String))))
    (define (set-problem lifecycle in-set?)
      (match lifecycle
        ((Some _)
         (if in-set? (Some "lifecycle instances cannot belong to a named instance set") (None)))
        ((None) (None))))

    ;; ---- Rows ----

    ;; Whether the effect `label`, which the instance's row names, may be
    ;; performed by a drop or a clone: not when it has a control operation.
    ;; Only an effect known where the instance is written is checked: one
    ;; of the import closure's, or of the library's own declared before the
    ;; instance, as the old compiler finds only the effects in its program
    ;; so far; one declared after it is not checked at all.
    (: control-problem (impl (Fn Known Lifecycle Global -> (Option String))))
    (define (control-problem known lifecycle label)
      (match (known-operations known label)
        ((Some operations)
         (if (any? ::control? operations)
             (Some (string-append (match lifecycle
                                    ((Dropping) "a drop")
                                    ((Cloning) "a clone"))
                                  " cannot perform the control effect "
                                  (::name label)))
             (None)))
        ((None) (None))))

    ;; The refusal of a lifecycle instance's row, `shape` being its
    ;; class's.
    (: lifecycle-usage (impl (Fn ClassShape -> String)))
    (define (lifecycle-usage shape)
      (string-append (instance-noun shape)
                     "'s row is closed, (! label ...), or ends with the row e of its requirements ("
                     (::name shape)
                     " e A), as (! label ... e)"))

    ;; ---- Requirements ----

    ;; `head` is the instance's types, its row first, `variables` its
    ;; variables and `requirements` its requirements with evidence: each,
    ;; in order, is its own class at the variable its row ends with and one
    ;; of its variables; and a row that ends with a variable has one.
    (: lifecycle-requirements-problem
       (impl (Fn Lifecycle
                 ClassShape
                 (List Type)
                 (List TypeVariable)
                 (List Requirement)
                 ->
                 (Option String))))
    (define (lifecycle-requirements-problem lifecycle shape head variables requirements)
      (let ((tail (row-tail head)))
        (let loop ((remaining requirements))
          (match remaining
            ((Nil)
             (match (Pair tail requirements)
               ((Pair (Some _) (Nil)) (Some (lifecycle-usage shape)))
               (_ (None))))
            ((Cons requirement rest)
             (match (requirement-problem lifecycle shape tail variables requirement)
               ((Some message) (Some message))
               ((None) (loop rest))))))))

    ;; What the instance's row ends with: the tail of its first type, when
    ;; that is a row.
    (: row-tail (impl (Fn (List Type) -> (Option Type))))
    (define (row-tail head)
      (match head
        ((Cons (Row effects) _) (::tail effects))
        (_ (None))))

    (: requirement-problem
       (impl
        (Fn Lifecycle ClassShape (Option Type) (List TypeVariable) Requirement -> (Option String))))
    (define (requirement-problem lifecycle shape tail variables requirement)
      (match requirement
        ((ClassRequirement (ClassGlobal class) types)
         (if (same-global? class (lifecycle-class lifecycle))
             (requirement-row-problem shape tail variables types)
             (Some (only-own shape))))
        (_ (Some (only-own shape)))))

    (: only-own (impl (Fn ClassShape -> String)))
    (define (only-own shape)
      (string-append (instance-noun shape)
                     " can require only (Copy A) and ("
                     (::name shape)
                     " e A)"))

    ;; `(Class e A)`, `e` the variable the instance's row ends with and `A`
    ;; one of its variables.
    (: requirement-row-problem
       (impl (Fn ClassShape (Option Type) (List TypeVariable) (List Type) -> (Option String))))
    (define (requirement-row-problem shape tail variables types)
      (match (Pair tail types)
        ((Pair (Some (Var ending)) (Cons (Var row) (Cons (Var variable) (Nil))))
         (if (and (same-variable? ending row)
                  (variable-among? variable variables))
             (None)
             (Some (lifecycle-usage shape))))
        (_ (Some (lifecycle-usage shape)))))

    ;; ---- Heads ----

    ;; An instance of a lifecycle class, in `library`, is for a row and a
    ;; declared type of `library` at distinct variables. The old compiler
    ;; writes a callable stored as FnMut or FnOnce, an `impl` callable and
    ;; code as an application of a name of no library, so such a head is
    ;; for a type of another library; a `(dyn (Fn ...))` is its bare arrow,
    ;; no application at all.
    (: lifecycle-head-problem
       (impl (Fn (Option Lifecycle) LibraryName ClassShape (List Type) -> (Option String))))
    (define (lifecycle-head-problem lifecycle library shape head)
      (match (Pair lifecycle head)
        ((Pair (None) _) (None))
        ((Pair (Some _) (Cons _ (Cons type (Nil)))) (head-type-problem library shape type))
        (_ (Some (names-type shape)))))

    (: head-type-problem (impl (Fn LibraryName ClassShape Type -> (Option String))))
    (define (head-type-problem library shape type)
      (match type
        ((Con global arguments)
         (cond ((not (same-library? (::library global) library)) (Some (beside-type shape)))
               ((distinct-variables? arguments) (None))
               (else
                (Some
                 (string-append (instance-noun shape) " is for its type at distinct variables")))))
        ((Callable (Dyn) (FnContract) _) (Some (names-type shape)))
        ((Callable _ _ _) (Some (beside-type shape)))
        ((Code _) (Some (beside-type shape)))
        (_ (Some (names-type shape)))))

    (: names-type (impl (Fn ClassShape -> String)))
    (define (names-type shape)
      (string-append (instance-noun shape) " names a row and a declared type"))

    (: beside-type (impl (Fn ClassShape -> String)))
    (define (beside-type shape)
      (string-append (instance-noun shape) " is declared in the library of its type"))

    (: distinct-variables? (impl (Fn (List Type) -> Bool)))
    (define (distinct-variables? types)
      (let ((variables (concatenate (map (lambda (type)
                                           (match type
                                             ((Var variable) (list variable))
                                             (_ (Nil))))
                                         types))))
        (and (= (length variables) (length types))
             (= (length (delete-duplicates same-variable? variables)) (length variables)))))

    ;; ---- Drop ----

    ;; The type a Drop instance is for. Every lifecycle instance `declare`
    ;; accepts is for a declared type of its own library
    ;; (`lifecycle-head-problem`), so the type is one of the library's.
    (: drop-type (impl (Fn Instance -> (Option Global))))
    (define (drop-type instance)
      (match (Pair (::class instance) (::types instance))
        ((Pair (ClassGlobal class) (Cons _ (Cons (Con type _) (Nil))))
         (if (same-global? class drop-class) (Some type) (None)))
        (_ (None))))

    ;; `data`, saying whether it is among the types `dropped`, which have a
    ;; Drop instance.
    (: with-drops (impl (Fn Data (List Global) -> Data)))
    (define (with-drops data dropped)
      (Data (::global data)
            (::parameters data)
            (::cases data)
            (::kind data)
            (::move? data)
            (any? (lambda (type) (same-global? type (::global data))) dropped)
            (::annotations data)
            (::loc data)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-lifecycle)
    (import
     (snail core table)
     (snail compiler source)
     (only (snail compiler expand language) Impl FnMutContract)
     (only (snail compiler names globals) FieldClass)
     (snail compiler declare offer)
     (snail stage0 testing))
    (begin
      (define (test-lifecycle)
        (test-sets)
        (test-control)
        (test-requirements)
        (test-heads)
        (test-drops))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define base (list "snail" "core" "base"))
      (define handle (Global main "Handle" 0))
      (define pair-type (Global base "Pair" 0))

      (define drop-shape (ClassShape "Drop" (list (RowParameter "e") (TypeParameter "T")) (list)))
      (define clone-shape (ClassShape "Clone" (list (RowParameter "e") (TypeParameter "T")) (list)))

      (define (var name)
        (Var (Written name)))

      (define (row labels tail)
        (Row (Effects labels tail)))

      (define (drop-of types)
        (ClassRequirement (ClassGlobal drop-class) types))

      ;; Read off error-instance-set-lifecycle.sld.
      (define (test-sets)
        (expect (set-problem (Some (Dropping)) #t)
                (Some "lifecycle instances cannot belong to a named instance set"))
        (expect (set-problem (Some (Cloning)) #f) (None))
        (expect (set-problem (None) #t) (None)))

      ;; (main) declares the effect Gen, with a control operation, and
      ;; audit, with none; (snail core base) offers dyn-cast, whose
      ;; operation is a control one (error-drop-control.sld and
      ;; error-dyn-cast-drop.sld). An effect not yet known is not checked.
      (define (test-control)
        (let* ((operation (lambda (library name control?)
                            (Operation (Global library name 0)
                                       control?
                                       (list)
                                       (Con (Global forms-library "Unit" 0) (list))
                                       (list)
                                       (list)
                                       loc)))
               (gen (Global main "Gen" 0))
               (audit (Global main "audit" 0))
               (dyn-cast (Global base "dyn-cast" 0))
               (known (Known main
                             (Scanned empty-table empty-table)
                             (Declarations main
                                           empty-table
                                           empty-table
                                           (by-name (by-name empty-table
                                                             "Gen"
                                                             (OfferedEffect gen
                                                                            (list (operation main
                                                                                             "next"
                                                                                             #t))))
                                                    "audit"
                                                    (OfferedEffect audit
                                                                   (list (operation main
                                                                                    "note"
                                                                                    #f)))))
                             (list (Declarations base
                                                 empty-table
                                                 empty-table
                                                 (by-name empty-table
                                                          "dyn-cast"
                                                          (OfferedEffect dyn-cast
                                                                         (list (operation base
                                                                                          "cast"
                                                                                          #t)))))))))
          (expect (control-problem known (Dropping) gen)
                  (Some "a drop cannot perform the control effect Gen"))
          (expect (control-problem known (Cloning) dyn-cast)
                  (Some "a clone cannot perform the control effect dyn-cast"))
          (expect (control-problem known (Dropping) audit) (None))
          (expect (control-problem known (Dropping) (Global main "later" 0)) (None))
          (expect (control-problem known (Dropping) (Global forms-library "mut" 0)) (None))))

      (define open-row
        "a Drop instance's row is closed, (! label ...), or ends with the row e of its requirements (Drop e A), as (! label ... e)")

      (define (requirements-of head requirements)
        (lifecycle-requirements-problem (Dropping)
                                        drop-shape
                                        head
                                        (list (Written "A") (Written "e"))
                                        requirements))

      ;; Read off error-drop-open-row.sld, error-drop-requires-row.sld,
      ;; error-drop-requires-class.sld and error-clone-requires-class.sld:
      ;; each requirement in order, its class before its row, and then a
      ;; row that ends with a variable and has no requirement.
      (define (test-requirements)
        (let ((box (Con (Global main "Box" 0) (list (var "A")))))
          (expect (requirements-of (list (row (list) (None)) box) (list)) (None))
          (expect (requirements-of (list (row (list) (Some (var "e"))) box)
                                   (list (drop-of (list (var "e") (var "A")))))
                  (None))
          (expect (requirements-of (list (var "e") (Con handle (list))) (list)) (None))
          (expect (requirements-of (list (row (list) (Some (var "e"))) (Con handle (list))) (list))
                  (Some open-row))
          (expect (requirements-of (list (row (list) (None)) box)
                                   (list (drop-of (list (var "e") (var "A")))))
                  (Some open-row))
          (expect (requirements-of (list (row (list) (Some (var "e"))) box)
                                   (list (drop-of (list (var "f") (var "A")))))
                  (Some open-row))
          (expect (requirements-of (list (row (list) (Some (var "e"))) box)
                                   (list (drop-of (list (var "e") (var "B")))))
                  (Some open-row))
          (expect (requirements-of (list (row (list) (None)) box)
                                   (list (ClassRequirement (ClassGlobal (Global base "Show" 0))
                                                           (list (row (list) (None)) (var "A")))))
                  (Some "a Drop instance can require only (Copy A) and (Drop e A)"))
          (expect (requirements-of (list (row (list) (None)) box)
                                   (list (drop-of (list (var "e") (var "A")))
                                         (ClassRequirement (ClassGlobal clone-class)
                                                           (list (var "e") (var "A")))))
                  (Some open-row))
          (expect (lifecycle-requirements-problem (Cloning)
                                                  clone-shape
                                                  (list (row (list) (Some (var "e"))) box)
                                                  (list (Written "A") (Written "e"))
                                                  (list (drop-of (list (var "e") (var "A")))))
                  (Some "a Clone instance can require only (Copy A) and (Clone e A)"))))

      ;; Read off error-drop-foreign.sld: the head's count and shape, then
      ;; its library, then its variables; an instance of no lifecycle class
      ;; has none of these rules.
      (define (test-heads)
        (let ((closed (row (list) (None)))
              (head-of
               (lambda (head) (lifecycle-head-problem (Some (Dropping)) main drop-shape head)))
              (names "a Drop instance names a row and a declared type")
              (beside "a Drop instance is declared in the library of its type"))
          (expect (head-of (list closed (Con handle (list)))) (None))
          (expect (head-of (list closed (Con handle (list (var "a") (var "b"))))) (None))
          (expect (head-of (list closed (Con pair-type (list (var "A") (var "B"))))) (Some beside))
          (expect (head-of (list closed (Con (Global forms-library "I64" 0) (list)))) (Some beside))
          (expect (head-of (list closed (Con handle (list (var "a") (var "a")))))
                  (Some "a Drop instance is for its type at distinct variables"))
          (expect (head-of (list closed (Con handle (list (Con handle (list))))))
                  (Some "a Drop instance is for its type at distinct variables"))
          (expect (head-of (list closed (var "T"))) (Some names))
          (expect (head-of (list closed)) (Some names))
          (expect (head-of (list closed (Con handle (list)) closed)) (Some names))
          (let ((arrow (Arrow (list) (Con handle (list)) (Effects (list) (None)))))
            (expect (head-of (list closed (Callable (Dyn) (FnContract) arrow))) (Some names))
            (expect (head-of (list closed (Callable (Dyn) (FnMutContract) arrow))) (Some beside))
            (expect (head-of (list closed (Callable (Impl) (FnContract) arrow))) (Some beside))
            (expect (head-of (list closed (Code arrow))) (Some beside)))
          (expect (lifecycle-head-problem (None) main drop-shape (list (var "T"))) (None))))

      (define (test-drops)
        (let* ((closed (row (list) (None)))
               (instance (lambda (class types)
                           (Instance (Global main "Drop" 7)
                                     class
                                     (list)
                                     types
                                     (list)
                                     (list)
                                     (list)
                                     (Methods (list))
                                     loc))))
          (expect (drop-type (instance (ClassGlobal drop-class) (list closed (Con handle (list)))))
                  (Some handle))
          (expect (drop-type (instance (ClassGlobal clone-class) (list closed (Con handle (list)))))
                  (None))
          (expect (drop-type (instance (FieldClass "x") (list closed (Con handle (list))))) (None))
          (let ((data (Data handle (list) (list) (StructData) #f #f (list) loc)))
            (expect (::drop? (with-drops data (list handle))) #t)
            (expect (::drop? (with-drops data (list (Global main "Handle" 2)))) #f))))))
   (else)))
