;; Checked conversions become ordinary branches, constructors and an
;; abortive effect call. This runs after types are solved and before the
;; ownership and control passes, so both see every possible nonlocal exit.
(define-library (snail shell compiler conversions)
  (export
   dyn-cast-label
   cast-result-type
   conversion-error
   conversion-failure
   lower-conversions)
  (import
   (snail core base)
   (snail shell compiler read)
   (snail shell compiler core))
  (begin

    ;; ---- Runtime contract ----

    (: dyn-cast-label String)
    (define dyn-cast-label "snail.core.base:dyn-cast")

    (: error-type Type)
    (define error-type (TCon "snail.core.base:CastError" (Nil)))

    (: any-type Type)
    (define any-type (TCon "Any" (Nil)))

    (: cast-result-type (-> Type Type))
    (define (cast-result-type target)
      (TCon "snail.core.base:Result" (list target error-type)))

    (: call (-> String (List Type) Type Type (List Expr) Loc Expr))
    (define (call name types result row args loc)
      (Expr (App (Expr (Var name types (Nil)) (TFun (map ::type args) result row) loc) args)
            result loc))

    (: text-value (-> String Loc Expr))
    (define (text-value value loc)
      (Expr (Lit (DString value)) (TCon "String" (Nil)) loc))

    (: integer-value (-> I64 Loc Expr))
    (define (integer-value value loc)
      (Expr (Lit (DInt value)) (TCon "I64" (Nil)) loc))

    (: string-list (-> (List String) Loc Expr))
    (define (string-list values loc)
      (let ((string (TCon "String" (Nil)))
            (list-type (TCon "snail.core.base:List" (list (TCon "String" (Nil))))))
        (fold-right (lambda (value rest)
                      (call "snail.core.base:Cons" (list string) list-type empty-row
                            (list (text-value value loc) rest) loc))
                    (call "snail.core.base:Nil" (list string) list-type empty-row (Nil) loc)
                    values)))

    (: conversion-error (-> String (List Type) Expr String I64 Loc Expr))
    (define (conversion-error reason expected value method argument loc)
      (call "snail.core.base:CastError" (Nil) error-type empty-row
            (list (call (string-append "snail.core.base:" reason) (Nil)
                        (TCon "snail.core.base:CastReason" (Nil)) empty-row (Nil) loc)
                  (string-list (map type->string expected) loc)
                  (call "prim:any-type-id" (Nil) (TCon "I64" (Nil)) empty-row (list value) loc)
                  (text-value (loc->string loc) loc)
                  (text-value method loc)
                  (integer-value argument loc))
            loc))

    (: conversion-failure (-> Expr Type Loc Expr))
    (define (conversion-failure error target loc)
      (Expr (Match (call "snail.core.base:conversion-failed" (Nil)
                         (TCon "snail.core.base:Never" (Nil))
                         (TRow (list dyn-cast-label) (None)) (list error) loc)
                   (Nil)) target loc))

    ;; Only the success branch constructs a raw projection. Its type test
    ;; established both the identity and the representation of that value.
    (: checked-branch (-> Bool Expr Type Loc Expr))
    (define (checked-branch attempt? value target loc)
      (let ((checked (if (any-type? target) value (Expr (Convert value target) target loc))))
        (if attempt?
            (call "snail.core.base:Ok" (list target error-type) (cast-result-type target)
                  empty-row (list checked) loc)
            checked)))

    (: failed-branch (-> Bool Expr Type Loc Expr))
    (define (failed-branch attempt? value target loc)
      (let ((error (conversion-error "TypeMismatch" (list target) value "" -1 loc)))
        (if attempt?
            (call "snail.core.base:Err" (list target error-type) (cast-result-type target)
                  empty-row (list error) loc)
            (conversion-failure error target loc))))

    (: projection (-> I64 Bool Expr Type Loc (Pair Expr I64)))
    (define (projection count attempt? inner target loc)
      (let* ((name (string-append "%dyn-cast." (i64->string count) "%"))
             (value (Expr (Var name (Nil) (Nil)) any-type loc))
             (body (if (any-type? target)
                       (checked-branch attempt? value target loc)
                       (Expr (If (Expr (TypeTest value target) (TCon "Bool" (Nil)) loc)
                                 (checked-branch attempt? value target loc)
                                 (failed-branch attempt? value target loc))
                             (if attempt? (cast-result-type target) target) loc))))
        (Pair (Expr (Let name inner body) (::type body) loc) (+ count 1))))

    ;; ---- Immediate probes ----

    ;; A flat Ok binding consumes a checked value; an unbound fallback
    ;; cannot observe its Result or error. Keep the input and recovered
    ;; binding together. Nested patterns and observed errors stay ordinary
    ;; matches, so their fallthrough and diagnostics need no special rules.
    (struct Probe
      ((input Expr)
       (target Type)
       (name String)
       (loc Loc)))

    (: probe (-> Expr Pattern (Option Probe)))
    (define (probe value pattern)
      (match (Pair (::term value) pattern)
        ((Pair (TryConvert input target)
               (PCon "snail.core.base:Ok" (Cons (PVar name _) (Nil)) _))
         (Some (Probe input target name (::loc value))))
        (_ (None))))

    (: probes (-> Expr Pattern (Option (List Probe))))
    (define (probes value pattern)
      (match (Pair (::term value) pattern)
        ((Pair (App (Expr (Var "snail.core.base:Pair" _ _) _ _)
                    (Cons left (Cons right (Nil))))
               (PCon "snail.core.base:Pair" (Cons left-pattern (Cons right-pattern (Nil))) _))
         (match (Pair (probe left left-pattern) (probe right right-pattern))
           ((Pair (Some left) (Some right)) (Some (list left right)))
           (_ (None))))
        (_ (match (probe value pattern)
             ((Some found) (Some (list found)))
             ((None) (None))))))

    ;; These inputs are unrestricted Any values. Projection only recovers
    ;; their payload; it neither creates a resource nor needs cleanup when
    ;; another probe fails. Type tests and projections still reach ownership
    ;; checking, which rejects ineligible payload types as before.
    (: probe-test (-> (List (Pair Probe Expr)) Loc Expr))
    (define (probe-test held loc)
      (let ((bool (TCon "Bool" (Nil))))
        (fold-right (lambda (entry rest)
                      (let* ((probe (::first entry)) (target (::target probe)))
                        (if (any-type? target) rest
                            (Expr
                             (If (Expr (TypeTest (::second entry) target) bool (::loc probe))
                                 rest (Expr (Lit (DBool #f)) bool loc)) bool loc))))
                    (Expr (Lit (DBool #t)) bool loc) held)))

    (: probe-values (-> (List (Pair Probe Expr)) Expr Loc Expr))
    (define (probe-values held body loc)
      (fold-right (lambda (entry body)
                    (let ((probe (::first entry)))
                      (Expr (Let (::name probe)
                                 (checked-branch #f (::second entry) (::target probe)
                                                 (::loc probe))
                                 body) (::type body) loc)))
                  body held))

    ;; Evaluate every input before selecting a branch: Pair is strict even
    ;; when its left probe fails. The fallback appears once, preserving the
    ;; unique names of its local bindings and control continuations.
    (: probe-body (-> I64 (List Probe) (List Expr) Expr Expr Expr Expr))
    (define (probe-body count probes inputs success failure matched)
      (let* ((loc (::loc matched))
             (names (map (lambda (i) (string-append "%dyn-cast." (i64->string (+ count i)) "%"))
                         (iota (length probes))))
             (values (map (lambda (name) (Expr (Var name (Nil) (Nil)) any-type loc)) names))
             (held (zip probes values))
             (body (Expr (If (probe-test held loc) (probe-values held success loc) failure)
                         (::type matched) loc)))
        (fold-right (lambda (entry body)
                      (Expr (Let (::first entry) (::second entry) body) (::type body) loc))
                    body (zip names inputs))))

    ;; ---- Traversal ----

    ;; A counter is the only state: fresh locals never shadow a source
    ;; binding or another inserted check. No registry or runtime dictionary
    ;; is involved in checking a value's existing type identity.
    (define-syntax lowering
      (syntax-rules ()
        ((_ count () body ...) (begin body ...))
        ((_ count ((name (step argument ...)) rest ...) body ...)
         (match (step count argument ...)
           ((Pair name count) (lowering count (rest ...) body ...))))))

    (: lower-probes (-> I64 (List Probe) Expr Expr Expr (Pair Expr I64)))
    (define (lower-probes count probes success failure matched)
      (lowering count ((inputs (lower-exprs (map ::input probes)))
                       (success (lower-expr success))
                       (failure (lower-expr failure)))
                (Pair (probe-body count probes inputs success failure matched)
                      (+ count (length probes)))))

    (: lower-expr (-> I64 Expr (Pair Expr I64)))
    (define (lower-expr count expr)
      (let ((rebuild (lambda (term) (Expr term (::type expr) (::loc expr)))))
        (match (::term expr)
          ((Convert inner target)
           (lowering count ((inner (lower-expr inner)))
                     (cond ((type=? (::type inner) target) (Pair inner count))
                           ((any-type? target) (Pair (rebuild (Convert inner target)) count))
                           (else (projection count #f inner target (::loc expr))))))
          ((TryConvert inner target)
           (lowering count ((inner (lower-expr inner)))
                     (projection count #t inner target (::loc expr))))
          ((Lambda params body captures?)
           (lowering count ((body (lower-expr body)))
                     (Pair (rebuild (Lambda params body captures?)) count)))
          ((App callee args)
           (lowering count ((callee (lower-expr callee)) (args (lower-exprs args)))
                     (Pair (rebuild (App callee args)) count)))
          ((If test then otherwise)
           (lowering count ((test (lower-expr test)) (then (lower-expr then))
                            (otherwise (lower-expr otherwise)))
                     (Pair (rebuild (If test then otherwise)) count)))
          ((Let name value body)
           (lowering count ((value (lower-expr value)) (body (lower-expr body)))
                     (Pair (rebuild (Let name value body)) count)))
          ((Seq first rest)
           (lowering count ((first (lower-expr first)) (rest (lower-expr rest)))
                     (Pair (rebuild (Seq first rest)) count)))
          ((Match value clauses)
           (lower-match count expr value clauses))
          ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
          ((Ann inner type)
           (lowering count ((inner (lower-expr inner)))
                     (Pair (rebuild (Ann inner type)) count)))
          ((TypeTest inner target)
           (lowering count ((inner (lower-expr inner)))
                     (Pair (rebuild (TypeTest inner target)) count)))
          ((Handle effect implementations body)
           (lowering count ((values (lower-exprs (map ::second implementations)))
                            (body (lower-expr body)))
                     (Pair
                      (rebuild (Handle effect (zip (map ::first implementations) values) body))
                      count)))
          (_ (Pair expr count)))))

    (: lower-match (-> I64 Expr Expr (List Clause) (Pair Expr I64)))
    (define (lower-match count expr value clauses)
      (match clauses
        ((Cons (Clause pattern success) (Cons (Clause (PWild _) failure) (Nil)))
         (match (probes value pattern)
           ((Some found) (lower-probes count found success failure expr))
           ((None) (lower-ordinary-match count expr value clauses))))
        (_ (lower-ordinary-match count expr value clauses))))

    (: lower-ordinary-match (-> I64 Expr Expr (List Clause) (Pair Expr I64)))
    (define (lower-ordinary-match count expr value clauses)
      (lowering count ((value (lower-expr value)) (clauses (lower-clauses clauses)))
                (Pair (Expr (Match value clauses) (::type expr) (::loc expr)) count)))

    (: lower-exprs (-> I64 (List Expr) (Pair (List Expr) I64)))
    (define (lower-exprs count exprs)
      (match exprs
        ((Cons first rest)
         (lowering count ((first (lower-expr first)) (rest (lower-exprs rest)))
                   (Pair (Cons first rest) count)))
        ((Nil) (Pair (Nil) count))))

    (: lower-clauses (-> I64 (List Clause) (Pair (List Clause) I64)))
    (define (lower-clauses count clauses)
      (match clauses
        ((Cons clause rest)
         (lowering count ((body (lower-expr (::body clause))) (rest (lower-clauses rest)))
                   (Pair (Cons (Clause (::pattern clause) body) rest) count)))
        ((Nil) (Pair (Nil) count))))

    (: lower-item (-> I64 Item (Pair Item I64)))
    (define (lower-item count item)
      (match item
        ((Define name value)
         (lowering count ((value (lower-expr value))) (Pair (Define name value) count)))
        ((Do value)
         (lowering count ((value (lower-expr value))) (Pair (Do value) count)))
        (_ (Pair item count))))

    (: lower-conversions (-> (List Item) (List Item)))
    (define (lower-conversions items)
      (reverse
       (::first
        (fold-left (lambda (result item)
                     (match (lower-item (::second result) item)
                       ((Pair item count) (Pair (Cons item (::first result)) count))))
                   (Pair (Nil) 0) items)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-conversions)
    (import
     (snail stage0 testing))
    (begin
      (define i64 (TCon "I64" (Nil)))
      (define string (TCon "String" (Nil)))
      (define loc (Loc "conversions" 1 1))
      (define (local name type) (Expr (Var name (Nil) (Nil)) type loc))
      (define (attempt value type) (Expr (TryConvert value type) (cast-result-type type) loc))
      (define (ok-pattern name type)
        (PCon "snail.core.base:Ok" (list (PVar name type)) (cast-result-type type)))
      (define (matched value pattern fallback)
        (Expr (Match value (list (Clause pattern (integer-value 1 loc)) fallback)) i64 loc))
      (define (lower value) (::first (lower-expr 0 value)))

      (define (count-terms predicate value)
        (+ (if (predicate (::term value)) 1 0)
           (fold-left (lambda (total child) (+ total (count-terms predicate child)))
                      0 (expr-children value))))
      (define (references name value)
        (count-terms (lambda (term)
                       (match term ((Var actual _ _) (string=? name actual)) (_ #f))) value))
      (define (tests value)
        (count-terms (lambda (term) (match term ((TypeTest _ _) #t) (_ #f))) value))
      (define (projections value)
        (count-terms (lambda (term) (match term ((Convert _ _) #t) (_ #f))) value))
      (define (expect-no-packaging value)
        (for-each (lambda (name) (expect (references name value) 0))
                  (list "snail.core.base:Pair" "snail.core.base:Ok" "snail.core.base:Err"
                        "snail.core.base:CastError")))

      (define (test-conversions)
        (test-single-probe)
        (test-paired-probes)
        (test-observed-results))

      (define (test-single-probe)
        (for-each
         (lambda (target)
           (let ((body (lower (matched (attempt (call "input" (Nil) any-type empty-row (Nil) loc)
                                                target)
                                       (ok-pattern "typed" target)
                                       (Clause (PWild (cast-result-type target))
                                               (integer-value 0 loc))))))
             (expect (references "input" body) 1)
             (expect (tests body) (if (any-type? target) 0 1))
             (expect (projections body) (if (any-type? target) 0 1))
             (expect-no-packaging body)))
         (list i64 string any-type)))

      (define (test-paired-probes)
        (let* ((left (attempt (call "left" (Nil) any-type empty-row (Nil) loc) i64))
               (right (attempt (call "right" (Nil) any-type empty-row (Nil) loc) string))
               (types (list (::type left) (::type right)))
               (pair (TCon "snail.core.base:Pair" types))
               (value (call "snail.core.base:Pair" types pair empty-row (list left right) loc))
               (pattern (PCon "snail.core.base:Pair"
                              (list (ok-pattern "a" i64) (ok-pattern "b" string)) pair))
               (fallback (Clause (PWild pair) (call "fallback" (Nil) i64 empty-row (Nil) loc)))
               (body (lower (matched value pattern fallback))))
          (for-each (lambda (name) (expect (references name body) 1))
                    (list "left" "right" "fallback"))
          (expect (tests body) 2)
          (expect (projections body) 2)
          (expect-no-packaging body)))

      ;; An escaping result or a fallback binding can observe the error.
      (define (test-observed-results)
        (let* ((value (attempt (local "input" any-type) i64))
               (fallback (Clause (PVar "result" (::type value))
                                 (call "observe" (Nil) i64 empty-row
                                       (list (local "result" (::type value))) loc))))
          (for-each (lambda (body)
                      (expect (references "snail.core.base:Ok" body) 1)
                      (expect (references "snail.core.base:Err" body) 1)
                      (expect (references "snail.core.base:CastError" body) 1))
                    (list (lower value)
                          (lower (matched value (ok-pattern "typed" i64) fallback))))))))))
