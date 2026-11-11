;; The rules callable types obey in a scheme, as the old compiler's
;; `callable-scheme` and `operational-scheme` (src/snail/shell/compiler/
;; expand.sld) apply them. When a scheme's type is a callable or code, an
;; `impl` callable is a contract of an argument or of the definition, so
;; its result may not be one, and each parameter that is one is a type the
;; caller chooses, a variable of the scheme with a callable requirement
;; of the parameter's contract; then no `impl` may remain within the
;; result or a parameter, where storage would need it. Executable code, a
;; method's, an operation's, a primitive's or an extern's, has an arrow
;; for its type, whatever its callable was written as.
(define-library (snail compiler declare callables)
  (export
   callable-scheme
   operational-scheme
   operational-type)
  (import
   (snail core base)
   (only (snail compiler expand language) Impl Dyn FnContract)
   (snail compiler declare language))
  (begin

    ;; ---- Callable schemes ----

    ;; `scheme` with each `impl` parameter of its callable lifted, or the
    ;; old compiler's refusal of it.
    (: callable-scheme (impl (Fn Scheme -> (Result Scheme String))))
    (define (callable-scheme scheme)
      (match (callable-arrow (::type scheme))
        ((None) (Ok scheme))
        ((Some arrow)
         (if (impl? (::result arrow))
             (Err returned-callable)
             (let ((lifted (lifted-parameters scheme arrow)))
               (if (arrow-impl? (::second lifted))
                   (Err stored-callable)
                   (Ok (::first lifted))))))))

    (: returned-callable String)
    (define returned-callable
      "a returned callable needs explicit dyn storage; impl is an argument or definition contract")

    (: stored-callable String)
    (define stored-callable
      "stored and returned callable types require explicit dyn; impl is a definition or argument contract")

    ;; The scheme with a variable and a callable requirement for each
    ;; `impl` parameter, in order, and each such parameter its variable;
    ;; and its arrow. A variable is numbered by its position among the
    ;; scheme's variables, as the old compiler names it
    ;; `$callable-argument.N`.
    (: lifted-parameters (impl (Fn Scheme Arrow -> (Pair Scheme Arrow))))
    (define (lifted-parameters scheme arrow)
      (let* ((lifted (fold-left (lambda (lifted parameter)
                                  (lifted-parameter (::first lifted) (::second lifted) parameter))
                                (Pair scheme (Nil))
                                (::parameters arrow)))
             (found (::first lifted))
             (arrow (Arrow (reverse (::second lifted)) (::result arrow) (::effects arrow))))
        (Pair (Scheme (::variables found)
                      (::requirements found)
                      (::copied found)
                      (with-arrow (::type scheme) arrow))
              arrow)))

    (: lifted-parameter (impl (Fn Scheme (List Type) Type -> (Pair Scheme (List Type)))))
    (define (lifted-parameter scheme parameters parameter)
      (match parameter
        ((Callable (Impl) contract arrow)
         (let ((variable (CallableArgument (length (::variables scheme)))))
           (Pair (Scheme (append (::variables scheme) (list variable))
                         (append (::requirements scheme)
                                 (list (CallableRequirement contract (Var variable) arrow)))
                         (::copied scheme)
                         (::type scheme))
                 (Cons (Var variable) parameters))))
        (_ (Pair scheme (Cons parameter parameters)))))

    ;; A callable's or code's arrow, which a scheme whose type it is
    ;; quantifies over.
    (: callable-arrow (impl (Fn Type -> (Option Arrow))))
    (define (callable-arrow type)
      (match type
        ((Callable _ _ arrow) (Some arrow))
        ((Code arrow) (Some arrow))
        (_ (None))))

    (: with-arrow (impl (Fn Type Arrow -> Type)))
    (define (with-arrow type arrow)
      (match type
        ((Callable former contract _) (Callable former contract arrow))
        ((Code _) (Code arrow))
        (_ type)))

    (: impl? (impl (Fn Type -> Bool)))
    (define (impl? type)
      (match type
        ((Callable (Impl) _ _) #t)
        (_ #f)))

    ;; Whether an `impl` callable is the type or within it where the old
    ;; compiler looks (`check-stored-type`): a Con's arguments, and the
    ;; parameters and results of callables and code, but not a row.
    (: impl-within? (impl (Fn Type -> Bool)))
    (define (impl-within? type)
      (match type
        ((Callable (Impl) _ _) #t)
        ((Callable (Dyn) _ arrow) (arrow-impl? arrow))
        ((Code arrow) (arrow-impl? arrow))
        ((Con _ arguments) (any? impl-within? arguments))
        (_ #f)))

    (: arrow-impl? (impl (Fn Arrow -> Bool)))
    (define (arrow-impl? arrow)
      (or (impl-within? (::result arrow)) (any? impl-within? (::parameters arrow))))

    ;; ---- Executable code ----

    ;; A callable or code is its arrow, which is `(dyn (Fn ...))`, as the
    ;; old compiler's `fn-arrow` makes it a bare function type; any other
    ;; type is itself.
    (: operational-type (impl (Fn Type -> Type)))
    (define (operational-type type)
      (match (callable-arrow type)
        ((Some arrow) (Callable (Dyn) (FnContract) arrow))
        ((None) type)))

    (: operational-scheme (impl (Fn Scheme -> Scheme)))
    (define (operational-scheme scheme)
      (Scheme (::variables scheme)
              (::requirements scheme)
              (::copied scheme)
              (operational-type (::type scheme))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-callables)
    (import
     (only (snail compiler expand language) Global ClassGlobal FnMutContract FnOnceContract)
     (snail stage0 testing))
    (begin
      (define (test-callables)
        (test-lifting)
        (test-refusals)
        (test-operational))

      (define i64 (Con (Global (list "snail" "core" "forms") "I64" 0) (list)))
      (define vector (Global (list "snail" "core" "forms") "Vector" 0))
      (define pure (Effects (list) (None)))

      (define (arrow parameters result)
        (Arrow parameters result pure))

      (define (impl-of contract parameters result)
        (Callable (Impl) contract (arrow parameters result)))

      (define (scheme variables requirements type)
        (Scheme variables requirements (list) type))

      (define a (Written "a"))
      (define show (Global (list "main") "Show" 0))

      ;; Read off `callable-parameter`: `$callable-argument.N` is named by
      ;; the count of the scheme's variables when it is lifted, those
      ;; written, then outputs, then the arguments lifted before; its
      ;; requirement is appended after the written ones.
      (define (test-lifting)
        (let* ((written
                (ClassRequirement (ClassGlobal show) (list (Var a) (Var (Associated 0 "Out")))))
               (variables (list a (Associated 0 "Out")))
               (callback (impl-of (FnContract) (list i64) i64))
               (later (impl-of (FnOnceContract) (list) (Var a))))
          (expect (callable-scheme (scheme variables
                                           (list written)
                                           (Callable (Dyn) (FnContract)
                                                     (arrow (list callback (Var a) later) i64))))
                  (Ok
                   (scheme (list a (Associated 0 "Out") (CallableArgument 2) (CallableArgument 3))
                           (list written
                                 (CallableRequirement (FnContract)
                                                      (Var (CallableArgument 2))
                                                      (arrow (list i64) i64))
                                 (CallableRequirement (FnOnceContract)
                                                      (Var (CallableArgument 3))
                                                      (arrow (list) (Var a))))
                           (Callable (Dyn) (FnContract)
                                     (arrow (list (Var (CallableArgument 2))
                                                  (Var a)
                                                  (Var (CallableArgument 3)))
                                            i64)))))
          ;; The definition's own `impl`, and code, keep their former.
          (expect
           (callable-scheme (scheme (list) (list) (impl-of (FnMutContract) (list callback) i64)))
           (Ok (scheme (list (CallableArgument 0))
                       (list (CallableRequirement (FnContract)
                                                  (Var (CallableArgument 0))
                                                  (arrow (list i64) i64)))
                       (impl-of (FnMutContract) (list (Var (CallableArgument 0))) i64))))
          (expect (callable-scheme (scheme (list) (list) (Code (arrow (list callback) i64))))
                  (Ok (scheme (list (CallableArgument 0))
                              (list (CallableRequirement (FnContract)
                                                         (Var (CallableArgument 0))
                                                         (arrow (list i64) i64)))
                              (Code (arrow (list (Var (CallableArgument 0))) i64)))))
          ;; A scheme of another type, and an `impl` inside a lifted
          ;; parameter's own arrow, are left as they are.
          (expect (callable-scheme (scheme (list a) (list) (Con vector (list callback))))
                  (Ok (scheme (list a) (list) (Con vector (list callback)))))
          (let ((nested (impl-of (FnContract) (list callback) i64)))
            (expect (callable-scheme (scheme (list) (list) (Code (arrow (list nested) i64))))
                    (Ok (scheme (list (CallableArgument 0))
                                (list (CallableRequirement (FnContract)
                                                           (Var (CallableArgument 0))
                                                           (arrow (list callback) i64)))
                                (Code (arrow (list (Var (CallableArgument 0))) i64))))))))

      (define returned
        "a returned callable needs explicit dyn storage; impl is an argument or definition contract")

      (define stored
        "stored and returned callable types require explicit dyn; impl is a definition or argument contract")

      ;; The result first; then `impl` within the result or a parameter,
      ;; but not within a row.
      (define (test-refusals)
        (let ((callback (impl-of (FnContract) (list) i64)))
          (expect (callable-scheme (scheme (list) (list) (Code (arrow (list callback) callback))))
                  (Err returned))
          (expect (callable-scheme
                   (scheme (list) (list) (Code (arrow (list) (Con vector (list callback))))))
                  (Err stored))
          (expect (callable-scheme (scheme (list)
                                           (list)
                                           (Code (arrow (list (Callable (Dyn) (FnMutContract)
                                                                        (arrow (list callback)
                                                                               i64)))
                                                        i64))))
                  (Err stored))
          (expect (callable-scheme (scheme (list)
                                           (list)
                                           (Code
                                            (arrow (list (Row (Effects (list) (Some callback))))
                                                   i64))))
                  (Ok (scheme (list)
                              (list)
                              (Code (arrow (list (Row (Effects (list) (Some callback)))) i64)))))))

      ;; Read off `fn-arrow`: a callable or code is its bare arrow.
      (define (test-operational)
        (let ((pair (arrow (list i64) i64)))
          (expect (operational-type (Callable (Impl) (FnOnceContract) pair))
                  (Callable (Dyn) (FnContract) pair))
          (expect (operational-type (Callable (Dyn) (FnMutContract) pair))
                  (Callable (Dyn) (FnContract) pair))
          (expect (operational-type (Code pair)) (Callable (Dyn) (FnContract) pair))
          (expect (operational-type i64) i64)
          (expect (operational-scheme (scheme (list a) (list) (Code pair)))
                  (scheme (list a) (list) (Callable (Dyn) (FnContract) pair)))))))
   (else)))
