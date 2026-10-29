;; Compiler-owned properties of types, found from their structure: whether a
;; type is first-order data, whether it is linear, and whether a struct
;; contains itself. A procedure's arrow does not describe its captured
;; environment.
(define-library (snail shell compiler capabilities)
  (export linear-type? missing-copy copy-declaration first-order-type? contains-itself?)
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
    ;; which declarations it has entered. A declaration is entered once per
    ;; query, including across sibling fields, because re-exploring a
    ;; recursive graph by every path is exponential. Carrying the set rather
    ;; than mutating one keeps the query a function of its arguments.
    (struct Linearity
      ((found? Bool)
       (entered (List String))))

    ;; A type variable is linear unless `copy` names it, as a signature's
    ;; `(requires (Copy A))` does. Concrete fields can make a record linear;
    ;; ordinary arrows never describe owned captures.
    (: linear-type? (-> Program (List String) Type Bool))
    (define (linear-type? program copy type)
      (Linearity-found? (linear-search program copy type (Nil))))

    (: linear-search (-> Program (List String) Type (List String) Linearity))
    (define (linear-search program copy type entered)
      (match type
        ((TCon "Once" _) (Linearity #t entered))
        ((TCon name args)
         (let ((found (linear-any program copy args entered)))
           (cond ((Linearity-found? found) found)
                 ((or (member? name (Linearity-entered found))
                      (any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types))
                  found)
                 (else
                  (linear-fields program copy name args (Cons name (Linearity-entered found)))))))
        ((TRigid name) (Linearity (not (member? name copy)) entered))
        (_ (Linearity #f entered))))

    ;; Arguments are searched before a recursive declaration is cut by name.
    ;; Thus List<Ref<I64>> cannot pass because List has been entered already.
    (: linear-any (-> Program (List String) (List Type) (List String) Linearity))
    (define (linear-any program copy types entered)
      (fold-left (lambda (found type) (linear-next program copy type found))
                 (Linearity #f entered) types))

    (: linear-next (-> Program (List String) Type Linearity Linearity))
    (define (linear-next program copy type found)
      (if (Linearity-found? found)
          found
          (linear-search program copy type (Linearity-entered found))))

    ;; A declaration's parameters are bound to `args`, so its fields hold
    ;; only the variables of the type being searched.
    (: linear-fields (-> Program (List String) String (List Type) (List String) Linearity))
    (define (linear-fields program copy name args entered)
      (let* ((data (program-type program name)) (bindings (zip (DataType-params data) args)))
        (fold-left (lambda (found case) (linear-case program copy bindings case found))
                   (Linearity #f entered) (DataType-cases data))))

    (: linear-case (-> Program (List String) Substitution Case Linearity Linearity))
    (define (linear-case program copy bindings case found)
      (fold-left (lambda (found field)
                   (linear-next program copy (substitute bindings (Field-type field)) found))
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

    ;; ---- Buildable structs ----

    ;; Whether every value of the struct `data` would hold another of
    ;; itself. The search follows struct fields and cell contents, and stops
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
        ((TCon "Ref" (Cons content _)) (reaches? program target content entered))
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
