;; The shape of each top-level form and of the declarations it holds:
;; which items a form has where, as the old expander takes them apart,
;; and what to say of one that is malformed, and where, which the part
;; places. Their words, `annotations`, `doc`, `deriving`, `mut`, `ctl`,
;; `requires`, `dispatch`, `dynamic-instances`, `default`, `around-main`,
;; `dynamic`, `:` and `type` among a declaration's items, are known by
;; name, whatever binds them, as the old expander knows them; a form's
;; head keyword is resolved by the part, which then asks here.
(define-library (snail compiler expand declaration-shapes)
  (export
   Malformed
   Named
   named
   items-of
   form-tail
   AnnotatedForm
   annotation-arity
   split-annotations
   declaration-head
   declared-name
   declared-params
   struct-fields
   enum-cases
   FieldForm
   field-form
   CaseForm
   case-form
   derived-classes
   derivation
   alias-body
   associated-form?
   associated-name
   method-form
   effect-operations
   OperationForm
   operation-form
   EffectForm
   effect-form
   default-clauses
   around-main?
   default-entries
   DefaultForm
   default-entry
   InstanceForm
   instance-form
   InstanceMembers
   instance-members
   dispatch-types
   dynamic-instances-form
   DynamicForm
   pair-types
   ExternForm
   extern-form
   ExposeForm
   expose-form
   dynamic-flag
   ScopeForm
   with-instances-form
   SetForm
   instance-set-form
   dynamic-instances?
   PrimitiveForm
   primitive-form
   callable-once?)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (snail compiler expand language)
   (snail compiler expand marked)
   (only (snail compiler expand scopes) marked-loc))
  (begin

    ;; ---- Answers ----

    ;; What to say of a malformed form, and where.
    (struct Malformed
      ((loc Loc)
       (message String)))

    ;; An identifier where it is written.
    (struct Named
      ((identifier Identifier)
       (loc Loc)))

    ;; The identifier `syntax` is, or "expected `what`" at it.
    (: named (impl (Fn Marked String -> (Result Named Malformed))))
    (define (named syntax what)
      (match syntax
        ((Ident identifier loc) (Ok (Named identifier loc)))
        (_ (Err (Malformed (marked-loc syntax) (string-append "expected " what))))))

    ;; The items of a form, or "expected `what`" at it.
    (: items-of (impl (Fn Marked String -> (Result (List Marked) Malformed))))
    (define (items-of syntax what)
      (match syntax
        ((Form items _) (Ok items))
        (_ (Err (Malformed (marked-loc syntax) (string-append "expected " what))))))

    ;; The items after a form's head.
    (: form-tail (impl (Fn Marked -> (List Marked))))
    (define (form-tail syntax)
      (match syntax
        ((Form (Cons _ rest) _) rest)
        (_ (Nil))))

    (: word? (impl (Fn String Marked -> Bool)))
    (define (word? word syntax)
      (match syntax
        ((Ident identifier _) (string=? (::name identifier) word))
        (_ #f)))

    ;; Whether a form's head is `word`.
    (: headed? (impl (Fn String Marked -> Bool)))
    (define (headed? word syntax)
      (match syntax
        ((Form (Cons head _) _) (word? word head))
        (_ #f)))

    ;; ---- Annotations ----

    ;; A declaration without its annotation list, and the annotations the
    ;; list held.
    (struct AnnotatedForm
      ((form Marked)
       (annotations (List Annotation))))

    ;; How many items a declaration has before its annotation list, for
    ;; the keywords whose declarations may end with one.
    (: annotation-arity (impl (Fn String -> (Option I64))))
    (define (annotation-arity keyword)
      (cond ((member? keyword (list ":" "type" "effect")) (Some 3))
            ((member? keyword (list "struct" "enum" "typeclass")) (Some 2))
            ((string=? keyword "extern") (Some 5))
            (else (None))))

    ;; A form with more than `required` items may end with
    ;; `(annotations entry ...)`, and then only one.
    (: split-annotations (impl (Fn Marked I64 -> (Result AnnotatedForm Malformed))))
    (define (split-annotations form required)
      (match form
        ((Form items loc)
         (if (> (length items) required)
             (match (reverse items)
               ((Cons (Form (Cons head entries) _) rest)
                (if (word? "annotations" head)
                    (annotation-list rest entries required loc)
                    (Ok (AnnotatedForm form (Nil)))))
               (_ (Ok (AnnotatedForm form (Nil)))))
             (Ok (AnnotatedForm form (Nil)))))
        (_ (Ok (AnnotatedForm form (Nil))))))

    ;; `before` is what precedes the list, the latest first.
    (: annotation-list
       (impl (Fn (List Marked) (List Marked) I64 Loc -> (Result AnnotatedForm Malformed))))
    (define (annotation-list before entries required loc)
      (if (and (> (length before) required)
               (match before
                 ((Cons previous _) (headed? "annotations" previous))
                 ((Nil) #f)))
          (Err (Malformed loc "a declaration has at most one annotation list"))
          (result-let* ((annotations (annotations-of entries)))
            (Ok (AnnotatedForm (Form (reverse before) loc) annotations)))))

    (: annotations-of (impl (Fn (List Marked) -> (Result (List Annotation) Malformed))))
    (define (annotations-of entries)
      (match entries
        ((Nil) (Ok (Nil)))
        ((Cons entry rest)
         (result-let* ((first (annotation entry))
                       (more (annotations-of rest)))
           (Ok (Cons first more))))))

    ;; `(doc "text")` is the one annotation.
    (: annotation (impl (Fn Marked -> (Result Annotation Malformed))))
    (define (annotation form)
      (match form
        ((Form (Cons head (Cons (Atom (syntax-Text text) _) (Nil))) loc)
         (if (word? "doc" head) (Ok (Documentation text loc)) (unknown-annotation head loc)))
        ((Form (Cons (Ident identifier _) _) loc)
         (if (string=? (::name identifier) "doc")
             (Err (Malformed loc "doc needs exactly one literal string"))
             (Err (Malformed loc (string-append "unknown annotation: " (::name identifier))))))
        (_
         (Err (Malformed (marked-loc form)
                         "expected an annotation application, such as (doc \"text\")")))))

    (: unknown-annotation (impl (Fn Marked Loc -> (Result Annotation Malformed))))
    (define (unknown-annotation head loc)
      (match head
        ((Ident identifier _)
         (Err (Malformed loc (string-append "unknown annotation: " (::name identifier)))))
        (_ (Err (Malformed loc "expected an annotation application, such as (doc \"text\")")))))

    ;; ---- Declared names ----

    (: declaration-head (impl (Fn Marked -> (Result Marked Malformed))))
    (define (declaration-head form)
      (match (form-tail form)
        ((Cons head _) (Ok head))
        ((Nil) (Err (Malformed (marked-loc form) "expected a declared name")))))

    ;; `Name`, or `(Name parameter ...)`.
    (: declared-name (impl (Fn Marked -> (Result Named Malformed))))
    (define (declared-name head)
      (match head
        ((Form (Cons name _) _) (named name "a type name"))
        (_ (named head "a type name"))))

    (: declared-params (impl (Fn Marked -> (Result (List Named) Malformed))))
    (define (declared-params head)
      (match head
        ((Form (Cons _ params) _) (type-parameters params))
        (_ (Ok (Nil)))))

    (: type-parameters (impl (Fn (List Marked) -> (Result (List Named) Malformed))))
    (define (type-parameters params)
      (match params
        ((Nil) (Ok (Nil)))
        ((Cons param rest)
         (result-let* ((first (named param "a type parameter"))
                       (more (type-parameters rest)))
           (Ok (Cons first more))))))

    ;; ---- Structs and enums ----

    ;; The items after a declaration's head, without its deriving clauses.
    (: declaration-body (impl (Fn Marked -> (List Marked))))
    (define (declaration-body form)
      (match (form-tail form)
        ((Cons _ rest) (filter (lambda (item) (not (headed? "deriving" item))) rest))
        ((Nil) (Nil))))

    (: struct-fields (impl (Fn Marked -> (Result (List Marked) Malformed))))
    (define (struct-fields form)
      (match (declaration-body form)
        ((Nil) (Ok (Nil)))
        ((Cons fields (Nil)) (items-of fields "a field list"))
        (_ (Err (Malformed (marked-loc form) "expected (struct Name ((field type) ...))")))))

    (: enum-cases (impl (Fn Marked -> (List Marked))))
    (define (enum-cases form)
      (declaration-body form))

    ;; `(name type)`, or `(name mut type)` for a mutable field, optionally
    ;; with an annotation list. Its name is checked where it is bound.
    (struct FieldForm
      ((name Marked)
       (mutable? Bool)
       (type Marked)
       (annotations (List Annotation))))

    (: field-form (impl (Fn Marked -> (Result FieldForm Malformed))))
    (define (field-form field)
      (result-let* ((split (split-annotations field (if (mutable-field? field) 3 2))))
        (match (::form split)
          ((Form (Cons name (Cons type (Nil))) _)
           (Ok (FieldForm name #f type (::annotations split))))
          ((Form (Cons name (Cons mut (Cons type (Nil)))) _)
           (if (word? "mut" mut)
               (Ok (FieldForm name #t type (::annotations split)))
               (Err (malformed-field field))))
          (_ (Err (malformed-field field))))))

    (: mutable-field? (impl (Fn Marked -> Bool)))
    (define (mutable-field? field)
      (match field
        ((Form (Cons _ (Cons mut _)) _) (word? "mut" mut))
        (_ #f)))

    (: malformed-field (impl (Fn Marked -> Malformed)))
    (define (malformed-field field)
      (Malformed (marked-loc field)
                 "expected (field type) or (field mut type), optionally with (annotations ...)"))

    ;; `(Case)` or `(Case ((field type) ...))`, optionally with an
    ;; annotation list.
    (struct CaseForm
      ((name Named)
       (fields (List Marked))
       (annotations (List Annotation))))

    (: case-form (impl (Fn Marked -> (Result CaseForm Malformed))))
    (define (case-form case)
      (result-let* ((split (split-annotations case 1)))
        (match (::form split)
          ((Form (Cons name (Nil)) _)
           (result-let* ((case-name (named name "a case name")))
             (Ok (CaseForm case-name (Nil) (::annotations split)))))
          ((Form (Cons name (Cons fields (Nil))) _)
           (result-let* ((case-name (named name "a case name"))
                         (items (items-of fields "a field list")))
             (Ok (CaseForm case-name items (::annotations split)))))
          (_
           (Err (Malformed (marked-loc case)
                           "expected (Case), or (Case ((field type) ...)), optionally with (annotations ...)"))))))

    ;; The classes every `(deriving class ...)` clause names, in order.
    (: derived-classes (impl (Fn Marked -> (List Marked))))
    (define (derived-classes form)
      (concatenate
       (map form-tail (filter (lambda (item) (headed? "deriving" item)) (form-tail form)))))

    (: derivation (impl (Fn Marked -> (Result Derivation Malformed))))
    (define (derivation class)
      (cond ((word? "Move" class) (Ok (DeriveMove (marked-loc class))))
            ((word? "Serialize" class) (Ok (DeriveSerialize (marked-loc class))))
            ((word? "Deserialize" class) (Ok (DeriveDeserialize (marked-loc class))))
            (else
             (Err (Malformed (marked-loc class)
                             "only Move, Serialize and Deserialize can be derived")))))

    ;; ---- Aliases and classes ----

    ;; What `(type Name type)` leaves after its head.
    (: alias-body (impl (Fn (List Marked) Marked -> (Result Marked Malformed))))
    (define (alias-body rest form)
      (match rest
        ((Cons body (Nil)) (Ok body))
        (_ (Err (Malformed (marked-loc form) "expected (type Name type)")))))

    ;; A class's `(type Output)` member, an associated output.
    (: associated-form? (impl (Fn Marked -> Bool)))
    (define (associated-form? form)
      (headed? "type" form))

    (: associated-name (impl (Fn Marked -> (Result Named Malformed))))
    (define (associated-name form)
      (result-let* ((split (split-annotations form 2)))
        (match (::form split)
          ((Form (Cons _ (Cons (Ident identifier loc) (Nil))) _) (Ok (Named identifier loc)))
          (_
           (Err (Malformed (marked-loc form)
                           "expected (type Output); associated types take no parameters"))))))

    ;; A class's `(: method type)` member: its name and its type.
    (: method-form (impl (Fn Marked -> (Option (Pair Marked Marked)))))
    (define (method-form form)
      (match form
        ((Form (Cons colon (Cons method (Cons type (Nil)))) _)
         (if (word? ":" colon) (Some (Pair method type)) (None)))
        (_ (None))))

    ;; ---- Effects ----

    ;; The operations of `(effect Name ((operation type) ...) clause ...)`.
    (: effect-operations (impl (Fn (List Marked) Marked -> (Result (List Marked) Malformed))))
    (define (effect-operations rest form)
      (match rest
        ((Cons operations _) (items-of operations "a list of operations"))
        (_ (Err (Malformed (marked-loc form) "expected (effect Name ((operation type) ...))")))))

    ;; `(name type)`, or `(ctl name type)` for a control operation,
    ;; optionally with an annotation list.
    (struct OperationForm
      ((name Marked)
       (type Marked)
       (control? Bool)
       (annotations (List Annotation))))

    (: operation-form (impl (Fn Marked -> (Result OperationForm Malformed))))
    (define (operation-form operation)
      (result-let* ((split (split-annotations operation (if (headed? "ctl" operation) 3 2))))
        (match (::form split)
          ((Form (Cons ctl (Cons name (Cons type (Nil)))) _)
           (if (word? "ctl" ctl)
               (Ok (OperationForm name type #t (::annotations split)))
               (Err (malformed-operation operation))))
          ((Form (Cons name (Cons type (Nil))) _)
           (Ok (OperationForm name type #f (::annotations split))))
          (_ (Err (malformed-operation operation))))))

    (: malformed-operation (impl (Fn Marked -> Malformed)))
    (define (malformed-operation operation)
      (Malformed (marked-loc operation) "expected (operation type) or (ctl operation type)"))

    ;; An effect's name, operations and the clauses after them.
    (struct EffectForm
      ((name Marked)
       (operations Marked)
       (clauses (List Marked))))

    (: effect-form (impl (Fn Marked -> (Result EffectForm Malformed))))
    (define (effect-form form)
      (match form
        ((Form (Cons _ (Cons name (Cons operations clauses))) _)
         (Ok (EffectForm name operations clauses)))
        (_ (Err (Malformed (marked-loc form) "expected (effect Name ((operation type) ...))")))))

    ;; The `default` clauses, once every clause is found to be one or
    ;; `(around-main)`.
    (: default-clauses (impl (Fn (List Marked) -> (Result (List Marked) Malformed))))
    (define (default-clauses clauses)
      (match clauses
        ((Nil) (Ok (Nil)))
        ((Cons clause rest)
         (cond ((headed? "default" clause)
                (result-let* ((more (default-clauses rest)))
                  (Ok (Cons clause more))))
               ((around-main-clause? clause) (default-clauses rest))
               (else
                (Err
                 (Malformed (marked-loc clause) "expected a default clause or (around-main)")))))))

    (: around-main-clause? (impl (Fn Marked -> Bool)))
    (define (around-main-clause? clause)
      (match clause
        ((Form (Cons head (Nil)) _) (word? "around-main" head))
        (_ #f)))

    (: around-main? (impl (Fn (List Marked) -> Bool)))
    (define (around-main? clauses)
      (any? around-main-clause? clauses))

    (: default-entries (impl (Fn Marked -> (Result (List Marked) Malformed))))
    (define (default-entries clause)
      (match clause
        ((Form (Cons _ (Cons (Form entries _) (Nil))) _) (Ok entries))
        (_
         (Err
          (Malformed (marked-loc clause) "expected (default ((operation implementation) ...))")))))

    ;; `(operation implementation)`, whose operation is a name.
    (struct DefaultForm
      ((name Named)
       (value Marked)
       (loc Loc)))

    (: default-entry (impl (Fn Marked -> (Result DefaultForm Malformed))))
    (define (default-entry entry)
      (match entry
        ((Form (Cons name (Cons value (Nil))) loc)
         (result-let* ((operation (named name "an operation name")))
           (Ok (DefaultForm operation value loc))))
        (_ (Err (Malformed (marked-loc entry) "expected (operation implementation)")))))

    ;; ---- Instances ----

    ;; `(instance (Class type ...) (requires requirement ...) member ...)`,
    ;; where the requirements may be absent.
    (struct InstanceForm
      ((class Marked)
       (types (List Marked))
       (requirements (List Marked))
       (members (List Marked))
       (loc Loc)))

    (: instance-form (impl (Fn Marked -> (Result InstanceForm Malformed))))
    (define (instance-form form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons class types) _) body)) loc)
         (match body
           ((Cons (Form (Cons head requirements) _) members)
            (if (word? "requires" head)
                (Ok (InstanceForm class types requirements members loc))
                (Ok (InstanceForm class types (Nil) body loc))))
           (_ (Ok (InstanceForm class types (Nil) body loc)))))
        (_
         (Err
          (Malformed (marked-loc form) "expected (instance (Class type ...) definition ...)")))))

    ;; An instance's members: its equations `(type Output type)`, and the
    ;; rest, its methods, each in the order written.
    (struct InstanceMembers
      ((equations (List Marked))
       (methods (List Marked))))

    (: instance-members (impl (Fn (List Marked) -> InstanceMembers)))
    (define (instance-members members)
      (InstanceMembers (filter associated-form? members)
                       (filter (lambda (member) (not (associated-form? member))) members)))

    ;; The types of `(dispatch type ...)` when it is an instance's only
    ;; method member, and where it is.
    (: dispatch-types (impl (Fn (List Marked) -> (Option (Pair (List Marked) Loc)))))
    (define (dispatch-types methods)
      (match methods
        ((Cons (Form (Cons head types) loc) (Nil))
         (if (word? "dispatch" head) (Some (Pair types loc)) (None)))
        (_ (None))))

    ;; `(dynamic-instances Class (type ...) ...)`.
    (struct DynamicForm
      ((class Marked)
       (pairs (List Marked))
       (loc Loc)))

    (: dynamic-instances-form (impl (Fn Marked -> (Result DynamicForm Malformed))))
    (define (dynamic-instances-form form)
      (match form
        ((Form (Cons _ (Cons class pairs)) loc) (Ok (DynamicForm class pairs loc)))
        (_
         (Err (Malformed (marked-loc form)
                         "expected (dynamic-instances Class (Left Right) ...) in an instance set")))))

    (: pair-types (impl (Fn Marked -> (Result (List Marked) Malformed))))
    (define (pair-types pair)
      (items-of pair "a pair of concrete types"))

    (: dynamic-instances? (impl (Fn Marked -> Bool)))
    (define (dynamic-instances? form)
      (headed? "dynamic-instances" form))

    ;; ---- Externs, exposes and primitives ----

    (struct ExternForm
      ((name Marked)
       (module String)
       (symbol String)
       (type Marked)))

    (: extern-form (impl (Fn Marked -> (Result ExternForm Malformed))))
    (define (extern-form form)
      (match form
        ((Form (Cons _
                     (Cons name
                           (Cons (Atom (syntax-Text module) _)
                                 (Cons (Atom (syntax-Text symbol) _) (Cons type (Nil))))))
               _)
         (Ok (ExternForm name module symbol type)))
        (_
         (Err (Malformed (marked-loc form) "expected (extern name \"module\" \"symbol\" type)")))))

    ;; `(expose name "symbol")` or `(expose name "symbol" dynamic)`; the
    ;; flags are checked once the name is resolved.
    (struct ExposeForm
      ((name Marked)
       (symbol String)
       (flags (List Marked))
       (loc Loc)))

    (: expose-form (impl (Fn Marked -> (Result ExposeForm Malformed))))
    (define (expose-form form)
      (match form
        ((Form (Cons _ (Cons name (Cons (Atom (syntax-Text symbol) _) flags))) loc)
         (Ok (ExposeForm name symbol flags loc)))
        (_ (Err (Malformed (marked-loc form) expose-usage)))))

    (: dynamic-flag (impl (Fn ExposeForm -> (Result Bool Malformed))))
    (define (dynamic-flag form)
      (match (::flags form)
        ((Nil) (Ok #f))
        ((Cons flag (Nil))
         (if (word? "dynamic" flag) (Ok #t) (Err (Malformed (::loc form) expose-usage))))
        (_ (Err (Malformed (::loc form) expose-usage)))))

    (: expose-usage String)
    (define expose-usage "expected (expose name \"symbol\") or (expose name \"symbol\" dynamic)")

    ;; `(primitive name type)`.
    (struct PrimitiveForm
      ((name Named)
       (type Marked)))

    (: primitive-form (impl (Fn Marked -> (Result PrimitiveForm Malformed))))
    (define (primitive-form form)
      (match form
        ((Form (Cons _ (Cons name (Cons type (Nil)))) _)
         (result-let* ((primitive (named name "a primitive name")))
           (Ok (PrimitiveForm primitive type))))
        (_ (Err (Malformed (marked-loc form) "expected (primitive name type)")))))

    ;; `callable-once`, the type `once` is declared with, which no type
    ;; syntax writes.
    (: callable-once? (impl (Fn Marked -> Bool)))
    (define (callable-once? syntax)
      (word? "callable-once" syntax))

    ;; ---- Scopes and sets ----

    ;; `(with-instances (set ...) top ...)` at the top level.
    (struct ScopeForm
      ((sets (List Marked))
       (body (List Marked))))

    (: with-instances-form (impl (Fn Marked -> (Result ScopeForm Malformed))))
    (define (with-instances-form form)
      (match (form-tail form)
        ((Cons sets body)
         (result-let* ((items (items-of sets "a list of instance sets")))
           (Ok (ScopeForm items body))))
        (_ (Err (Malformed (marked-loc form) "expected (with-instances (set ...) body ...)")))))

    ;; `(define-instance-set name declaration ...)`.
    (struct SetForm
      ((name Named)
       (declarations (List Marked))))

    (: instance-set-form (impl (Fn Marked -> (Result SetForm Malformed))))
    (define (instance-set-form form)
      (match (form-tail form)
        ((Cons name declarations)
         (result-let* ((set-name (named name "an instance set name")))
           (Ok (SetForm set-name declarations))))
        (_ (Err (Malformed (marked-loc form) "expected (define-instance-set name instance ...)")))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-declaration-shapes)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail stage0 testing))
    (begin
      (define (test-declaration-shapes)
        (test-annotations)
        (test-heads)
        (test-data)
        (test-effects)
        (test-instances)
        (test-others))

      (define loc (Loc "t.sld" 1 1))

      (define (marked datum)
        (cond ((or (null? datum) (pair? datum)) (Form (map marked datum) loc))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) loc))
              ((string? datum) (Atom (syntax-Text datum) loc))
              ((exact-integer? datum) (Atom (syntax-Integer datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (plain name)
        (Named (Identifier name (Nil)) loc))

      (define (refused message)
        (Err (Malformed loc message)))

      ;; An annotation list comes after the required items, once.
      (define (test-annotations)
        (expect (split-annotations (marked '(: f I64 (annotations (doc "f")))) 3)
                (Ok (AnnotatedForm (marked '(: f I64)) (list (Documentation "f" loc)))))
        (expect (split-annotations (marked '(: f (annotations (doc "f")))) 3)
                (Ok (AnnotatedForm (marked '(: f (annotations (doc "f")))) (list))))
        (expect (split-annotations (marked '(struct P
                                              () (annotations) (annotations))) 2)
                (refused "a declaration has at most one annotation list"))
        (expect (split-annotations (marked '(struct P
                                              () (annotations (doc 1)))) 2)
                (refused "doc needs exactly one literal string"))
        (expect
         (split-annotations (marked '((annotations ("x" "y")) P () (annotations ("x" "y")))) 2)
         (refused "expected an annotation application, such as (doc \"text\")"))
        (expect (split-annotations (marked '(struct P
                                              () (annotations (doc)))) 2)
                (refused "doc needs exactly one literal string"))
        (expect (split-annotations (marked '(struct P
                                              () (annotations (see "x")))) 2)
                (refused "unknown annotation: see"))
        (expect (split-annotations (marked '(struct P
                                              () (annotations x))) 2)
                (refused "expected an annotation application, such as (doc \"text\")"))
        (expect (annotation-arity "extern") (Some 5))
        (expect (annotation-arity "define") (None)))

      (define (test-heads)
        (expect (declaration-head (marked '(struct))) (refused "expected a declared name"))
        (expect (declared-name (marked '(Box a))) (Ok (plain "Box")))
        (expect (declared-name (marked 1)) (refused "expected a type name"))
        (expect (declared-params (marked '(Box a b))) (Ok (list (plain "a") (plain "b"))))
        (expect (declared-params (marked '(Box 1))) (refused "expected a type parameter"))
        (expect (declared-params (marked 'Box)) (Ok (list))))

      (define (test-data)
        (expect (struct-fields (marked '(struct P
                                          ((x I64)) (deriving Move))))
                (Ok (list (marked '(x I64)))))
        (expect (struct-fields (marked '(struct P))) (Ok (list)))
        (expect (struct-fields (marked '(struct P x))) (refused "expected a field list"))
        (expect (struct-fields (marked '(struct P
                                          () ())))
                (refused "expected (struct Name ((field type) ...))"))
        (expect (field-form (marked '(x mut I64)))
                (Ok (FieldForm (marked 'x) #t (marked 'I64) (list))))
        (expect (field-form (marked '(x I64 (annotations (doc "x")))))
                (Ok (FieldForm (marked 'x) #f (marked 'I64) (list (Documentation "x" loc)))))
        (expect (field-form (marked '(x y I64)))
                (refused
                 "expected (field type) or (field mut type), optionally with (annotations ...)"))
        (expect (case-form (marked '(None))) (Ok (CaseForm (plain "None") (list) (list))))
        (expect (case-form (marked '(Some ((value a)))))
                (Ok (CaseForm (plain "Some") (list (marked '(value a))) (list))))
        (expect (case-form (marked '(1))) (refused "expected a case name"))
        (expect (case-form (marked '(Some x))) (refused "expected a field list"))
        (expect (case-form (marked 'None))
                (refused
                 "expected (Case), or (Case ((field type) ...)), optionally with (annotations ...)"))
        (expect (derived-classes (marked '(enum E (A) (deriving Move Serialize) (deriving X))))
                (map marked '(Move Serialize X)))
        (expect (derivation (marked 'Deserialize)) (Ok (DeriveDeserialize loc)))
        (expect (derivation (marked 'Show))
                (refused "only Move, Serialize and Deserialize can be derived"))
        (expect (alias-body (list) (marked '(type T))) (refused "expected (type Name type)"))
        (expect (associated-name (marked '(type Output))) (Ok (plain "Output")))
        (expect (associated-name (marked '(type (Output a))))
                (refused "expected (type Output); associated types take no parameters"))
        (expect (method-form (marked '(: show (Fn a -> String))))
                (Some (Pair (marked 'show) (marked '(Fn a -> String)))))
        (expect (method-form (marked '(define x 1))) (None)))

      (define (test-effects)
        (expect (effect-operations (list) (marked '(effect E)))
                (refused "expected (effect Name ((operation type) ...))"))
        (expect (effect-operations (list (marked 'x)) (marked '(effect E x)))
                (refused "expected a list of operations"))
        (expect (operation-form (marked '(ctl yield (Fn -> Unit))))
                (Ok (OperationForm (marked 'yield) (marked '(Fn -> Unit)) #t (list))))
        (expect (operation-form (marked '(read T)))
                (Ok (OperationForm (marked 'read) (marked 'T) #f (list))))
        (expect (operation-form (marked '(read)))
                (refused "expected (operation type) or (ctl operation type)"))
        (expect (default-clauses (map marked '((default ()) (around-main) (default ((a b))))))
                (Ok (map marked '((default ()) (default ((a b)))))))
        (expect (default-clauses (map marked '((around-main x))))
                (refused "expected a default clause or (around-main)"))
        (expect (around-main? (map marked '((default ()) (around-main)))) #t)
        (expect (default-entries (marked '(default x)))
                (refused "expected (default ((operation implementation) ...))"))
        (expect (default-entry (marked '(read f)))
                (Ok (DefaultForm (plain "read") (marked 'f) loc)))
        (expect (default-entry (marked '(1 f))) (refused "expected an operation name"))
        (expect (default-entry (marked '(read))) (refused "expected (operation implementation)")))

      (define (test-instances)
        (expect (instance-form (marked '(instance (Show I64) (requires (Show a)) (define x 1))))
                (Ok (InstanceForm (marked 'Show)
                                  (list (marked 'I64))
                                  (list (marked '(Show a)))
                                  (list (marked '(define x 1)))
                                  loc)))
        (expect (instance-form (marked '(instance Show)))
                (refused "expected (instance (Class type ...) definition ...)"))
        (expect (instance-members (map marked '((type Out I64) (define x 1))))
                (InstanceMembers (list (marked '(type Out I64))) (list (marked '(define x 1)))))
        (expect (dispatch-types (list (marked '(dispatch A B))))
                (Some (Pair (map marked '(A B)) loc)))
        (expect (dispatch-types (list (marked '(define x 1)))) (None))
        (expect (dynamic-instances-form (marked '(dynamic-instances)))
                (refused "expected (dynamic-instances Class (Left Right) ...) in an instance set"))
        (expect (pair-types (marked 'x)) (refused "expected a pair of concrete types")))

      (define (test-others)
        (expect (extern-form (marked '(extern f "m" "s" T)))
                (Ok (ExternForm (marked 'f) "m" "s" (marked 'T))))
        (expect (extern-form (marked '(extern f m "s" T)))
                (refused "expected (extern name \"module\" \"symbol\" type)"))
        (let ((form (ExposeForm (marked 'f) "f" (list (marked 'static)) loc)))
          (expect (dynamic-flag form)
                  (refused
                   "expected (expose name \"symbol\") or (expose name \"symbol\" dynamic)")))
        (expect (dynamic-flag (ExposeForm (marked 'f) "f" (list (marked 'dynamic)) loc)) (Ok #t))
        (expect (primitive-form (marked '(primitive 1 T))) (refused "expected a primitive name"))
        (expect (primitive-form (marked '(primitive f))) (refused "expected (primitive name type)"))
        (expect (with-instances-form (marked '(with-instances x)))
                (refused "expected a list of instance sets"))
        (expect (with-instances-form (marked '(with-instances)))
                (refused "expected (with-instances (set ...) body ...)"))
        (expect (instance-set-form (marked '(define-instance-set)))
                (refused "expected (define-instance-set name instance ...)"))
        (expect (instance-set-form (marked '(define-instance-set 1)))
                (refused "expected an instance set name"))
        (expect (callable-once? (marked 'callable-once)) #t))))
   (else)))
