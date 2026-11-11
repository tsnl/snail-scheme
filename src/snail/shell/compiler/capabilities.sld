;; Compiler-owned properties of types, found from their structure: whether a
;; type is first-order data, whether it is linear, what dropping or cloning
;; one of its values runs, and whether a struct contains itself. A
;; procedure's arrow does not describe its captured environment.
(define-library (snail shell compiler capabilities)
  (export
   linear-type?
   missing-copy
   copy-declaration
   copy-refusal
   instance-copy-refusal
   first-order-type?
   contains-itself?
   lifecycle-plan
   checked-plan
   plan-covers?
   glue-fields
   field-types
   lifecycle-instance
   instance-bindings
   lifecycle-rows)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler core))
  (begin

    ;; ---- Data ----

    ;; A type is first-order data when nothing inside it, through type
    ;; arguments and declared fields, is a function, a Funcref or an Any.
    ;; Its TypeId then names all of it: a function type's says only that it
    ;; is one, and an Any's nothing of what it holds. The search returns the
    ;; declarations it has entered, each once, as the search for linear
    ;; fields below does, or None once it finds something that is not data.
    (: first-order-type? (impl (Fn Program Type -> Bool)))
    (define (first-order-type? program type)
      (match (first-order-search program type (Some (Nil)))
        ((Some _) #t)
        ((None) #f)))

    ;; Arguments are searched before a recursive declaration is cut by name.
    (: first-order-search (impl (Fn Program Type (Option (List String)) -> (Option (List String)))))
    (define (first-order-search program type entered)
      (match (Pair type entered)
        ((Pair _ (None)) (None))
        ((Pair (TCon name args) _)
         (if (concrete-callable? type) (None)
             (match (fold-left (lambda (found arg) (first-order-search program arg found))
                               entered
                               args)
               ((Some names)
                (cond ((member? name (list "Any" "Funcref")) (None))
                      ((or (member? name names)
                           (any? (lambda (entry) (string=? name (::first entry))) builtin-types))
                       (Some names))
                      (else (first-order-fields program name args (Cons name names)))))
               ((None) (None)))))
        ((Pair (TRow _ _) _) entered)
        (_ (None))))

    (: first-order-fields
       (impl (Fn Program String (List Type) (List String) -> (Option (List String)))))
    (define (first-order-fields program name args entered)
      (let* ((data (program-type program name)) (bindings (zip (::params data) args)))
        (fold-left (lambda (found field)
                     (first-order-search program (substitute bindings (::type field)) found))
                   (Some entered) (concatenate (map ::fields (::cases data))))))

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
    ;; `(Ref (Queue T))` and `(Ref T)` do, are not recursion, so each is
    ;; searched through its fields. Carrying the sets rather than mutating
    ;; them keeps the query a function of its arguments.
    (struct Linearity
      ((found? Bool)
       (keys (List String))
       (names (List String))))

    ;; A type variable is linear unless `copy` names it, as a signature's
    ;; `(requires (Copy A))` does. An owned declaration is linear, and
    ;; immutable fields can make any record linear; ordinary arrows never
    ;; describe owned captures. A cell, like any struct with a mutable
    ;; field, is a shared handle whatever it holds, so a declaration that
    ;; holds a parameter only in a `Ref` is unrestricted.
    (: linear-type? (impl (Fn Program (List String) Type -> Bool)))
    (define (linear-type? program copy type)
      (::found? (linear-search program copy type (Linearity #f (Nil) (Nil)))))

    (: linear-search (impl (Fn Program (List String) Type Linearity -> Linearity)))
    (define (linear-search program copy type progress)
      (match type
        ((TCon "Borrow" _) progress)
        ((TCon "FnOnce" _) (Linearity-found?-set progress #t))
        ((TCon "FnMut" _) (Linearity-found?-set progress #t))
        ((TCon name args)
         (if (concrete-callable? type)
             (match (callable-kind type)
               ((Some "FnOnce") (Linearity-found?-set progress #t))
               (_ (linear-any program copy (callable-captures type) progress)))
             (linear-instance program copy name args progress)))
        ((TRigid name) (if (member? name copy) progress (Linearity-found?-set progress #t)))
        (_ progress)))

    ;; A builtin holds its arguments directly, and so, conservatively, does
    ;; a declaration met again on the path at other arguments. Any other
    ;; declaration is searched through its fields, with its parameters bound
    ;; to `args`.
    (: linear-instance (impl (Fn Program (List String) String (List Type) Linearity -> Linearity)))
    (define (linear-instance program copy name args progress)
      (let ((key (type-key (TCon name args))))
        (cond ((member? key (::keys progress)) progress)
              ((or (member? name (::names progress))
                   (any? (lambda (entry) (string=? name (::first entry))) builtin-types))
               (linear-any program copy args progress))
              (else
               (let* ((names (::names progress))
                      (entered
                       (Linearity #f (Cons key (::keys progress)) (Cons name names))))
                 (Linearity-names-set (linear-fields program copy name args entered) names))))))

    (: linear-any (impl (Fn Program (List String) (List Type) Linearity -> Linearity)))
    (define (linear-any program copy types progress)
      (fold-left (lambda (found type) (linear-next program copy type found)) progress types))

    (: linear-next (impl (Fn Program (List String) Type Linearity -> Linearity)))
    (define (linear-next program copy type found)
      (if (::found? found)
          found
          (linear-search program copy type found)))

    ;; A declaration's parameters are bound to `args`, so its fields hold
    ;; only the variables of the type being searched.
    (: linear-fields (impl (Fn Program (List String) String (List Type) Linearity -> Linearity)))
    (define (linear-fields program copy name args progress)
      (let* ((data (program-type program name)) (bindings (zip (::params data) args)))
        (if (::owned? data)
            (Linearity-found?-set progress #t)
            (fold-left (lambda (found case) (linear-case program copy bindings case found))
                       progress (::cases data)))))

    ;; A mutable field never makes its holder linear: its content leaves
    ;; only by being swapped out, so sharing the holder never duplicates it.
    (: linear-case (impl (Fn Program (List String) Substitution Case Linearity -> Linearity)))
    (define (linear-case program copy bindings case found)
      (fold-left (lambda (found field)
                   (if (::mutable? field)
                       found
                       (linear-next program copy (substitute bindings (::type field)) found)))
                 found (::fields case)))

    ;; The variables a signature would have to declare Copy to make `type`
    ;; unrestricted, or none when a concrete part of it is linear, which
    ;; no declaration changes. A variable reached through data makes its
    ;; type linear; one inside an arrow does not.
    (: missing-copy (impl (Fn Program (List String) Type -> (List String))))
    (define (missing-copy program copy type)
      (let ((free (filter (lambda (name) (not (member? name copy))) (data-variables type))))
        (if (linear-type? program (append free copy) type) (Nil) free)))

    (: data-variables (impl (Fn Type -> (List String))))
    (define (data-variables type)
      (match type
        ((TRigid name) (list name))
        ((TCon _ args) (delete-duplicates string=? (concatenate (map data-variables args))))
        (_ (Nil))))

    ;; The requirements naming `names`, as a diagnostic quotes them.
    (: copy-declaration (impl (Fn (List String) -> String)))
    (define (copy-declaration names)
      (string-join (map (lambda (name) (string-append "(Copy " name ")")) names) " "))

    ;; Why `type` cannot be bound to a variable declared Copy, under the
    ;; enclosing definition's Copy variables `copy`, or None when it can: a
    ;; concrete linear part is never unrestricted, and a variable of the
    ;; definition is only when the definition requires it to be. `required`
    ;; says what requires the variable to be Copy.
    (: copy-refusal (impl (Fn Program (List String) Type String -> (Option String))))
    (define (copy-refusal program copy type required)
      (if (linear-type? program copy type)
          (Some (match (missing-copy program copy type)
                  ((Nil) (string-append required ", and " (type->string type) " is linear"))
                  (names
                   (string-append "this use needs "
                                  (copy-declaration names)
                                  ", which the definition must require"))))
          (None)))

    ;; Why an instance cannot be used where its head matched with
    ;; `bindings`: a variable it requires to be Copy, as `(requires (Copy
    ;; A))` does, is bound to a linear type. The instance's body was
    ;; checked with that variable unrestricted, so it may duplicate or
    ;; discard one, and a linear type there would be duplicated or lost.
    (: instance-copy-refusal
       (impl (Fn Program (List String) Instance Substitution -> (Option String))))
    (define (instance-copy-refusal program copy instance bindings)
      (fold-left (lambda (refusal var)
                   (match (Pair refusal (assoc-ref bindings var))
                     ((Pair (None) (Some bound))
                      (copy-refusal program
                                    copy
                                    bound
                                    (string-append "the instance "
                                                   (type->string (TCon (::class instance)
                                                                       (::types instance)))
                                                   " requires "
                                                   (copy-declaration (list var)))))
                     (_ refusal)))
                 (None) (::copy instance)))

    ;; ---- Releasing and cloning ----

    ;; `drop` and `clone` are the methods of the lifecycle classes, Drop and
    ;; Clone. What one runs for a value of a type that is not a type
    ;; variable is found from the type alone, so that the checker, which
    ;; charges its row, and mono, which emits its call, agree:
    ;;
    ;; - Trivial: a drop discards the value, and a clone shares it, both
    ;;   halves of its pair one reference. An unrestricted value is
    ;;   trivial, and so, to a drop, are a FnOnce, whose type does not say
    ;;   what it captured, so that what a `once` lambda moved in is
    ;;   abandoned, and data whose glue would run nothing else, so dropping
    ;;   a list of work items walks nothing.
    ;; - Implemented: a type with an instance of the class runs its method.
    ;; - Glue: other linear data is matched apart. A drop drops each linear
    ;;   immutable field; a clone clones each, shares the others, and builds
    ;;   the two values. A drop abandons a mutable field's content, as a
    ;;   lost cell's is abandoned.
    ;; - Refused: a FnOnce runs once, so it has no clone. Nor has, without a
    ;;   Clone instance, a type its library made linear with a Drop instance
    ;;   or Move, whose library decides what a copy of one is, or linear data
    ;;   with a mutable field, whose content a clone could only share.
    ;;
    ;; `Plan` is declared in core.sld, since a drop's evidence records it.
    (: lifecycle-plan (impl (Fn Program String (List String) Type -> Plan)))
    (define (lifecycle-plan program class copy type)
      (match type
        ((TCon "FnOnce" _)
         (if (string=? class drop-class)
             (Trivial)
             (Refused "a FnOnce runs once, so it has no clone")))
        ((TCon name _)
         (if (or (concrete-callable? type) (string=? name "FnMut"))
             (if (or (string=? class drop-class) (not (linear-type? program copy type)))
                 (Trivial)
                 (Refused "a callable with owned captures has no clone"))
             (if (any? (lambda (entry) (string=? name (::first entry))) builtin-types)
                 (Trivial)
                 (match (lifecycle-instance program class name)
                   ((Some instance) (Implemented instance))
                   ((None) (data-plan program class copy type))))))
        (_ (Trivial))))

    ;; The plan the checker records for a drop or a clone of `type`, or None
    ;; for a type variable, whose plan its instantiation decides.
    (: checked-plan (impl (Fn Program String (List String) Type -> (Option Plan))))
    (define (checked-plan program class copy type)
      (match type
        ((TRigid _) (None))
        (_ (Some (lifecycle-plan program class copy type)))))

    ;; Whether the plan for a ground type runs no more than the plan the
    ;; checker charged for the type the drop or clone was written at, which
    ;; mono checks for each one written in a program. Grounding only makes
    ;; data unrestricted, since a Copy variable is bound only to an
    ;; unrestricted type, at a signature's use and an instance's alike, so
    ;; glue may become trivial and nothing else changes; an instance is
    ;; found by its type's name in both.
    (: plan-covers? (impl (Fn (Option Plan) Plan -> Bool)))
    (define (plan-covers? checked ground)
      (match (Pair checked ground)
        ((Pair (None) _) #t)
        ((Pair _ (Trivial)) #t)
        ((Pair (Some (Implemented charged)) (Implemented found))
         (string=? (::name charged) (::name found)))
        ((Pair (Some (Glue)) (Glue)) #t)
        (_ #f)))

    ;; Declared data without an instance of the class.
    (: data-plan (impl (Fn Program String (List String) Type -> Plan)))
    (define (data-plan program class copy type)
      (let* ((name (type-name type)) (data (program-type program name)))
        (cond ((not (linear-type? program copy type)) (Trivial))
              ((string=? class drop-class)
               (if (drop-runs? program copy type (Nil) (Nil)) (Glue) (Trivial)))
              ((::owned? data)
               (Refused (string-append (short-name name)
                                       " is linear by its declaration, so only a Clone instance copies one")))
              ((any? (lambda (case) (any? ::mutable? (::fields case))) (::cases data))
               (Refused (string-append (short-name name)
                                       " has a mutable field, which a clone could only share; give it a Clone instance")))
              (else (Glue)))))

    (: type-name (impl (Fn Type -> String)))
    (define (type-name type)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: data has a name"))))

    ;; Whether dropping a value of `type` runs anything: an instance's
    ;; method, or the drop of a type variable, which a ground type may give
    ;; one. A declaration met again at the same arguments adds nothing, and
    ;; one met again at other arguments is taken to run something, so that
    ;; glue refuses it (`glue-search`). `keys` and `names` are those met on
    ;; the way here.
    (: drop-runs? (impl (Fn Program (List String) Type (List String) (List String) -> Bool)))
    (define (drop-runs? program copy type keys names)
      (match type
        ((TRigid name) (not (member? name copy)))
        ;; Dropping a FnOnce runs its dropper, which drops what it captured
        ;; (control.sld, "Droppers"), so data holding one runs glue.
        ((TCon "FnOnce" _) #t)
        ((TCon name _)
         (cond ((or (concrete-callable? type) (string=? name "FnMut"))
                (linear-type? program copy type))
               ((member? (type-key type) keys) #f)
               ((member? name names) #t)
               ((any? (lambda (entry) (string=? name (::first entry))) builtin-types) #f)
               (else (match (lifecycle-instance program drop-class name)
                       ((Some _) #t)
                       ((None) (fields-drop-run? program copy type keys names))))))
        (_ #f)))

    (: fields-drop-run? (impl (Fn Program (List String) Type (List String) (List String) -> Bool)))
    (define (fields-drop-run? program copy type keys names)
      (match type
        ((TCon name _)
         (any? (lambda (case)
                 (any? (lambda (field)
                         (drop-runs? program
                                     copy
                                     (::second field)
                                     (Cons (type-key type) keys)
                                     (Cons name names)))
                       (glue-fields program copy type case)))
               (::cases (program-type program name))))
        (_ #f)))

    ;; The fields of `case` that glue drops or clones, by index, at the type
    ;; `type` gives its declaration's parameters: the immutable linear ones.
    (: glue-fields (impl (Fn Program (List String) Type Case -> (List (Pair I64 Type)))))
    (define (glue-fields program copy type case)
      (filter (lambda (field) (linear-type? program copy (::second field)))
              (concatenate
               (map-indexed (lambda (index pair)
                              (if (::mutable? (::first pair))
                                  (Nil)
                                  (list (Pair index (::second pair)))))
                            (zip (::fields case) (field-types program type case))))))

    ;; Each field of `case` at the type `type` gives its declaration's
    ;; parameters.
    (: field-types (impl (Fn Program Type Case -> (List Type))))
    (define (field-types program type case)
      (let ((bindings (match type
                        ((TCon name args) (zip (::params (program-type program name)) args))
                        (_ (Nil)))))
        (map (lambda (field) (substitute bindings (::type field))) (::fields case))))

    ;; An instance of a lifecycle class is declared in its type's library
    ;; for the type at distinct variables, so a type has at most one of
    ;; each, found by its name.
    (: lifecycle-instance (impl (Fn Program String String -> (Option Instance))))
    (define (lifecycle-instance program class name)
      (find (lambda (instance)
              (match (::types instance)
                ((Cons _ (Cons (TCon head _) (Nil))) (string=? head name))
                (_ #f)))
            (class-instances program class)))

    ;; The rows a drop or a clone of a value of `type` performs, or why it
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
       (keys (List String))
       (names (List String))))

    (: lifecycle-rows
       (impl
        (Fn Program String (List String) (List Constraint) Type -> (Result (List Type) String))))
    (define (lifecycle-rows program class copy givens type)
      (match (lifecycle-search program class copy givens type (Ok (RowSearch (Nil) (Nil) (Nil))))
        ((Ok found) (Ok (reverse (::rows found))))
        ((Err message) (Err message))))

    (: lifecycle-search
       (impl (Fn Program
                 String
                 (List String)
                 (List Constraint)
                 Type
                 (Result RowSearch String)
                 -> (Result RowSearch String))))
    (define (lifecycle-search program class copy givens type progress)
      (match (Pair type progress)
        ((Pair _ (Err message)) (Err message))
        ((Pair (TRigid name) (Ok found))
         (cond ((member? name copy) progress)
               (else (match (given-row givens class name)
                       ((Some row)
                        (Ok (RowSearch-rows-set found (Cons row (::rows found)))))
                       ((None) (Err (missing-requirement class name)))))))
        ((Pair _ (Ok found))
         (match (lifecycle-plan program class copy type)
           ((Trivial) (trivial-rows program class copy type found))
           ((Implemented instance) (instance-search program class copy givens type instance found))
           ((Glue) (glue-search program class copy givens type found))
           ((Refused reason) (Err reason))))))

    ;; A drop that runs nothing performs nothing, except a FnOnce's:
    ;; dropping one unrun drops what it captured, whose drops its own row
    ;; allows (ownership.sld, "Drops that may run"), so dropping a
    ;; `(dyn (FnOnce A -> B ! e))` performs `e`, less its control effects, which no
    ;; drop performs.
    (: trivial-rows
       (impl (Fn Program String (List String) Type RowSearch -> (Result RowSearch String))))
    (define (trivial-rows program class copy type found)
      (match (callable-arrow type)
        ((Some (TFun _ _ row))
         (if (and (string=? class drop-class) (linear-type? program copy type))
             (Ok (RowSearch-rows-set found
                                     (Cons (without-control program row) (::rows found))))
             (Ok found)))
        (_ (Ok found))))

    (: without-control (impl (Fn Program Type -> Type)))
    (define (without-control program row)
      (match row
        ((TRow labels tail)
         (TRow (filter (lambda (label)
                         (match (table-ref (::effects program) label)
                           ((Some effect) (null? (::control effect)))
                           ((None) #t)))
                       labels)
               (match tail
                 ((Some inner) (Some (without-control program inner)))
                 ((None) (None)))))
        (_ row)))

    (: missing-requirement (impl (Fn String String -> String)))
    (define (missing-requirement class name)
      (string-append (if (string=? class drop-class) "dropping" "cloning")
                     " a value of type "
                     name
                     " needs ("
                     (short-name class)
                     " e "
                     name
                     "); give the definition that requirement"))

    ;; An instance performs the labels its head names, and, for each
    ;; requirement, as `(Drop e A)`, what the class's method performs at the
    ;; type `type` gives `A`, which is the row `e` its head ends with. That
    ;; type is part of `type`, so the search ends. It cannot run where a
    ;; variable it requires Copy is given a linear type.
    (: instance-search
       (impl (Fn Program
                 String
                 (List String)
                 (List Constraint)
                 Type
                 Instance
                 RowSearch
                 -> (Result RowSearch String))))
    (define (instance-search program class copy givens type instance found)
      (let ((bindings (instance-bindings instance type)))
        (match (instance-copy-refusal program copy instance bindings)
          ((Some refusal) (Err refusal))
          ((None)
           (fold-left (lambda (progress required)
                        (lifecycle-search program
                                          class
                                          copy
                                          givens
                                          (substitute bindings
                                                      (list-ref (::types required) 1))
                                          progress))
                      (Ok
                       (RowSearch-rows-set found (Cons (head-row instance) (::rows found))))
                      (::requires instance))))))

    ;; The labels a lifecycle instance's head names, as a closed row.
    (: head-row (impl (Fn Instance -> Type)))
    (define (head-row instance)
      (match (::types instance)
        ((Cons (TRow labels _) _) (TRow labels (None)))
        (_ (panic "internal error: a lifecycle instance names its row"))))

    ;; The types `type` gives a lifecycle instance's variables, matched
    ;; against its head, which names its type at distinct variables.
    (: instance-bindings (impl (Fn Instance Type -> Substitution)))
    (define (instance-bindings instance type)
      (match (Pair (::types instance) type)
        ((Pair (Cons _ (Cons (TCon _ params) (Nil))) (TCon _ args))
         (zip (map (lambda (param)
                     (match param
                       ((TRigid name) name)
                       (_ "")))
                   params)
              args))
        (_ (panic "internal error: a lifecycle instance names a row and a declared type"))))

    (: glue-search
       (impl (Fn Program
                 String
                 (List String)
                 (List Constraint)
                 Type
                 RowSearch
                 ->
                 (Result RowSearch String))))
    (define (glue-search program class copy givens type found)
      (let ((name (type-name type)) (key (type-key type)))
        (cond ((member? key (::keys found)) (Ok found))
              ((member? name (::names found)) (Err (nonregular-glue class type)))
              (else
               (match (glue-fields-search program
                                          class
                                          copy
                                          givens
                                          type
                                          (RowSearch (::rows found)
                                                     (Cons key (::keys found))
                                                     (Cons name (::names found))))
                 ((Ok inner) (Ok (RowSearch-names-set inner (::names found))))
                 (failed failed))))))

    ;; Glue performs what dropping or cloning each field it reaches does.
    (: glue-fields-search
       (impl (Fn Program
                 String
                 (List String)
                 (List Constraint)
                 Type
                 RowSearch
                 ->
                 (Result RowSearch String))))
    (define (glue-fields-search program class copy givens type found)
      (fold-left (lambda (progress field)
                   (lifecycle-search program class copy givens (::second field) progress))
                 (Ok found)
                 (concatenate (map (lambda (case) (glue-fields program copy type case))
                                   (::cases (program-type program (type-name type)))))))

    ;; A declaration met again at other arguments would need glue for every
    ;; depth, so it needs an instance instead.
    (: nonregular-glue (impl (Fn String Type -> String)))
    (define (nonregular-glue class type)
      (string-append "glue cannot "
                     (if (string=? class drop-class) "drop " "clone ")
                     (type->string type)
                     ", which contains itself at other type arguments; give "
                     (short-name (type-name type))
                     " a "
                     (short-name class)
                     " instance"))

    ;; The row of the enclosing definition's requirement of the class for
    ;; `A`, as `(Drop e A)`'s.
    (: given-row (impl (Fn (List Constraint) String String -> (Option Type))))
    (define (given-row givens class name)
      (match (find (lambda (given)
                     (and (string=? (::class given) class)
                          (match (::types given)
                            ((Cons _ (Cons (TRigid other) (Nil))) (string=? other name))
                            (_ #f))))
                   givens)
        ((Some given) (Some (first-type (::types given))))
        ((None) (None))))

    (: first-type (impl (Fn (List Type) -> Type)))
    (define (first-type types)
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
    (: contains-itself? (impl (Fn Program DataType -> Bool)))
    (define (contains-itself? program data)
      (any? (lambda (field) (reaches? program (::name data) field (Nil)))
            (struct-field-types data (map TRigid (::params data)))))

    (: reaches? (impl (Fn Program String Type (List String) -> Bool)))
    (define (reaches? program target type entered)
      (match type
        ((TCon name args)
         (cond ((string=? name target) #t)
               ((or (member? name entered)
                    (any? (lambda (entry) (string=? name (::first entry))) builtin-types))
                #f)
               (else (let ((data (program-type program name)))
                       (and (not (::enum? data))
                            (any?
                             (lambda (field) (reaches? program target field (Cons name entered)))
                             (struct-field-types data args)))))))
        (_ #f)))

    ;; The field types of a struct's one case, with its parameters bound to
    ;; `args`.
    (: struct-field-types (impl (Fn DataType (List Type) -> (List Type))))
    (define (struct-field-types data args)
      (let ((bindings (zip (::params data) args)))
        (match (::cases data)
          ((Cons case _)
           (map (lambda (field) (substitute bindings (::type field))) (::fields case)))
          ((Nil) (panic "internal error: a struct has one case")))))))
