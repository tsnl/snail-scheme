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

    (define (prepare-specialization (typed Typed)) (→ Specialization)
      (let ((instances (fold-left (lambda (table instance)
                                    (table-set table (● instance name) instance))
                                  empty-table
                                  (concatenate
                                   (table-values (● (● typed program) instances))))))
        (Specialization typed instances (item-definitions (● typed items)))))

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

    (define (Definition-external? (binding Definition)) (→ Bool)
      (match (● binding body)
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

    (define (each (state State) (step (dyn (Fn State A → (Pair B State)))) (items (List A)))
      (→ (Pair (List B) State))
      (∀ A B)
      (⊨ (Copy B))
      (let ((done (fold-left (lambda (done item)
                               (match (step (● done second) item)
                                 ((Pair value state) (Pair (Cons value (● done first)) state))))
                             (Pair (Nil) state) items)))
        (Pair (reverse (● done first)) (● done second))))

    (define (specialization-program (state State)) (→ Program)
      (● (● (● state input) typed) program))

    (define (definition (state State) (name String)) (→ Expr)
      (match (table-ref (● (● state input) definitions) name)
        ((Some value) value)
        ((None) (panic (string-append "internal error: no definition " name)))))

    (define (scheme-of (state State) (name String)) (→ Scheme)
      (definition-scheme (● (● state input) typed) name))

    ;; ---- Requests ----

    ;; The specialized name, queueing the copy the first time. Under coherent
    ;; instances the types determine the evidence.

    (define (request (state State) (name String) (types (List Type)) (evidence (List Evidence)))
      (→ (Pair String State))
      (let ((spec (if (null? types)
                      name
                      (string-append name "<" (string-join (map spec-key types) ",") ">"))))
        (Pair spec
              (if (table-contains? (● state bindings) spec)
                  state
                  (let ((value (definition state name)))
                    (reserve state spec
                             (Definition
                               (ground (instantiation state name types evidence) (● value type))
                               (lambda-expr? value) (Source name types evidence))))))))

    ;; All executable work, including recursive glue, uses this reservation
    ;; rule and this queue. Merely looking up a binding never generates code.

    (define (reserve (state State) (name String) (binding Definition)) (→ State)
      (if (table-contains? (● state bindings) name)
          state
          (State-pending-set
           (State-bindings-set state (table-set (● state bindings) name binding))
           (Cons name (● state pending)))))

    (define (requested (state State) (name String)) (→ State)
      (if (external? state name (Nil))
          (import-definition state name (definition state name))
          (● (request state name (Nil) (Nil)) second)))

    (define (instantiation (state State)
                           (name String)
                           (types (List Type))
                           (evidence (List Evidence)))
      (→ Instantiation)
      (Instantiation (zip (● (scheme-of state name) vars) types)
                     evidence (● state control)))

    ;; Complete the entire newly reached graph before a contextual check
    ;; reads any body. Calls reserve identities; they never instantiate here
    ;; recursively, so each queued recipe is consumed exactly once.

    (define (complete-specializations (state State)) (→ (Pair (List Item) State))
      (let loop ((state state) (items (Nil)))
        (match (next-definition state)
          ((Pair (Some item) state) (loop state (Cons item items)))
          ((Pair (None) state) (Pair (reverse items) state)))))

    (define (next-definition (state State)) (→ (Pair (Option Item) State))
      (match (● state pending)
        ((Cons name rest)
         (let ((definition (binding-of state name)))
           (specializing state ((then (State-pending-set rest))
                                (value (instantiate-body (● definition body)))
                                (then (complete-definition name definition value)))
                         (Pair (Some (Define name value)) state))))
        ((Nil) (Pair (None) state))))

    (define (complete-definition (state State) (name String) (definition Definition) (value Expr))
      (→ State)
      (let ((body (match (● definition body)
                    ((Source origin _ _) (SourceBody origin value))
                    (_ (GlueBody)))))
        (State-bindings-set state
                            (table-set (● state bindings) name
                                       (Definition-body-set definition body)))))

    (define (instantiate-body (state State) (body Body)) (→ (Pair Expr State))
      (match body
        ((Source name types evidence)
         (copy-expr state (instantiation state name types evidence) (definition state name)))
        ((DropGlue method subject loc) (drop-function state method subject loc))
        ((CloneGlue method subject loc) (clone-function state method subject loc))
        ((ShareGlue subject loc) (Pair (share-function subject loc) state))
        (_ (panic "internal error: only an unbuilt recipe can be queued"))))

    (define (binding-of (state State) (name String)) (→ Definition)
      (match (table-ref (● state bindings) name)
        ((Some binding) binding)
        ((None) (panic (string-append "internal error: no reserved binding " name)))))

    ;; Freeze signatures and discard all source bodies at the emitter's
    ;; boundary. The program contributes declarations, not its syntax items.

    (define (specialization-declarations (state State)) (→ Declarations)
      (Declarations (Program-items-set (specialization-program state) (Nil))
                    (● state owner) (● state control)
                    (fold-left (lambda (bindings name)
                                 (let ((definition (binding-of state name)))
                                   (table-set bindings name
                                              (Binding (● definition type)
                                                       (● definition function?)
                                                       (Definition-external? definition)))))
                               empty-table (table-keys (● state bindings)))))

    ;; A read-only snapshot of original source instantiations. Generated
    ;; glue and imports keep their declared rows, as before. Missing local
    ;; bodies mean discovery was not closed before analysis.

    (define (specialization-definitions (state State)) (→ (Table Expr))
      (fold-left (lambda (bodies name)
                   (match (● (binding-of state name) body)
                     ((SourceBody _ value) (table-set bodies name value))
                     ((GlueBody) bodies)
                     ((Imported) bodies)
                     (_ (panic "internal error: analysis requires completed definitions"))))
                 empty-table (table-keys (● state bindings))))

    ;; Group concrete initializers by the source definition they came from,
    ;; then follow checked source order. Within one definition, retain the
    ;; specialization discovery order. Functions and glue have no startup work.

    (define (order-initializers (state State) (items (List Item))) (→ (List Item))
      (let ((groups (fold-right (lambda (item groups) (group-initializer state groups item))
                                empty-table items)))
        (concatenate
         (map (lambda (item)
                (match item
                  ((Define name _) (initializers-at groups name))
                  (_ (Nil))))
              (● (● (● state input) typed) items)))))

    (define (group-initializer (state State) (groups (Table (List Item))) (item Item))
      (→ (Table (List Item)))
      (match item
        ((Define name value)
         (if (lambda-expr? value)
             groups
             (match (● (binding-of state name) body)
               ((SourceBody origin _)
                (table-set groups origin (Cons item (initializers-at groups origin))))
               (_ (panic "internal error: an initializer must have a source definition")))))
        (_ groups)))

    (define (initializers-at (groups (Table (List Item))) (name String)) (→ (List Item))
      (match (table-ref groups name)
        ((Some items) items)
        ((None) (Nil))))

    ;; ---- Copying ----

    ;; Effects are erased here except control effects, because a call that
    ;; may reach a control operation compiles differently from one that
    ;; cannot; specializations differ by their types and their control rows.

    (define (ground (inst Instantiation) (type Type)) (→ Type)
      (erase-rows (● inst control) (substitute (● inst vars) type)))

    (define (erase-rows (control (List String)) (type Type)) (→ Type)
      (match type
        ((TCon name args) (TCon name (map (lambda (arg) (erase-rows control arg)) args)))
        ((TFun params result row)
         (TFun (map (lambda (param) (erase-rows control param)) params)
               (erase-rows control result)
               (control-row control row)))
        ((TRow _ _) (control-row control type))
        (_ type)))

    ;; The control effects a row names, in the order of `control`, closed.

    (define (control-row (control (List String)) (row Type)) (→ Type)
      (let ((labels (row-labels row)))
        (TRow (filter (lambda (effect) (member? effect labels)) control) (None))))

    (define (row-labels (row Type)) (→ (List String))
      (match row
        ((TRow labels (Some tail)) (append labels (row-labels tail)))
        ((TRow labels (None)) labels)
        (_ (Nil))))

    ;; A specialization's name keys its types as `type-key` does, plus the
    ;; control effects in their rows. A row without one keys as before, so
    ;; code that cannot reach a control operation keeps its names.

    (define (spec-key (type Type)) (→ String)
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

    (define (control-suffix (row Type)) (→ String)
      (string-concatenate (map (lambda (effect) (string-append "!" effect)) (row-labels row))))

    (define (ground-evidence (inst Instantiation) (evidence Evidence)) (→ Evidence)
      (match evidence
        ((EvParam index) (list-ref (● inst evidence) index))
        ((EvInstance instance types subs)
         (EvInstance instance
                     (map (lambda (type) (ground inst type)) types)
                     (map (lambda (sub) (ground-evidence inst sub)) subs)))
        ((EvDerived plan) (EvDerived plan))
        ((EvHole _) (panic "internal error: unsolved evidence"))))

    (define (copy-expr (state State) (inst Instantiation) (expr Expr)) (→ (Pair Expr State))
      (let ((type (ground inst (● expr type))) (loc (● expr loc)))
        (match (● expr term)
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

    (define (copy-callee (state State) (inst Instantiation) (callee Expr)) (→ (Pair Expr State))
      (match (● callee term)
        ((Var "prim:once" _ _)
         (Pair (Expr (Var "prim:once" (Nil) (Nil))
                     (ground inst (● callee type)) (● callee loc)) state))
        (_ (copy-expr state inst callee))))

    ;; A first-class once constructor uses the same adaptation as a direct
    ;; use, including owned shared environments and bare code pointers.

    (define (once-function-value (state State) (type Type) (loc Loc)) (→ (Pair Expr State))
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

    (define (specialized-call (state State) (callee Expr) (args (List Expr)) (type Type) (loc Loc))
      (→ (Pair Expr State))
      (match (Pair (● callee term) args)
        ((Pair (Var "prim:once" _ _) (Cons value (Nil)))
         (if (needs-consuming-adapter? state value)
             (once-adapter state value type loc)
             (Pair (Expr (App callee args) type loc) state)))
        (_ (if (and (match (invocation-mode callee) ((Some "FnOnce") #t) (_ #f))
                    (needs-consuming-adapter? state callee))
               (let ((name (string-append "$consuming.receiver:" (loc->string loc))))
                 (specializing state ((body (consuming-body (local-value name (● callee type) loc)
                                                            args type loc)))
                               (Pair (Expr (Let name callee body) type loc) state)))
               (Pair (Expr (App callee args) type loc) state)))))

    (define (needs-consuming-adapter? (state State) (value Expr)) (→ Bool)
      (and (match (callable-kind (● value type)) ((Some "FnOnce") #f) (_ #t))
           (or (linear-type? (specialization-program state) (Nil) (● value type))
               (match (● value type) ((TCon "fn" _) #t) (_ #f)))))

    (define (local-value (name String) (type Type) (loc Loc)) (→ Expr)
      (Expr (Var name (Nil) (Nil)) type loc))

    (define (shared-invocation (receiver Expr)) (→ Expr)
      (match (callable-kind (● receiver type))
        ((Some kind) (Expr (Ann receiver (TCon "$invoke"
                                               (list (TCon kind (Nil))
                                                     (fn-arrow (● receiver type)))))
                           (● receiver type) (● receiver loc)))
        (_ (panic "internal error: a consuming adapter has a callable receiver"))))

    (define (consuming-body (state State) (receiver Expr) (args (List Expr)) (type Type) (loc Loc))
      (→ (Pair Expr State))
      (let* ((name (string-append "$consuming.answer:" (loc->string loc)))
             (call (Expr (App (shared-invocation receiver) args) type loc)))
        (specializing state ((drop (drop-entry (● receiver type) loc)))
                      (Pair (Expr (Let name call
                                       (Expr (Seq (Expr (App (● drop second) (list receiver))
                                                        unit-type loc)
                                                  (local-value name type loc)) type loc))
                                  type loc) state))))

    ;; `once` and dyn FnOnce storage use the same adapter when they take a
    ;; shared owner. The ordinary once dropper releases it if never called.

    (define (once-adapter (state State) (value Expr) (type Type) (loc Loc)) (→ (Pair Expr State))
      (match (fn-arrow type)
        ((TFun params result row)
         (let* ((name (string-append "$once.receiver:" (loc->string loc)))
                (receiver (local-value name (● value type) loc))
                (names (map-indexed (lambda (index param)
                                      (string-append "$once.argument:" (i64->string index)
                                                     ":" (loc->string loc))) params))
                (args (map (lambda (entry) (local-value (● entry first) (● entry second) loc))
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

    (define (copy-term (state State) (inst Instantiation) (term Term)) (→ (Pair Term State))
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
        ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
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

    (define (copy-exprs (state State) (inst Instantiation) (exprs (List Expr)))
      (→ (Pair (List Expr) State))
      (each state (lambda (state expr) (copy-expr state inst expr)) exprs))

    (define (copy-clause (state State) (inst Instantiation) (clause Clause)) (→ (Pair Clause State))
      (specializing state ((body (copy-expr inst (● clause body))))
                    (Pair (Clause (copy-pattern inst (● clause pattern)) body) state)))

    (define (copy-implementation (state State) (inst Instantiation) (entry (Pair String Expr)))
      (→ (Pair (Pair String Expr) State))
      (specializing state ((value (copy-expr inst (● entry second))))
                    (Pair (Pair (● entry first) value) state)))

    (define (copy-pattern (inst Instantiation) (pattern Pattern)) (→ Pattern)
      (match pattern
        ((PWild type) (PWild (ground inst type)))
        ((PVar name type) (PVar name (ground inst type)))
        ((PLit value type) (PLit value (ground inst type)))
        ((PCon constructor args type)
         (PCon constructor (map (lambda (arg) (copy-pattern inst arg)) args) (ground inst type)))))

    ;; ---- References ----

    ;; Locals and builtin operations keep their names. A definition becomes
    ;; its specialization; a method becomes its instance's implementation.

    (define (reference (state State)
                       (name String)
                       (types (List Type))
                       (evidence (List Evidence))
                       (type Type)
                       (loc Loc))
      (→ (Pair Expr State))
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
                       (length (● (program-class (specialization-program state) class) params)))
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

    (define (lifecycle-reference (state State)
                                 (class String)
                                 (method String)
                                 (subject Type)
                                 (charged (Option Plan))
                                 (type Type)
                                 (loc Loc))
      (→ (Pair Expr State))
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

    (define (planned-reference (state State)
                               (class String)
                               (method String)
                               (subject Type)
                               (charged (Option Plan))
                               (type Type)
                               (loc Loc))
      (→ (Pair Expr State))
      (match (covered-plan (lifecycle-plan (specialization-program state) class (Nil) subject)
                           charged
                           subject)
        ((Trivial)
         (if (string=? class drop-class)
             (Pair (Expr (Var "prim:discard" (Nil) (Nil)) type loc) state)
             (glue-reference state "share" subject type loc (ShareGlue subject loc))))
        ((Implemented instance)
         (definition-reference state
           (instance-method state (● instance name) method)
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

    (define (charged-plan (evidence (List Evidence))) (→ (Option Plan))
      (match evidence
        ((Cons (EvDerived plan) _) plan)
        (_ (panic "internal error: a drop or a clone has derived evidence"))))

    (define (covered-plan (plan Plan) (charged (Option Plan)) (subject Type)) (→ Plan)
      (if (plan-covers? charged plan)
          plan
          (panic (string-append "internal error: releasing "
                                (type->string subject)
                                " runs more than the checker charged"))))

    ;; The instance's variables, as the ground type binds them in its head.
    ;; The row its head ends with, if it names one, is left empty: a drop or
    ;; a clone performs no control effect, and only those specialize code.

    (define (instance-arguments (instance Instance) (subject Type)) (→ (List Type))
      (let ((bindings (instance-bindings instance subject)))
        (map (lambda (var)
               (match (assoc-ref bindings var)
                 ((Some type) type)
                 ((None) empty-row)))
             (● instance vars))))

    ;; Glue has one implementation per concrete type. Reserve its recipe
    ;; now, and build the body only when the emitter asks for the next item.

    (define (glue-reference (state State)
                            (kind String)
                            (subject Type)
                            (type Type)
                            (loc Loc)
                            (body Body))
      (→ (Pair Expr State))
      (let ((name (string-append "glue:" kind "<" (spec-key subject) ">")))
        (Pair (Expr (Var name (Nil) (Nil)) type loc)
              (reserve state name (Definition (glue-type type) #t body)))))

    ;; A method use may have the enclosing control row. Generated glue
    ;; itself never yields, independently of which use first requested it.
    ;; Nested function arguments keep their own control rows.

    (define (glue-type (type Type)) (→ Type)
      (match type
        ((TFun params result _) (TFun params result empty-row))
        (_ (panic "internal error: glue has a function type"))))

    ;; Drop glue matches the value apart and drops each linear immutable
    ;; field, skipping the rest.

    (define (drop-function (state State) (method String) (dropped Type) (loc Loc))
      (→ (Pair Expr State))
      (glue-lambda state
                   dropped
                   unit-type
                   (lambda (state case) (drop-clause state method dropped case loc))
                   loc))

    ;; One case's clause binds each field glue drops to a local of its own
    ;; and skips the others, then drops what it bound, in field order.

    (define (drop-clause (state State) (method String) (dropped Type) (case Case) (loc Loc))
      (→ (Pair Clause State))
      (let* ((program (specialization-program state))
             (released (glue-fields program (Nil) dropped case)))
        (specializing state
                      ((drops (each (lambda (state field) (glue-drop state method case field loc))
                                    released)))
                      (Pair (Clause (PCon (● case name)
                                          (map-indexed (lambda (index type)
                                                         (if (any? (lambda (entry)
                                                                     (= (● entry first) index))
                                                                   released)
                                                             (PVar (glue-local case index) type)
                                                             (PWild type)))
                                                       (field-types program dropped case))
                                          dropped)
                                    (in-sequence drops loc))
                            state))))

    (define (glue-drop (state State) (method String) (case Case) (field (Pair I64 Type)) (loc Loc))
      (→ (Pair Expr State))
      (let ((type (● field second)))
        (specializing state ((callee (lifecycle-reference drop-class
                                                          method
                                                          type
                                                          (None)
                                                          (TFun (list type) unit-type empty-row)
                                                          loc)))
                      (Pair (Expr (App callee
                                       (list
                                        (Expr (Var (glue-local case (● field first)) (Nil) (Nil))
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

    (define (clone-function (state State) (method String) (cloned Type) (loc Loc))
      (→ (Pair Expr State))
      (glue-lambda state
                   cloned
                   (pair-type cloned)
                   (lambda (state case) (clone-clause state method cloned case loc))
                   loc))

    (define (clone-clause (state State) (method String) (cloned Type) (case Case) (loc Loc))
      (→ (Pair Clause State))
      (let* ((program (specialization-program state))
             (types (field-types program cloned case))
             (linear (glue-fields program (Nil) cloned case)))
        (specializing state
                      ((body
                        (clone-fields method
                                      cloned
                                      case
                                      types
                                      (map (lambda (record) (● record first)) linear)
                                      linear
                                      loc)))
                      (Pair (Clause (PCon (● case name)
                                          (map-indexed
                                           (lambda (index type) (PVar (glue-local case index) type))
                                           types)
                                          cloned)
                                    body)
                            state))))

    ;; The clone of the first of the linear fields left, taken apart for the
    ;; rest, and once none is left, the pair of values rebuilt from the
    ;; halves of every linear field, `halves`.

    (define (clone-fields (state State)
                          (method String)
                          (cloned Type)
                          (case Case)
                          (types (List Type))
                          (halves (List I64))
                          (left (List (Pair I64 Type)))
                          (loc Loc))
      (→ (Pair Expr State))
      (match left
        ((Nil)
         (Pair (pair-of cloned
                        (rebuilt cloned case types halves "a" loc)
                        (rebuilt cloned case types halves "b" loc)
                        loc)
               state))
        ((Cons field rest)
         (let ((index (● field first)) (type (● field second)))
           (specializing state ((halved (field-clone method case index type loc))
                                (body (clone-fields method cloned case types halves rest loc)))
                         (Pair
                          (Expr (Match halved (list (Clause (halves-pattern case index type) body)))
                                (pair-type cloned)
                                loc)
                          state))))))

    ;; Takes a field's clone apart into a local for each half.

    (define (halves-pattern (case Case) (index I64) (type Type)) (→ Pattern)
      (PCon pair-name
            (list (PVar (half-local case index "a") type) (PVar (half-local case index "b") type))
            (pair-type type)))

    (define (field-clone (state State)
                         (method String)
                         (case Case)
                         (index I64)
                         (type Type)
                         (loc Loc))
      (→ (Pair Expr State))
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

    (define (rebuilt (cloned Type)
                     (case Case)
                     (types (List Type))
                     (halves (List I64))
                     (half String)
                     (loc Loc))
      (→ Expr)
      (Expr (App (Expr (Var (● case name) (Nil) (Nil)) (TFun types cloned empty-row) loc)
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

    (define (share-function (shared Type) (loc Loc)) (→ Expr)
      (let ((value (Expr (Var "glue%value" (Nil) (Nil)) shared loc)))
        (Expr (Lambda (list "glue%value") (pair-of shared value value loc) #f)
              (TFun (list shared) (pair-type shared) empty-row)
              loc)))

    ;; A function of one value of `subject` that matches it apart, with a
    ;; clause for each case.

    (define (glue-lambda (state State)
                         (subject Type)
                         (result Type)
                         (clause (dyn (Fn State Case → (Pair Clause State))))
                         (loc Loc))
      (→ (Pair Expr State))
      (let ((data (program-type (specialization-program state) (type-name subject)))
            (value (Expr (Var "glue%value" (Nil) (Nil)) subject loc)))
        (specializing state ((clauses (each clause (● data cases))))
                      (Pair
                       (Expr (Lambda (list "glue%value") (Expr (Match value clauses) result loc) #f)
                             (TFun (list subject) result empty-row)
                             loc)
                       state))))

    (define (type-name (type Type)) (→ String)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: glue takes data apart"))))

    (define pair-name (→ String) "snail.core.base:Pair")

    (define (pair-type (type Type)) (→ Type)
      (TCon pair-name (list type type)))

    (define (pair-of (type Type) (first Expr) (second Expr) (loc Loc)) (→ Expr)
      (Expr (App (Expr (Var pair-name (Nil) (Nil))
                       (TFun (list type type) (pair-type type) empty-row)
                       loc)
                 (list first second))
            (pair-type type)
            loc))

    ;; Each case's fields have locals of their own, since the clauses of a
    ;; function share its locals, and so does each half of a clone.

    (define (glue-local (case Case) (index I64)) (→ String)
      (string-append "glue%" (i64->string (● case tag)) "%" (i64->string index)))

    (define (half-local (case Case) (index I64) (half String)) (→ String)
      (string-append (glue-local case index) "%" half))

    ;; The drops in order, the last one in tail position, so glue for a
    ;; list runs in constant stack.

    (define (in-sequence (drops (List Expr)) (loc Loc)) (→ Expr)
      (match drops
        ((Nil) (Expr (Lit (DUnit)) unit-type loc))
        ((Cons last (Nil)) last)
        ((Cons first rest) (Expr (Seq first (in-sequence rest loc)) unit-type loc))))

    (define unit-type (→ Type) (TCon "Unit" (Nil)))

    ;; Performing an operation runs its Snail-Core default when no handler
    ;; is in scope, so a use of the operation reaches the default too, which
    ;; is copied, or imported from the effect's library, under its own name.

    (define (operation-reference (state State) (effect String) (name String) (type Type) (loc Loc))
      (→ (Pair Expr State))
      (Pair (Expr (Var name (Nil) (Nil)) type loc)
            (match (assoc-ref
                    (● (program-effect (specialization-program state) effect) defaults)
                    name)
              ((Some function)
               (● (definition-reference state
                    function
                    (Nil)
                    (Nil)
                    (● (scheme-of state function) type)
                    loc) second))
              (_ state))))

    (define (instance-method (state State) (instance String) (method String)) (→ String)
      (match (table-ref (● (● state input) instances) instance)
        ((Some found)
         (match (assoc-ref (● found methods) method)
           ((Some global) global)
           ((None) (panic "internal error: missing instance method"))))
        ((None) (panic "internal error: unknown instance"))))

    ;; A definition whose value is just another reference, such as
    ;; `(define + i64-add)`, is replaced by its target. Another library's
    ;; monomorphic definition stays a reference, which its module imports.

    (define (definition-reference (state State)
              (name String)
              (types (List Type))
              (evidence (List Evidence))
              (type Type)
              (loc Loc))
      (→ (Pair Expr State))
      (let ((value (definition state name)))
        (match (● value term)
          ((Var _ _ _)
           (let ((scheme (scheme-of state name)))
             (copy-expr state
                        (Instantiation (zip (● scheme vars) types)
                                       evidence
                                       (● state control))
                        value)))
          (_ (if (external? state name types)
                 (Pair (Expr (Var name (Nil) (Nil)) type loc)
                       (import-definition state name value))
                 (specializing state ((spec (request name types evidence)))
                               (Pair (Expr (Var spec (Nil) (Nil)) type loc) state)))))))

    ;; Imports and emitted definitions share one identity table. In
    ;; particular, exposing an imported function must not enqueue a local
    ;; copy that a later reference could replace with an import.

    (define (import-definition (state State) (name String) (value Expr)) (→ State)
      (if (table-contains? (● state bindings) name)
          state
          (State-bindings-set state
                              (table-set (● state bindings) name
                                         (Definition (● value type)
                                           (lambda-expr? value)
                                           (Imported))))))

    (define (external? (state State) (name String) (types (List Type))) (→ Bool)
      (match (● state owner)
        ((Some owner) (and (null? types) (not (string=? (name-owner name) owner))))
        ((None) #f)))

    ;; ---- Roots and cleanup requests ----

    (define (new-state (input Specialization) (owner (Option String))) (→ State)
      (State input owner
             (control-effects (● (● input typed) program))
             empty-table (Nil)))

    ;; The effects with a control operation, in order of their names.

    (define (control-effects (program Program)) (→ (List String))
      (list-sort string<?
                 (map (lambda (record) (● record name))
                      (filter (lambda (effect) (not (null? (● effect control))))
                              (table-values (● program effects))))))

    ;; A library exports every monomorphic definition. A whole program only
    ;; needs functions reached by its statements, exposures, and initializers.
    ;; Initializers are roots even when their values are never used.

    (define (start-specialization (state State) (items (List Item))) (→ (Pair (List String) State))
      (specializing state ((exports (each root-item items)))
                    (Pair (concatenate exports) state)))

    (define (root-item (state State) (item Item)) (→ (Pair (List String) State))
      (match item
        ((Expose name _ _ _) (Pair (Nil) (requested state name)))
        ((Define name value)
         (if (and (null? (● (scheme-of state name) vars)) (not (alias-expr? value)))
             (match (● state owner)
               ((Some _) (Pair (list name) (requested state name)))
               ((None) (Pair (Nil) (if (lambda-expr? value) state (requested state name)))))
             (Pair (Nil) state)))
        (_ (Pair (Nil) state))))

    (define (specialize-statements (state State) (items (List Item))) (→ (Pair (List Item) State))
      (each state specialize-statement
            (filter (lambda (item) (match item ((Define _ _) #f) (_ #t))) items)))

    (define (specialize-statement (state State) (item Item)) (→ (Pair Item State))
      (match item
        ((Do expr)
         (specializing state
                       ((value (copy-expr (Instantiation (Nil) (Nil) (● state control)) expr)))
                       (Pair (Do value) state)))
        (_ (Pair item state))))

    ;; Frame cleanup asks for ordinary definitions or derived glue. Those
    ;; requests join the very same queue as calls discovered in a body.

    (define (request-drops (state State) (types (List Type)) (loc Loc))
      (→ (Pair (Table Expr) State))
      (specializing state ((drops (each (lambda (state type) (drop-entry state type loc)) types)))
                    (Pair (fold-left (lambda (table entry)
                                       (table-set table (● entry first) (● entry second)))
                                     empty-table drops)
                          state)))

    (define (drop-entry (state State) (type Type) (loc Loc)) (→ (Pair (Pair String Expr) State))
      (specializing state ((drop (lifecycle-reference drop-class
                                                      (drop-method state)
                                                      type
                                                      (None)
                                                      (TFun (list type) unit-type empty-row)
                                                      loc)))
                    (Pair (Pair (type-key type) drop) state)))

    (define (drop-method (state State)) (→ String)
      (match (● (program-class (specialization-program state) drop-class) methods)
        ((Cons method _) method)
        ((Nil) (panic "internal error: Drop has a method"))))

    (define (alias-expr? (expr Expr)) (→ Bool)
      (match (● expr term)
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
      (define test-specialize
        (lambda () (test-control-rows)
                (test-spec-keys)
                (test-glue-contract)))

      ;; Grounding keeps a row's control effects, in name order, and drops
      ;; the rest, wherever the row sits.
      (define test-control-rows
        (lambda ()
          (let ((row (TRow (list "mut" "gen") (Some (TRow (list "abort" "console") (None)))))
                (control (list "abort" "gen")))
            (expect (erase-rows control row) (TRow (list "abort" "gen") (None)))
            (expect (erase-rows (Nil) row) empty-row)
            (expect (erase-rows control (TFun (list (TCon "I64" (Nil))) (TCon "Unit" (Nil)) row))
                    (TFun (list (TCon "I64" (Nil)))
                          (TCon "Unit" (Nil))
                          (TRow (list "abort" "gen") (None)))))))

      ;; A pure generated function stays pure even if its first use was
      ;; widened to an enclosing control row. Its reserved contract must
      ;; agree with the emitted lambda before that lambda has been built.
      (define test-glue-contract
        (lambda () (let* ((i64 (TCon "I64" (Nil)))
                          (row (TRow (list "abort") (None)))
                          (callback (TFun (list i64) i64 row))
                          (type (TFun (list callback) (pair-type callback) row))
                          (state (new-state
                                  (prepare-specialization (Typed empty-program (Nil) empty-table))
                                  (None)))
                          (requested (glue-reference state "share" callback type (Loc "test" 1 1)
                                                     (ShareGlue callback (Loc "test" 1 1))))
                          (state (● requested second)))
                     (match (● (● requested first) term)
                       ((Var name _ _)
                        (match (next-definition state)
                          ((Pair (Some (Define _ value)) _)
                           (expect (● (binding-of state name) type) (● value type))
                           (expect (● (binding-of state name) type)
                                   (TFun (list callback) (pair-type callback) empty-row)))))))))

      ;; Without control effects a name is what `type-key` gives, so pure
      ;; code keeps its names; with one, the name says so.
      (define test-spec-keys
        (lambda () (let ((pure (TFun (list (TCon "I64" (Nil))) (TCon "I64" (Nil)) empty-row))
                         (control
                          (TFun (list (TCon "I64" (Nil)))
                                (TCon "I64" (Nil))
                                (TRow (list "gen") (None)))))
                     (expect (spec-key pure) (type-key pure))
                     (expect (spec-key (TCon "List" (list pure)))
                             (type-key (TCon "List" (list pure))))
                     (expect (spec-key control) "fn<I64->I64>!gen")
                     (expect (spec-key empty-row) "row"))))))))
