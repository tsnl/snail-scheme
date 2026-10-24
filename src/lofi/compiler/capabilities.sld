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

    (: capability-type? (-> Program String Type (List Constraint) (List String) Bool ! mut))
    (define (capability-type? program property type givens visiting)
      (or (any? (lambda (given) (and (string=? property (Constraint-class given))
                                     (types=? (list type) (Constraint-types given)))) givens)
          (match type
            ((TVar _ cell)
             (match (ref-get cell)
               ((Some bound) (capability-type? program property bound givens visiting))
               ((None) #f)))
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
    (: capability-fields? (-> Program String Type (List Constraint) (List String) Bool ! mut))
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

    ;; Type variables range over unrestricted values. Concrete fields can
    ;; make a record affine; ordinary arrows never describe owned captures.
    (: affine-type? (-> Program Type Bool ! mut))
    (define (affine-type? program type)
      (affine-within? program type (ref (Nil))))

    ;; Each declaration is explored once per query, including across sibling
    ;; fields. Re-exploring a recursive graph by every path is exponential.
    (: affine-within? (-> Program Type (Ref (List String)) Bool ! mut))
    (define (affine-within? program type visiting)
      (match type
        ((TVar _ cell) (match (ref-get cell) ((Some bound) (affine-within? program bound visiting)) ((None) #f)))
        ((TCon name args)
         (or (string=? name "Once")
             (any? (lambda (arg) (affine-within? program arg visiting)) args)
             (and (not (member? name (ref-get visiting)))
                  (not (any? (lambda (entry) (string=? name (Pair-first entry))) builtin-types))
                  (let* ((data (program-type program name)) (bindings (zip (DataType-params data) args)))
                    (ref-set! visiting (Cons name (ref-get visiting)))
                    (any? (lambda (case)
                            (any? (lambda (field) (affine-within? program (substitute bindings (Field-type field)) visiting))
                                  (Case-fields case)))
                          (DataType-cases data))))))
        (_ #f)))))
