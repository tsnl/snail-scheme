;; Expressions and the bodies that hold them. An expression's head is
;; expanded first: while it names a macro, the macro's use is replaced by
;; what it writes. Then an atom is a literal, an identifier a path or a
;; reference, and a form a path applied, a core form or a call. A body is
;; sequential: each definition it holds binds a local over the forms after
;; it, a macro it defines is a frame of its own, and it ends with an
;; expression.
;;
;; Everything is checked in the old expander's order, so a program with
;; two problems is told of the same one. What needs declarations, which
;; `declare` makes, is left to it: which operation a handler's clause
;; implements, whether a value is a constructor, and whether a type with
;; a Drop instance may be taken apart here. Each step threads the state
;; of (snail compiler expand state), the numbers it hands out.
(define-library (snail compiler expand expressions)
  (export
   Site
   WrittenSets
   expand-expression
   expand-body
   expand-head
   defined-value
   instance-sets
   expr-loc)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (only (snail compiler outline names) same-library?)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand forms)
   (snail compiler expand scopes)
   (snail compiler expand state)
   (snail compiler expand paths)
   (snail compiler expand form-shapes)
   (snail compiler expand macros)
   (snail compiler expand types)
   (snail compiler expand patterns))
  (begin

    ;; ---- Sites ----

    ;; Where an expression is expanded: the scopes its names resolve in,
    ;; the environment around it, and the sets each `with-instances` around
    ;; it names, innermost first, as written where they were.
    (struct Site
      ((scopes Scopes)
       (env Env)
       (instance-sets (List WrittenSets))))

    (struct WrittenSets
      ((sets (List Marked))
       (env Env)))

    ;; `site` with each identifier bound to its local, the last innermost.
    (: bound-site (impl (Fn Site (List Identifier) (List Local) -> Site)))
    (define (bound-site site identifiers locals)
      (framed-site site
                   (fold-left (lambda (frames pair)
                                (Cons (Frame (::first pair) (LocalValue (::second pair))) frames))
                              (::frames (::env site))
                              (zip identifiers locals))))

    (: framed-site (impl (Fn Site (List Frame) -> Site)))
    (define (framed-site site frames)
      (Site (::scopes site) (Env frames (::library (::env site))) (::instance-sets site)))

    ;; A fresh local for each identifier, and the site that binds them.
    (struct Bound
      ((site Site)
       (locals (List Local))))

    (: bind-locals
       (impl
        (Fn Expanding Site (List Identifier) -> (Result (Pair Bound Expanding) (List Feedback)))))
    (define (bind-locals state site identifiers)
      (expanding-let* ((locals state (expanding-map state fresh-local identifiers)))
        (Ok (Pair (Bound (bound-site site identifiers locals) locals) state))))

    (: fresh-local
       (impl (Fn Expanding Identifier -> (Result (Pair Local Expanding) (List Feedback)))))
    (define (fresh-local state identifier)
      (expanding-let* ((number state (fresh state)))
        (Ok (Pair (Local (::name identifier) number) state))))

    (: identifier-in (impl (Fn Marked String -> (Result Identifier (List Feedback)))))
    (define (identifier-in syntax message)
      (match syntax
        ((Ident identifier _) (Ok identifier))
        (_ (fail (marked-loc syntax) message))))

    ;; ---- Heads ----

    ;; `syntax` with each macro at its head used, until its head is none.
    (: expand-head
       (impl (Fn Expanding Site Marked -> (Result (Pair Marked Expanding) (List Feedback)))))
    (define (expand-head state site syntax)
      (match (resolved-macro (head-resolution (::scopes site) (::env site) syntax))
        ((Some found)
         (expanding-let* ((number state (fresh state))
                          (written state (unchanged state (macro-use (::scopes site)
                                                                     (::env site)
                                                                     found
                                                                     (form-tail syntax)
                                                                     (marked-loc syntax)
                                                                     number))))
           (expand-head state site written)))
        ((None) (Ok (Pair syntax state)))))

    (: form-tail (impl (Fn Marked -> (List Marked))))
    (define (form-tail syntax)
      (match syntax
        ((Form (Cons _ rest) _) rest)
        (_ (Nil))))

    ;; ---- Expressions ----

    (: expand-expression
       (impl (Fn Expanding Site Marked -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (expand-expression state site syntax)
      (expanding-let* ((expanded state (expand-head state site syntax)))
        (match expanded
          ((Atom datum loc) (Ok (Pair (Literal (datum-constant datum) loc) state)))
          ((Ident identifier loc) (unchanged state (reference site identifier loc)))
          ((Form (Nil) loc) (fail loc "empty application"))
          ((Form (Cons (Ident identifier head-loc) (Cons argument (Nil))) loc)
           (match (field-path (::name identifier))
             ((PathLabels labels) (path-application state site labels argument loc))
             ((EmptyLabel message) (fail loc message))
             ((NotAPath) (application state site (Ident identifier head-loc) (list argument) loc))))
          ((Form (Cons head arguments) loc) (application state site head arguments loc)))))

    (: datum-constant (impl (Fn syntax-Datum -> Constant)))
    (define (datum-constant datum)
      (match datum
        ((syntax-Integer integer) (Integer integer))
        ((syntax-Float text) (Float text))
        ((syntax-Text text) (Text text))
        ((syntax-Character character) (Character character))
        ((syntax-ByteVector bytes) (ByteVector bytes))
        ((syntax-Boolean boolean) (Boolean boolean))))

    ;; ---- References ----

    ;; An identifier `::a::b` is a path by its name, whatever binds it.
    (: reference (impl (Fn Site Identifier Loc -> (Result Expr (List Feedback)))))
    (define (reference site identifier loc)
      (match (field-path (::name identifier))
        ((PathLabels labels) (Ok (Path labels loc)))
        ((EmptyLabel message) (fail loc message))
        ((NotAPath)
         (resolved-reference (resolve (::scopes site) (::env site) identifier) identifier loc))))

    ;; A value, or a struct, whose name is its constructor.
    (: resolved-reference (impl (Fn Resolution Identifier Loc -> (Result Expr (List Feedback)))))
    (define (resolved-reference resolution identifier loc)
      (let ((name (::name identifier)))
        (match resolution
          ((BoundLocally (LocalValue local) _) (Ok (LocalRef local loc)))
          ((BoundAtTop (Value value)) (Ok (TopRef value loc)))
          ((BoundAtTop (TypeName global #t)) (Ok (TopRef (TopGlobal global) loc)))
          ((BoundAtTop (TypeName _ #f)) (fail loc (string-append "a type is not a value: " name)))
          ((BoundAtTop (ReservedAccessor)) (fail loc field-read-message))
          ((Unbound) (fail loc (string-append "unbound identifier " name)))
          (_ (fail loc (string-append "syntax used as a value: " name))))))

    (: field-read-message String)
    (define field-read-message
      "a struct's field is read by path, (::field s), not through an accessor")

    ;; ---- Applications ----

    ;; `(::a::b value)` is the chain of reads itself, not a call.
    (: path-application
       (impl (Fn Expanding
                 Site
                 (List String)
                 Marked
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (path-application state site labels argument loc)
      (expanding-let* ((record state (expand-expression state site argument)))
        (Ok (Pair (PathApply labels record loc) state))))

    ;; A core form, or a call: the callee, then each argument in order.
    (: application
       (impl (Fn Expanding
                 Site
                 Marked
                 (List Marked)
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (application state site head arguments loc)
      (match (head-meaning site head)
        ((BoundAtTop (Keyword keyword)) (core state site keyword (Cons head arguments) loc))
        ((BoundAtTop (ReservedAccessor)) (fail loc field-read-message))
        (_
         (expanding-let* ((callee state (expand-expression state site head))
                          (expanded state
                                    (expanding-map state
                                                   (lambda (state argument)
                                                     (expand-expression state site argument))
                                                   arguments)))
           (Ok (Pair (Call callee expanded loc) state))))))

    ;; What the identifier at a form's head means, if one is there.
    (: head-meaning (impl (Fn Site Marked -> Resolution)))
    (define (head-meaning site head)
      (match head
        ((Ident identifier _) (resolve (::scopes site) (::env site) identifier))
        (_ (Unbound))))

    ;; ---- Core forms ----

    (: core
       (impl (Fn Expanding
                 Site
                 String
                 (List Marked)
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (core state site keyword items loc)
      (match (core-form keyword items)
        ((FunctionForm captures? parameters body)
         (function-form state site captures? parameters body loc))
        ((IfForm test consequent alternative)
         (conditional state site test consequent alternative loc))
        ((WithInstancesForm sets body) (with-instances state site sets body loc))
        ((BeginForm body) (expand-body state site body loc))
        ((NamedLetForm name bindings body) (named-let state site name bindings body loc))
        ((PlainLetForm bindings body) (plain-let state site bindings body loc))
        ((MatchForm scrutinee clauses) (match-expression state site scrutinee clauses loc))
        ((ArtifactFilesForm target file prepend empty)
         (artifact-files state site target file prepend empty loc))
        ((LinkHandleForm path path-loc) (unchanged state (linked-file path path-loc loc)))
        ((TypedForm kind value type) (typed state site kind value type loc))
        ((HandleForm effect implementations body)
         (handler state site effect implementations body loc))
        ((CaseIdForm constructor) (unchanged state (case-id site constructor loc)))
        ((QuoteForm datum) (Ok (Pair (Literal (datum-constant datum) loc) state)))
        ((MalformedForm message) (fail loc message))))

    ;; ---- Functions ----

    ;; `(lambda (parameter ...) body ...)`, and `fn`'s, which captures
    ;; nothing.
    (: function-form
       (impl (Fn Expanding
                 Site
                 Bool
                 Marked
                 (List Marked)
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (function-form state site captures? parameters body loc)
      (match parameters
        ((Form items _) (function-of state site captures? items body loc))
        (_ (fail (marked-loc parameters) "expected a parameter list"))))

    ;; A function whose parameters are `parameters`, each a variable.
    (: function-of
       (impl (Fn Expanding Site Bool (List Marked) (List Marked) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (function-of state site captures? parameters body loc)
      (expanding-let* ((names state (unchanged state (variables parameters))))
        (expand-function state site captures? names body loc)))

    (: variables (impl (Fn (List Marked) -> (Result (List Identifier) (List Feedback)))))
    (define (variables parameters)
      (map-results (lambda (parameter) (identifier-in parameter "expected a variable name"))
                   parameters))

    ;; Each name bound to a fresh local over the body.
    (: expand-function
       (impl (Fn Expanding Site Bool (List Identifier) (List Marked) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (expand-function state site captures? names body loc)
      (expanding-let* ((bound state (bind-locals state site names))
                       (value state (expand-body state (::site bound) body loc)))
        (Ok (Pair (if captures?
                      (Lambda (::locals bound) value loc)
                      (ClosedLambda (::locals bound) value loc))
                  state))))

    ;; ---- Conditionals ----

    ;; An `if` without an alternative has the unit value there.
    (: conditional
       (impl (Fn Expanding Site Marked Marked (Option Marked) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (conditional state site test consequent alternative loc)
      (expanding-let* ((tested state (expand-expression state site test))
                       (then-value state (expand-expression state site consequent))
                       (else-value state (alternative-of state site alternative loc)))
        (Ok (Pair (If tested then-value else-value loc) state))))

    (: alternative-of
       (impl
        (Fn Expanding Site (Option Marked) Loc -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (alternative-of state site alternative loc)
      (match alternative
        ((Some syntax) (expand-expression state site syntax))
        ((None) (Ok (Pair (Literal (UnitValue) loc) state)))))

    ;; ---- Instance sets ----

    ;; `(with-instances (set ...) body ...)`. The body is expanded first;
    ;; then the sets are resolved where the form is written, and so again
    ;; are those of each `with-instances` around it, innermost first, as
    ;; the old expander resolves them each time a body ends. A set written
    ;; twice is in scope once.
    (: with-instances
       (impl (Fn Expanding
                 Site
                 Marked
                 (List Marked)
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (with-instances state site sets body loc)
      (match sets
        ((Form items _)
         (let* ((written (WrittenSets items (::env site)))
                (inner (Site (::scopes site) (::env site) (Cons written (::instance-sets site)))))
           (expanding-let* ((value state (expand-body state inner body loc))
                            (sets state (unchanged state (active-sets (::scopes site)
                                                                      written
                                                                      (::instance-sets site)))))
             (Ok (Pair (WithInstances sets value loc) state)))))
        (_ (fail (marked-loc sets) "expected a list of instance sets"))))

    ;; The sets `written` names, once each, once those of each enclosing
    ;; `with-instances` are resolved too.
    (: active-sets
       (impl (Fn Scopes WrittenSets (List WrittenSets) -> (Result (List Global) (List Feedback)))))
    (define (active-sets scopes written enclosing)
      (result-let* ((own (instance-sets scopes written))
                    (outer (map-results (lambda (sets) (instance-sets scopes sets)) enclosing)))
        (Ok (delete-duplicates same-global? own))))

    (: instance-sets (impl (Fn Scopes WrittenSets -> (Result (List Global) (List Feedback)))))
    (define (instance-sets scopes written)
      (map-results (lambda (syntax) (instance-set scopes (::env written) syntax)) (::sets written)))

    (: instance-set (impl (Fn Scopes Env Marked -> (Result Global (List Feedback)))))
    (define (instance-set scopes env syntax)
      (match syntax
        ((Ident identifier loc)
         (match (resolve scopes env identifier)
           ((BoundAtTop (InstanceSetName global)) (Ok global))
           (_ (fail loc "not an instance set"))))
        (_ (fail (marked-loc syntax) "expected an instance set"))))

    ;; ---- Lets ----

    ;; `(let name ((variable value) ...) body ...)`, a loop: the
    ;; variables' names are checked, then the loop's body is expanded,
    ;; where `name` is the loop, then the values, where it is not.
    (: named-let
       (impl (Fn Expanding Site Identifier Marked (List Marked) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (named-let state site name bindings body loc)
      (match bindings
        ((Form items _)
         (expanding-let* ((names state (unchanged state (map-results binding-name items)))
                          (loop state (fresh-local state name))
                          (function state
                                    (expand-function state (bound-site site (list name) (list loop))
                                                     #t
                                                     names
                                                     body
                                                     loc))
                          (initial state (expanding-map state (lambda (state binding)
                                                                (binding-value state site binding))
                                                        items)))
           (Ok (Pair
                (Let loop (None) function (Call (LocalRef loop loc) initial loc) loc)
                state))))
        (_ (fail (marked-loc bindings) "expected a list of bindings"))))

    ;; `(let ((variable value) ...) body ...)`: the values, where no
    ;; variable is bound, then the names, then the body.
    (: plain-let
       (impl (Fn Expanding
                 Site
                 (List Marked)
                 (List Marked)
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (plain-let state site bindings body loc)
      (expanding-let* ((initial state
                                (expanding-map state
                                               (lambda (state binding)
                                                 (binding-value state site binding))
                                               bindings))
                       (names state (unchanged state (map-results binding-name bindings)))
                       (bound state (bind-locals state site names))
                       (value state (expand-body state (::site bound) body loc)))
        (Ok
         (Pair (fold-right (lambda (pair rest) (Let (::first pair) (None) (::second pair) rest loc))
                           value
                           (zip (::locals bound) initial))
               state))))

    (: binding-name (impl (Fn Marked -> (Result Identifier (List Feedback)))))
    (define (binding-name binding)
      (match binding
        ((Form (Cons name _) _) (identifier-in name "expected a binding name"))
        ((Form (Nil) loc) (fail loc "expected (name value)"))
        (_ (fail (marked-loc binding) "expected a (name value) binding"))))

    (: binding-value
       (impl (Fn Expanding Site Marked -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (binding-value state site binding)
      (match binding
        ((Form (Cons _ (Cons value (Nil))) _) (expand-expression state site value))
        (_ (fail (marked-loc binding) "expected (name value)"))))

    ;; ---- Matches ----

    (: match-expression
       (impl (Fn Expanding
                 Site
                 Marked
                 (List Marked)
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (match-expression state site scrutinee clauses loc)
      (expanding-let* ((value state (expand-expression state site scrutinee))
                       (expanded state (expanding-map state
                                                      (lambda (state clause)
                                                        (match-clause state site clause))
                                                      clauses)))
        (Ok (Pair (Match value expanded loc) state))))

    ;; `(pattern body ...)`: its pattern, which binds its variables, the
    ;; last innermost, then its body.
    (: match-clause
       (impl (Fn Expanding Site Marked -> (Result (Pair Clause Expanding) (List Feedback)))))
    (define (match-clause state site clause)
      (match clause
        ((Form (Cons pattern body) loc)
         (expanding-let* ((expanded state
                                    (expand-pattern state (::scopes site) (::env site) pattern))
                          (value state (expand-body state
                                                    (framed-site site
                                                                 (append
                                                                  (reverse (::frames expanded))
                                                                  (::frames (::env site))))
                                                    body
                                                    loc)))
           (Ok (Pair (Clause (::pattern expanded) value loc) state))))
        ((Form (Nil) loc) (fail loc "expected (pattern body ...)"))
        (_ (fail (marked-loc clause) "expected a match clause"))))

    ;; ---- Files ----

    ;; `(artifact-files "target" file prepend empty)`. The old expander
    ;; expands the three as the list it builds of the target's files, so
    ;; `empty` alone for a target with none; here each is expanded once, in
    ;; order. The only use, `artifact-bundle`'s, writes a constructor and
    ;; the list constructors, which expand without failing either way.
    (: artifact-files
       (impl (Fn Expanding Site String Marked Marked Marked Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (artifact-files state site target file prepend empty loc)
      (expanding-let* ((file-value state (expand-expression state site file))
                       (prepend-value state (expand-expression state site prepend))
                       (empty-value state (expand-expression state site empty)))
        (Ok (Pair (ArtifactFiles target file-value prepend-value empty-value loc)
                  state))))

    ;; `(link-handle "path")`, the path's canonical names, beside the file
    ;; the path is written in.
    (: linked-file (impl (Fn String Loc Loc -> (Result Expr (List Feedback)))))
    (define (linked-file path path-loc loc)
      (match (linked-path path)
        ((LinkedNames names) (Ok (LinkedFile names path-loc loc)))
        ((UnlinkablePath message) (fail path-loc message))))

    ;; ---- Types in expressions ----

    ;; The value, then the type.
    (: typed
       (impl (Fn Expanding
                 Site
                 TypedKind
                 Marked
                 Marked
                 Loc
                 ->
                 (Result (Pair Expr Expanding) (List Feedback)))))
    (define (typed state site kind value type loc)
      (expanding-let* ((expanded state (expand-expression state site value))
                       (written state
                                (unchanged state (expand-type (::scopes site) (::env site) type))))
        (Ok (Pair (match kind
                    ((Annotated) (Ann expanded written loc))
                    ((Converted) (Convert expanded written loc))
                    ((TryConverted) (TryConvert expanded written loc))
                    ((TypeTested) (TypeTest expanded written loc)))
                  state))))

    ;; `(case-id Constructor)`.
    (: case-id (impl (Fn Site Marked Loc -> (Result Expr (List Feedback)))))
    (define (case-id site constructor loc)
      (result-let* ((value (constructor-of (::scopes site) (::env site) constructor)))
        (Ok (CaseId value (marked-loc constructor) loc))))

    ;; ---- Handlers ----

    ;; `(handle Effect ((operation implementation) ...) body ...)`: the
    ;; effect, each clause, then the body. The builtin effects have no
    ;; operations.
    (: handler
       (impl (Fn Expanding Site Marked (List Marked) (List Marked) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (handler state site effect implementations body loc)
      (expanding-let* ((global state (unchanged state (handled-effect site effect)))
                       (expanded state (expanding-map state (lambda (state implementation)
                                                              (handler-clause state
                                                                              site
                                                                              implementation))
                                                      implementations))
                       (value state (expand-body state site body loc)))
        (Ok (Pair (Handle global expanded value loc) state))))

    (: handled-effect (impl (Fn Site Marked -> (Result Global (List Feedback)))))
    (define (handled-effect site effect)
      (match effect
        ((Ident identifier loc)
         (match (resolve (::scopes site) (::env site) identifier)
           ((BoundAtTop (EffectName global))
            (if (same-library? (::library global) forms-library)
                (fail loc
                      (string-append "the builtin effect "
                                     (::name global)
                                     " has no operations to handle"))
                (Ok global)))
           (_ (fail loc (string-append "not an effect: " (::name identifier))))))
        (_ (fail (marked-loc effect) "expected an effect name"))))

    ;; `(operation implementation)`. The old expander finds the effect's
    ;; operation before it expands the implementation; `declare`, which
    ;; has the effect's operations, finds it from the label, so a clause
    ;; naming none whose implementation fails is told of the failure.
    (: handler-clause
       (impl
        (Fn Expanding Site Marked -> (Result (Pair Implementation Expanding) (List Feedback)))))
    (define (handler-clause state site implementation)
      (match implementation
        ((Form (Cons (Ident identifier name-loc) (Cons value (Nil))) loc)
         (expanding-let* ((expanded state (expand-expression state site value)))
           (Ok
            (Pair (Implementation (Label (::name identifier) name-loc) expanded loc)
                  state))))
        ((Form (Cons name (Cons _ (Nil))) _) (fail (marked-loc name) "expected an operation name"))
        (_ (fail (marked-loc implementation) "expected (operation implementation)"))))

    ;; ---- Bodies ----

    (: expand-body
       (impl
        (Fn Expanding Site (List Marked) Loc -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (expand-body state site forms loc)
      (if (null? forms)
          (fail loc "empty body")
          (body-forms state site forms (None) loc)))

    ;; A local signature, waiting for the definition after it.
    (struct Pending
      ((name String)
       (scheme Scheme)
       (loc Loc)))

    ;; The forms of a body from `forms` on, each with its head expanded.
    ;; `begin` splices its forms in, and a signature waits across it and
    ;; across a macro's definition.
    (: body-forms
       (impl (Fn Expanding Site (List Marked) (Option Pending) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (body-forms state site forms pending loc)
      (match forms
        ((Nil) (fail loc "a body must end with an expression"))
        ((Cons form rest)
         (expanding-let* ((expanded state (expand-head state site form)))
           (match (head-resolution (::scopes site) (::env site) expanded)
             ((BoundAtTop (Keyword "begin"))
              (body-forms state site (append (form-tail expanded) rest) pending loc))
             ((BoundAtTop (Keyword "define-syntax"))
              (local-macro state site expanded rest pending loc))
             ((BoundAtTop (Keyword ":"))
              (local-signature state site expanded rest pending loc))
             ((BoundAtTop (Keyword "define"))
              (local-definition state site expanded rest pending loc))
             (_ (body-expression state site expanded rest pending loc)))))))

    ;; A macro a body defines is the frame binding its name, which is its
    ;; home, so its template may use it.
    (: local-macro
       (impl (Fn Expanding Site Marked (List Marked) (Option Pending) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (local-macro state site form rest pending loc)
      (expanding-let* ((parts state (unchanged state (macro-definition form)))
                       (number state (fresh state)))
        (let ((macro (Macro (MacroId (::library (::scopes site)) number)
                            (::literals parts)
                            (::rules parts))))
          (body-forms state
                      (framed-site site
                                   (Cons (Frame (::name parts) (LocalMacro macro))
                                         (::frames (::env site))))
                      rest
                      pending
                      loc))))

    ;; `(: name type)` waits for the next definition; a signature waiting
    ;; already annotates no definition.
    (: local-signature
       (impl (Fn Expanding Site Marked (List Marked) (Option Pending) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (local-signature state site form rest pending loc)
      (match (signature-shape form)
        ((SignatureForm name _ type)
         (expanding-let* ((scheme state
                                  (unchanged state
                                             (expand-scheme (::scopes site) (::env site) type)))
                          (body state
                                (body-forms state
                                            site
                                            rest
                                            (Some (Pending (::name name) scheme (marked-loc form)))
                                            loc)))
           (Ok (Pair (dropped pending body) state))))
        ((MalformedSignature place message) (fail place message))))

    ;; A definition binds a fresh local over the rest of the body; a
    ;; function sees itself, and a value does not. The signature waiting
    ;; annotates it if it names it.
    (: local-definition
       (impl (Fn Expanding Site Marked (List Marked) (Option Pending) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (local-definition state site form rest pending loc)
      (match (definition-shape form)
        ((NamedDefinition name _ defined)
         (expanding-let* ((local state (fresh-local state name)))
           (let ((inner (bound-site site (list name) (list local))))
             (expanding-let* ((value state
                                     (defined-value state
                                       (if (function-definition? site defined) inner site)
                                       defined
                                       (marked-loc form)))
                              (body state (body-forms state inner rest (None) loc)))
               (Ok (Pair (dropped (unsigned (::name name) pending)
                                  (Let local
                                       (signed (::name name) pending)
                                       value
                                       body
                                       (marked-loc form)))
                         state))))))
        ((MalformedDefinition place message) (fail place message))))

    ;; A definition is a function's when it is written `(define (name
    ;; parameter ...) body ...)` or its value is a `lambda` or `fn` form.
    (: function-definition? (impl (Fn Site DefinedValue -> Bool)))
    (define (function-definition? site defined)
      (match defined
        ((FunctionValue _ _) #t)
        ((ExpressionValue syntax)
         (match (head-resolution (::scopes site) (::env site) syntax)
           ((BoundAtTop (Keyword "lambda")) #t)
           ((BoundAtTop (Keyword "fn")) #t)
           (_ #f)))))

    (: defined-value
       (impl
        (Fn Expanding Site DefinedValue Loc -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (defined-value state site defined loc)
      (match defined
        ((FunctionValue parameters body) (function-of state site #t parameters body loc))
        ((ExpressionValue syntax) (expand-expression state site syntax))))

    ;; An expression is the body's value when it is last, and else is done
    ;; before the rest of the body.
    (: body-expression
       (impl (Fn Expanding Site Marked (List Marked) (Option Pending) Loc
                 -> (Result (Pair Expr Expanding) (List Feedback)))))
    (define (body-expression state site form rest pending loc)
      (expanding-let* ((value state (expand-expression state site form)))
        (if (null? rest)
            (Ok (Pair (dropped pending value) state))
            (expanding-let* ((more state (body-forms state site rest (None) loc)))
              (Ok
               (Pair (dropped pending (Seq value more (expr-loc value)))
                     state))))))

    ;; ---- Signatures ----

    ;; The signature waiting, when it names `name`.
    (: signed (impl (Fn String (Option Pending) -> (Option Scheme))))
    (define (signed name pending)
      (match pending
        ((Some found) (if (string=? (::name found) name) (Some (::scheme found)) (None)))
        ((None) (None))))

    ;; The signature waiting, when it names another.
    (: unsigned (impl (Fn String (Option Pending) -> (Option Pending))))
    (define (unsigned name pending)
      (match pending
        ((Some found) (if (string=? (::name found) name) (None) pending))
        ((None) (None))))

    ;; `body` under a signature that annotates no definition, whose type is
    ;; still checked.
    (: dropped (impl (Fn (Option Pending) Expr -> Expr)))
    (define (dropped pending body)
      (match pending
        ((Some found) (LocalSignature (::scheme found) body (::loc found)))
        ((None) body)))

    ;; ---- Places ----

    (: expr-loc (impl (Fn Expr -> Loc)))
    (define (expr-loc expr)
      (match expr
        ((Literal _ loc) loc)
        ((LocalRef _ loc) loc)
        ((TopRef _ loc) loc)
        ((Path _ loc) loc)
        ((PathApply _ _ loc) loc)
        ((Lambda _ _ loc) loc)
        ((ClosedLambda _ _ loc) loc)
        ((Call _ _ loc) loc)
        ((If _ _ _ loc) loc)
        ((Seq _ _ loc) loc)
        ((Let _ _ _ _ loc) loc)
        ((LocalSignature _ _ loc) loc)
        ((Match _ _ loc) loc)
        ((Handle _ _ _ loc) loc)
        ((WithInstances _ _ loc) loc)
        ((Ann _ _ loc) loc)
        ((Convert _ _ loc) loc)
        ((TryConvert _ _ loc) loc)
        ((TypeTest _ _ loc) loc)
        ((CaseId _ _ loc) loc)
        ((LinkedFile _ _ loc) loc)
        ((ArtifactFiles _ _ _ _ loc) loc)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-expressions)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail core table)
     (snail stage0 testing))
    (begin
      (define (test-expressions)
        (test-references)
        (test-applications)
        (test-functions)
        (test-conditionals)
        (test-instance-sets)
        (test-lets)
        (test-matches)
        (test-files)
        (test-typed)
        (test-handlers)
        (test-quotes)
        (test-macros)
        (test-bodies)
        (test-signatures))

      ;; ---- Helpers ----

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))

      (define main (list "main"))

      (define (marked datum)
        (marked-at loc datum))

      (define (marked-at here datum)
        (cond ((or (null? datum) (pair? datum))
               (Form (map (lambda (item) (marked-at here item)) datum) here))
              ((symbol? datum) (Ident (plain (symbol->string datum)) here))
              ((string? datum) (Atom (syntax-Text datum) here))
              ((exact-integer? datum) (Atom (syntax-Integer datum) here))
              ((boolean? datum) (Atom (syntax-Boolean datum) here))
              (else (panic "no syntax for this datum"))))

      (define (plain name)
        (Identifier name (Nil)))

      (define (global name)
        (Global main name 0))

      (define (bindings-of pairs)
        (fold-left (lambda (table pair)
                     (table-set table
                                (::first pair)
                                (append (match (table-ref table (::first pair))
                                          ((Some found) found)
                                          ((None) (list)))
                                        (list (Binding (plain (::first pair)) (::second pair))))))
                   empty-table
                   pairs))

      ;; (main) imports (snail core forms) and defines `f`, `Some`, the
      ;; struct Point, whose field `x` is read by path, the enum Shape, the
      ;; class Show, the effect `io`, the instance set Set, and `twice`,
      ;; which writes its argument twice in a `begin`.
      (define twice
        (Macro (MacroId main 1) (list) (list (marked '((_ e) (begin e e))))))

      (define scopes
        (Scopes main
                (TopScope (bindings-of (list (Pair "f" (Value (TopGlobal (global "f"))))
                                             (Pair "Some" (Value (TopGlobal (global "Some"))))
                                             (Pair "Point" (TypeName (global "Point") #t))
                                             (Pair "Point-x" (ReservedAccessor))
                                             (Pair "Shape" (TypeName (global "Shape") #f))
                                             (Pair "Show" (ClassName (global "Show")))
                                             (Pair "io" (EffectName (global "io")))
                                             (Pair "Set" (InstanceSetName (global "Set")))
                                             (Pair "twice" (MacroRules twice))))
                          (bindings-of
                           (map (lambda (export) (Pair (::name export) (::meaning export)))
                                (::exports forms-offer))))
                (list (Offered forms-library forms-offer))))

      (define site
        (Site scopes (Env (list) main) (list)))

      ;; What `datum` expands to, numbering from 10, and the next number.
      (define (expanded datum)
        (expand-expression (Expanding 10) site (marked datum)))

      (define (expression datum)
        (match (expanded datum)
          ((Ok (Pair value _)) (Ok value))
          ((Err feedback) (Err feedback))))

      (define (problem message)
        (fail loc message))

      (define (top name)
        (TopRef (TopGlobal (global name)) loc))

      (define (lit integer)
        (Literal (Integer integer) loc))

      (define (local name number)
        (Local name number))

      (define (ref name number)
        (LocalRef (Local name number) loc))

      (define i64
        (Applied (Global forms-library "I64" 0) "I64" (list) loc))

      ;; ---- Cases ----

      ;; A value, or a struct as its constructor; a path by its name.
      (define (test-references)
        (expect (expanded 5) (Ok (Pair (lit 5) (Expanding 10))))
        (expect (expression #t) (Ok (Literal (Boolean #t) loc)))
        (expect (expression 'f) (Ok (top "f")))
        (expect (expression 'Point) (Ok (top "Point")))
        (expect (expression 'Shape) (problem "a type is not a value: Shape"))
        (expect (expression 'Point-x)
                (problem "a struct's field is read by path, (::field s), not through an accessor"))
        (expect (expression 'missing) (problem "unbound identifier missing"))
        (expect (expression 'Show) (problem "syntax used as a value: Show"))
        (expect (expression 'if) (problem "syntax used as a value: if"))
        (expect (expression 'twice) (problem "syntax used as a value: twice"))
        (expect (expression '::a::b) (Ok (Path (list "a" "b") loc)))
        (expect (expression '::a::) (problem "empty field label in ::a::"))
        (expect (expression '::) (problem "unbound identifier ::")))

      (define (test-applications)
        (expect (expression '(f 1 f)) (Ok (Call (top "f") (list (lit 1) (top "f")) loc)))
        (expect (expression '(::a f)) (Ok (PathApply (list "a") (top "f") loc)))
        (expect (expression '(::a::b (f)))
                (Ok (PathApply (list "a" "b") (Call (top "f") (list) loc) loc)))
        (expect (expression '(::a f f))
                (Ok (Call (Path (list "a") loc) (list (top "f") (top "f")) loc)))
        (expect (expand-expression (Expanding 0)
                                   site
                                   (Form (list (Ident (plain "::a::") (at 2)) (marked 'f)) (at 3)))
                (fail (at 3) "empty field label in ::a::"))
        (expect (expression '()) (problem "empty application"))
        (expect (expression '(Point-x f))
                (problem "a struct's field is read by path, (::field s), not through an accessor"))
        (expect (expression '(missing f)) (problem "unbound identifier missing"))
        (expect (expression '(define x 1))
                (problem "this form is only valid as a definition: define"))
        (expect (expression '(syntax-rules ()))
                (problem "this form is only valid as a definition: syntax-rules")))

      ;; Parameters are fresh locals, the last innermost.
      (define (test-functions)
        (expect (expanded '(lambda (x y) x))
                (Ok (Pair (Lambda (list (local "x" 10) (local "y" 11)) (ref "x" 10) loc)
                          (Expanding 12))))
        (expect (expression '(fn (x x) x))
                (Ok (ClosedLambda (list (local "x" 10) (local "x" 11)) (ref "x" 11) loc)))
        (expect (expression '(lambda () f)) (Ok (Lambda (list) (top "f") loc)))
        (expect (expression '(lambda x x)) (problem "expected a parameter list"))
        (expect (expression '(lambda (x 1) x)) (problem "expected a variable name"))
        (expect (expression '(lambda (x))) (problem "empty body"))
        (expect (expression '(lambda)) (problem "expected (lambda (parameter ...) body ...)"))
        (expect (expression '(fn)) (problem "expected (fn (parameter ...) body ...)")))

      (define (test-conditionals)
        (expect (expression '(if f 1 2)) (Ok (If (top "f") (lit 1) (lit 2) loc)))
        (expect (expand-expression (Expanding 0)
                                   site
                                   (Form (list (marked 'if) (marked 'f) (marked 1)) (at 4)))
                (Ok
                 (Pair (If (top "f") (lit 1) (Literal (UnitValue) (at 4)) (at 4)) (Expanding 0))))
        (expect (expression '(if f)) (problem "expected (if test then [else])"))
        (expect (expression '(if missing 1 also-missing)) (problem "unbound identifier missing")))

      ;; The body comes before the sets, and an inner form's end resolves
      ;; the sets around it too.
      (define (test-instance-sets)
        (expect (expression '(with-instances (Set Set) f))
                (Ok (WithInstances (list (global "Set")) (top "f") loc)))
        (expect (expression '(with-instances () f)) (Ok (WithInstances (list) (top "f") loc)))
        (expect (expression '(with-instances (f) 1)) (problem "not an instance set"))
        (expect (expression '(with-instances (1) 1)) (problem "expected an instance set"))
        (expect (expression '(with-instances Set 1)) (problem "expected a list of instance sets"))
        (expect (expression '(with-instances (f) missing)) (problem "unbound identifier missing"))
        (expect (expression '(with-instances (f) (with-instances (Set) 1) missing))
                (problem "not an instance set"))
        (expect (expression '(with-instances (Set))) (problem "empty body"))
        (expect (expression '(with-instances))
                (problem "expected (with-instances (set ...) body ...)")))

      (define (test-lets)
        (expect (expanded '(let ((x 1) (y f)) y))
                (Ok (Pair (Let (local "x" 10)
                               (None)
                               (lit 1)
                               (Let (local "y" 11) (None) (top "f") (ref "y" 11) loc)
                               loc)
                          (Expanding 12))))
        (expect (expression '(let ((x 1)) (let ((x x)) x)))
                (Ok (Let (local "x" 10)
                         (None)
                         (lit 1)
                         (Let (local "x" 11) (None) (ref "x" 10) (ref "x" 11) loc)
                         loc)))
        (expect (expression '(let ((x x)) 1)) (problem "unbound identifier x"))
        (expect (expression '(let () 1)) (Ok (lit 1)))
        (expect (expression '(let loop ((i 1)) (loop i)))
                (Ok (Let (local "loop" 10)
                         (None)
                         (Lambda (list (local "i" 11))
                                 (Call (ref "loop" 10) (list (ref "i" 11)) loc)
                                 loc)
                         (Call (ref "loop" 10) (list (lit 1)) loc)
                         loc)))
        (expect (expression '(let loop ((i loop)) i)) (problem "unbound identifier loop"))
        (expect (expression '(let loop ((i missing) 1) i))
                (problem "expected a (name value) binding"))
        (expect (expression '(let loop ((i 1 2)) missing)) (problem "unbound identifier missing"))
        (expect (expression '(let loop ((i 1 2)) i)) (problem "expected (name value)"))
        (expect (expression '(let loop x i)) (problem "expected a list of bindings"))
        (expect (expression '(let loop (()) i)) (problem "expected (name value)"))
        (expect (expression '(let ((1 2)) 1)) (problem "expected a binding name"))
        (expect (expression '(let ((1 missing)) 1)) (problem "unbound identifier missing"))
        (expect (expression '(let (()) 1)) (problem "expected (name value)"))
        (expect (expression '(let ((x)) 1)) (problem "expected (name value)"))
        (expect (expression '(let (x) 1)) (problem "expected (name value)"))
        (expect (expression '(let ((x 1)))) (problem "expected (let ((name value) ...) body ...)"))
        (expect (expression '(let)) (problem "expected (let ((name value) ...) body ...)")))

      ;; A clause binds its variables over its body.
      (define (test-matches)
        (expect (expression '(match f ((Some x) x) (_ 1)))
                (Ok (Match (top "f")
                           (list (Clause (Destructure (TopGlobal (global "Some"))
                                                      (list (Bind (local "x" 10) loc))
                                                      loc)
                                         (ref "x" 10)
                                         loc)
                                 (Clause (Wild loc) (lit 1) loc))
                           loc)))
        (expect (expression '(match f)) (Ok (Match (top "f") (list) loc)))
        (expect (expression '(match f (x 1 x)))
                (Ok (Match (top "f")
                           (list
                            (Clause (Bind (local "x" 10) loc) (Seq (lit 1) (ref "x" 10) loc) loc))
                           loc)))
        (expect (expression '(match f ((Some x x) 1))) (problem "pattern variable bound twice: x"))
        (expect (expression '(match f ((Missing x) 1))) (problem "not a constructor: Missing"))
        (expect (expression '(match f 1)) (problem "expected a match clause"))
        (expect (expression '(match f ())) (problem "expected (pattern body ...)"))
        (expect (expression '(match f (x))) (problem "empty body"))
        (expect (expression '(match missing (x 1))) (problem "unbound identifier missing"))
        (expect (expression '(match)) (problem "expected (match expression clause ...)")))

      ;; A linked file's path is canonical, and refused at the path. An
      ;; artifact's three expressions are each expanded once, in order.
      (define (test-files)
        (expect (expression '(artifact-files "site" f Some f))
                (Ok (ArtifactFiles "site" (top "f") (top "Some") (top "f") loc)))
        (expect (expression '(artifact-files site f f f))
                (problem "artifact-bundle expects a literal target name"))
        (expect (expression '(link-handle "data/../x.png"))
                (Ok (LinkedFile (list "x.png") loc loc)))
        (expect (expand-expression (Expanding 0)
                                   site
                                   (Form
                                    (list (marked 'link-handle) (Atom (syntax-Text "../x") (at 5)))
                                    loc))
                (fail (at 5) "link-file may not leave the library's directory: ../x"))
        (expect (expression '(link-handle "a/..")) (problem "link-file names no file: a/.."))
        (expect (expression '(link-handle "/x"))
                (problem "link-file takes a path relative to the library, with no empty names: /x"))
        (expect (expression '(link-handle x))
                (problem "link-file expects a literal relative path")))

      ;; The value, then the type.
      (define (test-typed)
        (expect (expression '(ann f I64)) (Ok (Ann (top "f") i64 loc)))
        (expect (expression '(type-convert f I64)) (Ok (Convert (top "f") i64 loc)))
        (expect (expression '(try-convert f I64)) (Ok (TryConvert (top "f") i64 loc)))
        (expect (expression '(type-test f I64)) (Ok (TypeTest (top "f") i64 loc)))
        (expect (expression '(ann missing Missing)) (problem "unbound identifier missing"))
        (expect (expression '(ann f Missing)) (problem "not a type: Missing"))
        (expect (expression '(ann f)) (problem "expected (ann expression type)"))
        (expect (expression '(type-test f)) (problem "expected (type-test expression type)"))
        (expect (expression '(case-id Some)) (Ok (CaseId (TopGlobal (global "Some")) loc loc)))
        (expect (expression '(case-id Point)) (Ok (CaseId (TopGlobal (global "Point")) loc loc)))
        ;; Whether a value is a constructor is `declare`'s to decide.
        (expect (expression '(case-id f)) (Ok (CaseId (TopGlobal (global "f")) loc loc)))
        (expect (expression '(case-id Shape)) (problem "not a constructor: Shape"))
        (expect (expression '(case-id 1)) (problem "expected a constructor"))
        (expect (expression '(case-id)) (problem "expected (case-id Constructor)")))

      ;; The effect, each clause, then the body; an operation is a label,
      ;; which is not looked up here.
      (define (test-handlers)
        (expect (expression '(handle io ((read f)) 1))
                (Ok (Handle (global "io")
                            (list (Implementation (Label "read" loc) (top "f") loc))
                            (lit 1)
                            loc)))
        ;; The old expander said "not an operation of this effect:
        ;; anything" first, from the effect's declaration; `declare` does.
        (expect (expression '(handle io ((anything missing)) 1))
                (problem "unbound identifier missing"))
        (expect (expression '(handle mut () 1))
                (problem "the builtin effect mut has no operations to handle"))
        (expect (expression '(handle host () 1))
                (problem "the builtin effect host has no operations to handle"))
        (expect (expression '(handle f () 1)) (problem "not an effect: f"))
        (expect (expression '(handle 1 () 1)) (problem "expected an effect name"))
        (expect (expression '(handle io (read) 1)) (problem "expected (operation implementation)"))
        (expect (expression '(handle io ((read)) 1))
                (problem "expected (operation implementation)"))
        (expect (expression '(handle io ((1 f)) 1)) (problem "expected an operation name"))
        (expect (expression '(handle io ((read missing)) also-missing))
                (problem "unbound identifier missing"))
        (expect (expression '(handle io ())) (problem "empty body"))
        (expect (expression '(handle io read 1))
                (problem "expected (handle Effect ((operation implementation) ...) body ...)")))

      (define (test-quotes)
        (expect (expand-expression (Expanding 0)
                                   site
                                   (Form (list (marked 'quote) (Atom (syntax-Integer 5) (at 2)))
                                         (at 3)))
                (Ok (Pair (Literal (Integer 5) (at 3)) (Expanding 0))))
        (expect (expression '(quote x)) (problem "only literals can be quoted"))
        (expect (expression '(quote)) (problem "only literals can be quoted")))

      ;; A macro at a head is used until none is; a local macro's names
      ;; mean what they meant where it was defined.
      (define (test-macros)
        (expect (expanded '(twice f)) (Ok (Pair (Seq (top "f") (top "f") loc) (Expanding 11))))
        (expect (expression '(twice (twice f)))
                (Ok (Seq (top "f") (Seq (top "f") (Seq (top "f") (top "f") loc) loc) loc)))
        (expect (expression '(twice)) (problem "no syntax-rules pattern matches this use"))
        (expect (expanded '(begin (define-syntax m (syntax-rules () ((_) f))) (m)))
                (Ok (Pair (top "f") (Expanding 12))))
        (expect (expanded
                 '(lambda (f) (begin (define-syntax m (syntax-rules () ((_) f))) (lambda (f) (m)))))
                (Ok (Pair (Lambda (list (local "f" 10))
                                  (Lambda (list (local "f" 12)) (ref "f" 10) loc)
                                  loc)
                          (Expanding 14))))
        (expect (expression '(lambda () (define-syntax m) 1))
                (problem "expected (define-syntax name (syntax-rules (literal ...) rule ...))")))

      ;; Definitions bind over what follows; a function sees itself.
      (define (test-bodies)
        (expect (expression '(begin 1 2)) (Ok (Seq (lit 1) (lit 2) loc)))
        (expect (expand-expression (Expanding 0)
                                   site
                                   (Form (list (marked 'begin)
                                               (Atom (syntax-Integer 1) (at 2))
                                               (marked 2))
                                         (at 3)))
                (Ok (Pair (Seq (Literal (Integer 1) (at 2)) (lit 2) (at 2)) (Expanding 0))))
        (expect (expression '(begin (begin) 1)) (Ok (lit 1)))
        (expect (expression '(begin (begin 1 (define x 2)) x))
                (Ok (Seq (lit 1) (Let (local "x" 10) (None) (lit 2) (ref "x" 10) loc) loc)))
        (expect (expression '(begin)) (problem "empty body"))
        (expect (expression '(begin (define x 1) x))
                (Ok (Let (local "x" 10) (None) (lit 1) (ref "x" 10) loc)))
        (expect (expression '(begin (define (g) (g)) g))
                (Ok (Let (local "g" 10)
                         (None)
                         (Lambda (list) (Call (ref "g" 10) (list) loc) loc)
                         (ref "g" 10)
                         loc)))
        (expect (expression '(begin (define g (lambda () g)) g))
                (Ok (Let (local "g" 10) (None) (Lambda (list) (ref "g" 10) loc) (ref "g" 10) loc)))
        (expect (expression '(begin (define g (fn () g)) g))
                (Ok (Let (local "g" 10)
                         (None)
                         (ClosedLambda (list) (ref "g" 10) loc)
                         (ref "g" 10)
                         loc)))
        (expect (expression '(begin (define g g) g)) (problem "unbound identifier g"))
        (expect (expression '(begin (define (g x 1) x) g)) (problem "expected a variable name"))
        (expect (expression '(begin (define 1 2) 1)) (problem "expected a definition name"))
        (expect (expression '(begin (define x) 1))
                (problem "expected (define name value) or (define (name parameter ...) body ...)"))
        (expect (expression '(begin (define x 1))) (problem "a body must end with an expression")))

      ;; A signature annotates the definition after it that it names; one
      ;; that annotates none stays, to be checked.
      (define (test-signatures)
        (let ((scheme (Scheme (list) (list) i64 loc))
              (bool (Scheme (list)
                            (list)
                            (Applied (Global forms-library "Bool" 0) "Bool" (list) loc)
                            loc)))
          (expect (expression '(begin (: x I64) (define x 1) x))
                  (Ok (Let (local "x" 10) (Some scheme) (lit 1) (ref "x" 10) loc)))
          (expect (expression
                   '(begin (: x I64) (begin) (define-syntax m (syntax-rules ())) (define x 1) x))
                  (Ok (Let (local "x" 11) (Some scheme) (lit 1) (ref "x" 11) loc)))
          (expect (expression '(begin (: y I64) (define x 1) x))
                  (Ok (LocalSignature scheme
                                      (Let (local "x" 10) (None) (lit 1) (ref "x" 10) loc)
                                      loc)))
          (expect (expression '(begin (: x I64) 1)) (Ok (LocalSignature scheme (lit 1) loc)))
          (expect (expression '(begin (: x I64) 1 (define x 2) x))
                  (Ok (LocalSignature scheme
                                      (Seq (lit 1)
                                           (Let (local "x" 10) (None) (lit 2) (ref "x" 10) loc)
                                           loc)
                                      loc)))
          (expect (expression '(begin (: x I64) (: x Bool) (define x 1) x))
                  (Ok (LocalSignature scheme
                                      (Let (local "x" 10) (Some bool) (lit 1) (ref "x" 10) loc)
                                      loc)))
          (expect (expression '(begin (: x I64))) (problem "a body must end with an expression"))
          (expect (expression '(begin (: 1 I64) 1)) (problem "expected a name"))
          (expect (expression '(begin (: x) 1)) (problem "expected (: name type)"))
          (expect (expression '(begin (: x Missing) missing)) (problem "not a type: Missing"))))))
   (else)))
