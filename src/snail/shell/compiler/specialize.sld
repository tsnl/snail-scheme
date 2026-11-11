;; Concrete definitions built from checked source. One registry reserves
;; source functions, imports and generated cleanup before visiting their
;; bodies. Each body is instantiated once and retained for preparation's
;; contextual checks; emission receives only fixed declaration metadata.
(define-library (snail shell compiler specialize)
  (export
   Specialization
   prepare-specialization
   State
   Declarations
   Binding
   new-state
   specialization-declarations
   specialization-definitions
   order-initializers
   start-specialization
   specialize-statements
   complete-specializations
   request-drops
   control-effects)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (snail shell compiler check))
  (begin

    ;; ---- Specialization state ----

    ;; Checked facts shared by every library emitted in one build. Preparing
    ;; them once keeps lookup independent of each library's request lifetime.
    (struct Specialization
      ((typed Typed)
       (instances (Table Instance))
       (definitions (Table Expr))))

    (: prepare-specialization (impl (Fn Typed -> Specialization)))
    (define (prepare-specialization typed)
      (let ((instances (fold-left (lambda (table instance)
                                    (table-set table (::name instance) instance))
                                  empty-table
                                  (concatenate
                                   (table-values (::instances (::program typed)))))))
        (Specialization typed instances (item-definitions (::items typed)))))

    ;; A frozen view of executable bindings. It contains no source templates,
    ;; pending requests or concrete bodies, so an emitter cannot specialize.
    (struct Declarations
      ((program Program)
       (owner (Option String))
       (control (List String))
       (bindings (Table Binding))))

    (struct Binding
      ((type Type)
       (function? Bool)
       (external? Bool)))

    ;; Requests reserve names before visiting bodies, so recursive calls and
    ;; recursive drop glue terminate. A recipe becomes a concrete body once.
    ;; Original bodies survive until preparation has checked every batch.
    (struct State
      ((input Specialization)
       (owner (Option String))
       (control (List String))
       (bindings (Table Definition))
       (pending (List String))))

    ;; The registry owns each executable identity and its signature. A body
    ;; is a recipe, its completed instantiation, or an imported declaration.
    (struct Definition
      ((type Type)
       (function? Bool)
       (body Body)))

    (enum Body
      (Source
       ((name String)
        (types (List Type))
        (evidence (List Evidence))))
      (DropGlue
       ((method String)
        (subject Type)
        (loc Loc)))
      (CloneGlue
       ((method String)
        (subject Type)
        (loc Loc)))
      (ShareGlue
       ((subject Type)
        (loc Loc)))
      (SourceBody
       ((origin String)
        (value Expr)))
      (GlueBody)
      (Imported))

    (: Definition-external? (impl (Fn Definition -> Bool)))
    (define (Definition-external? binding)
      (match (::body binding)
        ((Imported) #t)
        (_ #f)))

    ;; The types and evidence that replace a definition's quantified variables
    ;; and requirements while it is copied.
    ;; `control` names the program's control effects, the ones a ground row
    ;; keeps, in order of their names.
    (struct Instantiation
      ((vars Substitution)
       (evidence (List Evidence))
       (control (List String))))

    ;; A sequence of steps that each take the state and hand it back,
    ;; written as `let*` is, as `learning` threads the checker in check.sld.
    ;; `(name (step argument ...))` binds the step's value;
    ;; `(then (step argument ...))` is for a step that hands back the state
    ;; alone. Every step is a call, with the state passed as its first
    ;; argument, and the state is named by an identifier: each step rebinds
    ;; that name, so the body and every later step see the newest one and
    ;; nothing can read a state a step has moved past.
    (define-syntax specializing
      (syntax-rules (then)
        ((_ state () body ...) (begin body ...))
        ((_ state ((then (f argument ...)) step ...) body ...)
         (let ((state (f state argument ...))) (specializing state (step ...) body ...)))
        ((_ state ((name (f argument ...)) step ...) body ...)
         (match (f state argument ...)
           ((Pair name state) (specializing state (step ...) body ...))))))

    ;; `step` over each item in order, threading the state and collecting
    ;; the values, so a sequence of steps is itself one step.
    (: each
       (All (A B)
            (requires (Copy B))
            (impl
             (Fn State (dyn (Fn State A -> (Pair B State))) (List A) -> (Pair (List B) State)))))
    (define (each state step items)
      (let ((done (fold-left (lambda (done item)
                               (match (step (::second done) item)
                                 ((Pair value state) (Pair (Cons value (::first done)) state))))
                             (Pair (Nil) state) items)))
        (Pair (reverse (::first done)) (::second done))))

    (: specialization-program (impl (Fn State -> Program)))
    (define (specialization-program state)
      (::program (::typed (::input state))))

    (: definition (impl (Fn State String -> Expr)))
    (define (definition state name)
      (match (table-ref (::definitions (::input state)) name)
        ((Some value) value)
        ((None) (panic (string-append "internal error: no definition " name)))))

    (: scheme-of (impl (Fn State String -> Scheme)))
    (define (scheme-of state name)
      (definition-scheme (::typed (::input state)) name))

    ;; ---- Requests ----

    ;; The specialized name, queueing the copy the first time. Under coherent
    ;; instances the types determine the evidence.
    (: request (impl (Fn State String (List Type) (List Evidence) -> (Pair String State))))
    (define (request state name types evidence)
      (let ((spec (if (null? types)
                      name
                      (string-append name "<" (string-join (map spec-key types) ",") ">"))))
        (Pair spec
              (if (table-contains? (::bindings state) spec)
                  state
                  (let ((value (definition state name)))
                    (reserve state spec
                             (Definition
                               (ground (instantiation state name types evidence) (::type value))
                               (lambda-expr? value) (Source name types evidence))))))))

    ;; All executable work, including recursive glue, uses this reservation
    ;; rule and this queue. Merely looking up a binding never generates code.
    (: reserve (impl (Fn State String Definition -> State)))
    (define (reserve state name binding)
      (if (table-contains? (::bindings state) name)
          state
          (State-pending-set
           (State-bindings-set state (table-set (::bindings state) name binding))
           (Cons name (::pending state)))))

    (: requested (impl (Fn State String -> State)))
    (define (requested state name)
      (if (external? state name (Nil))
          (import-definition state name (definition state name))
          (::second (request state name (Nil) (Nil)))))

    (: instantiation (impl (Fn State String (List Type) (List Evidence) -> Instantiation)))
    (define (instantiation state name types evidence)
      (Instantiation (zip (::vars (scheme-of state name)) types)
                     evidence (::control state)))

    ;; Complete the entire newly reached graph before a contextual check
    ;; reads any body. Calls reserve identities; they never instantiate here
    ;; recursively, so each queued recipe is consumed exactly once.
    (: complete-specializations (impl (Fn State -> (Pair (List Item) State))))
    (define (complete-specializations state)
      (let loop ((state state) (items (Nil)))
        (match (next-definition state)
          ((Pair (Some item) state) (loop state (Cons item items)))
          ((Pair (None) state) (Pair (reverse items) state)))))

    (: next-definition (impl (Fn State -> (Pair (Option Item) State))))
    (define (next-definition state)
      (match (::pending state)
        ((Cons name rest)
         (let ((definition (binding-of state name)))
           (specializing state ((then (State-pending-set rest))
                                (value (instantiate-body (::body definition)))
                                (then (complete-definition name definition value)))
                         (Pair (Some (Define name value)) state))))
        ((Nil) (Pair (None) state))))

    (: complete-definition (impl (Fn State String Definition Expr -> State)))
    (define (complete-definition state name definition value)
      (let ((body (match (::body definition)
                    ((Source origin _ _) (SourceBody origin value))
                    (_ (GlueBody)))))
        (State-bindings-set state
                            (table-set (::bindings state) name
                                       (Definition-body-set definition body)))))

    (: instantiate-body (impl (Fn State Body -> (Pair Expr State))))
    (define (instantiate-body state body)
      (match body
        ((Source name types evidence)
         (copy-expr state (instantiation state name types evidence) (definition state name)))
        ((DropGlue method subject loc) (drop-function state method subject loc))
        ((CloneGlue method subject loc) (clone-function state method subject loc))
        ((ShareGlue subject loc) (Pair (share-function subject loc) state))
        (_ (panic "internal error: only an unbuilt recipe can be queued"))))

    (: binding-of (impl (Fn State String -> Definition)))
    (define (binding-of state name)
      (match (table-ref (::bindings state) name)
        ((Some binding) binding)
        ((None) (panic (string-append "internal error: no reserved binding " name)))))

    ;; Freeze signatures and discard all source bodies at the emitter's
    ;; boundary. The program contributes declarations, not its syntax items.
    (: specialization-declarations (impl (Fn State -> Declarations)))
    (define (specialization-declarations state)
      (Declarations (Program-items-set (specialization-program state) (Nil))
                    (::owner state) (::control state)
                    (fold-left (lambda (bindings name)
                                 (let ((definition (binding-of state name)))
                                   (table-set bindings name
                                              (Binding (::type definition)
                                                       (::function? definition)
                                                       (Definition-external? definition)))))
                               empty-table (table-keys (::bindings state)))))

    ;; A read-only snapshot of original source instantiations. Generated
    ;; glue and imports keep their declared rows, as before. Missing local
    ;; bodies mean discovery was not closed before analysis.
    (: specialization-definitions (impl (Fn State -> (Table Expr))))
    (define (specialization-definitions state)
      (fold-left (lambda (bodies name)
                   (match (::body (binding-of state name))
                     ((SourceBody _ value) (table-set bodies name value))
                     ((GlueBody) bodies)
                     ((Imported) bodies)
                     (_ (panic "internal error: analysis requires completed definitions"))))
                 empty-table (table-keys (::bindings state))))

    ;; Group concrete initializers by the source definition they came from,
    ;; then follow checked source order. Within one definition, retain the
    ;; specialization discovery order. Functions and glue have no startup work.
    (: order-initializers (impl (Fn State (List Item) -> (List Item))))
    (define (order-initializers state items)
      (let ((groups (fold-right (lambda (item groups) (group-initializer state groups item))
                                empty-table items)))
        (concatenate
         (map (lambda (item)
                (match item
                  ((Define name _) (initializers-at groups name))
                  (_ (Nil))))
              (::items (::typed (::input state)))))))

    (: group-initializer (impl (Fn State (Table (List Item)) Item -> (Table (List Item)))))
    (define (group-initializer state groups item)
      (match item
        ((Define name value)
         (if (lambda-expr? value)
             groups
             (match (::body (binding-of state name))
               ((SourceBody origin _)
                (table-set groups origin (Cons item (initializers-at groups origin))))
               (_ (panic "internal error: an initializer must have a source definition")))))
        (_ groups)))

    (: initializers-at (impl (Fn (Table (List Item)) String -> (List Item))))
    (define (initializers-at groups name)
      (match (table-ref groups name)
        ((Some items) items)
        ((None) (Nil))))

    ;; ---- Copying ----

    ;; Effects are erased here except control effects, because a call that
    ;; may reach a control operation compiles differently from one that
    ;; cannot; specializations differ by their types and their control rows.
    (: ground (impl (Fn Instantiation Type -> Type)))
    (define (ground inst type)
      (erase-rows (::control inst) (substitute (::vars inst) type)))

    (: erase-rows (impl (Fn (List String) Type -> Type)))
    (define (erase-rows control type)
      (match type
        ((TCon name args) (TCon name (map (lambda (arg) (erase-rows control arg)) args)))
        ((TFun params result row)
         (TFun (map (lambda (param) (erase-rows control param)) params)
               (erase-rows control result)
               (control-row control row)))
        ((TRow _ _) (control-row control type))
        (_ type)))

    ;; The control effects a row names, in the order of `control`, closed.
    (: control-row (impl (Fn (List String) Type -> Type)))
    (define (control-row control row)
      (let ((labels (row-labels row)))
        (TRow (filter (lambda (effect) (member? effect labels)) control) (None))))

    (: row-labels (impl (Fn Type -> (List String))))
    (define (row-labels row)
      (match row
        ((TRow labels (Some tail)) (append labels (row-labels tail)))
        ((TRow labels (None)) labels)
        (_ (Nil))))

    ;; A specialization's name keys its types as `type-key` does, plus the
    ;; control effects in their rows. A row without one keys as before, so
    ;; code that cannot reach a control operation keeps its names.
    (: spec-key (impl (Fn Type -> String)))
    (define (spec-key type)
      (match type
        ((TCon name (Nil)) name)
        ((TCon name args) (string-append name "<" (string-join (map spec-key args) ",") ">"))
        ((TFun params result row)
         (string-append "fn<"
                        (string-join (map spec-key params) ",")
                        "->"
                        (spec-key result)
                        ">"
                        (control-suffix row)))
        ((TRow _ _) (string-append "row" (control-suffix type)))
        (_ (type-key type))))

    (: control-suffix (impl (Fn Type -> String)))
    (define (control-suffix row)
      (string-concatenate (map (lambda (effect) (string-append "!" effect)) (row-labels row))))

    (: ground-evidence (impl (Fn Instantiation Evidence -> Evidence)))
    (define (ground-evidence inst evidence)
      (match evidence
        ((EvParam index) (list-ref (::evidence inst) index))
        ((EvInstance instance types subs)
         (EvInstance instance
                     (map (lambda (type) (ground inst type)) types)
                     (map (lambda (sub) (ground-evidence inst sub)) subs)))
        ((EvDerived plan) (EvDerived plan))
        ((EvHole _) (panic "internal error: unsolved evidence"))))

    (: copy-expr (impl (Fn State Instantiation Expr -> (Pair Expr State))))
    (define (copy-expr state inst expr)
      (let ((type (ground inst (::type expr))) (loc (::loc expr)))
        (match (::term expr)
          ((Var "prim:once" _ _) (once-function-value state type loc))
          ((Var name types evidence)
           (reference state
                      name
                      (map (lambda (t) (ground inst t)) types)
                      (map (lambda (e) (ground-evidence inst e)) evidence)
                      type
                      loc))
          ((App callee args)
           (specializing state ((callee (copy-callee inst callee)) (args (copy-exprs inst args)))
                         (specialized-call state callee args type loc)))
          ((Ann inner target)
           (specializing state ((inner (copy-expr inst inner)))
                         (if (and (match (callable-kind type) ((Some "FnOnce") #t) (_ #f))
                                  (needs-consuming-adapter? state inner))
                             (once-adapter state inner type loc)
                             (Pair (Expr (Ann inner (ground inst target)) type loc) state))))
          (term (specializing state
                              ((copied (copy-term inst term)))
                              (Pair (Expr copied type loc) state))))))

    (: copy-callee (impl (Fn State Instantiation Expr -> (Pair Expr State))))
    (define (copy-callee state inst callee)
      (match (::term callee)
        ((Var "prim:once" _ _)
         (Pair (Expr (Var "prim:once" (Nil) (Nil))
                     (ground inst (::type callee)) (::loc callee)) state))
        (_ (copy-expr state inst callee))))

    ;; A first-class once constructor uses the same adaptation as a direct
    ;; use, including owned shared environments and bare code pointers.
    (: once-function-value (impl (Fn State Type Loc -> (Pair Expr State))))
    (define (once-function-value state type loc)
      (match (fn-arrow type)
        ((TFun (Cons receiver (Nil)) result _)
         (let* ((name (string-append "$once.input:" (loc->string loc)))
                (callee (Expr (Var "prim:once" (Nil) (Nil)) type loc)))
           (specializing state ((body
                                 (specialized-call callee (list (local-value name receiver loc))
                                                   result loc)))
                         (Pair (Expr (Lambda (list name) body #f) type loc) state))))
        (_ (panic "internal error: once takes one callable"))))

    ;; A consuming requirement may be instantiated by a shared callable.
    ;; Its body borrows the environment, so this call owns and releases the
    ;; environment after the answer, including cleanup on an aborted call.
    (: specialized-call (impl (Fn State Expr (List Expr) Type Loc -> (Pair Expr State))))
    (define (specialized-call state callee args type loc)
      (match (Pair (::term callee) args)
        ((Pair (Var "prim:once" _ _) (Cons value (Nil)))
         (if (needs-consuming-adapter? state value)
             (once-adapter state value type loc)
             (Pair (Expr (App callee args) type loc) state)))
        (_ (if (and (match (invocation-mode callee) ((Some "FnOnce") #t) (_ #f))
                    (needs-consuming-adapter? state callee))
               (let ((name (string-append "$consuming.receiver:" (loc->string loc))))
                 (specializing state ((body (consuming-body (local-value name (::type callee) loc)
                                                            args type loc)))
                               (Pair (Expr (Let name callee body) type loc) state)))
               (Pair (Expr (App callee args) type loc) state)))))

    (: needs-consuming-adapter? (impl (Fn State Expr -> Bool)))
    (define (needs-consuming-adapter? state value)
      (and (match (callable-kind (::type value)) ((Some "FnOnce") #f) (_ #t))
           (or (linear-type? (specialization-program state) (Nil) (::type value))
               (match (::type value) ((TCon "fn" _) #t) (_ #f)))))

    (: local-value (impl (Fn String Type Loc -> Expr)))
    (define (local-value name type loc)
      (Expr (Var name (Nil) (Nil)) type loc))

    (: shared-invocation (impl (Fn Expr -> Expr)))
    (define (shared-invocation receiver)
      (match (callable-kind (::type receiver))
        ((Some kind) (Expr (Ann receiver (TCon "$invoke"
                                               (list (TCon kind (Nil))
                                                     (fn-arrow (::type receiver)))))
                           (::type receiver) (::loc receiver)))
        (_ (panic "internal error: a consuming adapter has a callable receiver"))))

    (: consuming-body (impl (Fn State Expr (List Expr) Type Loc -> (Pair Expr State))))
    (define (consuming-body state receiver args type loc)
      (let* ((name (string-append "$consuming.answer:" (loc->string loc)))
             (call (Expr (App (shared-invocation receiver) args) type loc)))
        (specializing state ((drop (drop-entry (::type receiver) loc)))
                      (Pair (Expr (Let name call
                                       (Expr (Seq (Expr (App (::second drop) (list receiver))
                                                        unit-type loc)
                                                  (local-value name type loc)) type loc))
                                  type loc) state))))

    ;; `once` and dyn FnOnce storage use the same adapter when they take a
    ;; shared owner. The ordinary once dropper releases it if never called.
    (: once-adapter (impl (Fn State Expr Type Loc -> (Pair Expr State))))
    (define (once-adapter state value type loc)
      (match (fn-arrow type)
        ((TFun params result row)
         (let* ((name (string-append "$once.receiver:" (loc->string loc)))
                (receiver (local-value name (::type value) loc))
                (names (map-indexed (lambda (index param)
                                      (string-append "$once.argument:" (i64->string index)
                                                     ":" (loc->string loc))) params))
                (args (map (lambda (entry) (local-value (::first entry) (::second entry) loc))
                           (zip names params))))
           (specializing state ((body (consuming-body receiver args result loc)))
                         (let* ((arrow (TFun params result row))
                                (lambda-value (Expr (Lambda names body #t) arrow loc))
                                (once (Expr (Var "prim:once" (Nil) (Nil))
                                            (TFun (list arrow) type empty-row) loc)))
                           (Pair
                            (Expr (Let name value (Expr (App once (list lambda-value)) type loc))
                                  type loc) state)))))
        (_ (panic "internal error: a once adapter has a signature"))))

    ;; A copy requests the specializations it references, so the copies of
    ;; sibling terms are steps in the order they are written.
    (: copy-term (impl (Fn State Instantiation Term -> (Pair Term State))))
    (define (copy-term state inst term)
      (match term
        ((Lit value) (Pair (Lit value) state))
        ((Var name types evidence) (Pair (Var name types evidence) state))
        ((Lambda params body captures?)
         (specializing state
                       ((body (copy-expr inst body)))
                       (Pair (Lambda params body captures?) state)))
        ((App callee args)
         (specializing state ((callee (copy-expr inst callee)) (args (copy-exprs inst args)))
                       (Pair (App callee args) state)))
        ((If test consequent alternative)
         (specializing state ((test (copy-expr inst test))
                              (consequent (copy-expr inst consequent))
                              (alternative (copy-expr inst alternative)))
                       (Pair (If test consequent alternative) state)))
        ((Let name value body)
         (specializing state ((value (copy-expr inst value)) (body (copy-expr inst body)))
                       (Pair (Let name value body) state)))
        ((Seq first rest)
         (specializing state ((first (copy-expr inst first)) (rest (copy-expr inst rest)))
                       (Pair (Seq first rest) state)))
        ((Match scrutinee clauses)
         (specializing state ((scrutinee (copy-expr inst scrutinee))
                              (clauses (each (lambda (state clause) (copy-clause state inst clause))
                                             clauses)))
                       (Pair (Match scrutinee clauses) state)))
        ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
        ((Ann inner type)
         (specializing state
                       ((inner (copy-expr inst inner)))
                       (Pair (Ann inner (ground inst type)) state)))
        ((Handle effect implementations body)
         (specializing state ((implementations
                               (each (lambda (state entry) (copy-implementation state inst entry))
                                     implementations))
                              (body (copy-expr inst body)))
                       (Pair (Handle effect implementations body) state)))
        ((Convert inner target)
         (specializing state ((inner (copy-expr inst inner)))
                       (Pair (Convert inner (ground inst target)) state)))
        ((TryConvert _ _)
         (panic "internal error: try-convert must be lowered before specialization"))
        ((TypeTest inner target)
         (specializing state ((inner (copy-expr inst inner)))
                       (Pair (TypeTest inner (ground inst target)) state)))))

    (: copy-exprs (impl (Fn State Instantiation (List Expr) -> (Pair (List Expr) State))))
    (define (copy-exprs state inst exprs)
      (each state (lambda (state expr) (copy-expr state inst expr)) exprs))

    (: copy-clause (impl (Fn State Instantiation Clause -> (Pair Clause State))))
    (define (copy-clause state inst clause)
      (specializing state ((body (copy-expr inst (::body clause))))
                    (Pair (Clause (copy-pattern inst (::pattern clause)) body) state)))

    (: copy-implementation
       (impl (Fn State Instantiation (Pair String Expr) -> (Pair (Pair String Expr) State))))
    (define (copy-implementation state inst entry)
      (specializing state ((value (copy-expr inst (::second entry))))
                    (Pair (Pair (::first entry) value) state)))

    (: copy-pattern (impl (Fn Instantiation Pattern -> Pattern)))
    (define (copy-pattern inst pattern)
      (match pattern
        ((PWild type) (PWild (ground inst type)))
        ((PVar name type) (PVar name (ground inst type)))
        ((PLit value type) (PLit value (ground inst type)))
        ((PCon constructor args type)
         (PCon constructor (map (lambda (arg) (copy-pattern inst arg)) args) (ground inst type)))))

    ;; ---- References ----

    ;; Locals and builtin operations keep their names. A definition becomes
    ;; its specialization; a method becomes its instance's implementation.
    (: reference (impl (Fn State String (List Type) (List Evidence) Type Loc -> (Pair Expr State))))
    (define (reference state name types evidence type loc)
      (match (program-value (specialization-program state) name)
        ((Some (Defined _ _ _)) (definition-reference state name types evidence type loc))
        ((Some (Method class _))
         (if (lifecycle-class? class)
             (lifecycle-reference state
                                  class
                                  name
                                  (list-ref types 1)
                                  (charged-plan evidence)
                                  type
                                  loc)
             (match evidence
               ((Cons (EvInstance instance instance-types subs) rest)
                (let ((class-arity
                       (length (::params (program-class (specialization-program state) class))))
                      (target (instance-method state instance name)))
                  ;; A struct's own field instance names the field's
                  ;; accessor, a builtin, which keeps its name.
                  (match (program-value (specialization-program state) target)
                    ((Some (Defined _ _ _))
                     (definition-reference state
                       target
                       (append instance-types (list-drop types class-arity))
                       (append subs rest) type loc))
                    (_ (Pair (Expr (Var target (Nil) (Nil)) type loc) state)))))
               (_ (panic "internal error: a method needs instance evidence")))))
        ((Some (Operation effect _)) (operation-reference state effect name type loc))
        (_ (Pair (Expr (Var name (Nil) (Nil)) type loc) state))))

    ;; ---- Drops and clones ----

    ;; A drop or a clone of a ground type runs what its plan says
    ;; (`lifecycle-plan`). A trivial drop is the primitive `discard`, and a
    ;; trivial clone is glue that pairs the value with itself; a type with
    ;; an instance runs its method; other data runs its glue. `method` is
    ;; the class method's own name, `drop` or `clone`. `charged` is the plan
    ;; the checker charged for one written in the program, which the ground
    ;; plan may not exceed (`plan-covers?`), and None for one glue makes.
    (: lifecycle-reference
       (impl (Fn State String String Type (Option Plan) Type Loc -> (Pair Expr State))))
    (define (lifecycle-reference state class method subject charged type loc)
      (if (and (or (concrete-callable? subject)
                   (match subject ((TCon "FnMut" _) #t) (_ #f)))
               (string=? class drop-class)
               (linear-type? (specialization-program state) (Nil) subject))
          (Pair (Expr (Var "prim:drop-once" (Nil) (Nil)) type loc) state)
          (match (Pair class subject)
            ;; Dropping a FnOnce runs the dropper its closure carries, which
            ;; drops what it captured (wasm.sld, `drop-once`).
            ((Pair _ (TCon "FnOnce" _))
             (if (string=? class drop-class)
                 (Pair (Expr (Var "prim:drop-once" (Nil) (Nil)) type loc) state)
                 (planned-reference state class method subject charged type loc)))
            (_ (planned-reference state class method subject charged type loc)))))

    (: planned-reference
       (impl (Fn State String String Type (Option Plan) Type Loc -> (Pair Expr State))))
    (define (planned-reference state class method subject charged type loc)
      (match (covered-plan (lifecycle-plan (specialization-program state) class (Nil) subject)
                           charged
                           subject)
        ((Trivial)
         (if (string=? class drop-class)
             (Pair (Expr (Var "prim:discard" (Nil) (Nil)) type loc) state)
             (glue-reference state "share" subject type loc (ShareGlue subject loc))))
        ((Implemented instance)
         (definition-reference state
           (instance-method state (::name instance) method)
           (instance-arguments instance subject)
           (Nil)
           type
           loc))
        ((Glue)
         (if (string=? class drop-class)
             (glue-reference state "drop" subject type loc
                             (DropGlue method subject loc))
             (glue-reference state "clone" subject type loc
                             (CloneGlue method subject loc))))
        ((Refused reason)
         (panic (string-append "internal error: the checker allowed this: " reason)))))

    (: charged-plan (impl (Fn (List Evidence) -> (Option Plan))))
    (define (charged-plan evidence)
      (match evidence
        ((Cons (EvDerived plan) _) plan)
        (_ (panic "internal error: a drop or a clone has derived evidence"))))

    (: covered-plan (impl (Fn Plan (Option Plan) Type -> Plan)))
    (define (covered-plan plan charged subject)
      (if (plan-covers? charged plan)
          plan
          (panic (string-append "internal error: releasing "
                                (type->string subject)
                                " runs more than the checker charged"))))

    ;; The instance's variables, as the ground type binds them in its head.
    ;; The row its head ends with, if it names one, is left empty: a drop or
    ;; a clone performs no control effect, and only those specialize code.
    (: instance-arguments (impl (Fn Instance Type -> (List Type))))
    (define (instance-arguments instance subject)
      (let ((bindings (instance-bindings instance subject)))
        (map (lambda (var)
               (match (assoc-ref bindings var)
                 ((Some type) type)
                 ((None) empty-row)))
             (::vars instance))))

    ;; Glue has one implementation per concrete type. Reserve its recipe
    ;; now, and build the body only when the emitter asks for the next item.
    (: glue-reference (impl (Fn State String Type Type Loc Body -> (Pair Expr State))))
    (define (glue-reference state kind subject type loc body)
      (let ((name (string-append "glue:" kind "<" (spec-key subject) ">")))
        (Pair (Expr (Var name (Nil) (Nil)) type loc)
              (reserve state name (Definition (glue-type type) #t body)))))

    ;; A method use may have the enclosing control row. Generated glue
    ;; itself never yields, independently of which use first requested it.
    ;; Nested function arguments keep their own control rows.
    (: glue-type (impl (Fn Type -> Type)))
    (define (glue-type type)
      (match type
        ((TFun params result _) (TFun params result empty-row))
        (_ (panic "internal error: glue has a function type"))))

    ;; Drop glue matches the value apart and drops each linear immutable
    ;; field, skipping the rest.
    (: drop-function (impl (Fn State String Type Loc -> (Pair Expr State))))
    (define (drop-function state method dropped loc)
      (glue-lambda state
                   dropped
                   unit-type
                   (lambda (state case) (drop-clause state method dropped case loc))
                   loc))

    ;; One case's clause binds each field glue drops to a local of its own
    ;; and skips the others, then drops what it bound, in field order.
    (: drop-clause (impl (Fn State String Type Case Loc -> (Pair Clause State))))
    (define (drop-clause state method dropped case loc)
      (let* ((program (specialization-program state))
             (released (glue-fields program (Nil) dropped case)))
        (specializing state
                      ((drops (each (lambda (state field) (glue-drop state method case field loc))
                                    released)))
                      (Pair (Clause (PCon (::name case)
                                          (map-indexed (lambda (index type)
                                                         (if (any? (lambda (entry)
                                                                     (= (::first entry) index))
                                                                   released)
                                                             (PVar (glue-local case index) type)
                                                             (PWild type)))
                                                       (field-types program dropped case))
                                          dropped)
                                    (in-sequence drops loc))
                            state))))

    (: glue-drop (impl (Fn State String Case (Pair I64 Type) Loc -> (Pair Expr State))))
    (define (glue-drop state method case field loc)
      (let ((type (::second field)))
        (specializing state ((callee (lifecycle-reference drop-class
                                                          method
                                                          type
                                                          (None)
                                                          (TFun (list type) unit-type empty-row)
                                                          loc)))
                      (Pair (Expr (App callee
                                       (list
                                        (Expr (Var (glue-local case (::first field)) (Nil) (Nil))
                                              type
                                              loc)))
                                  unit-type
                                  loc)
                            state))))

    ;; Clone glue matches the value apart, binding every field; clones each
    ;; linear immutable field in field order, taking the pair apart into a
    ;; local for each half; and pairs two values of the case, built from
    ;; the halves and the shared other fields. The plan has refused data
    ;; with a mutable field, so every field is immutable here.
    (: clone-function (impl (Fn State String Type Loc -> (Pair Expr State))))
    (define (clone-function state method cloned loc)
      (glue-lambda state
                   cloned
                   (pair-type cloned)
                   (lambda (state case) (clone-clause state method cloned case loc))
                   loc))

    (: clone-clause (impl (Fn State String Type Case Loc -> (Pair Clause State))))
    (define (clone-clause state method cloned case loc)
      (let* ((program (specialization-program state))
             (types (field-types program cloned case))
             (linear (glue-fields program (Nil) cloned case)))
        (specializing state
                      ((body
                        (clone-fields method cloned case types (map ::first linear) linear loc)))
                      (Pair (Clause (PCon (::name case)
                                          (map-indexed
                                           (lambda (index type) (PVar (glue-local case index) type))
                                           types)
                                          cloned)
                                    body)
                            state))))

    ;; The clone of the first of the linear fields left, taken apart for the
    ;; rest, and once none is left, the pair of values rebuilt from the
    ;; halves of every linear field, `halves`.
    (: clone-fields
       (impl (Fn State
                 String
                 Type
                 Case
                 (List Type)
                 (List I64)
                 (List (Pair I64 Type))
                 Loc
                 -> (Pair Expr State))))
    (define (clone-fields state method cloned case types halves left loc)
      (match left
        ((Nil)
         (Pair (pair-of cloned
                        (rebuilt cloned case types halves "a" loc)
                        (rebuilt cloned case types halves "b" loc)
                        loc)
               state))
        ((Cons field rest)
         (let ((index (::first field)) (type (::second field)))
           (specializing state ((halved (field-clone method case index type loc))
                                (body (clone-fields method cloned case types halves rest loc)))
                         (Pair
                          (Expr (Match halved (list (Clause (halves-pattern case index type) body)))
                                (pair-type cloned)
                                loc)
                          state))))))

    ;; Takes a field's clone apart into a local for each half.
    (: halves-pattern (impl (Fn Case I64 Type -> Pattern)))
    (define (halves-pattern case index type)
      (PCon pair-name
            (list (PVar (half-local case index "a") type) (PVar (half-local case index "b") type))
            (pair-type type)))

    (: field-clone (impl (Fn State String Case I64 Type Loc -> (Pair Expr State))))
    (define (field-clone state method case index type loc)
      (specializing state ((callee (lifecycle-reference clone-class
                                                        method
                                                        type
                                                        (None)
                                                        (TFun (list type)
                                                              (pair-type type)
                                                              empty-row)
                                                        loc)))
                    (Pair (Expr (App callee
                                     (list
                                      (Expr (Var (glue-local case index) (Nil) (Nil)) type loc)))
                                (pair-type type)
                                loc)
                          state)))

    ;; One value of the case, from the `half` of each field in `halves` and
    ;; the field itself otherwise.
    (: rebuilt (impl (Fn Type Case (List Type) (List I64) String Loc -> Expr)))
    (define (rebuilt cloned case types halves half loc)
      (Expr (App (Expr (Var (::name case) (Nil) (Nil)) (TFun types cloned empty-row) loc)
                 (map-indexed (lambda (index type)
                                (Expr (Var (if (member? index halves)
                                               (half-local case index half)
                                               (glue-local case index))
                                           (Nil)
                                           (Nil))
                                      type
                                      loc))
                              types))
            cloned
            loc))

    ;; A trivial clone pairs the value with itself.
    (: share-function (impl (Fn Type Loc -> Expr)))
    (define (share-function shared loc)
      (let ((value (Expr (Var "glue%value" (Nil) (Nil)) shared loc)))
        (Expr (Lambda (list "glue%value") (pair-of shared value value loc) #f)
              (TFun (list shared) (pair-type shared) empty-row)
              loc)))

    ;; A function of one value of `subject` that matches it apart, with a
    ;; clause for each case.
    (: glue-lambda
       (impl
        (Fn State Type Type (dyn (Fn State Case -> (Pair Clause State))) Loc -> (Pair Expr State))))
    (define (glue-lambda state subject result clause loc)
      (let ((data (program-type (specialization-program state) (type-name subject)))
            (value (Expr (Var "glue%value" (Nil) (Nil)) subject loc)))
        (specializing state ((clauses (each clause (::cases data))))
                      (Pair
                       (Expr (Lambda (list "glue%value") (Expr (Match value clauses) result loc) #f)
                             (TFun (list subject) result empty-row)
                             loc)
                       state))))

    (: type-name (impl (Fn Type -> String)))
    (define (type-name type)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: glue takes data apart"))))

    (: pair-name String)
    (define pair-name "snail.core.base:Pair")

    (: pair-type (impl (Fn Type -> Type)))
    (define (pair-type type)
      (TCon pair-name (list type type)))

    (: pair-of (impl (Fn Type Expr Expr Loc -> Expr)))
    (define (pair-of type first second loc)
      (Expr (App (Expr (Var pair-name (Nil) (Nil))
                       (TFun (list type type) (pair-type type) empty-row)
                       loc)
                 (list first second))
            (pair-type type)
            loc))

    ;; Each case's fields have locals of their own, since the clauses of a
    ;; function share its locals, and so does each half of a clone.
    (: glue-local (impl (Fn Case I64 -> String)))
    (define (glue-local case index)
      (string-append "glue%" (i64->string (::tag case)) "%" (i64->string index)))

    (: half-local (impl (Fn Case I64 String -> String)))
    (define (half-local case index half)
      (string-append (glue-local case index) "%" half))

    ;; The drops in order, the last one in tail position, so glue for a
    ;; list runs in constant stack.
    (: in-sequence (impl (Fn (List Expr) Loc -> Expr)))
    (define (in-sequence drops loc)
      (match drops
        ((Nil) (Expr (Lit (DUnit)) unit-type loc))
        ((Cons last (Nil)) last)
        ((Cons first rest) (Expr (Seq first (in-sequence rest loc)) unit-type loc))))

    (: unit-type Type)
    (define unit-type (TCon "Unit" (Nil)))

    ;; Performing an operation runs its Snail-Core default when no handler
    ;; is in scope, so a use of the operation reaches the default too, which
    ;; is copied, or imported from the effect's library, under its own name.
    (: operation-reference (impl (Fn State String String Type Loc -> (Pair Expr State))))
    (define (operation-reference state effect name type loc)
      (Pair (Expr (Var name (Nil) (Nil)) type loc)
            (match (assoc-ref
                    (::defaults (program-effect (specialization-program state) effect))
                    name)
              ((Some function)
               (::second (definition-reference state
                           function
                           (Nil)
                           (Nil)
                           (::type (scheme-of state function))
                           loc)))
              (_ state))))

    (: instance-method (impl (Fn State String String -> String)))
    (define (instance-method state instance method)
      (match (table-ref (::instances (::input state)) instance)
        ((Some found)
         (match (assoc-ref (::methods found) method)
           ((Some global) global)
           ((None) (panic "internal error: missing instance method"))))
        ((None) (panic "internal error: unknown instance"))))

    ;; A definition whose value is just another reference, such as
    ;; `(define + i64-add)`, is replaced by its target. Another library's
    ;; monomorphic definition stays a reference, which its module imports.
    (: definition-reference
       (impl (Fn State String (List Type) (List Evidence) Type Loc -> (Pair Expr State))))
    (define (definition-reference state name types evidence type loc)
      (let ((value (definition state name)))
        (match (::term value)
          ((Var _ _ _)
           (let ((scheme (scheme-of state name)))
             (copy-expr state
                        (Instantiation (zip (::vars scheme) types)
                                       evidence
                                       (::control state))
                        value)))
          (_ (if (external? state name types)
                 (Pair (Expr (Var name (Nil) (Nil)) type loc)
                       (import-definition state name value))
                 (specializing state ((spec (request name types evidence)))
                               (Pair (Expr (Var spec (Nil) (Nil)) type loc) state)))))))

    ;; Imports and emitted definitions share one identity table. In
    ;; particular, exposing an imported function must not enqueue a local
    ;; copy that a later reference could replace with an import.
    (: import-definition (impl (Fn State String Expr -> State)))
    (define (import-definition state name value)
      (if (table-contains? (::bindings state) name)
          state
          (State-bindings-set state
                              (table-set (::bindings state) name
                                         (Definition (::type value)
                                           (lambda-expr? value)
                                           (Imported))))))

    (: external? (impl (Fn State String (List Type) -> Bool)))
    (define (external? state name types)
      (match (::owner state)
        ((Some owner) (and (null? types) (not (string=? (name-owner name) owner))))
        ((None) #f)))

    ;; ---- Roots and cleanup requests ----

    (: new-state (impl (Fn Specialization (Option String) -> State)))
    (define (new-state input owner)
      (State input owner
             (control-effects (::program (::typed input)))
             empty-table (Nil)))

    ;; The effects with a control operation, in order of their names.
    (: control-effects (impl (Fn Program -> (List String))))
    (define (control-effects program)
      (list-sort string<?
                 (map ::name (filter (lambda (effect) (not (null? (::control effect))))
                                     (table-values (::effects program))))))

    ;; A library exports every monomorphic definition. A whole program only
    ;; needs functions reached by its statements, exposures, and initializers.
    ;; Initializers are roots even when their values are never used.
    (: start-specialization (impl (Fn State (List Item) -> (Pair (List String) State))))
    (define (start-specialization state items)
      (specializing state ((exports (each root-item items)))
                    (Pair (concatenate exports) state)))

    (: root-item (impl (Fn State Item -> (Pair (List String) State))))
    (define (root-item state item)
      (match item
        ((Expose name _ _ _) (Pair (Nil) (requested state name)))
        ((Define name value)
         (if (and (null? (::vars (scheme-of state name))) (not (alias-expr? value)))
             (match (::owner state)
               ((Some _) (Pair (list name) (requested state name)))
               ((None) (Pair (Nil) (if (lambda-expr? value) state (requested state name)))))
             (Pair (Nil) state)))
        (_ (Pair (Nil) state))))

    (: specialize-statements (impl (Fn State (List Item) -> (Pair (List Item) State))))
    (define (specialize-statements state items)
      (each state specialize-statement
            (filter (lambda (item) (match item ((Define _ _) #f) (_ #t))) items)))

    (: specialize-statement (impl (Fn State Item -> (Pair Item State))))
    (define (specialize-statement state item)
      (match item
        ((Do expr)
         (specializing state
                       ((value (copy-expr (Instantiation (Nil) (Nil) (::control state)) expr)))
                       (Pair (Do value) state)))
        (_ (Pair item state))))

    ;; Frame cleanup asks for ordinary definitions or derived glue. Those
    ;; requests join the very same queue as calls discovered in a body.
    (: request-drops (impl (Fn State (List Type) Loc -> (Pair (Table Expr) State))))
    (define (request-drops state types loc)
      (specializing state ((drops (each (lambda (state type) (drop-entry state type loc)) types)))
                    (Pair (fold-left (lambda (table entry)
                                       (table-set table (::first entry) (::second entry)))
                                     empty-table drops)
                          state)))

    (: drop-entry (impl (Fn State Type Loc -> (Pair (Pair String Expr) State))))
    (define (drop-entry state type loc)
      (specializing state ((drop (lifecycle-reference drop-class
                                                      (drop-method state)
                                                      type
                                                      (None)
                                                      (TFun (list type) unit-type empty-row)
                                                      loc)))
                    (Pair (Pair (type-key type) drop) state)))

    (: drop-method (impl (Fn State -> String)))
    (define (drop-method state)
      (match (::methods (program-class (specialization-program state) drop-class))
        ((Cons method _) method)
        ((Nil) (panic "internal error: Drop has a method"))))

    (: alias-expr? (impl (Fn Expr -> Bool)))
    (define (alias-expr? expr)
      (match (::term expr)
        ((Var _ _ _) #t)
        (_ #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-specialize)
    (import
     (snail stage0 testing))
    (begin
      (define (test-specialize)
        (test-control-rows)
        (test-spec-keys)
        (test-glue-contract))

      ;; Grounding keeps a row's control effects, in name order, and drops
      ;; the rest, wherever the row sits.
      (define (test-control-rows)
        (let ((row (TRow (list "mut" "gen") (Some (TRow (list "abort" "console") (None)))))
              (control (list "abort" "gen")))
          (expect (erase-rows control row) (TRow (list "abort" "gen") (None)))
          (expect (erase-rows (Nil) row) empty-row)
          (expect (erase-rows control (TFun (list (TCon "I64" (Nil))) (TCon "Unit" (Nil)) row))
                  (TFun (list (TCon "I64" (Nil)))
                        (TCon "Unit" (Nil))
                        (TRow (list "abort" "gen") (None))))))

      ;; A pure generated function stays pure even if its first use was
      ;; widened to an enclosing control row. Its reserved contract must
      ;; agree with the emitted lambda before that lambda has been built.
      (define (test-glue-contract)
        (let* ((i64 (TCon "I64" (Nil)))
               (row (TRow (list "abort") (None)))
               (callback (TFun (list i64) i64 row))
               (type (TFun (list callback) (pair-type callback) row))
               (state (new-state (prepare-specialization (Typed empty-program (Nil) empty-table))
                                 (None)))
               (requested (glue-reference state "share" callback type (Loc "test" 1 1)
                                          (ShareGlue callback (Loc "test" 1 1))))
               (state (::second requested)))
          (match (::term (::first requested))
            ((Var name _ _)
             (match (next-definition state)
               ((Pair (Some (Define _ value)) _)
                (expect (::type (binding-of state name)) (::type value))
                (expect (::type (binding-of state name))
                        (TFun (list callback) (pair-type callback) empty-row))))))))

      ;; Without control effects a name is what `type-key` gives, so pure
      ;; code keeps its names; with one, the name says so.
      (define (test-spec-keys)
        (let ((pure (TFun (list (TCon "I64" (Nil))) (TCon "I64" (Nil)) empty-row))
              (control
               (TFun (list (TCon "I64" (Nil))) (TCon "I64" (Nil)) (TRow (list "gen") (None)))))
          (expect (spec-key pure) (type-key pure))
          (expect (spec-key (TCon "List" (list pure))) (type-key (TCon "List" (list pure))))
          (expect (spec-key control) "fn<I64->I64>!gen")
          (expect (spec-key empty-row) "row")))))))
