;; Concrete definitions built from checked source. One registry reserves
;; source functions and imports before visiting their bodies. Each body is instantiated once; source bodies are retained for
;; preparation's contextual checks. Emission receives fixed declaration metadata.
(define-library (snail shell compiler specialize)
  (export
   Specialization
   prepare-specialization
   State
   Declarations
   Binding
   new-state
   specialization-declarations
   specialization-program
   specialization-definitions
   start-specialization
   complete-specializations
   control-effects)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler check))
  (begin

    ;; ---- Specialization state ----

    ;; Checked facts shared by every library emitted in one build. Preparing
    ;; them once keeps lookup independent of each library's request lifetime.
    (record Specialization
      ((typed Typed)
       (instances (Table Instance))
       (definitions (Table Expr))))

    (define (prepare-specialization (typed Typed)) (→ Specialization)
      (let ((instances (fold-left (lambda (table instance)
                                    (table-set table (● instance name) instance))
                                  (empty-table)
                                  (concatenate
                                   (table-values (● (● typed program) instances))))))
        (new Specialization
          (typed typed)
          (instances instances)
          (definitions (item-definitions (● typed items))))))

    ;; A frozen view of executable bindings. It contains no source templates,
    ;; pending requests or concrete bodies, so an emitter cannot specialize.
    (record Declarations
      ((program Program)
       (owner (Option String))
       (control (List String))
       (bindings (Table Binding))))

    (record Binding
      ((type Type)
       (external? Bool)))

    ;; Requests reserve names before visiting bodies, so recursive calls
    ;; terminate. A recipe becomes a concrete body once.
    ;; Original bodies survive until preparation has checked every batch.
    (record State
      ((input Specialization)
       (owner (Option String))
       (control (List String))
       (bindings (Table Definition))
       (remaining I64)
       (pending (List String))))

    ;; The registry owns each executable identity and its signature. A body
    ;; is a recipe, its completed instantiation, or an imported declaration.
    (record Definition
      ((type Type)
       (body Body)))

    (enum Body
      (SourceRecipe
       ((name String)
        (types (List Type))
        (evidence (List Evidence))))
      (SourceBody
       ((value Expr)))
      (Imported))

    (define (Definition-external? (binding Definition)) (→ Bool)
      (match (● binding body)
        ((Imported) #t)
        (_ #f)))

    ;; The types and evidence that replace a definition's quantified variables
    ;; and requirements while it is copied.
    ;; `control` names the program's control effects, the ones a ground row
    ;; keeps, in order of their names.
    (record Instantiation
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

    (define (each (state State) (step (Fn State A → (Pair B State))) (items (List A)))
      (→ (Pair (List B) State))
      (∀ (A B))
      (let ((done (fold-left (lambda (done item)
                               (match (step (● done second) item)
                                 ((Pair value state)
                                  (new Pair (first (Cons value (● done first))) (second state)))))
                             (new Pair (first (Nil)) (second state)) items)))
        (new Pair (first (reverse (● done first))) (second (● done second)))))

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
        (new Pair (first spec)
             (second (if (table-contains? (● state bindings) spec)
                         state
                         (let ((value (definition state name)))
                           (reserve state spec
                                    (new Definition
                                      (type (ground (instantiation state name types evidence)
                                                    (● value type)))
                                      (body (SourceRecipe name types evidence))))))))))

    ;; All executable work uses this reservation rule and this queue. Merely looking up a binding never generates code.

    (define (reserve (state State) (name String) (binding Definition)) (→ State)
      (if (table-contains? (● state bindings) name)
          state
          (begin
            (when (= (● state remaining) 0)
              (panic "compilation exceeds the limit of 65536 specialized definitions"))
            (State-pending-set
             (State-remaining-set
              (State-bindings-set state (table-set (● state bindings) name binding))
              (- (● state remaining) 1))
             (Cons name (● state pending))))))

    (define (requested (state State) (name String)) (→ State)
      (if (external? state name (Nil))
          (import-definition state name (definition state name))
          (● (request state name (Nil) (Nil)) second)))

    (define (instantiation (state State)
                           (name String)
                           (types (List Type))
                           (evidence (List Evidence)))
      (→ Instantiation)
      (new Instantiation (vars (zip (● (scheme-of state name) vars) types))
           (evidence evidence) (control (● state control))))

    ;; Complete the entire newly reached graph before a contextual check
    ;; reads any body. Calls reserve identities; they never instantiate here
    ;; recursively, so each queued recipe is consumed exactly once.

    (define (complete-specializations (state State)) (→ (Pair (List Item) State))
      (let loop ((state state) (items (Nil)))
        (match (next-definition state)
          ((Pair (Some item) state) (loop state (Cons item items)))
          ((Pair (None) state) (new Pair (first (reverse items)) (second state))))))

    (define (next-definition (state State)) (→ (Pair (Option Item) State))
      (match (● state pending)
        ((Cons name rest)
         (let ((definition (binding-of state name)))
           (specializing state ((then (State-pending-set rest))
                                (value (instantiate-body (● definition body)))
                                (then (complete-definition name definition value)))
                         (new Pair (first (Some (Define name value))) (second state)))))
        ((Nil) (new Pair (first (None)) (second state)))))

    (define (complete-definition (state State) (name String) (definition Definition) (value Expr))
      (→ State)
      (State-bindings-set state
                          (table-set (● state bindings) name
                                     (Definition-body-set definition (SourceBody value)))))

    (define (instantiate-body (state State) (body Body)) (→ (Pair Expr State))
      (match body
        ((SourceRecipe name types evidence)
         (copy-expr state (instantiation state name types evidence) (definition state name)))
        (_ (panic "internal error: only an unbuilt recipe can be queued"))))

    (define (binding-of (state State) (name String)) (→ Definition)
      (match (table-ref (● state bindings) name)
        ((Some binding) binding)
        ((None) (panic (string-append "internal error: no reserved binding " name)))))

    ;; Freeze signatures and discard all source bodies at the emitter's
    ;; boundary. The program contributes declarations, not its syntax items.

    (define (specialization-declarations (state State)) (→ Declarations)
      (new Declarations (program (Program-items-set (specialization-program state) (Nil)))
           (owner (● state owner)) (control (● state control))
           (bindings (fold-left (lambda (bindings name)
                                  (let ((definition (binding-of state name)))
                                    (table-set bindings name
                                               (new Binding (type (● definition type))

                                                    (external?
                                                     (Definition-external? definition))))))
                                (empty-table) (table-keys (● state bindings))))))

    ;; A read-only snapshot of original source instantiations. Imports keep
    ;; their declared rows. Missing local bodies mean discovery was not
    ;; closed before analysis.

    (define (specialization-definitions (state State)) (→ (Table Expr))
      (fold-left (lambda (bodies name)
                   (match (● (binding-of state name) body)
                     ((SourceBody value) (table-set bodies name value))
                     ((Imported) bodies)
                     (_ (panic "internal error: analysis requires completed definitions"))))
                 (empty-table) (table-keys (● state bindings))))

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
      (require-type-capacity type)
      (unchecked-spec-key type))

    (define (unchecked-spec-key (type Type)) (→ String)
      (match type
        ((TCon name (Nil)) name)
        ((TCon name args)
         (string-append name "<" (string-join (map unchecked-spec-key args) ",") ">"))
        ((TFun params result row)
         (string-append "fn<"
                        (string-join (map unchecked-spec-key params) ",")
                        "->"
                        (unchecked-spec-key result)
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
        ((EvHole _) (panic "internal error: unsolved evidence"))))

    (define (copy-expr (state State) (inst Instantiation) (expr Expr)) (→ (Pair Expr State))
      (let ((type (ground inst (● expr type))) (loc (● expr loc)))
        (match (● expr term)
          ((Var name types evidence)
           (reference state name (map (lambda (t) (ground inst t)) types)
                      (map (lambda (e) (ground-evidence inst e)) evidence) type loc))
          (term (specializing state ((copied (copy-term inst term)))
                              (new Pair
                                (first (new Expr (term copied) (type type) (loc loc)))
                                (second state)))))))

    ;; A copy requests the specializations it references, so the copies of
    ;; sibling terms are steps in the order they are written.

    (define (copy-term (state State) (inst Instantiation) (term Term)) (→ (Pair Term State))
      (match term
        ((Lit value) (new Pair (first (Lit value)) (second state)))
        ((Var name types evidence) (new Pair (first (Var name types evidence)) (second state)))
        ((Lambda params body )
         (specializing state
                       ((body (copy-expr inst body)))
                       (new Pair (first (Lambda params body )) (second state))))
        ((App callee args)
         (specializing state ((callee (copy-expr inst callee)) (args (copy-exprs inst args)))
                       (new Pair (first (App callee args)) (second state))))
        ((If test consequent alternative)
         (specializing state ((test (copy-expr inst test))
                              (consequent (copy-expr inst consequent))
                              (alternative (copy-expr inst alternative)))
                       (new Pair (first (If test consequent alternative)) (second state))))
        ((Let name value body)
         (specializing state ((value (copy-expr inst value)) (body (copy-expr inst body)))
                       (new Pair (first (Let name value body)) (second state))))
        ((Seq first rest)
         (specializing state ((first (copy-expr inst first)) (rest (copy-expr inst rest)))
                       (new Pair (first (Seq first rest)) (second state))))
        ((Match scrutinee clauses)
         (specializing state ((scrutinee (copy-expr inst scrutinee))
                              (clauses (each (lambda (state clause) (copy-clause state inst clause))
                                             clauses)))
                       (new Pair (first (Match scrutinee clauses)) (second state))))

        ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
        ((New _ _) (panic "internal error: named construction survived checking"))
        ((Ann inner type)
         (specializing state
                       ((inner (copy-expr inst inner)))
                       (new Pair (first (Ann inner (ground inst type))) (second state))))
        ((Handle effect implementations body)
         (specializing state ((implementations
                               (each (lambda (state entry) (copy-implementation state inst entry))
                                     implementations))
                              (body (copy-expr inst body)))
                       (new Pair (first (Handle effect implementations body)) (second state))))
        ((BoxAny inner)
         (specializing state ((inner (copy-expr inst inner)))
                       (new Pair (first (BoxAny inner)) (second state))))

        ((Downcast inner target)
         (specializing state ((inner (copy-expr inst inner)))
                       (new Pair (first (Downcast inner (ground inst target))) (second state))))))

    (define (copy-exprs (state State) (inst Instantiation) (exprs (List Expr)))
      (→ (Pair (List Expr) State))
      (each state (lambda (state expr) (copy-expr state inst expr)) exprs))

    (define (copy-clause (state State) (inst Instantiation) (clause Clause)) (→ (Pair Clause State))
      (specializing state ((body (copy-expr inst (● clause body))))
                    (new Pair
                      (first
                       (new Clause (pattern (copy-pattern inst (● clause pattern))) (body body)))
                      (second state))))

    (define (copy-implementation (state State) (inst Instantiation) (entry (Pair String Expr)))
      (→ (Pair (Pair String Expr) State))
      (specializing state ((value (copy-expr inst (● entry second))))
                    (new Pair
                      (first (new Pair (first (● entry first)) (second value)))
                      (second state))))

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
        ((Some (Defined _ _ )) (definition-reference state name types evidence type loc))
        ((Some (Method class _))
         (match evidence
           ((Cons (EvInstance instance instance-types subs) rest)
            (let ((class-arity
                   (length (● (program-class (specialization-program state) class) params)))
                  (target (instance-method state instance name)))
              ;; A record's own field instance names the field's
              ;; accessor, a builtin, which keeps its name.
              (match (program-value (specialization-program state) target)
                ((Some (Defined _ _ ))
                 (definition-reference state
                   target
                   (append instance-types (list-drop types class-arity))
                   (append subs rest) type loc))
                (_ (new Pair
                     (first (new Expr (term (Var target (Nil) (Nil))) (type type) (loc loc)))
                     (second state))))))
           (_ (panic "internal error: a method needs instance evidence"))))
        ((Some (Operation effect _)) (operation-reference state effect name type loc))
        (_ (new Pair
             (first (new Expr (term (Var name (Nil) (Nil))) (type type) (loc loc)))
             (second state)))))

    ;; ---- Operations ----

    ;; Performing an operation runs its Snail Scheme default when no handler
    ;; is in scope, so a use of the operation reaches the default too, which
    ;; is copied, or imported from the effect's library, under its own name.

    (define (operation-reference (state State) (effect String) (name String) (type Type) (loc Loc))
      (→ (Pair Expr State))
      (new Pair (first (new Expr (term (Var name (Nil) (Nil))) (type type) (loc loc)))
           (second (reach-operations state (list name) (Nil) loc))))

    ;; Forwarding a latent effect constructs closures for every operation of
    ;; that effect. Their defaults are reachable even if source names none of
    ;; those operations directly. Follow the same finite graph as emission.
    (define (reach-operations (state State) (pending (List String)) (seen (List String)) (loc Loc))
      (→ State)
      (match pending
        ((Nil) state)
        ((Cons name rest)
         (if (member? name seen) (reach-operations state rest seen loc)
             (match (program-value (specialization-program state) name)
               ((Some (Operation effect scheme))
                (let* ((state (reach-default state effect name loc))
                       (forwarded
                        (forwarded-operations (specialization-program state) effect scheme)))
                  (reach-operations state (append forwarded rest) (Cons name seen) loc)))
               (_ (panic "internal error: forwarding names an operation")))))))

    (define (reach-default (state State) (effect String) (operation String) (loc Loc)) (→ State)
      (match (assoc-ref (● (program-effect (specialization-program state) effect) defaults)
                        operation)
        ((Some function)
         (●
          (definition-reference state function (Nil) (Nil) (● (scheme-of state function) type) loc)
          second))
        ((None) state)))

    (define (forwarded-operations (program Program) (effect String) (scheme Scheme))
      (→ (List String))
      (concatenate
       (map (lambda (label)
              (match (table-ref (● program effects) label)
                ((Some info) (● info operations))
                ((None) (Nil)))) (operation-latent effect scheme))))

    (define (instance-method (state State) (instance String) (method String)) (→ String)
      (match (table-ref (● (● state input) instances) instance)
        ((Some found)
         (match (assoc-ref (● found methods) method)
           ((Some global) global)
           ((None) (panic "internal error: missing instance method"))))
        ((None) (panic "internal error: unknown instance"))))

    ;; Another library's monomorphic function stays an imported reference;
    ;; a generic function reserves a concrete specialization in this module.

    (define (definition-reference (state State) (name String)
              (types (List Type)) (evidence (List Evidence))
              (type Type) (loc Loc))
      (→ (Pair Expr State))
      (if (external? state name types)
          (new Pair (first (new Expr (term (Var name (Nil) (Nil))) (type type) (loc loc)))
               (second (import-definition state name (definition state name))))
          (specializing state ((spec (request name types evidence)))
                        (new Pair
                          (first (new Expr (term (Var spec (Nil) (Nil))) (type type) (loc loc)))
                          (second state)))))

    ;; Imports and emitted definitions share one identity table. In
    ;; particular, exposing an imported function must not enqueue a local
    ;; copy that a later reference could replace with an import.

    (define (import-definition (state State) (name String) (value Expr)) (→ State)
      (if (table-contains? (● state bindings) name)
          state
          (State-bindings-set state
                              (table-set (● state bindings) name
                                         (new Definition (type (● value type))

                                              (body (Imported)))))))

    (define (external? (state State) (name String) (types (List Type))) (→ Bool)
      (match (● state owner)
        ((Some owner) (and (null? types)
                           (not (string=? (name-owner name) owner))))
        ((None) #f)))

    ;; ---- Roots ----

    (define (new-state (input Specialization) (owner (Option String))) (→ State)
      (new State (input input) (owner owner)
           (control (control-effects (● (● input typed) program)))
           (bindings (empty-table)) (remaining 65536) (pending (Nil))))

    ;; The effects with a control operation, in order of their names.

    (define (control-effects (program Program)) (→ (List String))
      (list-sort string<?
                 (map (lambda (record) (● record name))
                      (filter (lambda (effect) (not (null? (● effect control))))
                              (table-values (● program effects))))))

    ;; Library modules export monomorphic functions.
    ;; Whole programs keep only definitions reached from an entry or exposure.
    (define (start-specialization (state State) (items (List Item))) (→ (Pair (List String) State))
      (specializing state ((exports (each root-item items)))
                    (new Pair (first (concatenate exports)) (second state))))

    (define (root-item (state State) (item Item)) (→ (Pair (List String) State))
      (match item
        ((Expose name _ _) (new Pair (first (Nil)) (second (requested state name))))
        ((Entry name _) (new Pair (first (Nil)) (second (requested state name))))
        ((Define name value)
         (if (null? (● (scheme-of state name) vars))
             (match (● state owner)
               ((Some _) (new Pair (first (list name)) (second (requested state name))))
               ((None) (new Pair (first (Nil)) (second state))))
             (new Pair (first (Nil)) (second state))))))

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
                ))

      ;; Grounding keeps a row's control effects, in name order, and drops
      ;; the rest, wherever the row sits.
      (define test-control-rows
        (lambda ()
          (let ((row (TRow (list "mut" "gen") (Some (TRow (list "abort" "console") (None)))))
                (control (list "abort" "gen")))
            (expect (erase-rows control row) (TRow (list "abort" "gen") (None)))
            (expect (erase-rows (Nil) row) (empty-row))
            (expect (erase-rows control (TFun (list (TCon "I64" (Nil))) (TCon "Unit" (Nil)) row))
                    (TFun (list (TCon "I64" (Nil)))
                          (TCon "Unit" (Nil))
                          (TRow (list "abort" "gen") (None)))))))

      ;; Without control effects a name is what `type-key` gives, so pure
      ;; code keeps its names; with one, the name says so.
      (define test-spec-keys
        (lambda () (let ((pure (TFun (list (TCon "I64" (Nil))) (TCon "I64" (Nil)) (empty-row)))
                         (control
                          (TFun (list (TCon "I64" (Nil)))
                                (TCon "I64" (Nil))
                                (TRow (list "gen") (None)))))
                     (expect (spec-key pure) (type-key pure))
                     (expect (spec-key (TCon "List" (list pure)))
                             (type-key (TCon "List" (list pure))))
                     (expect (spec-key control) "fn<I64->I64>!gen")
                     (expect (spec-key (empty-row)) "row"))))))))
