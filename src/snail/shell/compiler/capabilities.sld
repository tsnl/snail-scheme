;; Compiler-owned properties of types, found from their structure: whether a
;; type is first-order data, whether it is linear, what dropping one of its
;; values runs, and whether a struct contains itself. A procedure's arrow
;; does not describe its captured environment.
(define-library (snail shell compiler capabilities)
  (export
   linear-type? missing-copy copy-declaration first-order-type? contains-itself?
   Release Discard Destroy Glue release released-fields drop-instance drop-rows)
  (import
   (snail core base)
   (snail shell compiler core))
  (begin

    ;; ---- Data ----

    ;; A type is first-order data when nothing inside it, through type
    ;; arguments and declared fields, is a function, a Funcref or an Any.
    ;; Its TypeId then names all of it: a function type's says only that it
    ;; is one, and an Any's nothing of what it holds. The search returns the
    ;; declarations it has entered, each once, as the search for linear
    ;; fields below does, or None once it finds something that is not data.
    (: first-order-type? (-> Program Type Bool))
    (define (first-order-type? program type)
      (match (first-order-search program type (Some (Nil)))
        ((Some _) #t)
        ((None) #f)))

    ;; Arguments are searched before a recursive declaration is cut by name.
    (: first-order-search (-> Program Type (Option (List String)) (Option (List String))))
    (define (first-order-search program type entered)
      (match (Pair type entered)
        ((Pair _ (None)) (None))
        ((Pair (TCon name args) _)
         (match (fold-left (lambda (found arg) (first-order-search program arg found)) entered args)
           ((Some names)
            (cond ((member? name (list "Any" "Funcref")) (None))
                  ((or (member? name names)
                       (any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types))
                   (Some names))
                  (else (first-order-fields program name args (Cons name names)))))
           ((None) (None))))
        ((Pair (TRow _ _) _) entered)
        (_ (None))))

    (: first-order-fields (-> Program String (List Type) (List String) (Option (List String))))
    (define (first-order-fields program name args entered)
      (let* ((data (program-type program name)) (bindings (zip (DataType-params data) args)))
        (fold-left (lambda (found field)
                     (first-order-search program (substitute bindings (Field-type field)) found))
                   (Some entered) (concatenate (map Case-fields (DataType-cases data))))))

    ;; ---- Type grades ----

    ;; One query's progress: whether it has found a linear field yet, and
    ;; what it has entered. Each instantiation of a declaration, named in
    ;; `keys` by its `type-key`, is entered once per query, including across
    ;; sibling fields, because re-exploring a recursive graph by every path
    ;; is exponential. `names` holds their declarations: one met again at
    ;; other arguments, as non-regular recursion would, has its arguments
    ;; searched as if it held them directly, which keeps the query finite.
    ;; Carrying the sets rather than mutating them keeps the query a
    ;; function of its arguments.
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
    (: linear-type? (-> Program (List String) Type Bool))
    (define (linear-type? program copy type)
      (Linearity-found? (linear-search program copy type (Linearity #f (Nil) (Nil)))))

    (: linear-search (-> Program (List String) Type Linearity Linearity))
    (define (linear-search program copy type progress)
      (match type
        ((TCon "FnOnce" _) (Linearity-found?-set progress #t))
        ((TCon name args) (linear-instance program copy name args progress))
        ((TRigid name) (if (member? name copy) progress (Linearity-found?-set progress #t)))
        (_ progress)))

    ;; A builtin holds its arguments directly, and so, conservatively, does
    ;; a declaration met again at other arguments. Any other declaration is
    ;; searched through its fields, with its parameters bound to `args`.
    (: linear-instance (-> Program (List String) String (List Type) Linearity Linearity))
    (define (linear-instance program copy name args progress)
      (let ((key (type-key (TCon name args))))
        (cond ((member? key (Linearity-keys progress)) progress)
              ((or (member? name (Linearity-names progress))
                   (any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types))
               (linear-any program copy args progress))
              (else
               (linear-fields program
                              copy
                              name
                              args
                              (Linearity #f
                                         (Cons key (Linearity-keys progress))
                                         (Cons name (Linearity-names progress))))))))

    (: linear-any (-> Program (List String) (List Type) Linearity Linearity))
    (define (linear-any program copy types progress)
      (fold-left (lambda (found type) (linear-next program copy type found)) progress types))

    (: linear-next (-> Program (List String) Type Linearity Linearity))
    (define (linear-next program copy type found)
      (if (Linearity-found? found)
          found
          (linear-search program copy type found)))

    ;; A declaration's parameters are bound to `args`, so its fields hold
    ;; only the variables of the type being searched.
    (: linear-fields (-> Program (List String) String (List Type) Linearity Linearity))
    (define (linear-fields program copy name args progress)
      (let* ((data (program-type program name)) (bindings (zip (DataType-params data) args)))
        (if (DataType-owned? data)
            (Linearity-found?-set progress #t)
            (fold-left (lambda (found case) (linear-case program copy bindings case found))
                       progress (DataType-cases data)))))

    ;; A mutable field never makes its holder linear: its content leaves
    ;; only by being swapped out, so sharing the holder never duplicates it.
    (: linear-case (-> Program (List String) Substitution Case Linearity Linearity))
    (define (linear-case program copy bindings case found)
      (fold-left (lambda (found field)
                   (if (Field-mutable? field)
                       found
                       (linear-next program copy (substitute bindings (Field-type field)) found)))
                 found (Case-fields case)))

    ;; The variables a signature would have to declare Copy to make `type`
    ;; unrestricted, or none when a concrete part of it is linear, which
    ;; no declaration changes. A variable reached through data makes its
    ;; type linear; one inside an arrow does not.
    (: missing-copy (-> Program (List String) Type (List String)))
    (define (missing-copy program copy type)
      (let ((free (filter (lambda (name) (not (member? name copy))) (data-variables type))))
        (if (linear-type? program (append free copy) type) (Nil) free)))

    (: data-variables (-> Type (List String)))
    (define (data-variables type)
      (match type
        ((TRigid name) (list name))
        ((TCon _ args) (delete-duplicates string=? (concatenate (map data-variables args))))
        (_ (Nil))))

    ;; The requirements naming `names`, as a diagnostic quotes them.
    (: copy-declaration (-> (List String) String))
    (define (copy-declaration names)
      (string-join (map (lambda (name) (string-append "(Copy " name ")")) names) " "))

    ;; ---- Releasing ----

    ;; What `drop` runs for a value of a type that is not a type variable,
    ;; found from the type alone, so that the checker, which charges its
    ;; row, and mono, which emits its call, agree. An unrestricted value and
    ;; a FnOnce are discarded: a FnOnce's frames hold nothing a drop must
    ;; run. A type with a Drop instance runs its method. Other linear data
    ;; runs glue, which matches the value apart and drops each linear
    ;; immutable field, when dropping one of those runs anything; otherwise
    ;; it is discarded too, so dropping a list of work items walks nothing.
    ;; A mutable field's content is abandoned, as a lost cell's is.
    (enum Release
      (Discard)
      (Destroy
       ((instance Instance)))
      (Glue))

    (: release (-> Program (List String) Type Release))
    (define (release program copy type)
      (match type
        ((TCon "FnOnce" _) (Discard))
        ((TCon name args)
         (cond ((not (linear-type? program copy type)) (Discard))
               ((any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types) (Discard))
               (else (match (drop-instance program name)
                       ((Some instance) (Destroy instance))
                       ((None) (if (drop-runs? program copy type (Nil) (Nil)) (Glue) (Discard)))))))
        (_ (Discard))))

    ;; Whether dropping a value of `type` runs anything: an instance's
    ;; method, or the drop of a type variable, which a ground type may give
    ;; one. A declaration met again at the same arguments adds nothing, and
    ;; one met again at other arguments is taken to run something, so that
    ;; glue refuses it (`glue-search`). `keys` and `names` are those met on
    ;; the way here.
    (: drop-runs? (-> Program (List String) Type (List String) (List String) Bool))
    (define (drop-runs? program copy type keys names)
      (match type
        ((TRigid name) (not (member? name copy)))
        ((TCon "FnOnce" _) #f)
        ((TCon name _)
         (cond ((member? (type-key type) keys) #f)
               ((member? name names) #t)
               ((any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types) #f)
               (else (match (drop-instance program name)
                       ((Some _) #t)
                       ((None) (fields-drop-run? program copy type keys names))))))
        (_ #f)))

    (: fields-drop-run? (-> Program (List String) Type (List String) (List String) Bool))
    (define (fields-drop-run? program copy type keys names)
      (match type
        ((TCon name _)
         (any? (lambda (case)
                 (any? (lambda (field)
                         (drop-runs? program
                                     copy
                                     (Pair-second field)
                                     (Cons (type-key type) keys)
                                     (Cons name names)))
                       (released-fields program copy type case)))
               (DataType-cases (program-type program name))))
        (_ #f)))

    ;; The fields of `case` that glue drops, by index, at the type `type`
    ;; gives its declaration's parameters: the immutable linear ones.
    (: released-fields (-> Program (List String) Type Case (List (Pair I64 Type))))
    (define (released-fields program copy type case)
      (let ((bindings (match type
                        ((TCon name args) (zip (DataType-params (program-type program name)) args))
                        (_ (Nil)))))
        (filter (lambda (field) (linear-type? program copy (Pair-second field)))
                (concatenate
                 (map-indexed (lambda (index field)
                                (if (Field-mutable? field)
                                    (Nil)
                                    (list (Pair index (substitute bindings (Field-type field))))))
                              (Case-fields case))))))

    ;; A Drop instance is declared in its type's library for the type at
    ;; distinct variables, so a type has at most one, found by its name.
    (: drop-instance (-> Program String (Option Instance)))
    (define (drop-instance program name)
      (find (lambda (instance)
              (match (Instance-types instance)
                ((Cons _ (Cons (TCon head _) (Nil))) (string=? head name))
                (_ #f)))
            (class-instances program drop-class)))

    ;; The rows dropping a value of `type` performs, or why it cannot be
    ;; dropped, under the enclosing definition's Copy variables and
    ;; requirements: a type variable's row is its `(Drop e A)`'s, an
    ;; instance's is in its head, and glue performs its fields' rows. Each
    ;; instantiation of a declaration is entered once, so a recursive type
    ;; adds its fields' rows once. A declaration met again at other
    ;; arguments would need glue at unboundedly many types, so it needs an
    ;; instance instead.
    (struct Dropping
      ((rows (List Type))
       (keys (List String))
       (names (List String))))

    (: drop-rows
       (-> Program (List String) (List Constraint) Type (Result (List Type) String)))
    (define (drop-rows program copy givens type)
      (match (drop-search program copy givens type (Ok (Dropping (Nil) (Nil) (Nil))))
        ((Ok found) (Ok (reverse (Dropping-rows found))))
        ((Err message) (Err message))))

    (: drop-search
       (-> Program
           (List String)
           (List Constraint)
           Type
           (Result Dropping String)
           (Result Dropping String)))
    (define (drop-search program copy givens type progress)
      (match (Pair type progress)
        ((Pair _ (Err message)) (Err message))
        ((Pair (TRigid name) (Ok found))
         (cond ((member? name copy) progress)
               (else (match (given-drop-row givens name)
                       ((Some row) (Ok (Dropping-rows-set found (Cons row (Dropping-rows found)))))
                       ((None) (Err (string-append "dropping a value of type "
                                                   name
                                                   " needs (Drop e "
                                                   name
                                                   "); give the definition that requirement")))))))
        ((Pair _ (Ok found))
         (match (release program copy type)
           ((Discard) progress)
           ((Destroy instance)
            (Ok (Dropping-rows-set found (Cons (first-type (Instance-types instance))
                                               (Dropping-rows found)))))
           ((Glue) (glue-search program copy givens type found))))))

    (: glue-search
       (-> Program (List String) (List Constraint) Type Dropping (Result Dropping String)))
    (define (glue-search program copy givens type found)
      (match type
        ((TCon name _)
         (let ((key (type-key type)))
           (cond ((member? key (Dropping-keys found)) (Ok found))
                 ((member? name (Dropping-names found))
                  (Err (string-append "glue cannot drop "
                                      (type->string type)
                                      ", which contains itself at other type arguments; give "
                                      (short-name name)
                                      " a Drop instance")))
                 (else
                  (fold-left (lambda (progress field)
                               (drop-search program copy givens (Pair-second field) progress))
                             (Ok (Dropping (Dropping-rows found)
                                           (Cons key (Dropping-keys found))
                                           (Cons name (Dropping-names found))))
                             (concatenate (map (lambda (case)
                                                 (released-fields program copy type case))
                                               (DataType-cases (program-type program name)))))))))
        (_ (panic "internal error: glue drops data"))))

    ;; The row of the enclosing definition's `(Drop e A)` for `A`.
    (: given-drop-row (-> (List Constraint) String (Option Type)))
    (define (given-drop-row givens name)
      (match (find (lambda (given)
                     (and (string=? (Constraint-class given) drop-class)
                          (match (Constraint-types given)
                            ((Cons _ (Cons (TRigid other) (Nil))) (string=? other name))
                            (_ #f))))
                   givens)
        ((Some given) (Some (first-type (Constraint-types given))))
        ((None) (None))))

    (: first-type (-> (List Type) Type))
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
    (: contains-itself? (-> Program DataType Bool))
    (define (contains-itself? program data)
      (any? (lambda (field) (reaches? program (DataType-name data) field (Nil)))
            (struct-field-types data (map TRigid (DataType-params data)))))

    (: reaches? (-> Program String Type (List String) Bool))
    (define (reaches? program target type entered)
      (match type
        ((TCon name args)
         (cond ((string=? name target) #t)
               ((or (member? name entered)
                    (any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types))
                #f)
               (else (let ((data (program-type program name)))
                       (and (not (DataType-enum? data))
                            (any?
                             (lambda (field) (reaches? program target field (Cons name entered)))
                             (struct-field-types data args)))))))
        (_ #f)))

    ;; The field types of a struct's one case, with its parameters bound to
    ;; `args`.
    (: struct-field-types (-> DataType (List Type) (List Type)))
    (define (struct-field-types data args)
      (let ((bindings (zip (DataType-params data) args)))
        (match (DataType-cases data)
          ((Cons case _)
           (map (lambda (field) (substitute bindings (Field-type field))) (Case-fields case)))
          ((Nil) (panic "internal error: a struct has one case")))))))
