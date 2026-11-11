;; Local decisions on supplied facts. No rule checks a child, evaluates a
;; closure, quotes a value, or calls the driver.
(define-library (snail experiment lambda-pi rules)
  (export named-value indexed-value free-type bound-type fresh under-binder
          new-name bind-global enter require-product require-natural
          ApplicationStep EnterScope AppliedValue application-step
          Reduction Reduced Recur reduce-natural reduce-vector
          constant-product nat-motive-type nat-step-type vector-motive-type vector-step-type)
  (import
   (except (snail core base) ann)
   (snail experiment lambda-pi language))
  (begin

    ;; ---- Explicit scope inputs ----

    (: named-value (-> (List (Pair String Value)) String (Option Value)))
    (define (named-value entries name)
      (match entries
        ((Nil) (None))
        ((Cons (Pair key value) rest)
         (if (string=? key name) (Some value) (named-value rest name)))))

    (: indexed-value (-> (List Value) I64 (Option Value)))
    (define (indexed-value entries index)
      (match entries
        ((Nil) (None))
        ((Cons value rest)
         (cond ((< index 0) (None))
               ((= index 0) (Some value))
               (else (indexed-value rest (- index 1)))))))

    (: free-type (-> Context Identifier (Result Value Error)))
    (define (free-type context node)
      (match (named-value (::global-types context) (::name node))
        ((Some type) (Ok type))
        ((None) (Err (UnknownName (::name node))))))

    (: bound-type (-> Context Index (Result Value Error)))
    (define (bound-type context node)
      (match (indexed-value (::local-types context) (::index node))
        ((Some type) (Ok type))
        ((None) (Err (InvalidIndex (::index node))))))

    (: fresh (-> I64 Value))
    (define (fresh depth) (Stuck (LocalValue (Index depth))))

    (: under-binder (-> Context Value Context))
    (define (under-binder context domain)
      (let ((environment (::environment context)))
        (Context (::global-types context) (Cons domain (::local-types context))
                 (Environment (::globals environment)
                              (Cons (fresh (length (::local-types context)))
                                    (::locals environment))))))

    (: new-name (-> Context String (Result Unit Error)))
    (define (new-name context name)
      (match (named-value (::global-types context) name)
        ((Some _) (Err (DuplicateName name)))
        ((None) (Ok (unit)))))

    (: bind-global (-> Context String Value Value Context))
    (define (bind-global context name type value)
      (let ((environment (::environment context)))
        (Context (Cons (Pair name type) (::global-types context)) (::local-types context)
                 (Environment (Cons (Pair name value) (::globals environment))
                              (::locals environment)))))

    (: enter (-> Scope Value Scope))
    (define (enter scope argument)
      (let ((environment (::environment scope)))
        (Scope (::body scope)
               (Environment (::globals environment) (Cons argument (::locals environment))))))

    ;; ---- Checking premises ----

    ;; ANCHOR: product-rule
    (: require-product (-> Value (Result (Product Value Scope) Error)))
    (define (require-product type)
      (match type
        ((ProductValue node) (Ok node))
        (_ (Err (ExpectedFunction)))))
    ;; ANCHOR_END: product-rule

    (: require-natural (-> Value (Result Unit Error)))
    (define (require-natural type)
      (match type ((Natural) (Ok (unit))) (_ (Err (ExpectedNatural)))))

    ;; ---- Evaluation decisions ----

    (enum ApplicationStep
      (EnterScope ((scope Scope)))
      (AppliedValue ((value Value))))

    ;; A successful check establishes that these are the only two cases.
    ;; The scope returned here is data; its body has not been evaluated.
    (: application-step (-> Value Value ApplicationStep))
    (define (application-step function argument)
      (match function
        ((Function scope) (EnterScope (enter scope argument)))
        ((Stuck neutral) (AppliedValue (Stuck (ApplyValue (Application neutral argument)))))
        (_ (panic "internal LambdaPi invariant: a checked application has a function"))))

    (enum (Reduction Next)
      (Reduced ((value Value)))
      (Recur ((next Next))))

    (: reduce-natural (-> (NatElimination Value Value) (Reduction Value)))
    (define (reduce-natural node)
      (match (::scrutinee node)
        ((ZeroValue) (Reduced (::base node)))
        ((SuccessorValue (Successor previous)) (Recur previous))
        ((Stuck neutral)
         (Reduced (Stuck (NatElimValue (NatElimination (::motive node) (::base node)
                                                       (::step node) neutral)))))
        (_ (panic "internal LambdaPi invariant: natural elimination has a natural"))))

    (: reduce-vector (-> (VectorElimination Value Value) (Reduction (VectorCons Value))))
    (define (reduce-vector node)
      (match (::scrutinee node)
        ((EmptyValue _) (Reduced (::base node)))
        ((ConsValue fields) (Recur fields))
        ((Stuck neutral)
         (Reduced (Stuck (VecElimValue (VectorElimination (::element node) (::motive node)
                                                          (::base node) (::step node)
                                                          (::size node) neutral)))))
        (_ (panic "internal LambdaPi invariant: vector elimination has a vector"))))

    ;; ---- Dependent expectations as data ----

    ;; A constant codomain captures its result at slot one after entry.
    (: constant-product (-> Value Value Value))
    (define (constant-product domain result)
      (ProductValue (Product domain (Scope (local 1) (Environment (Nil) (list result))))))

    (: nat-motive-type Value)
    (define nat-motive-type (constant-product (Natural) (Universe)))

    ;; Pi k:Nat. Pi ih:(m k). m (succ k). Captured environment is [m].
    ;; The driver will enter these scopes when checking each lambda.
    (: nat-step-type (-> Value Value))
    (define (nat-step-type motive)
      (ProductValue
       (Product (Natural)
                (Scope (pi (Inf (app (IBound (Index 1)) (local 0)))
                           (Inf (app (IBound (Index 2)) (successor (local 1)))))
                       (Environment (Nil) (list motive))))))

    ;; Pi n:Nat. Pi xs:(Vec A n). *. Captured environment is [A].
    (: vector-motive-type (-> Value Value))
    (define (vector-motive-type element)
      (ProductValue (Product (Natural)
                             (Scope (pi (vec (local 1) (local 0)) star)
                                    (Environment (Nil) (list element))))))

    ;; Pi n:Nat. Pi h:A. Pi t:(Vec A n). Pi ih:(m n t).
    ;;   m (succ n) (cons A n h t).
    ;; Captures [A,m]; under all four binders: [ih,t,h,n,A,m].
    (: vector-step-type (-> Value Value Value))
    (define (vector-step-type element motive)
      (ProductValue
       (Product (Natural)
                (Scope
                 (pi (local 1)
                     (pi (vec (local 2) (local 1))
                         (pi (Inf (apps (IBound (Index 4)) (list (local 2) (local 0))))
                             (Inf (apps (IBound (Index 5))
                                        (list (successor (local 3))
                                              (vcons (local 4) (local 3)
                                                     (local 2) (local 1))))))))
                 (Environment (Nil) (list element motive))))))))
