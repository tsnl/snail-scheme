;; Compiler-owned properties of types, found from their structure: whether a
;; type is linear, what dropping
;; one of its values runs, and whether a struct contains itself. A
;; procedure's arrow does not describe its captured environment.
(define-library (snail shell compiler capabilities)
  (export
   linear-type?
   shared-type?
   missing-copy
   copy-declaration
   copy-refusal
   instance-copy-refusal
   contains-itself?
   drop-plan
   checked-drop-plan
   plan-covers?
   glue-fields
   field-types
   drop-instance
   instance-bindings
   drop-rows)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler core))
  (begin

    ;; ---- Shared ownership ----

    ;; Copy containers own their fields once, even when the container has
    ;; aliases. Only containers that can reach counted content need their
    ;; own count. Linear containers already have exactly one owner.
    (define (shared-type? (program Program) (type Type)) (→ Bool)
      (and (not (linear-type? program (Nil) type))
           (shared-content? program type (Nil))))

    (define (shared-content? (program Program) (type Type) (seen (List String))) (→ Bool)
      (match type
        ((TFun _ _ _) #t)
        ((TCon "Rc" _) #t)
        ((TCon "Any" _) #t)
        ((TCon "WeakRc" _) #f)
        ((TCon "FnOnce" _) #f)

        ((TCon name args)
         (cond ((member? name (list "Vector"))
                (any? (lambda (arg) (shared-content? program arg seen)) args))
               ((any? (lambda (entry) (string=? name (● entry first))) (builtin-types)) #f)
               ((member? name seen)
                (any? (lambda (arg) (shared-content? program arg seen)) args))
               (else (shared-fields? program type (Cons name seen)))))
        (_ #f)))

    (define (shared-fields? (program Program) (type Type) (seen (List String))) (→ Bool)
      (match type
        ((TCon name _)
         (any? (lambda (case)
                 (any? (lambda (field) (shared-content? program field seen))
                       (field-types program type case)))
               (● (program-type program name) cases)))
        (_ #f)))

    ;; ---- Type grades ----

    ;; One query's progress: whether it has found a linear field yet, and
    ;; what it has entered. Each instantiation of a declaration, named in
    ;; `keys` by its `type-key`, is entered once per query, including across
    ;; sibling fields, because re-exploring a recursive graph by every path
    ;; is exponential. `names` holds the declarations on the path from the
    ;; query's type to the one being searched: one met again on it at other
    ;; arguments, as non-regular recursion would, has its arguments searched
    ;; as if it held them directly, which keeps the query finite. Sibling
    ;; fields that hold one declaration at different arguments, as
    ;; `(Option (Queue T))` and `(Option T)` do, are not recursion, so each is
    ;; searched through its fields. Carrying the sets rather than mutating
    ;; them keeps the query a function of its arguments.
    (struct Linearity
      ((found? Bool)
       (keys (List String))
       (names (List String))))

    ;; A type variable is linear unless `copy` names it, as a signature's
    ;; `(⊨ (Copy A))` does. A declared destructor or any linear field makes
    ;; an aggregate linear. Rc is the sole owning wrapper that can hold a
    ;; linear value while remaining Copy; WeakRc has no ownership of its target.

    (define (linear-type? (program Program) (copy (List String)) (type Type)) (→ Bool)
      (● (linear-search program copy type (Linearity #f (Nil) (Nil))) found?))

    (define (linear-search (program Program) (copy (List String)) (type Type) (progress Linearity))
      (→ Linearity)
      (match type
        ((TCon "Rc" _) progress)
        ((TCon "WeakRc" _) progress)
        ((TCon "FnOnce" _) (Linearity-found?-set progress #t))
        ((TCon name args)
         (linear-instance program copy name args progress))
        ((TRigid name) (if (member? name copy) progress (Linearity-found?-set progress #t)))
        (_ progress)))

    ;; A builtin holds its arguments directly, and so, conservatively, does
    ;; a declaration met again on the path at other arguments. Any other
    ;; declaration is searched through its fields, with its parameters bound
    ;; to `args`.

    (define (linear-instance (program Program)
                             (copy (List String))
                             (name String)
                             (args (List Type))
                             (progress Linearity))
      (→ Linearity)
      (let ((key (type-key (TCon name args))))
        (cond ((member? key (● progress keys)) progress)
              ((or (member? name (● progress names))
                   (any? (lambda (entry) (string=? name (● entry first))) (builtin-types)))
               (linear-any program copy args progress))
              (else
               (let* ((names (● progress names))
                      (entered
                       (Linearity #f (Cons key (● progress keys)) (Cons name names))))
                 (Linearity-names-set (linear-fields program copy name args entered) names))))))

    (define (linear-any (program Program)
                        (copy (List String))
                        (types (List Type))
                        (progress Linearity))
      (→ Linearity)
      (fold-left (lambda (found type) (linear-next program copy type found)) progress types))

    (define (linear-next (program Program) (copy (List String)) (type Type) (found Linearity))
      (→ Linearity)
      (if (● found found?)
          found
          (linear-search program copy type found)))

    ;; A declaration's parameters are bound to `args`, so its fields hold
    ;; only the variables of the type being searched.

    (define (linear-fields (program Program)
                           (copy (List String))
                           (name String)
                           (args (List Type))
                           (progress Linearity))
      (→ Linearity)
      (let* ((data (program-type program name)) (bindings (zip (● data params) args)))
        (if (● data owned?)
            (Linearity-found?-set progress #t)
            (fold-left (lambda (found case) (linear-case program copy bindings case found))
                       progress (● data cases)))))

    ;; A mutable field never makes its holder linear: its content leaves
    ;; only by being swapped out, so sharing the holder never duplicates it.

    (define (linear-case (program Program)
                         (copy (List String))
                         (bindings Substitution)
                         (case Case)
                         (found Linearity))
      (→ Linearity)
      (fold-left (lambda (found field)
                   (linear-next program copy (substitute bindings (● field type)) found))
                 found (● case fields)))

    ;; The variables a signature would have to declare Copy to make `type`
    ;; unrestricted, or none when a concrete part of it is linear, which
    ;; no declaration changes. A variable reached through data makes its
    ;; type linear; one inside an arrow does not.

    (define (missing-copy (program Program) (copy (List String)) (type Type)) (→ (List String))
      (let ((free (filter (lambda (name) (not (member? name copy))) (data-variables type))))
        (if (linear-type? program (append free copy) type) (Nil) free)))

    (define (data-variables (type Type)) (→ (List String))
      (match type
        ((TRigid name) (list name))
        ((TCon _ args) (delete-duplicates string=? (concatenate (map data-variables args))))
        (_ (Nil))))

    ;; The requirements naming `names`, as a diagnostic quotes them.

    (define (copy-declaration (names (List String))) (→ String)
      (string-join (map (lambda (name) (string-append "(Copy " name ")")) names) " "))

    ;; Why `type` cannot be bound to a variable declared Copy, under the
    ;; enclosing definition's Copy variables `copy`, or None when it can: a
    ;; concrete linear part is never unrestricted, and a variable of the
    ;; definition is only when the definition requires it to be. `required`
    ;; says what requires the variable to be Copy.

    (define (copy-refusal (program Program) (copy (List String)) (type Type) (required String))
      (→ (Option String))
      (if (linear-type? program copy type)
          (Some (match (missing-copy program copy type)
                  ((Nil) (string-append required ", and " (type->string type) " is linear"))
                  (names
                   (string-append "this use needs "
                                  (copy-declaration names)
                                  ", which the definition must require"))))
          (None)))

    ;; Why an instance cannot be used where its head matched with
    ;; `bindings`: a variable it requires to be Copy, as `(⊨ (Copy
    ;; A))` does, is bound to a linear type. The instance's body was
    ;; checked with that variable unrestricted, so it may duplicate or
    ;; discard one, and a linear type there would be duplicated or lost.

    (define (instance-copy-refusal (program Program)
                                   (copy (List String))
                                   (instance Instance)
                                   (bindings Substitution))
      (→ (Option String))
      (fold-left (lambda (refusal var)
                   (match (Pair refusal (assoc-ref bindings var))
                     ((Pair (None) (Some bound))
                      (copy-refusal program
                                    copy
                                    bound
                                    (string-append "the instance "
                                                   (type->string (TCon (● instance class)
                                                                       (● instance types)))
                                                   " requires "
                                                   (copy-declaration (list var)))))
                     (_ refusal)))
                 (None) (● instance copy)))

    ;; ---- Releasing ----

    ;; A drop either discards a value, calls its declared destructor, or
    ;; releases the linear fields of an aggregate. The checker records this
    ;; plan so specialization cannot introduce cleanup it did not charge.

    (define (drop-plan (program Program) (copy (List String)) (type Type))
      (→ Plan)
      (match type
        ((TCon name _)
         (if (any? (lambda (entry) (string=? name (● entry first))) (builtin-types)) (Trivial)
             (match (drop-instance program name)
               ((Some instance) (Implemented instance))
               ((None) (data-plan program copy type)))))
        (_ (Trivial))))

    ;; The plan the checker records for a drop of `type`, or None
    ;; for a type variable, whose plan its instantiation decides.

    (define (checked-drop-plan (program Program) (copy (List String)) (type Type))
      (→ (Option Plan))
      (match type
        ((TRigid _) (None))
        (_ (Some (drop-plan program copy type)))))

    ;; Whether the plan for a ground type runs no more than the plan the
    ;; checker charged for the type the drop was written at, which
    ;; mono checks for each one written in a program. Grounding only makes
    ;; data unrestricted, since a Copy variable is bound only to an
    ;; unrestricted type, at a signature's use and an instance's alike, so
    ;; glue may become trivial and nothing else changes; an instance is
    ;; found by its type's name in both.

    (define (plan-covers? (checked (Option Plan)) (ground Plan)) (→ Bool)
      (match (Pair checked ground)
        ((Pair (None) _) #t)
        ((Pair _ (Trivial)) #t)
        ((Pair (Some (Implemented charged)) (Implemented found))
         (string=? (● charged name) (● found name)))
        ((Pair (Some (Glue)) (Glue)) #t)
        (_ #f)))

    ;; Declared data without an instance of the class.

    (define (data-plan (program Program) (copy (List String)) (type Type)) (→ Plan)
      (if (and (linear-type? program copy type) (drop-runs? program copy type (Nil) (Nil)))
          (Glue) (Trivial)))

    (define (type-name (type Type)) (→ String)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: data has a name"))))

    ;; Whether dropping a value of `type` runs anything: an instance's
    ;; method, or the drop of a type variable, which a ground type may give
    ;; one. A declaration met again at the same arguments adds nothing, and
    ;; one met again at other arguments is taken to run something, so that
    ;; glue refuses it (`glue-search`). `keys` and `names` are those met on
    ;; the way here.

    (define (drop-runs? (program Program)
                        (copy (List String))
                        (type Type)
                        (keys (List String))
                        (names (List String)))
      (→ Bool)
      (match type
        ((TRigid name) (not (member? name copy)))
        ;; Dropping a FnOnce runs its dropper, which drops what it captured
        ;; (control.sld, "Droppers"), so data holding one runs glue.
        ((TCon "FnOnce" _) #t)
        ((TCon name _)
         (cond ((member? (type-key type) keys) #f)
               ((member? name names) #t)
               ((any? (lambda (entry) (string=? name (● entry first))) (builtin-types)) #f)
               (else (match (drop-instance program name)
                       ((Some _) #t)
                       ((None) (fields-drop-run? program copy type keys names))))))
        (_ #f)))

    (define (fields-drop-run? (program Program)
                              (copy (List String))
                              (type Type)
                              (keys (List String))
                              (names (List String)))
      (→ Bool)
      (match type
        ((TCon name _)
         (any? (lambda (case)
                 (any? (lambda (field)
                         (drop-runs? program
                                     copy
                                     (● field second)
                                     (Cons (type-key type) keys)
                                     (Cons name names)))
                       (glue-fields program copy type case)))
               (● (program-type program name) cases)))
        (_ #f)))

    ;; The fields of `case` that glue drops, by index, at the type
    ;; `type` gives its declaration's parameters: the linear ones.

    (define (glue-fields (program Program) (copy (List String)) (type Type) (case Case))
      (→ (List (Pair I64 Type)))
      (filter (lambda (field) (linear-type? program copy (● field second)))
              (zip (iota (length (● case fields))) (field-types program type case))))

    ;; Each field of `case` at the type `type` gives its declaration's
    ;; parameters.

    (define (field-types (program Program) (type Type) (case Case)) (→ (List Type))
      (let ((bindings (match type
                        ((TCon name args) (zip (● (program-type program name) params) args))
                        (_ (Nil)))))
        (map (lambda (field) (substitute bindings (● field type))) (● case fields))))

    ;; An instance of a Drop class is declared in its type's library
    ;; for the type at distinct variables, so a type has at most one of
    ;; each, found by its name.

    (define (drop-instance (program Program) (name String))
      (→ (Option Instance))
      (find (lambda (instance)
              (match (● instance types)
                ((Cons _ (Cons (TCon head _) (Nil))) (string=? head name))
                (_ #f)))
            (class-instances program (drop-class))))

    ;; The rows a drop of a value of `type` performs, or why it
    ;; cannot run, under the enclosing definition's Copy variables and
    ;; requirements: a type variable's row is its requirement's, as
    ;; `(Drop e A)`'s, an instance's is in its head, and glue performs its
    ;; fields' rows. Each instantiation of a declaration is entered once, so
    ;; a recursive type adds its fields' rows once. `names` holds the
    ;; declarations on the path here, as `Linearity`'s does: one met again
    ;; on it at other arguments would need glue at unboundedly many types,
    ;; so it needs an instance instead, while sibling fields may hold one
    ;; declaration at different arguments, as `(Option Handle)` and
    ;; `(Option Token)`.
    (struct RowSearch
      ((rows (List Type))
       (keys (List Type))
       (names (List String))))

    (define (drop-rows (program Program)
                       (copy (List String))
                       (givens (List Constraint))
                       (type Type))
      (→ (Result (List Type) String))
      (match (drop-rows-search program copy givens type (Ok (RowSearch (Nil) (Nil) (Nil))))
        ((Ok found) (Ok (reverse (● found rows))))
        ((Err message) (Err message))))

    (define (drop-rows-search (program Program)
                              (copy (List String))
                              (givens (List Constraint))
                              (type Type)
                              (progress (Result RowSearch String)))
      (→ (Result RowSearch String))
      (match (Pair type progress)
        ((Pair _ (Err message)) (Err message))
        ((Pair (TRigid name) (Ok found))
         (match (given-drop-row givens name)
           ((Some row) (Ok (RowSearch-rows-set found (Cons row (● found rows)))))
           ((None) (Err (missing-requirement name)))))
        ((Pair _ (Ok found)) (drop-search program copy givens type found))))

    ;; A drop that runs nothing performs nothing, except a FnOnce's:
    ;; dropping one unrun drops what it captured, whose drops its own row
    ;; allows (ownership.sld, "Drops that may run"), so dropping a
    ;; `(FnOnce A → B ! e)` performs `e`, less its control effects, which no
    ;; drop performs.

    (define (drop-search (program Program) (copy (List String))
                         (givens (List Constraint)) (type Type) (found RowSearch))
      (→ (Result RowSearch String))
      (match type
        ((TFun _ _ row)
         (Ok (RowSearch-rows-set found (Cons (without-control program row) (● found rows)))))
        ((TCon "FnOnce" (Cons signature (Nil))) (drop-search program copy givens signature found))
        ((TCon "Rc" (Cons inner (Nil)))
         (drop-rows-search program
                           copy
                           givens
                           inner
                           (Ok (RowSearch-rows-set found (Cons (mut-row) (● found rows))))))
        ((TCon name args)
         (cond ((member? name (list "Vector"))
                (fold-left (lambda (progress arg)
                             (drop-rows-search program copy givens arg progress))
                           (Ok found) args))
               ((any? (lambda (entry) (string=? name (● entry first))) (builtin-types)) (Ok found))
               (else (match (drop-instance program name)
                       ((Some instance)
                        (instance-search program copy givens type instance found))
                       ((None) (glue-search program copy givens type found))))))
        (_ (Ok found))))

    (define (without-control (program Program) (row Type)) (→ Type)
      (match row
        ((TRow labels tail)
         (TRow (filter (lambda (label)
                         (match (table-ref (● program effects) label)
                           ((Some effect) (null? (● effect control)))
                           ((None) #t)))
                       labels)
               (match tail
                 ((Some inner) (Some (without-control program inner)))
                 ((None) (None)))))
        (_ row)))

    (define (missing-requirement (name String)) (→ String)
      (string-append "dropping a value of type " name
                     " needs (Drop e " name "); give the definition that requirement"))

    ;; An instance performs the labels its head names, and, for each
    ;; requirement, as `(Drop e A)`, what the class's method performs at the
    ;; type `type` gives `A`, which is the row `e` its head ends with. That
    ;; type is part of `type`, so the search ends. It cannot run where a
    ;; variable it requires Copy is given a linear type.

    (define (instance-search (program Program)
                             (copy (List String))
                             (givens (List Constraint))
                             (type Type)
                             (instance Instance)
                             (found RowSearch))
      (→ (Result RowSearch String))
      (let ((bindings (instance-bindings instance type)))
        (match (instance-copy-refusal program copy instance bindings)
          ((Some refusal) (Err refusal))
          ((None)
           (fold-left (lambda (progress required)
                        (drop-rows-search program copy givens (substitute bindings
                                                                          (list-ref
                                                                           (● required types)
                                                                           1))
                                          progress))
                      (Ok
                       (RowSearch-rows-set found (Cons (head-row instance) (● found rows))))
                      (● instance requires))))))

    ;; The labels a Drop instance's head names, as a closed row.

    (define (head-row (instance Instance)) (→ Type)
      (match (● instance types)
        ((Cons (TRow labels _) _) (TRow labels (None)))
        (_ (panic "internal error: a Drop instance names its row"))))

    ;; The types `type` gives a Drop instance's variables, matched
    ;; against its head, which names its type at distinct variables.

    (define (instance-bindings (instance Instance) (type Type)) (→ Substitution)
      (match (Pair (● instance types) type)
        ((Pair (Cons _ (Cons (TCon _ params) (Nil))) (TCon _ args))
         (zip (map (lambda (param)
                     (match param
                       ((TRigid name) name)
                       (_ "")))
                   params)
              args))
        (_ (panic "internal error: a Drop instance names a row and a declared type"))))

    (define (glue-search (program Program)
                         (copy (List String))
                         (givens (List Constraint))
                         (type Type)
                         (found RowSearch))
      (→ (Result RowSearch String))
      (let ((name (type-name type)) (key type))
        (cond ((any? (lambda (seen) (type=? key seen)) (● found keys)) (Ok found))
              ((member? name (● found names))
               (match type
                 ((TCon _ args)
                  (fold-left (lambda (progress arg)
                               (match (Pair arg progress)
                                 ((Pair (TRow _ _) (Ok inner))
                                  (Ok (RowSearch-rows-set inner (Cons arg (● inner rows)))))
                                 (_ (drop-rows-search program copy givens arg progress))))
                             (Ok found) args))
                 (_ (Ok found))))
              (else
               (match (glue-fields-search program
                                          copy
                                          givens
                                          type
                                          (RowSearch (● found rows) (Cons key (● found keys))
                                                     (Cons name (● found names))))
                 ((Ok inner) (Ok (RowSearch-names-set inner (● found names))))
                 (failed failed))))))

    ;; Glue performs what dropping each field it reaches does.

    (define (glue-fields-search (program Program)
                                (copy (List String))
                                (givens (List Constraint))
                                (type Type)
                                (found RowSearch))
      (→ (Result RowSearch String))
      (fold-left (lambda (progress field) (drop-rows-search program copy givens field progress))
                 (Ok found)
                 (concatenate (map (lambda (case) (field-types program type case))
                                   (● (program-type program (type-name type)) cases)))))

    ;; A declaration met again at other arguments would need glue for every
    ;; depth, so it needs an instance instead.

    ;; The row of the enclosing definition's requirement of the class for
    ;; `A`, as `(Drop e A)`'s.

    (define (given-drop-row (givens (List Constraint)) (name String)) (→ (Option Type))
      (match (find (lambda (given)
                     (and (string=? (● given class) (drop-class))
                          (match (● given types)
                            ((Cons _ (Cons (TRigid other) (Nil))) (string=? other name))
                            (_ #f))))
                   givens)
        ((Some given) (Some (first-type (● given types))))
        ((None) (None))))

    (define (first-type (types (List Type))) (→ Type)
      (match types
        ((Cons type _) type)
        ((Nil) (panic "internal error: a constraint has types"))))

    ;; ---- Buildable structs ----

    ;; Whether every value of the struct `data` would hold another of
    ;; itself. The search follows struct fields, cells among them, and stops
    ;; at every other type, each of which has a value that holds no struct:
    ;; an enum's tag, an empty array or string, an Any, a function. A
    ;; declaration is entered once per path: one that reached its own name
    ;; would itself contain itself, and the expander refuses it where it is
    ;; declared.

    (define (contains-itself? (program Program) (data DataType)) (→ Bool)
      (any? (lambda (field) (reaches? program (● data name) field (Nil)))
            (struct-field-types data (map TRigid (● data params)))))

    (define (reaches? (program Program) (target String) (type Type) (entered (List String)))
      (→ Bool)
      (match type
        ((TCon name args)
         (cond ((string=? name target) #t)
               ((or (member? name entered)
                    (any? (lambda (entry) (string=? name (● entry first))) (builtin-types)))
                #f)
               (else (let ((data (program-type program name)))
                       (and (not (● data enum?))
                            (any?
                             (lambda (field) (reaches? program target field (Cons name entered)))
                             (struct-field-types data args)))))))
        (_ #f)))

    ;; The field types of a struct's one case, with its parameters bound to
    ;; `args`.

    (define (struct-field-types (data DataType) (args (List Type))) (→ (List Type))
      (let ((bindings (zip (● data params) args)))
        (match (● data cases)
          ((Cons case _)
           (map (lambda (field) (substitute bindings (● field type))) (● case fields)))
          ((Nil) (panic "internal error: a struct has one case")))))))
