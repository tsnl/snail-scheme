;; Typed program to monomorphic program. Starting from the statements and
;; top-level values, each reachable definition is copied once per ground type
;; instantiation. Method references become references to the instance method
;; their evidence names, so no instance is selected twice.
(define-library (lofi compiler mono)
  (export
   Mono
   Mono-program
   Mono-items
   monomorphize)
  (import
   (lofi base)
   (lofi table)
   (lofi compiler read)
   (lofi compiler core)
   (lofi compiler check))
  (begin

    ;; ---- Specialization state ----

    ;; `definitions` maps each name to its typed value. `done` maps a request
    ;; key to its specialized name; `specialized` collects the copies of each
    ;; definition in creation order.
    (struct Mono
      ((program Program)
       (items (List Item))))

    (struct State
      ((typed Typed)
       (instances (Table Instance))
       (definitions (Table Expr))
       (done (Ref (Table String)))
       (specialized (Ref (Table (List Item))))
       (pending (Ref (List Request)))))

    (struct Request
      ((name String)
       (spec String)
       (types (List Type))
       (evidence (List Evidence))))

    ;; The types and evidence that replace a definition's quantified variables
    ;; and requirements while it is copied.
    (struct Instantiation
      ((vars Substitution)
       (evidence (List Evidence))))

    (: program-of (-> State Program))
    (define (program-of state)
      (Typed-program (State-typed state)))

    (: definition (-> State String Expr))
    (define (definition state name)
      (match (table-ref (State-definitions state) name)
        ((Some value) value)
        ((None) (panic (string-append "internal error: no definition " name)))))

    ;; ---- Requests ----

    ;; The specialized name, queueing the copy the first time. Under coherent
    ;; instances the types determine the evidence.
    (: request! (-> State String (List Type) (List Evidence) String ! mut))
    (define (request! state name types evidence)
      (let ((spec (if (null? types) name (string-append name "<" (string-join (map type-key types) ",") ">"))))
        (unless (table-contains? (ref-get (State-done state)) spec)
          (ref-set! (State-done state) (table-set (ref-get (State-done state)) spec spec))
          (ref-set! (State-pending state) (Cons (Request name spec types evidence) (ref-get (State-pending state)))))
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
             (scheme (definition-scheme (State-typed state) name))
             (inst (Instantiation (zip (Scheme-vars scheme) (Request-types request)) (Request-evidence request)))
             (value (copy-expr state inst (definition state name)))
             (copies (copies-of state name)))
        (ref-set! (State-specialized state)
                  (table-set (ref-get (State-specialized state)) name (append copies (list (Define (Request-spec request) value)))))))

    (: copies-of (-> State String (List Item) ! mut))
    (define (copies-of state name)
      (match (table-ref (ref-get (State-specialized state)) name)
        ((Some copies) copies)
        ((None) (Nil))))

    ;; ---- Copying ----

    ;; Effects are erased here: specializations differ only by their types.
    (: ground (-> Instantiation Type Type))
    (define (ground inst type)
      (erase-rows (substitute (Instantiation-vars inst) type)))

    (: erase-rows (-> Type Type))
    (define (erase-rows type)
      (match type
        ((TCon name args) (TCon name (map erase-rows args)))
        ((TFun params result _) (TFun (map erase-rows params) (erase-rows result) empty-row))
        ((TRow _ _) empty-row)
        (_ type)))

    (: ground-evidence (-> Instantiation Evidence Evidence))
    (define (ground-evidence inst evidence)
      (match evidence
        ((EvParam index) (list-ref (Instantiation-evidence inst) index))
        ((EvInstance instance types subs)
         (EvInstance instance (map (lambda (type) (ground inst type)) types) (map (lambda (sub) (ground-evidence inst sub)) subs)))
        ((EvHole _) (panic "internal error: unsolved evidence"))))

    (: copy-expr (-> State Instantiation Expr Expr ! mut))
    (define (copy-expr state inst expr)
      (let ((type (ground inst (Expr-type expr))) (loc (Expr-loc expr)))
        (match (Expr-term expr)
          ((Var name types evidence)
           (reference state name (map (lambda (t) (ground inst t)) types) (map (lambda (e) (ground-evidence inst e)) evidence) type loc))
          (term (Expr (copy-term state inst term) type loc)))))

    (: copy-term (-> State Instantiation Term Term ! mut))
    (define (copy-term state inst term)
      (let ((copy (lambda (expr) (copy-expr state inst expr))))
        (match term
          ((Lit value) (Lit value))
          ((Var name types evidence) (Var name types evidence))
          ((Lambda params body) (Lambda params (copy body)))
          ((App callee args) (App (copy callee) (map copy args)))
          ((If test then otherwise) (If (copy test) (copy then) (copy otherwise)))
          ((Let name value body) (Let name (copy value) (copy body)))
          ((Seq first rest) (Seq (copy first) (copy rest)))
          ((Match scrutinee clauses)
           (Match (copy scrutinee)
                  (map (lambda (clause) (Clause (copy-pattern inst (Clause-pattern clause)) (copy (Clause-body clause)))) clauses)))
          ((Ann inner type) (Ann (copy inner) (ground inst type)))
          ((Handle effect implementations body)
           (Handle effect (map (lambda (entry) (Pair (Pair-first entry) (copy (Pair-second entry)))) implementations) (copy body)))
          ((Convert inner target) (Convert (copy inner) (ground inst target))))))

    (: copy-pattern (-> Instantiation Pattern Pattern))
    (define (copy-pattern inst pattern)
      (match pattern
        ((PWild type) (PWild (ground inst type)))
        ((PVar name type) (PVar name (ground inst type)))
        ((PLit value type) (PLit value (ground inst type)))
        ((PCon constructor args type) (PCon constructor (map (lambda (arg) (copy-pattern inst arg)) args) (ground inst type)))))

    ;; ---- References ----

    ;; Locals and builtin operations keep their names. A definition becomes
    ;; its specialization; a method becomes its instance's implementation.
    (: reference (-> State String (List Type) (List Evidence) Type Loc Expr ! mut))
    (define (reference state name types evidence type loc)
      (match (program-value (program-of state) name)
        ((Some (Defined _)) (definition-reference state name types evidence type loc))
        ((Some (Method class _))
         (match evidence
           ((Cons (EvInstance instance instance-types subs) rest)
            (let ((class-arity (length (Class-params (program-class (program-of state) class)))))
              (definition-reference state (instance-method state instance name) (append instance-types (drop types class-arity))
                (append subs rest) type loc)))
           (_ (panic "internal error: a method needs instance evidence"))))
        (_ (Expr (Var name (Nil) (Nil)) type loc))))

    (: instance-method (-> State String String String))
    (define (instance-method state instance method)
      (match (table-ref (State-instances state) instance)
        ((Some found)
         (match (assoc-ref (Instance-methods found) method)
           ((Some global) global)
           ((None) (panic "internal error: missing instance method"))))
        ((None) (panic "internal error: unknown instance"))))

    ;; A definition whose value is just another reference, such as
    ;; `(define + i64-add)`, is replaced by its target.
    (: definition-reference (-> State String (List Type) (List Evidence) Type Loc Expr ! mut))
    (define (definition-reference state name types evidence type loc)
      (let ((value (definition state name)))
        (match (Expr-term value)
          ((Var _ _ _)
           (let ((scheme (definition-scheme (State-typed state) name)))
             (copy-expr state (Instantiation (zip (Scheme-vars scheme) types) evidence) value)))
          (_ (Expr (Var (request! state name types evidence) (Nil) (Nil)) type loc)))))

    ;; ---- Programs ----

    ;; Statements and monomorphic top-level values are roots, so their
    ;; initializers run even when nothing refers to them. Functions are
    ;; copied only when reached.
    (: monomorphize (-> Typed Mono ! mut))
    (define (monomorphize typed)
      (let* ((items (Typed-items typed))
             (instances (fold-left (lambda (table instance) (table-set table (Instance-name instance) instance))
                                   empty-table (concatenate (table-values (Program-instances (Typed-program typed))))))
             (definitions (fold-left (lambda (table item)
                                       (match item
                                         ((Define name value) (table-set table name value))
                                         (_ table)))
                                     empty-table items))
             (state (State typed instances definitions (ref empty-table) (ref empty-table) (ref (Nil)))))
        (let ((statements (map (lambda (item) (root-item state item)) items)))
          (run-requests! state)
          (Mono (Typed-program typed) (concatenate (map (lambda (pair) (output-items state (Pair-first pair) (Pair-second pair)))
                                                        (zip items statements)))))))

    ;; A statement is copied now; a monomorphic value is requested.
    (: root-item (-> State Item (Option Item) ! mut))
    (define (root-item state item)
      (match item
        ((Expose name _ _) (request! state name (Nil) (Nil)) (None))
        ((Do expr) (Some (Do (copy-expr state (Instantiation (Nil) (Nil)) expr))))
        ((Define name value)
         (let ((scheme (definition-scheme (State-typed state) name)))
           (if (and (null? (Scheme-vars scheme)) (not (lambda-expr? value)) (not (alias-expr? value)))
               (begin (request! state name (Nil) (Nil)) (None))
               (None))))))

    ;; Each definition's copies take its place in program order.
    (: output-items (-> State Item (Option Item) (List Item) ! mut))
    (define (output-items state item statement)
      (match item
        ((Define name _) (copies-of state name))
        ((Do _) (match statement ((Some statement) (list statement)) ((None) (Nil))))
        ((Expose _ _ _) (list item))))

    (: alias-expr? (-> Expr Bool))
    (define (alias-expr? expr)
      (match (Expr-term expr)
        ((Var _ _ _) #t)
        (_ #f)))

    ))
