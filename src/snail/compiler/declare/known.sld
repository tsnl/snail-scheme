;; What a library's declaration knows, at one point of it, of the types and
;; classes a written type can name, and what a name is known as there. It
;; knows what the libraries in its import closure offer, complete. Of its
;; own declarations it knows two things: from the start, the shapes the
;; scan finds, as the old scan registers them, each type's parameters and
;; each class's parameters and outputs; and each declaration once it is
;; reached, as its entity, kept as the Declarations the library will
;; offer. So a class of the library's own is known by its shape alone,
;; every parameter a type and no method, until its declaration is reached,
;; as in the old compiler, where a declaration sees only those before it.
(define-library (snail compiler declare known)
  (export
   Known
   Scanned
   ScannedType
   ScannedClass
   ClassShape
   type-arity
   arity-problem
   class-shape
   known-with-data
   known-with-class
   known-with-effect
   known-class
   known-data
   constructor-case
   effect-operations
   by-name)
  (import
   (snail core base)
   (snail core table)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler outline names) same-library?)
   (only (snail compiler expand language) Global ClassRef ClassGlobal FieldClass)
   (snail compiler declare language)
   (snail compiler declare offer)
   (snail compiler declare forms)
   (snail compiler declare equality))
  (begin

    ;; ---- What is known ----

    ;; `library` is the library being declared, `declared` its entities so
    ;; far, and `imported` the offers of every library in its import
    ;; closure, each library's once.
    (struct Known
      ((library LibraryName)
       (scanned Scanned)
       (declared Declarations)
       (imported (List Declarations))))

    ;; The library's own types and classes, by name, a list for the
    ;; Globals that share one when a macro's template wrote them.
    (struct Scanned
      ((types (Table (List ScannedType)))
       (classes (Table (List ScannedClass)))))

    (struct ScannedType
      ((global Global)
       (parameters (List String))))

    (struct ScannedClass
      ((global Global)
       (parameters (List String))
       (outputs (List String))))

    ;; A class as a written type or a requirement sees it where it is
    ;; written: the name messages give it, its written parameters, each a
    ;; type or a row as far as is known there, and its outputs.
    (struct ClassShape
      ((name String)
       (parameters (List ClassParameter))
       (outputs (List String))))

    ;; ---- Types ----

    ;; How many arguments a type a written type names takes: a builtin's,
    ;; or as many as its declaration has parameters, which the scan knows
    ;; of the library's own.
    (: type-arity (impl (Fn Known Global -> I64)))
    (define (type-arity known global)
      (match (builtin-arity global)
        ((Some arity) arity)
        ((None)
         (if (own? known global)
             (length (::parameters (scanned-type known global)))
             (length (::parameters (offered-data known global)))))))

    ;; The old compiler's refusal of a type named `written` and given
    ;; `count` arguments, when it takes another number.
    (: arity-problem (impl (Fn Known Global String I64 -> (Option String))))
    (define (arity-problem known global written count)
      (if (= (type-arity known global) count)
          (None)
          (Some (string-append "wrong number of type arguments: " written))))

    ;; ---- Classes ----

    ;; A field class `::label` is `(::label R T)`: a record type and its
    ;; field's type, both types, and no output. A declared class is its
    ;; entity once its declaration is reached, and its scanned shape
    ;; before that.
    (: class-shape (impl (Fn Known ClassRef -> ClassShape)))
    (define (class-shape known class)
      (match class
        ((FieldClass label) (ClassShape label (list (TypeParameter "R") (TypeParameter "T")) (Nil)))
        ((ClassGlobal global)
         (if (own? known global)
             (match (declared-class (::declared known) global)
               ((Some declared) (entity-shape declared))
               ((None) (scanned-shape (scanned-class known global))))
             (entity-shape (offered-class known global))))))

    (: entity-shape (impl (Fn Class -> ClassShape)))
    (define (entity-shape class)
      (ClassShape (::name (::global class))
                  (::parameters class)
                  (map (lambda (output) (::name (::label output))) (::outputs class))))

    (: scanned-shape (impl (Fn ScannedClass -> ClassShape)))
    (define (scanned-shape class)
      (ClassShape (::name (::global class))
                  (map (lambda (name) (TypeParameter name)) (::parameters class))
                  (::outputs class)))

    ;; A declared class as an instance sees it: its entity, once its
    ;; declaration is reached or when it is imported. A class of the
    ;; library's own whose declaration is not yet reached is known by its
    ;; shape alone, so it has no method an instance can implement, as in
    ;; the old compiler, where the scan registers a class without methods.
    (: known-class (impl (Fn Known Global -> (Option Class))))
    (define (known-class known global)
      (if (own? known global)
          (declared-class (::declared known) global)
          (Some (offered-class known global))))

    ;; ---- Declarations reached ----

    ;; What is known once a declaration is reached: its entity, among the
    ;; library's own.
    (: known-with-data (impl (Fn Known Data -> Known)))
    (define (known-with-data known data)
      (let ((declared (::declared known)))
        (with-declared known
                       (Declarations (::library declared)
                                     (by-name (::data declared) (::name (::global data)) data)
                                     (::classes declared)
                                     (::effects declared)))))

    (: known-with-class (impl (Fn Known Class -> Known)))
    (define (known-with-class known class)
      (let ((declared (::declared known)))
        (with-declared known
                       (Declarations (::library declared)
                                     (::data declared)
                                     (by-name (::classes declared) (::name (::global class)) class)
                                     (::effects declared)))))

    (: known-with-effect (impl (Fn Known OfferedEffect -> Known)))
    (define (known-with-effect known effect)
      (let ((declared (::declared known)))
        (with-declared known
                       (Declarations (::library declared)
                                     (::data declared)
                                     (::classes declared)
                                     (by-name (::effects declared)
                                              (::name (::global effect))
                                              effect)))))

    (: with-declared (impl (Fn Known Declarations -> Known)))
    (define (with-declared known declared)
      (Known (::library known) (::scanned known) declared (::imported known)))

    ;; `table` with `entry` after those already kept under `name`, as an
    ;; offer keeps the Globals that share a name.
    (: by-name
       (All (T) (requires (Copy T)) (impl (Fn (Table (List T)) String T -> (Table (List T))))))
    (define (by-name table name entry)
      (table-set table
                 name
                 (append (match (table-ref table name)
                           ((Some entries) entries)
                           ((None) (Nil)))
                         (list entry))))

    ;; ---- Data and effects ----

    ;; The data type a type's Global names, declared by the library or one
    ;; in its import closure; a builtin of (snail core forms) is none. A
    ;; type of the library's own is known once its declaration is reached.
    (: known-data (impl (Fn Known Global -> (Option Data))))
    (define (known-data known global)
      (match (builtin-arity global)
        ((Some _) (None))
        ((None)
         (if (own? known global)
             (named global (::data (::declared known)) ::global)
             (Some (offered-data known global))))))

    ;; The case a constructor makes, with its data type, when `global` is
    ;; one: a struct, whose one case is its own Global, or an enum's case.
    ;; Any other top-level value is none, a primitive's among them, whose
    ;; library ("prim") offers nothing.
    (: constructor-case (impl (Fn Known Global -> (Option (Pair Data DataCase)))))
    (define (constructor-case known global)
      (match (library-declarations known (::library global))
        ((Some declarations)
         (first-case global (concatenate (table-values (::data declarations)))))
        ((None) (None))))

    (: first-case (impl (Fn Global (List Data) -> (Option (Pair Data DataCase)))))
    (define (first-case global types)
      (match types
        ((Nil) (None))
        ((Cons data rest)
         (match (find (lambda (case) (same-global? (::global case) global)) (::cases data))
           ((Some case) (Some (Pair data case)))
           ((None) (first-case global rest))))))

    ;; The operations of an effect a handler names. `expand` resolves a
    ;; handler's effect to an effect of the library or of its import
    ;; closure, never a builtin one, and every body is declared once every
    ;; declaration is reached, so the effect is known.
    (: effect-operations (impl (Fn Known Global -> (List Operation))))
    (define (effect-operations known global)
      (match (match (library-declarations known (::library global))
               ((Some declarations) (named global (::effects declarations) ::global))
               ((None) (None)))
        ((Some effect) (::operations effect))
        ((None) (panic (string-append "declare: no effect " (::name global))))))

    ;; What is known of the library named `library`: the library's own
    ;; declarations so far, or what an imported library offers.
    (: library-declarations (impl (Fn Known LibraryName -> (Option Declarations))))
    (define (library-declarations known library)
      (if (same-library? library (::library known))
          (Some (::declared known))
          (find (lambda (offer) (same-library? (::library offer) library)) (::imported known))))

    ;; ---- Lookups ----

    ;; `expand` resolves a type's name to a struct, an enum or a builtin,
    ;; and a class's to a class, of the library or of one in its import
    ;; closure; the integrator hands `declare` the offers of that closure,
    ;; and the scan finds the library's own. So a lookup of a name a
    ;; written type holds finds it, and a miss is a compiler bug.

    (: own? (impl (Fn Known Global -> Bool)))
    (define (own? known global)
      (same-library? (::library global) (::library known)))

    (: scanned-type (impl (Fn Known Global -> ScannedType)))
    (define (scanned-type known global)
      (match (named global (::types (::scanned known)) ::global)
        ((Some found) found)
        ((None) (panic (string-append "declare: the scan found no type " (::name global))))))

    (: scanned-class (impl (Fn Known Global -> ScannedClass)))
    (define (scanned-class known global)
      (match (named global (::classes (::scanned known)) ::global)
        ((Some found) found)
        ((None) (panic (string-append "declare: the scan found no class " (::name global))))))

    (: declared-class (impl (Fn Declarations Global -> (Option Class))))
    (define (declared-class declarations global)
      (named global (::classes declarations) ::global))

    (: offered-data (impl (Fn Known Global -> Data)))
    (define (offered-data known global)
      (match (named global (::data (offer-of known global)) ::global)
        ((Some found) found)
        ((None) (panic (string-append "declare: no library offers the type " (::name global))))))

    (: offered-class (impl (Fn Known Global -> Class)))
    (define (offered-class known global)
      (match (declared-class (offer-of known global) global)
        ((Some found) found)
        ((None) (panic (string-append "declare: no library offers the class " (::name global))))))

    (: offer-of (impl (Fn Known Global -> Declarations)))
    (define (offer-of known global)
      (match (find (lambda (offer) (same-library? (::library offer) (::library global)))
                   (::imported known))
        ((Some offer) offer)
        ((None) (panic (string-append "declare: no offer of the library of " (::name global))))))

    ;; The entry of `table` for `global`'s name whose Global is `global`.
    (: named
       (All (T Key)
            (requires (Copy T)
                      (Copy Key)
                      (Fn Key T -> Global))
            (impl (Fn Global (Table (List T)) Key -> (Option T)))))
    (define (named global table key)
      (match (table-ref table (::name global))
        ((Some entries) (find (lambda (entry) (same-global? (key entry) global)) entries))
        ((None) (None))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-known)
    (import
     (snail compiler source)
     (only (snail compiler expand language) Label)
     (snail stage0 testing))
    (begin
      (define (test-known)
        (test-arities)
        (test-classes)
        (test-reached)
        (test-constructors))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define lib (list "lib"))

      (define (global library name)
        (Global library name 0))

      ;; (main) scans the types Box a and Box at serial 3, and the class
      ;; (Show a) with output Out; (lib) offers the type (Pair a b) and the
      ;; class (Store e s), whose e is a row.
      (define scanned
        (Scanned (by-name (by-name empty-table "Box" (ScannedType (global main "Box") (list "a")))
                          "Box"
                          (ScannedType (Global main "Box" 3) (list)))
                 (by-name empty-table
                          "Show"
                          (ScannedClass (global main "Show") (list "a") (list "Out")))))

      (define store
        (Class (global lib "Store")
               (list (RowParameter "e") (TypeParameter "s"))
               (list)
               (list)
               (list)
               loc))

      (define lib-offer
        (Declarations lib
                      (by-name empty-table
                               "Pair"
                               (Data (global lib "Pair")
                                     (list "a" "b")
                                     (list)
                                     (StructData)
                                     #f
                                     #f
                                     (list)
                                     loc))
                      (by-name empty-table "Store" store)
                      empty-table))

      (define nothing-declared
        (Declarations main empty-table empty-table empty-table))

      (define known
        (Known main scanned nothing-declared (list lib-offer)))

      ;; A builtin's arity, a scanned type's by its serial too, and an
      ;; imported type's.
      (define (test-arities)
        (expect (type-arity known (Global forms-library "Array" 0)) 1)
        (expect (type-arity known (global main "Box")) 1)
        (expect (type-arity known (Global main "Box" 3)) 0)
        (expect (type-arity known (global lib "Pair")) 2)
        (expect (arity-problem known (global lib "Pair") "Pair" 2) (None))
        (expect (arity-problem known (global lib "Pair") "P" 1)
                (Some "wrong number of type arguments: P")))

      ;; A field class's fixed shape; the library's own class by its scan
      ;; until it is declared, then by its entity, rows and all; an
      ;; imported class by its entity.
      (define (test-classes)
        (expect (class-shape known (FieldClass "count"))
                (ClassShape "count" (list (TypeParameter "R") (TypeParameter "T")) (list)))
        (expect (class-shape known (ClassGlobal (global main "Show")))
                (ClassShape "Show" (list (TypeParameter "a")) (list "Out")))
        (expect (class-shape known (ClassGlobal (global lib "Store")))
                (ClassShape "Store" (list (RowParameter "e") (TypeParameter "s")) (list)))
        (let ((declared (Class (global main "Show")
                               (list (RowParameter "a"))
                               (list (Output (Label "Out" loc) (list)))
                               (list)
                               (list)
                               loc)))
          (expect (class-shape (Known main
                                      scanned
                                      (Declarations main
                                                    empty-table
                                                    (by-name empty-table "Show" declared)
                                                    empty-table)
                                      (list lib-offer))
                               (ClassGlobal (global main "Show")))
                  (ClassShape "Show" (list (RowParameter "a")) (list "Out")))))

      (define show-class
        (Class (global main "Show")
               (list (TypeParameter "a"))
               (list (Output (Label "Out" loc) (list)))
               (list (Method (global main "show")
                             (Scheme (list) (list) (list) (Var (Written "a")))
                             (list)
                             loc))
               (list)
               loc))

      (define io-read
        (Operation (global main "read")
                   #f
                   (list)
                   (Con (Global forms-library "I64" 0) (list))
                   (list)
                   (list)
                   loc))

      ;; A class of the library's own has no entity until its declaration
      ;; is reached; then it has, as an imported one has. An effect's
      ;; operations, and a data type, are known once reached.
      (define (test-reached)
        (expect (known-class known (global main "Show")) (None))
        (expect (known-class known (global lib "Store")) (Some store))
        (let ((reached (known-with-effect (known-with-class known show-class)
                                          (OfferedEffect (global main "io") (list io-read)))))
          (expect (known-class reached (global main "Show")) (Some show-class))
          (expect (effect-operations reached (global main "io")) (list io-read))
          (expect (::library (::declared reached)) main))
        (expect (known-data known (Global forms-library "I64" 0)) (None))
        (expect (map ::parameters (option-list (known-data known (global lib "Pair"))))
                (list (list "a" "b"))))

      (define (option-list option)
        (match option
          ((Some value) (list value))
          ((None) (list))))

      (define (data-of global cases)
        (Data global (list) cases (EnumData) #f #f (list) loc))

      (define (case-of global tag)
        (DataCase global tag (list) (list) loc))

      ;; A struct's constructor is its own Global; an enum's is a case's,
      ;; found among the library's types once reached; any other value,
      ;; and a library that offers nothing, has none.
      (define (test-constructors)
        (let* ((point (data-of (global main "Point") (list (case-of (global main "Point") 0))))
               (shape (data-of (global main "Shape")
                               (list (case-of (global main "Circle") 0)
                                     (case-of (global main "Square") 1))))
               (reached (known-with-data (known-with-data known point) shape)))
          (expect (constructor-case known (global main "Point")) (None))
          (expect (constructor-case reached (global main "Point"))
                  (Some (Pair point (case-of (global main "Point") 0))))
          (expect (constructor-case reached (global main "Square"))
                  (Some (Pair shape (case-of (global main "Square") 1))))
          (expect (constructor-case reached (global main "show")) (None))
          (expect (constructor-case reached (Global (list "prim") "once" 0)) (None))
          (expect
           (map ::name (map ::global (option-list (known-data reached (global main "Shape")))))
           (list "Shape"))))))
   (else)))
