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
   (scheme base)
   (scheme char)
   (scheme cxr)
   (scheme file)
   (srfi 1)
   (srfi 69)
   (lofi compiler shim)
   (lofi compiler read)
   (lofi compiler core))
  (begin

    ;; ---- Identifiers, marks and environments ----

    ;; A macro expansion marks each identifier its template introduces. The
    ;; mark's key is unique to the expansion; an unbound marked identifier
    ;; resolves as its original in the macro's definition environment.
    (struct Mark
      ((key Symbol)
       (original Syntax)
       (env Env)))

    (struct Env
      ((table HashTable)
       (parent Env)))

    (define (child-env parent)
      (Env (make-hash-table eq?) parent))

    (define (ident-key ident)
      (let ((mark (Ident-mark ident)))
        (if mark (Mark-key mark) (Ident-name ident))))

    (define (resolve env ident)
      (let lookup ((frame env))
        (cond (frame (or (hash-table-ref/default (Env-table frame) (ident-key ident) #f)
                         (lookup (Env-parent frame))))
              ((Ident-mark ident)
               (resolve (Mark-env (Ident-mark ident)) (Mark-original (Ident-mark ident))))
              (else #f))))

    (define (bind! env ident binding)
      (hash-table-set! (Env-table env) (ident-key ident) binding))

    (define (ident? syntax)
      (match syntax
        ((Ident _ _ _) #t)
        (_ #f)))

    (define (ident-named? syntax name)
      (and (ident? syntax) (eq? (Ident-name syntax) name)))

    (define (expect-ident syntax what)
      (unless (ident? syntax) (compile-error (syntax-loc syntax) (string-append "expected " what)))
      syntax)

    ;; The items of a form, or an error naming what was expected.
    (define (form-items syntax what)
      (match syntax
        ((Form items _) items)
        (_ (compile-error (syntax-loc syntax) (string-append "expected " what)))))

    ;; ---- Bindings ----

    ;; A struct's name is both a type and its constructor.
    (enum Binding
      (Local
       ((name Symbol)))
      (Global
       ((name Symbol)))
      (TypeName
       ((name Symbol)
        (arity I64)
        (constructor Symbol)))
      (Alias
       ((params (List Syntax))
        (body Syntax)
        (env Env)))
      (TypeVar
       ((type Type)))
      (ClassName
       ((name Symbol)))
      (EffectName
       ((name Symbol)))
      (Core
       ((name Symbol)))
      (Macro
       ((literals (List Syntax))
        (rules (List Syntax))
        (env Env))))

    (define (head-binding env syntax)
      (match syntax
        ((Form (Cons head _) _) (and (ident? head) (resolve env head)))
        (_ #f)))

    (define (core-form? env syntax name)
      (match (head-binding env syntax)
        ((Core keyword) (eq? keyword name))
        (_ #f)))

    ;; ---- Expansion context ----

    ;; Shared by every library of one compilation. `prefix` names the library
    ;; being expanded, so its globals are `prefix:name`.
    (struct Context
      ((program Program)
       (directories (List String))
       (libraries HashTable)
       (counter (Ref I64))
       (deriving (Ref Env))
       (prefix String)))

    (define (make-context directories)
      (let ((cx (Context (make-program) directories (make-hash-table equal?) (ref 0) (ref #f) "")))
        (hash-table-set! (Context-libraries cx) '(lofi core) (core-library))
        (hash-table-set! (Context-libraries cx) '(lofi primitive) (primitive-library cx))
        cx))

    (define (fresh cx base)
      (let ((count (+ (ref-get (Context-counter cx)) 1)))
        (ref-set! (Context-counter cx) count)
        (string->symbol (string-append (if (symbol? base) (symbol->string base) base) "." (number->string count)))))

    (define (global-name cx key)
      (string->symbol (string-append (Context-prefix cx) ":" (symbol->string key))))

    (define (fresh-global cx base)
      (global-name cx (fresh cx base)))

    (define (program cx)
      (Context-program cx))

    ;; ---- Builtin libraries ----

    (struct Library
      ((name (List Symbol))
       (exports (List (Pair Symbol Binding)))))

    (define core-keywords
      '(define lambda if begin let define-syntax syntax-rules quote : struct enum type
         typeclass instance match ann extern effect handle expose case-id))

    (define (core-library)
      (Library '(lofi core)
               (append (map (lambda (name) (cons name (Core name))) core-keywords)
                       (map (lambda (entry) (cons (car entry) (TypeName (car entry) (cdr entry) #f))) builtin-types)
                       (list (cons 'mut (EffectName 'mut))))))

    (define (primitive-library cx)
      (Library '(lofi primitive)
               (map (lambda (entry)
                      (let ((name (string->symbol (string-append "prim:" (symbol->string (car entry))))))
                        (add-value! (program cx) name (Primitive (generalize-rigids (datum->type (cadr entry)))))
                        (cons (car entry) (Global name))))
                    primitives)))

    ;; Quantifies every rigid variable of a primitive's type.
    (define (generalize-rigids type)
      (Scheme (delete-duplicates (rigid-names type '())) '() type))

    (define (rigid-names type names)
      (match type
        ((TRigid name) (cons name names))
        ((TCon _ args) (fold rigid-names names args))
        ((TFun params result row) (rigid-names row (rigid-names result (fold rigid-names names params))))
        ((TRow _ tail) (if tail (rigid-names tail names) names))
        (_ names)))

    ;; ---- Libraries ----

    (define (library-path directory name)
      (string-append directory "/"
                     (let join ((parts (map (lambda (part) (if (symbol? part) (symbol->string part) (number->string part))) name)))
                       (if (null? (cdr parts)) (car parts) (string-append (car parts) "/" (join (cdr parts)))))
                     ".sld"))

    (define (library-prefix name)
      (let join ((parts (map (lambda (part) (if (symbol? part) (symbol->string part) (number->string part))) name)))
        (if (null? (cdr parts)) (car parts) (string-append (car parts) "." (join (cdr parts))))))

    ;; Loads each library once. A library that is still loading when it is
    ;; requested again is part of an import cycle.
    (define (load-library cx name loc)
      (let ((loaded (hash-table-ref/default (Context-libraries cx) name #f)))
        (cond ((eq? loaded 'loading) (compile-error loc "library import cycle" name))
              (loaded loaded)
              (else (hash-table-set! (Context-libraries cx) name 'loading)
                    (let ((library (read-library cx name loc)))
                      (hash-table-set! (Context-libraries cx) name library)
                      library)))))

    (define (read-library cx name loc)
      (let ((path (find (lambda (path) (file-exists? path))
                        (map (lambda (directory) (library-path directory name)) (Context-directories cx)))))
        (unless path (compile-error loc "library not found" name))
        (match (read-file path)
          ((list (Form (Cons head declarations) form-loc))
           (unless (ident-named? head 'define-library) (compile-error form-loc "expected define-library"))
           (expand-library cx name declarations form-loc))
          (_ (compile-error (Loc path 1 1) "expected exactly one define-library form")))))

    (define (expand-library cx name declarations loc)
      (let ((declared (syntax->datum (car declarations))))
        (unless (equal? declared name) (compile-error loc "library name does not match its path" declared))
        (let* ((sections (map (lambda (declaration) (library-section declaration)) (cdr declarations)))
               (cx (Context-prefix-set cx (library-prefix name)))
               (env (import-env cx (section-items sections 'import))))
          (expand-top-level cx env (section-items sections 'begin))
          (Library name (map (lambda (spec) (export-entry env spec)) (section-items sections 'export))))))

    (define (library-section declaration)
      (match declaration
        ((Form (Cons (Ident kind _ _) items) _)
         (if (memq kind '(import export begin))
             (cons kind items)
             (compile-error (syntax-loc declaration) "expected import, export or begin")))
        (_ (compile-error (syntax-loc declaration) "expected import, export or begin"))))

    (define (section-items sections kind)
      (append-map cdr (filter (lambda (section) (eq? (car section) kind)) sections)))

    ;; A program is a sequence of imports followed by a body.
    (define (expand-program cx path)
      (let* ((forms (read-file path))
             (imports (take-while (lambda (form) (match form ((Form (Cons (Ident 'import _ _) _) _) #t) (_ #f))) forms))
             (cx (Context-prefix-set cx "main"))
             (env (import-env cx (append-map (lambda (form) (cdr (Form-items form))) imports))))
        (expand-top-level cx env (drop forms (length imports)))
        (program cx)))

    ;; ---- Imports and exports ----

    (define (import-env cx specs)
      (let ((imports (child-env #f)))
        (for-each
         (lambda (spec)
           (for-each (lambda (entry) (import-binding! imports entry (syntax-loc spec)))
                     (import-set cx spec)))
         specs)
        (child-env imports)))

    (define (import-binding! env entry loc)
      (let ((existing (hash-table-ref/default (Env-table env) (car entry) #f)))
        (when (and existing (not (eq? existing (cdr entry))))
          (compile-error loc "conflicting imports" (car entry)))
        (hash-table-set! (Env-table env) (car entry) (cdr entry))))

    ;; Returns the (name . binding) entries an import set provides.
    (define (import-set cx spec)
      (let ((items (form-items spec "an import set")))
        (match (car items)
          ((Ident 'only _ _) (filter (lambda (entry) (memq (car entry) (names (cddr items))))
                                     (checked-import-set cx (cadr items) (cddr items))))
          ((Ident 'except _ _) (remove (lambda (entry) (memq (car entry) (names (cddr items))))
                                       (checked-import-set cx (cadr items) (cddr items))))
          ((Ident 'prefix _ _) (map (lambda (entry) (cons (symbol-append (Ident-name (caddr items)) (car entry)) (cdr entry)))
                                    (import-set cx (cadr items))))
          ((Ident 'rename _ _) (map (lambda (entry) (rename-entry entry (cddr items))) (checked-import-set cx (cadr items) (map (lambda (pair) (car (Form-items pair))) (cddr items)))))
          (_ (Library-exports (load-library cx (syntax->datum spec) (syntax-loc spec)))))))

    (define (checked-import-set cx spec idents)
      (let ((entries (import-set cx spec)))
        (for-each (lambda (ident)
                    (unless (assq (Ident-name ident) entries)
                      (compile-error (syntax-loc ident) "import names an identifier the library does not export" (Ident-name ident))))
                  idents)
        entries))

    (define (names idents)
      (map (lambda (ident) (Ident-name (expect-ident ident "an identifier"))) idents))

    (define (rename-entry entry pairs)
      (let ((pair (find (lambda (pair) (eq? (Ident-name (car (Form-items pair))) (car entry))) pairs)))
        (if pair (cons (Ident-name (cadr (Form-items pair))) (cdr entry)) entry)))

    (define (symbol-append a b)
      (string->symbol (string-append (symbol->string a) (symbol->string b))))

    (define (export-entry env spec)
      (match spec
        ((Ident name _ loc) (cons name (or (resolve env spec) (compile-error loc "exported name is not defined" name))))
        ((Form (list (Ident 'rename _ _) inner (Ident outer _ _)) loc)
         (cons outer (or (resolve env inner) (compile-error loc "exported name is not defined" (Ident-name inner)))))
        (_ (compile-error (syntax-loc spec) "expected an export specification"))))

    ;; ---- Top-level bodies ----

    ;; Pass 1 discovers every top-level name, so definitions may refer to later
    ;; ones. Pass 2 resolves declarations and signatures, returning one thunk
    ;; per definition or expression; running the thunks in order expands them.
    (define (expand-top-level cx env forms)
      (let* ((pending (append-each (lambda (form) (scan-top-level cx env form)) forms))
             (signatures (make-hash-table eq?))
             (definitions (append-each (lambda (entry) (declare! cx signatures entry)) pending)))
        (for-each (lambda (expand!) (expand!)) definitions)))

    ;; A pending entry is (keyword form env).
    (define (scan-top-level cx env form)
      (let ((form (expand-head cx env form)))
        (match (head-binding env form)
          ((Core 'begin) (append-each (lambda (item) (scan-top-level cx env item)) (cdr (Form-items form))))
          ((Core 'define-syntax) (define-macro! env form) '())
          ((Core 'define) (let ((ident (definition-name form)))
                            (bind-top! cx env ident (Global (global-name cx (ident-key ident))))
                            (list (list 'define form env))))
          ((Core keyword)
           (if (memq keyword '(: struct enum type typeclass instance extern effect expose))
               (begin (scan-declaration cx env keyword form)
                      (cons (list keyword form env)
                            (if (memq keyword '(struct enum))
                                (append-each (lambda (instance) (scan-top-level cx env instance))
                                             (derived-instances cx env form (eq? keyword 'enum)))
                                '())))
               (list (list 'expression form env))))
          (_ (list (list 'expression form env))))))

    ;; `append-map` with a guaranteed left-to-right order, for effectful passes.
    (define (append-each f items)
      (let loop ((items items) (results '()))
        (if (null? items)
            (apply append (reverse results))
            (let ((result (f (car items))))
              (loop (cdr items) (cons result results))))))

    (define (bind-top! cx env ident binding)
      (when (hash-table-ref/default (Env-table env) (ident-key ident) #f)
        (compile-error (syntax-loc ident) "duplicate top-level definition" (Ident-name ident)))
      (bind! env ident binding))

    (define (definition-name form)
      (match (Form-items form)
        ((Cons _ (Cons (Form (Cons name _) _) _)) (expect-ident name "a definition name"))
        ((list _ name _) (expect-ident name "a definition name"))
        (_ (compile-error (syntax-loc form) "expected (define name value) or (define (name parameter ...) body ...)"))))

    (define (declare! cx signatures entry)
      (let ((keyword (car entry)) (form (cadr entry)) (env (caddr entry)))
        (case keyword
          ((:) (declare-signature! cx signatures env form) '())
          ((struct enum) (declare-data! cx env form (eq? keyword 'enum)) '())
          ((typeclass) (declare-class! cx env form) '())
          ((instance) (declare-instance! cx env form))
          ((extern) (declare-extern! cx env form) '())
          ((effect) (declare-effect! cx env form) '())
          ((define) (list (lambda () (define-top-level! cx signatures env form))))
          ((expose) (list (lambda () (add-item! (program cx) (expose-item env form)))))
          ((expression) (list (lambda () (add-item! (program cx) (Do (expand-expr cx env form))))))
          (else '()))))

    ;; `(expose name "symbol")` exports a top-level function to the host.
    (define (expose-item env form)
      (match (Form-items form)
        ((list _ name (Atom symbol _))
         (match (resolve env (expect-ident name "a function name"))
           ((Global global) (Expose global symbol (syntax-loc form)))
           (_ (compile-error (syntax-loc name) "only a top-level function can be exposed" (Ident-name name)))))
        (_ (compile-error (syntax-loc form) "expected (expose name \"symbol\")"))))

    (define (define-top-level! cx signatures env form)
      (let ((name (Global-name (resolve env (definition-name form)))))
        (add-value! (program cx) name (Defined (hash-table-ref/default signatures name #f)))
        (add-item! (program cx) (Define name (definition-value cx env form)))))

    (define (definition-value cx env form)
      (match (Form-items form)
        ((Cons _ (Cons (Form (Cons name params) _) body)) (expand-lambda cx env params body (syntax-loc form)))
        ((list _ name value) (expand-expr cx env value))))

    ;; ---- Declarations ----

    ;; Pass 1 binds the names a declaration introduces; pass 2 resolves types.
    (define (scan-declaration cx env keyword form)
      (let ((items (Form-items form)))
        (case keyword
          ((struct) (let* ((name (declared-name (cadr items))) (id (global-name cx (ident-key name))))
                      (bind-top! cx env name (TypeName id (length (declared-params (cadr items))) id))
                      (bind-fields! cx env name (struct-fields form) #t)))
          ((enum) (let ((name (declared-name (cadr items))))
                    (bind-top! cx env name (TypeName (global-name cx (ident-key name)) (length (declared-params (cadr items))) #f))
                    (for-each (lambda (case) (scan-case! cx env case)) (cddr (declaration-items form)))))
          ((type) (let ((name (declared-name (cadr items))))
                    (bind-top! cx env name (Alias (declared-params (cadr items)) (caddr items) env))))
          ((typeclass) (let ((name (declared-name (cadr items))))
                         (bind-top! cx env name (ClassName (global-name cx (ident-key name))))
                         (for-each (lambda (signature) (bind-member! cx env (cadr (Form-items signature)))) (cddr items))))
          ((extern) (bind-member! cx env (cadr items)))
          ((effect) (let ((name (expect-ident (cadr items) "an effect name")))
                      (bind-top! cx env name (EffectName (global-name cx (ident-key name))))
                      (for-each (lambda (operation) (bind-member! cx env (car (Form-items operation))))
                                (form-items (caddr items) "a list of operations"))))
          (else #f))))

    (define (bind-member! cx env ident)
      (let ((ident (expect-ident ident "a name")))
        (bind-top! cx env ident (Global (global-name cx (ident-key ident))))))

    (define (scan-case! cx env case)
      (let* ((items (form-items case "an enum case")) (name (expect-ident (car items) "a case name")))
        (bind-member! cx env name)
        (bind-fields! cx env name (if (pair? (cdr items)) (form-items (cadr items) "a field list") '()) #f)))

    ;; Accessors are `Name-field`; structs also get replacements `Name-field-set`.
    (define (bind-fields! cx env name fields setters?)
      (for-each (lambda (field)
                  (let ((accessor (field-ident name (car (form-items field "a field")) "")))
                    (bind-member! cx env accessor)
                    (when setters? (bind-member! cx env (field-ident name (car (Form-items field)) "-set")))))
                fields))

    (define (field-ident name field suffix)
      (Ident (string->symbol (string-append (symbol->string (Ident-name name)) "-"
                                            (symbol->string (Ident-name (expect-ident field "a field name"))) suffix))
             (and (Ident-mark name) (Mark (string->symbol (string-append (symbol->string (ident-key name)) "-"
                                                                         (symbol->string (Ident-name field)) suffix))
                                          (Mark-original (Ident-mark name)) (Mark-env (Ident-mark name))))
             (Ident-loc field)))

    (define (declared-name head)
      (match head
        ((Form (Cons name _) _) (expect-ident name "a type name"))
        (_ (expect-ident head "a type name"))))

    (define (declared-params head)
      (match head
        ((Form (Cons _ params) _) (map (lambda (param) (expect-ident param "a type parameter")) params))
        (_ '())))

    (define (struct-fields form)
      (match (declaration-items form)
        ((list _ _) '())
        ((list _ _ fields) (form-items fields "a field list"))
        (_ (compile-error (syntax-loc form) "expected (struct Name ((field type) ...))"))))

    ;; A struct or enum may end with `(deriving Class ...)`.
    (define (declaration-items form)
      (remove deriving-clause? (Form-items form)))

    (define (deriving-clause? syntax)
      (match syntax
        ((Form (Cons (Ident 'deriving _ _) _) _) #t)
        (_ #f)))

    (define (derived-classes form)
      (append-map (lambda (item) (cdr (Form-items item))) (filter deriving-clause? (Form-items form))))

    ;; A type parameter scope binds each parameter to a rigid variable.
    (define (type-scope env params)
      (let ((scope (child-env env)))
        (for-each (lambda (param) (bind! scope param (TypeVar (TRigid (Ident-name param))))) params)
        scope))

    (define (declare-data! cx env form enum?)
      (let* ((head (cadr (Form-items form))) (params (declared-params head))
             (id (TypeName-name (resolve env (declared-name head)))) (scope (type-scope env params))
             (cases (if enum?
                        (map (lambda (case) (form-items case "an enum case")) (cddr (declaration-items form)))
                        (list (cons (declared-name head) (if (null? (struct-fields form)) '() (list (caddr (declaration-items form))))))))
             (data (DataType id (map Ident-name params)
                             (map (lambda (case tag) (resolve-case scope case id tag)) cases (iota (length cases)))
                             enum?)))
        (add-type! (program cx) data)
        (for-each (lambda (case) (declare-case-values! cx data case (not enum?))) (DataType-cases data))))

    ;; A case is its name followed by an optional field list.
    (define (resolve-case scope case type tag)
      (Case (Global-or-constructor (resolve scope (car case))) type tag
            (map (lambda (field)
                   (match (form-items field "a (field type) pair")
                     ((list name type) (Field (Ident-name (expect-ident name "a field name")) (resolve-type scope type)))
                     (_ (compile-error (syntax-loc field) "expected (field type)"))))
                 (if (pair? (cdr case)) (form-items (cadr case) "a field list") '()))))

    (define (Global-or-constructor binding)
      (match binding
        ((Global name) name)
        ((TypeName _ _ constructor) constructor)))

    (define (declare-case-values! cx data case setters?)
      (let* ((params (DataType-params data)) (self (TCon (DataType-name data) (map TRigid params)))
             (scheme (lambda (type) (Scheme params '() type))))
        (add-value! (program cx) (Case-name case) (Constructor case (scheme (TFun (map Field-type (Case-fields case)) self empty-row))))
        (let loop ((fields (Case-fields case)) (index 0))
          (unless (null? fields)
            (let ((accessor (global-member cx (Case-name case) (Field-name (car fields)) "")) (type (Field-type (car fields))))
              (add-value! (program cx) accessor (Accessor case index (scheme (TFun (list self) type empty-row))))
              (when setters?
                (add-value! (program cx) (global-member cx (Case-name case) (Field-name (car fields)) "-set")
                            (Replacer case index (scheme (TFun (list self type) self empty-row)))))
              (loop (cdr fields) (+ index 1)))))))

    (define (global-member cx case field suffix)
      (string->symbol (string-append (symbol->string case) "-" (symbol->string field) suffix)))

    ;; `(: name type)` records a scheme for the following definition.
    (define (declare-signature! cx signatures env form)
      (match (Form-items form)
        ((list _ name type)
         (match (resolve env (expect-ident name "a name"))
           ((Global global) (hash-table-set! signatures global (resolve-scheme env type)))
           (_ (compile-error (syntax-loc name) "signature names an undefined top-level definition" (Ident-name name)))))
        (_ (compile-error (syntax-loc form) "expected (: name type)"))))

    (define (declare-class! cx env form)
      (let* ((items (Form-items form)) (head (cadr items)) (params (declared-params head))
             (id (ClassName-name (resolve env (declared-name head)))) (scope (type-scope env params))
             (self (Constraint id (map (lambda (param) (TRigid (Ident-name param))) params))))
        (add-class! (program cx)
                    (Class id (map Ident-name params)
                           (map (lambda (signature)
                                  (match (Form-items signature)
                                    ((list _ name type)
                                     (let ((own (resolve-scheme scope type)) (global (Global-name (resolve env name))))
                                       (add-value! (program cx) global
                                                   (Method id (Scheme (append (map Ident-name params) (Scheme-vars own))
                                                                      (cons self (Scheme-constraints own)) (Scheme-type own))))
                                       global))
                                    (_ (compile-error (syntax-loc signature) "expected (: method type)"))))
                                (cddr items))))))

    ;; Unbound identifiers in an instance head are its type variables. Returns
    ;; one thunk per method, which expands its definition.
    (define (declare-instance! cx env form)
      (let* ((items (Form-items form)) (head (form-items (cadr items) "an instance head"))
             (class (match (resolve env (car head)) ((ClassName id) (program-class (program cx) id))
                           (_ (compile-error (syntax-loc (car head)) "instance of something that is not a typeclass"))))
             (vars (delete-duplicates (append-map (lambda (type) (free-type-idents env type)) (cdr head)) eq?))
             (scope (type-scope env (map (lambda (name) (Ident name #f (syntax-loc form))) vars)))
             (requires? (and (pair? (cddr items)) (match (caddr items) ((Form (Cons (Ident 'requires _ _) _) _) #t) (_ #f))))
             (instance (Instance (fresh-global cx (short-name (Class-name class))) (Class-name class) vars
                                 (map (lambda (type) (resolve-type scope type)) (cdr head))
                                 (if requires? (map (lambda (c) (resolve-constraint scope c)) (cdr (Form-items (caddr items)))) '())
                                 '()))
             (methods (map (lambda (definition) (instance-method cx env class instance definition))
                           (if requires? (cdddr items) (cddr items)))))
        (check-instance-methods class methods (syntax-loc form))
        (check-overlap (program cx) instance (syntax-loc form))
        (add-instance! (program cx) (Instance-methods-set instance (map (lambda (method) (cons (car method) (cadr method))) methods)))
        (map caddr methods)))

    ;; Returns (class-method global thunk) for one method definition.
    (define (instance-method cx env class instance definition)
      (unless (core-form? env definition 'define) (compile-error (syntax-loc definition) "expected a method definition"))
      (let* ((ident (definition-name definition))
             (method (match (resolve env ident) ((Global name) name) (_ #f)))
             (global (fresh-global cx (short-name (or method (Ident-name ident))))))
        (unless (memq method (Class-methods class))
          (compile-error (syntax-loc ident) "not a method of this class" (Ident-name ident)))
        (add-value! (program cx) global (Defined (instance-method-scheme (program cx) class method instance)))
        (list method global (lambda () (add-item! (program cx) (Define global (definition-value cx env definition)))))))

    (define (instance-method-scheme program class method instance)
      (match (program-value program method)
        ((Method _ (Scheme method-vars (Cons _ own) type))
         (let* ((class-vars (Class-params class)) (substitution (map cons class-vars (Instance-types instance))))
           (Scheme (append (Instance-vars instance) (drop method-vars (length class-vars)))
                   (append (Instance-requires instance) (map (lambda (c) (substitute-constraint substitution c)) own))
                   (substitute substitution type))))))

    ;; Instance selection matches heads, so two heads may never both match
    ;; the same types. A type variable in either head matches anything.
    (define (check-overlap program instance loc)
      (for-each (lambda (other)
                  (when (every heads-overlap? (Instance-types instance) (Instance-types other))
                    (compile-error loc "this instance overlaps another instance of the class")))
                (class-instances program (Instance-class instance))))

    (define (heads-overlap? a b)
      (match a
        ((TRigid _) #t)
        ((TCon name args)
         (match b
           ((TRigid _) #t)
           ((TCon other others) (and (eq? name other) (every heads-overlap? args others)))
           (_ #f)))
        (_ #t)))

    (define (check-instance-methods class methods loc)
      (for-each (lambda (method)
                  (unless (assq method methods) (compile-error loc "instance is missing a method" (short-name method))))
                (Class-methods class)))

    (define (free-type-idents env syntax)
      (match syntax
        ((Ident name _ _) (if (resolve env syntax) '() (list name)))
        ((Form items _) (append-map (lambda (item) (free-type-idents env item)) items))
        (_ '())))

    (define (declare-extern! cx env form)
      (match (Form-items form)
        ((list _ name (Atom module _) (Atom symbol _) type)
         (add-value! (program cx) (Global-name (resolve env name))
                     (Foreign module symbol (mono-scheme (resolve-type env type)))))
        (_ (compile-error (syntax-loc form) "expected (extern name \"module\" \"symbol\" type)"))))

    ;; Operations perform their effect; host defaults name Wasm imports.
    (define (declare-effect! cx env form)
      (let* ((items (Form-items form)) (id (EffectName-name (resolve env (cadr items))))
             (operations (map (lambda (operation)
                                (match (Form-items operation)
                                  ((list name type) (declare-operation! cx env id name type))
                                  (_ (compile-error (syntax-loc operation) "expected (operation type)"))))
                              (Form-items (caddr items)))))
        (add-effect! (program cx)
                     (Effect id operations (if (pair? (cdddr items)) (host-defaults env (cadddr items)) '())))))

    (define (declare-operation! cx env effect name type)
      (match (resolve-scheme env type)
        ((Scheme vars constraints (TFun params result (TRow '() #f)))
         (let ((global (Global-name (resolve env name))))
           (add-value! (program cx) global (Operation effect (Scheme vars constraints (TFun params result (TRow (list effect) #f)))))
           global))
        (_ (compile-error (syntax-loc type) "an operation has a total function type; its effect is implied"))))

    (define (host-defaults env syntax)
      (match (Form-items syntax)
        ((list (Ident 'host _ _) (Atom module _) operations)
         (map (lambda (operation)
                (match (Form-items operation)
                  ((list name (Atom symbol _)) (cons (Global-name (resolve env name)) (cons module symbol)))))
              (Form-items operations)))
        (_ (compile-error (syntax-loc syntax) "expected (host \"module\" ((operation \"symbol\") ...))"))))

    ;; ---- Types ----

    ;; `(All (A e) (requires (Class A) ...) type)` or a plain type.
    (define (resolve-scheme env syntax)
      (match syntax
        ((Form (Cons (Ident 'All _ _) (Cons (Form params _) rest)) loc)
         (let* ((scope (type-scope env params))
                (requires? (and (pair? (cdr rest)) (match (car rest) ((Form (Cons (Ident 'requires _ _) _) _) #t) (_ #f)))))
           (Scheme (map Ident-name params)
                   (if requires? (map (lambda (c) (resolve-constraint scope c)) (cdr (Form-items (car rest)))) '())
                   (resolve-type scope (if requires? (cadr rest) (car rest))))))
        (_ (mono-scheme (resolve-type env syntax)))))

    (define (resolve-constraint env syntax)
      (match syntax
        ((Form (Cons class types) loc)
         (match (resolve env class)
           ((ClassName id) (Constraint id (map (lambda (type) (resolve-type env type)) types)))
           (_ (compile-error loc "expected a typeclass constraint"))))
        (_ (compile-error (syntax-loc syntax) "expected (Class type ...)"))))

    (define (resolve-type env syntax)
      (match syntax
        ((Ident name _ loc) (resolve-type-name env syntax '() loc))
        ((Form (Cons (Ident '-> _ _) items) loc) (resolve-arrow env items '() loc))
        ((Form (Cons head args) loc) (resolve-type-name env (expect-ident head "a type constructor") args loc))
        (_ (compile-error (syntax-loc syntax) "expected a type"))))

    (define (resolve-type-name env ident args loc)
      (match (resolve env ident)
        ((TypeName name arity _)
         (unless (= arity (length args)) (compile-error loc "wrong number of type arguments" (Ident-name ident)))
         (TCon name (map (lambda (arg) (resolve-type env arg)) args)))
        ((TypeVar type) (if (null? args) type (compile-error loc "a type variable takes no arguments")))
        ((Alias params body alias-env)
         (unless (= (length params) (length args)) (compile-error loc "wrong number of alias arguments" (Ident-name ident)))
         (let ((scope (child-env alias-env)))
           (for-each (lambda (param arg) (bind! scope param (TypeVar (resolve-type env arg)))) params args)
           (resolve-type scope body)))
        (_ (compile-error loc "not a type" (Ident-name ident)))))

    ;; `(-> A B R)` or `(-> A B R ! label ... [row-variable])`.
    (define (resolve-arrow env items params loc)
      (cond ((null? items) (compile-error loc "an arrow needs a result type"))
            ((or (null? (cdr items)) (ident-named? (cadr items) '!))
             (TFun (reverse params) (resolve-type env (car items))
                   (if (null? (cdr items)) empty-row (resolve-row env (cddr items) loc))))
            (else (resolve-arrow env (cdr items) (cons (resolve-type env (car items)) params) loc))))

    (define (resolve-row env items loc)
      (let loop ((items items) (labels '()))
        (if (null? items)
            (TRow (sort-labels labels) #f)
            (match (resolve env (expect-ident (car items) "an effect label"))
              ((EffectName name) (loop (cdr items) (if (memq name labels) labels (cons name labels))))
              ((TypeVar type) (if (null? (cdr items)) (TRow (sort-labels labels) type)
                                  (compile-error loc "a row variable must come last")))
              (_ (compile-error (syntax-loc (car items)) "not an effect" (Ident-name (car items))))))))

    (define (sort-labels labels)
      (sort-symbols labels))

    (define (sort-symbols symbols)
      (if (null? symbols)
          '()
          (let ((pivot (symbol->string (car symbols))))
            (append (sort-symbols (filter (lambda (s) (string<? (symbol->string s) pivot)) (cdr symbols)))
                    (list (car symbols))
                    (sort-symbols (filter (lambda (s) (string>=? (symbol->string s) pivot)) (cdr symbols)))))))

    ;; ---- Expressions ----

    ;; Expands macro uses at the head of a form until the head is not a macro.
    (define (expand-head cx env syntax)
      (match (head-binding env syntax)
        ((Macro literals rules macro-env) (expand-head cx env (apply-macro cx env syntax literals rules macro-env)))
        (_ syntax)))

    (define (expr term loc)
      (Expr term #f loc))

    (define (unit-expr loc)
      (expr (Lit 'unit) loc))

    (define (expand-expr cx env syntax)
      (let ((syntax (expand-head cx env syntax)))
        (match syntax
          ((Atom value loc) (expr (Lit value) loc))
          ((Ident name _ loc) (expand-reference env syntax loc))
          ((Form '() loc) (compile-error loc "empty application"))
          ((Form (Cons head args) loc)
           (match (head-binding env syntax)
             ((Core keyword) (expand-core cx env keyword syntax (Form-items syntax) loc))
             (_ (expr (App (expand-expr cx env head) (map (lambda (arg) (expand-expr cx env arg)) args)) loc)))))))

    (define (expand-reference env ident loc)
      (match (resolve env ident)
        ((Local name) (expr (Var name '() '()) loc))
        ((Global name) (expr (Var name '() '()) loc))
        ((TypeName _ _ constructor)
         (if constructor (expr (Var constructor '() '()) loc) (compile-error loc "a type is not a value" (Ident-name ident))))
        (#f (compile-error loc "unbound identifier" (Ident-name ident)))
        (_ (compile-error loc "syntax used as a value" (Ident-name ident)))))

    (define (expand-core cx env keyword syntax items loc)
      (case keyword
        ((lambda) (if (and (pair? (cdr items)) (pair? (cddr items)))
                      (expand-lambda cx env (form-items (cadr items) "a parameter list") (cddr items) loc)
                      (compile-error loc "expected (lambda (parameter ...) body ...)")))
        ((if) (match items
                ((list _ test then else) (expr (If (expand-expr cx env test) (expand-expr cx env then) (expand-expr cx env else)) loc))
                ((list _ test then) (expr (If (expand-expr cx env test) (expand-expr cx env then) (unit-expr loc)) loc))
                (_ (compile-error loc "expected (if test then [else])"))))
        ((begin) (expand-body cx env (cdr items) loc))
        ((let) (expand-let cx env items loc))
        ((match) (expand-match cx env items loc))
        ((ann) (match items
                 ((list _ value type) (expr (Ann (expand-expr cx env value) (resolve-type env type)) loc))
                 (_ (compile-error loc "expected (ann expression type)"))))
        ((handle) (expand-handle cx env items loc))
        ((case-id) (match items
                     ((list _ constructor) (expr (Ann (expr (Lit (constructor-case-id cx env constructor)) loc) (TCon 'I32 '())) loc))
                     (_ (compile-error loc "expected (case-id Constructor)"))))
        ((quote) (match items
                   ((list _ (Atom value _)) (expr (Lit value) loc))
                   (_ (compile-error loc "only literals can be quoted"))))
        (else (compile-error loc "this form is only valid as a definition" keyword))))

    (define (expand-lambda cx env params body loc)
      (let* ((scope (child-env env))
             (names (map (lambda (param)
                           (let ((name (fresh cx (Ident-name (expect-ident param "a parameter name")))))
                             (bind! scope param (Local name))
                             name))
                         params)))
        (expr (Lambda names (expand-body cx scope body loc)) loc)))

    ;; A local body is sequential: each definition is visible to the forms
    ;; after it, and a function definition is also visible to itself.
    (define (expand-body cx env forms loc)
      (when (null? forms) (compile-error loc "empty body"))
      (let ((scope (child-env env)))
        (let loop ((forms forms) (signature #f))
          (if (null? forms)
              (compile-error loc "a body must end with an expression")
              (expand-body-form cx scope (expand-head cx scope (car forms)) (cdr forms) signature loop)))))

    (define (expand-body-form cx scope form rest signature continue)
      (match (head-binding scope form)
        ((Core 'begin) (continue (append (cdr (Form-items form)) rest) signature))
        ((Core 'define-syntax) (define-macro! scope form) (continue rest signature))
        ((Core ':) (continue rest (cons (cadr (Form-items form)) (resolve-scheme scope (caddr (Form-items form))))))
        ((Core 'define) (expand-local-definition cx scope form rest signature continue))
        (_ (let ((value (expand-expr cx scope form)))
             (if (null? rest) value (expr (Seq value (continue rest #f)) (Expr-loc value)))))))

    (define (expand-local-definition cx scope form rest signature continue)
      (let* ((ident (definition-name form)) (name (fresh cx (Ident-name ident)))
             (function? (or (match (Form-items form) ((Cons _ (Cons (Form _ _) _)) #t) (_ #f))
                            (core-form? scope (caddr (Form-items form)) 'lambda))))
        (when function? (bind! scope ident (Local name)))
        (let ((value (definition-value cx scope form)))
          (unless function? (bind! scope ident (Local name)))
          (let ((value (if (and signature (eq? (Ident-name (car signature)) (Ident-name ident)))
                           (expr (Ann value (Scheme-type (cdr signature))) (Expr-loc value))
                           value)))
            (expr (Let name value (continue rest #f)) (syntax-loc form))))))

    ;; `(let ((name value) ...) body ...)` or the named-let loop form.
    (define (expand-let cx env items loc)
      (match items
        ((Cons _ (Cons (Ident _ _ _) (Cons (Form bindings _) body)))
         (let* ((ident (cadr items)) (name (fresh cx (Ident-name ident))) (scope (child-env env)))
           (bind! scope ident (Local name))
           (expr (Let name (expand-lambda cx scope (map binding-name bindings) body loc)
                      (expr (App (expr (Var name '() '()) loc) (map (lambda (b) (expand-expr cx env (binding-value b))) bindings)) loc))
                 loc)))
        ((Cons _ (Cons (Form bindings _) body))
         (let* ((values (map (lambda (binding) (expand-expr cx env (binding-value binding))) bindings))
                (scope (child-env env))
                (names (map (lambda (binding) (let ((name (fresh cx (Ident-name (binding-name binding)))))
                                                (bind! scope (binding-name binding) (Local name))
                                                name))
                            bindings)))
           (fold-right (lambda (name value body) (expr (Let name value body) loc))
                       (expand-body cx scope body loc) names values)))
        (_ (compile-error loc "expected (let ((name value) ...) body ...)"))))

    (define (binding-name binding)
      (expect-ident (car (form-items binding "a (name value) binding")) "a binding name"))

    (define (binding-value binding)
      (match (Form-items binding)
        ((list _ value) value)
        (_ (compile-error (syntax-loc binding) "expected (name value)"))))

    (define (expand-handle cx env items loc)
      (match items
        ((Cons _ (Cons effect (Cons (Form implementations _) body)))
         (let ((id (match (resolve env (expect-ident effect "an effect name"))
                     ((EffectName id) id)
                     (_ (compile-error (syntax-loc effect) "not an effect" (Ident-name effect))))))
           (expr (Handle id (map (lambda (implementation)
                                   (match (Form-items implementation)
                                     ((list name value) (cons (Global-name (resolve env name)) (expand-expr cx env value)))
                                     (_ (compile-error (syntax-loc implementation) "expected (operation implementation)"))))
                                 implementations)
                         (expand-body cx env body loc))
                 loc)))
        (_ (compile-error loc "expected (handle Effect ((operation implementation) ...) body ...)"))))

    (define (constructor-case-id cx env constructor)
      (match (program-value (program cx) (pattern-constructor env constructor))
        ((Constructor case _) (case-type-id (program cx) case))
        (_ (compile-error (syntax-loc constructor) "not a constructor"))))

    ;; ---- Deriving ----

    ;; Derived instances are ordinary instance declarations, built as syntax.
    ;; Identifiers they introduce are marked to resolve in an environment of
    ;; (lofi core), (lofi primitive) and (lofi wire), whatever the declaring
    ;; library imports.
    (define (derived-instances cx env form enum?)
      (let* ((head (cadr (Form-items form))) (loc (syntax-loc form))
             (cases (if enum?
                        (map (lambda (case) (let ((items (Form-items case)))
                                              (cons (car items) (if (pair? (cdr items)) (length (Form-items (cadr items))) 0))))
                             (cddr (declaration-items form)))
                        (list (cons (declared-name head) (length (struct-fields form)))))))
        (map (lambda (class)
               (case (Ident-name class)
                 ((Serialize) (serialize-instance cx head cases loc))
                 ((Deserialize) (deserialize-instance cx head cases loc))
                 (else (compile-error (syntax-loc class) "only Serialize and Deserialize can be derived"))))
             (derived-classes form))))

    (define (deriving-env cx loc)
      (or (ref-get (Context-deriving cx))
          (let ((env (child-env #f)))
            (for-each (lambda (entry) (hash-table-set! (Env-table env) (car entry) (cdr entry)))
                      (append (Library-exports (load-library cx '(lofi core) loc))
                              (Library-exports (load-library cx '(lofi primitive) loc))
                              (Library-exports (load-library cx '(lofi wire) loc))))
            (ref-set! (Context-deriving cx) env)
            env)))

    (define (wire-ident cx name loc)
      (let ((original (Ident name #f loc)))
        (Ident name (Mark (string->symbol (string-append (symbol->string name) "%deriving")) original (deriving-env cx loc)) loc)))

    (define (form loc . items)
      (Form items loc))

    (define (field-idents cx count loc)
      (map (lambda (index) (wire-ident cx (string->symbol (string-append "field" (number->string index))) loc)) (iota count)))

    (define (instance-head cx class head loc)
      (let ((params (declared-params head)))
        (append (list (wire-ident cx 'instance loc) (form loc (wire-ident cx class loc) head))
                (if (null? params) '()
                    (list (apply form loc (wire-ident cx 'requires loc)
                                 (map (lambda (param) (form loc (wire-ident cx class loc) param)) params)))))))

    ;; Each case writes its TypeId, then its fields in order.
    (define (serialize-instance cx head cases loc)
      (let ((w (lambda (name) (wire-ident cx name loc))) (value (wire-ident cx 'value loc)) (encoder (wire-ident cx 'encoder loc)))
        (apply form loc
               (append (instance-head cx 'Serialize head loc)
                       (list (form loc (w 'define) (form loc (w 'encode) value encoder)
                                   (apply form loc (w 'match) value
                                          (map (lambda (case)
                                                 (let ((fields (field-idents cx (cdr case) loc)))
                                                   (apply form loc (apply form loc (car case) fields)
                                                          (form loc (w 'encode-case-id) encoder (form loc (w 'case-id) (car case)))
                                                          (append (map (lambda (field) (form loc (w 'encode) field encoder)) fields)
                                                                  (list (form loc (w 'unit)))))))
                                               cases))))))))

    ;; The TypeId read selects the case; an unknown one is a schema mismatch.
    (define (deserialize-instance cx head cases loc)
      (let* ((w (lambda (name) (wire-ident cx name loc))) (decoder (wire-ident cx 'decoder loc)) (id (wire-ident cx 'id loc))
             (decode-case (lambda (case)
                            (let ((fields (field-idents cx (cdr case) loc)))
                              (fold-right (lambda (field body) (form loc (w 'let) (form loc (form loc field (form loc (w 'decode) decoder))) body))
                                          (apply form loc (car case) fields) fields)))))
        (apply form loc
               (append (instance-head cx 'Deserialize head loc)
                       (list (form loc (w 'define) (form loc (w 'decode) decoder)
                                   (form loc (w 'let) (form loc (form loc id (form loc (w 'decode-case-id) decoder)))
                                         (fold-right (lambda (case otherwise)
                                                       (form loc (w 'if) (form loc (w 'case-id=?) id (form loc (w 'case-id) (car case)))
                                                             (decode-case case) otherwise))
                                                     (form loc (w 'panic) (Atom "wire data has a different schema" loc))
                                                     cases))))))))

    ;; ---- Patterns ----

    (define (expand-match cx env items loc)
      (when (null? (cdr items)) (compile-error loc "expected (match expression clause ...)"))
      (expr (Match (expand-expr cx env (cadr items))
                   (map (lambda (clause)
                          (match (form-items clause "a match clause")
                            ((Cons pattern body)
                             (let ((scope (child-env env)))
                               (let ((pattern (expand-pattern cx env scope pattern)))
                                 (Clause pattern (expand-body cx scope body (syntax-loc clause))))))))
                        (cddr items)))
            loc))

    ;; Bare identifiers are variables or `_`; constructors are always applied,
    ;; as in `(None)`.
    (define (expand-pattern cx env scope syntax)
      (match syntax
        ((Ident '_ _ _) (PWild #f))
        ((Ident name _ _)
         (let ((local (fresh cx name)))
           (when (hash-table-ref/default (Env-table scope) (ident-key syntax) #f)
             (compile-error (syntax-loc syntax) "pattern variable bound twice" name))
           (bind! scope syntax (Local local))
           (PVar local #f)))
        ((Atom value _) (PLit value #f))
        ((Form (Cons head args) loc)
         (PCon (pattern-constructor env head) (map (lambda (arg) (expand-pattern cx env scope arg)) args) #f))
        (_ (compile-error (syntax-loc syntax) "expected a pattern"))))

    (define (pattern-constructor env head)
      (match (resolve env (expect-ident head "a constructor"))
        ((TypeName _ _ constructor)
         (or constructor (compile-error (syntax-loc head) "not a constructor" (Ident-name head))))
        ((Global name) name)
        (_ (compile-error (syntax-loc head) "not a constructor" (Ident-name head)))))

    ;; ---- Syntax rules ----

    (define (define-macro! env form)
      (match (Form-items form)
        ((list _ name (Form (Cons (Ident 'syntax-rules _ _) (Cons (Form literals _) rules)) _))
         (bind! env (expect-ident name "a macro name") (Macro literals rules env)))
        (_ (compile-error (syntax-loc form) "expected (define-syntax name (syntax-rules (literal ...) rule ...))"))))

    (define (apply-macro cx env form literals rules macro-env)
      (let try ((rules rules))
        (when (null? rules) (compile-error (syntax-loc form) "no syntax-rules pattern matches this use"))
        (match (form-items (car rules) "a syntax rule")
          ((list (Form (Cons _ pattern) _) template)
           (let ((bindings (match-pattern (Form pattern #f) (Form (cdr (Form-items form)) #f) literals env macro-env)))
             (if bindings
                 (transcribe template bindings (Expansion (make-hash-table eq?) (fresh cx "m") macro-env (syntax-loc form)))
                 (try (cdr rules)))))
          (_ (compile-error (syntax-loc (car rules)) "expected ((_ pattern ...) template)")))))

    ;; Returns an association list from pattern-variable keys to matches, or
    ;; #f. A variable under n ellipses matches a depth-n nested list.
    (define (match-pattern pattern input literals env macro-env)
      (match pattern
        ((Ident '_ _ _) '())
        ((Ident name _ _)
         (cond ((find (lambda (literal) (eq? (ident-key literal) (ident-key pattern))) literals)
                (and (ident? input) (same-binding? env input macro-env pattern) '()))
               (else (list (cons (ident-key pattern) input)))))
        ((Atom value _) (and (match input ((Atom other _) (equal? value other)) (_ #f)) '()))
        ((Form items _) (match input ((Form inputs _) (match-items items inputs literals env macro-env)) (_ #f)))))

    (define (same-binding? env input macro-env literal)
      (let ((a (resolve env input)) (b (resolve macro-env literal)))
        (if (or a b) (eq? a b) (eq? (Ident-name input) (Ident-name literal)))))

    (define (match-items patterns inputs literals env macro-env)
      (cond ((and (pair? patterns) (pair? (cdr patterns)) (ident-named? (cadr patterns) '...))
             (match-ellipsis (car patterns) (cddr patterns) inputs literals env macro-env))
            ((null? patterns) (and (null? inputs) '()))
            ((null? inputs) #f)
            (else (let ((head (match-pattern (car patterns) (car inputs) literals env macro-env)))
                    (and head (let ((tail (match-items (cdr patterns) (cdr inputs) literals env macro-env)))
                                (and tail (append head tail))))))))

    (define (match-ellipsis repeated after inputs literals env macro-env)
      (let ((count (- (length inputs) (length after))))
        (and (>= count 0)
             (let ((matches (map (lambda (input) (match-pattern repeated input literals env macro-env)) (take inputs count)))
                   (tail (match-items after (drop inputs count) literals env macro-env)))
               (and tail (every (lambda (m) m) matches)
                    (append (map (lambda (key) (cons key (Repeated (map (lambda (m) (cdr (assq key m))) matches))))
                                 (pattern-keys repeated literals))
                            tail))))))

    (struct Repeated
      ((matches (List Match))))

    (define (pattern-keys pattern literals)
      (match pattern
        ((Ident name _ _)
         (if (or (memq name '(_ ...)) (find (lambda (literal) (eq? (ident-key literal) (ident-key pattern))) literals))
             '() (list (ident-key pattern))))
        ((Form items _) (append-map (lambda (item) (pattern-keys item literals)) items))
        (_ '())))

    ;; One expansion: identifiers the template introduces share one mark per
    ;; name, and every introduced form is located at the macro use.
    (struct Expansion
      ((renames HashTable)
       (stamp Symbol)
       (env Env)
       (loc Loc)))

    (define (transcribe template bindings expansion)
      (match template
        ((Ident name _ _)
         (let ((binding (assq (ident-key template) bindings)))
           (cond ((not binding) (rename-ident template expansion))
                 ((Repeated? (cdr binding)) (compile-error (Expansion-loc expansion) "pattern variable used without an ellipsis" name))
                 (else (cdr binding)))))
        ((Atom _ _) template)
        ((Form items _) (Form (transcribe-items items bindings expansion) (Expansion-loc expansion)))))

    (define (Repeated? value)
      (match value
        ((Repeated _) #t)
        (_ #f)))

    (define (transcribe-items items bindings expansion)
      (cond ((null? items) '())
            ((and (pair? (cdr items)) (ident-named? (cadr items) '...))
             (append (transcribe-repeated (car items) bindings expansion)
                     (transcribe-items (cddr items) bindings expansion)))
            (else (cons (transcribe (car items) bindings expansion)
                        (transcribe-items (cdr items) bindings expansion)))))

    ;; The repeated template iterates over every variable it uses that matched
    ;; under an ellipsis; such variables must have equal lengths.
    (define (transcribe-repeated template bindings expansion)
      (let* ((keys (template-keys template))
             (repeated (filter (lambda (binding) (and (memq (car binding) keys) (Repeated? (cdr binding)))) bindings)))
        (when (null? repeated) (compile-error (Expansion-loc expansion) "ellipsis follows a template without pattern variables"))
        (let ((count (length (Repeated-matches (cdar repeated)))))
          (unless (every (lambda (binding) (= count (length (Repeated-matches (cdr binding))))) repeated)
            (compile-error (Expansion-loc expansion) "pattern variables under one ellipsis matched different lengths"))
          (let loop ((index 0))
            (if (= index count)
                '()
                (cons (transcribe template
                                  (append (map (lambda (binding) (cons (car binding) (list-ref (Repeated-matches (cdr binding)) index))) repeated)
                                          bindings)
                                  expansion)
                      (loop (+ index 1))))))))

    (define (template-keys template)
      (match template
        ((Ident _ _ _) (list (ident-key template)))
        ((Form items _) (append-map template-keys items))
        (_ '())))

    (define (rename-ident ident expansion)
      (let* ((renames (Expansion-renames expansion)) (key (ident-key ident))
             (existing (hash-table-ref/default renames key #f)))
        (or existing
            (let ((renamed (Ident (Ident-name ident)
                                  (Mark (string->symbol (string-append (symbol->string key) "%" (symbol->string (Expansion-stamp expansion))))
                                        ident (Expansion-env expansion))
                                  (Expansion-loc expansion))))
              (hash-table-set! renames key renamed)
              renamed))))

    ))
