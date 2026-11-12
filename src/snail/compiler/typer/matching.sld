;; One-way matching of an instance's head against types, as the old
;; compiler's `match-types` (src/snail/shell/compiler/core.sld) matches
;; them: only the instance's own variables bind, the types they are matched
;; with are never looked into for variables, and a match is the bindings
;; it makes, which `substituted` of (snail compiler types substitution)
;; applies. `dispatch` matches a source instance to a domain pair with it,
;; and `solve` will choose an instance with it.
;;
;; - A variable of the instance binds to the type it meets the first time,
;;   and is then the same type wherever it is written; any other variable
;;   matches only itself.
;; - A data type or a builtin matches the same type, its arguments matched
;;   in turn.
;; - A callable matches a callable of the same former and contract, and
;;   code matches code: their parameters and results, the result first,
;;   but never their effects.
;; - A row matches nothing, not even itself.
(define-library (snail compiler typer matching)
  (export
   matched-types)
  (import
   (snail core base)
   (only (snail compiler types type) Type Con Callable Code Row Var Arrow TypeVariable)
   (only (snail compiler types equality)
         same-type?
         same-variable?
         variable-among?
         same-former?
         same-contract?)
   (only (snail compiler names globals) same-global?))
  (begin

    ;; ---- Matching ----

    ;; The bindings that make `patterns`, written over `variables`, the
    ;; `types`, one by one; none when they are not as many or one does not
    ;; match. Each binding made is put before those already made.
    (: matched-types
       (impl (Fn (List TypeVariable)
                 (List Type)
                 (List Type)
                 ->
                 (Option (List (Pair TypeVariable Type))))))
    (define (matched-types variables patterns types)
      (matched-in variables patterns types (Some (Nil))))

    (: matched-in
       (impl (Fn (List TypeVariable)
                 (List Type)
                 (List Type)
                 (Option (List (Pair TypeVariable Type)))
                 ->
                 (Option (List (Pair TypeVariable Type))))))
    (define (matched-in variables patterns types found)
      (if (= (length patterns) (length types))
          (fold-left (lambda (found pair)
                       (match found
                         ((Some bindings)
                          (matched-type variables (::first pair) (::second pair) bindings))
                         ((None) (None))))
                     found
                     (zip patterns types))
          (None)))

    (: matched-type
       (impl (Fn (List TypeVariable)
                 Type
                 Type
                 (List (Pair TypeVariable Type))
                 ->
                 (Option (List (Pair TypeVariable Type))))))
    (define (matched-type variables pattern type bindings)
      (match pattern
        ((Var variable)
         (if (variable-among? variable variables)
             (matched-variable variable type bindings)
             (if (same-type? pattern type) (Some bindings) (None))))
        ((Con global arguments)
         (match type
           ((Con other others)
            (if (same-global? global other)
                (matched-in variables arguments others (Some bindings))
                (None)))
           (_ (None))))
        ((Callable former contract arrow)
         (match type
           ((Callable other-former other-contract other-arrow)
            (if (and (same-former? former other-former) (same-contract? contract other-contract))
                (matched-arrow variables arrow other-arrow bindings)
                (None)))
           (_ (None))))
        ((Code arrow)
         (match type
           ((Code other-arrow) (matched-arrow variables arrow other-arrow bindings))
           (_ (None))))
        ((Row _) (None))))

    ;; A variable already bound matches only the type it is bound to.
    (: matched-variable
       (impl (Fn TypeVariable
                 Type
                 (List (Pair TypeVariable Type))
                 ->
                 (Option (List (Pair TypeVariable Type))))))
    (define (matched-variable variable type bindings)
      (match (find (lambda (binding) (same-variable? (::first binding) variable)) bindings)
        ((None) (Some (Cons (Pair variable type) bindings)))
        ((Some bound) (if (same-type? (::second bound) type) (Some bindings) (None)))))

    (: matched-arrow
       (impl (Fn (List TypeVariable)
                 Arrow
                 Arrow
                 (List (Pair TypeVariable Type))
                 ->
                 (Option (List (Pair TypeVariable Type))))))
    (define (matched-arrow variables arrow other bindings)
      (matched-in variables
                  (Cons (::result arrow) (::parameters arrow))
                  (Cons (::result other) (::parameters other))
                  (Some bindings)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-matching)
    (import
     (only (snail compiler types type) Effects Written Impl Dyn FnContract FnMutContract)
     (only (snail compiler names globals) Global)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-matching)
        (test-variables)
        (test-data)
        (test-callables))

      (define (builtin name)
        (Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define list-global (Global (list "snail" "core" "base") "List" 0))

      (define (list-of type)
        (Con list-global (list type)))

      (define a (Written "a"))
      (define b (Written "b"))

      (define (closed labels)
        (Effects labels (None)))

      (define io (Global (list "main") "io" 0))

      ;; Read off `match-types` (build/dispatch-runs/old-matching.scm prints
      ;; the old answers): a variable binds once, before those bound
      ;; already, and a repeated one must meet the same type; a variable not
      ;; the instance's matches only itself; the counts must agree.
      (define (test-variables)
        (expect (matched-types (list a b) (list (Var a) (Var b)) (list i64 f64))
                (Some (list (Pair b f64) (Pair a i64))))
        (expect (matched-types (list a) (list (Var a) (Var a)) (list i64 i64))
                (Some (list (Pair a i64))))
        (expect (matched-types (list a) (list (Var a) (Var a)) (list i64 f64)) (None))
        (expect (matched-types (list) (list (Var a)) (list (Var a))) (Some (list)))
        (expect (matched-types (list) (list (Var a)) (list i64)) (None))
        (expect (matched-types (list a) (list (Var a)) (list i64 f64)) (None))
        (expect (matched-types (list a) (list (Var a)) (list (Row (closed (list io)))))
                (Some (list (Pair a (Row (closed (list io))))))))

      ;; A type's arguments are matched in turn; another type, or a
      ;; variable met where a type is written, does not match.
      (define (test-data)
        (expect (matched-types (list a) (list (list-of (Var a))) (list (list-of i64)))
                (Some (list (Pair a i64))))
        (expect (matched-types (list a) (list (list-of (Var a))) (list i64)) (None))
        (expect (matched-types (list) (list i64) (list f64)) (None))
        (expect (matched-types (list) (list i64) (list (Var a))) (None))
        (expect
         (matched-types (list) (list (Row (closed (list io)))) (list (Row (closed (list io)))))
         (None)))

      ;; A callable of one former and contract, or code, matches its kind
      ;; whatever its effects, the result before the parameters.
      (define (test-callables)
        (let ((function (lambda (former contract parameter result labels)
                          (Callable former
                                    contract
                                    (Arrow (list parameter) result (closed labels))))))
          (expect (matched-types (list a b)
                                 (list (function (Dyn) (FnContract) (Var a) (Var b) (list)))
                                 (list (function (Dyn) (FnContract) i64 f64 (list io))))
                  (Some (list (Pair a i64) (Pair b f64))))
          (expect (matched-types (list a)
                                 (list (function (Dyn) (FnContract) (Var a) i64 (list)))
                                 (list (function (Dyn) (FnMutContract) i64 i64 (list))))
                  (None))
          (expect (matched-types (list a)
                                 (list (function (Impl) (FnContract) (Var a) i64 (list)))
                                 (list (function (Dyn) (FnContract) i64 i64 (list))))
                  (None))
          (expect (matched-types (list a)
                                 (list (Code (Arrow (list (Var a)) i64 (closed (list)))))
                                 (list (Code (Arrow (list f64) i64 (closed (list io))))))
                  (Some (list (Pair a f64))))
          (expect (matched-types (list a)
                                 (list (Code (Arrow (list (Var a)) i64 (closed (list)))))
                                 (list (function (Dyn) (FnContract) f64 i64 (list))))
                  (None))
          (expect (matched-types (list a)
                                 (list (Code (Arrow (list (Var a)) i64 (closed (list)))))
                                 (list (Code (Arrow (list f64 f64) i64 (closed (list))))))
                  (None))))))
   (else)))
