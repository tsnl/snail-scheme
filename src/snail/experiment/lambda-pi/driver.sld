;; Ordinary orchestration for LambdaPi. Every recursive edge is visible here:
;; checking asks for evaluation when a dependent premise needs a value, and
;; quotation enters closures to normalize beneath binders. There is no cache.
(define-library (snail experiment lambda-pi driver)
  (export Checked infer check assume define-global term-normal type-normal with-results)
  (import
   (except (snail core base) ann)
   (snail experiment lambda-pi language)
   (snail experiment lambda-pi rules)
   (snail experiment lambda-pi normal))
  (begin

    ;; ---- Checked boundary ----

    ;; The constructor is private. Retaining the exact immutable context
    ;; means later declarations cannot change this checked result's meaning.
    (enum Checked
      (Accepted ((context Context)
                 (term Check)
                 (type Value))))

    ;; Sequencing sugar only: this expands to ordinary Result matches. It
    ;; adds no callbacks, mutable state, scheduler, cache, or implicit inputs.
    (define-syntax with-results
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name computation) next ...) body ...)
         (match computation
           ((Err problem) (Err problem))
           ((Ok name) (with-results (next ...) body ...))))))

    (: infer (-> Context Infer (Result Checked Error)))
    (define (infer context term)
      (with-results ((type (infer-type context term)))
                    (Ok (Accepted context (Inf term) type))))

    (: check (-> Context Check Check (Result Checked Error)))
    (define (check context term expected)
      (with-results ((verified (check-term context expected (Universe))))
                    (let ((type (evaluate-check (::environment context) expected)))
                      (with-results ((verified (check-term context term type)))
                                    (Ok (Accepted context term type))))))

    (: assume (-> Context String Check (Result Context Error)))
    (define (assume context name type)
      (with-results ((unused (new-name context name))
                     (verified (check-term context type (Universe))))
                    (Ok (bind-global context name (evaluate-check (::environment context) type)
                                     (Stuck (FreeValue (Identifier name)))))))

    (: define-global (-> Context String Infer (Result Context Error)))
    (define (define-global context name term)
      (with-results ((unused (new-name context name))
                     (type (infer-type context term)))
                    (Ok
                     (bind-global context
                                  name
                                  type
                                  (evaluate-infer (::environment context) term)))))

    (: term-normal (-> Checked Normal))
    (define (term-normal checked)
      (match checked
        ((Accepted context term _)
         (quote-value (length (::local-types context))
                      (evaluate-check (::environment context) term)))))

    (: type-normal (-> Checked Normal))
    (define (type-normal checked)
      (match checked
        ((Accepted context _ type) (quote-value (length (::local-types context)) type))))

    ;; ---- Synthesis ----

    (: infer-type (-> Context Infer (Result Value Error)))
    (define (infer-type context term)
      (match term
        ((IStar) (Ok (Universe)))
        ((INat) (Ok (Universe)))
        ((IFree node) (free-type context node))
        ((IBound node) (bound-type context node))
        ((IAnn node) (infer-annotation context node))
        ((IPi node) (infer-product context node))
        ((IApp node) (infer-application context node))
        ((INatElim node) (infer-natural-elimination context node))
        ((IVec node) (infer-vector-type context node))
        ((IVecElim node) (infer-vector-elimination context node))))

    (: infer-annotation (-> Context (:: Check Check) (Result Value Error)))
    (define (infer-annotation context node)
      (with-results ((verified (check-term context (::type node) (Universe))))
                    (let ((type (evaluate-check (::environment context) (::type node))))
                      (with-results ((verified (check-term context (::term node) type)))
                                    (Ok type)))))

    (: infer-product (-> Context (Product Check Check) (Result Value Error)))
    (define (infer-product context node)
      (with-results ((verified (check-term context (::domain node) (Universe))))
                    (let ((domain (evaluate-check (::environment context) (::domain node))))
                      (with-results ((verified (check-term (under-binder context domain)
                                                           (::codomain node) (Universe))))
                                    (Ok (Universe))))))

    ;; ANCHOR: application
    (: infer-application (-> Context (Application Infer Check) (Result Value Error)))
    (define (infer-application context node)
      (with-results ((function-type (infer-type context (::function node)))
                     (product (require-product function-type))
                     (verified (check-term context (::argument node) (::domain product))))
                    (let ((argument (evaluate-check (::environment context) (::argument node))))
                      (Ok (evaluate-scope (enter (::codomain product) argument))))))
    ;; ANCHOR_END: application

    ;; ---- Checking and conversion ----

    (: check-term (-> Context Check Value (Result Unit Error)))
    (define (check-term context term expected)
      (match term
        ((Inf inferable)
         (with-results ((actual (infer-type context inferable)))
                       (convert context expected actual)))
        ((Lam node) (check-lambda context node expected))
        ((Zero) (require-natural expected))
        ((Succ (Successor previous))
         (with-results ((verified (require-natural expected)))
                       (check-term context previous (Natural))))
        ((VNil element) (check-empty-vector context element expected))
        ((VCons node) (check-vector-cons context node expected))))

    ;; ANCHOR: lambda
    (: check-lambda (-> Context (Binder Check) Value (Result Unit Error)))
    (define (check-lambda context node expected)
      (with-results ((product (require-product expected)))
                    (let* ((variable (fresh (length (::local-types context))))
                           (body-type (evaluate-scope (enter (::codomain product) variable))))
                      (check-term (under-binder context (::domain product))
                                  (::body node)
                                  body-type))))
    ;; ANCHOR_END: lambda

    (: convert (-> Context Value Value (Result Unit Error)))
    (define (convert context expected actual)
      (let* ((depth (length (::local-types context)))
             (expected (quote-value depth expected))
             (actual (quote-value depth actual)))
        (if (normal=? expected actual) (Ok (unit)) (Err (ConversionMismatch expected actual)))))

    ;; ---- Natural and vector premises ----

    (: infer-natural-elimination (-> Context (NatElimination Check Check) (Result Value Error)))
    (define (infer-natural-elimination context node)
      (with-results ((verified (check-term context (::motive node) nat-motive-type)))
                    (let ((motive (evaluate-check (::environment context) (::motive node))))
                      (with-results
                       ((verified
                         (check-term context (::base node) (apply-value motive (ZeroValue))))
                        (verified (check-term context (::step node) (nat-step-type motive)))
                        (verified (check-term context (::scrutinee node) (Natural))))
                       (Ok (apply-value motive
                                        (evaluate-check (::environment context)
                                                        (::scrutinee node))))))))

    (: infer-vector-type (-> Context (VectorType Check) (Result Value Error)))
    (define (infer-vector-type context node)
      (with-results ((verified (check-term context (::element node) (Universe)))
                     (verified (check-term context (::size node) (Natural))))
                    (Ok (Universe))))

    (: check-empty-vector (-> Context Check Value (Result Unit Error)))
    (define (check-empty-vector context element expected)
      (with-results ((verified (check-term context element (Universe))))
                    (convert context expected
                             (VectorValue
                              (VectorType (evaluate-check (::environment context) element)
                                          (ZeroValue))))))

    (: check-vector-cons (-> Context (VectorCons Check) Value (Result Unit Error)))
    (define (check-vector-cons context node expected)
      (with-results ((verified (check-term context (::element node) (Universe)))
                     (verified (check-term context (::size node) (Natural))))
                    (let ((element (evaluate-check (::environment context) (::element node)))
                          (size (evaluate-check (::environment context) (::size node))))
                      (with-results ((verified (check-term context (::head node) element))
                                     (verified (check-term context
                                                           (::tail node)
                                                           (VectorValue
                                                            (VectorType element size)))))
                                    (convert context expected
                                             (VectorValue (VectorType element
                                                                      (SuccessorValue
                                                                       (Successor size)))))))))

    (: infer-vector-elimination (-> Context (VectorElimination Check Check) (Result Value Error)))
    (define (infer-vector-elimination context node)
      (with-results ((verified (check-term context (::element node) (Universe))))
                    (let ((element (evaluate-check (::environment context) (::element node))))
                      (with-results
                       ((verified
                         (check-term context (::motive node) (vector-motive-type element))))
                       (check-vector-branches context node element
                                              (evaluate-check (::environment context)
                                                              (::motive node)))))))

    (: check-vector-branches
       (-> Context (VectorElimination Check Check) Value Value (Result Value Error)))
    (define (check-vector-branches context node element motive)
      (with-results ((verified (check-term context (::base node)
                                           (apply-many motive
                                                       (list (ZeroValue) (EmptyValue element)))))
                     (verified (check-term context (::step node) (vector-step-type element motive)))
                     (verified (check-term context (::size node) (Natural))))
                    (let ((size (evaluate-check (::environment context) (::size node))))
                      (with-results ((verified (check-term context
                                                           (::scrutinee node)
                                                           (VectorValue
                                                            (VectorType element size)))))
                                    (Ok (apply-many motive
                                                    (list size
                                                          (evaluate-check (::environment context)
                                                                          (::scrutinee node)))))))))

    ;; ---- Evaluation ----

    ;; Called only for premises already checked or internal expectation
    ;; recipes built by rules.sld. Public normalization requires Checked.
    (: evaluate-infer (-> Environment Infer Value))
    (define (evaluate-infer environment term)
      (match term
        ((IStar) (Universe))
        ((INat) (Natural))
        ((IAnn node) (evaluate-check environment (::term node)))
        ((IBound (Index index))
         (known (indexed-value (::locals environment) index)))
        ((IFree (Identifier name))
         (known (named-value (::globals environment) name)))
        ((IPi node)
         (ProductValue (Product (evaluate-check environment (::domain node))
                                (Scope (::codomain node) environment))))
        ((IApp node)
         (apply-value (evaluate-infer environment (::function node))
                      (evaluate-check environment (::argument node))))
        ((INatElim node) (evaluate-natural environment node))
        ((IVec node)
         (VectorValue (VectorType (evaluate-check environment (::element node))
                                  (evaluate-check environment (::size node)))))
        ((IVecElim node) (evaluate-vector environment node))))

    (: evaluate-check (-> Environment Check Value))
    (define (evaluate-check environment term)
      (match term
        ((Inf term) (evaluate-infer environment term))
        ((Lam (Binder body)) (Function (Scope body environment)))
        ((Zero) (ZeroValue))
        ((Succ (Successor previous))
         (SuccessorValue (Successor (evaluate-check environment previous))))
        ((VNil element) (EmptyValue (evaluate-check environment element)))
        ((VCons node)
         (ConsValue (VectorCons (evaluate-check environment (::element node))
                                (evaluate-check environment (::size node))
                                (evaluate-check environment (::head node))
                                (evaluate-check environment (::tail node)))))))

    (: known (-> (Option Value) Value))
    (define (known value)
      (match value
        ((Some value) value)
        ((None) (panic "internal LambdaPi invariant: checked variable has a binding"))))

    (: evaluate-scope (-> Scope Value))
    (define (evaluate-scope scope) (evaluate-check (::environment scope) (::body scope)))

    ;; ANCHOR: evaluation-call
    (: apply-value (-> Value Value Value))
    (define (apply-value function argument)
      (match (application-step function argument)
        ((AppliedValue value) value)
        ((EnterScope scope) (evaluate-scope scope))))
    ;; ANCHOR_END: evaluation-call

    (: apply-many (-> Value (List Value) Value))
    (define (apply-many function arguments) (fold-left apply-value function arguments))

    (: evaluate-natural (-> Environment (NatElimination Check Check) Value))
    (define (evaluate-natural environment node)
      (fold-natural (NatElimination (evaluate-check environment (::motive node))
                                    (evaluate-check environment (::base node))
                                    (evaluate-check environment (::step node))
                                    (evaluate-check environment (::scrutinee node)))))

    (: fold-natural (-> (NatElimination Value Value) Value))
    (define (fold-natural node)
      (match (reduce-natural node)
        ((Reduced value) value)
        ((Recur previous)
         (let ((induction (fold-natural (NatElimination (::motive node) (::base node)
                                                        (::step node) previous))))
           (apply-many (::step node) (list previous induction))))))

    (: evaluate-vector (-> Environment (VectorElimination Check Check) Value))
    (define (evaluate-vector environment node)
      (fold-vector (VectorElimination (evaluate-check environment (::element node))
                                      (evaluate-check environment (::motive node))
                                      (evaluate-check environment (::base node))
                                      (evaluate-check environment (::step node))
                                      (evaluate-check environment (::size node))
                                      (evaluate-check environment (::scrutinee node)))))

    (: fold-vector (-> (VectorElimination Value Value) Value))
    (define (fold-vector node)
      (match (reduce-vector node)
        ((Reduced value) value)
        ((Recur fields)
         (let ((induction (fold-vector (VectorElimination (::element node) (::motive node)
                                                          (::base node) (::step node)
                                                          (::size fields) (::tail fields)))))
           (apply-many (::step node)
                       (list (::size fields) (::head fields) (::tail fields) induction))))))

    ;; ---- Quotation ----

    ;; ANCHOR: quotation
    (: quote-scope (-> I64 Scope Normal))
    (define (quote-scope depth scope)
      (quote-value (+ depth 1) (evaluate-scope (enter scope (fresh depth)))))
    ;; ANCHOR_END: quotation

    (: quote-value (-> I64 Value Normal))
    (define (quote-value depth value)
      (match value
        ((Universe) (NormalStar))
        ((Natural) (NormalNat))
        ((ZeroValue) (NormalZero))
        ((Function scope) (NormalLam (Binder (quote-scope depth scope))))
        ((ProductValue node)
         (NormalPi (Product (quote-value depth (::domain node))
                            (quote-scope depth (::codomain node)))))
        ((Stuck neutral) (NormalNeutral (quote-neutral depth neutral)))
        ((SuccessorValue (Successor previous))
         (NormalSucc (Successor (quote-value depth previous))))
        ((VectorValue node)
         (NormalVec
          (VectorType (quote-value depth (::element node)) (quote-value depth (::size node)))))
        ((EmptyValue element) (NormalNil (quote-value depth element)))
        ((ConsValue node)
         (NormalCons
          (VectorCons (quote-value depth (::element node)) (quote-value depth (::size node))
                      (quote-value depth (::head node))
                      (quote-value depth (::tail node)))))))

    (: quote-neutral (-> I64 Neutral NeutralNormal))
    (define (quote-neutral depth neutral)
      (match neutral
        ((FreeValue node) (NormalFree node))
        ((LocalValue (Index level))
         (if (and (>= level 0) (< level depth))
             (NormalBound (Index (- (- depth level) 1)))
             (panic "internal LambdaPi invariant: quoted level belongs to scope")))
        ((ApplyValue node)
         (NormalApp (Application (quote-neutral depth (::function node))
                                 (quote-value depth (::argument node)))))
        ((NatElimValue node)
         (NormalNatElim (NatElimination (quote-value depth (::motive node))
                                        (quote-value depth (::base node))
                                        (quote-value depth (::step node))
                                        (quote-neutral depth (::scrutinee node)))))
        ((VecElimValue node)
         (NormalVecElim (VectorElimination (quote-value depth (::element node))
                                           (quote-value depth (::motive node))
                                           (quote-value depth (::base node))
                                           (quote-value depth (::step node))
                                           (quote-value depth (::size node))
                                           (quote-neutral depth (::scrutinee node)))))))))
