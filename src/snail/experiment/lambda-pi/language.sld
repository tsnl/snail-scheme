;; An experimental LambdaPi: syntax, semantic values and normal forms.
;; Node payloads are structs; the enums say which nodes each language admits.
(define-library (snail experiment lambda-pi language)
  (export
   Identifier Index Binder Ascription Product Application Successor
   NatElimination VectorType VectorCons VectorElimination
   Infer IAnn IStar IPi IBound IFree IApp INat INatElim IVec IVecElim
   Check Inf Lam Zero Succ VNil VCons
   Environment Scope Context empty-context
   Value Universe Function ProductValue Stuck Natural ZeroValue SuccessorValue
   VectorValue EmptyValue ConsValue
   Neutral FreeValue LocalValue ApplyValue NatElimValue VecElimValue
   Normal NormalStar NormalPi NormalLam NormalNeutral NormalNat NormalZero
   NormalSucc NormalVec NormalNil NormalCons
   NeutralNormal NormalFree NormalBound NormalApp NormalNatElim NormalVecElim
   Error UnknownName InvalidIndex ExpectedFunction ExpectedNatural
   ConversionMismatch DuplicateName
   star nat free local reference pi lam app apps typed successor number
   nat-elim vec vnil vcons vec-elim)
  (import
   (snail core base))
  (begin

    ;; ---- Constructor shapes ----

    (struct Identifier
      ((name String)))

    (struct Index
      ((index I64)))

    (struct (Binder Body)
      ((body Body)))

    (struct (Ascription Term Type)
      ((term Term)
       (type Type)))

    (struct (Product Domain Codomain)
      ((domain Domain)
       (codomain Codomain)))

    (struct (Application Function Argument)
      ((function Function)
       (argument Argument)))

    (struct (Successor Previous)
      ((previous Previous)))

    (struct (NatElimination Branch Scrutinee)
      ((motive Branch)
       (base Branch)
       (step Branch)
       (scrutinee Scrutinee)))

    (struct (VectorType Term)
      ((element Term)
       (size Term)))

    (struct (VectorCons Term)
      ((element Term)
       (size Term)
       (head Term)
       (tail Term)))

    (struct (VectorElimination Branch Scrutinee)
      ((element Branch)
       (motive Branch)
       (base Branch)
       (step Branch)
       (size Branch)
       (scrutinee Scrutinee)))

    ;; ---- Bidirectional input language ----

    ;; Bound indices count outwards from zero. Pi's codomain and a lambda's
    ;; body introduce one binder. A lambda needs an annotation to synthesize.
    (enum Infer
      (IAnn ((node (Ascription Check Check))))
      (IStar)
      (IPi ((node (Product Check Check))))
      (IBound ((node Index)))
      (IFree ((node Identifier)))
      (IApp ((node (Application Infer Check))))
      (INat)
      (INatElim ((node (NatElimination Check Check))))
      (IVec ((node (VectorType Check))))
      (IVecElim ((node (VectorElimination Check Check)))))

    (enum Check
      (Inf ((term Infer)))
      (Lam ((node (Binder Check))))
      (Zero)
      (Succ ((node (Successor Check))))
      (VNil ((element Check)))
      (VCons ((node (VectorCons Check)))))

    ;; ---- Semantic language ----

    ;; A closure captures values, including an immutable global environment.
    ;; It contains no host function or checking context. Entering it is an
    ;; explicit operation in the recursive driver.
    (struct Environment
      ((globals (List (Pair String Value)))
       (locals (List Value))))

    (struct Scope
      ((body Check)
       (environment Environment)))

    (enum Value
      (Universe)
      (Function ((scope Scope)))
      (ProductValue ((node (Product Value Scope))))
      (Stuck ((neutral Neutral)))
      (Natural)
      (ZeroValue)
      (SuccessorValue ((node (Successor Value))))
      (VectorValue ((node (VectorType Value))))
      (EmptyValue ((element Value)))
      (ConsValue ((node (VectorCons Value)))))

    ;; Semantic locals use levels: entering another binder never shifts them.
    ;; Eliminations blocked on an unknown retain their motive and branches.
    (enum Neutral
      (FreeValue ((node Identifier)))
      (LocalValue ((node Index)))
      (ApplyValue ((node (Application Neutral Value))))
      (NatElimValue ((node (NatElimination Value Neutral))))
      (VecElimValue ((node (VectorElimination Value Neutral)))))

    ;; Contexts extend local types and semantic locals together. Public
    ;; checking creates globals through assume/define-global, checking their
    ;; types before publishing either the type or its semantic binding.
    (struct Context
      ((global-types (List (Pair String Value)))
       (local-types (List Value))
       (environment Environment)))

    (: empty-context Context)
    (define empty-context (Context (Nil) (Nil) (Environment (Nil) (Nil))))

    ;; ---- Normal-form language ----

    ;; An application has a neutral head, and an elimination has a neutral
    ;; scrutinee. Beta and constructor-elimination redexes cannot be built.
    ;; These data types alone do not prove typing or scope correctness.
    (enum Normal
      (NormalStar)
      (NormalPi ((node (Product Normal Normal))))
      (NormalLam ((node (Binder Normal))))
      (NormalNeutral ((neutral NeutralNormal)))
      (NormalNat)
      (NormalZero)
      (NormalSucc ((node (Successor Normal))))
      (NormalVec ((node (VectorType Normal))))
      (NormalNil ((element Normal)))
      (NormalCons ((node (VectorCons Normal)))))

    (enum NeutralNormal
      (NormalFree ((node Identifier)))
      (NormalBound ((node Index)))
      (NormalApp ((node (Application NeutralNormal Normal))))
      (NormalNatElim ((node (NatElimination Normal NeutralNormal))))
      (NormalVecElim ((node (VectorElimination Normal NeutralNormal)))))

    (enum Error
      (UnknownName ((name String)))
      (InvalidIndex ((index I64)))
      (ExpectedFunction)
      (ExpectedNatural)
      (ConversionMismatch ((expected Normal)
                           (actual Normal)))
      (DuplicateName ((name String))))

    ;; ---- Small syntax builders ----

    ;; These are ordinary constructors, not a reader or a macro language.
    (: star Check)
    (define star (Inf (IStar)))
    (: nat Check)
    (define nat (Inf (INat)))

    (: free (-> String Infer))
    (define (free name) (IFree (Identifier name)))

    (: local (-> I64 Check))
    (define (local index) (Inf (IBound (Index index))))

    (: reference (-> String Check))
    (define (reference name) (Inf (free name)))

    (: pi (-> Check Check Check))
    (define (pi domain codomain) (Inf (IPi (Product domain codomain))))

    (: lam (-> Check Check))
    (define (lam body) (Lam (Binder body)))

    (: app (-> Infer Check Infer))
    (define (app function argument) (IApp (Application function argument)))

    (: apps (-> Infer (List Check) Infer))
    (define (apps function arguments) (fold-left app function arguments))

    (: typed (-> Check Check Infer))
    (define (typed term type) (IAnn (Ascription term type)))

    (: successor (-> Check Check))
    (define (successor previous) (Succ (Successor previous)))

    (: number (-> I64 Check))
    (define (number n)
      (if (< n 0) (panic "a natural literal is nonnegative")
          (if (= n 0) (Zero) (successor (number (- n 1))))))

    (: nat-elim (-> Check Check Check Check Infer))
    (define (nat-elim motive base step scrutinee)
      (INatElim (NatElimination motive base step scrutinee)))

    (: vec (-> Check Check Check))
    (define (vec element size) (Inf (IVec (VectorType element size))))

    (: vnil (-> Check Check))
    (define (vnil element) (VNil element))

    (: vcons (-> Check Check Check Check Check))
    (define (vcons element size head tail) (VCons (VectorCons element size head tail)))

    (: vec-elim (-> Check Check Check Check Check Check Infer))
    (define (vec-elim element motive base step size scrutinee)
      (IVecElim (VectorElimination element motive base step size scrutinee)))))
