;; A type with its variables bound, as the old compiler's `substitute`
;; (src/snail/shell/compiler/core.sld) makes it: each variable a binding
;; names is the type bound to it, and every other is left as it is. A
;; binding is a variable and its type; when two name one variable, the
;; first is the one that holds, as one-way matching, (snail compiler typer
;; matching), puts the latest binding first. A row's tail that becomes a
;; row joins its labels to the row's, so the substituted row is the one
;; row they make, its labels still a set.
(define-library (snail compiler types substitution)
  (export
   substituted
   substituted-requirement)
  (import
   (snail core base)
   (snail compiler types type)
   (snail compiler types scheme)
   (only (snail compiler types equality) effect-set same-variable?))
  (begin

    ;; ---- Types ----

    (: substituted (impl (Fn (List (Pair TypeVariable Type)) Type -> Type)))
    (define (substituted bindings type)
      (match type
        ((Var variable) (bound-to bindings variable type))
        ((Con global arguments)
         (Con global (map (lambda (argument) (substituted bindings argument)) arguments)))
        ((Callable former contract arrow)
         (Callable former contract (substituted-arrow bindings arrow)))
        ((Code arrow) (Code (substituted-arrow bindings arrow)))
        ((Row effects) (Row (substituted-effects bindings effects)))))

    (: bound-to (impl (Fn (List (Pair TypeVariable Type)) TypeVariable Type -> Type)))
    (define (bound-to bindings variable type)
      (match (find (lambda (binding) (same-variable? (::first binding) variable)) bindings)
        ((Some binding) (::second binding))
        ((None) type)))

    (: substituted-arrow (impl (Fn (List (Pair TypeVariable Type)) Arrow -> Arrow)))
    (define (substituted-arrow bindings arrow)
      (Arrow (map (lambda (parameter) (substituted bindings parameter)) (::parameters arrow))
             (substituted bindings (::result arrow))
             (substituted-effects bindings (::effects arrow))))

    ;; A tail that becomes a row joins its labels.
    (: substituted-effects (impl (Fn (List (Pair TypeVariable Type)) Effects -> Effects)))
    (define (substituted-effects bindings effects)
      (match (::tail effects)
        ((None) effects)
        ((Some tail)
         (match (substituted bindings tail)
           ((Row (Effects labels rest))
            (Effects (effect-set (append (::labels effects) labels)) rest))
           (other (Effects (::labels effects) (Some other)))))))

    ;; ---- Requirements ----

    (: substituted-requirement
       (impl (Fn (List (Pair TypeVariable Type)) Requirement -> Requirement)))
    (define (substituted-requirement bindings requirement)
      (match requirement
        ((ClassRequirement class types)
         (ClassRequirement class (map (lambda (type) (substituted bindings type)) types)))
        ((CallableRequirement contract receiver arrow)
         (CallableRequirement contract
                              (substituted bindings receiver)
                              (substituted-arrow bindings arrow)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-substitution)
    (import
     (only (snail compiler names globals) Global ClassGlobal)
     (snail stage0 testing))
    (begin
      (define (test-substitution)
        (test-types)
        (test-rows)
        (test-requirements))

      (define (global name)
        (Global (list "main") name 0))

      (define i64 (Con (global "I64") (list)))
      (define f64 (Con (global "F64") (list)))
      (define a (Written "a"))
      (define b (Written "b"))

      (define (closed labels)
        (Effects labels (None)))

      ;; A bound variable is its type wherever it is written, the first
      ;; binding of it holding; an unbound one stays.
      (define (test-types)
        (expect (substituted (list (Pair a i64)) (Con (global "List") (list (Var a))))
                (Con (global "List") (list i64)))
        (expect (substituted (list (Pair a i64) (Pair a f64)) (Var a)) i64)
        (expect (substituted (list (Pair a i64)) (Var b)) (Var b))
        (expect (substituted (list (Pair (Own a) i64)) (Var a)) (Var a))
        (expect (substituted (list (Pair a i64))
                             (Callable (Dyn)
                                       (FnContract)
                                       (Arrow (list (Var a)) (Var a) (closed (list)))))
                (Callable (Dyn) (FnContract) (Arrow (list i64) i64 (closed (list))))))

      ;; A tail that becomes a row is the one row they make; one that
      ;; becomes any other type stays a tail.
      (define (test-rows)
        (let ((io (global "io"))
              (log (global "log")))
          (expect (substituted (list (Pair a (Row (closed (list io)))))
                               (Row (Effects (list log) (Some (Var a)))))
                  (Row (closed (list io log))))
          (expect (substituted (list (Pair a (Row (Effects (list io) (Some (Var b))))))
                               (Row (Effects (list log) (Some (Var a)))))
                  (Row (Effects (list io log) (Some (Var b)))))
          (expect (substituted (list (Pair a i64)) (Row (Effects (list log) (Some (Var a)))))
                  (Row (Effects (list log) (Some i64))))))

      (define (test-requirements)
        (expect (substituted-requirement (list (Pair a i64))
                                         (ClassRequirement (ClassGlobal (global "Show"))
                                                           (list (Var a))))
                (ClassRequirement (ClassGlobal (global "Show")) (list i64)))
        (expect (substituted-requirement (list (Pair a i64))
                                         (CallableRequirement (FnMutContract)
                                                              (Var a)
                                                              (Arrow (list (Var a))
                                                                     f64
                                                                     (closed (list)))))
                (CallableRequirement (FnMutContract) i64 (Arrow (list i64) f64 (closed (list))))))))
   (else)))
