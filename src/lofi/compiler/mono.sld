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
   (scheme base)
   (scheme cxr)
   (srfi 1)
   (srfi 69)
   (lofi compiler shim)
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
       (instances HashTable)
       (definitions HashTable)
       (done HashTable)
       (specialized HashTable)
       (pending (Ref (List Request)))))

    (struct Request
      ((name Symbol)
       (spec Symbol)
       (types (List Type))
       (evidence (List Evidence))))

    ;; The types and evidence that replace a definition's quantified variables
    ;; and requirements while it is copied.
    (struct Instantiation
      ((vars (List (Pair Symbol Type)))
       (evidence (List Evidence))))

    (define (program-of state)
      (Typed-program (State-typed state)))

    ;; ---- Requests ----

    (define (request-key name types)
      (string->symbol (apply string-append (symbol->string name)
                             (map (lambda (type) (string-append " " (type->string type))) types))))

    (define (spec-name name types)
      (if (null? types)
          name
          (string->symbol (string-append (symbol->string name) "<"
                                         (let join ((types (map type->string types)))
                                           (if (null? (cdr types)) (car types) (string-append (car types) "," (join (cdr types)))))
                                         ">"))))

    ;; Returns the specialized name, queueing the copy the first time. Under
    ;; coherent instances the types determine the evidence.
    (define (request! state name types evidence)
      (let ((key (request-key name types)))
        (or (hash-table-ref/default (State-done state) key #f)
            (let ((spec (spec-name name types)))
              (hash-table-set! (State-done state) key spec)
              (ref-set! (State-pending state) (cons (Request name spec types evidence) (ref-get (State-pending state))))
              spec))))

    (define (run-requests! state)
      (let ((pending (ref-get (State-pending state))))
        (unless (null? pending)
          (ref-set! (State-pending state) (cdr pending))
          (specialize-request! state (car pending))
          (run-requests! state))))

    (define (specialize-request! state request)
      (let* ((name (Request-name request))
             (scheme (definition-scheme (State-typed state) name))
             (inst (Instantiation (map cons (Scheme-vars scheme) (Request-types request)) (Request-evidence request)))
             (value (copy-expr state inst (hash-table-ref (State-definitions state) name))))
        (hash-table-update!/default (State-specialized state) name
                                    (lambda (copies) (append copies (list (Define (Request-spec request) value))))
                                    '())))

    ;; ---- Copying ----

    ;; Effects are erased here: specializations differ only by their types.
    (define (ground inst type)
      (erase-rows (substitute (Instantiation-vars inst) type)))

    (define (erase-rows type)
      (match type
        ((TCon name args) (TCon name (map erase-rows args)))
        ((TFun params result _) (TFun (map erase-rows params) (erase-rows result) empty-row))
        ((TRow _ _) empty-row)
        (_ type)))

    (define (ground-evidence inst evidence)
      (match evidence
        ((EvParam index) (list-ref (Instantiation-evidence inst) index))
        ((EvInstance instance types subs)
         (EvInstance instance (map (lambda (type) (ground inst type)) types)
                     (map (lambda (sub) (ground-evidence inst sub)) subs)))))

    (define (copy-expr state inst expr)
      (let ((type (ground inst (Expr-type expr))) (loc (Expr-loc expr)))
        (match (Expr-term expr)
          ((Var name types evidence)
           (reference state name (map (lambda (t) (ground inst t)) types)
                      (map (lambda (e) (ground-evidence inst e)) evidence) type loc))
          (term (Expr (copy-term state inst term) type loc)))))

    (define (copy-term state inst term)
      (let ((copy (lambda (expr) (copy-expr state inst expr))))
        (match term
          ((Lit value) (Lit value))
          ((Lambda params body) (Lambda params (copy body)))
          ((App callee args) (App (copy callee) (map copy args)))
          ((If test then else) (If (copy test) (copy then) (copy else)))
          ((Let name value body) (Let name (copy value) (copy body)))
          ((Seq first rest) (Seq (copy first) (copy rest)))
          ((Match scrutinee clauses)
           (Match (copy scrutinee)
                  (map (lambda (clause) (Clause (copy-pattern inst (Clause-pattern clause)) (copy (Clause-body clause))))
                       clauses)))
          ((Handle effect implementations body)
           (Handle effect (map (lambda (entry) (cons (car entry) (copy (cdr entry)))) implementations) (copy body))))))

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
    (define (reference state name types evidence type loc)
      (match (program-value (program-of state) name)
        ((Defined _) (definition-reference state name types evidence type loc))
        ((Method class (Scheme vars _ _))
         (match (car evidence)
           ((EvInstance instance instance-types subs)
            (let ((class-arity (length (Class-params (program-class (program-of state) class)))))
              (definition-reference state (instance-method state instance name)
                (append instance-types (drop types class-arity))
                (append subs (cdr evidence)) type loc)))))
        (_ (Expr (Var name '() '()) type loc))))

    (define (instance-method state instance method)
      (cdr (assq method (Instance-methods (hash-table-ref (State-instances state) instance)))))

    ;; A definition whose value is just another reference, such as
    ;; `(define + i64-add)`, is replaced by its target.
    (define (definition-reference state name types evidence type loc)
      (let ((value (hash-table-ref (State-definitions state) name)))
        (match (Expr-term value)
          ((Var _ _ _)
           (let ((scheme (definition-scheme (State-typed state) name)))
             (copy-expr state (Instantiation (map cons (Scheme-vars scheme) types) evidence) value)))
          (_ (Expr (Var (request! state name types evidence) '() '()) type loc)))))

    ;; ---- Programs ----

    ;; Statements and monomorphic top-level values are roots, so their
    ;; initializers run even when nothing refers to them. Functions are
    ;; copied only when reached.
    (define (monomorphize typed)
      (let ((state (State typed (make-hash-table eq?) (make-hash-table eq?) (make-hash-table eq?) (make-hash-table eq?) (ref '()))))
        (hash-table-walk (Program-instances (Typed-program typed))
                         (lambda (class instances)
                           (for-each (lambda (instance) (hash-table-set! (State-instances state) (Instance-name instance) instance))
                                     instances)))
        (for-each (lambda (item) (match item ((Define name value) (hash-table-set! (State-definitions state) name value)) (_ #f)))
                  (Typed-items typed))
        (let ((statements (map (lambda (item) (root-item state item)) (Typed-items typed))))
          (run-requests! state)
          (Mono (Typed-program typed)
                (append-map (lambda (item statement)
                              (match item
                                ((Define name _) (hash-table-ref/default (State-specialized state) name '()))
                                ((Do _) (list statement))
                                ((Expose _ _ _) (list item))))
                            (Typed-items typed) statements)))))

    (define (root-item state item)
      (match item
        ((Expose name _ _) (request! state name '() '()) #f)
        ((Do expr) (Do (copy-expr state (Instantiation '() '()) expr)))
        ((Define name value)
         (let ((scheme (definition-scheme (State-typed state) name)))
           (when (and (null? (Scheme-vars scheme)) (not (lambda-expr? value)) (not (alias-expr? value)))
             (request! state name '() '()))
           #f))))

    (define (lambda-expr? expr)
      (match (Expr-term expr)
        ((Lambda _ _) #t)
        (_ #f)))

    (define (alias-expr? expr)
      (match (Expr-term expr)
        ((Var _ _ _) #t)
        (_ #f)))

    ))
