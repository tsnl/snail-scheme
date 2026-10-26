;; Compiler-owned properties of values. The language distinguishes transfer
;; from sharing even while its managed, aliased mutable containers permit
;; neither. A procedure's arrow does not describe its captured environment.
(define-library (lofi compiler capabilities)
  (export capability-class? capability-type? affine-type?)
  (import
   (lofi base)
   (lofi compiler core))
  (begin

    ;; ---- Structural evidence ----

    (: capability-class? (-> String Bool))
    (define (capability-class? name)
      (member? name (list "lofi.base:Send" "lofi.base:Sync")))

    (: capability-type? (-> Program String Type (List Constraint) (List String) Bool))
    (define (capability-type? program property type givens visiting)
      (or (any? (lambda (given) (and (string=? property (Constraint-class given))
                                     (types=? (list type) (Constraint-types given)))) givens)
          (match type
            ((TCon name args)
             (and (not (member? name (list "Ref" "Array" "Any" "Funcref")))
                  (every? (lambda (arg) (capability-type? program property arg givens visiting)) args)
                  (or (member? name visiting)
                      (any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types)
                      (capability-fields? program property type givens (Cons name visiting)))))
            ((TRow _ _) #t)
            (_ #f))))

    ;; Arguments are checked before cutting a recursive declaration by name.
    ;; Thus List<Ref<I64>> cannot pass because List has been visited already.
    (: capability-fields? (-> Program String Type (List Constraint) (List String) Bool))
    (define (capability-fields? program property type givens visiting)
      (match type
        ((TCon name args)
         (let* ((data (program-type program name)) (bindings (zip (DataType-params data) args)))
           (every? (lambda (case)
                     (every? (lambda (field) (capability-type? program property (substitute bindings (Field-type field)) givens visiting))
                             (Case-fields case)))
                   (DataType-cases data))))
        (_ #f)))

    ;; ---- Type grades ----

    ;; One query's progress: whether it has found an affine field yet, and
    ;; which declarations it has entered. A declaration is entered once per
    ;; query, including across sibling fields, because re-exploring a
    ;; recursive graph by every path is exponential. Carrying the set rather
    ;; than mutating one keeps the query a function of its arguments.
    (struct Affinity
      ((found? Bool)
       (entered (List String))))

    ;; Type variables range over unrestricted values. Concrete fields can
    ;; make a record affine; ordinary arrows never describe owned captures.
    (: affine-type? (-> Program Type Bool))
    (define (affine-type? program type)
      (Affinity-found? (affine-search program type (Nil))))

    (: affine-search (-> Program Type (List String) Affinity))
    (define (affine-search program type entered)
      (match type
        ((TCon "Once" _) (Affinity #t entered))
        ((TCon name args)
         (let ((found (affine-any program args entered)))
           (cond ((Affinity-found? found) found)
                 ((or (member? name (Affinity-entered found))
                      (any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types))
                  found)
                 (else (affine-fields program name args (Cons name (Affinity-entered found)))))))
        (_ (Affinity #f entered))))

    ;; Arguments are searched before a recursive declaration is cut by name.
    ;; Thus List<Ref<I64>> cannot pass because List has been entered already.
    (: affine-any (-> Program (List Type) (List String) Affinity))
    (define (affine-any program types entered)
      (fold-left (lambda (found type) (affine-next program type found))
                 (Affinity #f entered) types))

    (: affine-next (-> Program Type Affinity Affinity))
    (define (affine-next program type found)
      (if (Affinity-found? found) found (affine-search program type (Affinity-entered found))))

    (: affine-fields (-> Program String (List Type) (List String) Affinity))
    (define (affine-fields program name args entered)
      (let* ((data (program-type program name)) (bindings (zip (DataType-params data) args)))
        (fold-left (lambda (found case) (affine-case program bindings case found))
                   (Affinity #f entered) (DataType-cases data))))

    (: affine-case (-> Program Substitution Case Affinity Affinity))
    (define (affine-case program bindings case found)
      (fold-left (lambda (found field) (affine-next program (substitute bindings (Field-type field)) found))
                 found (Case-fields case)))))
