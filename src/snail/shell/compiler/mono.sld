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
       (exported (List String))))

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
    ;; `glue` holds the glue made so far, newest first, which belongs
    ;; to no definition, so each module emits its own.
    (struct State
      ((input Specialization)
       (done (Ref (Table String)))
       (specialized (Ref (Table (List Item))))
       (pending (Ref (List Request)))
       (owner (Option String))
       (externals (Ref (Table Expr)))
       (control (List String))
       (glue (Ref (List Item)))))

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
    (: request! (-> State String (List Type) (List Evidence) String ! mut))
    (define (request! state name types evidence)
      (let ((spec (if (null? types)
                      name
                      (string-append name "<" (string-join (map spec-key types) ",") ">"))))
        (unless (table-contains? (ref-get (State-done state)) spec)
          (ref-set! (State-done state) (table-set (ref-get (State-done state)) spec spec))
          (ref-set! (State-pending state)
                    (Cons (Request name spec types evidence) (ref-get (State-pending state)))))
        spec))

    (: run-requests! (-> State Unit ! mut))
    (define (run-requests! state)
      (match (ref-get (State-pending state))
        ((Cons request rest)
         (ref-set! (State-pending state) rest)
         (specialize-request! state request)
         (run-requests! state))
        ((Nil) (unit))))

    (: specialize-request! (-> State Request Unit ! mut))
    (define (specialize-request! state request)
      (let* ((name (Request-name request))
             (scheme (scheme-of state name))
             (inst (Instantiation (zip (Scheme-vars scheme) (Request-types request))
                                  (Request-evidence request)
                                  (State-control state)))
             (value (copy-expr state inst (definition state name)))
             (copies (copies-of state name)))
        (ref-set! (State-specialized state)
                  (table-set (ref-get (State-specialized state))
                             name
                             (append copies (list (Define (Request-spec request) value)))))))

    (: copies-of (-> State String (List Item) ! mut))
    (define (copies-of state name)
      (match (table-ref (ref-get (State-specialized state)) name)
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
        ((EvDerived) (EvDerived))
        ((EvHole _) (panic "internal error: unsolved evidence"))))

    (: copy-expr (-> State Instantiation Expr Expr ! mut))
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
          (term (Expr (copy-term state inst term) type loc)))))

    (: copy-term (-> State Instantiation Term Term ! mut))
    ;; A copy requests the specializations it references, so sibling copies
    ;; are sequenced: the requests, and the copies they produce, then come
    ;; in the same order on either host.
    (define (copy-term state inst term)
      (let ((copy (lambda (expr) (copy-expr state inst expr))))
        (match term
          ((Lit value) (Lit value))
          ((Var name types evidence) (Var name types evidence))
          ((Lambda params body captures?) (Lambda params (copy body) captures?))
          ((App callee args)
           (let* ((callee (copy callee)) (args (map copy args))) (App callee args)))
          ((If test then otherwise)
           (let* ((test (copy test))
                  (then (copy then))
                  (otherwise (copy otherwise)))
             (If test then otherwise)))
          ((Let name value body)
           (let* ((value (copy value)) (body (copy body))) (Let name value body)))
          ((Seq first rest) (let* ((first (copy first)) (rest (copy rest))) (Seq first rest)))
          ((Match scrutinee clauses)
           (let* ((scrutinee (copy scrutinee))
                  (clauses (map (lambda (clause)
                                  (Clause (copy-pattern inst (Clause-pattern clause))
                                          (copy (Clause-body clause))))
                                clauses)))
             (Match scrutinee clauses)))
          ((Ann inner type) (Ann (copy inner) (ground inst type)))
          ((Handle effect implementations body)
           (let* ((implementations
                   (map (lambda (entry) (Pair (Pair-first entry) (copy (Pair-second entry))))
                        implementations))
                  (body (copy body)))
             (Handle effect implementations body)))
          ((Convert inner target) (Convert (copy inner) (ground inst target)))
          ((TypeTest inner target) (TypeTest (copy inner) (ground inst target))))))

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
    (: reference (-> State String (List Type) (List Evidence) Type Loc Expr ! mut))
    (define (reference state name types evidence type loc)
      (match (program-value (program-of state) name)
        ((Some (Defined _ _ _)) (definition-reference state name types evidence type loc))
        ((Some (Method class _))
         (if (lifecycle-class? class)
             (lifecycle-reference state class name (list-ref types 1) type loc)
             (match evidence
               ((Cons (EvInstance instance instance-types subs) rest)
                (let ((class-arity
                       (length (Class-params (program-class (program-of state) class)))))
                  (definition-reference state
                    (instance-method state instance name)
                    (append instance-types (list-drop types class-arity))
                    (append subs rest) type loc)))
               (_ (panic "internal error: a method needs instance evidence")))))
        ((Some (Operation effect _)) (operation-reference state effect name type loc))
        (_ (Expr (Var name (Nil) (Nil)) type loc))))

    ;; ---- Drops and clones ----

    ;; A drop or a clone of a ground type runs what its plan says
    ;; (`lifecycle-plan`). A trivial drop is the primitive `discard`, and a
    ;; trivial clone is glue that pairs the value with itself; a type with
    ;; an instance runs its method; other data runs its glue. `method` is
    ;; the class method's own name, `drop` or `clone`.
    (: lifecycle-reference (-> State String String Type Type Loc Expr ! mut))
    (define (lifecycle-reference state class method subject type loc)
      (match (lifecycle-plan (program-of state) class (Nil) subject)
        ((Trivial)
         (if (string=? class drop-class)
             (Expr (Var "prim:discard" (Nil) (Nil)) type loc)
             (glue-reference state
                             "share"
                             subject
                             type
                             loc
                             (lambda () (share-function subject loc)))))
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
                             (lambda () (drop-function state method subject loc)))
             (glue-reference state "clone" subject type loc
                             (lambda () (clone-function state method subject loc)))))
        ((Refused reason)
         (panic (string-append "internal error: the checker allowed this: " reason)))))

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
    (: glue-reference (-> State String Type Type Loc (-> Expr ! mut) Expr ! mut))
    (define (glue-reference state kind subject type loc make)
      (let ((name (string-append "glue:" kind "<" (spec-key subject) ">")))
        (unless (table-contains? (ref-get (State-done state)) name)
          (ref-set! (State-done state) (table-set (ref-get (State-done state)) name name))
          (let ((value (make)))
            (ref-set! (State-glue state) (Cons (Define name value) (ref-get (State-glue state))))))
        (Expr (Var name (Nil) (Nil)) type loc)))

    ;; Drop glue matches the value apart and drops each linear immutable
    ;; field, skipping the rest.
    (: drop-function (-> State String Type Loc Expr ! mut))
    (define (drop-function state method dropped loc)
      (glue-lambda state
                   dropped
                   unit-type
                   (lambda (case) (drop-clause state method dropped case loc))
                   loc))

    ;; One case's clause binds each field glue drops to a local of its own
    ;; and skips the others, then drops what it bound, in field order.
    (: drop-clause (-> State String Type Case Loc Clause ! mut))
    (define (drop-clause state method dropped case loc)
      (let* ((program (program-of state)) (released (glue-fields program (Nil) dropped case)))
        (Clause (PCon (Case-name case)
                      (map-indexed (lambda (index type)
                                     (if
                                      (any? (lambda (entry) (= (Pair-first entry) index)) released)
                                      (PVar (glue-local case index) type)
                                      (PWild type)))
                                   (field-types program dropped case))
                      dropped)
                (in-sequence (map (lambda (field) (glue-drop state method case field loc)) released)
                             loc))))

    (: glue-drop (-> State String Case (Pair I64 Type) Loc Expr ! mut))
    (define (glue-drop state method case field loc)
      (let ((type (Pair-second field)))
        (Expr (App (lifecycle-reference state
                                        drop-class
                                        method
                                        type
                                        (TFun (list type) unit-type empty-row)
                                        loc)
                   (list (Expr (Var (glue-local case (Pair-first field)) (Nil) (Nil)) type loc)))
              unit-type
              loc)))

    ;; Clone glue matches the value apart, binding every field; clones each
    ;; linear immutable field in field order, taking the pair apart into a
    ;; local for each half; and pairs two values of the case, built from
    ;; the halves and the shared other fields. The plan has refused data
    ;; with a mutable field, so every field is immutable here.
    (: clone-function (-> State String Type Loc Expr ! mut))
    (define (clone-function state method cloned loc)
      (glue-lambda state
                   cloned
                   (pair-type cloned)
                   (lambda (case) (clone-clause state method cloned case loc))
                   loc))

    (: clone-clause (-> State String Type Case Loc Clause ! mut))
    (define (clone-clause state method cloned case loc)
      (let* ((program (program-of state))
             (types (field-types program cloned case))
             (linear (glue-fields program (Nil) cloned case)))
        (Clause (PCon (Case-name case)
                      (map-indexed (lambda (index type) (PVar (glue-local case index) type)) types)
                      cloned)
                (clone-fields state method cloned case types (map Pair-first linear) linear loc))))

    ;; The clone of the first of the linear fields left, taken apart for the
    ;; rest, and once none is left, the pair of values rebuilt from the
    ;; halves of every linear field, `halves`.
    (: clone-fields
       (-> State String Type Case (List Type) (List I64) (List (Pair I64 Type)) Loc Expr ! mut))
    (define (clone-fields state method cloned case types halves left loc)
      (match left
        ((Nil)
         (pair-of cloned
                  (rebuilt cloned case types halves "a" loc)
                  (rebuilt cloned case types halves "b" loc)
                  loc))
        ((Cons field rest)
         (let ((index (Pair-first field)) (type (Pair-second field)))
           (Expr (Match (field-clone state method case index type loc)
                        (list (Clause (PCon pair-name
                                            (list (PVar (half-local case index "a") type)
                                                  (PVar (half-local case index "b") type))
                                            (pair-type type))
                                      (clone-fields state
                                                    method
                                                    cloned
                                                    case
                                                    types
                                                    halves
                                                    rest
                                                    loc))))
                 (pair-type cloned)
                 loc)))))

    (: field-clone (-> State String Case I64 Type Loc Expr ! mut))
    (define (field-clone state method case index type loc)
      (Expr (App (lifecycle-reference state
                                      clone-class
                                      method
                                      type
                                      (TFun (list type) (pair-type type) empty-row)
                                      loc)
                 (list (Expr (Var (glue-local case index) (Nil) (Nil)) type loc)))
            (pair-type type)
            loc))

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
    (: glue-lambda (-> State Type Type (-> Case Clause ! mut) Loc Expr ! mut))
    (define (glue-lambda state subject result clause loc)
      (let ((data (program-type (program-of state) (type-name subject)))
            (value (Expr (Var "glue%value" (Nil) (Nil)) subject loc)))
        (Expr (Lambda (list "glue%value")
                      (Expr (Match value (map clause (DataType-cases data))) result loc)
                      #f)
              (TFun (list subject) result empty-row)
              loc)))

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
    (: operation-reference (-> State String String Type Loc Expr ! mut))
    (define (operation-reference state effect name type loc)
      (match (assoc-ref (Effect-defaults (program-effect (program-of state) effect)) name)
        ((Some (SnailDefault function))
         (definition-reference state
           function
           (Nil)
           (Nil)
           (Scheme-type (scheme-of state function))
           loc)
         (unit))
        (_ (unit)))
      (Expr (Var name (Nil) (Nil)) type loc))

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
    (: definition-reference (-> State String (List Type) (List Evidence) Type Loc Expr ! mut))
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
                 (begin
                   (ref-set! (State-externals state)
                             (table-set (ref-get (State-externals state)) name value))
                   (Expr (Var name (Nil) (Nil)) type loc))
                 (Expr (Var (request! state name types evidence) (Nil) (Nil)) type loc))))))

    (: external? (-> State String (List Type) Bool))
    (define (external? state name types)
      (match (State-owner state)
        ((Some owner) (and (null? types) (not (string=? (name-owner name) owner))))
        ((None) #f)))

    ;; ---- Programs ----

    (: new-state (-> Specialization (Option String) State))
    (define (new-state input owner)
      (State input (ref empty-table) (ref empty-table) (ref (Nil)) owner (ref empty-table)
             (control-effects (Typed-program (Specialization-typed input)))
             (ref (Nil))))

    ;; The effects with a control operation, in order of their names.
    (: control-effects (-> Program (List String)))
    (define (control-effects program)
      (sort-names (map Effect-name (filter (lambda (effect) (not (null? (Effect-control effect))))
                                           (table-values (Program-effects program))))))

    (: sort-names (-> (List String) (List String)))
    (define (sort-names names)
      (fold-left (lambda (sorted name) (insert-name name sorted)) (Nil) names))

    (: insert-name (-> String (List String) (List String)))
    (define (insert-name name sorted)
      (match sorted
        ((Cons first rest)
         (if (string<? first name) (Cons first (insert-name name rest)) (Cons name sorted)))
        ((Nil) (list name))))

    ;; Statements and monomorphic top-level values are roots, so their
    ;; initializers run even when nothing refers to them. Functions are
    ;; copied only when reached.
    (: monomorphize (-> Typed Mono ! mut))
    (define (monomorphize typed)
      (let* ((items (Typed-items typed)) (state (new-state (prepare-specialization typed) (None)))
             (statements (map (lambda (item) (root-item state item)) items)))
        (run-requests! state)
        (finish-mono state
                     (concatenate
                      (map (lambda (pair) (output-items state (Pair-first pair) (Pair-second pair)))
                           (zip items statements))) (Nil))))

    ;; One library's items, `items` among the program's. Every monomorphic
    ;; definition is a root, since any module may import it. Copies of other
    ;; libraries' definitions, the generic ones this library uses, come first,
    ;; in program order, as those libraries come before it.
    (: monomorphize-library (-> Specialization String (List Item) Mono ! mut))
    (define (monomorphize-library input owner items)
      (let* ((typed (Specialization-typed input))
             (state (new-state input (Some owner)))
             (exported (library-roots state items))
             (statements (map (lambda (item) (root-item state item)) items)))
        (run-requests! state)
        (finish-mono state
                     (append (concatenate (map (lambda (item) (foreign-copies state owner item))
                                               (Typed-items typed)))
                             (concatenate (map (lambda (pair)
                                                 (output-items state
                                                               (Pair-first pair)
                                                               (Pair-second pair)))
                                               (zip items statements))))
                     exported)))

    (: finish-mono (-> State (List Item) (List String) Mono ! mut))
    (define (finish-mono state items exported)
      (Mono (program-of state)
            (append (reverse (ref-get (State-glue state))) items)
            (ref-get (State-externals state))
            exported))

    ;; Requests the library's monomorphic functions, which `root-item` leaves
    ;; until something reaches them, and returns every name it exports.
    (: library-roots (-> State (List Item) (List String) ! mut))
    (define (library-roots state items)
      (concatenate (map (lambda (item)
                          (match item
                            ((Define name value)
                             (if (and (null? (Scheme-vars (scheme-of state name)))
                                      (not (alias-expr? value)))
                                 (begin (request! state name (Nil) (Nil)) (list name))
                                 (Nil)))
                            (_ (Nil))))
                        items)))

    (: foreign-copies (-> State String Item (List Item) ! mut))
    (define (foreign-copies state owner item)
      (match item
        ((Define name _) (if (string=? (name-owner name) owner) (Nil) (copies-of state name)))
        (_ (Nil))))

    ;; A statement is copied now; a monomorphic value is requested.
    (: root-item (-> State Item (Option Item) ! mut))
    (define (root-item state item)
      (match item
        ((Expose name _ _ _) (request! state name (Nil) (Nil)) (None))
        ((Do expr)
         (Some (Do (copy-expr state (Instantiation (Nil) (Nil) (State-control state)) expr))))
        ((Define name value)
         (let ((scheme (scheme-of state name)))
           (if
            (and (null? (Scheme-vars scheme)) (not (lambda-expr? value)) (not (alias-expr? value)))
            (begin (request! state name (Nil) (Nil)) (None))
            (None))))))

    ;; Each definition's copies take its place in program order.
    (: output-items (-> State Item (Option Item) (List Item) ! mut))
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
