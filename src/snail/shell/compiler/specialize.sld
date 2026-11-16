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
   specialization-definitions
   start-specialization
   complete-specializations)
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
       (control (List String))
       (bindings (Table Binding))))

    (record Binding
      ((type Type)))

    ;; Requests reserve names before visiting bodies, so recursive calls
    ;; terminate. A recipe becomes a concrete body once.
    ;; Original bodies survive until preparation has checked every batch.
    (record State
      ((input Specialization)
       (control (List String))
       (bindings (Table Definition))
       (remaining I64)
       (pending (List String))))

    ;; The registry owns each executable identity and its signature. A body
    ;; is a recipe or its completed instantiation.
    (record Definition
      ((type Type)
       (body Body)))

    (enum Body
      (SourceRecipe
       ((name String)
        (types (List Type))
        (evidence (List Evidence))))
      (SourceBody
       ((value Expr))))

    ;; The types and evidence that replace a definition's quantified variables
    ;; and requirements while it is copied.
    ;; `control` names the program's control effects, the ones a ground row
    ;; keeps, in order of their names.
    (record Instantiation
      ((vars Substitution)
       (evidence (List Evidence))
       (control (List String))))

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
      (● (request state name (Nil) (Nil)) second))

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
           (threading state ((then (State-pending-set rest))
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
           (control (● state control))
           (bindings (fold-left (lambda (bindings name)
                                  (table-set bindings
                                             name
                                             (new Binding (type (● (binding-of state name) type)))))
                                (empty-table) (table-keys (● state bindings))))))

    ;; A read-only snapshot of original source instantiations. Missing
    ;; bodies mean discovery was not closed before analysis.

    (define (specialization-definitions (state State)) (→ (Table Expr))
      (fold-left (lambda (bodies name)
                   (match (● (binding-of state name) body)
                     ((SourceBody value) (table-set bodies name value))
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
          (term (threading state ((copied (copy-term inst term)))
                           (new Pair
                             (first (new Expr (term copied) (type type) (loc loc)))
                             (second state)))))))

    ;; A copy requests the specializations it references, so the copies of
    ;; sibling terms are steps in the order they are written.

    (define (copy-term (state State) (inst Instantiation) (term Term)) (→ (Pair Term State))
      (match term
        ((Lit value) (new Pair (first (Lit value)) (second state)))
        ((Var name types evidence) (new Pair (first (Var name types evidence)) (second state)))
        ((Lambda params body)
         (threading state
                    ((body (copy-expr inst body)))
                    (new Pair (first (Lambda params body)) (second state))))
        ((App callee args)
         (threading state ((callee (copy-expr inst callee)) (args (copy-exprs inst args)))
                    (new Pair (first (App callee args)) (second state))))
        ((If test consequent alternative)
         (threading state ((test (copy-expr inst test))
                           (consequent (copy-expr inst consequent))
                           (alternative (copy-expr inst alternative)))
                    (new Pair (first (If test consequent alternative)) (second state))))
        ((Let name value body)
         (threading state ((value (copy-expr inst value)) (body (copy-expr inst body)))
                    (new Pair (first (Let name value body)) (second state))))
        ((Seq first rest)
         (threading state ((first (copy-expr inst first)) (rest (copy-expr inst rest)))
                    (new Pair (first (Seq first rest)) (second state))))
        ((Match scrutinee clauses)
         (threading state ((scrutinee (copy-expr inst scrutinee))
                           (clauses (each (lambda (state clause) (copy-clause state inst clause))
                                          clauses)))
                    (new Pair (first (Match scrutinee clauses)) (second state))))

        ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
        ((New _ _) (panic "internal error: named construction survived checking"))
        ((Ann inner type)
         (threading state
                    ((inner (copy-expr inst inner)))
                    (new Pair (first (Ann inner (ground inst type))) (second state))))
        ((Handle effect implementations body)
         (threading state ((implementations
                            (each (lambda (state entry) (copy-implementation state inst entry))
                                  implementations))
                           (body (copy-expr inst body)))
                    (new Pair (first (Handle effect implementations body)) (second state))))
        ((BoxAny inner)
         (threading state ((inner (copy-expr inst inner)))
                    (new Pair (first (BoxAny inner)) (second state))))

        ((Downcast inner target)
         (threading state ((inner (copy-expr inst inner)))
                    (new Pair (first (Downcast inner (ground inst target))) (second state))))))

    (define (copy-exprs (state State) (inst Instantiation) (exprs (List Expr)))
      (→ (Pair (List Expr) State))
      (each state (lambda (state expr) (copy-expr state inst expr)) exprs))

    (define (copy-clause (state State) (inst Instantiation) (clause Clause)) (→ (Pair Clause State))
      (threading state ((body (copy-expr inst (● clause body))))
                 (new Pair
                   (first
                    (new Clause (pattern (copy-pattern inst (● clause pattern))) (body body)))
                   (second state))))

    (define (copy-implementation (state State) (inst Instantiation) (entry (Pair String Expr)))
      (→ (Pair (Pair String Expr) State))
      (threading state ((value (copy-expr inst (● entry second))))
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
        ((Some (Defined _ _)) (definition-reference state name types evidence type loc))
        ((Some (Method class _))
         (match evidence
           ((Cons (EvInstance instance instance-types subs) rest)
            (let ((class-arity
                   (length (● (program-class (specialization-program state) class) params))))
              (definition-reference state
                (instance-method state instance name)
                (append instance-types (list-drop types class-arity))
                (append subs rest) type loc)))
           (_ (panic "internal error: a method needs instance evidence"))))
        ;; An operation, like a builtin, keeps its name: a handler answers
        ;; it, and nothing else is reached through it.
        (_ (new Pair
             (first (new Expr (term (Var name (Nil) (Nil))) (type type) (loc loc)))
             (second state)))))

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
      (threading state ((spec (request name types evidence)))
                 (new Pair
                   (first (new Expr (term (Var spec (Nil) (Nil))) (type type) (loc loc)))
                   (second state))))

    ;; ---- Roots ----

    (define (new-state (input Specialization)) (→ State)
      (new State (input input)
           (control (control-effects (● (● input typed) program)))
           (bindings (empty-table)) (remaining 65536) (pending (Nil))))

    ;; The effects with a control operation, in order of their names.

    (define (control-effects (program Program)) (→ (List String))
      (list-sort string<?
                 (map (lambda (record) (● record name))
                      (filter (lambda (effect) (not (null? (● effect control))))
                              (table-values (● program effects))))))

    ;; A program keeps only the definitions reached from an entry or an
    ;; exposure.
    (define (start-specialization (state State) (items (List Item))) (→ State)
      (fold-left (lambda (state item)
                   (match item
                     ((Expose name _ _) (requested state name))
                     ((Entry _ start _) (requested state start))
                     ((Define _ _) state)))
                 state
                 items))

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
            (expect (erase-rows (Nil) row) empty-row)
            (expect (erase-rows control (TFun (list (TCon "I64" (Nil))) (TCon "Unit" (Nil)) row))
                    (TFun (list (TCon "I64" (Nil)))
                          (TCon "Unit" (Nil))
                          (TRow (list "abort" "gen") (None)))))))

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
