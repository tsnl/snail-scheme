;; The shape of each core form, and of the definitions a body may hold:
;; which items a form has where, as the old expander takes them apart.
;; The part that expands a form knows which keyword its head resolved to,
;; and asks here for the form's items, or what to say of a form that is
;; malformed, which it places; it expands each item.
(define-library (snail compiler expand form-shapes)
  (export
   CoreForm
   FunctionForm
   IfForm
   WithInstancesForm
   BeginForm
   NamedLetForm
   PlainLetForm
   MatchForm
   ArtifactFilesForm
   LinkHandleForm
   TypedForm
   HandleForm
   CaseIdForm
   QuoteForm
   MalformedForm
   TypedKind
   Annotated
   Converted
   TryConverted
   TypeTested
   core-form
   DefinitionShape
   NamedDefinition
   MalformedDefinition
   DefinedValue
   FunctionValue
   ExpressionValue
   definition-shape
   SignatureShape
   SignatureForm
   MalformedSignature
   signature-shape)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler literals datum) Datum)
   (prefix (snail compiler literals datum) datum-)
   (snail compiler expand marked)
   (only (snail compiler expand scopes) marked-loc))
  (begin

    ;; ---- Core forms ----

    ;; The items of a form whose head is a core keyword. `lambda` and `fn`
    ;; are a function, and `fn` one that captures nothing. A let with a
    ;; name at its head is a loop, whose bindings must still be found to be
    ;; a list. The four forms of an expression and a type are one shape.
    ;; A malformed form, at the form, is answered with what it should have
    ;; been, and so is one a keyword heads that no expression may, which
    ;; is a definition's.
    (enum CoreForm
      (FunctionForm
       ((captures? Bool)
        (parameters Marked)
        (body (List Marked))))
      (IfForm
       ((test Marked)
        (consequent Marked)
        (alternative (Option Marked))))
      (WithInstancesForm
       ((sets Marked)
        (body (List Marked))))
      (BeginForm
       ((body (List Marked))))
      (NamedLetForm
       ((name Identifier)
        (bindings Marked)
        (body (List Marked))))
      (PlainLetForm
       ((bindings (List Marked))
        (body (List Marked))))
      (MatchForm
       ((scrutinee Marked)
        (clauses (List Marked))))
      (ArtifactFilesForm
       ((target String)
        (file Marked)
        (prepend Marked)
        (empty Marked)))
      (LinkHandleForm
       ((path String)
        (path-loc Loc)))
      (TypedForm
       ((kind TypedKind)
        (value Marked)
        (type Marked)))
      (HandleForm
       ((effect Marked)
        (implementations (List Marked))
        (body (List Marked))))
      (CaseIdForm
       ((constructor Marked)))
      (QuoteForm
       ((datum Datum)))
      (MalformedForm
       ((message String))))

    ;; `ann`, `type-convert`, `try-convert` and `type-test`.
    (enum TypedKind
      (Annotated)
      (Converted)
      (TryConverted)
      (TypeTested))

    ;; The shape of the form headed by `keyword` whose items, the head
    ;; first, are `items`.
    (: core-form (impl (Fn String (List Marked) -> CoreForm)))
    (define (core-form keyword items)
      (let ((rest (match items
                    ((Cons _ after) after)
                    ((Nil) (Nil)))))
        (cond ((string=? keyword "lambda") (function-form #t rest))
              ((string=? keyword "fn") (function-form #f rest))
              ((string=? keyword "if") (if-form rest))
              ((string=? keyword "with-instances") (with-instances-form rest))
              ((string=? keyword "begin") (BeginForm rest))
              ((string=? keyword "let") (let-form rest))
              ((string=? keyword "match") (match-form rest))
              ((string=? keyword "artifact-files") (artifact-files-form rest))
              ((string=? keyword "link-handle") (link-handle-form rest))
              ((string=? keyword "handle") (handle-form rest))
              ((string=? keyword "case-id") (case-id-form rest))
              ((string=? keyword "quote") (quote-form rest))
              (else
               (match (typed-kind keyword)
                 ((Some kind) (typed-form kind rest))
                 ((None)
                  (MalformedForm (string-append "this form is only valid as a definition: "
                                                keyword))))))))

    (: function-form (impl (Fn Bool (List Marked) -> CoreForm)))
    (define (function-form captures? items)
      (match items
        ((Cons parameters body) (FunctionForm captures? parameters body))
        ((Nil)
         (MalformedForm (if captures?
                            "expected (lambda (parameter ...) body ...)"
                            "expected (fn (parameter ...) body ...)")))))

    (: if-form (impl (Fn (List Marked) -> CoreForm)))
    (define (if-form items)
      (match items
        ((Cons test (Cons consequent (Nil))) (IfForm test consequent (None)))
        ((Cons test (Cons consequent (Cons alternative (Nil))))
         (IfForm test consequent (Some alternative)))
        (_ (MalformedForm "expected (if test then [else])"))))

    (: with-instances-form (impl (Fn (List Marked) -> CoreForm)))
    (define (with-instances-form items)
      (match items
        ((Cons sets body) (WithInstancesForm sets body))
        ((Nil) (MalformedForm "expected (with-instances (set ...) body ...)"))))

    ;; `(let name bindings body ...)` or `(let (binding ...) body ...)`,
    ;; with something after the head either way.
    (: let-form (impl (Fn (List Marked) -> CoreForm)))
    (define (let-form items)
      (match items
        ((Cons (Ident name _) (Cons bindings body)) (NamedLetForm name bindings body))
        ((Cons (Form bindings _) (Cons more body)) (PlainLetForm bindings (Cons more body)))
        (_ (MalformedForm "expected (let ((name value) ...) body ...)"))))

    (: match-form (impl (Fn (List Marked) -> CoreForm)))
    (define (match-form items)
      (match items
        ((Cons scrutinee clauses) (MatchForm scrutinee clauses))
        ((Nil) (MalformedForm "expected (match expression clause ...)"))))

    (: artifact-files-form (impl (Fn (List Marked) -> CoreForm)))
    (define (artifact-files-form items)
      (match items
        ((Cons (Atom (datum-Text target) _) (Cons file (Cons prepend (Cons empty (Nil)))))
         (ArtifactFilesForm target file prepend empty))
        (_ (MalformedForm "artifact-bundle expects a literal target name"))))

    (: link-handle-form (impl (Fn (List Marked) -> CoreForm)))
    (define (link-handle-form items)
      (match items
        ((Cons (Atom (datum-Text path) path-loc) (Nil)) (LinkHandleForm path path-loc))
        (_ (MalformedForm "link-file expects a literal relative path"))))

    (: handle-form (impl (Fn (List Marked) -> CoreForm)))
    (define (handle-form items)
      (match items
        ((Cons effect (Cons (Form implementations _) body))
         (HandleForm effect implementations body))
        (_ (MalformedForm "expected (handle Effect ((operation implementation) ...) body ...)"))))

    (: case-id-form (impl (Fn (List Marked) -> CoreForm)))
    (define (case-id-form items)
      (match items
        ((Cons constructor (Nil)) (CaseIdForm constructor))
        (_ (MalformedForm "expected (case-id Constructor)"))))

    (: quote-form (impl (Fn (List Marked) -> CoreForm)))
    (define (quote-form items)
      (match items
        ((Cons (Atom datum _) (Nil)) (QuoteForm datum))
        (_ (MalformedForm "only literals can be quoted"))))

    (: typed-kind (impl (Fn String -> (Option TypedKind))))
    (define (typed-kind keyword)
      (cond ((string=? keyword "ann") (Some (Annotated)))
            ((string=? keyword "type-convert") (Some (Converted)))
            ((string=? keyword "try-convert") (Some (TryConverted)))
            ((string=? keyword "type-test") (Some (TypeTested)))
            (else (None))))

    (: typed-form (impl (Fn TypedKind (List Marked) -> CoreForm)))
    (define (typed-form kind items)
      (match items
        ((Cons value (Cons type (Nil))) (TypedForm kind value type))
        (_ (MalformedForm (typed-usage kind)))))

    (: typed-usage (impl (Fn TypedKind -> String)))
    (define (typed-usage kind)
      (match kind
        ((Annotated) "expected (ann expression type)")
        ((Converted) "expected (type-convert expression type)")
        ((TryConverted) "expected (try-convert expression type)")
        ((TypeTested) "expected (type-test expression type)")))

    ;; ---- Definitions ----

    ;; `(define (name parameter ...) body ...)` or `(define name value)`.
    ;; A name that is not an identifier is refused at the name, and any
    ;; other malformed definition at the form.
    (enum DefinitionShape
      (NamedDefinition
       ((name Identifier)
        (name-loc Loc)
        (value DefinedValue)))
      (MalformedDefinition
       ((loc Loc)
        (message String))))

    (enum DefinedValue
      (FunctionValue
       ((parameters (List Marked))
        (body (List Marked))))
      (ExpressionValue
       ((value Marked))))

    (: definition-shape (impl (Fn Marked -> DefinitionShape)))
    (define (definition-shape form)
      (match form
        ((Form (Cons _ (Cons (Form (Cons (Ident name name-loc) parameters) _) body)) _)
         (NamedDefinition name name-loc (FunctionValue parameters body)))
        ((Form (Cons _ (Cons (Form (Cons name _) _) _)) _)
         (MalformedDefinition (marked-loc name) "expected a definition name"))
        ((Form (Cons _ (Cons (Ident name name-loc) (Cons value (Nil)))) _)
         (NamedDefinition name name-loc (ExpressionValue value)))
        ((Form (Cons _ (Cons name (Cons _ (Nil)))) _)
         (MalformedDefinition (marked-loc name) "expected a definition name"))
        (_
         (MalformedDefinition (marked-loc form)
                              "expected (define name value) or (define (name parameter ...) body ...)"))))

    ;; `(: name type)`.
    (enum SignatureShape
      (SignatureForm
       ((name Identifier)
        (name-loc Loc)
        (type Marked)))
      (MalformedSignature
       ((loc Loc)
        (message String))))

    (: signature-shape (impl (Fn Marked -> SignatureShape)))
    (define (signature-shape form)
      (match form
        ((Form (Cons _ (Cons (Ident name name-loc) (Cons type (Nil)))) _)
         (SignatureForm name name-loc type))
        ((Form (Cons _ (Cons name (Cons _ (Nil)))) _)
         (MalformedSignature (marked-loc name) "expected a name"))
        (_ (MalformedSignature (marked-loc form) "expected (: name type)"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-form-shapes)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail stage0 testing))
    (begin
      (define (test-form-shapes)
        (test-functions)
        (test-conditionals)
        (test-lets)
        (test-literal-forms)
        (test-other-forms)
        (test-definitions)
        (test-signatures))

      (define loc (Loc "t.sld" 1 1))

      (define (marked datum)
        (cond ((or (null? datum) (pair? datum)) (Form (map marked datum) loc))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) loc))
              ((string? datum) (Atom (datum-Text datum) loc))
              ((exact-integer? datum) (Atom (datum-Integer datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (shape datum)
        (match (marked datum)
          ((Form (Cons (Ident keyword _) rest) _)
           (core-form (::name keyword) (Cons (marked 'head) rest)))
          (_ (panic "a test form has a keyword at its head"))))

      (define (plain name)
        (Identifier name (Nil)))

      (define (test-functions)
        (expect (shape '(lambda (x) x)) (FunctionForm #t (marked '(x)) (list (marked 'x))))
        (expect (shape '(fn (x))) (FunctionForm #f (marked '(x)) (list)))
        (expect (shape '(fn x 1 2)) (FunctionForm #f (marked 'x) (list (marked 1) (marked 2))))
        (expect (shape '(lambda)) (MalformedForm "expected (lambda (parameter ...) body ...)"))
        (expect (shape '(fn)) (MalformedForm "expected (fn (parameter ...) body ...)")))

      (define (test-conditionals)
        (expect (shape '(if a b)) (IfForm (marked 'a) (marked 'b) (None)))
        (expect (shape '(if a b c)) (IfForm (marked 'a) (marked 'b) (Some (marked 'c))))
        (expect (shape '(if a)) (MalformedForm "expected (if test then [else])"))
        (expect (shape '(if a b c d)) (MalformedForm "expected (if test then [else])"))
        (expect (shape '(match x)) (MatchForm (marked 'x) (list)))
        (expect (shape '(match x (a 1))) (MatchForm (marked 'x) (list (marked '(a 1)))))
        (expect (shape '(match)) (MalformedForm "expected (match expression clause ...)")))

      ;; A let needs something after its head; a loop's bindings are
      ;; whatever follows its name.
      (define (test-lets)
        (expect (shape '(let ((x 1)) x)) (PlainLetForm (list (marked '(x 1))) (list (marked 'x))))
        (expect (shape '(let () x)) (PlainLetForm (list) (list (marked 'x))))
        (expect (shape '(let loop ((x 1)) x))
                (NamedLetForm (plain "loop") (marked '((x 1))) (list (marked 'x))))
        (expect (shape '(let loop x)) (NamedLetForm (plain "loop") (marked 'x) (list)))
        (expect (shape '(let ((x 1)))) (MalformedForm "expected (let ((name value) ...) body ...)"))
        (expect (shape '(let loop)) (MalformedForm "expected (let ((name value) ...) body ...)"))
        (expect (shape '(let 1 x)) (MalformedForm "expected (let ((name value) ...) body ...)"))
        (expect (shape '(let)) (MalformedForm "expected (let ((name value) ...) body ...)")))

      (define (test-literal-forms)
        (expect (shape '(quote 1)) (QuoteForm (datum-Integer 1)))
        (expect (shape '(quote x)) (MalformedForm "only literals can be quoted"))
        (expect (shape '(quote 1 2)) (MalformedForm "only literals can be quoted"))
        (expect (shape '(link-handle "data/x.png")) (LinkHandleForm "data/x.png" loc))
        (expect (shape '(link-handle x))
                (MalformedForm "link-file expects a literal relative path"))
        (expect (shape '(artifact-files "site" f c n))
                (ArtifactFilesForm "site" (marked 'f) (marked 'c) (marked 'n)))
        (expect (shape '(artifact-files site f c n))
                (MalformedForm "artifact-bundle expects a literal target name"))
        (expect (shape '(artifact-files "site" f c))
                (MalformedForm "artifact-bundle expects a literal target name")))

      (define (test-other-forms)
        (expect (shape '(with-instances (s) x))
                (WithInstancesForm (marked '(s)) (list (marked 'x))))
        (expect (shape '(with-instances s)) (WithInstancesForm (marked 's) (list)))
        (expect (shape '(with-instances))
                (MalformedForm "expected (with-instances (set ...) body ...)"))
        (expect (shape '(begin)) (BeginForm (list)))
        (expect (shape '(handle io ((read r)) x))
                (HandleForm (marked 'io) (list (marked '(read r))) (list (marked 'x))))
        (expect (shape '(handle io read x))
                (MalformedForm
                 "expected (handle Effect ((operation implementation) ...) body ...)"))
        (expect (shape '(case-id Some)) (CaseIdForm (marked 'Some)))
        (expect (shape '(case-id)) (MalformedForm "expected (case-id Constructor)"))
        (expect (shape '(ann x I64)) (TypedForm (Annotated) (marked 'x) (marked 'I64)))
        (expect (shape '(type-convert x I64)) (TypedForm (Converted) (marked 'x) (marked 'I64)))
        (expect (shape '(try-convert x I64)) (TypedForm (TryConverted) (marked 'x) (marked 'I64)))
        (expect (shape '(type-test x I64)) (TypedForm (TypeTested) (marked 'x) (marked 'I64)))
        (expect (shape '(ann x)) (MalformedForm "expected (ann expression type)"))
        (expect (shape '(define x 1))
                (MalformedForm "this form is only valid as a definition: define"))
        (expect (shape '(struct Point))
                (MalformedForm "this form is only valid as a definition: struct")))

      (define (test-definitions)
        (expect (definition-shape (marked '(define (f x y) x)))
                (NamedDefinition (plain "f")
                                 loc
                                 (FunctionValue (list (marked 'x) (marked 'y)) (list (marked 'x)))))
        (expect (definition-shape (marked '(define (f))))
                (NamedDefinition (plain "f") loc (FunctionValue (list) (list))))
        (expect (definition-shape (marked '(define x 1)))
                (NamedDefinition (plain "x") loc (ExpressionValue (marked 1))))
        (expect (definition-shape (marked '(define (1 x) x)))
                (MalformedDefinition loc "expected a definition name"))
        (expect (definition-shape (marked '(define "x" 1)))
                (MalformedDefinition loc "expected a definition name"))
        (expect (definition-shape (marked '(define x)))
                (MalformedDefinition loc
                                     "expected (define name value) or (define (name parameter ...) body ...)"))
        (expect (definition-shape (marked '(define x 1 2)))
                (MalformedDefinition loc
                                     "expected (define name value) or (define (name parameter ...) body ...)"))
        (expect (definition-shape (marked '(define () 1)))
                (MalformedDefinition loc "expected a definition name"))
        (expect (definition-shape (marked '(define () 1 2)))
                (MalformedDefinition loc
                                     "expected (define name value) or (define (name parameter ...) body ...)")))

      (define (test-signatures)
        (expect (signature-shape (marked '(: x I64))) (SignatureForm (plain "x") loc (marked 'I64)))
        (expect (signature-shape (marked '(: 1 I64))) (MalformedSignature loc "expected a name"))
        (expect (signature-shape (marked '(: x))) (MalformedSignature loc "expected (: name type)"))
        (expect (signature-shape (marked '(: x I64 I64)))
                (MalformedSignature loc "expected (: name type)")))))
   (else)))
