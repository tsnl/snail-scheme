;; The code that recovers a typed value from Any, and the code that fails a
;; dispatch with a CastError, as the old compiler's `recover-value`
;; (src/snail/shell/compiler/dynamic.sld) and `conversion-error` and
;; `conversion-failure` (src/snail/shell/compiler/conversions.sld) write
;; them. A dispatch clause's methods and a generated instance's are made of
;; these, every node at the place handed in.
;;
;;   (match (try-convert value target)       ; a recovery
;;     ((Ok local) success)
;;     (_ failure))
;;
;;   (match (conversion-failed               ; a failure: a match of no
;;           (CastError (reason)             ; clause, since the operation
;;                      (Cons "T" ... (Nil)) ; never returns
;;                      (any-type-id value)
;;                      "FILE:LINE:COLUMN"
;;                      "LIBRARY:method"
;;                      argument)))
;;
;; The texts are (snail compiler dispatch text)'s: each expected type's,
;; the place's, and the method's, the member whose call failed.
(define-library (snail compiler dispatch conversions)
  (export
   recovered
   cast-failure)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler expand language) Global Local TopGlobal Text Integer)
   (prefix (snail compiler declare language) declared-)
   (snail compiler dispatch runtime)
   (snail compiler dispatch text))
  (begin

    ;; ---- Recoveries ----

    ;; `success` with `local` bound to the value `value`, an Any, holds as
    ;; a `target`, and else `failure`.
    (: recovered
       (impl
        (Fn declared-Expr declared-Type Local declared-Expr declared-Expr Loc -> declared-Expr)))
    (define (recovered value target local success failure loc)
      (declared-Match (declared-TryConvert value target loc)
                      (list (declared-Clause (declared-Destructure (TopGlobal ok-case)
                                                                   (list (declared-Bind local loc))
                                                                   loc)
                                             success
                                             loc)
                            (declared-Clause (declared-Wild loc) failure loc))
                      loc))

    ;; ---- Failures ----

    ;; The dispatch fails for `reason`, UnsupportedInstance or
    ;; ArgumentMismatch, expecting one of `expected`, where the argument at
    ;; `index` of a call of `member` was `value`.
    (: cast-failure
       (impl
        (Fn Global (List declared-Type) declared-Expr declared-Member I64 Loc -> declared-Expr)))
    (define (cast-failure reason expected value member index loc)
      (declared-Match (called conversion-failed-operation
                              (list (called cast-error-case
                                            (list (called reason (Nil) loc)
                                                  (texts (map type-text expected) loc)
                                                  (called any-type-id-primitive (list value) loc)
                                                  (text (place-text loc) loc)
                                                  (text (member-text member) loc)
                                                  (declared-Literal (Integer index) loc))
                                            loc))
                              loc)
                      (Nil)
                      loc))

    ;; `(Cons "a" (Cons "b" (Nil)))`.
    (: texts (impl (Fn (List String) Loc -> declared-Expr)))
    (define (texts values loc)
      (fold-right (lambda (value rest) (called cons-case (list (text value loc) rest) loc))
                  (called nil-case (Nil) loc)
                  values))

    (: text (impl (Fn String Loc -> declared-Expr)))
    (define (text value loc)
      (declared-Literal (Text value) loc))

    (: called (impl (Fn Global (List declared-Expr) Loc -> declared-Expr)))
    (define (called global arguments loc)
      (declared-Call (declared-TopRef (TopGlobal global) loc) arguments loc))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-conversions)
    (import
     (only (snail compiler declare forms) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-conversions)
        (test-recovered)
        (test-failure))

      (define loc (Loc "t.sld" 4 1))
      (define i64 (declared-Con (Global forms-library "I64" 0) (list)))
      (define value (declared-LocalRef (Local "argument" 1) loc))

      (define (top global)
        (declared-TopRef (TopGlobal global) loc))

      (define (test-recovered)
        (expect
         (recovered value i64 (Local "selected" 2) value (declared-Literal (Integer 0) loc) loc)
         (declared-Match (declared-TryConvert value i64 loc)
                         (list (declared-Clause (declared-Destructure (TopGlobal ok-case)
                                                                      (list (declared-Bind
                                                                             (Local "selected" 2)
                                                                             loc))
                                                                      loc)
                                                value
                                                loc)
                               (declared-Clause (declared-Wild loc)
                                                (declared-Literal (Integer 0) loc)
                                                loc))
                         loc)))

      ;; Read off `conversion-error`: the reason, the expected types' texts
      ;; as a list, the value's TypeId, the place, the method and the
      ;; argument's index.
      (define (test-failure)
        (let ((plus (declared-ClassMethod (Global (list "snail" "core" "base") "+" 0))))
          (expect (cast-failure argument-mismatch-case (list i64) value plus 1 loc)
                  (declared-Match
                   (declared-Call
                    (top conversion-failed-operation)
                    (list (declared-Call (top cast-error-case)
                                         (list
                                          (declared-Call (top argument-mismatch-case) (list) loc)
                                          (declared-Call (top cons-case)
                                                         (list (declared-Literal (Text "I64") loc)
                                                               (declared-Call (top nil-case)
                                                                              (list)
                                                                              loc))
                                                         loc)
                                          (declared-Call (top any-type-id-primitive)
                                                         (list value)
                                                         loc)
                                          (declared-Literal (Text "t.sld:4:1") loc)
                                          (declared-Literal (Text "snail.core.base:+") loc)
                                          (declared-Literal (Integer 1) loc))
                                         loc))
                    loc)
                   (list)
                   loc))))))
   (else)))
