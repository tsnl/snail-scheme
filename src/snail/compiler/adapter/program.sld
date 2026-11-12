;; The program the old checker is handed, made from every library the
;; integrator compiled, in its order, as the old expander makes it: its
;; `Program`, and, for each library that records a run of items, its key
;; and the files it links. Nothing here reads a file or performs the old
;; `compile` effect.
;;
;; Each library adds, in turn:
;;
;; - its entities to the tables, by their old names: each data type with
;;   its constructors and field functions, each class with its methods,
;;   each effect with its operations, each extern, primitive and linked
;;   file's handle, each definition with its signature's scheme and
;;   whether its value is a function, and each instance's implementations
;;   and effect's defaults, with their schemes, which no program names;
;; - its instances, each to its class's, in the order of its listing,
;;   which is the old order: a struct's field instances among them;
;; - the field class of each label it names;
;; - and its run of items, the order the old expander adds them, which is
;;   the order its tops are written: each definition, statement and
;;   exposure, and each instance's methods and effect's defaults at their
;;   declaration. A definition under instance scopes is scoped twice, as
;;   the old expander scopes it, a statement once. The statements of a
;;   program, whose key is `main`, are instead one body, `main:%body`, a
;;   function of no arguments, defined after every other item, and one
;;   statement calls it, as the old `with-one-body` gathers them; no
;;   library can be named `(main)`, since its import is refused where it
;;   is written. `program-body` is that gathering, which the
;;   comparison of expansions shares. The primitive library records no
;;   run, since the backend implements all it declares.
;;
;; Metadata is left empty: nothing past the old expander reads it.
(define-library (snail compiler adapter program)
  (export
   AdaptedProgram
   AdaptedLibrary
   adapted-program
   scoped
   program-body)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries)
   (only (snail compiler declare language)
         Expr
         Lambda
         ClosedLambda
         Seq
         WithInstances
         Signed
         Data
         Class
         Effect
         Default
         Operation
         InstanceMethod
         PrimitiveType
         PrimitiveScheme
         CallableOnce)
   (only (snail compiler names globals)
         Global
         FieldFunction
         Accessor
         ClassRef
         FieldClass
         same-global?)
   (only (snail compiler declare schemes) default-scheme)
   (only (snail compiler types type) Type Con)
   (only (snail compiler types builtins) i32-type)
   (only (snail compiler types scheme) Scheme)
   (snail compiler dispatch language)
   (only (snail compiler dispatch listing) Listed ListedInstance FieldInstance)
   (only (snail compiler bind placed) Placed)
   (only (snail compiler integrate compile) CompiledFile)
   (only (snail compiler adapter declaration)
         old-name
         old-value-name
         old-type
         old-scheme
         old-data
         old-class
         old-effect
         old-instance
         old-implementation-scheme
         declared-values)
   (snail compiler adapter expressions)
   (only (snail compiler adapter source) loc->old)
   (prefix (only (snail shell compiler core)
                 Type
                 TCon
                 TFun
                 TRigid
                 Constraint
                 Scheme
                 Expr
                 Var
                 App
                 Item
                 Define
                 Do
                 Expose
                 Value
                 Defined
                 Primitive
                 Foreign
                 Import
                 Program
                 empty-program
                 empty-row
                 mono-scheme
                 unchecked
                 callable-class
                 program-with-value
                 program-with-type
                 program-with-class
                 program-with-instance
                 program-with-effect
                 program-with-field-class
                 program-with-field-instance
                 program-with-library)
           old:)
   (prefix (only (snail shell compiler expand) LinkedFile) old:))
  (begin

    ;; ---- Programs ----

    ;; The old program, and each library that records a run of items, in
    ;; program order, by the old compiler's key, with the files the build
    ;; places beside the program for it.
    (struct AdaptedProgram
      ((program old:Program)
       (libraries (List AdaptedLibrary))))

    (struct AdaptedLibrary
      ((key String)
       (links (List old:LinkedFile))))

    ;; `files` are every library compiled, in the integrator's order.
    (: adapted-program (impl (Fn (List CompiledFile) -> AdaptedProgram)))
    (define (adapted-program files)
      (AdaptedProgram (::program (fold-left (lambda (joined file) (with-library files joined file))
                                            (Joined old:empty-program 0)
                                            files))
                      (map adapted-library (filter recorded? files))))

    ;; The program with the libraries added so far, and the first number
    ;; none of their locals has, which the next library's are numbered
    ;; from.
    (struct Joined
      ((program old:Program)
       (next I64)))

    (: adapted-library (impl (Fn CompiledFile -> AdaptedLibrary)))
    (define (adapted-library file)
      (AdaptedLibrary (library-key (::library file))
                      (map (lambda (placed) (old:LinkedFile (::digest placed) (::file placed)))
                           (::placed file))))

    ;; Whether the library records a run of items: all but the primitive
    ;; library, as the old expander decides by its name.
    (: recorded? (impl (Fn CompiledFile -> Bool)))
    (define (recorded? file)
      (not (same-library? (::library file) primitive-library)))

    ;; ---- Libraries ----

    ;; How far a library's walk is: the program with what the library has
    ;; added so far, the items of its run, newest first, as the old
    ;; program keeps them, and what converting its expressions hands on.
    (struct Adding
      ((program old:Program)
       (items (List old:Item))
       (converting Converting)))

    ;; What a library's walk reads: every library compiled, whose classes
    ;; an instance may implement, and whether the library's statements are
    ;; gathered, as those of a library whose key is `main` are.
    (struct Walk
      ((files (List CompiledFile))
       (gathering? Bool)))

    ;; One library's additions to the program: its tops in order, a
    ;; program's body, the instances of its listing, the field class of
    ;; each label it names, and then its run.
    (: with-library (impl (Fn (List CompiledFile) Joined CompiledFile -> Joined)))
    (define (with-library files joined file)
      (let* ((root (::dispatched file))
             (base (::next joined))
             (walk (Walk files (same-library? (::library file) program-library)))
             (walked (fold-left (lambda (adding top) (with-top walk (Nil) adding top))
                                (Adding (::program joined)
                                        (Nil)
                                        (Converting base (+ base (first-unused root)) (Nil)))
                                (root-tops root)))
             (done (with-body walk walked (root-tops root)))
             (listed (fold-left with-listed (::program done) (::listing file)))
             (labelled
              (fold-left (lambda (program label) (old:program-with-field-class program label))
                         listed
                         (::labels (::converting done)))))
        (Joined (if (recorded? file)
                    (old:program-with-library labelled
                                              (library-key (::library file))
                                              (::items done))
                    labelled)
                (::next (::converting done)))))

    (: root-tops (impl (Fn Dispatched -> (List Top))))
    (define (root-tops root)
      (match root
        ((Defined _ tops _ _) tops)
        ((Program tops _) tops)))

    (: first-unused (impl (Fn Dispatched -> I64)))
    (define (first-unused root)
      (match root
        ((Defined _ _ number _) number)
        ((Program _ number) number)))

    ;; ---- Additions ----

    (: with-values (impl (Fn Adding (List (Pair String old:Value)) -> Adding)))
    (define (with-values adding values)
      (Adding-program-set adding
                          (fold-left (lambda (program entry)
                                       (old:program-with-value program
                                                               (::first entry)
                                                               (::second entry)))
                                     (::program adding)
                                     values)))

    (: with-item (impl (Fn Adding old:Item -> Adding)))
    (define (with-item adding item)
      (Adding-items-set adding (Cons item (::items adding))))

    (: with-labels-of (impl (Fn Adding (List String) -> Adding)))
    (define (with-labels-of adding labels)
      (Adding-converting-set adding (with-labels (::converting adding) labels)))

    ;; `value`, a top-level value with `around` active, and the walk with
    ;; what converting it handed on.
    (: converted (impl (Fn Adding (List Global) Expr -> (Pair old:Expr Adding))))
    (define (converted adding around value)
      (match (top-level-expr (::converting adding) around value)
        ((Pair value state) (Pair value (Adding-converting-set adding state)))))

    ;; ---- Tops ----

    ;; One top, where the instance sets `around` are active: the sets of
    ;; the scopes around it, innermost first, and, for an instance of a
    ;; named set, that set before them.
    (: with-top (impl (Fn Walk (List Global) Adding Top -> Adding)))
    (define (with-top walk around adding top)
      (match top
        ((LinkImport global _ digest _ _)
         (with-values adding (list (Pair (old-name global) (link-import digest)))))
        ((Define global value signature _ _)
         (with-definition (with-values adding (declared-values top)) around global value signature))
        ((Statement expr) (if (::gathering? walk) adding (with-statement adding around expr)))
        ((Expose target symbol dynamic? loc)
         (with-item adding (old:Expose (old-value-name target) symbol dynamic? (loc->old loc))))
        ((TopData data)
         (with-values (Adding-program-set adding
                                          (old:program-with-type (::program adding)
                                                                 (old-data data)))
           (declared-values top)))
        ((Alias _ _ _ _) adding)
        ((TopClass class) (with-class adding class top))
        ((TopInstance instance) (with-instance walk around adding instance))
        ((InstanceSet global instances _)
         (fold-left
          (lambda (adding instance) (with-instance walk (Cons global around) adding instance))
          adding
          instances))
        ((InstanceScope sets tops _)
         (fold-left (lambda (adding top) (with-top walk (active-sets sets around) adding top))
                    adding
                    tops))
        ((Extern _ _ _ _ _ _) (with-values adding (declared-values top)))
        ((TopEffect effect) (with-effect around adding effect top))
        ((Primitive global type _)
         (with-values adding
           (list (Pair (old-name global) (old:Primitive (primitive-scheme type))))))))

    ;; A definition's value, scoped twice by the sets around it, as the
    ;; old expander's `define-top-level` scopes it.
    (: with-definition
       (impl (Fn Adding (List Global) Global Expr (Option Signed) -> Adding)))
    (define (with-definition adding around global value signature)
      (match (converted (with-labels-of adding (signed-labels signature))
                        (Nil)
                        (scoped around (scoped around value)))
        ((Pair value adding) (with-item adding (old:Define (old-name global) value)))))

    (: signed-labels (impl (Fn (Option Signed) -> (List String))))
    (define (signed-labels signature)
      (match signature
        ((Some signed) (requirement-labels (::requirements (::scheme signed))))
        ((None) (Nil))))

    ;; A library's statement, scoped once, where it is written. Its value
    ;; is no top-level value: a function there may capture.
    (: with-statement (impl (Fn Adding (List Global) Expr -> Adding)))
    (define (with-statement adding around expr)
      (match (old-expr (::converting adding) (Nil) (scoped around expr))
        ((Pair value state) (with-item (Adding-converting-set adding state) (old:Do value)))))

    (: with-class (impl (Fn Adding Class Top -> Adding)))
    (define (with-class adding class top)
      (with-values (with-labels-of (Adding-program-set adding
                                                       (old:program-with-class (::program adding)
                                                                               (old-class class)))
                                   (concatenate (map (lambda (method)
                                                       (requirement-labels
                                                        (::requirements (::scheme method))))
                                                     (::methods class))))
        (declared-values top)))

    ;; ---- Instances ----

    ;; Each of an instance's implementations, a definition at the
    ;; instance's place, which `around` is active in. The instance itself
    ;; is entered from the library's listing.
    (: with-instance (impl (Fn Walk (List Global) Adding Instance -> Adding)))
    (define (with-instance walk around adding instance)
      (fold-left (lambda (adding method) (with-method walk around instance adding method))
                 (with-labels-of adding
                                 (append (class-labels (::class instance))
                                         (requirement-labels (::requirements instance))))
                 (::methods instance)))

    (: class-labels (impl (Fn ClassRef -> (List String))))
    (define (class-labels class)
      (match class
        ((FieldClass label) (list label))
        (_ (Nil))))

    ;; An implementation is no value a program names: it has the
    ;; member's scheme at the instance's head, no signature, and is not
    ;; marked a function, though the old expander marks a dispatched
    ;; one, since the mark is read only of a value a program names.
    (: with-method (impl (Fn Walk (List Global) Instance Adding InstanceMethod -> Adding)))
    (define (with-method walk around instance adding method)
      (let ((name (old-name (::implementation method))))
        (match (converted adding around (::value method))
          ((Pair value adding)
           (with-item (with-values adding
                        (list (Pair name
                                    (old:Defined
                                     (Some (implementation-scheme walk instance method))
                                     (None)
                                     #f))))
                      (old:Define name value))))))

    ;; `declare` names, for each method of an instance, a member of its
    ;; class, and every class an instance names is declared by a library
    ;; compiled, so the member's scheme is found.
    (: implementation-scheme (impl (Fn Walk Instance InstanceMethod -> old:Scheme)))
    (define (implementation-scheme walk instance method)
      (match (old-implementation-scheme (::files walk) instance method)
        ((Some scheme) scheme)
        ((None) (panic "internal error: an instance implements no member of its class"))))

    ;; An instance of the library's listing, in its class's instances: an
    ;; instance with its set, or a struct's field instance, read by the
    ;; field's accessor, which the old program names `lib:::label@S`.
    (: with-listed (impl (Fn old:Program Listed -> old:Program)))
    (define (with-listed program listed)
      (match listed
        ((ListedInstance instance set)
         (old:program-with-instance program (old-instance instance set)))
        ((FieldInstance data field)
         (old:program-with-field-instance program
                                          (old-data data)
                                          (::label field)
                                          (old-type (::type field))
                                          (old-value-name
                                           (FieldFunction (::global data)
                                                          (::label field)
                                                          (Accessor)))))))

    ;; ---- Effects ----

    ;; An effect's defaults, each a definition at the effect's place, with
    ;; its operation's scheme but its own effect, and its entry as its
    ;; signature, as the old expander gives it.
    (: with-effect (impl (Fn (List Global) Adding Effect Top -> Adding)))
    (define (with-effect around adding effect top)
      (fold-left (lambda (adding default) (with-default around effect adding default))
                 (with-values (Adding-program-set adding
                                                  (old:program-with-effect (::program adding)
                                                                           (old-effect effect)))
                   (declared-values top))
                 (::defaults effect)))

    (: with-default (impl (Fn (List Global) Effect Adding Default -> Adding)))
    (define (with-default around effect adding default)
      (let ((name (old-name (::implementation default))))
        (match (converted adding around (::value default))
          ((Pair value adding)
           (with-item (with-values adding
                        (list (Pair name
                                    (old:Defined
                                     (Some (old-scheme
                                            (default-scheme
                                              (default-operation effect default))))
                                     (Some (loc->old (::loc default)))
                                     #f))))
                      (old:Define name value))))))

    ;; `declare` names, for each default, an operation of its effect.
    (: default-operation (impl (Fn Effect Default -> Operation)))
    (define (default-operation effect default)
      (match (find (lambda (operation) (same-global? (::global operation) (::operation default)))
                   (::operations effect))
        ((Some operation) operation)
        ((None) (panic "internal error: a default names no operation of its effect"))))

    ;; ---- Values made for the old program ----

    ;; A linked file's handle: the import from "snail.runtime.link" named
    ;; for the file's digest, a function of no arguments that answers the
    ;; file's handle, as the old expander binds it.
    (: link-import (impl (Fn String -> old:Value)))
    (define (link-import digest)
      (old:Foreign (old:Import "snail.runtime.link" digest)
                   (old:mono-scheme (old:TFun (Nil) (old-type i32-type) old:empty-row))))

    ;; A primitive's operational scheme; or `callable-once`, the signature
    ;; of `once`, which the old expander writes over a variable standing
    ;; for an arrow, `Signature`, which no Declared type writes.
    (: primitive-scheme (impl (Fn PrimitiveType -> old:Scheme)))
    (define (primitive-scheme type)
      (match type
        ((PrimitiveScheme scheme) (old-scheme scheme))
        ((CallableOnce)
         (let ((receiver (old:TRigid "F"))
               (signature (old:TRigid "Signature")))
           (old:Scheme (list "F" "Signature")
                       (list
                        (old:Constraint (old:callable-class "FnOnce") (list receiver signature)))
                       (Nil)
                       (old:TFun (list receiver)
                                 (old:TCon "FnOnce" (list signature))
                                 old:empty-row))))))

    ;; ---- A program's body ----

    ;; The statements of a library gathered, defined as `main:%body`, and
    ;; called by the one statement left, which is at the first statement.
    (: with-body (impl (Fn Walk Adding (List Top) -> Adding)))
    (define (with-body walk adding tops)
      (match (if (::gathering? walk) (program-body tops) (None))
        ((Some body)
         (match (converted adding (Nil) body)
           ((Pair value adding)
            (let ((loc (::loc value)))
              (with-item (with-item (with-values adding
                                      (list (Pair body-name (old:Defined (None) (None) #t))))
                                    (old:Define body-name value))
                         (old:Do (old:Expr (old:App (old:Expr (old:Var body-name (Nil) (Nil))
                                                              old:unchecked
                                                              loc)
                                                    (Nil))
                                           old:unchecked
                                           loc)))))))
        ((None) adding)))

    (: body-name String)
    (define body-name
      (string-append (library-key program-library) ":%body"))

    ;; A program's statements as the old `with-one-body` gathers them:
    ;; each scoped by the sets of the scopes around it, in the order
    ;; written, in sequence, the body of a function of no arguments at the
    ;; first; none when the program has none.
    (: program-body (impl (Fn (List Top) -> (Option Expr))))
    (define (program-body tops)
      (match (scoped-statements tops (Nil))
        ((Nil) (None))
        ((Cons first rest) (Some (Lambda (Nil) (sequenced first rest) (expression-loc first))))))

    (: scoped-statements (impl (Fn (List Top) (List Global) -> (List Expr))))
    (define (scoped-statements tops around)
      (concatenate (map (lambda (top)
                          (match top
                            ((Statement expr) (list (scoped around expr)))
                            ((InstanceScope sets inner _)
                             (scoped-statements inner (active-sets sets around)))
                            (_ (Nil))))
                        tops)))

    ;; Each sequence is at its first expression.
    (: sequenced (impl (Fn Expr (List Expr) -> Expr)))
    (define (sequenced first rest)
      (match rest
        ((Nil) first)
        ((Cons next more) (Seq first (sequenced next more) (expression-loc first)))))

    ;; A top-level value with the sets `sets` active, as the old
    ;; `scope-instance-value` scopes it: a function's body, at the body,
    ;; or else the value, at the value.
    (: scoped (impl (Fn (List Global) Expr -> Expr)))
    (define (scoped sets value)
      (if (null? sets)
          value
          (match value
            ((Lambda parameters body loc)
             (Lambda parameters (WithInstances sets body (expression-loc body)) loc))
            ((ClosedLambda parameters body loc)
             (ClosedLambda parameters (WithInstances sets body (expression-loc body)) loc))
            (_ (WithInstances sets value (expression-loc value))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-program)
    (import
     (snail core table)
     (only (snail compiler names globals) Local ClassGlobal)
     (only (snail compiler literals constant) Integer Boolean)
     (only (snail compiler expand offer) Offer TopScope)
     (only (snail compiler declare language)
           Literal
           LocalRef
           Path
           StructData
           DataCase
           DataField
           TypeParameter
           Method
           ClassMethod)
     (only (snail compiler types type) Callable Var Arrow Effects Written Dyn FnContract)
     (only (snail compiler declare offer) Declarations)
     (only (snail compiler dispatch listing) library-instances)
     (prefix (only (snail shell compiler read) Loc DInt DBool) old:)
     (prefix (only (snail shell compiler core)
                   Lit
                   Lambda
                   Seq
                   ScopedInstances
                   program-value
                   program-class
                   class-instances
                   program-items)
             old:)
     (snail stage0 testing))
    (begin
      (define (test-program)
        (test-library)
        (test-statements)
        (test-program-body)
        (test-numbers)
        (test-primitives))

      (define main (list "main"))
      (define shapes (list "sample" "shapes"))

      (define (loc line)
        (Loc "t.sld" line 1))

      (define (old-at line term)
        (old:Expr term old:unchecked (old:Loc "t.sld" line 1)))

      (define (global library name)
        (Global library name 0))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      (define (function parameters result)
        (Callable (Dyn) (FnContract) (Arrow parameters result (Effects (list) (None)))))

      (define (compiled library root)
        (CompiledFile "t.sld"
                      library
                      (list)
                      (Offer (list) (TopScope empty-table empty-table))
                      (list (Placed "ab12" "data/x.txt"))
                      root
                      (Declarations library empty-table empty-table empty-table)
                      (library-instances root)))

      ;; A struct with no mutable field, a class and an instance of it in
      ;; a scope, a definition in that scope, and a statement: the tables,
      ;; the instances by class with the struct's field instance, the
      ;; items in order, the definition scoped twice, the statement once.
      (define (test-library)
        (let* ((point (global shapes "Point"))
               (size (global shapes "size"))
               (sized (global shapes "Sized"))
               (set (global shapes "Metric"))
               (implementation (Global shapes "size" 7))
               (x (DataField "x" #f i64 (list) (loc 2)))
               (data (Data point (list) (list (DataCase point 0 (list x) (list) (loc 2)))
                           (StructData) #f #f (list) (loc 2)))
               (method
                (Method size (Scheme (list) (list) (list) (function (list (Var (Written "T"))) i64))
                        (list) (loc 3)))
               (class (Class sized (list (TypeParameter "T")) (list) (list method) (list) (loc 3)))
               (instance (Instance (Global shapes "Sized" 6)
                                   (ClassGlobal sized)
                                   (list)
                                   (list (Con point (list)))
                                   (list)
                                   (list)
                                   (list)
                                   (list (InstanceMethod (ClassMethod size)
                                                         implementation
                                                         (Path (list "x") (loc 4))
                                                         (loc 4)))
                                   (loc 4)))
               (root (Defined shapes
                       (list (TopData data)
                             (TopClass class)
                             (InstanceScope (list set)
                                            (list (TopInstance instance)
                                                  (Define (global shapes "one")
                                                    (Literal (Integer 1) (loc 5))
                                                    (None)
                                                    (list)
                                                    (loc 5)))
                                            (loc 4))
                             (Statement (Literal (Boolean #t) (loc 6))))
                       8
                       (loc 1)))
               (file (CompiledFile "t.sld"
                                   shapes
                                   (list)
                                   (Offer (list) (TopScope empty-table empty-table))
                                   (list (Placed "ab12" "data/x.txt"))
                                   root
                                   (Declarations shapes
                                                 empty-table
                                                 (table-set empty-table "Sized" (list class))
                                                 empty-table)
                                   (library-instances root)))
               (adapted (adapted-program (list file)))
               (program (::program adapted)))
          (expect (::libraries adapted)
                  (list (AdaptedLibrary "sample.shapes"
                                        (list (old:LinkedFile "ab12" "data/x.txt")))))
          (expect (map ::name (old:class-instances program "::x"))
                  (list "sample.shapes:::x@Point"))
          (expect (map ::name (old:class-instances program "sample.shapes:Sized"))
                  (list "sample.shapes:Sized%6"))
          (expect (::methods (old:program-class program "::x")) (list "::x"))
          (expect (old:program-value program "sample.shapes:size%7")
                  (Some (old:Defined (Some (old-scheme (Scheme (list)
                                                               (list)
                                                               (list)
                                                               (function (list (Con point (list)))
                                                                         i64))))
                                     (None)
                                     #f)))
          (expect (old:program-value program "sample.shapes:one")
                  (Some (old:Defined (None) (None) #f)))
          (expect (::libraries program) (list (Pair "sample.shapes" 3)))
          (expect (old:program-items program)
                  (list (old:Define "sample.shapes:size%7"
                                    (old-at 4 (old:Var "::x" (list) (list))))
                        (old:Define "sample.shapes:one"
                                    (old-at 5
                                            (old:ScopedInstances
                                             (list "sample.shapes:Metric")
                                             (old-at 5
                                                     (old:ScopedInstances
                                                      (list "sample.shapes:Metric")
                                                      (old-at 5 (old:Lit (old:DInt 1))))))))
                        (old:Do (old-at 6 (old:Lit (old:DBool #t))))))))

      ;; A program's statements are one body, after every other item,
      ;; each under the sets of the scopes around it; the one statement
      ;; left calls it.
      (define (test-statements)
        (let* ((set (global main "Loud"))
               (root (Program (list (Statement (Literal (Integer 1) (loc 2)))
                                    (InstanceScope (list set)
                                                   (list (Statement (Literal (Integer 2) (loc 4))))
                                                   (loc 3))
                                    (Define (global main "f")
                                      (Lambda (list (Local "x" 0))
                                              (LocalRef (Local "x" 0) (loc 5))
                                              (loc 5))
                                      (None)
                                      (list)
                                      (loc 5)))
                              1))
               (program (::program (adapted-program (list (compiled main root))))))
          (expect (old:program-value program "main:%body") (Some (old:Defined (None) (None) #t)))
          (expect (old:program-value program "main:f") (Some (old:Defined (None) (None) #t)))
          (expect (old:program-items program)
                  (list (old:Define "main:f"
                                    (old-at 5
                                            (old:Lambda (list "x.0")
                                                        (old-at 5 (old:Var "x.0" (list) (list)))
                                                        #f)))
                        (old:Define "main:%body"
                                    (old-at 2
                                            (old:Lambda
                                             (list)
                                             (old-at 2
                                                     (old:Seq (old-at 2 (old:Lit (old:DInt 1)))
                                                              (old-at 4
                                                                      (old:ScopedInstances
                                                                       (list "main:Loud")
                                                                       (old-at 4
                                                                               (old:Lit
                                                                                (old:DInt 2)))))))
                                             #f)))
                        (old:Do (old-at 2
                                        (old:App (old-at 2 (old:Var "main:%body" (list) (list)))
                                                 (list))))))))

      ;; A program's statements are gathered into one body; a library keeps
      ;; its statement where it is.
      (define (test-program-body)
        (let ((gathered (lambda (library root)
                          (old:program-items
                           (::program (adapted-program (list (compiled library root)))))))
              (statements (list (Statement (Literal (Integer 1) (loc 2))))))
          (expect (gathered main (Program statements 0))
                  (list (old:Define "main:%body"
                                    (old-at 2
                                            (old:Lambda (list)
                                                        (old-at 2 (old:Lit (old:DInt 1)))
                                                        #f)))
                        (old:Do (old-at 2
                                        (old:App (old-at 2 (old:Var "main:%body" (list) (list)))
                                                 (list))))))
          (expect (gathered shapes (Defined shapes statements 0 (loc 1)))
                  (list (old:Do (old-at 2 (old:Lit (old:DInt 1))))))))

      ;; Each library's locals are numbered after those of the libraries
      ;; before it, its paths' parameters among them: the first library
      ;; numbers 3 locals and makes a path, so the second's start at 4.
      (define (test-numbers)
        (let* ((x (Local "x" 0))
               (first (Defined shapes
                        (list (Define (global shapes "get")
                                (Path (list "a" "b") (loc 2))
                                (None)
                                (list)
                                (loc 2)))
                        3
                        (loc 1)))
               (second (Program (list (Define (global main "f")
                                        (Lambda (list x) (LocalRef x (loc 3)) (loc 3))
                                        (None)
                                        (list)
                                        (loc 3)))
                                1))
               (items (old:program-items
                       (::program (adapted-program (list (compiled shapes first)
                                                         (compiled main second)))))))
          (expect (map (lambda (item)
                         (match item
                           ((old:Define _ value)
                            (match (::term value)
                              ((old:Lambda parameters _ _) parameters)
                              (_ (list))))
                           (_ (list))))
                       items)
                  (list (list "path.3") (list "x.4")))))

      ;; The primitive library's values are `prim:`, and it records no run.
      (define (test-primitives)
        (let* ((library (list "snail" "core" "primitive"))
               (root (Defined library
                       (list (Primitive (Global (list "prim") "once" 0) (CallableOnce) (loc 2)))
                       0
                       (loc 1)))
               (adapted (adapted-program (list (compiled library root)))))
          (expect (::libraries adapted) (list))
          (expect (::libraries (::program adapted)) (list))
          (expect (map ::vars
                       (match (old:program-value (::program adapted) "prim:once")
                         ((Some (old:Primitive scheme)) (list scheme))
                         (_ (list))))
                  (list (list "F" "Signature")))))))
   (else)))
