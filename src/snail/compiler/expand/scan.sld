;; The top level's first pass: every name it defines, bound in the order
;; written, so a definition may refer to a later one. Each form's head is
;; expanded first, while it names a macro; a `begin` is spliced, and a
;; `with-instances` scans its forms under its sets. A `define-syntax`
;; binds its macro, which the forms after it may use. A declaration binds
;; its names: a type, a struct's constructor and its fields' functions,
;; an enum's cases and theirs, a class with its methods and outputs, an
;; effect with its operations, an extern. What remains of each form waits
;; as an Item for the passes after this, which read the syntax again. The
;; first problem stops the scan, as it stops the old expander's, since
;; what follows needs every name.
(define-library (snail compiler expand scan)
  (export
   Item
   Pending
   PendingScope
   PendingSet
   Scan
   scan-forms
   top-global
   top-site
   bind)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (only (snail compiler outline names) same-library?)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand scopes)
   (snail compiler expand state)
   (snail compiler expand form-shapes)
   (snail compiler expand macros)
   (snail compiler expand declaration-shapes)
   (snail compiler expand expressions))
  (begin

    ;; ---- Items ----

    ;; A form the scan found, by the keyword at its head, or "expression":
    ;; without its annotation list, which `annotations` holds. A top-level
    ;; `with-instances` holds the items written under its sets, and an
    ;; instance set those its declarations are.
    (enum Item
      (Pending
       ((keyword String)
        (form Marked)
        (annotations (List Annotation))))
      (PendingScope
       ((sets (List Marked))
        (items (List Item))
        (loc Loc)))
      (PendingSet
       ((global Global)
        (items (List Item))
        (loc Loc))))

    ;; The items a scan found, and the scopes with the names they bound.
    (struct Scan
      ((items (List Item))
       (scopes Scopes)))

    ;; ---- Names ----

    ;; A top-level name's Global: its serial is its latest mark's number,
    ;; which is the expansion that wrote it, or 0 when the source did.
    (: top-global (impl (Fn Scopes Identifier -> Global)))
    (define (top-global scopes identifier)
      (Global (::library scopes)
              (::name identifier)
              (match (::marks identifier)
                ((Cons mark _) (::number mark))
                ((Nil) 0))))

    ;; `scopes` with `identifier` bound at its top level, once. Two names
    ;; are one definition when their names and latest marks are, as the
    ;; old expander keys them, so each Global is defined once.
    (: bind (impl (Fn Scopes Identifier Loc Meaning -> (Result Scopes (List Feedback)))))
    (define (bind scopes identifier loc meaning)
      (let* ((top (::top scopes))
             (named (match (table-ref (::definitions top) (::name identifier))
                      ((Some bindings) bindings)
                      ((None) (Nil)))))
        (if (any? (lambda (binding) (same-key? (::identifier binding) identifier)) named)
            (fail loc (string-append "duplicate top-level definition " (::name identifier)))
            (Ok (Scopes (::library scopes)
                        (TopScope (table-set (::definitions top)
                                             (::name identifier)
                                             (Cons (Binding identifier meaning) named))
                                  (::imports top))
                        (::offers scopes))))))

    (: same-key? (impl (Fn Identifier Identifier -> Bool)))
    (define (same-key? identifier other)
      (and (string=? (::name identifier) (::name other))
           (match (Pair (::marks identifier) (::marks other))
             ((Pair (Nil) (Nil)) #t)
             ((Pair (Cons mark _) (Cons other-mark _))
              (and (same-library? (::library mark) (::library other-mark))
                   (= (::number mark) (::number other-mark))))
             (_ #f))))

    ;; A value named where the source or a macro wrote it.
    (: bind-value (impl (Fn Scopes Named -> (Result Scopes (List Feedback)))))
    (define (bind-value scopes name)
      (bind scopes
            (::identifier name)
            (::loc name)
            (Value (TopGlobal (top-global scopes (::identifier name))))))

    ;; A name a declaration makes from another by adding to it, as a
    ;; field's functions are named from their type's: it keeps the marks
    ;; of the name it is made from, so only the expansion that wrote that
    ;; name sees it.
    (: suffixed (impl (Fn Identifier String -> Identifier)))
    (define (suffixed identifier text)
      (Identifier (string-append (::name identifier) text) (::marks identifier)))

    ;; The site where a top-level form is expanded: no frames, under the
    ;; sets of each `with-instances` around it.
    (: top-site (impl (Fn Scopes (List WrittenSets) -> Site)))
    (define (top-site scopes sets)
      (Site scopes (Env (Nil) (::library scopes)) sets))

    (: refused (All (T) (impl (Fn (Result T Malformed) -> (Result T (List Feedback))))))
    (define (refused answer)
      (match answer
        ((Ok value) (Ok value))
        ((Err malformed) (fail (::loc malformed) (::message malformed)))))

    ;; ---- Forms ----

    ;; The items `forms` are, in order, written under `sets`.
    (: scan-forms
       (impl (Fn Expanding Scopes (List WrittenSets) (List Marked)
                 -> (Result (Pair Scan Expanding) (List Feedback)))))
    (define (scan-forms state scopes sets forms)
      (let loop ((state state)
                 (scopes scopes)
                 (forms forms)
                 (found (Nil)))
        (match forms
          ((Nil) (Ok (Pair (Scan (concatenate (reverse found)) scopes) state)))
          ((Cons form rest)
           (expanding-let* ((scan state (scan-form state scopes sets form)))
             (loop state (::scopes scan) rest (Cons (::items scan) found)))))))

    ;; A form once its head is expanded, without its annotation list. A
    ;; declaration with annotations names what they annotate, which must
    ;; be a name before the form is looked at further.
    (: scan-form
       (impl (Fn Expanding Scopes (List WrittenSets) Marked
                 -> (Result (Pair Scan Expanding) (List Feedback)))))
    (define (scan-form state scopes sets form)
      (expanding-let* ((expanded state (expand-head state (top-site scopes sets) form)))
        (let ((keyword (form-keyword scopes expanded)))
          (expanding-let* ((split state (unchanged state (refused (annotated keyword expanded))))
                           (owner state (unchanged state (annotated-owner split))))
            (scan-keyword state scopes sets keyword split)))))

    ;; The keyword a form's head means, if it means one at the top level.
    (: form-keyword (impl (Fn Scopes Marked -> (Option String))))
    (define (form-keyword scopes form)
      (match (head-resolution scopes (Env (Nil) (::library scopes)) form)
        ((BoundAtTop (Keyword keyword)) (Some keyword))
        (_ (None))))

    ;; Only a declaration's form may end with an annotation list.
    (: annotated (impl (Fn (Option String) Marked -> (Result AnnotatedForm Malformed))))
    (define (annotated keyword form)
      (match (match keyword
               ((Some name) (annotation-arity name))
               ((None) (None)))
        ((Some arity) (split-annotations form arity))
        ((None) (Ok (AnnotatedForm form (Nil))))))

    (: annotated-owner (impl (Fn AnnotatedForm -> (Result Bool (List Feedback)))))
    (define (annotated-owner split)
      (if (null? (::annotations split))
          (Ok #f)
          (result-let* ((head (refused (declaration-head (::form split))))
                        (name (refused (declared-name head))))
            (Ok #t))))

    (: scan-keyword
       (impl (Fn Expanding Scopes (List WrittenSets) (Option String) AnnotatedForm
                 -> (Result (Pair Scan Expanding) (List Feedback)))))
    (define (scan-keyword state scopes sets keyword split)
      (let ((form (::form split))
            (annotations (::annotations split)))
        (match keyword
          ((Some "begin") (scan-forms state scopes sets (form-tail form)))
          ((Some "with-instances") (scan-scope state scopes sets form))
          ((Some "define-instance-set") (scan-instance-set state scopes sets form))
          ((Some "define-syntax") (top-macro state scopes form))
          ((Some "primitive")
           (fail (marked-loc form) "primitives are declared only in (snail core primitive)"))
          ((Some "define") (unchanged state (scan-define scopes form)))
          ((Some other)
           (if (member? other declaration-keywords)
               (unchanged state (scan-declared scopes other form annotations))
               (unchanged state (Ok (Scan (list (Pending "expression" form (Nil))) scopes)))))
          ((None) (unchanged state (Ok (Scan (list (Pending "expression" form (Nil))) scopes)))))))

    (: declaration-keywords (List String))
    (define declaration-keywords
      (list ":" "struct" "enum" "type" "typeclass" "instance" "extern" "effect" "expose"))

    ;; ---- Scopes, sets and macros ----

    (: scan-scope
       (impl (Fn Expanding Scopes (List WrittenSets) Marked
                 -> (Result (Pair Scan Expanding) (List Feedback)))))
    (define (scan-scope state scopes sets form)
      (expanding-let* ((scope state (unchanged state (refused (with-instances-form form))))
                       (inner state (scan-forms state
                                                scopes
                                                (Cons (WrittenSets (::sets scope)
                                                                   (Env (Nil) (::library scopes)))
                                                      sets)
                                                (::body scope))))
        (Ok (Pair (Scan (list (PendingScope (::sets scope) (::items inner) (marked-loc form)))
                        (::scopes inner))
                  state))))

    ;; An instance set binds its name, then holds instances, each scanned
    ;; as written, and `dynamic-instances` declarations.
    (: scan-instance-set
       (impl (Fn Expanding Scopes (List WrittenSets) Marked
                 -> (Result (Pair Scan Expanding) (List Feedback)))))
    (define (scan-instance-set state scopes sets form)
      (expanding-let* ((set state (unchanged state (refused (instance-set-form form))))
                       (bound state (unchanged state
                                               (bind scopes
                                                     (::identifier (::name set))
                                                     (::loc (::name set))
                                                     (InstanceSetName
                                                      (top-global scopes
                                                                  (::identifier (::name set))))))))
        (let loop ((state state)
                   (scopes bound)
                   (declarations (::declarations set))
                   (found (Nil)))
          (match declarations
            ((Nil)
             (Ok (Pair (Scan (list (PendingSet (top-global scopes (::identifier (::name set)))
                                               (concatenate (reverse found))
                                               (marked-loc form)))
                             scopes)
                       state)))
            ((Cons declaration rest)
             (expanding-let* ((scan state (set-member state scopes sets declaration)))
               (loop state (::scopes scan) rest (Cons (::items scan) found))))))))

    (: set-member
       (impl (Fn Expanding Scopes (List WrittenSets) Marked
                 -> (Result (Pair Scan Expanding) (List Feedback)))))
    (define (set-member state scopes sets declaration)
      (cond ((equal-keyword? (form-keyword scopes declaration) "instance")
             (scan-form state scopes sets declaration))
            ((dynamic-instances? declaration)
             (Ok (Pair (Scan (list (Pending "dynamic-instances" declaration (Nil))) scopes) state)))
            (else
             (fail (marked-loc declaration)
                   "an instance set contains instance or dynamic-instances declarations"))))

    (: equal-keyword? (impl (Fn (Option String) String -> Bool)))
    (define (equal-keyword? keyword name)
      (match keyword
        ((Some found) (string=? found name))
        ((None) #f)))

    ;; A top-level macro's templates resolve at this top level, where its
    ;; own name is bound, so it may expand to a use of itself.
    (: top-macro
       (impl (Fn Expanding Scopes Marked -> (Result (Pair Scan Expanding) (List Feedback)))))
    (define (top-macro state scopes form)
      (expanding-let* ((parts state (unchanged state (macro-definition form)))
                       (number state (fresh state))
                       (bound state (unchanged state
                                               (bind scopes
                                                     (::name parts)
                                                     (::name-loc parts)
                                                     (MacroRules
                                                      (Macro (MacroId (::library scopes) number)
                                                             (::literals parts)
                                                             (::rules parts)))))))
        (Ok (Pair (Scan (list) bound) state))))

    ;; ---- Definitions ----

    (: scan-define (impl (Fn Scopes Marked -> (Result Scan (List Feedback)))))
    (define (scan-define scopes form)
      (match (definition-shape form)
        ((NamedDefinition name name-loc _)
         (result-let* ((bound (bind-value scopes (Named name name-loc))))
           (Ok (Scan (list (Pending "define" form (Nil))) bound))))
        ((MalformedDefinition place message) (fail place message))))

    ;; A declaration binds its names; then a struct's or enum's deriving
    ;; clauses are checked, which `derive` makes instances of.
    (: scan-declared
       (impl (Fn Scopes String Marked (List Annotation) -> (Result Scan (List Feedback)))))
    (define (scan-declared scopes keyword form annotations)
      (match (form-tail form)
        ((Cons head rest)
         (result-let* ((bound (declaration-names scopes keyword head rest form))
                       (checked (derivations-of keyword form)))
           (Ok (Scan (list (Pending keyword form annotations)) bound))))
        ((Nil) (fail (marked-loc form) "expected a declaration"))))

    (: declaration-names
       (impl (Fn Scopes String Marked (List Marked) Marked -> (Result Scopes (List Feedback)))))
    (define (declaration-names scopes keyword head rest form)
      (cond ((string=? keyword "struct") (scan-struct scopes head form))
            ((string=? keyword "enum") (scan-enum scopes head form))
            ((string=? keyword "type") (scan-alias scopes head rest form))
            ((string=? keyword "typeclass") (scan-class scopes head rest))
            ((string=? keyword "extern")
             (result-let* ((name (refused (named head "a name"))))
               (bind-value scopes name)))
            ((string=? keyword "effect") (scan-effect scopes head rest form))
            (else (Ok scopes))))

    ;; ---- Structs and enums ----

    (: scan-struct (impl (Fn Scopes Marked Marked -> (Result Scopes (List Feedback)))))
    (define (scan-struct scopes head form)
      (result-let* ((name (refused (declared-name head)))
                    (params (refused (declared-params head)))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (TypeName (top-global scopes (::identifier name)) #t)))
                    (fields (refused (struct-fields form))))
        (bind-fields bound name (top-global scopes (::identifier name)) fields #t)))

    (: scan-enum (impl (Fn Scopes Marked Marked -> (Result Scopes (List Feedback)))))
    (define (scan-enum scopes head form)
      (result-let* ((name (refused (declared-name head)))
                    (params (refused (declared-params head)))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (TypeName (top-global scopes (::identifier name)) #f))))
        (let loop ((scopes bound)
                   (cases (enum-cases form)))
          (match cases
            ((Nil) (Ok scopes))
            ((Cons case rest)
             (result-let* ((parts (refused (case-form case)))
                           (with-case (bind-value scopes (::name parts)))
                           (with-fields (bind-fields with-case
                                                     (::name parts)
                                                     (top-global scopes
                                                                 (::identifier (::name parts)))
                                                     (::fields parts)
                                                     #f)))
               (loop with-fields rest)))))))

    ;; Every field is parsed, then each is checked to be allowed mutable,
    ;; then each binds its functions in order: a struct with no mutable
    ;; field reserves its field's accessor name.
    (: bind-fields
       (impl (Fn Scopes Named Global (List Marked) Bool -> (Result Scopes (List Feedback)))))
    (define (bind-fields scopes owner case fields struct?)
      (result-let* ((parsed (map-results (lambda (field) (refused (field-form field))) fields))
                    (allowed (map-results (lambda (field) (mutable-allowed scopes field)) parsed)))
        (let ((pure? (not (any? ::mutable? parsed))))
          (let loop ((scopes scopes)
                     (parsed parsed))
            (match parsed
              ((Nil) (Ok scopes))
              ((Cons field rest)
               (result-let* ((bound (bind-field scopes owner case field struct? pure?)))
                 (loop bound rest))))))))

    ;; Only Ref, in (snail core base), and the runtime's UnsafeSlot, in
    ;; (snail shell slot), have a mutable field.
    (: mutable-allowed (impl (Fn Scopes FieldForm -> (Result Bool (List Feedback)))))
    (define (mutable-allowed scopes field)
      (if (and (::mutable? field)
               (not (any? (lambda (library) (same-library? library (::library scopes)))
                          (list (list "snail" "core" "base") (list "snail" "shell" "slot")))))
          (fail (marked-loc (::name field))
                "only Ref and the runtime's UnsafeSlot have a mutable field; hold the struct in a cell and write its fields with set!")
          (Ok #t)))

    (: bind-field
       (impl (Fn Scopes Named Global FieldForm Bool Bool -> (Result Scopes (List Feedback)))))
    (define (bind-field scopes owner case field struct? pure?)
      (result-let* ((label (refused (named (::name field) "a field name")))
                    (reserved (if (and struct? pure?)
                                  (bind scopes
                                        (field-identifier owner label "")
                                        (::loc label)
                                        (ReservedAccessor))
                                  (Ok scopes)))
                    (roles (field-roles field struct? pure?)))
        (let loop ((scopes reserved)
                   (roles roles))
          (match roles
            ((Nil) (Ok scopes))
            ((Cons role rest)
             (result-let* ((bound (bind scopes
                                        (field-identifier owner label (::first role))
                                        (::loc label)
                                        (Value (FieldFunction case
                                                              (::name (::identifier label))
                                                              (::second role))))))
               (loop bound rest)))))))

    ;; `Owner-field` and its suffix.
    (: field-identifier (impl (Fn Named Named String -> Identifier)))
    (define (field-identifier owner label suffix)
      (suffixed (::identifier owner) (string-append "-" (::name (::identifier label)) suffix)))

    ;; The functions a field has, by their names' suffixes. A struct with
    ;; no mutable field is a value read by path, so its fields have only a
    ;; Replacer; a mutable field, which only Ref and UnsafeSlot have, an
    ;; Accessor, a Setter and a Swapper; an enum's, an Accessor.
    (: field-roles
       (impl (Fn FieldForm Bool Bool -> (Result (List (Pair String FieldRole)) (List Feedback)))))
    (define (field-roles field struct? pure?)
      (cond ((and (::mutable? field) (not struct?))
             (fail (marked-loc (::name field))
                   "an enum's fields cannot be mutable; hold a struct with a mutable field in the case"))
            ((::mutable? field)
             (Ok (list (Pair "" (Accessor)) (Pair "-set!" (Setter)) (Pair "-replace!" (Swapper)))))
            ((and struct? pure?) (Ok (list (Pair "-set" (Replacer)))))
            (else (Ok (list (Pair "" (Accessor)))))))

    ;; A struct with a mutable field has identity, so it derives nothing
    ;; but Move; every class a clause names must be one `derive` knows.
    (: derivations-of (impl (Fn String Marked -> (Result (List Derivation) (List Feedback)))))
    (define (derivations-of keyword form)
      (if (or (string=? keyword "struct") (string=? keyword "enum"))
          (result-let* ((identity (identity-checked keyword form)))
            (map-results (lambda (class) (refused (derivation class))) (derived-classes form)))
          (Ok (Nil))))

    (: identity-checked (impl (Fn String Marked -> (Result Bool (List Feedback)))))
    (define (identity-checked keyword form)
      (if (string=? keyword "struct")
          (result-let* ((fields (refused (struct-fields form)))
                        (parsed (map-results (lambda (field) (refused (field-form field))) fields)))
            (if (and (any? (lambda (class) (not (move? class))) (derived-classes form))
                     (any? ::mutable? parsed))
                (fail (marked-loc form)
                      "a struct with a mutable field has identity, so it cannot derive an instance")
                (Ok #t)))
          (Ok #t)))

    (: move? (impl (Fn Marked -> Bool)))
    (define (move? class)
      (match class
        ((Ident (Identifier "Move" _) _) #t)
        (_ #f)))

    ;; ---- Aliases, classes and effects ----

    ;; An alias's body resolves at this top level, where it is used.
    (: scan-alias
       (impl (Fn Scopes Marked (List Marked) Marked -> (Result Scopes (List Feedback)))))
    (define (scan-alias scopes head rest form)
      (result-let* ((name (refused (declared-name head)))
                    (body (refused (alias-body rest form)))
                    (params (refused (declared-params head))))
        (bind scopes
              (::identifier name)
              (::loc name)
              (TypeAlias (top-global scopes (::identifier name))
                         (map ::identifier params)
                         body
                         (::library scopes)))))

    ;; A class binds its name, each method, and each associated output as
    ;; `Class.Output`, once its parameters and outputs are found distinct.
    (: scan-class (impl (Fn Scopes Marked (List Marked) -> (Result Scopes (List Feedback)))))
    (define (scan-class scopes head members)
      (result-let* ((name (refused (declared-name head)))
                    (outputs (map-results (lambda (member) (refused (associated-name member)))
                                          (filter associated-form? members)))
                    (params (refused (declared-params head)))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (ClassName (top-global scopes (::identifier name)))))
                    (distinct (distinct-parameters (append params outputs) (marked-loc head))))
        (let loop ((scopes bound)
                   (members members))
          (match members
            ((Nil) (Ok scopes))
            ((Cons member rest)
             (result-let* ((with-member (scan-member scopes name member)))
               (loop with-member rest)))))))

    (: distinct-parameters (impl (Fn (List Named) Loc -> (Result Bool (List Feedback)))))
    (define (distinct-parameters names loc)
      (let ((written (map (lambda (name) (::name (::identifier name))) names)))
        (if (= (length written) (length (delete-duplicates string=? written)))
            (Ok #t)
            (fail loc "class parameters and associated types must be distinct"))))

    ;; A member's annotation list is split off, and what it annotates
    ;; named, before the member is looked at.
    (: scan-member (impl (Fn Scopes Named Marked -> (Result Scopes (List Feedback)))))
    (define (scan-member scopes class member)
      (let ((associated? (associated-form? member)))
        (result-let* ((split (refused (split-annotations member (if associated? 2 3))))
                      (owner (if associated?
                                 (refused (associated-name (::form split)))
                                 (result-let* ((head (refused (declaration-head (::form split)))))
                                   (refused (declared-name head))))))
          (if associated?
              (bind scopes
                    (suffixed (::identifier class)
                              (string-append "." (::name (::identifier owner))))
                    (marked-loc (::form split))
                    (Associated (top-global scopes (::identifier class))
                                (::name (::identifier owner))))
              (match (method-form (::form split))
                ((Some (Pair method _))
                 (result-let* ((name (refused (named method "a name"))))
                   (bind-value scopes name)))
                ((None)
                 (fail (marked-loc (::form split))
                       "expected (: method type) or (type Output)")))))))

    (: scan-effect
       (impl (Fn Scopes Marked (List Marked) Marked -> (Result Scopes (List Feedback)))))
    (define (scan-effect scopes head rest form)
      (result-let* ((name (refused (named head "an effect name")))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (EffectName (top-global scopes (::identifier name)))))
                    (operations (refused (effect-operations rest form))))
        (let loop ((scopes bound)
                   (operations operations))
          (match operations
            ((Nil) (Ok scopes))
            ((Cons operation more)
             (result-let* ((parts (refused (operation-form operation)))
                           (operation-name (refused (named (::name parts) "a name")))
                           (with-operation (bind-value scopes operation-name)))
               (loop with-operation more)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-scan)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (prefix (snail compiler read language) syntax-)
     (snail compiler expand forms)
     (snail stage0 testing))
    (begin
      (define (test-scan)
        (test-binding)
        (test-declarations)
        (test-order))

      (define main (list "main"))

      (define (at column)
        (Loc "t.sld" 1 column))

      (define loc (at 1))

      (define (marked datum)
        (cond ((or (null? datum) (pair? datum)) (Form (map marked datum) loc))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) loc))
              ((string? datum) (Atom (syntax-Text datum) loc))
              ((exact-integer? datum) (Atom (syntax-Integer datum) loc))
              (else (panic "no syntax for this datum"))))

      ;; A library that imports (snail core forms) whole.
      (define (scopes-of library)
        (Scopes library
                (TopScope empty-table
                          (fold-left (lambda (table export)
                                       (table-set table
                                                  (::name export)
                                                  (list (Binding (Identifier (::name export) (Nil))
                                                                 (::meaning export)))))
                                     empty-table
                                     (::exports forms-offer)))
                (list (Offered forms-library forms-offer))))

      (define (scanned library forms)
        (match (scan-forms (Expanding 1) (scopes-of library) (list) (map marked forms))
          ((Ok (Pair scan _)) (Ok scan))
          ((Err feedback) (Err feedback))))

      ;; What `name` means at the top level the scan leaves.
      (define (meaning forms name)
        (match (scanned main forms)
          ((Ok scan)
           (match (resolve (::scopes scan) (Env (list) main) (Identifier name (list)))
             ((BoundAtTop found) (Some found))
             (_ (None))))
          ((Err feedback) (None))))

      (define (global name)
        (Global main name 0))

      (define (problem forms)
        (match (scanned main forms)
          ((Ok _) (list))
          ((Err feedback) (map ::message feedback))))

      (define (test-binding)
        (expect (meaning '((define x 1)) "x") (Some (Value (TopGlobal (global "x")))))
        (expect (meaning '((begin (define x 1) (define y 2))) "y")
                (Some (Value (TopGlobal (global "y")))))
        (expect (problem '((define x 1) (define x 2))) (list "duplicate top-level definition x"))
        (expect (problem '((primitive p I64)))
                (list "primitives are declared only in (snail core primitive)"))
        (expect (problem '((struct))) (list "expected a declaration"))
        (expect (match (meaning '((define-syntax m (syntax-rules () ((_) 1)))) "m")
                  ((Some (MacroRules macro)) (::number (::id macro)))
                  (_ 0))
                1)
        (expect (meaning '((define-instance-set s (instance (Show I64)))) "s")
                (Some (InstanceSetName (global "s"))))
        (expect (problem '((define-instance-set s (define x 1))))
                (list "an instance set contains instance or dynamic-instances declarations")))

      (define (test-declarations)
        (expect (meaning '((struct P
                             ((x I64)))) "P") (Some (TypeName (global "P") #t)))
        (expect (meaning '((struct P
                             ((x I64)))) "P-x-set")
                (Some (Value (FieldFunction (global "P") "x" (Replacer)))))
        (expect (meaning '((struct P
                             ((x I64)))) "P-x") (Some (ReservedAccessor)))
        (expect (problem '((struct P
                             ((x mut I64)))))
                (list
                 "only Ref and the runtime's UnsafeSlot have a mutable field; hold the struct in a cell and write its fields with set!"))
        (expect (meaning '((enum E (A ((v I64))))) "A-v")
                (Some (Value (FieldFunction (global "A") "v" (Accessor)))))
        (expect (meaning '((enum E (A ((v I64))))) "E") (Some (TypeName (global "E") #f)))
        (expect (meaning '((typeclass (C a) (type Out) (: m (Fn a -> Out)))) "C.Out")
                (Some (Associated (global "C") "Out")))
        (expect (meaning '((typeclass (C a) (: m (Fn a -> a)))) "m")
                (Some (Value (TopGlobal (global "m")))))
        (expect (problem '((typeclass (C a) (type a))))
                (list "class parameters and associated types must be distinct"))
        (expect (problem '((typeclass (C a) (define x 1))))
                (list "expected (: method type) or (type Output)"))
        (expect (meaning '((effect E ((read (Fn -> I64))))) "read")
                (Some (Value (TopGlobal (global "read")))))
        (expect (meaning '((extern f "m" "s" I64)) "f") (Some (Value (TopGlobal (global "f")))))
        (expect (problem '((struct P
                             () (deriving Show))))
                (list "only Move, Serialize and Deserialize can be derived"))
        (expect (problem '((struct (P 1)))) (list "expected a type parameter"))
        (expect (problem '((: f I64 (annotations (doc 1)))))
                (list "doc needs exactly one literal string")))

      ;; Items keep the order written; a scope holds what it encloses.
      (define (test-order)
        (match (scanned main '((define x 1) (with-instances (s) (f x)) (: x I64)))
          ((Ok scan)
           (expect (map (lambda (item)
                          (match item
                            ((Pending keyword _ _) keyword)
                            ((PendingScope _ items _)
                             (string-append "scope " (i64->string (length items))))
                            ((PendingSet _ _ _) "set")))
                        (::items scan))
                   (list "define" "scope 1" ":")))
          ((Err feedback) (expect feedback (list)))))))
   (else)))
