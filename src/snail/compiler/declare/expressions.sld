;; Expressions: a body of the derived library becomes Declared's, once
;; every declaration of the library is reached, so whatever a body names
;; is known. The first problem stops the body, in the order the old
;; compiler expands it (src/snail/shell/compiler/expand.sld), which is the
;; order written but that:
;;
;; - a type an expression writes, in `ann`, `convert`, `try-convert` and
;;   `type-test`, is converted after the expression, where no requirement
;;   is in scope;
;; - a local signature is converted where it is written, before the
;;   definition it annotates and the body after it; one that annotates no
;;   definition is then dropped;
;; - a handler's clause names an operation of the handler's effect before
;;   its value is converted;
;; - a match clause's pattern comes before its body, a constructor before
;;   the patterns it is given;
;; - a `case-id` names a constructor, refused where the constructor is
;;   written, and is then its case and the case's TypeId.
;;
;; A reference to a replacer, a pattern's constructor and a `case-id`'s
;; are refused where they are written when their type has a Drop instance
;; and another library (`owned`).
(define-library (snail compiler declare expressions)
  (export
   declared-expr)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (only (snail compiler names globals) TopValue TopGlobal FieldFunction)
   (prefix (snail compiler bind language) bound-)
   (snail compiler declare language)
   (snail compiler declare known)
   (only (snail compiler declare state) checked)
   (snail compiler declare owned)
   (snail compiler declare members)
   (snail compiler declare identities)
   (snail compiler declare types))
  (begin

    ;; ---- Expressions ----

    (: declared-expr (impl (Fn Known bound-Expr -> (Result Expr (List Feedback)))))
    (define (declared-expr known expr)
      (match expr
        ((bound-Literal constant loc) (Ok (Literal constant loc)))
        ((bound-LocalRef local loc) (Ok (LocalRef local loc)))
        ((bound-TopRef value loc)
         (result-let* ((owned (checked (reference-problem known value) loc)))
           (Ok (TopRef value loc))))
        ((bound-Path labels loc) (Ok (Path labels loc)))
        ((bound-PathApply labels record loc)
         (result-let* ((declared (declared-expr known record)))
           (Ok (PathApply labels declared loc))))
        ((bound-Lambda parameters body loc)
         (result-let* ((declared (declared-expr known body)))
           (Ok (Lambda parameters declared loc))))
        ((bound-ClosedLambda parameters body loc)
         (result-let* ((declared (declared-expr known body)))
           (Ok (ClosedLambda parameters declared loc))))
        ((bound-Call callee arguments loc)
         (result-let* ((function (declared-expr known callee))
                       (values (declared-exprs known arguments)))
           (Ok (Call function values loc))))
        ((bound-If test consequent alternative loc)
         (result-let* ((condition (declared-expr known test))
                       (then (declared-expr known consequent))
                       (otherwise (declared-expr known alternative)))
           (Ok (If condition then otherwise loc))))
        ((bound-Seq first rest loc)
         (result-let* ((before (declared-expr known first))
                       (after (declared-expr known rest)))
           (Ok (Seq before after loc))))
        ((bound-Let local signature value body loc)
         (result-let* ((scheme (local-scheme known signature))
                       (bound (declared-expr known value))
                       (inside (declared-expr known body)))
           (Ok (Let local scheme bound inside loc))))
        ((bound-LocalSignature scheme body _)
         (result-let* ((checked (declared-scheme (Scope known (Nil)) scheme)))
           (declared-expr known body)))
        ((bound-Match scrutinee clauses loc)
         (result-let* ((value (declared-expr known scrutinee))
                       (declared (map-results (lambda (clause) (declared-clause known clause))
                                              clauses)))
           (Ok (Match value declared loc))))
        ((bound-Handle effect implementations body loc)
         (let ((operations (effect-operations known effect)))
           (result-let* ((declared (map-results (lambda (implementation)
                                                  (declared-implementation known
                                                                           operations
                                                                           implementation))
                                                implementations))
                         (inside (declared-expr known body)))
             (Ok (Handle effect declared inside loc)))))
        ((bound-WithInstances sets body loc)
         (result-let* ((inside (declared-expr known body)))
           (Ok (WithInstances sets inside loc))))
        ((bound-Ann value type loc)
         (result-let* ((pair (typed known value type)))
           (Ok (Ann (::first pair) (::second pair) loc))))
        ((bound-Convert value type loc)
         (result-let* ((pair (typed known value type)))
           (Ok (Convert (::first pair) (::second pair) loc))))
        ((bound-TryConvert value type loc)
         (result-let* ((pair (typed known value type)))
           (Ok (TryConvert (::first pair) (::second pair) loc))))
        ((bound-TypeTest value type loc)
         (result-let* ((pair (typed known value type)))
           (Ok (TypeTest (::first pair) (::second pair) loc))))
        ((bound-CaseId constructor constructor-loc loc)
         (case-id known constructor constructor-loc loc))))

    (: declared-exprs (impl (Fn Known (List bound-Expr) -> (Result (List Expr) (List Feedback)))))
    (define (declared-exprs known exprs)
      (map-results (lambda (expr) (declared-expr known expr)) exprs))

    ;; An expression, then the type written beside it.
    (: typed
       (impl (Fn Known bound-Expr expanded-TypeExpr -> (Result (Pair Expr Type) (List Feedback)))))
    (define (typed known value type)
      (result-let* ((declared (declared-expr known value))
                    (converted (declared-type (Scope known (Nil)) type)))
        (Ok (Pair declared converted))))

    (: local-scheme
       (impl (Fn Known (Option expanded-Scheme) -> (Result (Option Scheme) (List Feedback)))))
    (define (local-scheme known signature)
      (match signature
        ((Some scheme)
         (result-let* ((declared (declared-scheme (Scope known (Nil)) scheme)))
           (Ok (Some declared))))
        ((None) (Ok (None)))))

    ;; ---- Clauses ----

    (: declared-clause (impl (Fn Known bound-Clause -> (Result Clause (List Feedback)))))
    (define (declared-clause known clause)
      (result-let* ((pattern (declared-pattern known (::pattern clause)))
                    (body (declared-expr known (::body clause))))
        (Ok (Clause pattern body (::loc clause)))))

    ;; A pattern holds no type, so it is as written, once each constructor
    ;; may take its value apart here.
    (: declared-pattern (impl (Fn Known bound-Pattern -> (Result Pattern (List Feedback)))))
    (define (declared-pattern known pattern)
      (match pattern
        ((bound-Wild loc) (Ok (Wild loc)))
        ((bound-Bind local loc) (Ok (Bind local loc)))
        ((bound-Equals datum loc) (Ok (Equals datum loc)))
        ((bound-Destructure constructor arguments loc)
         (result-let* ((owned (checked (destructure-problem known constructor) loc))
                       (parts (map-results (lambda (argument) (declared-pattern known argument))
                                           arguments)))
           (Ok (Destructure constructor parts loc))))))

    ;; A clause's operation, refused at its label, then its value.
    (: declared-implementation
       (impl (Fn Known
                 (List Operation)
                 bound-Implementation
                 ->
                 (Result Implementation (List Feedback)))))
    (define (declared-implementation known operations implementation)
      (let ((label (::label implementation)))
        (match (named-operation operations (::name label))
          ((Ok operation)
           (result-let* ((value (declared-expr known (::value implementation))))
             (Ok (Implementation (::global operation) value (::loc implementation)))))
          ((Err message) (fail (::loc label) message)))))

    ;; ---- Case identities ----

    ;; The case a constructor makes, and its TypeId, which the wire format
    ;; writes before the case's fields.
    (: case-id (impl (Fn Known TopValue Loc Loc -> (Result Expr (List Feedback)))))
    (define (case-id known constructor constructor-loc loc)
      (match (constructed-case known constructor)
        ((Some found)
         (result-let* ((owned (checked (destructure-problem known constructor) constructor-loc)))
           (Ok (CaseId (::global (::second found))
                       (case-type-id known (::first found) (::second found))
                       loc))))
        ((None) (fail constructor-loc "not a constructor"))))

    (: constructed-case (impl (Fn Known TopValue -> (Option (Pair Data DataCase)))))
    (define (constructed-case known value)
      (match value
        ((TopGlobal global) (constructor-case known global))
        ((FieldFunction _ _ _) (None))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-expressions)
    (import
     (snail core table)
     (only (snail compiler names globals) Local Global Accessor Replacer Label)
     (only (snail compiler literals constant) UnitValue)
     (snail compiler declare offer)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-expressions)
        (test-order)
        (test-signatures)
        (test-handlers)
        (test-case-ids)
        (test-owned-uses))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))

      (define (global name)
        (Global main name 0))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      (define (i64-at line)
        (expanded-Applied (Global forms-library "I64" 0) "I64" (list) (at line)))

      (define (arity-wrong line)
        (expanded-Applied (Global forms-library "Array" 0) "Array" (list) (at line)))

      (define (unit-at line)
        (bound-Literal (UnitValue) (at line)))

      (define (local name number)
        (Local name number))

      ;; (main) declares (Point) with the field x and the effect io with
      ;; the operation read; (owned handle) offers Handle, with a Drop
      ;; instance.
      (define point
        (Data (global "Point")
              (list)
              (list
               (DataCase (global "Point") 0 (list (DataField "x" #f i64 (list) loc)) (list) loc))
              (StructData)
              #f
              #f
              (list)
              loc))

      (define read-op (Operation (global "read") #f (list) i64 (list) (list) loc))

      (define handle (Global (list "owned" "handle") "Handle" 0))

      (define handle-data
        (Data handle
              (list)
              (list (DataCase handle 0 (list (DataField "name" #f i64 (list) loc)) (list) loc))
              (StructData)
              #t
              #t
              (list)
              loc))

      (define known
        (Known main
               (Scanned empty-table empty-table)
               (Declarations main
                             (by-name empty-table "Point" point)
                             empty-table
                             (by-name empty-table
                                      "io"
                                      (OfferedEffect (global "io") (list read-op))))
               (list (Declarations (list "owned" "handle")
                                   (by-name empty-table "Handle" handle-data)
                                   empty-table
                                   empty-table))))

      (define (declared expr)
        (declared-expr known expr))

      ;; The callee before its arguments, the condition before its
      ;; branches, an expression before its type.
      (define (test-order)
        (expect (declared (bound-Call (bound-Ann (unit-at 2) (arity-wrong 3) (at 2))
                                      (list (bound-Ann (unit-at 4) (arity-wrong 5) (at 4)))
                                      loc))
                (fail (at 3) "wrong number of type arguments: Array"))
        (expect (declared (bound-If (unit-at 2)
                                    (bound-Convert (unit-at 3) (arity-wrong 4) (at 3))
                                    (bound-TypeTest (unit-at 5) (arity-wrong 6) (at 5))
                                    loc))
                (fail (at 4) "wrong number of type arguments: Array"))
        (expect (declared (bound-TryConvert (unit-at 2) (i64-at 3) loc))
                (Ok (TryConvert (Literal (UnitValue) (at 2)) i64 loc)))
        (expect (declared (bound-Match (unit-at 2)
                                       (list (bound-Clause (bound-Destructure
                                                            (TopGlobal (global "Point"))
                                                            (list (bound-Bind (local "x" 1) loc))
                                                            loc)
                                                           (bound-LocalRef (local "x" 1) loc)
                                                           loc))
                                       loc))
                (Ok (Match (Literal (UnitValue) (at 2))
                           (list (Clause (Destructure (TopGlobal (global "Point"))
                                                      (list (Bind (local "x" 1) loc))
                                                      loc)
                                         (LocalRef (local "x" 1) loc)
                                         loc))
                           loc))))

      ;; A let's signature before its value; one that annotates nothing is
      ;; checked where it is and dropped.
      (define (test-signatures)
        (let ((scheme (lambda (line) (expanded-Scheme (list) (list) (i64-at line) (at line))))
              (bad (lambda (line) (expanded-Scheme (list) (list) (arity-wrong line) (at line)))))
          (expect (declared (bound-Let (local "x" 1)
                                       (Some (scheme 2))
                                       (unit-at 3)
                                       (bound-LocalRef (local "x" 1) (at 4))
                                       loc))
                  (Ok (Let (local "x" 1)
                           (Some (Scheme (list) (list) (list) i64))
                           (Literal (UnitValue) (at 3))
                           (LocalRef (local "x" 1) (at 4))
                           loc)))
          (expect (declared (bound-Let (local "x" 1)
                                       (Some (bad 2))
                                       (bound-Ann (unit-at 3) (arity-wrong 3) (at 3))
                                       (unit-at 4)
                                       loc))
                  (fail (at 2) "wrong number of type arguments: Array"))
          (expect (declared (bound-LocalSignature (scheme 2) (unit-at 3) loc))
                  (Ok (Literal (UnitValue) (at 3))))
          (expect (declared (bound-LocalSignature (bad 2) (unit-at 3) loc))
                  (fail (at 2) "wrong number of type arguments: Array"))))

      ;; A clause's label names an operation before its value is looked at.
      (define (test-handlers)
        (let ((clause (lambda (name line value)
                        (bound-Implementation (Label name (at line)) value (at line)))))
          (expect (declared (bound-Handle (global "io")
                                          (list (clause "read" 2 (unit-at 2)))
                                          (unit-at 3)
                                          loc))
                  (Ok (Handle (global "io")
                              (list (Implementation (global "read")
                                                    (Literal (UnitValue) (at 2))
                                                    (at 2)))
                              (Literal (UnitValue) (at 3))
                              loc)))
          (expect (declared (bound-Handle (global "io")
                                          (list (clause "write"
                                                        2
                                                        (bound-Ann (unit-at 2)
                                                                   (arity-wrong 2)
                                                                   (at 2))))
                                          (unit-at 3)
                                          loc))
                  (fail (at 2) "not an operation of this effect: write"))))

      ;; A constructor's case and its TypeId; anything else is refused where
      ;; it is written.
      (define (test-case-ids)
        (expect (declared (bound-CaseId (TopGlobal (global "Point")) (at 2) loc))
                (Ok (CaseId (global "Point")
                            (case-type-id known point (list-ref (::cases point) 0))
                            loc)))
        (expect (declared (bound-CaseId (TopGlobal (global "read")) (at 2) loc))
                (fail (at 2) "not a constructor"))
        (expect
         (declared (bound-CaseId (FieldFunction (global "Point") "x" (Accessor))
                                 (at 3)
                                 loc))
         (fail (at 3) "not a constructor"))
        (expect (declared (bound-CaseId (TopGlobal handle) (at 2) loc))
                (fail (at 2) take-apart)))

      (define take-apart
        "Handle has a Drop instance, so only its own library can take it apart; drop it instead")

      (define (handle-pattern line arguments)
        (bound-Destructure (TopGlobal handle) arguments (at line)))

      (define (clause pattern body)
        (bound-Clause pattern body loc))

      ;; A Handle taken apart, or its field replaced, outside its library
      ;; (error-drop-match.sld and error-replace-owned.sld): a clause's
      ;; pattern before its body, but after the clauses before it; a
      ;; constructor before the patterns it is given; a callee before its
      ;; arguments.
      (define (test-owned-uses)
        (let ((bad-body (bound-Ann (unit-at 4) (arity-wrong 4) (at 4))))
          (expect (declared (bound-Match (unit-at 2)
                                         (list (clause (handle-pattern 3 (list (bound-Wild loc)))
                                                       bad-body))
                                         loc))
                  (fail (at 3) take-apart))
          (expect (declared (bound-Match (unit-at 2)
                                         (list (clause (bound-Wild loc) bad-body)
                                               (clause (handle-pattern 5 (list)) (unit-at 6)))
                                         loc))
                  (fail (at 4) "wrong number of type arguments: Array"))
          (expect (declared (bound-Match (unit-at 2)
                                         (list (clause (bound-Destructure
                                                        (TopGlobal (global "Point"))
                                                        (list (handle-pattern 5 (list)))
                                                        (at 3))
                                                       (unit-at 6)))
                                         loc))
                  (fail (at 5) take-apart))
          (expect (declared (bound-Match (unit-at 2)
                                         (list (clause
                                                (handle-pattern 3 (list (handle-pattern 5 (list))))
                                                (unit-at 6)))
                                         loc))
                  (fail (at 3) take-apart))
          (expect (declared (bound-Call (bound-TopRef (FieldFunction handle
                                                                     "name"
                                                                     (Replacer))
                                                      (at 2))
                                        (list bad-body)
                                        loc))
                  (fail (at 2)
                        "Handle has a Drop instance, so only its own library can replace its fields"))
          (expect (declared (bound-TopRef (FieldFunction handle "name" (Accessor))
                                          (at 2)))
                  (Ok
                   (TopRef (FieldFunction handle "name" (Accessor)) (at 2))))))))
   (else)))
