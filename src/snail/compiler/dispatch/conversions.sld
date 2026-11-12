;; The code that recovers a typed value from Any, and the code that fails a
;; dispatch with a CastError, as the old compiler's `recover-value`
;; (src/snail/shell/compiler/dynamic.sld) and `conversion-error` and
;; `conversion-failure` (src/snail/shell/compiler/conversions.sld) write
;; them, and `recover-pair` the recovery of two. A dispatch clause's methods
;; and a generated instance's are made of these, every node at the place
;; handed in.
;;
;;   (match (try-convert value target)       ; a recovery
;;     ((Ok local) success)
;;     (_ failure))
;;
;;   (match (Pair (try-convert left L)       ; a recovery of two at once
;;                (try-convert right R))
;;     ((Pair (Ok left1) (Ok right1)) success)
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
   recovered-both
   cast-failure)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler names globals) Local Global TopGlobal)
   (only (snail compiler literals constant) Integer Text)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler builtins base)
         any-type-id-primitive
         ok-case
         pair-case
         cons-case
         nil-case
         cast-error-case
         argument-mismatch-case
         conversion-failed-operation)
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
                      (list (declared-Clause (ok-pattern local loc) success loc)
                            (declared-Clause (declared-Wild loc) failure loc))
                      loc))

    ;; `success` with `left-local` and `right-local` bound to the values
    ;; `left` and `right` hold as a `left-target` and a `right-target`,
    ;; when both do, and else `failure`.
    (: recovered-both
       (impl (Fn declared-Expr declared-Type Local declared-Expr declared-Type Local declared-Expr
                 declared-Expr Loc
                 -> declared-Expr)))
    (define (recovered-both left
                            left-target
                            left-local
                            right
                            right-target
                            right-local
                            success
                            failure
                            loc)
      (declared-Match (called pair-case
                              (list (declared-TryConvert left left-target loc)
                                    (declared-TryConvert right right-target loc))
                              loc)
                      (list (declared-Clause (declared-Destructure (TopGlobal pair-case)
                                                                   (list (ok-pattern left-local loc)
                                                                         (ok-pattern right-local
                                                                                     loc))
                                                                   loc)
                                             success
                                             loc)
                            (declared-Clause (declared-Wild loc) failure loc))
                      loc))

    (: ok-pattern (impl (Fn Local Loc -> declared-Pattern)))
    (define (ok-pattern local loc)
      (declared-Destructure (TopGlobal ok-case) (list (declared-Bind local loc)) loc))

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
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-conversions)
        (test-recovered)
        (test-both)
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

      ;; Read off `recover-pair`: one Pair of two tries, matched at once.
      (define (test-both)
        (let ((right (declared-LocalRef (Local "argument" 2) loc))
              (f64 (declared-Con (Global forms-library "F64" 0) (list)))
              (ok (lambda (number)
                    (declared-Destructure (TopGlobal ok-case)
                                          (list (declared-Bind (Local "case" number) loc))
                                          loc))))
          (expect
           (recovered-both value i64 (Local "case" 3) right f64 (Local "case" 4) value right loc)
           (declared-Match (declared-Call (top pair-case)
                                          (list (declared-TryConvert value i64 loc)
                                                (declared-TryConvert right f64 loc))
                                          loc)
                           (list (declared-Clause (declared-Destructure (TopGlobal pair-case)
                                                                        (list (ok 3) (ok 4))
                                                                        loc)
                                                  value
                                                  loc)
                                 (declared-Clause (declared-Wild loc) right loc))
                           loc))))

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
