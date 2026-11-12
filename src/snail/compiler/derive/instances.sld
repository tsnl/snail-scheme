;; The instances `derive` writes, built as nodes: for a type that derives
;; Serialize or Deserialize, the declaration and the method body the old
;; expander writes as syntax and expands. Each node is the core form that
;; syntax expands to, so the instance is the old one up to the names of
;; its locals, which are numbered here. The names an instance is written
;; with come from the implicit libraries; one that they do not offer as
;; needed is a problem of the instance's head or of its body, in the
;; order the old expander finds it: the class as it declares the instance,
;; then each name of the body as it expands the body, the first that is
;; missing ending the body. An instance's locals are numbered from the
;; library's Numbering, and one that is a problem numbers none.
(define-library (snail compiler derive instances)
  (export
   DerivedType
   Constructor
   Problem
   HeadProblem
   BodyProblem
   serialize-instance
   deserialize-instance)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (only (snail compiler names globals) Local Global TopValue TopGlobal ClassGlobal Label)
   (only (snail compiler literals constant) Text)
   (only (snail compiler names numbering) Numbering fresh-local)
   (prefix (snail compiler bind language) bound-)
   (snail compiler derive implicit))
  (begin

    ;; ---- What is derived ----

    ;; A struct or enum that derives an instance: its type and parameters,
    ;; its constructors in order, and the place of its declaration.
    (struct DerivedType
      ((type Global)
       (parameters (List String))
       (constructors (List Constructor))
       (loc Loc)))

    ;; A case's constructor, or a struct's, how many fields it takes, and
    ;; where its name is written.
    (struct Constructor
      ((global Global)
       (arity I64)
       (loc Loc)))

    ;; A problem the old expander finds as it declares the instance, which
    ;; ends the library's declarations, or as it expands the method's
    ;; body, which ends only that body.
    (enum Problem
      (HeadProblem
       ((feedback Feedback)))
      (BodyProblem
       ((feedback (List Feedback)))))

    ;; ---- Serialize ----

    ;; Each case writes its TypeId, then its fields in order:
    ;;
    ;;   (define (encode value encoder)
    ;;     (match value
    ;;       ((C field0 ...)
    ;;        (encode-case-id encoder (case-id C)) (encode field0 encoder) ... (unit))
    ;;       ...))
    ;;
    ;; `value` and `encoder` are numbered first, then each case's fields;
    ;; the answer holds the numbering they leave.
    (: serialize-instance
       (impl (Fn WireNames DerivedType Numbering
                 -> (Result (Pair bound-Instance Numbering) Problem))))
    (define (serialize-instance names derived numbering)
      (let ((loc (::loc derived)))
        (state-let* ((value numbering (fresh-local numbering "value"))
                     (encoder numbering (fresh-local numbering "encoder"))
                     (cases numbering (numbered-cases numbering (::constructors derived))))
          (instance-result (::serialize names)
                           derived
                           (result-let* ((clauses (map-results (lambda (case)
                                                                 (serialize-clause names
                                                                                   case
                                                                                   encoder
                                                                                   loc))
                                                               cases)))
                             (Ok (method "encode"
                                         (list value encoder)
                                         (bound-Match (reference value loc) clauses loc)
                                         loc)))
                           numbering))))

    (: serialize-clause
       (impl
        (Fn WireNames NumberedCase Local Loc -> (Result bound-Clause (List Feedback)))))
    (define (serialize-clause names case encoder loc)
      (result-let* ((encode-case-id (placed loc (::encode-case-id names)))
                    (encodes (map-results (lambda (field)
                                            (result-let* ((encode (placed loc (::encode names))))
                                              (Ok (call encode
                                                        (list (reference field loc)
                                                              (reference encoder loc))
                                                        loc))))
                                          (::fields case)))
                    (unit (placed loc (::unit names))))
        (Ok (bound-Clause (destructure case loc)
                          (sequence (call encode-case-id
                                          (list (reference encoder loc)
                                                (case-id (::constructor case) loc))
                                          loc)
                                    (append encodes (list (call unit (list) loc)))
                                    loc)
                          loc))))

    ;; ---- Deserialize ----

    ;; The TypeId read selects the case; an unknown one is a schema
    ;; mismatch:
    ;;
    ;;   (define (decode decoder)
    ;;     (let ((id (decode-case-id decoder)))
    ;;       (if (case-id=? id (case-id C))
    ;;           (let ((field0 (decode decoder))) ... (C field0 ...))
    ;;           ...
    ;;           (panic "wire data has a different schema"))))
    ;;
    ;; `decoder` and `id` are numbered first, then each case's fields; the
    ;; answer holds the numbering they leave.
    (: deserialize-instance
       (impl (Fn WireNames DerivedType Numbering
                 -> (Result (Pair bound-Instance Numbering) Problem))))
    (define (deserialize-instance names derived numbering)
      (let ((loc (::loc derived)))
        (state-let* ((decoder numbering (fresh-local numbering "decoder"))
                     (id numbering (fresh-local numbering "id"))
                     (cases numbering (numbered-cases numbering (::constructors derived))))
          (instance-result (::deserialize names)
                           derived
                           (result-let* ((decode-case-id (placed loc (::decode-case-id names)))
                                         (chosen (chosen-case names cases id decoder loc)))
                             (Ok (method "decode"
                                         (list decoder)
                                         (bound-Let id
                                                    (None)
                                                    (call decode-case-id
                                                          (list (reference decoder loc))
                                                          loc)
                                                    chosen
                                                    loc)
                                         loc)))
                           numbering))))

    ;; The case whose TypeId is `id`'s, decoded, tested in order; after the
    ;; last, the mismatch.
    (: chosen-case
       (impl (Fn WireNames (List NumberedCase) Local Local Loc
                 -> (Result bound-Expr (List Feedback)))))
    (define (chosen-case names cases id decoder loc)
      (match cases
        ((Nil)
         (result-let* ((panic (placed loc (::panic names))))
           (Ok (call panic
                     (list (bound-Literal (Text "wire data has a different schema") loc))
                     loc))))
        ((Cons case rest)
         (result-let* ((equal (placed loc (::case-id-equal names)))
                       (decoded (decoded-case names case decoder loc))
                       (otherwise (chosen-case names rest id decoder loc)))
           (Ok (bound-If (call equal
                               (list (reference id loc) (case-id (::constructor case) loc))
                               loc)
                         decoded
                         otherwise
                         loc))))))

    ;; Each field decoded in order, then the case built of them.
    (: decoded-case
       (impl (Fn WireNames NumberedCase Local Loc -> (Result bound-Expr (List Feedback)))))
    (define (decoded-case names case decoder loc)
      (let loop ((fields (::fields case)))
        (match fields
          ((Nil)
           (Ok (bound-Call (constructor-reference (::constructor case))
                           (map (lambda (field) (reference field loc)) (::fields case))
                           loc)))
          ((Cons field rest)
           (result-let* ((decode (placed loc (::decode names)))
                         (body (loop rest)))
             (Ok (bound-Let field
                            (None)
                            (call decode (list (reference decoder loc)) loc)
                            body
                            loc)))))))

    ;; ---- Instances ----

    ;; The instance of `class` for the type, with its method, once its
    ;; head's class and then its body are found.
    (: instance-result
       (impl (Fn (Result Global String)
                 DerivedType
                 (Result bound-InstanceMethod (List Feedback))
                 Numbering
                 ->
                 (Result (Pair bound-Instance Numbering) Problem))))
    (define (instance-result class derived method numbering)
      (match class
        ((Err message) (Err (HeadProblem (Feedback (::loc derived) message))))
        ((Ok global)
         (match method
           ((Err feedback) (Err (BodyProblem feedback)))
           ((Ok found) (Ok (Pair (instance-of global derived found) numbering)))))))

    ;; `(instance (Class (Type parameter ...)) (requires (Class parameter)
    ;; ...) method)`, its variables the type's parameters.
    (: instance-of (impl (Fn Global DerivedType bound-InstanceMethod -> bound-Instance)))
    (define (instance-of class derived method)
      (let* ((loc (::loc derived))
             (class-ref (ClassGlobal class))
             (variables (map (lambda (parameter) (expanded-Variable parameter loc))
                             (::parameters derived))))
        (bound-Instance class-ref
                        (::parameters derived)
                        (list (expanded-Applied (::type derived)
                                                (::name (::type derived))
                                                variables
                                                loc))
                        (map (lambda (variable)
                               (expanded-ClassRequirement class-ref (list variable) (list) loc))
                             variables)
                        (list)
                        (bound-Methods (list method))
                        loc)))

    ;; `(define (label parameter ...) body)`.
    (: method
       (impl (Fn String (List Local) bound-Expr Loc -> bound-InstanceMethod)))
    (define (method label parameters body loc)
      (bound-InstanceMethod (expanded-MemberName (Label label loc))
                            (bound-Lambda parameters body loc)))

    ;; ---- Cases ----

    ;; A constructor with a local of its own for each field, `field0` and
    ;; on.
    (struct NumberedCase
      ((constructor Constructor)
       (fields (List Local))))

    ;; Each constructor's fields numbered in turn.
    (: numbered-cases
       (impl (Fn Numbering (List Constructor) -> (Pair (List NumberedCase) Numbering))))
    (define (numbered-cases numbering constructors)
      (map-with-state numbering numbered-case constructors))

    (: numbered-case (impl (Fn Numbering Constructor -> (Pair NumberedCase Numbering))))
    (define (numbered-case numbering constructor)
      (state-let* ((fields numbering
                           (map-with-state numbering
                                           (lambda (numbering index)
                                             (fresh-local numbering
                                                          (string-append "field"
                                                                         (i64->string index))))
                                           (iota (::arity constructor)))))
        (Pair (NumberedCase constructor fields) numbering)))

    ;; `(C field0 ...)` as a pattern, at the constructor.
    (: destructure (impl (Fn NumberedCase Loc -> bound-Pattern)))
    (define (destructure case loc)
      (let ((constructor (::constructor case)))
        (bound-Destructure (TopGlobal (::global constructor))
                           (map (lambda (field) (bound-Bind field loc)) (::fields case))
                           (::loc constructor))))

    (: case-id (impl (Fn Constructor Loc -> bound-Expr)))
    (define (case-id constructor loc)
      (bound-CaseId (TopGlobal (::global constructor)) (::loc constructor) loc))

    (: constructor-reference (impl (Fn Constructor -> bound-Expr)))
    (define (constructor-reference constructor)
      (bound-TopRef (TopGlobal (::global constructor)) (::loc constructor)))

    ;; ---- Expressions ----

    ;; A name the implicit libraries offer, or the problem its absence is,
    ;; at the instance.
    (: placed (All (T) (impl (Fn Loc (Result T String) -> (Result T (List Feedback))))))
    (define (placed loc found)
      (match found
        ((Ok value) (Ok value))
        ((Err message) (fail loc message))))

    (: call (impl (Fn TopValue (List bound-Expr) Loc -> bound-Expr)))
    (define (call function arguments loc)
      (bound-Call (bound-TopRef function loc) arguments loc))

    (: reference (impl (Fn Local Loc -> bound-Expr)))
    (define (reference local loc)
      (bound-LocalRef local loc))

    ;; A body of expressions in order, as `expand` writes one: each but
    ;; the last done before the rest, at the first, which is at `loc`.
    (: sequence (impl (Fn bound-Expr (List bound-Expr) Loc -> bound-Expr)))
    (define (sequence first rest loc)
      (match rest
        ((Nil) first)
        ((Cons next more) (bound-Seq first (sequence next more loc) loc))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-instances)
    (import
     (snail stage0 testing))
    (begin
      (define (test-instances)
        (test-serialize)
        (test-deserialize)
        (test-problems))

      (define loc (Loc "a.sld" 1 1))

      (define (at column)
        (Loc "a.sld" 1 column))

      (define wire (list "snail" "shell" "wire"))

      (define (wire-global name)
        (Global wire name 0))

      (define (wire-value name)
        (Ok (TopGlobal (wire-global name))))

      (define names
        (WireNames (Ok (wire-global "Serialize"))
                   (Ok (wire-global "Deserialize"))
                   (wire-value "encode")
                   (wire-value "decode")
                   (wire-value "encode-case-id")
                   (wire-value "decode-case-id")
                   (wire-value "case-id=?")
                   (Ok (TopGlobal (Global (list "prim") "unit" 0)))
                   (Ok (TopGlobal (Global (list "prim") "panic" 0)))))

      (define a (list "a"))

      (define (numbered next)
        (Numbering a next))

      ;; (enum (Shape T) (Dot) (Pair x y)), the first case's name at column
      ;; 5 and the second's at 9.
      (define shape
        (DerivedType (Global a "Shape" 0)
                     (list "T")
                     (list (Constructor (Global a "Dot" 0) 0 (at 5))
                           (Constructor (Global a "Pair" 0) 2 (at 9)))
                     loc))

      (define (local name number)
        (Local name number))

      (define (ref name number)
        (bound-LocalRef (local name number) loc))

      (define (top value)
        (bound-TopRef (match value
                        ((Ok found) found)
                        ((Err _) (panic "a test name")))
                      loc))

      (define (wire-call name arguments)
        (bound-Call (top (wire-value name)) arguments loc))

      (define (case-of name column)
        (bound-CaseId (TopGlobal (Global a name 0)) (at column) loc))

      (define (head class body)
        (bound-Instance (ClassGlobal (wire-global class))
                        (list "T")
                        (list (expanded-Applied (Global a "Shape" 0)
                                                "Shape"
                                                (list (expanded-Variable "T" loc))
                                                loc))
                        (list (expanded-ClassRequirement (ClassGlobal (wire-global class))
                                                         (list (expanded-Variable "T" loc))
                                                         (list)
                                                         loc))
                        (list)
                        (bound-Methods (list body))
                        loc))

      ;; Each case writes its TypeId and its fields; locals from 7.
      (define (test-serialize)
        (let ((unit-call (bound-Call (top (::unit names)) (list) loc)))
          (expect
           (serialize-instance names shape (numbered 7))
           (Ok
            (Pair
             (head "Serialize"
                   (bound-InstanceMethod
                    (expanded-MemberName (Label "encode" loc))
                    (bound-Lambda
                     (list (local "value" 7) (local "encoder" 8))
                     (bound-Match
                      (ref "value" 7)
                      (list (bound-Clause
                             (bound-Destructure (TopGlobal (Global a "Dot" 0))
                                                (list)
                                                (at 5))
                             (bound-Seq (wire-call "encode-case-id"
                                                   (list (ref "encoder" 8) (case-of "Dot" 5)))
                                        unit-call
                                        loc)
                             loc)
                            (bound-Clause
                             (bound-Destructure (TopGlobal (Global a "Pair" 0))
                                                (list (bound-Bind (local "field0" 9) loc)
                                                      (bound-Bind (local "field1" 10) loc))
                                                (at 9))
                             (bound-Seq
                              (wire-call "encode-case-id"
                                         (list (ref "encoder" 8) (case-of "Pair" 9)))
                              (bound-Seq
                               (wire-call "encode" (list (ref "field0" 9) (ref "encoder" 8)))
                               (bound-Seq (wire-call "encode"
                                                     (list (ref "field1" 10)
                                                           (ref "encoder" 8)))
                                          unit-call
                                          loc)
                               loc)
                              loc)
                             loc))
                      loc)
                     loc)))
             (numbered 11))))))

      ;; The TypeId read selects the case, whose fields are decoded in
      ;; order; locals from 3.
      (define (test-deserialize)
        (let ((decode (wire-call "decode" (list (ref "decoder" 3)))))
          (expect
           (deserialize-instance names shape (numbered 3))
           (Ok
            (Pair
             (head "Deserialize"
                   (bound-InstanceMethod
                    (expanded-MemberName (Label "decode" loc))
                    (bound-Lambda
                     (list (local "decoder" 3))
                     (bound-Let
                      (local "id" 4)
                      (None)
                      (wire-call "decode-case-id" (list (ref "decoder" 3)))
                      (bound-If
                       (wire-call "case-id=?" (list (ref "id" 4) (case-of "Dot" 5)))
                       (bound-Call (bound-TopRef (TopGlobal (Global a "Dot" 0))
                                                 (at 5))
                                   (list)
                                   loc)
                       (bound-If
                        (wire-call "case-id=?" (list (ref "id" 4) (case-of "Pair" 9)))
                        (bound-Let
                         (local "field0" 5)
                         (None)
                         decode
                         (bound-Let (local "field1" 6)
                                    (None)
                                    decode
                                    (bound-Call (bound-TopRef (TopGlobal
                                                               (Global a "Pair" 0))
                                                              (at 9))
                                                (list (ref "field0" 5) (ref "field1" 6))
                                                loc)
                                    loc)
                         loc)
                        (bound-Call (top (::panic names))
                                    (list (bound-Literal (Text
                                                          "wire data has a different schema")
                                                         loc))
                                    loc)
                        loc)
                       loc)
                      loc)
                     loc)))
             (numbered 7))))))

      ;; A missing class is the head's problem; a missing name the body's,
      ;; the first the body uses. A name no body uses is never asked for.
      (define (test-problems)
        (let ((without (lambda (names field)
                         (WireNames (if (string=? field "Serialize")
                                        (Err "no class")
                                        (::serialize names))
                                    (::deserialize names)
                                    (if (string=? field "encode")
                                        (Err "no encode")
                                        (::encode names))
                                    (::decode names)
                                    (::encode-case-id names)
                                    (if (string=? field "decode-case-id")
                                        (Err "no decode-case-id")
                                        (::decode-case-id names))
                                    (::case-id-equal names)
                                    (if (string=? field "unit") (Err "no unit") (::unit names))
                                    (::panic names)))))
          (expect (serialize-instance (without names "Serialize") shape (numbered 0))
                  (Err (HeadProblem (Feedback loc "no class"))))
          (expect (serialize-instance (without names "encode") shape (numbered 0))
                  (Err (BodyProblem (list (Feedback loc "no encode")))))
          (expect (serialize-instance (without names "unit") shape (numbered 0))
                  (Err (BodyProblem (list (Feedback loc "no unit")))))
          (expect (deserialize-instance (without names "decode-case-id") shape (numbered 0))
                  (Err (BodyProblem (list (Feedback loc "no decode-case-id")))))
          (expect (serialize-instance (without names "encode")
                                      (DerivedType (Global a "Unit" 0)
                                                   (list)
                                                   (list (Constructor (Global a "Unit" 0)
                                                                      0
                                                                      (at 3)))
                                                   loc)
                                      (numbered 0))
                  (Ok (Pair (bound-Instance
                             (ClassGlobal (wire-global "Serialize"))
                             (list)
                             (list
                              (expanded-Applied (Global a "Unit" 0) "Unit" (list) loc))
                             (list)
                             (list)
                             (bound-Methods
                              (list (bound-InstanceMethod
                                     (expanded-MemberName (Label "encode" loc))
                                     (bound-Lambda
                                      (list (local "value" 0) (local "encoder" 1))
                                      (bound-Match
                                       (ref "value" 0)
                                       (list (bound-Clause
                                              (bound-Destructure (TopGlobal
                                                                  (Global a "Unit" 0))
                                                                 (list)
                                                                 (at 3))
                                              (bound-Seq (wire-call "encode-case-id"
                                                                    (list (ref "encoder" 1)
                                                                          (bound-CaseId
                                                                           (TopGlobal
                                                                            (Global a
                                                                                    "Unit"
                                                                                    0))
                                                                           (at 3)
                                                                           loc)))
                                                         (bound-Call (top (::unit names))
                                                                     (list)
                                                                     loc)
                                                         loc)
                                              loc))
                                       loc)
                                      loc))))
                             loc)
                            (numbered 2))))))))
   (else)))
