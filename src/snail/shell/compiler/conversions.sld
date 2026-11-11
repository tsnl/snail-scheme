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

    (define dyn-cast-label (→ String) "snail.core.base:dyn-cast")

    (define error-type (→ Type) (TCon "snail.core.base:CastError" (Nil)))

    (define any-type (→ Type) (TCon "Any" (Nil)))

    (define (cast-result-type (target Type)) (→ Type)
      (TCon "snail.core.base:Result" (list target error-type)))

    (define (call (name String)
                  (types (List Type))
                  (result Type)
                  (row Type)
                  (args (List Expr))
                  (loc Loc))
      (→ Expr)
      (Expr (App (Expr (Var name types (Nil))
                       (TFun (map (lambda (record) (● record type)) args) result row)
                       loc)
                 args)
            result loc))

    (define (text-value (value String) (loc Loc)) (→ Expr)
      (Expr (Lit (DString value)) (TCon "String" (Nil)) loc))

    (define (integer-value (value I64) (loc Loc)) (→ Expr)
      (Expr (Lit (DInt value)) (TCon "I64" (Nil)) loc))

    (define (string-list (values (List String)) (loc Loc)) (→ Expr)
      (let ((string (TCon "String" (Nil)))
            (list-type (TCon "snail.core.base:List" (list (TCon "String" (Nil))))))
        (fold-right (lambda (value rest)
                      (call "snail.core.base:Cons" (list string) list-type empty-row
                            (list (text-value value loc) rest) loc))
                    (call "snail.core.base:Nil" (list string) list-type empty-row (Nil) loc)
                    values)))

    (define (conversion-error (reason String)
                              (expected (List Type))
                              (value Expr)
                              (method String)
                              (argument I64)
                              (loc Loc))
      (→ Expr)
      (call "snail.core.base:CastError" (Nil) error-type empty-row
            (list (call (string-append "snail.core.base:" reason) (Nil)
                        (TCon "snail.core.base:CastReason" (Nil)) empty-row (Nil) loc)
                  (string-list (map type->string expected) loc)
                  (call "prim:any-type-id" (Nil) (TCon "I64" (Nil)) empty-row (list value) loc)
                  (text-value (loc->string loc) loc)
                  (text-value method loc)
                  (integer-value argument loc))
            loc))

    (define (conversion-failure (error Expr) (target Type) (loc Loc)) (→ Expr)
      (Expr (Match (call "snail.core.base:conversion-failed" (Nil)
                         (TCon "snail.core.base:Never" (Nil))
                         (TRow (list dyn-cast-label) (None)) (list error) loc)
                   (Nil)) target loc))

    ;; Only the success branch constructs a raw projection. Its type test
    ;; established both the identity and the representation of that value.

    (define (checked-branch (attempt? Bool) (value Expr) (target Type) (loc Loc)) (→ Expr)
      (let ((checked (if (any-type? target) value (Expr (Convert value target) target loc))))
        (if attempt?
            (call "snail.core.base:Ok" (list target error-type) (cast-result-type target)
                  empty-row (list checked) loc)
            checked)))

    (define (failed-branch (attempt? Bool) (value Expr) (target Type) (loc Loc)) (→ Expr)
      (let ((error (conversion-error "TypeMismatch" (list target) value "" -1 loc)))
        (if attempt?
            (call "snail.core.base:Err" (list target error-type) (cast-result-type target)
                  empty-row (list error) loc)
            (conversion-failure error target loc))))

    (define (projection (count I64) (attempt? Bool) (inner Expr) (target Type) (loc Loc))
      (→ (Pair Expr I64))
      (let* ((name (string-append "%dyn-cast." (i64->string count) "%"))
             (value (Expr (Var name (Nil) (Nil)) any-type loc))
             (body (if (any-type? target)
                       (checked-branch attempt? value target loc)
                       (Expr (If (Expr (TypeTest value target) (TCon "Bool" (Nil)) loc)
                                 (checked-branch attempt? value target loc)
                                 (failed-branch attempt? value target loc))
                             (if attempt? (cast-result-type target) target) loc))))
        (Pair (Expr (Let name inner body) (● body type) loc) (+ count 1))))

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

    (define (probe (value Expr) (pattern Pattern)) (→ (Option Probe))
      (match (Pair (● value term) pattern)
        ((Pair (TryConvert input target)
               (PCon "snail.core.base:Ok" (Cons (PVar name _) (Nil)) _))
         (Some (Probe input target name (● value loc))))
        (_ (None))))

    (define (probes (value Expr) (pattern Pattern)) (→ (Option (List Probe)))
      (match (Pair (● value term) pattern)
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

    (define (probe-test (held (List (Pair Probe Expr))) (loc Loc)) (→ Expr)
      (let ((bool (TCon "Bool" (Nil))))
        (fold-right (lambda (entry rest)
                      (let* ((probe (● entry first)) (target (● probe target)))
                        (if (any-type? target) rest
                            (Expr
                             (If (Expr (TypeTest (● entry second) target) bool (● probe loc))
                                 rest (Expr (Lit (DBool #f)) bool loc)) bool loc))))
                    (Expr (Lit (DBool #t)) bool loc) held)))

    (define (probe-values (held (List (Pair Probe Expr))) (body Expr) (loc Loc)) (→ Expr)
      (fold-right (lambda (entry body)
                    (let ((probe (● entry first)))
                      (Expr (Let (● probe name)
                                 (checked-branch #f (● entry second) (● probe target)
                                                 (● probe loc))
                                 body) (● body type) loc)))
                  body held))

    ;; Evaluate every input before selecting a branch: Pair is strict even
    ;; when its left probe fails. The fallback appears once, preserving the
    ;; unique names of its local bindings and control continuations.

    (define (probe-body (count I64)
                        (probes (List Probe))
                        (inputs (List Expr))
                        (success Expr)
                        (failure Expr)
                        (matched Expr))
      (→ Expr)
      (let* ((loc (● matched loc))
             (names (map (lambda (i) (string-append "%dyn-cast." (i64->string (+ count i)) "%"))
                         (iota (length probes))))
             (values (map (lambda (name) (Expr (Var name (Nil) (Nil)) any-type loc)) names))
             (held (zip probes values))
             (body (Expr (If (probe-test held loc) (probe-values held success loc) failure)
                         (● matched type) loc)))
        (fold-right (lambda (entry body)
                      (Expr (Let (● entry first) (● entry second) body) (● body type) loc))
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

    (define (lower-probes (count I64)
                          (probes (List Probe))
                          (success Expr)
                          (failure Expr)
                          (matched Expr))
      (→ (Pair Expr I64))
      (lowering count ((inputs (lower-exprs (map (lambda (record) (● record input)) probes)))
                       (success (lower-expr success))
                       (failure (lower-expr failure)))
                (Pair (probe-body count probes inputs success failure matched)
                      (+ count (length probes)))))

    (define (lower-expr (count I64) (expr Expr)) (→ (Pair Expr I64))
      (let ((rebuild (lambda (term) (Expr term (● expr type) (● expr loc)))))
        (match (● expr term)
          ((Convert inner target)
           (lowering count ((inner (lower-expr inner)))
                     (cond ((type=? (● inner type) target) (Pair inner count))
                           ((any-type? target) (Pair (rebuild (Convert inner target)) count))
                           (else (projection count #f inner target (● expr loc))))))
          ((TryConvert inner target)
           (lowering count ((inner (lower-expr inner)))
                     (projection count #t inner target (● expr loc))))
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
          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((Ann inner type)
           (lowering count ((inner (lower-expr inner)))
                     (Pair (rebuild (Ann inner type)) count)))
          ((TypeTest inner target)
           (lowering count ((inner (lower-expr inner)))
                     (Pair (rebuild (TypeTest inner target)) count)))
          ((Handle effect implementations body)
           (lowering count
                     ((values
                       (lower-exprs (map (lambda (record) (● record second)) implementations)))
                      (body (lower-expr body)))
                     (Pair
                      (rebuild (Handle effect
                                       (zip (map (lambda (record) (● record first)) implementations)
                                            values)
                                       body))
                      count)))
          (_ (Pair expr count)))))

    (define (lower-match (count I64) (expr Expr) (value Expr) (clauses (List Clause)))
      (→ (Pair Expr I64))
      (match clauses
        ((Cons (Clause pattern success) (Cons (Clause (PWild _) failure) (Nil)))
         (match (probes value pattern)
           ((Some found) (lower-probes count found success failure expr))
           ((None) (lower-ordinary-match count expr value clauses))))
        (_ (lower-ordinary-match count expr value clauses))))

    (define (lower-ordinary-match (count I64) (expr Expr) (value Expr) (clauses (List Clause)))
      (→ (Pair Expr I64))
      (lowering count ((value (lower-expr value)) (clauses (lower-clauses clauses)))
                (Pair (Expr (Match value clauses) (● expr type) (● expr loc)) count)))

    (define (lower-exprs (count I64) (exprs (List Expr))) (→ (Pair (List Expr) I64))
      (match exprs
        ((Cons first rest)
         (lowering count ((first (lower-expr first)) (rest (lower-exprs rest)))
                   (Pair (Cons first rest) count)))
        ((Nil) (Pair (Nil) count))))

    (define (lower-clauses (count I64) (clauses (List Clause))) (→ (Pair (List Clause) I64))
      (match clauses
        ((Cons clause rest)
         (lowering count ((body (lower-expr (● clause body))) (rest (lower-clauses rest)))
                   (Pair (Cons (Clause (● clause pattern) body) rest) count)))
        ((Nil) (Pair (Nil) count))))

    (define (lower-item (count I64) (item Item)) (→ (Pair Item I64))
      (match item
        ((Define name value)
         (lowering count ((value (lower-expr value))) (Pair (Define name value) count)))
        ((Do value)
         (lowering count ((value (lower-expr value))) (Pair (Do value) count)))
        (_ (Pair item count))))

    (define (lower-conversions (items (List Item))) (→ (List Item))
      (reverse
       (● (fold-left (lambda (result item)
                       (match (lower-item (● result second) item)
                         ((Pair item count) (Pair (Cons item (● result first)) count))))
                     (Pair (Nil) 0) items) first))))

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
      (define local (lambda (name type) (Expr (Var name (Nil) (Nil)) type loc)))
      (define attempt
        (lambda (value type) (Expr (TryConvert value type) (cast-result-type type) loc)))
      (define ok-pattern
        (lambda (name type)
          (PCon "snail.core.base:Ok" (list (PVar name type)) (cast-result-type type))))
      (define matched
        (lambda (value pattern fallback)
          (Expr (Match value (list (Clause pattern (integer-value 1 loc)) fallback)) i64 loc)))
      (define lower (lambda (value) (● (lower-expr 0 value) first)))

      (define count-terms
        (lambda (predicate value) (+ (if (predicate (● value term)) 1 0)
                                     (fold-left
                                      (lambda (total child) (+ total (count-terms predicate child)))
                                      0 (expr-children value)))))
      (define references
        (lambda (name value) (count-terms (lambda (term)
                                            (match term
                                              ((Var actual _ _) (string=? name actual))
                                              (_ #f)))
                                          value)))
      (define tests
        (lambda (value)
          (count-terms (lambda (term) (match term ((TypeTest _ _) #t) (_ #f))) value)))
      (define projections
        (lambda (value) (count-terms (lambda (term) (match term ((Convert _ _) #t) (_ #f))) value)))
      (define expect-no-packaging
        (lambda (value) (for-each (lambda (name) (expect (references name value) 0))
                                  (list "snail.core.base:Pair"
                                        "snail.core.base:Ok"
                                        "snail.core.base:Err"
                                        "snail.core.base:CastError"))))

      (define test-conversions
        (lambda () (test-single-probe)
                (test-paired-probes)
                (test-observed-results)))

      (define test-single-probe
        (lambda () (for-each
                    (lambda (target)
                      (let ((body (lower (matched
                                          (attempt (call "input" (Nil) any-type empty-row (Nil) loc)
                                                   target)
                                          (ok-pattern "typed" target)
                                          (Clause (PWild (cast-result-type target))
                                                  (integer-value 0 loc))))))
                        (expect (references "input" body) 1)
                        (expect (tests body) (if (any-type? target) 0 1))
                        (expect (projections body) (if (any-type? target) 0 1))
                        (expect-no-packaging body)))
                    (list i64 string any-type))))

      (define test-paired-probes
        (lambda () (let* ((left (attempt (call "left" (Nil) any-type empty-row (Nil) loc) i64))
                          (right (attempt (call "right" (Nil) any-type empty-row (Nil) loc) string))
                          (types (list (● left type) (● right type)))
                          (pair (TCon "snail.core.base:Pair" types))
                          (value
                           (call "snail.core.base:Pair" types pair empty-row (list left right) loc))
                          (pattern (PCon "snail.core.base:Pair"
                                         (list (ok-pattern "a" i64) (ok-pattern "b" string)) pair))
                          (fallback
                           (Clause (PWild pair) (call "fallback" (Nil) i64 empty-row (Nil) loc)))
                          (body (lower (matched value pattern fallback))))
                     (for-each (lambda (name) (expect (references name body) 1))
                               (list "left" "right" "fallback"))
                     (expect (tests body) 2)
                     (expect (projections body) 2)
                     (expect-no-packaging body))))

      ;; An escaping result or a fallback binding can observe the error.
      (define test-observed-results
        (lambda () (let* ((value (attempt (local "input" any-type) i64))
                          (fallback (Clause (PVar "result" (● value type))
                                            (call "observe" (Nil) i64 empty-row
                                                  (list (local "result" (● value type))) loc))))
                     (for-each (lambda (body)
                                 (expect (references "snail.core.base:Ok" body) 1)
                                 (expect (references "snail.core.base:Err" body) 1)
                                 (expect (references "snail.core.base:CastError" body) 1))
                               (list (lower value)
                                     (lower
                                      (matched value (ok-pattern "typed" i64) fallback)))))))))))
