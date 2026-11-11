;; The top level after the scan, in the old expander's three steps. Every
;; signature is expanded first, needing only the names the scan bound;
;; then each declaration, in order, becomes its node, with its types
;; expanded; and the first problem in either stops the library, since
;; the bodies need them. Then each body is expanded in order, a
;; definition's value, a statement, an expose, an instance's methods, an
;; effect's defaults and the sets of a `with-instances`: a body that
;; fails leaves the numbers as they were, and the bodies after it are
;; expanded all the same, so every body's feedback is returned, in order.
;;
;; What needs a declaration's content is left to `declare`: whether a
;; method or an operation a label names exists, how many types a class
;; takes, what a dispatch clause covers, whether a struct can be built,
;; and the rules of host functions and operation types. A program's
;; statements leave its tops to become its body.
(define-library (snail compiler expand declarations)
  (export
   checked-signatures
   declared-items
   Declared
   Bodies
   expanded-bodies)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler outline names) same-library?)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand scopes)
   (snail compiler expand state)
   (snail compiler expand paths)
   (snail compiler expand form-shapes)
   (snail compiler expand type-shapes)
   (snail compiler expand types)
   (snail compiler expand declaration-shapes)
   (snail compiler expand expressions)
   (snail compiler expand scan))
  (begin

    ;; ---- Answers ----

    (: refused (All (T) (impl (Fn (Result T Malformed) -> (Result T (List Feedback))))))
    (define (refused answer)
      (match answer
        ((Ok value) (Ok value))
        ((Err malformed) (fail (::loc malformed) (::message malformed)))))

    (: top-env (impl (Fn Scopes -> Env)))
    (define (top-env scopes)
      (Env (Nil) (::library scopes)))

    ;; ---- Signatures ----

    ;; Every signature in order, before any declaration.
    (: checked-signatures (impl (Fn Scopes (List Item) -> (Result Bool (List Feedback)))))
    (define (checked-signatures scopes items)
      (match items
        ((Nil) (Ok #t))
        ((Cons item rest)
         (result-let* ((checked (item-signatures scopes item))
                       (more (checked-signatures scopes rest)))
           (Ok #t)))))

    (: item-signatures (impl (Fn Scopes Item -> (Result Bool (List Feedback)))))
    (define (item-signatures scopes item)
      (match item
        ((PendingSignature shape annotations loc)
         (result-let* ((top (signature scopes shape annotations loc)))
           (Ok #t)))
        ((PendingScope _ inner _) (checked-signatures scopes inner))
        ((PendingSet _ inner _) (checked-signatures scopes inner))
        (_ (Ok #t))))

    ;; `(: name type)` names a top-level value, whichever declaration
    ;; binds it, imported or not.
    (: signature
       (impl (Fn Scopes SignatureShape (List Annotation) Loc -> (Result Top (List Feedback)))))
    (define (signature scopes shape annotations loc)
      (match shape
        ((SignatureForm name name-loc type)
         (match (resolve scopes (top-env scopes) name)
           ((BoundAtTop (Value target))
            (result-let* ((scheme (expand-scheme scopes (top-env scopes) type)))
              (Ok (Signature target scheme annotations loc))))
           (_
            (fail name-loc
                  (string-append "signature names an undefined top-level definition: "
                                 (::name name))))))
        ((MalformedSignature place message) (fail place message))))

    ;; ---- Declarations ----

    ;; What the second pass leaves for the bodies: a node that is done, or
    ;; one whose bodies are still syntax.
    (enum Declared
      (Done
       ((top Top)))
      (DynamicDone
       ((member SetMember)))
      (Defining
        ((global Global)
         (value DefinedValue)
         (loc Loc)))
      (Stating
       ((form Marked)))
      (Exposing
       ((shape (Result ExposeForm Malformed))))
      (Instancing
       ((instance Instance)
        (methods (List PendingMethod))))
      (Effecting
       ((effect Top)
        (defaults (List DefaultForm))))
      (Scoping
       ((sets (List Marked))
        (items (List Declared))
        (loc Loc)))
      (Setting
       ((global Global)
        (items (List Declared))
        (loc Loc))))

    ;; A method definition of an instance, whose value is still syntax.
    (struct PendingMethod
      ((name MethodName)
       (value DefinedValue)
       (loc Loc)))

    ;; Each item's node, in order; the first problem stops them. A
    ;; signature, checked already, is expanded again into its node.
    (: declared-items (impl (Fn Scopes (List Item) -> (Result (List Declared) (List Feedback)))))
    (define (declared-items scopes items)
      (map-results (lambda (item) (declared-item scopes item)) items))

    (: declared-item (impl (Fn Scopes Item -> (Result Declared (List Feedback)))))
    (define (declared-item scopes item)
      (match item
        ((PendingDefinition global value loc) (Ok (Defining global value loc)))
        ((PendingSignature shape annotations loc)
         (done (signature scopes shape annotations loc)))
        ((PendingStruct head fields derivations)
         (done (declared-struct scopes head fields derivations)))
        ((PendingEnum head cases derivations) (done (declared-enum scopes head cases derivations)))
        ((PendingAlias head) (done (declared-alias scopes head)))
        ((PendingClass head members) (done (declared-class scopes head members)))
        ((PendingInstance shape) (declared-instance scopes shape))
        ((PendingDynamic shape) (declared-dynamic scopes shape))
        ((PendingExtern head shape) (done (declared-extern scopes head shape)))
        ((PendingEffect head operations clauses) (declared-effect scopes head operations clauses))
        ((PendingExpose shape) (Ok (Exposing shape)))
        ((PendingStatement form) (Ok (Stating form)))
        ((PendingScope sets items loc)
         (result-let* ((inner (declared-items scopes items)))
           (Ok (Scoping sets inner loc))))
        ((PendingSet global items loc)
         (result-let* ((inner (declared-items scopes items)))
           (Ok (Setting global inner loc))))))

    (: done (impl (Fn (Result Top (List Feedback)) -> (Result Declared (List Feedback)))))
    (define (done top)
      (result-let* ((node top))
        (Ok (Done node))))

    ;; ---- Heads ----

    ;; A declaration's types are written over its parameters.
    (: head-env (impl (Fn Scopes Head -> Env)))
    (define (head-env scopes head)
      (with-variables (top-env scopes) (map ::identifier (::params head))))

    (: head-params (impl (Fn Head -> (List String))))
    (define (head-params head)
      (map (lambda (param) (::name (::identifier param))) (::params head)))

    (: head-global (impl (Fn Scopes Head -> Global)))
    (define (head-global scopes head)
      (top-global scopes (::identifier (::name head))))

    ;; ---- Structs and enums ----

    (: declared-struct
       (impl
        (Fn Scopes Head (List ScannedField) (List Derivation) -> (Result Top (List Feedback)))))
    (define (declared-struct scopes head fields derivations)
      (result-let* ((nodes (map-results (lambda (field)
                                          (field-node scopes (head-env scopes head) field))
                                        fields)))
        (Ok (Struct (head-global scopes head)
                    (head-params head)
                    nodes
                    derivations
                    (::annotations head)
                    (::loc (::name head))
                    (::loc head)))))

    (: declared-enum
       (impl (Fn Scopes Head (List ScannedCase) (List Derivation) -> (Result Top (List Feedback)))))
    (define (declared-enum scopes head cases derivations)
      (result-let* ((nodes
                     (map-results (lambda (case) (case-node scopes (head-env scopes head) case))
                                  cases)))
        (Ok (Enum (head-global scopes head)
                  (head-params head)
                  nodes
                  derivations
                  (::annotations head)
                  (::loc head)))))

    (: case-node (impl (Fn Scopes Env ScannedCase -> (Result Case (List Feedback)))))
    (define (case-node scopes env case)
      (result-let* ((fields
                     (map-results (lambda (field) (field-node scopes env field)) (::fields case))))
        (Ok (Case (top-global scopes (::identifier (::name case)))
                  (map (lambda (field)
                         (CaseField (::label field)
                                    (::type field)
                                    (::annotations field)
                                    (::loc field)))
                       fields)
                  (::annotations case)
                  (::loc (::name case))))))

    ;; A field's type is stored, so no callable in it is `impl`.
    (: field-node (impl (Fn Scopes Env ScannedField -> (Result Field (List Feedback)))))
    (define (field-node scopes env field)
      (result-let* ((type (expand-type scopes env (::type field)))
                    (stored (stored-type type (marked-loc (::type field)))))
        (Ok (Field (::name (::identifier (::label field)))
                   (::mutable? field)
                   type
                   (::annotations field)
                   (::loc (::label field))))))

    (: stored-type (impl (Fn TypeExpr Loc -> (Result TypeExpr (List Feedback)))))
    (define (stored-type type loc)
      (if (impl-callable? type)
          (fail loc
                "stored and returned callable types require explicit dyn; impl is a definition or argument contract")
          (Ok type)))

    ;; Whether an `impl` callable is the type or within it, where the old
    ;; expander looks: arguments, and the parameters and results of
    ;; callables and code. It looks at an alias's use as the type it
    ;; resolves to, its body with each parameter its argument, so an
    ;; argument the body does not use is not looked at.
    (: impl-callable? (impl (Fn TypeExpr -> Bool)))
    (define (impl-callable? type)
      (impl-within? (Nil) type))

    ;; `parameters` says of each parameter of the alias whose body `type`
    ;; is part of whether its argument holds an `impl` callable.
    (: impl-within? (impl (Fn (List Bool) TypeExpr -> Bool)))
    (define (impl-within? parameters type)
      (match type
        ((Callable (Impl) _ _ _) #t)
        ((Callable (Dyn) _ arrow _) (arrow-impl? parameters arrow))
        ((Applied _ _ arguments _)
         (any? (lambda (argument) (impl-within? parameters argument)) arguments))
        ((Code arrow _) (arrow-impl? parameters arrow))
        ((Aliased _ arguments body _)
         (impl-within? (map (lambda (argument) (impl-within? parameters argument)) arguments)
                       body))
        ;; An AliasParameter's index is below its alias's count of
        ;; arguments, which Expanded guarantees.
        ((AliasParameter index _) (list-ref parameters index))
        (_ #f)))

    (: arrow-impl? (impl (Fn (List Bool) Arrow -> Bool)))
    (define (arrow-impl? parameters arrow)
      (or (impl-within? parameters (::result arrow))
          (any? (lambda (parameter) (impl-within? parameters parameter)) (::parameters arrow))))

    ;; ---- Aliases and classes ----

    (: declared-alias (impl (Fn Scopes Head -> (Result Top (List Feedback)))))
    (define (declared-alias scopes head)
      (Ok (Alias (head-global scopes head) (head-params head) (::annotations head) (::loc head))))

    ;; A class's methods are written over its parameters and its
    ;; associated outputs.
    (: declared-class
       (impl (Fn Scopes Head (List ScannedMember) -> (Result Top (List Feedback)))))
    (define (declared-class scopes head members)
      (let ((env (with-variables (top-env scopes)
                                 (map ::identifier
                                      (append (::params head) (output-names members))))))
        (result-let* ((nodes
                       (map-results (lambda (member) (member-node scopes env member)) members)))
          (Ok (Class (head-global scopes head)
                     (head-params head)
                     nodes
                     (::annotations head)
                     (::loc head))))))

    (: output-names (impl (Fn (List ScannedMember) -> (List Named))))
    (define (output-names members)
      (match members
        ((Nil) (Nil))
        ((Cons (ScannedOutput output) rest) (Cons (::name output) (output-names rest)))
        ((Cons (ScannedMethod _) rest) (output-names rest))))

    (: member-node (impl (Fn Scopes Env ScannedMember -> (Result Member (List Feedback)))))
    (define (member-node scopes env member)
      (match member
        ((ScannedOutput output)
         (Ok
          (AssociatedOutput (Label (::name (::identifier (::name output))) (::loc (::name output)))
                            (::annotations output))))
        ((ScannedMethod method)
         (result-let* ((scheme (expand-scheme scopes env (::type method))))
           (Ok (MethodSignature (top-global scopes (::identifier (::name method)))
                                scheme
                                (::annotations method)
                                (::loc method)))))))

    ;; ---- Instances ----

    ;; An instance's variables are the names its head's types leave
    ;; unbound, in the order first written; its requirements, types and
    ;; equations are expanded over them, in that order. Its methods'
    ;; values wait for the bodies.
    (: declared-instance
       (impl (Fn Scopes (Result InstanceForm Malformed) -> (Result Declared (List Feedback)))))
    (define (declared-instance scopes shape)
      (result-let* ((parts (refused shape))
                    (class (instance-class scopes (::class parts)))
                    (instance (instance-head scopes class parts))
                    (body (instance-body scopes (::methods (instance-members (::members parts))))))
        (Ok (Instancing (Instance class
                                  (::variables instance)
                                  (::types instance)
                                  (::requirements instance)
                                  (::equations instance)
                                  (::body body)
                                  (::loc parts))
                        (::methods body)))))

    ;; What an instance's head is, over its variables.
    (struct HeadParts
      ((variables (List String))
       (types (List TypeExpr))
       (requirements (List Requirement))
       (equations (List Equation))))

    (: instance-head
       (impl (Fn Scopes ClassRef InstanceForm -> (Result HeadParts (List Feedback)))))
    (define (instance-head scopes class parts)
      (let* ((variables (delete-duplicates string=?
                                           (concatenate
                                            (map (lambda (type) (free-names scopes type))
                                                 (::types parts)))))
             (env (with-variables (top-env scopes)
                                  (map (lambda (name) (Identifier name (Nil))) variables)))
             (written (::equations (instance-members (::members parts)))))
        (result-let* ((requirements
                       (expand-requirements scopes env variables (::requirements parts)))
                      (types
                       (map-results (lambda (type) (expand-type scopes env type)) (::types parts)))
                      (forms (map-results (lambda (equation) (equation-of equation)) written))
                      (equations (map-results (lambda (form)
                                                (result-let* ((type (expand-type scopes
                                                                                 env
                                                                                 (::type form))))
                                                  (Ok
                                                   (Equation (Label (::name form) (::name-loc form))
                                                             type))))
                                              forms)))
          (Ok (HeadParts variables types requirements equations)))))

    (: equation-of (impl (Fn Marked -> (Result EquationForm (List Feedback)))))
    (define (equation-of syntax)
      (match (equation-form syntax)
        ((Ok form) (Ok form))
        ((Err message) (fail (marked-loc syntax) message))))

    ;; The names in a type that nothing binds at the top level. A row's
    ;; `!` names nothing, as the old expander's `free-type-names` reads
    ;; `(! label ...)`: only its labels can be variables.
    (: free-names (impl (Fn Scopes Marked -> (List String))))
    (define (free-names scopes syntax)
      (match syntax
        ((Ident identifier _)
         (match (resolve scopes (top-env scopes) identifier)
           ((Unbound) (list (::name identifier)))
           (_ (Nil))))
        ((Form (Cons (Ident (Identifier "!" _) _) labels) _)
         (concatenate (map (lambda (item) (free-names scopes item)) labels)))
        ((Form items _) (concatenate (map (lambda (item) (free-names scopes item)) items)))
        (_ (Nil))))

    ;; The class an instance is of: a declared class, or the field class
    ;; `::label`. The compiler alone establishes a callable or an Unboxed
    ;; instance. A deviation, approved: a head that is not a name was an
    ;; internal error of the old expander, and is refused here as not a
    ;; class.
    (: instance-class (impl (Fn Scopes Marked -> (Result ClassRef (List Feedback)))))
    (define (instance-class scopes syntax)
      (match syntax
        ((Ident identifier loc)
         (match (field-path (::name identifier))
           ((PathLabels (Cons label (Nil))) (Ok (FieldClass label)))
           ((PathLabels _)
            (fail loc (string-append "a field class names one label, not " (::name identifier))))
           ((EmptyLabel message) (fail loc message))
           ((NotAPath) (declared-class-ref scopes identifier loc))))
        (_ (fail (marked-loc syntax) "instance of something that is not a typeclass"))))

    (: declared-class-ref
       (impl (Fn Scopes Identifier Loc -> (Result ClassRef (List Feedback)))))
    (define (declared-class-ref scopes identifier loc)
      (match (resolve scopes (top-env scopes) identifier)
        ((BoundAtTop (ClassName global))
         (cond ((some? (callable-contract global))
                (fail loc
                      "callable instances are established by the compiler from receiver access and captures"))
               ((unboxed? global)
                (fail loc
                      "Unboxed is decided by a type's representation; no instance can be declared"))
               (else (Ok (ClassGlobal global)))))
        (_ (fail loc "instance of something that is not a typeclass"))))

    (: some? (impl (Fn (Option Contract) -> Bool)))
    (define (some? option)
      (match option
        ((Some _) #t)
        ((None) #f)))

    (: unboxed? (impl (Fn Global -> Bool)))
    (define (unboxed? global)
      (and (same-library? (::library global) (list "snail" "core" "base"))
           (string=? (::name global) "Unboxed")
           (= (::serial global) 0)))

    ;; An instance's methods: one `dispatch` clause, whose types are
    ;; expanded where the instance is, or definitions.
    (struct BodyParts
      ((body InstanceBody)
       (methods (List PendingMethod))))

    (: instance-body (impl (Fn Scopes (List Marked) -> (Result BodyParts (List Feedback)))))
    (define (instance-body scopes methods)
      (match (dispatch-types methods)
        ((Some (Pair types loc))
         (result-let* ((expanded
                        (map-results (lambda (type) (expand-type scopes (top-env scopes) type))
                                     types)))
           (Ok (BodyParts (Dispatch expanded loc) (Nil)))))
        ((None)
         (result-let* ((pending
                        (map-results (lambda (method) (pending-method scopes method)) methods)))
           (Ok (BodyParts (Methods (Nil)) pending))))))

    (: pending-method (impl (Fn Scopes Marked -> (Result PendingMethod (List Feedback)))))
    (define (pending-method scopes method)
      (if (defines? scopes method)
          (match (definition-shape method)
            ((NamedDefinition name name-loc value)
             (Ok (PendingMethod (method-name (Label (::name name) name-loc))
                                value
                                (marked-loc method))))
            ((MalformedDefinition place message) (fail place message)))
          (fail (marked-loc method) "expected a method definition")))

    ;; A method's name is a field path when the rule reads it as one. The
    ;; old expander finds the method a name names by comparing text, and
    ;; reads no path there, so a path with an empty label is refused by
    ;; nothing here: it is a member's label, which names no member.
    (: method-name (impl (Fn Label -> MethodName)))
    (define (method-name label)
      (match (field-path (::name label))
        ((PathLabels labels) (PathName labels label))
        ((EmptyLabel _) (MemberName label))
        ((NotAPath) (MemberName label))))

    (: defines? (impl (Fn Scopes Marked -> Bool)))
    (define (defines? scopes form)
      (match (head-resolution scopes (top-env scopes) form)
        ((BoundAtTop (Keyword "define")) #t)
        (_ #f)))

    ;; `(dynamic-instances Class (type ...) ...)`: its class, then each
    ;; pair's types.
    (: declared-dynamic
       (impl (Fn Scopes (Result DynamicForm Malformed) -> (Result Declared (List Feedback)))))
    (define (declared-dynamic scopes shape)
      (result-let* ((parts (refused shape))
                    (class (instance-class scopes (::class parts)))
                    (pairs (map-results (lambda (pair)
                                          (result-let* ((types (refused (pair-types pair))))
                                            (map-results (lambda (type)
                                                           (expand-type scopes
                                                                        (top-env scopes)
                                                                        type))
                                                         types)))
                                        (::pairs parts))))
        (Ok (DynamicDone (DynamicInstances class pairs (::loc parts))))))

    ;; ---- Externs and effects ----

    (: declared-extern
       (impl (Fn Scopes Head (Result ExternForm Malformed) -> (Result Top (List Feedback)))))
    (define (declared-extern scopes head shape)
      (result-let* ((parts (refused shape))
                    (type (expand-type scopes (head-env scopes head) (::type parts))))
        (Ok (Extern (head-global scopes head)
                    (::module parts)
                    (::symbol parts)
                    type
                    (::annotations head)
                    (::loc head)))))

    ;; An effect's operations, then its clauses: each must be `default`
    ;; or `(around-main)`, and each default's entries are taken apart; the
    ;; values wait for the bodies.
    (: declared-effect
       (impl (Fn Scopes Head (List OperationForm) (Result EffectClauses Malformed)
                 -> (Result Declared (List Feedback)))))
    (define (declared-effect scopes head operations clauses)
      (result-let* ((nodes (map-results (lambda (operation) (operation-node scopes head operation))
                                        operations))
                    (said (refused clauses)))
        (Ok (Effecting (Effect (head-global scopes head)
                               nodes
                               (Nil)
                               (::around-main? said)
                               (::annotations head)
                               (::loc head))
                       (::defaults said)))))

    (: operation-node (impl (Fn Scopes Head OperationForm -> (Result Operation (List Feedback)))))
    (define (operation-node scopes head operation)
      (result-let* ((scheme (expand-scheme scopes (head-env scopes head) (::type operation))))
        (Ok (Operation (top-global scopes (::identifier (::name operation)))
                       (::control? operation)
                       scheme
                       (::annotations operation)
                       (::loc operation)))))

    ;; ---- Bodies ----

    ;; What the bodies have made so far: the tops, latest first; a
    ;; program's statements, latest first; the feedback of every body that
    ;; failed, in order; and the numbers handed out.
    (struct Bodies
      ((tops (List Top))
       (statements (List Expr))
       (feedback (List Feedback))
       (state Expanding)))

    ;; Where a body is: the scopes, the sets of each `with-instances`
    ;; around it, innermost first, and whether its statements are a
    ;; program's body.
    (struct Place
      ((scopes Scopes)
       (sets (List WrittenSets))
       (program? Bool)))

    (: expanded-bodies
       (impl (Fn Expanding Scopes (List Declared) Bool -> Bodies)))
    (define (expanded-bodies state scopes declared program?)
      (let ((bodies (items-bodies (Bodies (Nil) (Nil) (Nil) state)
                                  (Place scopes (Nil) program?)
                                  declared)))
        (Bodies (reverse (::tops bodies))
                (reverse (::statements bodies))
                (::feedback bodies)
                (::state bodies))))

    (: items-bodies (impl (Fn Bodies Place (List Declared) -> Bodies)))
    (define (items-bodies bodies place declared)
      (fold-left (lambda (bodies item) (item-bodies bodies place item)) bodies declared))

    (: with-top (impl (Fn Bodies Top Expanding -> Bodies)))
    (define (with-top bodies top state)
      (Bodies (Cons top (::tops bodies)) (::statements bodies) (::feedback bodies) state))

    ;; A body that failed leaves the numbers as they were.
    (: with-feedback (impl (Fn Bodies (List Feedback) -> Bodies)))
    (define (with-feedback bodies feedback)
      (Bodies (::tops bodies)
              (::statements bodies)
              (append (::feedback bodies) feedback)
              (::state bodies)))

    (: attempted (impl (Fn Bodies (Result (Pair Top Expanding) (List Feedback)) -> Bodies)))
    (define (attempted bodies result)
      (match result
        ((Ok (Pair top state)) (with-top bodies top state))
        ((Err feedback) (with-feedback bodies feedback))))

    (: item-bodies (impl (Fn Bodies Place Declared -> Bodies)))
    (define (item-bodies bodies place item)
      (match item
        ((Done top) (with-top bodies top (::state bodies)))
        ((DynamicDone member) bodies)
        ((Defining global value loc)
         (attempted bodies (definition-body (::state bodies) place global value loc)))
        ((Stating form) (statement-body bodies place form))
        ((Exposing shape) (attempted bodies (unchanged (::state bodies) (exposed place shape))))
        ((Instancing instance methods)
         (let ((done (methods-bodies bodies place methods)))
           (with-top (::second done)
                     (TopInstance (instance-with-methods instance (::first done)))
                     (::state (::second done)))))
        ((Effecting effect defaults) (effect-bodies bodies place effect defaults))
        ((Scoping sets items loc) (scope-bodies bodies place sets items loc))
        ((Setting global items loc) (set-bodies bodies place global items loc))))

    (: site-of (impl (Fn Place -> Site)))
    (define (site-of place)
      (top-site (::scopes place) (::sets place)))

    ;; The sets of each `with-instances` around a body, resolved once its
    ;; value is expanded, as the old expander resolves them.
    (: enclosing-sets (impl (Fn Place -> (Result (List Global) (List Feedback)))))
    (define (enclosing-sets place)
      (result-let* ((resolved
                     (map-results (lambda (written) (instance-sets (::scopes place) written))
                                  (::sets place))))
        (Ok (delete-duplicates same-global? (concatenate resolved)))))

    (: definition-body
       (impl (Fn Expanding Place Global DefinedValue Loc
                 -> (Result (Pair Top Expanding) (List Feedback)))))
    (define (definition-body state place global value loc)
      (expanding-let* ((expanded state (defined-value state (site-of place) value loc))
                       (sets state (unchanged state (enclosing-sets place))))
        (Ok (Pair (Define global expanded loc) state))))

    ;; A library's statement stays where it is written; a program's joins
    ;; its body, under the sets in scope where it was written.
    (: statement-body (impl (Fn Bodies Place Marked -> Bodies)))
    (define (statement-body bodies place form)
      (match (expanding-let* ((expanded state
                                        (expand-expression (::state bodies) (site-of place) form))
                              (sets state (unchanged state (enclosing-sets place))))
               (Ok (Pair (Pair expanded sets) state)))
        ((Ok (Pair (Pair expanded sets) state))
         (if (::program? place)
             (Bodies (::tops bodies)
                     (Cons
                      (if (null? sets) expanded (WithInstances sets expanded (expr-loc expanded)))
                      (::statements bodies))
                     (::feedback bodies)
                     state)
             (with-top bodies (Statement expanded) state)))
        ((Err feedback) (with-feedback bodies feedback))))

    ;; `(expose name "symbol")`, whose name is a top-level value.
    (: exposed (impl (Fn Place (Result ExposeForm Malformed) -> (Result Top (List Feedback)))))
    (define (exposed place shape)
      (result-let* ((parts (refused shape))
                    (target (exposed-value place (::name parts)))
                    (dynamic? (refused (dynamic-flag parts))))
        (Ok (Expose target (::symbol parts) dynamic? (::loc parts)))))

    (: exposed-value (impl (Fn Place Named -> (Result TopValue (List Feedback)))))
    (define (exposed-value place name)
      (match (resolve (::scopes place) (top-env (::scopes place)) (::identifier name))
        ((BoundAtTop (Value value)) (Ok value))
        (_
         (fail (::loc name)
               (string-append "only a top-level function can be exposed: "
                              (::name (::identifier name)))))))

    ;; Each method's value is a body of its own.
    (: methods-bodies
       (impl (Fn Bodies Place (List PendingMethod) -> (Pair (List InstanceMethod) Bodies))))
    (define (methods-bodies bodies place methods)
      (let loop ((bodies bodies)
                 (methods methods)
                 (done (Nil)))
        (match methods
          ((Nil) (Pair (reverse done) bodies))
          ((Cons method rest)
           (match (defined-value (::state bodies) (site-of place) (::value method) (::loc method))
             ((Ok (Pair value state))
              (loop (Bodies (::tops bodies) (::statements bodies) (::feedback bodies) state)
                    rest
                    (Cons (InstanceMethod (::name method) value) done)))
             ((Err feedback) (loop (with-feedback bodies feedback) rest done)))))))

    (: instance-with-methods (impl (Fn Instance (List InstanceMethod) -> Instance)))
    (define (instance-with-methods instance methods)
      (match (::body instance)
        ((Dispatch _ _) instance)
        ((Methods _)
         (Instance (::class instance)
                   (::variables instance)
                   (::types instance)
                   (::requirements instance)
                   (::equations instance)
                   (Methods methods)
                   (::loc instance)))))

    ;; Each default's value is a body of its own: a function, written as a
    ;; lambda or named.
    (: effect-bodies (impl (Fn Bodies Place Top (List DefaultForm) -> Bodies)))
    (define (effect-bodies bodies place effect defaults)
      (let loop ((bodies bodies)
                 (defaults defaults)
                 (done (Nil)))
        (match defaults
          ((Nil) (with-top bodies (effect-with-defaults effect (reverse done)) (::state bodies)))
          ((Cons default rest)
           (match (default-value (::state bodies) place default)
             ((Ok (Pair value state))
              (loop (Bodies (::tops bodies) (::statements bodies) (::feedback bodies) state)
                    rest
                    (Cons value done)))
             ((Err feedback) (loop (with-feedback bodies feedback) rest done)))))))

    (: default-value
       (impl (Fn Expanding Place DefaultForm -> (Result (Pair Default Expanding) (List Feedback)))))
    (define (default-value state place default)
      (expanding-let* ((value state (expand-expression state (site-of place) (::value default))))
        (if (default-function? value)
            (Ok (Pair
                 (Default (Label (::name (::identifier (::name default))) (::loc (::name default)))
                   value
                   (::loc default))
                 state))
            (fail (::loc default) "a default is a lambda or the name of a function"))))

    (: default-function? (impl (Fn Expr -> Bool)))
    (define (default-function? value)
      (match value
        ((Lambda _ _ _) #t)
        ((ClosedLambda _ _ _) #t)
        ((TopRef _ _) #t)
        ((LocalRef _ _) #t)
        (_ #f)))

    (: effect-with-defaults (impl (Fn Top (List Default) -> Top)))
    (define (effect-with-defaults effect defaults)
      (match effect
        ((Effect global operations _ around-main? annotations loc)
         (Effect global operations defaults around-main? annotations loc))
        (other other)))

    ;; A top-level `with-instances`: its sets are a body, resolved with
    ;; those around it, and then what it holds.
    (: scope-bodies (impl (Fn Bodies Place (List Marked) (List Declared) Loc -> Bodies)))
    (define (scope-bodies bodies place sets items loc)
      (let* ((written (WrittenSets sets (top-env (::scopes place))))
             (inner (Place (::scopes place) (Cons written (::sets place)) (::program? place)))
             (resolved (result-let* ((own (instance-sets (::scopes place) written))
                                     (outer (enclosing-sets place)))
                         (Ok (delete-duplicates same-global? own))))
             (checked (match resolved
                        ((Ok _) bodies)
                        ((Err feedback) (with-feedback bodies feedback))))
             (held (items-bodies
                    (Bodies (Nil) (::statements checked) (::feedback checked) (::state checked))
                    inner
                    items)))
        (Bodies (Cons (InstanceScope (match resolved
                                       ((Ok globals) globals)
                                       ((Err _) (Nil)))
                                     (reverse (::tops held))
                                     loc)
                      (::tops bodies))
                (::statements held)
                (::feedback held)
                (::state held))))

    ;; An instance set's instances and dynamic instances, in order.
    (: set-bodies (impl (Fn Bodies Place Global (List Declared) Loc -> Bodies)))
    (define (set-bodies bodies place global items loc)
      (let loop ((bodies bodies)
                 (items items)
                 (members (Nil)))
        (match items
          ((Nil) (with-top bodies (InstanceSet global (reverse members) loc) (::state bodies)))
          ((Cons (Instancing instance methods) rest)
           (let ((done (methods-bodies bodies place methods)))
             (loop (::second done)
                   rest
                   (Cons (SetInstance (instance-with-methods instance (::first done))) members))))
          ((Cons (DynamicDone member) rest) (loop bodies rest (Cons member members)))
          ((Cons other rest) (loop (item-bodies bodies place other) rest members)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-declarations)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail core table)
     (prefix (snail compiler read language) syntax-)
     (snail compiler expand forms)
     (snail stage0 testing))
    (begin
      (define (test-declarations)
        (test-signatures)
        (test-data)
        (test-instances)
        (test-bodies))

      (define main (list "main"))

      (define (at column)
        (Loc "t.sld" 1 column))

      (define loc (at 1))

      (define (marked datum)
        (cond ((or (null? datum) (pair? datum)) (Form (map marked datum) loc))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) loc))
              ((string? datum) (Atom (syntax-Text datum) loc))
              ((exact-integer? datum) (Atom (syntax-Integer datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (global name)
        (Global main name 0))

      (define forms-scopes
        (Scopes main
                (TopScope empty-table
                          (fold-left (lambda (table export)
                                       (table-set table
                                                  (::name export)
                                                  (list (Binding (Identifier (::name export) (Nil))
                                                                 (::meaning export)))))
                                     empty-table
                                     (::exports forms-offer)))
                (list (Offered forms-library forms-offer))))

      ;; The tops and feedback the three steps make of `forms`.
      (define (expanded forms)
        (match (scan-forms (Expanding 1) forms-scopes (list) (map marked forms))
          ((Ok (Pair scan state))
           (match (result-let* ((signed (checked-signatures (::scopes scan) (::items scan))))
                    (declared-items (::scopes scan) (::items scan)))
             ((Ok declared)
              (let ((bodies (expanded-bodies state (::scopes scan) declared #f)))
                (if (null? (::feedback bodies)) (Ok (::tops bodies)) (Err (::feedback bodies)))))
             ((Err feedback) (Err feedback))))
          ((Err feedback) (Err feedback))))

      (define (messages forms)
        (match (expanded forms)
          ((Ok _) (list))
          ((Err feedback) (map ::message feedback))))

      (define i64 (Applied (Global (list "snail" "core" "forms") "I64" 0) "I64" (list) loc))

      ;; Signatures come before every declaration, and name a value.
      (define (test-signatures)
        (expect (expanded '((: x I64) (define x 1)))
                (Ok (list
                     (Signature (TopGlobal (global "x")) (Scheme (list) (list) i64 loc) (list) loc)
                     (Define (global "x") (Literal (Integer 1) loc) loc))))
        (expect (messages '((: y I64)))
                (list "signature names an undefined top-level definition: y"))
        (expect (messages '((struct P
                              ((x Missing))) (: y I64)))
                (list "signature names an undefined top-level definition: y")))

      (define (test-data)
        (expect (expanded '((struct (Box a)
                              ((v a)) (deriving Move))))
                (Ok (list (Struct (global "Box")
                                  (list "a")
                                  (list (Field "v" #f (Variable "a" loc) (list) loc))
                                  (list (DeriveMove loc))
                                  (list)
                                  loc
                                  loc))))
        (expect (messages '((struct P
                              ((f (impl (Fn -> I64)))))))
                (list
                 "stored and returned callable types require explicit dyn; impl is a definition or argument contract"))
        ;; A field's type is looked at as it resolves: an argument an
        ;; alias's body does not use is not stored.
        (expect (messages '((type (Ignore a) I64) (struct P
                                                    ((f (Ignore (impl (Fn -> I64)))))))) (list))
        (expect (messages '((type (Keep a) (Array a)) (struct P
                                                        ((f (Keep (impl (Fn -> I64))))))))
                (list
                 "stored and returned callable types require explicit dyn; impl is a definition or argument contract"))
        (expect (expanded '((enum E (A) (B ((v I64))))))
                (Ok (list (Enum (global "E")
                                (list)
                                (list (Case (global "A") (list) (list) loc)
                                      (Case (global "B")
                                            (list (CaseField "v" i64 (list) loc))
                                            (list)
                                            loc))
                                (list)
                                (list)
                                loc))))
        (expect (expanded '((typeclass (C a) (type Out) (: m (Array Out)))))
                (Ok (list (Class (global "C")
                                 (list "a")
                                 (list (AssociatedOutput (Label "Out" loc) (list))
                                       (MethodSignature (global "m")
                                                        (Scheme (list)
                                                                (list)
                                                                (Applied (Global (list "snail"
                                                                                       "core"
                                                                                       "forms")
                                                                                 "Array"
                                                                                 0)
                                                                         "Array"
                                                                         (list (Variable "Out" loc))
                                                                         loc)
                                                                loc)
                                                        (list)
                                                        loc))
                                 (list)
                                 loc)))))

      (define (test-instances)
        (expect (messages '((instance (Missing a) (define x 1))))
                (list "instance of something that is not a typeclass"))
        ;; The approved deviation: a head that is not a name, an internal
        ;; error of the old expander, is not a class.
        (expect (messages '((instance (1 a))))
                (list "instance of something that is not a typeclass"))
        (expect (messages '((typeclass (C a) (: m (Array a))) (instance (C a) (m 1))))
                (list "expected a method definition"))
        (match (expanded '((typeclass (C a) (: m (Array a))) (instance (C t) (define (m x) x))))
          ((Ok (Cons _ (Cons (TopInstance instance) (Nil))))
           (expect (::variables instance) (list "t"))
           (expect (method-names instance) (list (MemberName (Label "m" loc)))))
          (other (expect other (Ok (list)))))
        ;; A row's `!` is no variable; its labels may be.
        (match (expanded '((typeclass (S e a) (: s (impl (Fn a -> a ! e))))
                           (instance (S (! r) t) (define (s x) x))))
          ((Ok (Cons _ (Cons (TopInstance instance) (Nil))))
           (expect (::variables instance) (list "r" "t")))
          (other (expect other (Ok (list)))))
        ;; A method named by a field path is its labels; one with an empty
        ;; label is a member's label still, as the old expander reads it,
        ;; for the pass that has the class to refuse.
        (match (expanded '((struct Circle
                             ((radius I64)))
                           (instance (::x Circle I64) (define (::x c) c) (define (::x:: c) c))))
          ((Ok (Cons _ (Cons (TopInstance instance) (Nil))))
           (expect (method-names instance)
                   (list (PathName (list "x") (Label "::x" loc)) (MemberName (Label "::x::" loc)))))
          (other (expect other (Ok (list))))))

      (define (method-names instance)
        (match (::body instance)
          ((Methods methods) (map ::name methods))
          ((Dispatch _ _) (list))))

      ;; Every body is expanded, and each failure reported in order.
      (define (test-bodies)
        (expect (messages '((define x missing) (define y 1) (expose z "z") (f)))
                (list "unbound identifier missing"
                      "only a top-level function can be exposed: z"
                      "unbound identifier f"))
        (expect (messages '((with-instances (s) (define x 1))))
                (list "not an instance set" "not an instance set"))
        (expect (messages '((effect E ((read (impl (Fn -> I64)))) (default ((read 1))))))
                (list "a default is a lambda or the name of a function")))))
   (else)))
