;; Typed program to monomorphic program. Starting from the statements and
;; top-level values, each reachable definition is copied once per ground type
;; instantiation. Method references become references to the instance method
;; their evidence names, so no instance is selected twice; a drop or a
;; clone becomes what its ground type runs, glue among it, made here. A
;; library can also be specialized alone, as one module of a program linked
;; when it runs.
(define-library (snail shell compiler mono)
  (export
   Mono
   Mono-program
   Mono-items
   Mono-externals
   Mono-exported
   Mono-input
   Mono-owner
   drop-functions
   Specialization
   Specialization-definitions
   prepare-specialization
   control-effects
   monomorphize
   monomorphize-library)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (snail shell compiler check))
  (begin

    ;; ---- Specialization state ----

    ;; A library's module also lists the definitions of other libraries it
    ;; refers to, which it imports, and the names it exports.
    (struct Mono
      ((program Program)
       (items (List Item))
       (externals (Table Expr))
       (exported (List String))
       (input (Option Specialization))
       (owner (Option String))))

    ;; Checked facts shared by every library emitted in one build. Preparing
    ;; them once keeps lookup independent of each library's request lifetime.
    (struct Specialization
      ((typed Typed)
       (instances (Table Instance))
       (definitions (Table Expr))))

    (: prepare-specialization (-> Typed Specialization))
    (define (prepare-specialization typed)
      (let ((instances (fold-left (lambda (table instance)
                                    (table-set table (Instance-name instance) instance))
                                  empty-table
                                  (concatenate
                                   (table-values (Program-instances (Typed-program typed)))))))
        (Specialization typed instances (item-definitions (Typed-items typed)))))

    ;; Every emission owns fresh requests, copies in creation order, and
    ;; imports. `owner` names a library, or None for the whole program.
    ;; `done` names every specialization and glue function asked for so
    ;; far; `pending` holds the requests not yet copied, newest first; and
    ;; `glue` the glue made so far, newest first, which belongs to no
    ;; definition, so each module emits its own. The state is a value:
    ;; each step that can request a copy takes it and hands back the next,
    ;; so requests, and the copies they produce, come in the order the
    ;; steps are written, on either host.
    (struct State
      ((input Specialization)
       (owner (Option String))
       (control (List String))
       (done (Table String))
       (specialized (Table (List Item)))
       (pending (List Request))
       (externals (Table Expr))
       (glue (List Item))))

    (struct Request
      ((name String)
       (spec String)
       (types (List Type))
       (evidence (List Evidence))))

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
            (-> State (-> State A (Pair B State)) (List A) (Pair (List B) State))))
    (define (each state step items)
      (let ((done (fold-left (lambda (done item)
                               (match (step (Pair-second done) item)
                                 ((Pair value state) (Pair (Cons value (Pair-first done)) state))))
                             (Pair (Nil) state) items)))
        (Pair (reverse (Pair-first done)) (Pair-second done))))

    (: program-of (-> State Program))
    (define (program-of state)
      (Typed-program (Specialization-typed (State-input state))))

    (: definition (-> State String Expr))
    (define (definition state name)
      (match (table-ref (Specialization-definitions (State-input state)) name)
        ((Some value) value)
        ((None) (panic (string-append "internal error: no definition " name)))))

    (: scheme-of (-> State String Scheme))
    (define (scheme-of state name)
      (definition-scheme (Specialization-typed (State-input state)) name))

    ;; ---- Requests ----

    ;; The specialized name, queueing the copy the first time. Under coherent
    ;; instances the types determine the evidence.
    (: request (-> State String (List Type) (List Evidence) (Pair String State)))
    (define (request state name types evidence)
      (let ((spec (if (null? types)
                      name
                      (string-append name "<" (string-join (map spec-key types) ",") ">"))))
        (Pair spec
              (if (table-contains? (State-done state) spec)
                  state
                  (State-pending-set (State-done-set state (table-set (State-done state) spec spec))
                                     (Cons (Request name spec types evidence)
                                           (State-pending state)))))))

    ;; The state once a monomorphic definition's copy is requested.
    (: requested (-> State String State))
    (define (requested state name)
      (Pair-second (request state name (Nil) (Nil))))

    (: run-requests (-> State State))
    (define (run-requests state)
      (match (State-pending state)
        ((Cons request rest)
         (run-requests (specialize-request (State-pending-set state rest) request)))
        ((Nil) state)))

    ;; A copy is added after the definition's earlier copies, read once it
    ;; is made, since making it can request another copy of the same
    ;; definition.
    (: specialize-request (-> State Request State))
    (define (specialize-request state request)
      (let* ((name (Request-name request))
             (scheme (scheme-of state name))
             (inst (Instantiation (zip (Scheme-vars scheme) (Request-types request))
                                  (Request-evidence request)
                                  (State-control state))))
        (specializing state ((value (copy-expr inst (definition state name))))
                      (State-specialized-set state
                                             (table-set (State-specialized state)
                                                        name
                                                        (append (copies-of state name)
                                                                (list (Define (Request-spec request)
                                                                        value))))))))

    (: copies-of (-> State String (List Item)))
    (define (copies-of state name)
      (match (table-ref (State-specialized state) name)
        ((Some copies) copies)
        ((None) (Nil))))

    ;; ---- Copying ----

    ;; Effects are erased here except control effects, because a call that
    ;; may reach a control operation compiles differently from one that
    ;; cannot; specializations differ by their types and their control rows.
    (: ground (-> Instantiation Type Type))
    (define (ground inst type)
      (erase-rows (Instantiation-control inst) (substitute (Instantiation-vars inst) type)))

    (: erase-rows (-> (List String) Type Type))
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
    (: control-row (-> (List String) Type Type))
    (define (control-row control row)
      (let ((labels (row-labels row)))
        (TRow (filter (lambda (effect) (member? effect labels)) control) (None))))

    (: row-labels (-> Type (List String)))
    (define (row-labels row)
      (match row
        ((TRow labels (Some tail)) (append labels (row-labels tail)))
        ((TRow labels (None)) labels)
        (_ (Nil))))

    ;; A specialization's name keys its types as `type-key` does, plus the
    ;; control effects in their rows. A row without one keys as before, so
    ;; code that cannot reach a control operation keeps its names.
    (: spec-key (-> Type String))
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

    (: control-suffix (-> Type String))
    (define (control-suffix row)
      (string-concatenate (map (lambda (effect) (string-append "!" effect)) (row-labels row))))

    (: ground-evidence (-> Instantiation Evidence Evidence))
    (define (ground-evidence inst evidence)
      (match evidence
        ((EvParam index) (list-ref (Instantiation-evidence inst) index))
        ((EvInstance instance types subs)
         (EvInstance instance
                     (map (lambda (type) (ground inst type)) types)
                     (map (lambda (sub) (ground-evidence inst sub)) subs)))
        ((EvDerived plan) (EvDerived plan))
        ((EvHole _) (panic "internal error: unsolved evidence"))))

    (: copy-expr (-> State Instantiation Expr (Pair Expr State)))
    (define (copy-expr state inst expr)
      (let ((type (ground inst (Expr-type expr))) (loc (Expr-loc expr)))
        (match (Expr-term expr)
          ((Var name types evidence)
           (reference state
                      name
                      (map (lambda (t) (ground inst t)) types)
                      (map (lambda (e) (ground-evidence inst e)) evidence)
                      type
                      loc))
          (term (specializing state
                              ((copied (copy-term inst term)))
                              (Pair (Expr copied type loc) state))))))

    ;; A copy requests the specializations it references, so the copies of
    ;; sibling terms are steps in the order they are written.
    (: copy-term (-> State Instantiation Term (Pair Term State)))
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
        ((TypeTest inner target)
         (specializing state ((inner (copy-expr inst inner)))
                       (Pair (TypeTest inner (ground inst target)) state)))))

    (: copy-exprs (-> State Instantiation (List Expr) (Pair (List Expr) State)))
    (define (copy-exprs state inst exprs)
      (each state (lambda (state expr) (copy-expr state inst expr)) exprs))

    (: copy-clause (-> State Instantiation Clause (Pair Clause State)))
    (define (copy-clause state inst clause)
      (specializing state ((body (copy-expr inst (Clause-body clause))))
                    (Pair (Clause (copy-pattern inst (Clause-pattern clause)) body) state)))

    (: copy-implementation
       (-> State Instantiation (Pair String Expr) (Pair (Pair String Expr) State)))
    (define (copy-implementation state inst entry)
      (specializing state ((value (copy-expr inst (Pair-second entry))))
                    (Pair (Pair (Pair-first entry) value) state)))

    (: copy-pattern (-> Instantiation Pattern Pattern))
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
    (: reference (-> State String (List Type) (List Evidence) Type Loc (Pair Expr State)))
    (define (reference state name types evidence type loc)
      (match (program-value (program-of state) name)
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
                       (length (Class-params (program-class (program-of state) class))))
                      (target (instance-method state instance name)))
                  ;; A struct's own field instance names the field's
                  ;; accessor, a builtin, which keeps its name.
                  (match (program-value (program-of state) target)
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
    (: lifecycle-reference (-> State String String Type (Option Plan) Type Loc (Pair Expr State)))
    (define (lifecycle-reference state class method subject charged type loc)
      (match (Pair class subject)
        ;; Dropping a FnOnce runs the dropper its closure carries, which
        ;; drops what it captured (wasm.sld, `drop-once`).
        ((Pair _ (TCon "FnOnce" _))
         (if (string=? class drop-class)
             (Pair (Expr (Var "prim:drop-once" (Nil) (Nil)) type loc) state)
             (planned-reference state class method subject charged type loc)))
        (_ (planned-reference state class method subject charged type loc))))

    (: planned-reference (-> State String String Type (Option Plan) Type Loc (Pair Expr State)))
    (define (planned-reference state class method subject charged type loc)
      (match (covered-plan (lifecycle-plan (program-of state) class (Nil) subject) charged subject)
        ((Trivial)
         (if (string=? class drop-class)
             (Pair (Expr (Var "prim:discard" (Nil) (Nil)) type loc) state)
             (glue-reference state
                             "share"
                             subject
                             type
                             loc
                             (lambda (state) (Pair (share-function subject loc) state)))))
        ((Implemented instance)
         (definition-reference state
           (instance-method state (Instance-name instance) method)
           (instance-arguments instance subject)
           (Nil)
           type
           loc))
        ((Glue)
         (if (string=? class drop-class)
             (glue-reference state "drop" subject type loc
                             (lambda (state) (drop-function state method subject loc)))
             (glue-reference state "clone" subject type loc
                             (lambda (state) (clone-function state method subject loc)))))
        ((Refused reason)
         (panic (string-append "internal error: the checker allowed this: " reason)))))

    (: charged-plan (-> (List Evidence) (Option Plan)))
    (define (charged-plan evidence)
      (match evidence
        ((Cons (EvDerived plan) _) plan)
        (_ (panic "internal error: a drop or a clone has derived evidence"))))

    (: covered-plan (-> Plan (Option Plan) Type Plan))
    (define (covered-plan plan charged subject)
      (if (plan-covers? charged plan)
          plan
          (panic (string-append "internal error: releasing "
                                (type->string subject)
                                " runs more than the checker charged"))))

    ;; The instance's variables, as the ground type binds them in its head.
    ;; The row its head ends with, if it names one, is left empty: a drop or
    ;; a clone performs no control effect, and only those specialize code.
    (: instance-arguments (-> Instance Type (List Type)))
    (define (instance-arguments instance subject)
      (let ((bindings (instance-bindings instance subject)))
        (map (lambda (var)
               (match (assoc-ref bindings var)
                 ((Some type) type)
                 ((None) empty-row)))
             (Instance-vars instance))))

    ;; Glue is a function of one ground type, made the first time a drop or
    ;; a clone needs it, and named before it is made, so that the drops and
    ;; clones it makes of the fields reach their own glue, its own for a
    ;; recursive type. It is built ground, so nothing copies it.
    (: glue-reference
       (-> State String Type Type Loc (-> State (Pair Expr State)) (Pair Expr State)))
    (define (glue-reference state kind subject type loc make)
      (let ((name (string-append "glue:" kind "<" (spec-key subject) ">")))
        (Pair (Expr (Var name (Nil) (Nil)) type loc)
              (if (table-contains? (State-done state) name)
                  state
                  (with-glue (State-done-set state (table-set (State-done state) name name))
                             name
                             make)))))

    ;; The state once the glue `make` builds is added, after the glue it
    ;; needed made first.
    (: with-glue (-> State String (-> State (Pair Expr State)) State))
    (define (with-glue state name make)
      (specializing state ((value (make)))
                    (State-glue-set state (Cons (Define name value) (State-glue state)))))

    ;; Drop glue matches the value apart and drops each linear immutable
    ;; field, skipping the rest.
    (: drop-function (-> State String Type Loc (Pair Expr State)))
    (define (drop-function state method dropped loc)
      (glue-lambda state
                   dropped
                   unit-type
                   (lambda (state case) (drop-clause state method dropped case loc))
                   loc))

    ;; One case's clause binds each field glue drops to a local of its own
    ;; and skips the others, then drops what it bound, in field order.
    (: drop-clause (-> State String Type Case Loc (Pair Clause State)))
    (define (drop-clause state method dropped case loc)
      (let* ((program (program-of state)) (released (glue-fields program (Nil) dropped case)))
        (specializing state
                      ((drops (each (lambda (state field) (glue-drop state method case field loc))
                                    released)))
                      (Pair (Clause (PCon (Case-name case)
                                          (map-indexed (lambda (index type)
                                                         (if (any? (lambda (entry)
                                                                     (= (Pair-first entry) index))
                                                                   released)
                                                             (PVar (glue-local case index) type)
                                                             (PWild type)))
                                                       (field-types program dropped case))
                                          dropped)
                                    (in-sequence drops loc))
                            state))))

    (: glue-drop (-> State String Case (Pair I64 Type) Loc (Pair Expr State)))
    (define (glue-drop state method case field loc)
      (let ((type (Pair-second field)))
        (specializing state ((callee (lifecycle-reference drop-class
                                                          method
                                                          type
                                                          (None)
                                                          (TFun (list type) unit-type empty-row)
                                                          loc)))
                      (Pair (Expr (App callee
                                       (list
                                        (Expr (Var (glue-local case (Pair-first field)) (Nil) (Nil))
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
    (: clone-function (-> State String Type Loc (Pair Expr State)))
    (define (clone-function state method cloned loc)
      (glue-lambda state
                   cloned
                   (pair-type cloned)
                   (lambda (state case) (clone-clause state method cloned case loc))
                   loc))

    (: clone-clause (-> State String Type Case Loc (Pair Clause State)))
    (define (clone-clause state method cloned case loc)
      (let* ((program (program-of state))
             (types (field-types program cloned case))
             (linear (glue-fields program (Nil) cloned case)))
        (specializing state
                      ((body
                        (clone-fields method cloned case types (map Pair-first linear) linear loc)))
                      (Pair (Clause (PCon (Case-name case)
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
       (-> State
           String
           Type
           Case
           (List Type)
           (List I64)
           (List (Pair I64 Type))
           Loc
           (Pair Expr State)))
    (define (clone-fields state method cloned case types halves left loc)
      (match left
        ((Nil)
         (Pair (pair-of cloned
                        (rebuilt cloned case types halves "a" loc)
                        (rebuilt cloned case types halves "b" loc)
                        loc)
               state))
        ((Cons field rest)
         (let ((index (Pair-first field)) (type (Pair-second field)))
           (specializing state ((halved (field-clone method case index type loc))
                                (body (clone-fields method cloned case types halves rest loc)))
                         (Pair
                          (Expr (Match halved (list (Clause (halves-pattern case index type) body)))
                                (pair-type cloned)
                                loc)
                          state))))))

    ;; Takes a field's clone apart into a local for each half.
    (: halves-pattern (-> Case I64 Type Pattern))
    (define (halves-pattern case index type)
      (PCon pair-name
            (list (PVar (half-local case index "a") type) (PVar (half-local case index "b") type))
            (pair-type type)))

    (: field-clone (-> State String Case I64 Type Loc (Pair Expr State)))
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
    (: rebuilt (-> Type Case (List Type) (List I64) String Loc Expr))
    (define (rebuilt cloned case types halves half loc)
      (Expr (App (Expr (Var (Case-name case) (Nil) (Nil)) (TFun types cloned empty-row) loc)
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
    (: share-function (-> Type Loc Expr))
    (define (share-function shared loc)
      (let ((value (Expr (Var "glue%value" (Nil) (Nil)) shared loc)))
        (Expr (Lambda (list "glue%value") (pair-of shared value value loc) #f)
              (TFun (list shared) (pair-type shared) empty-row)
              loc)))

    ;; A function of one value of `subject` that matches it apart, with a
    ;; clause for each case.
    (: glue-lambda (-> State Type Type (-> State Case (Pair Clause State)) Loc (Pair Expr State)))
    (define (glue-lambda state subject result clause loc)
      (let ((data (program-type (program-of state) (type-name subject)))
            (value (Expr (Var "glue%value" (Nil) (Nil)) subject loc)))
        (specializing state ((clauses (each clause (DataType-cases data))))
                      (Pair
                       (Expr (Lambda (list "glue%value") (Expr (Match value clauses) result loc) #f)
                             (TFun (list subject) result empty-row)
                             loc)
                       state))))

    (: type-name (-> Type String))
    (define (type-name type)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: glue takes data apart"))))

    (: pair-name String)
    (define pair-name "snail.core.base:Pair")

    (: pair-type (-> Type Type))
    (define (pair-type type)
      (TCon pair-name (list type type)))

    (: pair-of (-> Type Expr Expr Loc Expr))
    (define (pair-of type first second loc)
      (Expr (App (Expr (Var pair-name (Nil) (Nil))
                       (TFun (list type type) (pair-type type) empty-row)
                       loc)
                 (list first second))
            (pair-type type)
            loc))

    ;; Each case's fields have locals of their own, since the clauses of a
    ;; function share its locals, and so does each half of a clone.
    (: glue-local (-> Case I64 String))
    (define (glue-local case index)
      (string-append "glue%" (i64->string (Case-tag case)) "%" (i64->string index)))

    (: half-local (-> Case I64 String String))
    (define (half-local case index half)
      (string-append (glue-local case index) "%" half))

    ;; The drops in order, the last one in tail position, so glue for a
    ;; list runs in constant stack.
    (: in-sequence (-> (List Expr) Loc Expr))
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
    (: operation-reference (-> State String String Type Loc (Pair Expr State)))
    (define (operation-reference state effect name type loc)
      (Pair (Expr (Var name (Nil) (Nil)) type loc)
            (match (assoc-ref (Effect-defaults (program-effect (program-of state) effect)) name)
              ((Some function)
               (Pair-second (definition-reference state
                              function
                              (Nil)
                              (Nil)
                              (Scheme-type (scheme-of state function))
                              loc)))
              (_ state))))

    (: instance-method (-> State String String String))
    (define (instance-method state instance method)
      (match (table-ref (Specialization-instances (State-input state)) instance)
        ((Some found)
         (match (assoc-ref (Instance-methods found) method)
           ((Some global) global)
           ((None) (panic "internal error: missing instance method"))))
        ((None) (panic "internal error: unknown instance"))))

    ;; A definition whose value is just another reference, such as
    ;; `(define + i64-add)`, is replaced by its target. Another library's
    ;; monomorphic definition stays a reference, which its module imports.
    (: definition-reference
       (-> State String (List Type) (List Evidence) Type Loc (Pair Expr State)))
    (define (definition-reference state name types evidence type loc)
      (let ((value (definition state name)))
        (match (Expr-term value)
          ((Var _ _ _)
           (let ((scheme (scheme-of state name)))
             (copy-expr state
                        (Instantiation (zip (Scheme-vars scheme) types)
                                       evidence
                                       (State-control state))
                        value)))
          (_ (if (external? state name types)
                 (Pair (Expr (Var name (Nil) (Nil)) type loc)
                       (State-externals-set state (table-set (State-externals state) name value)))
                 (specializing state ((spec (request name types evidence)))
                               (Pair (Expr (Var spec (Nil) (Nil)) type loc) state)))))))

    (: external? (-> State String (List Type) Bool))
    (define (external? state name types)
      (match (State-owner state)
        ((Some owner) (and (null? types) (not (string=? (name-owner name) owner))))
        ((None) #f)))

    ;; ---- Programs ----

    (: new-state (-> Specialization (Option String) State))
    (define (new-state input owner)
      (State input
             owner
             (control-effects (Typed-program (Specialization-typed input)))
             empty-table
             empty-table
             (Nil)
             empty-table
             (Nil)))

    ;; The effects with a control operation, in order of their names.
    (: control-effects (-> Program (List String)))
    (define (control-effects program)
      (list-sort string<?
                 (map Effect-name (filter (lambda (effect) (not (null? (Effect-control effect))))
                                          (table-values (Program-effects program))))))

    ;; Statements and monomorphic top-level values are roots, so their
    ;; initializers run even when nothing refers to them. Functions are
    ;; copied only when reached.
    (: monomorphize (-> Typed Mono))
    (define (monomorphize typed)
      (let* ((items (Typed-items typed)) (state (new-state (prepare-specialization typed) (None))))
        (specializing state ((statements (each root-item items)) (then (run-requests)))
                      (finish-mono state
                                   (concatenate
                                    (map (lambda (pair)
                                           (output-items state
                                                         (Pair-first pair)
                                                         (Pair-second pair)))
                                         (zip items statements)))
                                   (Nil)))))

    ;; One library's items, `items` among the program's. Every monomorphic
    ;; definition is a root, since any module may import it. Copies of other
    ;; libraries' definitions, the generic ones this library uses, come first,
    ;; in program order, as those libraries come before it.
    (: monomorphize-library (-> Specialization String (List Item) Mono))
    (define (monomorphize-library input owner items)
      (let ((typed (Specialization-typed input)) (state (new-state input (Some owner))))
        (specializing state ((exported (library-roots items))
                             (statements (each root-item items))
                             (then (run-requests)))
                      (finish-mono state
                                   (append (concatenate
                                            (map (lambda (item) (foreign-copies state owner item))
                                                 (Typed-items typed)))
                                           (concatenate (map (lambda (pair)
                                                               (output-items state
                                                                             (Pair-first pair)
                                                                             (Pair-second pair)))
                                                             (zip items statements))))
                                   exported))))

    (: finish-mono (-> State (List Item) (List String) Mono))
    (define (finish-mono state items exported)
      (Mono (program-of state)
            (append (reverse (State-glue state)) items)
            (State-externals state)
            exported
            (Some (State-input state))
            (State-owner state)))

    ;; ---- Drops on demand ----

    ;; The control pass gives each frame and each once lambda a dropper for
    ;; the linear values it holds (control.sld, "Droppers"), and asks here
    ;; for the drop of each ground type: an instance's method, glue, or a
    ;; primitive, by `lifecycle-reference`. The glue and the copies that
    ;; makes join the module's items, and its externals the module's.
    (: drop-functions (-> Mono (List Type) Loc (Pair (Table Expr) Mono)))
    (define (drop-functions mono types loc)
      (let ((state (State-done-set (new-state (mono-input mono) (Mono-owner mono))
                                   (item-names (Mono-items mono)))))
        (specializing state ((drops (each (lambda (state type) (drop-entry state type loc)) types))
                             (then (run-requests)))
                      (Pair (fold-left (lambda (table entry)
                                         (table-set table (Pair-first entry) (Pair-second entry)))
                                       empty-table
                                       drops)
                            (Mono (Mono-program mono)
                                  (append (reverse (State-glue state))
                                          (append (concatenate
                                                   (table-values (State-specialized state)))
                                                  (Mono-items mono)))
                                  (fold-left (lambda (table name)
                                               (match (table-ref (State-externals state) name)
                                                 ((Some value) (table-set table name value))
                                                 ((None) table)))
                                             (Mono-externals mono)
                                             (table-keys (State-externals state)))
                                  (Mono-exported mono)
                                  (Mono-input mono)
                                  (Mono-owner mono))))))

    ;; A module made from a specialization has one; the control module,
    ;; which holds no code, has none and asks for no drops.
    (: mono-input (-> Mono Specialization))
    (define (mono-input mono)
      (match (Mono-input mono)
        ((Some input) input)
        ((None) (panic "internal error: a module without a specialization asked for drops"))))

    (: drop-entry (-> State Type Loc (Pair (Pair String Expr) State)))
    (define (drop-entry state type loc)
      (specializing state ((drop (lifecycle-reference drop-class
                                                      (drop-method state)
                                                      type
                                                      (None)
                                                      (TFun (list type) unit-type empty-row)
                                                      loc)))
                    (Pair (Pair (type-key type) drop) state)))

    ;; The Drop class's one method, by its global name, which an instance
    ;; implements under.
    (: drop-method (-> State String))
    (define (drop-method state)
      (match (Class-methods (program-class (program-of state) drop-class))
        ((Cons method _) method)
        ((Nil) (panic "internal error: Drop has a method"))))

    (: item-names (-> (List Item) (Table String)))
    (define (item-names items)
      (fold-left (lambda (table item)
                   (match item
                     ((Define name _) (table-set table name name))
                     (_ table)))
                 empty-table
                 items))

    ;; Requests the library's monomorphic functions, which `root-item` leaves
    ;; until something reaches them, and returns every name it exports.
    (: library-roots (-> State (List Item) (Pair (List String) State)))
    (define (library-roots state items)
      (specializing state ((roots (each library-root items)))
                    (Pair (concatenate roots) state)))

    (: library-root (-> State Item (Pair (List String) State)))
    (define (library-root state item)
      (match item
        ((Define name value)
         (if (and (null? (Scheme-vars (scheme-of state name))) (not (alias-expr? value)))
             (Pair (list name) (requested state name))
             (Pair (Nil) state)))
        (_ (Pair (Nil) state))))

    (: foreign-copies (-> State String Item (List Item)))
    (define (foreign-copies state owner item)
      (match item
        ((Define name _) (if (string=? (name-owner name) owner) (Nil) (copies-of state name)))
        (_ (Nil))))

    ;; A statement is copied now; a monomorphic value is requested.
    (: root-item (-> State Item (Pair (Option Item) State)))
    (define (root-item state item)
      (match item
        ((Expose name _ _ _) (Pair (None) (requested state name)))
        ((Do expr)
         (specializing state
                       ((copied (copy-expr (Instantiation (Nil) (Nil) (State-control state)) expr)))
                       (Pair (Some (Do copied)) state)))
        ((Define name value)
         (let ((scheme (scheme-of state name)))
           (if
            (and (null? (Scheme-vars scheme)) (not (lambda-expr? value)) (not (alias-expr? value)))
            (Pair (None) (requested state name))
            (Pair (None) state))))))

    ;; Each definition's copies take its place in program order.
    (: output-items (-> State Item (Option Item) (List Item)))
    (define (output-items state item statement)
      (match item
        ((Define name _) (copies-of state name))
        ((Do _) (match statement ((Some statement) (list statement)) ((None) (Nil))))
        ((Expose _ _ _ _) (list item))))

    (: alias-expr? (-> Expr Bool))
    (define (alias-expr? expr)
      (match (Expr-term expr)
        ((Var _ _ _) #t)
        (_ #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-mono)
    (import
     (snail stage0 testing))
    (begin
      (define (test-mono)
        (test-control-rows)
        (test-spec-keys))

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
