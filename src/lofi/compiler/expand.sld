;; Located syntax to the core program. The expander is the only pass that knows
;; Lofi's binding forms. It loads libraries, resolves every identifier to a
;; binding, runs `syntax-rules` macros, records declared entities in the
;; program tables, and emits core expressions with unique names.
(define-library (lofi compiler expand)
  (export
   Context
   make-context
   Context-program
   expand-program)
  (import
   (lofi base)
   (lofi table)
   (lofi io)
   (lofi compiler read)
   (lofi compiler core))
  (begin

    ;; ---- Bindings and environments ----

    ;; What an identifier denotes. A struct's name is both a type and its
    ;; constructor. A macro remembers the scope it was defined in by number,
    ;; because the marks on the identifiers it introduces refer to it.
    (enum Binding
      (Local
       ((name String)))
      (Global
       ((name String)))
      (TypeName
       ((name String)
        (arity I64)
        (constructor (Option String))))
      (Alias
       ((name String)
        (params (List Syntax))
        (body Syntax)
        (env Env)
        (expanding (Ref Bool))))
      (TypeVar
       ((type Type)))
      (ClassName
       ((name String)))
      (EffectName
       ((name String)))
      (Core
       ((name String)))
      (Macro
       ((id String)
        (literals (List Syntax))
        (rules (List Syntax))
        (scope I64))))

    ;; Two bindings are the same when they denote the same entity, which
    ;; unique names identify.
    (: binding-identity (-> Binding String))
    (define (binding-identity binding)
      (match binding
        ((Local name) name)
        ((Global name) name)
        ((TypeName name _ _) name)
        ((Alias name _ _ _ _) name)
        ((TypeVar _) "%type-variable")
        ((ClassName name) name)
        ((EffectName name) name)
        ((Core name) (string-append "%core " name))
        ((Macro id _ _ _) id)))

    ;; An environment is a chain of local frames, each binding one
    ;; identifier, that ends in a top level: a table the scan fills before any
    ;; body is expanded, over the table of its imports. Frames never change; a
    ;; body that defines a name passes a longer chain to the forms after it.
    (enum Env
      (Frame
       ((key String)
        (binding Binding)
        (rest Env)))
      (Top
       ((table (Table Binding))
        (parent (Option Env)))))

    (: extend (-> Env Syntax Binding Env))
    (define (extend env ident binding)
      (Frame (ident-key ident) binding env))

    ;; A marked identifier is keyed by its mark, so the same name introduced by
    ;; two expansions binds two variables.
    (: ident-key (-> Syntax String))
    (define (ident-key ident)
      (match ident
        ((Ident _ (Some mark) _) (Mark-key mark))
        ((Ident name (None) _) name)
        (_ (panic "internal error: not an identifier"))))

    ;; An unbound marked identifier resolves as its original in the scope of
    ;; the macro that introduced it.
    (: resolve (-> Context Env Syntax (Option Binding) ! mut))
    (define (resolve cx env ident)
      (let ((key (ident-key ident)))
        (let lookup ((env env))
          (match env
            ((Frame other binding rest) (if (string=? other key) (Some binding) (lookup rest)))
            ((Top table parent)
             (match (table-ref table key)
               ((Some binding) (Some binding))
               ((None)
                (match parent
                  ((Some parent) (lookup parent))
                  ((None)
                   (match ident
                     ((Ident _ (Some mark) _) (resolve cx (scope-env cx (Mark-scope mark)) (Mark-original mark)))
                     (_ (None))))))))))))

    (: expect-ident (-> Syntax String Syntax))
    (define (expect-ident syntax what)
      (match syntax
        ((Ident _ _ _) syntax)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items of a form, or an error naming what was expected.
    (: form-items (-> Syntax String (List Syntax)))
    (define (form-items syntax what)
      (match syntax
        ((Form items _) items)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; The items after a form's head.
    (: form-tail (-> Syntax (List Syntax)))
    (define (form-tail syntax)
      (match syntax
        ((Form (Cons _ rest) _) rest)
        (_ (Nil))))

    (: head-binding (-> Context Env Syntax (Option Binding) ! mut))
    (define (head-binding cx env syntax)
      (match syntax
        ((Form (Cons head _) _)
         (match head
           ((Ident _ _ _) (resolve cx env head))
           (_ (None))))
        (_ (None))))

    (: core-form? (-> Context Env Syntax String Bool ! mut))
    (define (core-form? cx env syntax name)
      (match (head-binding cx env syntax)
        ((Some (Core keyword)) (string=? keyword name))
        (_ #f)))

    ;; ---- Expansion context ----

    ;; Shared by every library of one compilation. `prefix` names the library
    ;; being expanded, so its globals are `prefix:name`. `libraries` holds
    ;; each library's exports, or None while it loads. `scopes` numbers the
    ;; environments that marks refer to. `generate` runs a producer program
    ;; for `generate-library` and returns what it prints; the driver supplies
    ;; it, because running a program means compiling one.
    (struct Context
      ((program Program)
       (directories (List String))
       (libraries (Table (Option Exports)))
       (counter (Ref I64))
       (scopes (Table Env))
       (deriving (Ref (Option I64)))
       (generate (-> (List Syntax) String String ! mut fs))
       (prefix String)))

    (type Exports (List (Pair String Binding)))

    (: make-context (-> (List String) (-> (List Syntax) String String ! mut fs) Context ! mut))
    (define (make-context directories generate)
      (let ((cx (Context (make-program) directories (make-table) (ref 0) (make-table) (ref (None)) generate "")))
        (table-set! (Context-libraries cx) "lofi.core" (Some (core-library)))
        (table-set! (Context-libraries cx) "lofi.primitive" (Some (primitive-library cx)))
        cx))

    (: program (-> Context Program))
    (define (program cx)
      (Context-program cx))

    (: fresh (-> Context String String ! mut))
    (define (fresh cx base)
      (let ((count (+ (ref-get (Context-counter cx)) 1)))
        (ref-set! (Context-counter cx) count)
        (string-append base "." (i64->string count))))

    (: global-name (-> Context String String))
    (define (global-name cx key)
      (string-append (Context-prefix cx) ":" key))

    (: register-scope! (-> Context Env I64 ! mut))
    (define (register-scope! cx env)
      (let ((number (table-count (Context-scopes cx))))
        (table-set! (Context-scopes cx) (i64->string number) env)
        number))

    (: scope-env (-> Context I64 Env ! mut))
    (define (scope-env cx number)
      (match (table-ref (Context-scopes cx) (i64->string number))
        ((Some env) env)
        ((None) (panic "internal error: unknown scope"))))

    ;; ---- Builtin libraries ----

    (: core-keywords (List String))
    (define core-keywords
      (list "define" "lambda" "if" "begin" "let" "define-syntax" "syntax-rules" "quote" ":" "struct" "enum" "type"
            "typeclass" "instance" "match" "ann" "extern" "effect" "handle" "expose" "case-id" "type-convert"))

    (: core-library (-> Exports))
    (define (core-library)
      (append (map (lambda (name) (Pair name (Core name))) core-keywords)
              (append (map (lambda (entry) (Pair (Pair-first entry) (TypeName (Pair-first entry) (Pair-second entry) (None))))
                           builtin-types)
                      (list (Pair "mut" (EffectName "mut"))))))

    (: primitive-library (-> Context Exports ! mut))
    (define (primitive-library cx)
      (map (lambda (entry)
             (let ((name (string-append "prim:" (Pair-first entry))))
               (add-value! (program cx) name (Primitive (Pair-second entry)))
               (Pair (Pair-first entry) (Global name))))
           (primitives)))

    ;; ---- Libraries ----

    ;; `(lofi base)` is the list ("lofi" "base"); its globals are prefixed
    ;; `lofi.base` and its source is `lofi/base.sld` in a search directory.
    (: library-name (-> Syntax (List String)))
    (define (library-name syntax)
      (map (lambda (part)
             (match part
               ((Ident name _ _) name)
               ((Atom (DInt number) _) (i64->string number))
               (_ (compile-error (syntax-loc part) "expected a library name part"))))
           (form-items syntax "a library name")))

    (: check-library-name (-> Syntax (List String) Loc Unit))
    (define (check-library-name declared name loc)
      (unless (string=? (string-join (library-name declared) ".") (string-join name "."))
        (compile-error loc "library name does not match its path")))

    ;; Loads each library once. A library that is still loading when it is
    ;; requested again is part of an import cycle.
    (: load-library (-> Context (List String) Loc Exports ! mut fs))
    (define (load-library cx name loc)
      (let ((key (string-join name ".")))
        (match (table-ref (Context-libraries cx) key)
          ((Some (Some exports)) exports)
          ((Some (None)) (compile-error loc (string-append "library import cycle through " key)))
          ((None)
           (table-set! (Context-libraries cx) key (None))
           (let ((exports (read-library cx name loc)))
             (table-set! (Context-libraries cx) key (Some exports))
             exports)))))

    (: read-library (-> Context (List String) Loc Exports ! mut fs))
    (define (read-library cx name loc)
      (let ((relative (string-append (string-join name "/") ".sld")))
        (match (find file-exists? (map (lambda (directory) (string-append directory "/" relative)) (Context-directories cx)))
          ((Some path) (library-from-forms cx name (read-text (read-file path) path) path))
          ((None) (compile-error loc (string-append "library not found: (" (string-join name " ") ")"))))))

    ;; A library file holds one `define-library`, or one `generate-library`
    ;; whose program prints the library's source text.
    (: library-from-forms (-> Context (List String) (List Syntax) String Exports ! mut fs))
    (define (library-from-forms cx name forms path)
      (match forms
        ((Cons (Form (Cons (Ident "define-library" _ _) (Cons declared declarations)) loc) (Nil))
         (check-library-name declared name loc)
         (expand-library cx name declarations))
        ((Cons (Form (Cons (Ident "generate-library" _ _)
                           (Cons declared (Cons (Form (Cons (Ident "import" _ _) imports) _) (Cons expression (Nil)))))
                     loc)
               (Nil))
         (check-library-name declared name loc)
         (let ((generated (string-append path "#generated")))
           (library-from-forms cx name (read-text ((Context-generate cx) (producer imports expression loc) generated) generated)
                               generated)))
        (_ (compile-error (Loc path 1 1) "expected exactly one define-library or generate-library form"))))

    ;; The producer imports what the recipe imports and prints its expression.
    (: producer (-> (List Syntax) Syntax Loc (List Syntax)))
    (define (producer imports expression loc)
      (let ((write-string (Ident "write-string" (None) loc)))
        (list (Form (Cons (Ident "import" (None) loc)
                          (append imports
                                  (list (Form (list (Ident "only" (None) loc)
                                                    (Form (list (Ident "lofi" (None) loc) (Ident "io" (None) loc)) loc)
                                                    write-string)
                                              loc))))
                    loc)
              (Form (list write-string expression) loc))))

    (: expand-library (-> Context (List String) (List Syntax) Exports ! mut fs))
    (define (expand-library cx name declarations)
      (let* ((sections (concatenate (map library-sections declarations)))
             (cx (Context-prefix-set cx (string-join name ".")))
             (env (import-env cx (section-items sections "import"))))
        (expand-top-level cx env (section-items sections "begin"))
        (map (lambda (spec) (export-entry cx env spec)) (section-items sections "export"))))

    ;; Each declaration is a section of imports, exports or definitions, or a
    ;; `cond-expand` choosing more declarations.
    (: library-sections (-> Syntax (List (Pair String (List Syntax)))))
    (define (library-sections declaration)
      (match declaration
        ((Form (Cons (Ident "cond-expand" _ _) clauses) _) (cond-expand-sections clauses))
        ((Form (Cons (Ident kind _ _) items) loc)
         (if (member? kind (list "import" "export" "begin"))
             (list (Pair kind items))
             (compile-error loc "expected import, export, begin or cond-expand")))
        (_ (compile-error (syntax-loc declaration) "expected import, export, begin or cond-expand"))))

    ;; The declarations of the first clause whose requirement holds. Lofi's
    ;; only feature is `lofi`.
    (: cond-expand-sections (-> (List Syntax) (List (Pair String (List Syntax)))))
    (define (cond-expand-sections clauses)
      (match clauses
        ((Nil) (Nil))
        ((Cons (Form (Cons requirement declarations) _) rest)
         (if (feature? requirement)
             (concatenate (map library-sections declarations))
             (cond-expand-sections rest)))
        ((Cons clause _) (compile-error (syntax-loc clause) "expected (requirement declaration ...)"))))

    (: feature? (-> Syntax Bool))
    (define (feature? requirement)
      (match requirement
        ((Ident name _ _) (or (string=? name "lofi") (string=? name "else")))
        ((Form (Cons (Ident "and" _ _) items) _) (every? feature? items))
        ((Form (Cons (Ident "or" _ _) items) _) (any? feature? items))
        ((Form (Cons (Ident "not" _ _) (Cons item (Nil))) _) (not (feature? item)))
        (_ #f)))

    (: section-items (-> (List (Pair String (List Syntax))) String (List Syntax)))
    (define (section-items sections kind)
      (concatenate (map Pair-second (filter (lambda (section) (string=? (Pair-first section) kind)) sections))))

    ;; A program is a sequence of imports followed by a body.
    (: expand-program (-> Context String Program ! mut fs))
    (define (expand-program cx path)
      (let loop ((forms (read-text (read-file path) path)) (specs (Nil)))
        (match forms
          ((Cons (Form (Cons (Ident "import" _ _) more) _) rest) (loop rest (append specs more)))
          (_ (let* ((cx (Context-prefix-set cx "main")) (env (import-env cx specs)))
               (expand-top-level cx env forms)
               (program cx))))))

    ;; ---- Imports and exports ----

    (: import-env (-> Context (List Syntax) Env ! mut fs))
    (define (import-env cx specs)
      (let ((imports (make-table)))
        (for-each (lambda (spec)
                    (for-each (lambda (entry) (import-binding! imports entry (syntax-loc spec))) (import-set cx spec)))
                  specs)
        (Top (make-table) (Some (Top imports (None))))))

    (: import-binding! (-> (Table Binding) (Pair String Binding) Loc Unit ! mut))
    (define (import-binding! imports entry loc)
      (match (table-ref imports (Pair-first entry))
        ((Some existing)
         (unless (string=? (binding-identity existing) (binding-identity (Pair-second entry)))
           (compile-error loc (string-append "conflicting imports of " (Pair-first entry)))))
        ((None) (table-set! imports (Pair-first entry) (Pair-second entry)))))

    ;; The (name . binding) entries an import set provides.
    (: import-set (-> Context Syntax Exports ! mut fs))
    (define (import-set cx spec)
      (match spec
        ((Form (Cons (Ident "only" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (filter (lambda (entry) (member? (Pair-first entry) names)) (checked-import-set cx inner idents))))
        ((Form (Cons (Ident "except" _ _) (Cons inner idents)) _)
         (let ((names (ident-names idents)))
           (filter (lambda (entry) (not (member? (Pair-first entry) names))) (checked-import-set cx inner idents))))
        ((Form (Cons (Ident "prefix" _ _) (Cons inner (Cons (Ident prefix _ _) (Nil)))) _)
         (map (lambda (entry) (Pair (string-append prefix (Pair-first entry)) (Pair-second entry))) (import-set cx inner)))
        ((Form (Cons (Ident "rename" _ _) (Cons inner pairs)) _)
         (let ((renames (map rename-pair pairs)))
           (map (lambda (entry)
                  (match (assoc-ref renames (Pair-first entry))
                    ((Some renamed) (Pair renamed (Pair-second entry)))
                    ((None) entry)))
                (checked-import-set cx inner (map (lambda (pair) (match pair ((Form (Cons from _) _) from) (_ pair))) pairs)))))
        (_ (load-library cx (library-name spec) (syntax-loc spec)))))

    (: checked-import-set (-> Context Syntax (List Syntax) Exports ! mut fs))
    (define (checked-import-set cx spec idents)
      (let ((entries (import-set cx spec)))
        (for-each (lambda (ident)
                    (match (assoc-ref entries (Ident-name ident))
                      ((Some _) (unit))
                      ((None) (compile-error (syntax-loc ident)
                                             (string-append "import names an identifier the library does not export: "
                                                            (Ident-name ident))))))
                  idents)
        entries))

    (: ident-names (-> (List Syntax) (List String)))
    (define (ident-names idents)
      (map (lambda (ident) (Ident-name (expect-ident ident "an identifier"))) idents))

    (: rename-pair (-> Syntax (Pair String String)))
    (define (rename-pair syntax)
      (match syntax
        ((Form (Cons (Ident from _ _) (Cons (Ident to _ _) (Nil))) _) (Pair from to))
        (_ (compile-error (syntax-loc syntax) "expected (name new-name)"))))

    (: export-entry (-> Context Env Syntax (Pair String Binding) ! mut))
    (define (export-entry cx env spec)
      (match spec
        ((Ident name _ _) (Pair name (defined-binding cx env spec "exported name is not defined")))
        ((Form (Cons (Ident "rename" _ _) (Cons inner (Cons (Ident outer _ _) (Nil)))) _)
         (Pair outer (defined-binding cx env inner "exported name is not defined")))
        (_ (compile-error (syntax-loc spec) "expected an export specification"))))

    ;; The binding of an identifier that must be bound.
    (: defined-binding (-> Context Env Syntax String Binding ! mut))
    (define (defined-binding cx env ident message)
      (match (resolve cx env (expect-ident ident "an identifier"))
        ((Some binding) binding)
        ((None) (compile-error (syntax-loc ident) (string-append message ": " (Ident-name ident))))))

    ;; The unique name of a top-level definition the scan bound.
    (: global-binding (-> Context Env Syntax String ! mut))
    (define (global-binding cx env ident)
      (match (defined-binding cx env ident "undefined name")
        ((Global name) name)
        (_ (compile-error (syntax-loc ident) (string-append "not a top-level definition: " (Ident-name ident))))))

    ;; ---- Top-level bodies ----

    ;; Pass 1 discovers every top-level name, so definitions may refer to later
    ;; ones. Pass 2 resolves declarations and signatures, returning one thunk
    ;; per definition or expression; running the thunks in order expands them.
    (struct Pending
      ((keyword String)
       (form Syntax)
       (env Env)))

    (: declaration-keywords (List String))
    (define declaration-keywords
      (list ":" "struct" "enum" "type" "typeclass" "instance" "extern" "effect" "expose"))

    (: expand-top-level (-> Context Env (List Syntax) Unit ! mut fs))
    (define (expand-top-level cx env forms)
      (let* ((pending (concatenate (map (lambda (form) (scan-top-level cx env form)) forms)))
             (signatures (make-table))
             (definitions (concatenate (map (lambda (entry) (declare! cx signatures entry)) pending))))
        (for-each (lambda (expand!) (expand!)) definitions)))

    (: scan-top-level (-> Context Env Syntax (List Pending) ! mut fs))
    (define (scan-top-level cx env form)
      (let ((form (expand-head cx env form)))
        (match (head-binding cx env form)
          ((Some (Core "begin")) (concatenate (map (lambda (item) (scan-top-level cx env item)) (form-tail form))))
          ((Some (Core "define-syntax")) (define-top-macro! cx env form) (Nil))
          ((Some (Core "define"))
           (let ((ident (definition-name form)))
             (bind-top! env ident (Global (unique-name cx ident)))
             (list (Pending "define" form env))))
          ((Some (Core keyword))
           (if (member? keyword declaration-keywords)
               (begin (scan-declaration cx env keyword form)
                      (Cons (Pending keyword form env)
                            (if (or (string=? keyword "struct") (string=? keyword "enum"))
                                (concatenate (map (lambda (instance) (scan-top-level cx env instance))
                                                  (derived-instances cx form (string=? keyword "enum"))))
                                (Nil))))
               (list (Pending "expression" form env))))
          (_ (list (Pending "expression" form env))))))

    (: bind-top! (-> Env Syntax Binding Unit ! mut))
    (define (bind-top! env ident binding)
      (match env
        ((Top table _)
         (when (table-contains? table (ident-key ident))
           (compile-error (syntax-loc ident) (string-append "duplicate top-level definition " (Ident-name ident))))
         (table-set! table (ident-key ident) binding))
        (_ (panic "internal error: not a top level"))))

    (: definition-name (-> Syntax Syntax))
    (define (definition-name form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons name _) _) _)) _) (expect-ident name "a definition name"))
        ((Form (Cons _ (Cons name (Cons _ (Nil)))) _) (expect-ident name "a definition name"))
        (_ (compile-error (syntax-loc form) "expected (define name value) or (define (name parameter ...) body ...)"))))

    (: declare! (-> Context (Table Scheme) Pending (List (-> Unit ! mut)) ! mut fs))
    (define (declare! cx signatures pending)
      (let ((form (Pending-form pending)) (env (Pending-env pending)))
        (case (Pending-keyword pending)
          ((":") (declare-signature! cx signatures env form) (Nil))
          (("struct") (declare-data! cx env form #f) (Nil))
          (("enum") (declare-data! cx env form #t) (Nil))
          (("typeclass") (declare-class! cx env form) (Nil))
          (("instance") (declare-instance! cx env form))
          (("extern") (declare-extern! cx env form) (Nil))
          (("effect") (declare-effect! cx env form) (Nil))
          (("define") (list (lambda () (define-top-level! cx signatures env form))))
          (("expose") (list (lambda () (add-item! (program cx) (expose-item cx env form)))))
          (("expression") (list (lambda () (add-item! (program cx) (Do (expand-expr cx env form))))))
          (else (Nil)))))

    ;; `(expose name "symbol")` exports a top-level function to the host.
    (: expose-item (-> Context Env Syntax Item ! mut))
    (define (expose-item cx env form)
      (match form
        ((Form (Cons _ (Cons name (Cons (Atom (DString symbol) _) (Nil)))) loc)
         (match (resolve cx env (expect-ident name "a function name"))
           ((Some (Global global)) (Expose global symbol loc))
           (_ (compile-error (syntax-loc name) (string-append "only a top-level function can be exposed: " (Ident-name name))))))
        (_ (compile-error (syntax-loc form) "expected (expose name \"symbol\")"))))

    (: define-top-level! (-> Context (Table Scheme) Env Syntax Unit ! mut))
    (define (define-top-level! cx signatures env form)
      (let ((name (global-binding cx env (definition-name form))))
        (add-value! (program cx) name (Defined (table-ref signatures name)))
        (add-item! (program cx) (Define name (definition-value cx env form)))))

    (: definition-value (-> Context Env Syntax Expr ! mut))
    (define (definition-value cx env form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons _ params) _) body)) loc) (expand-lambda cx env params body loc))
        ((Form (Cons _ (Cons _ (Cons value (Nil)))) _) (expand-expr cx env value))
        (_ (compile-error (syntax-loc form) "expected a definition"))))

    ;; ---- Declarations ----

    ;; Pass 1 binds the names a declaration introduces; pass 2 resolves types.
    (: scan-declaration (-> Context Env String Syntax Unit ! mut))
    (define (scan-declaration cx env keyword form)
      (match (form-tail form)
        ((Cons head rest)
         (case keyword
           (("struct") (scan-struct! cx env head form))
           (("enum") (scan-enum! cx env head form))
           (("type") (scan-alias! cx env head rest form))
           (("typeclass") (scan-class! cx env head rest))
           (("extern") (bind-member! cx env head))
           (("effect") (scan-effect! cx env head rest form))
           (else (unit))))
        (_ (compile-error (syntax-loc form) "expected a declaration"))))

    ;; A declared name is global in the library that declares it.
    (: unique-name (-> Context Syntax String))
    (define (unique-name cx ident)
      (global-name cx (ident-key ident)))

    ;; A struct's name is both its type and its constructor.
    (: scan-struct! (-> Context Env Syntax Syntax Unit ! mut))
    (define (scan-struct! cx env head form)
      (let ((name (declared-name head)))
        (bind-top! env name (TypeName (unique-name cx name) (length (declared-params head)) (Some (unique-name cx name))))
        (bind-fields! cx env name (struct-fields form) #t)))

    (: scan-enum! (-> Context Env Syntax Syntax Unit ! mut))
    (define (scan-enum! cx env head form)
      (let ((name (declared-name head)))
        (bind-top! env name (TypeName (unique-name cx name) (length (declared-params head)) (None)))
        (for-each (lambda (case) (scan-case! cx env case)) (enum-cases form))))

    (: scan-alias! (-> Context Env Syntax (List Syntax) Syntax Unit ! mut))
    (define (scan-alias! cx env head rest form)
      (let ((name (declared-name head)))
        (match rest
          ((Cons body (Nil)) (bind-top! env name (Alias (unique-name cx name) (declared-params head) body env (ref #f))))
          (_ (compile-error (syntax-loc form) "expected (type Name type)")))))

    (: scan-class! (-> Context Env Syntax (List Syntax) Unit ! mut))
    (define (scan-class! cx env head signatures)
      (let ((name (declared-name head)))
        (bind-top! env name (ClassName (unique-name cx name)))
        (for-each (lambda (signature)
                    (match signature
                      ((Form (Cons _ (Cons method _)) _) (bind-member! cx env method))
                      (_ (compile-error (syntax-loc signature) "expected (: method type)"))))
                  signatures)))

    (: scan-effect! (-> Context Env Syntax (List Syntax) Syntax Unit ! mut))
    (define (scan-effect! cx env head rest form)
      (let ((name (expect-ident head "an effect name")))
        (bind-top! env name (EffectName (unique-name cx name)))
        (match rest
          ((Cons operations _)
           (for-each (lambda (operation)
                       (match operation
                         ((Form (Cons operation-name _) _) (bind-member! cx env operation-name))
                         (_ (compile-error (syntax-loc operation) "expected (operation type)"))))
                     (form-items operations "a list of operations")))
          (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))")))))

    (: bind-member! (-> Context Env Syntax Unit ! mut))
    (define (bind-member! cx env ident)
      (let ((ident (expect-ident ident "a name")))
        (bind-top! env ident (Global (unique-name cx ident)))))

    (: scan-case! (-> Context Env Syntax Unit ! mut))
    (define (scan-case! cx env case)
      (match (form-items case "an enum case")
        ((Cons name fields)
         (bind-member! cx env name)
         (bind-fields! cx env name (match fields ((Cons fields _) (form-items fields "a field list")) ((Nil) (Nil))) #f))
        ((Nil) (compile-error (syntax-loc case) "expected an enum case"))))

    ;; Accessors are `Name-field`; structs also get replacements `Name-field-set`.
    (: bind-fields! (-> Context Env Syntax (List Syntax) Bool Unit ! mut))
    (define (bind-fields! cx env name fields setters?)
      (for-each (lambda (field)
                  (match (form-items field "a field")
                    ((Cons field-name _)
                     (bind-member! cx env (field-ident name field-name ""))
                     (when setters? (bind-member! cx env (field-ident name field-name "-set"))))
                    ((Nil) (compile-error (syntax-loc field) "expected (field type)"))))
                fields))

    ;; A field identifier shares the mark of its type's name, so a struct a
    ;; macro introduces has accessors only that expansion sees.
    (: field-ident (-> Syntax Syntax String Syntax))
    (define (field-ident name field suffix)
      (let ((text (string-append "-" (Ident-name (expect-ident field "a field name")) suffix)))
        (Ident (string-append (Ident-name name) text)
               (match (Ident-mark name)
                 ((Some mark) (Some (Mark (string-append (Mark-key mark) text) (Mark-original mark) (Mark-scope mark))))
                 ((None) (None)))
               (syntax-loc field))))

    (: declared-name (-> Syntax Syntax))
    (define (declared-name head)
      (match head
        ((Form (Cons name _) _) (expect-ident name "a type name"))
        (_ (expect-ident head "a type name"))))

    (: declared-params (-> Syntax (List Syntax)))
    (define (declared-params head)
      (match head
        ((Form (Cons _ params) _) (map (lambda (param) (expect-ident param "a type parameter")) params))
        (_ (Nil))))

    ;; A struct or enum may end with `(deriving Class ...)`.
    (: deriving-clause? (-> Syntax Bool))
    (define (deriving-clause? syntax)
      (match syntax
        ((Form (Cons (Ident "deriving" _ _) _) _) #t)
        (_ #f)))

    ;; The declaration's items after its head, without deriving clauses.
    (: declaration-body (-> Syntax (List Syntax)))
    (define (declaration-body form)
      (match (form-tail form)
        ((Cons _ rest) (filter (lambda (item) (not (deriving-clause? item))) rest))
        ((Nil) (Nil))))

    (: declaration-head (-> Syntax Syntax))
    (define (declaration-head form)
      (match (form-tail form)
        ((Cons head _) head)
        ((Nil) (compile-error (syntax-loc form) "expected a declared name"))))

    (: struct-fields (-> Syntax (List Syntax)))
    (define (struct-fields form)
      (match (declaration-body form)
        ((Nil) (Nil))
        ((Cons fields (Nil)) (form-items fields "a field list"))
        (_ (compile-error (syntax-loc form) "expected (struct Name ((field type) ...))"))))

    (: enum-cases (-> Syntax (List Syntax)))
    (define (enum-cases form)
      (declaration-body form))

    (: derived-classes (-> Syntax (List Syntax)))
    (define (derived-classes form)
      (concatenate (map form-tail (filter deriving-clause? (form-tail form)))))

    ;; A type parameter scope binds each parameter to a rigid variable.
    (: type-scope (-> Env (List Syntax) Env))
    (define (type-scope env params)
      (fold-left (lambda (scope param) (extend scope param (TypeVar (TRigid (Ident-name param))))) env params))

    ;; A case is its name followed by an optional field list; a struct is one
    ;; case named after the struct.
    (: declare-data! (-> Context Env Syntax Bool Unit ! mut))
    (define (declare-data! cx env form enum?)
      (let* ((head (declaration-head form)) (params (declared-params head))
             (id (match (resolve cx env (declared-name head)) ((Some (TypeName id _ _)) id) (_ (panic "internal error: type"))))
             (scope (type-scope env params))
             (cases (if enum?
                        (map (lambda (case) (form-items case "an enum case")) (enum-cases form))
                        (list (Cons (declared-name head) (declaration-body form)))))
             (data (DataType id (map Ident-name params) (map-indexed (lambda (tag case) (resolve-case cx scope case id tag)) cases)
                             enum?)))
        (add-type! (program cx) data)
        (for-each (lambda (case) (declare-case-values! cx data case (not enum?))) (DataType-cases data))))

    (: resolve-case (-> Context Env (List Syntax) String I64 Case ! mut))
    (define (resolve-case cx scope case type tag)
      (match case
        ((Cons name fields)
         (Case (constructor-name cx scope name) type tag
               (map (lambda (field) (resolve-field cx scope field))
                    (match fields ((Cons fields _) (form-items fields "a field list")) ((Nil) (Nil))))))
        ((Nil) (panic "internal error: empty case"))))

    (: resolve-field (-> Context Env Syntax Field ! mut))
    (define (resolve-field cx scope field)
      (match field
        ((Form (Cons name (Cons type (Nil))) _) (Field (Ident-name (expect-ident name "a field name")) (resolve-type cx scope type)))
        (_ (compile-error (syntax-loc field) "expected (field type)"))))

    (: constructor-name (-> Context Env Syntax String ! mut))
    (define (constructor-name cx env ident)
      (match (resolve cx env ident)
        ((Some (Global name)) name)
        ((Some (TypeName _ _ (Some constructor))) constructor)
        (_ (compile-error (syntax-loc ident) (string-append "not a constructor: " (Ident-name ident))))))

    (: declare-case-values! (-> Context DataType Case Bool Unit ! mut))
    (define (declare-case-values! cx data case setters?)
      (let* ((params (DataType-params data)) (self (TCon (DataType-name data) (map TRigid params)))
             (name (Case-name case)))
        (add-value! (program cx) name (Constructor case (Scheme params (Nil) (TFun (map Field-type (Case-fields case)) self empty-row))))
        (for-each (lambda (indexed)
                    (let* ((index (Pair-first indexed)) (field (Pair-second indexed)) (type (Field-type field))
                           (accessor (string-append name "-" (Field-name field))))
                      (add-value! (program cx) accessor (Accessor case index (Scheme params (Nil) (TFun (list self) type empty-row))))
                      (when setters?
                        (add-value! (program cx) (string-append accessor "-set")
                                    (Replacer case index (Scheme params (Nil) (TFun (list self type) self empty-row)))))))
                  (zip (iota (length (Case-fields case))) (Case-fields case)))))

    ;; `(: name type)` records a scheme for the following definition.
    (: declare-signature! (-> Context (Table Scheme) Env Syntax Unit ! mut))
    (define (declare-signature! cx signatures env form)
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (match (resolve cx env (expect-ident name "a name"))
           ((Some (Global global)) (table-set! signatures global (resolve-scheme cx env type)))
           (_ (compile-error (syntax-loc name) (string-append "signature names an undefined top-level definition: "
                                                              (Ident-name name))))))
        (_ (compile-error (syntax-loc form) "expected (: name type)"))))

    (: declare-class! (-> Context Env Syntax Unit ! mut))
    (define (declare-class! cx env form)
      (let* ((head (declaration-head form)) (params (declared-params head))
             (id (match (resolve cx env (declared-name head)) ((Some (ClassName id)) id) (_ (panic "internal error: class"))))
             (scope (type-scope env params))
             (self (Constraint id (map (lambda (param) (TRigid (Ident-name param))) params))))
        (add-class! (program cx)
                    (Class id (map Ident-name params)
                           (map (lambda (signature) (declare-method! cx env scope id params self signature))
                                (match (form-tail form) ((Cons _ signatures) signatures) ((Nil) (Nil))))))))

    (: declare-method! (-> Context Env Env String (List Syntax) Constraint Syntax String ! mut))
    (define (declare-method! cx env scope class params self signature)
      (match signature
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (let ((own (resolve-scheme cx scope type)) (global (global-binding cx env name)))
           (add-value! (program cx) global
                       (Method class (Scheme (append (map Ident-name params) (Scheme-vars own)) (Cons self (Scheme-constraints own))
                                             (Scheme-type own))))
           global))
        (_ (compile-error (syntax-loc signature) "expected (: method type)"))))

    ;; Returns one thunk per method, which expands its definition.
    (: declare-instance! (-> Context Env Syntax (List (-> Unit ! mut)) ! mut))
    (define (declare-instance! cx env form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons class-ident type-args) _) body)) loc)
         (let* ((class (match (resolve cx env class-ident)
                         ((Some (ClassName id)) (program-class (program cx) id))
                         (_ (compile-error (syntax-loc class-ident) "instance of something that is not a typeclass"))))
                (parts (split-requires body)) (instance (declared-instance cx env class type-args (Pair-first parts) loc))
                (methods (map (lambda (definition) (instance-method cx env class instance definition)) (Pair-second parts))))
           (check-instance-methods class methods loc)
           (check-overlap (program cx) instance loc)
           (add-instance! (program cx)
                          (Instance-methods-set instance
                                                (map (lambda (method) (Pair (MethodDefinition-method method) (MethodDefinition-global method)))
                                                     methods)))
           (map MethodDefinition-expand methods)))
        (_ (compile-error (syntax-loc form) "expected (instance (Class type ...) definition ...)"))))

    ;; Unbound identifiers in an instance head are its type variables.
    (: declared-instance (-> Context Env Class (List Syntax) (List Syntax) Loc Instance ! mut))
    (define (declared-instance cx env class type-args requires loc)
      (let* ((vars (delete-duplicates string=? (concatenate (map (lambda (type) (free-type-names cx env type)) type-args))))
             (scope (type-scope env (map (lambda (name) (Ident name (None) loc)) vars))))
        (Instance (fresh-global cx (short-name (Class-name class))) (Class-name class) vars
                  (map (lambda (type) (resolve-type cx scope type)) type-args)
                  (map (lambda (c) (resolve-constraint cx scope c)) requires) (Nil))))

    (: fresh-global (-> Context String String ! mut))
    (define (fresh-global cx base)
      (global-name cx (fresh cx base)))

    ;; A body may start with `(requires (Class type ...) ...)`.
    (: split-requires (-> (List Syntax) (Pair (List Syntax) (List Syntax))))
    (define (split-requires items)
      (match items
        ((Cons (Form (Cons (Ident "requires" _ _) constraints) _) rest) (Pair constraints rest))
        (_ (Pair (Nil) items))))

    ;; One method of an instance: the class method it implements, the global
    ;; that holds its definition, and the thunk that expands it.
    (struct MethodDefinition
      ((method String)
       (global String)
       (expand (-> Unit ! mut))))

    (: instance-method (-> Context Env Class Instance Syntax MethodDefinition ! mut))
    (define (instance-method cx env class instance definition)
      (unless (core-form? cx env definition "define") (compile-error (syntax-loc definition) "expected a method definition"))
      (let* ((ident (definition-name definition))
             (method (match (find (lambda (method) (string=? (short-name method) (Ident-name ident))) (Class-methods class))
                       ((Some method) method)
                       ((None) (compile-error (syntax-loc ident) (string-append "not a method of this class: " (Ident-name ident))))))
             (global (fresh-global cx (short-name method))))
        (add-value! (program cx) global (Defined (Some (instance-method-scheme (program cx) class method instance))))
        (MethodDefinition method global (lambda () (add-item! (program cx) (Define global (definition-value cx env definition)))))))

    (: instance-method-scheme (-> Program Class String Instance Scheme ! mut))
    (define (instance-method-scheme program class method instance)
      (match (program-value program method)
        ((Some (Method _ (Scheme method-vars (Cons _ own) type)))
         (let* ((class-vars (Class-params class)) (substitution (zip class-vars (Instance-types instance))))
           (Scheme (append (Instance-vars instance) (drop method-vars (length class-vars)))
                   (append (Instance-requires instance) (map (lambda (c) (substitute-constraint substitution c)) own))
                   (substitute substitution type))))
        (_ (panic "internal error: not a method"))))

    ;; Instance selection matches heads, so two heads may never both match
    ;; the same types. A type variable in either head matches anything.
    (: check-overlap (-> Program Instance Loc Unit ! mut))
    (define (check-overlap program instance loc)
      (for-each (lambda (other)
                  (when (heads-overlap? (Instance-types instance) (Instance-types other))
                    (compile-error loc "this instance overlaps another instance of the class")))
                (class-instances program (Instance-class instance))))

    (: heads-overlap? (-> (List Type) (List Type) Bool))
    (define (heads-overlap? as bs)
      (every? (lambda (pair) (head-overlaps? (Pair-first pair) (Pair-second pair))) (zip as bs)))

    (: head-overlaps? (-> Type Type Bool))
    (define (head-overlaps? a b)
      (match a
        ((TCon name args)
         (match b
           ((TCon other others) (and (string=? name other) (heads-overlap? args others)))
           ((TRigid _) #t)
           (_ #f)))
        (_ #t)))

    (: check-instance-methods (-> Class (List MethodDefinition) Loc Unit))
    (define (check-instance-methods class methods loc)
      (for-each (lambda (method)
                  (unless (any? (lambda (definition) (string=? (MethodDefinition-method definition) method)) methods)
                    (compile-error loc (string-append "instance is missing a method: " (short-name method)))))
                (Class-methods class)))

    (: free-type-names (-> Context Env Syntax (List String) ! mut))
    (define (free-type-names cx env syntax)
      (match syntax
        ((Ident name _ _)
         (match (resolve cx env syntax)
           ((Some _) (Nil))
           ((None) (list name))))
        ((Form items _) (concatenate (map (lambda (item) (free-type-names cx env item)) items)))
        (_ (Nil))))

    (: declare-extern! (-> Context Env Syntax Unit ! mut))
    (define (declare-extern! cx env form)
      (match form
        ((Form (Cons _ (Cons name (Cons (Atom (DString module) _) (Cons (Atom (DString symbol) _) (Cons type (Nil)))))) _)
         (add-value! (program cx) (global-binding cx env name)
                     (Foreign (Import module symbol) (mono-scheme (resolve-type cx env type)))))
        (_ (compile-error (syntax-loc form) "expected (extern name \"module\" \"symbol\" type)"))))

    ;; Operations perform their effect; host defaults name Wasm imports.
    (: declare-effect! (-> Context Env Syntax Unit ! mut))
    (define (declare-effect! cx env form)
      (match form
        ((Form (Cons _ (Cons name (Cons operations host))) _)
         (let ((id (match (resolve cx env name) ((Some (EffectName id)) id) (_ (panic "internal error: effect")))))
           (add-effect! (program cx)
                        (Effect id
                                (map (lambda (operation) (declare-operation! cx env id operation))
                                     (form-items operations "a list of operations"))
                                (match host
                                  ((Cons clause (Nil)) (host-defaults cx env clause))
                                  (_ (Nil)))))))
        (_ (compile-error (syntax-loc form) "expected (effect Name ((operation type) ...))"))))

    (: declare-operation! (-> Context Env String Syntax String ! mut))
    (define (declare-operation! cx env effect operation)
      (match operation
        ((Form (Cons name (Cons type (Nil))) _)
         (match (resolve-scheme cx env type)
           ((Scheme vars constraints (TFun params result (TRow (Nil) (None))))
            (let ((global (global-binding cx env name)))
              (add-value! (program cx) global
                          (Operation effect (Scheme vars constraints (TFun params result (TRow (list effect) (None))))))
              global))
           (_ (compile-error (syntax-loc type) "an operation has a total function type; its effect is implied"))))
        (_ (compile-error (syntax-loc operation) "expected (operation type)"))))

    (: host-defaults (-> Context Env Syntax (List (Pair String Import)) ! mut))
    (define (host-defaults cx env syntax)
      (match syntax
        ((Form (Cons (Ident "host" _ _) (Cons (Atom (DString module) _) (Cons operations (Nil)))) _)
         (map (lambda (operation)
                (match operation
                  ((Form (Cons name (Cons (Atom (DString symbol) _) (Nil))) _) (Pair (global-binding cx env name) (Import module symbol)))
                  (_ (compile-error (syntax-loc operation) "expected (operation \"symbol\")"))))
              (form-items operations "a list of host operations")))
        (_ (compile-error (syntax-loc syntax) "expected (host \"module\" ((operation \"symbol\") ...))"))))

    ;; ---- Types ----

    ;; `(All (A e) (requires (Class A) ...) type)` or a plain type.
    (: resolve-scheme (-> Context Env Syntax Scheme ! mut))
    (define (resolve-scheme cx env syntax)
      (match syntax
        ((Form (Cons (Ident "All" _ _) (Cons (Form params _) rest)) loc)
         (let* ((params (map (lambda (param) (expect-ident param "a type variable")) params))
                (scope (type-scope env params)) (parts (split-requires rest)))
           (match (Pair-second parts)
             ((Cons type (Nil))
              (Scheme (map Ident-name params) (map (lambda (c) (resolve-constraint cx scope c)) (Pair-first parts))
                      (resolve-type cx scope type)))
             (_ (compile-error loc "expected (All (variable ...) [(requires constraint ...)] type)")))))
        (_ (mono-scheme (resolve-type cx env syntax)))))

    (: resolve-constraint (-> Context Env Syntax Constraint ! mut))
    (define (resolve-constraint cx env syntax)
      (match syntax
        ((Form (Cons class types) loc)
         (match (resolve cx env (expect-ident class "a typeclass"))
           ((Some (ClassName id)) (Constraint id (map (lambda (type) (resolve-type cx env type)) types)))
           (_ (compile-error loc "expected a typeclass constraint"))))
        (_ (compile-error (syntax-loc syntax) "expected (Class type ...)"))))

    (: resolve-type (-> Context Env Syntax Type ! mut))
    (define (resolve-type cx env syntax)
      (match syntax
        ((Ident _ _ loc) (resolve-type-name cx env syntax (Nil) loc))
        ((Form (Cons (Ident "->" _ _) items) loc) (resolve-arrow cx env items (Nil) loc))
        ((Form (Cons head args) loc) (resolve-type-name cx env (expect-ident head "a type constructor") args loc))
        (_ (compile-error (syntax-loc syntax) "expected a type"))))

    (: resolve-type-name (-> Context Env Syntax (List Syntax) Loc Type ! mut))
    (define (resolve-type-name cx env ident args loc)
      (match (resolve cx env ident)
        ((Some (TypeName name arity _))
         (unless (= arity (length args)) (compile-error loc (string-append "wrong number of type arguments: " (Ident-name ident))))
         (TCon name (map (lambda (arg) (resolve-type cx env arg)) args)))
        ((Some (TypeVar type)) (if (null? args) type (compile-error loc "a type variable takes no arguments")))
        ((Some (Alias _ params body alias-env expanding))
         (unless (= (length params) (length args))
           (compile-error loc (string-append "wrong number of alias arguments: " (Ident-name ident))))
         (when (ref-get expanding) (compile-error loc (string-append "type alias refers to itself: " (Ident-name ident))))
         (let ((scope (fold-left (lambda (scope pair) (extend scope (Pair-first pair) (TypeVar (resolve-type cx env (Pair-second pair)))))
                                 alias-env (zip params args))))
           (ref-set! expanding #t)
           (let ((type (resolve-type cx scope body)))
             (ref-set! expanding #f)
             type)))
        (_ (compile-error loc (string-append "not a type: " (Ident-name ident))))))

    ;; `(-> A B R)` or `(-> A B R ! label ... [row-variable])`.
    (: resolve-arrow (-> Context Env (List Syntax) (List Type) Loc Type ! mut))
    (define (resolve-arrow cx env items params loc)
      (match items
        ((Nil) (compile-error loc "an arrow needs a result type"))
        ((Cons result (Nil)) (TFun (reverse params) (resolve-type cx env result) empty-row))
        ((Cons result (Cons (Ident "!" _ _) labels)) (TFun (reverse params) (resolve-type cx env result) (resolve-row cx env labels loc)))
        ((Cons param rest) (resolve-arrow cx env rest (Cons (resolve-type cx env param) params) loc))))

    (: resolve-row (-> Context Env (List Syntax) Loc Type ! mut))
    (define (resolve-row cx env items loc)
      (let loop ((items items) (labels (Nil)))
        (match items
          ((Nil) (TRow labels (None)))
          ((Cons item rest)
           (match (resolve cx env (expect-ident item "an effect label"))
             ((Some (EffectName name)) (loop rest (label-union labels (list name))))
             ((Some (TypeVar type)) (if (null? rest) (TRow labels (Some type)) (compile-error loc "a row variable must come last")))
             (_ (compile-error (syntax-loc item) (string-append "not an effect: " (Ident-name item)))))))))

    ;; ---- Expressions ----

    ;; Expands macro uses at the head of a form until the head is not a macro.
    (: expand-head (-> Context Env Syntax Syntax ! mut))
    (define (expand-head cx env syntax)
      (match (head-binding cx env syntax)
        ((Some (Macro _ literals rules scope)) (expand-head cx env (apply-macro cx env syntax literals rules scope)))
        (_ syntax)))

    (: expr (-> Term Loc Expr))
    (define (expr term loc)
      (Expr term unchecked loc))

    (: expand-expr (-> Context Env Syntax Expr ! mut))
    (define (expand-expr cx env syntax)
      (let ((syntax (expand-head cx env syntax)))
        (match syntax
          ((Atom value loc) (expr (Lit value) loc))
          ((Ident _ _ loc) (expand-reference cx env syntax loc))
          ((Form (Nil) loc) (compile-error loc "empty application"))
          ((Form (Cons head args) loc)
           (match (head-binding cx env syntax)
             ((Some (Core keyword)) (expand-core cx env keyword (Form-items syntax) loc))
             (_ (expr (App (expand-expr cx env head) (map (lambda (arg) (expand-expr cx env arg)) args)) loc)))))))

    (: expand-reference (-> Context Env Syntax Loc Expr ! mut))
    (define (expand-reference cx env ident loc)
      (match (resolve cx env ident)
        ((Some (Local name)) (expr (Var name (Nil) (Nil)) loc))
        ((Some (Global name)) (expr (Var name (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (Some constructor))) (expr (Var constructor (Nil) (Nil)) loc))
        ((Some (TypeName _ _ (None))) (compile-error loc (string-append "a type is not a value: " (Ident-name ident))))
        ((None) (compile-error loc (string-append "unbound identifier " (Ident-name ident))))
        (_ (compile-error loc (string-append "syntax used as a value: " (Ident-name ident))))))

    (: expand-core (-> Context Env String (List Syntax) Loc Expr ! mut))
    (define (expand-core cx env keyword items loc)
      (case keyword
        (("lambda")
         (match items
           ((Cons _ (Cons params body)) (expand-lambda cx env (form-items params "a parameter list") body loc))
           (_ (compile-error loc "expected (lambda (parameter ...) body ...)"))))
        (("if")
         (match items
           ((Cons _ (Cons test (Cons then (Cons otherwise (Nil)))))
            (expr (If (expand-expr cx env test) (expand-expr cx env then) (expand-expr cx env otherwise)) loc))
           ((Cons _ (Cons test (Cons then (Nil))))
            (expr (If (expand-expr cx env test) (expand-expr cx env then) (expr (Lit (DUnit)) loc)) loc))
           (_ (compile-error loc "expected (if test then [else])"))))
        (("begin") (expand-body cx env (list-tail items 1) loc))
        (("let") (expand-let cx env items loc))
        (("match") (expand-match cx env items loc))
        (("ann")
         (match items
           ((Cons _ (Cons value (Cons type (Nil)))) (expr (Ann (expand-expr cx env value) (resolve-type cx env type)) loc))
           (_ (compile-error loc "expected (ann expression type)"))))
        (("handle") (expand-handle cx env items loc))
        (("type-convert")
         (match items
           ((Cons _ (Cons value (Cons type (Nil)))) (expr (Convert (expand-expr cx env value) (resolve-type cx env type)) loc))
           (_ (compile-error loc "expected (type-convert expression type)"))))
        (("case-id")
         (match items
           ((Cons _ (Cons constructor (Nil)))
            (expr (Ann (expr (Lit (DInt (constructor-case-id cx env constructor))) loc) (TCon "I32" (Nil))) loc))
           (_ (compile-error loc "expected (case-id Constructor)"))))
        (("quote")
         (match items
           ((Cons _ (Cons (Atom value _) (Nil))) (expr (Lit value) loc))
           (_ (compile-error loc "only literals can be quoted"))))
        (else (compile-error loc (string-append "this form is only valid as a definition: " keyword)))))

    (: expand-lambda (-> Context Env (List Syntax) (List Syntax) Loc Expr ! mut))
    (define (expand-lambda cx env params body loc)
      (let ((locals (bind-locals cx env params)))
        (expr (Lambda (Pair-second locals) (expand-body cx (Pair-first locals) body loc)) loc)))

    ;; Binds each identifier to a fresh local, in order; returns the longer
    ;; environment and the unique names.
    (: bind-locals (-> Context Env (List Syntax) (Pair Env (List String)) ! mut))
    (define (bind-locals cx env idents)
      (let ((bound (fold-left (lambda (bound ident)
                                (let ((name (fresh cx (Ident-name (expect-ident ident "a variable name")))))
                                  (Pair (extend (Pair-first bound) ident (Local name)) (Cons name (Pair-second bound)))))
                              (Pair env (Nil)) idents)))
        (Pair (Pair-first bound) (reverse (Pair-second bound)))))

    (: expand-body (-> Context Env (List Syntax) Loc Expr ! mut))
    (define (expand-body cx env forms loc)
      (when (null? forms) (compile-error loc "empty body"))
      (expand-body-forms cx env forms (None) loc))

    ;; A local body is sequential: each definition is visible to the forms
    ;; after it, and a function definition is also visible to itself. A
    ;; signature annotates the definition that follows it.
    (: expand-body-forms (-> Context Env (List Syntax) (Option (Pair String Type)) Loc Expr ! mut))
    (define (expand-body-forms cx scope forms signature loc)
      (match forms
        ((Nil) (compile-error loc "a body must end with an expression"))
        ((Cons form rest)
         (let ((form (expand-head cx scope form)))
           (match (head-binding cx scope form)
             ((Some (Core "begin")) (expand-body-forms cx scope (append (form-tail form) rest) signature loc))
             ((Some (Core "define-syntax"))
              (expand-body-forms cx (define-local-macro cx scope form) rest signature loc))
             ((Some (Core ":")) (expand-body-forms cx scope rest (Some (local-signature cx scope form)) loc))
             ((Some (Core "define")) (expand-local-definition cx scope form rest signature loc))
             (_ (let ((value (expand-expr cx scope form)))
                  (if (null? rest) value (expr (Seq value (expand-body-forms cx scope rest (None) loc)) (Expr-loc value))))))))))

    (: local-signature (-> Context Env Syntax (Pair String Type) ! mut))
    (define (local-signature cx scope form)
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (Pair (Ident-name (expect-ident name "a name")) (Scheme-type (resolve-scheme cx scope type))))
        (_ (compile-error (syntax-loc form) "expected (: name type)"))))

    (: expand-local-definition (-> Context Env Syntax (List Syntax) (Option (Pair String Type)) Loc Expr ! mut))
    (define (expand-local-definition cx scope form rest signature loc)
      (let* ((ident (definition-name form)) (name (fresh cx (Ident-name ident)))
             (function? (match form
                          ((Form (Cons _ (Cons (Form _ _) _)) _) #t)
                          ((Form (Cons _ (Cons _ (Cons value (Nil)))) _) (core-form? cx scope value "lambda"))
                          (_ #f))))
        (let* ((inner (extend scope ident (Local name))) (value (definition-value cx (if function? inner scope) form))
               (value (match signature
                        ((Some (Pair signed type))
                         (if (string=? signed (Ident-name ident)) (expr (Ann value type) (Expr-loc value)) value))
                        ((None) value))))
          (expr (Let name value (expand-body-forms cx inner rest (None) loc)) (syntax-loc form)))))

    ;; `(let ((name value) ...) body ...)` or the named-let loop form.
    (: expand-let (-> Context Env (List Syntax) Loc Expr ! mut))
    (define (expand-let cx env items loc)
      (match items
        ((Cons _ (Cons head (Cons more body)))
         (match head
           ((Ident _ _ _) (expand-named-let cx env head (form-items more "a list of bindings") body loc))
           ((Form bindings _) (expand-plain-let cx env bindings (Cons more body) loc))
           (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))
        (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))

    (: expand-named-let (-> Context Env Syntax (List Syntax) (List Syntax) Loc Expr ! mut))
    (define (expand-named-let cx env ident bindings body loc)
      (let* ((name (fresh cx (Ident-name ident))) (scope (extend env ident (Local name))))
        (expr (Let name (expand-lambda cx scope (map binding-name bindings) body loc)
                   (expr (App (expr (Var name (Nil) (Nil)) loc)
                              (map (lambda (binding) (expand-expr cx env (binding-value binding))) bindings))
                         loc))
              loc)))

    (: expand-plain-let (-> Context Env (List Syntax) (List Syntax) Loc Expr ! mut))
    (define (expand-plain-let cx env bindings body loc)
      (let* ((values (map (lambda (binding) (expand-expr cx env (binding-value binding))) bindings))
             (locals (bind-locals cx env (map binding-name bindings))))
        (fold-right (lambda (pair body) (expr (Let (Pair-first pair) (Pair-second pair) body) loc))
                    (expand-body cx (Pair-first locals) body loc) (zip (Pair-second locals) values))))

    (: binding-name (-> Syntax Syntax))
    (define (binding-name binding)
      (match (form-items binding "a (name value) binding")
        ((Cons name _) (expect-ident name "a binding name"))
        ((Nil) (compile-error (syntax-loc binding) "expected (name value)"))))

    (: binding-value (-> Syntax Syntax))
    (define (binding-value binding)
      (match binding
        ((Form (Cons _ (Cons value (Nil))) _) value)
        (_ (compile-error (syntax-loc binding) "expected (name value)"))))

    (: expand-handle (-> Context Env (List Syntax) Loc Expr ! mut))
    (define (expand-handle cx env items loc)
      (match items
        ((Cons _ (Cons effect (Cons (Form implementations _) body)))
         (let ((id (match (resolve cx env (expect-ident effect "an effect name"))
                     ((Some (EffectName id)) id)
                     (_ (compile-error (syntax-loc effect) (string-append "not an effect: " (Ident-name effect)))))))
           (expr (Handle id
                         (map (lambda (implementation)
                                (match implementation
                                  ((Form (Cons name (Cons value (Nil))) _) (Pair (operation-name cx id name) (expand-expr cx env value)))
                                  (_ (compile-error (syntax-loc implementation) "expected (operation implementation)"))))
                              implementations)
                         (expand-body cx env body loc))
                 loc)))
        (_ (compile-error loc "expected (handle Effect ((operation implementation) ...) body ...)"))))

    ;; A handler names operations by their names within the effect, so they
    ;; need not be imported.
    (: operation-name (-> Context String Syntax String ! mut))
    (define (operation-name cx effect ident)
      (let ((name (Ident-name (expect-ident ident "an operation name"))))
        (match (find (lambda (operation) (string=? (short-name operation) name)) (Effect-operations (program-effect (program cx) effect)))
          ((Some operation) operation)
          ((None) (compile-error (syntax-loc ident) (string-append "not an operation of this effect: " name))))))

    (: constructor-case-id (-> Context Env Syntax I64 ! mut))
    (define (constructor-case-id cx env constructor)
      (match (program-value (program cx) (pattern-constructor cx env constructor))
        ((Some (Constructor case _)) (case-type-id (program cx) case))
        (_ (compile-error (syntax-loc constructor) "not a constructor"))))

    ;; ---- Deriving ----

    ;; Derived instances are ordinary instance declarations, built as syntax.
    ;; Identifiers they introduce are marked to resolve in an environment of
    ;; (lofi core), (lofi primitive) and (lofi wire), whatever the declaring
    ;; library imports.
    (: derived-instances (-> Context Syntax Bool (List Syntax) ! mut fs))
    (define (derived-instances cx form enum?)
      (let* ((head (declaration-head form)) (loc (syntax-loc form))
             (cases (if enum?
                        (map (lambda (case)
                               (match (form-items case "an enum case")
                                 ((Cons name (Cons fields _)) (Pair name (length (form-items fields "a field list"))))
                                 ((Cons name (Nil)) (Pair name 0))
                                 ((Nil) (compile-error (syntax-loc case) "expected an enum case"))))
                             (enum-cases form))
                        (list (Pair (declared-name head) (length (struct-fields form)))))))
        (map (lambda (class)
               (match class
                 ((Ident "Serialize" _ _) (serialize-instance cx head cases loc))
                 ((Ident "Deserialize" _ _) (deserialize-instance cx head cases loc))
                 (_ (compile-error (syntax-loc class) "only Serialize and Deserialize can be derived"))))
             (derived-classes form))))

    (: deriving-scope (-> Context Loc I64 ! mut fs))
    (define (deriving-scope cx loc)
      (match (ref-get (Context-deriving cx))
        ((Some scope) scope)
        ((None)
         (let* ((table (make-table)) (env (Top table (None))))
           (for-each (lambda (entry) (table-set! table (Pair-first entry) (Pair-second entry)))
                     (concatenate (map (lambda (name) (load-library cx name loc))
                                       (list (list "lofi" "core") (list "lofi" "primitive") (list "lofi" "wire")))))
           (let ((scope (register-scope! cx env)))
             (ref-set! (Context-deriving cx) (Some scope))
             scope)))))

    ;; Builds the syntax of a derived instance; `w` makes wire identifiers.
    (struct Deriver
      ((scope I64)
       (loc Loc)))

    (: w (-> Deriver String Syntax))
    (define (w deriver name)
      (let ((loc (Deriver-loc deriver)))
        (Ident name (Some (Mark (string-append name "%deriving") (Ident name (None) loc) (Deriver-scope deriver))) loc)))

    (: f (-> Deriver (List Syntax) Syntax))
    (define (f deriver items)
      (Form items (Deriver-loc deriver)))

    (: field-idents (-> Deriver I64 (List Syntax)))
    (define (field-idents deriver count)
      (map (lambda (index) (w deriver (string-append "field" (i64->string index)))) (iota count)))

    (: instance-head (-> Deriver String Syntax (List Syntax)))
    (define (instance-head d class head)
      (let ((params (declared-params head)))
        (append (list (w d "instance") (f d (list (w d class) head)))
                (if (null? params)
                    (Nil)
                    (list (f d (Cons (w d "requires") (map (lambda (param) (f d (list (w d class) param))) params))))))))

    ;; Each case writes its TypeId, then its fields in order.
    (: serialize-instance (-> Context Syntax (List (Pair Syntax I64)) Loc Syntax ! mut fs))
    (define (serialize-instance cx head cases loc)
      (let* ((d (Deriver (deriving-scope cx loc) loc)) (value (w d "value")) (encoder (w d "encoder")))
        (f d (append (instance-head d "Serialize" head)
                     (list (f d (list (w d "define") (f d (list (w d "encode") value encoder))
                                      (f d (Cons (w d "match")
                                                 (Cons value (map (lambda (case) (serialize-case d case encoder)) cases)))))))))))

    (: serialize-case (-> Deriver (Pair Syntax I64) Syntax Syntax))
    (define (serialize-case d case encoder)
      (let ((fields (field-idents d (Pair-second case))))
        (f d (Cons (f d (Cons (Pair-first case) fields))
                   (Cons (f d (list (w d "encode-case-id") encoder (f d (list (w d "case-id") (Pair-first case)))))
                         (append (map (lambda (field) (f d (list (w d "encode") field encoder))) fields)
                                 (list (f d (list (w d "unit"))))))))))

    ;; The TypeId read selects the case; an unknown one is a schema mismatch.
    (: deserialize-instance (-> Context Syntax (List (Pair Syntax I64)) Loc Syntax ! mut fs))
    (define (deserialize-instance cx head cases loc)
      (let* ((d (Deriver (deriving-scope cx loc) loc)) (decoder (w d "decoder")) (id (w d "id")))
        (f d (append (instance-head d "Deserialize" head)
                     (list (f d (list (w d "define") (f d (list (w d "decode") decoder))
                                      (f d (list (w d "let") (f d (list (f d (list id (f d (list (w d "decode-case-id") decoder))))))
                                                 (fold-right (lambda (case otherwise)
                                                               (f d (list (w d "if")
                                                                          (f d (list (w d "case-id=?") id (f d (list (w d "case-id") (Pair-first case)))))
                                                                          (deserialize-case d case decoder) otherwise)))
                                                             (f d (list (w d "panic") (Atom (DString "wire data has a different schema") loc)))
                                                             cases))))))))))

    (: deserialize-case (-> Deriver (Pair Syntax I64) Syntax Syntax))
    (define (deserialize-case d case decoder)
      (let ((fields (field-idents d (Pair-second case))))
        (fold-right (lambda (field body) (f d (list (w d "let") (f d (list (f d (list field (f d (list (w d "decode") decoder)))))) body)))
                    (f d (Cons (Pair-first case) fields)) fields)))

    ;; ---- Patterns ----

    (: expand-match (-> Context Env (List Syntax) Loc Expr ! mut))
    (define (expand-match cx env items loc)
      (match items
        ((Cons _ (Cons scrutinee clauses))
         (expr (Match (expand-expr cx env scrutinee) (map (lambda (clause) (expand-clause cx env clause)) clauses)) loc))
        (_ (compile-error loc "expected (match expression clause ...)"))))

    ;; A clause binds its pattern's variables first, so the pattern itself
    ;; only looks names up.
    (: expand-clause (-> Context Env Syntax Clause ! mut))
    (define (expand-clause cx env clause)
      (match (form-items clause "a match clause")
        ((Cons pattern body)
         (let ((scope (Pair-first (bind-locals cx env (pattern-variables pattern)))))
           (Clause (expand-pattern cx env scope pattern) (expand-body cx scope body (syntax-loc clause)))))
        ((Nil) (compile-error (syntax-loc clause) "expected (pattern body ...)"))))

    ;; The variables of a pattern, in order, each named once.
    (: pattern-variables (-> Syntax (List Syntax)))
    (define (pattern-variables syntax)
      (let ((variables (pattern-idents syntax)))
        (for-each (lambda (variable)
                    (when (< 1 (length (filter (lambda (other) (string=? (ident-key other) (ident-key variable))) variables)))
                      (compile-error (syntax-loc variable) (string-append "pattern variable bound twice: " (Ident-name variable)))))
                  variables)
        variables))

    (: pattern-idents (-> Syntax (List Syntax)))
    (define (pattern-idents syntax)
      (match syntax
        ((Ident "_" _ _) (Nil))
        ((Ident _ _ _) (list syntax))
        ((Form (Cons _ args) _) (concatenate (map pattern-idents args)))
        (_ (Nil))))

    ;; Bare identifiers are `_` or variables bound in `scope`; constructors
    ;; resolve in `env` and are always applied, as in `(None)`.
    (: expand-pattern (-> Context Env Env Syntax Pattern ! mut))
    (define (expand-pattern cx env scope syntax)
      (match syntax
        ((Ident "_" _ _) (PWild unchecked))
        ((Ident _ _ _)
         (match (resolve cx scope syntax)
           ((Some (Local name)) (PVar name unchecked))
           (_ (panic "internal error: unbound pattern variable"))))
        ((Atom value _) (PLit value unchecked))
        ((Form (Cons head args) _)
         (PCon (pattern-constructor cx env head) (map (lambda (arg) (expand-pattern cx env scope arg)) args) unchecked))
        (_ (compile-error (syntax-loc syntax) "expected a pattern"))))

    (: pattern-constructor (-> Context Env Syntax String ! mut))
    (define (pattern-constructor cx env head)
      (constructor-name cx env (expect-ident head "a constructor")))

    ;; ---- Syntax rules ----

    (struct MacroForm
      ((name Syntax)
       (literals (List Syntax))
       (rules (List Syntax))))

    (: macro-form (-> Syntax MacroForm))
    (define (macro-form form)
      (match form
        ((Form (Cons _ (Cons name (Cons (Form (Cons (Ident "syntax-rules" _ _) (Cons (Form literals _) rules)) _) (Nil)))) _)
         (MacroForm (expect-ident name "a macro name") literals rules))
        (_ (compile-error (syntax-loc form) "expected (define-syntax name (syntax-rules (literal ...) rule ...))"))))

    ;; A macro's template resolves in the environment of its definition,
    ;; which includes the macro, so it may expand to a use of itself.
    (: define-top-macro! (-> Context Env Syntax Unit ! mut))
    (define (define-top-macro! cx env form)
      (let ((parts (macro-form form)))
        (bind-top! env (MacroForm-name parts)
                   (Macro (fresh cx "%macro") (MacroForm-literals parts) (MacroForm-rules parts) (register-scope! cx env)))))

    (: define-local-macro (-> Context Env Syntax Env ! mut))
    (define (define-local-macro cx env form)
      (let* ((parts (macro-form form)) (scope (register-scope! cx env))
             (inner (extend env (MacroForm-name parts) (Macro (fresh cx "%macro") (MacroForm-literals parts) (MacroForm-rules parts) scope))))
        (table-set! (Context-scopes cx) (i64->string scope) inner)
        inner))

    (: apply-macro (-> Context Env Syntax (List Syntax) (List Syntax) I64 Syntax ! mut))
    (define (apply-macro cx env form literals rules scope)
      (let ((loc (syntax-loc form)))
        (match rules
          ((Nil) (compile-error loc "no syntax-rules pattern matches this use"))
          ((Cons rule more)
           (match rule
             ((Form (Cons (Form (Cons _ pattern) _) (Cons template (Nil))) _)
              (match (match-pattern cx (Form pattern loc) (Form (form-tail form) loc) literals env (scope-env cx scope))
                ((Some bindings) (transcribe template bindings (Expansion (make-table) (fresh cx "m") scope loc)))
                ((None) (apply-macro cx env form literals more scope))))
             (_ (compile-error (syntax-loc rule) "expected ((_ pattern ...) template)")))))))

    ;; What a pattern variable matched: one form, or under n ellipses a
    ;; depth-n nesting of matches.
    (enum Bound
      (One
       ((syntax Syntax)))
      (Many
       ((matches (List Bound)))))

    (type Bindings (List (Pair String Bound)))

    (: literal? (-> Syntax (List Syntax) Bool))
    (define (literal? ident literals)
      (any? (lambda (literal) (string=? (ident-key literal) (ident-key ident))) literals))

    (: match-pattern (-> Context Syntax Syntax (List Syntax) Env Env (Option Bindings) ! mut))
    (define (match-pattern cx pattern input literals env macro-env)
      (match pattern
        ((Ident "_" _ _) (Some (Nil)))
        ((Ident _ _ _)
         (cond ((not (literal? pattern literals)) (Some (list (Pair (ident-key pattern) (One input)))))
               ((same-binding? cx env input macro-env pattern) (Some (Nil)))
               (else (None))))
        ((Atom value _)
         (match input
           ((Atom other _) (if (datum=? value other) (Some (Nil)) (None)))
           (_ (None))))
        ((Form items _)
         (match input
           ((Form inputs _) (match-items cx items inputs literals env macro-env))
           (_ (None))))))

    ;; A literal matches an identifier with the same binding, or the same
    ;; name when both are unbound.
    (: same-binding? (-> Context Env Syntax Env Syntax Bool ! mut))
    (define (same-binding? cx env input macro-env literal)
      (match input
        ((Ident name _ _)
         (match (resolve cx env input)
           ((Some a)
            (match (resolve cx macro-env literal)
              ((Some b) (string=? (binding-identity a) (binding-identity b)))
              ((None) #f)))
           ((None)
            (match (resolve cx macro-env literal)
              ((Some _) #f)
              ((None) (string=? name (Ident-name literal)))))))
        (_ #f)))

    (: match-items (-> Context (List Syntax) (List Syntax) (List Syntax) Env Env (Option Bindings) ! mut))
    (define (match-items cx patterns inputs literals env macro-env)
      (match patterns
        ((Cons repeated (Cons (Ident "..." _ _) after)) (match-ellipsis cx repeated after inputs literals env macro-env))
        ((Nil) (if (null? inputs) (Some (Nil)) (None)))
        ((Cons pattern more)
         (match inputs
           ((Nil) (None))
           ((Cons input rest)
            (match (match-pattern cx pattern input literals env macro-env)
              ((Some head)
               (match (match-items cx more rest literals env macro-env)
                 ((Some tail) (Some (append head tail)))
                 ((None) (None))))
              ((None) (None))))))))

    (: match-ellipsis (-> Context Syntax (List Syntax) (List Syntax) (List Syntax) Env Env (Option Bindings) ! mut))
    (define (match-ellipsis cx repeated after inputs literals env macro-env)
      (let ((count (- (length inputs) (length after))))
        (if (< count 0)
            (None)
            (match (match-items cx after (drop inputs count) literals env macro-env)
              ((None) (None))
              ((Some tail)
               (match (all-matched (map (lambda (input) (match-pattern cx repeated input literals env macro-env)) (take inputs count)))
                 ((None) (None))
                 ((Some matches)
                  (Some (append (map (lambda (key) (Pair key (Many (map (lambda (bindings) (bound-ref bindings key)) matches))))
                                     (pattern-keys repeated literals))
                                tail)))))))))

    ;; Every match, or None if any failed.
    (: all-matched (-> (List (Option Bindings)) (Option (List Bindings))))
    (define (all-matched matches)
      (fold-right (lambda (match-result rest)
                    (match match-result
                      ((Some bindings) (match rest ((Some more) (Some (Cons bindings more))) ((None) (None))))
                      ((None) (None))))
                  (Some (Nil)) matches))

    (: bound-ref (-> Bindings String Bound))
    (define (bound-ref bindings key)
      (match (assoc-ref bindings key)
        ((Some bound) bound)
        ((None) (panic "internal error: unbound pattern variable"))))

    (: pattern-keys (-> Syntax (List Syntax) (List String)))
    (define (pattern-keys pattern literals)
      (match pattern
        ((Ident name _ _)
         (if (or (string=? name "_") (string=? name "...") (literal? pattern literals)) (Nil) (list (ident-key pattern))))
        ((Form items _) (concatenate (map (lambda (item) (pattern-keys item literals)) items)))
        (_ (Nil))))

    ;; One expansion: identifiers the template introduces share one mark per
    ;; name, and every introduced form is located at the macro use.
    (struct Expansion
      ((renames (Table Syntax))
       (stamp String)
       (scope I64)
       (loc Loc)))

    (: transcribe (-> Syntax Bindings Expansion Syntax ! mut))
    (define (transcribe template bindings expansion)
      (match template
        ((Ident name _ _)
         (match (assoc-ref bindings (ident-key template))
           ((None) (rename-ident template expansion))
           ((Some (Many _)) (compile-error (Expansion-loc expansion) (string-append "pattern variable used without an ellipsis: " name)))
           ((Some (One syntax)) syntax)))
        ((Atom _ _) template)
        ((Form items _) (Form (transcribe-items items bindings expansion) (Expansion-loc expansion)))))

    (: transcribe-items (-> (List Syntax) Bindings Expansion (List Syntax) ! mut))
    (define (transcribe-items items bindings expansion)
      (match items
        ((Nil) (Nil))
        ((Cons item (Cons (Ident "..." _ _) rest))
         (append (transcribe-repeated item bindings expansion) (transcribe-items rest bindings expansion)))
        ((Cons item rest) (Cons (transcribe item bindings expansion) (transcribe-items rest bindings expansion)))))

    ;; The repeated template iterates over every variable it uses that matched
    ;; under an ellipsis; such variables must have equal lengths.
    (: transcribe-repeated (-> Syntax Bindings Expansion (List Syntax) ! mut))
    (define (transcribe-repeated template bindings expansion)
      (let ((repeated (concatenate (map (lambda (key)
                                          (match (assoc-ref bindings key)
                                            ((Some (Many matches)) (list (Pair key matches)))
                                            (_ (Nil))))
                                        (delete-duplicates string=? (template-keys template))))))
        (match repeated
          ((Nil) (compile-error (Expansion-loc expansion) "ellipsis follows a template without pattern variables"))
          ((Cons first _)
           (let ((count (length (Pair-second first))))
             (unless (every? (lambda (entry) (= count (length (Pair-second entry)))) repeated)
               (compile-error (Expansion-loc expansion) "pattern variables under one ellipsis matched different lengths"))
             (map (lambda (index)
                    (transcribe template
                                (append (map (lambda (entry) (Pair (Pair-first entry) (list-ref (Pair-second entry) index))) repeated)
                                        bindings)
                                expansion))
                  (iota count)))))))

    (: template-keys (-> Syntax (List String)))
    (define (template-keys template)
      (match template
        ((Ident _ _ _) (list (ident-key template)))
        ((Form items _) (concatenate (map template-keys items)))
        (_ (Nil))))

    (: rename-ident (-> Syntax Expansion Syntax ! mut))
    (define (rename-ident ident expansion)
      (let ((key (ident-key ident)))
        (match (table-ref (Expansion-renames expansion) key)
          ((Some renamed) renamed)
          ((None)
           (let ((renamed (Ident (Ident-name ident)
                                 (Some (Mark (string-append key "%" (Expansion-stamp expansion)) ident (Expansion-scope expansion)))
                                 (Expansion-loc expansion))))
             (table-set! (Expansion-renames expansion) key renamed)
             renamed)))))

    ))
