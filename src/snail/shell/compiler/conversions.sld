;; Checked conversions become ordinary branches, constructors and an
;; abortive effect call. This runs after types are solved and before the
;; ownership and control passes, so both see every possible nonlocal exit.
(define-library (snail shell compiler conversions)
  (export
   dyn-tc-label
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

    (: dyn-tc-label String)
    (define dyn-tc-label "snail.core.base:dyn-tc")

    (: error-type Type)
    (define error-type (TCon "snail.core.base:CastError" (Nil)))

    (: any-type Type)
    (define any-type (TCon "Any" (Nil)))

    (: cast-result-type (-> Type Type))
    (define (cast-result-type target)
      (TCon "snail.core.base:Result" (list target error-type)))

    (: call (-> String (List Type) Type Type (List Expr) Loc Expr))
    (define (call name types result row args loc)
      (Expr (App (Expr (Var name types (Nil)) (TFun (map Expr-type args) result row) loc) args)
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
                         (TRow (list dyn-tc-label) (None)) (list error) loc)
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
      (let* ((name (string-append "%dyn-tc." (i64->string count) "%"))
             (value (Expr (Var name (Nil) (Nil)) any-type loc))
             (body (if (any-type? target)
                       (checked-branch attempt? value target loc)
                       (Expr (If (Expr (TypeTest value target) (TCon "Bool" (Nil)) loc)
                                 (checked-branch attempt? value target loc)
                                 (failed-branch attempt? value target loc))
                             (if attempt? (cast-result-type target) target) loc))))
        (Pair (Expr (Let name inner body) (Expr-type body) loc) (+ count 1))))

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

    (: lower-expr (-> I64 Expr (Pair Expr I64)))
    (define (lower-expr count expr)
      (let ((rebuild (lambda (term) (Expr term (Expr-type expr) (Expr-loc expr)))))
        (match (Expr-term expr)
          ((Convert inner target)
           (lowering count ((inner (lower-expr inner)))
                     (cond ((type=? (Expr-type inner) target) (Pair inner count))
                           ((any-type? target) (Pair (rebuild (Convert inner target)) count))
                           (else (projection count #f inner target (Expr-loc expr))))))
          ((TryConvert inner target)
           (lowering count ((inner (lower-expr inner)))
                     (projection count #t inner target (Expr-loc expr))))
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
           (lowering count ((value (lower-expr value)) (clauses (lower-clauses clauses)))
                     (Pair (rebuild (Match value clauses)) count)))
          ((Ann inner type)
           (lowering count ((inner (lower-expr inner)))
                     (Pair (rebuild (Ann inner type)) count)))
          ((TypeTest inner target)
           (lowering count ((inner (lower-expr inner)))
                     (Pair (rebuild (TypeTest inner target)) count)))
          ((Handle effect implementations body)
           (lowering count ((values (lower-exprs (map Pair-second implementations)))
                            (body (lower-expr body)))
                     (Pair
                      (rebuild (Handle effect (zip (map Pair-first implementations) values) body))
                      count)))
          (_ (Pair expr count)))))

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
         (lowering count ((body (lower-expr (Clause-body clause))) (rest (lower-clauses rest)))
                   (Pair (Cons (Clause (Clause-pattern clause) body) rest) count)))
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
       (Pair-first
        (fold-left (lambda (result item)
                     (match (lower-item (Pair-second result) item)
                       ((Pair item count) (Pair (Cons item (Pair-first result)) count))))
                   (Pair (Nil) 0) items))))))
