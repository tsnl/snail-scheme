;; The top level's first pass: every name it defines, bound in the order
;; written, so a definition may refer to a later one. Each form's head is
;; expanded first, while it names a macro; a `begin` is spliced, and a
;; `with-instances` scans its forms under its sets. A `define-syntax`
;; binds its macro, which the forms after it may use. A declaration binds
;; its names: a type, a struct's constructor and its fields' functions,
;; an enum's cases and theirs, a class with its methods and outputs, an
;; effect with its operations, an extern. Each form becomes an Item of its
;; kind, holding the shape the scan took it apart into, for the passes
;; after this, which read that shape and never the form. The first
;; problem stops the scan, as it stops the old expander's, since what
;; follows needs every name.
(define-library (snail compiler expand scan)
  (export
   Item
   PendingDefinition
   PendingSignature
   PendingStruct
   PendingEnum
   PendingAlias
   PendingClass
   PendingInstance
   PendingDynamic
   PendingExtern
   PendingEffect
   PendingExpose
   PendingStatement
   PendingScope
   PendingSet
   Head
   ScannedField
   ScannedCase
   ScannedMember
   ScannedOutput
   ScannedMethod
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

    ;; A form the scan found, as an item of its kind, holding the shape the
    ;; scan took it apart into, with its types and bodies still syntax.
    ;; Some shapes the old expander checks only after the scan: with the
    ;; declarations, a signature's, an instance's, a dynamic instances',
    ;; an extern's after its name and an effect's clauses; with the
    ;; bodies, an expose's. Each of those waits as its rule's answer,
    ;; malformed or not, for that step to report. A statement is any form
    ;; no keyword declares. A top-level `with-instances` holds the items
    ;; written under its sets, and an instance set those its declarations
    ;; are.
    (enum Item
      (PendingDefinition
       ((global Global)
        (value DefinedValue)
        (loc Loc)))
      (PendingSignature
       ((shape SignatureShape)
        (annotations (List Annotation))
        (loc Loc)))
      (PendingStruct
       ((head Head)
        (fields (List ScannedField))
        (derivations (List Derivation))))
      (PendingEnum
       ((head Head)
        (cases (List ScannedCase))
        (derivations (List Derivation))))
      (PendingAlias
       ((head Head)))
      (PendingClass
       ((head Head)
        (members (List ScannedMember))))
      (PendingInstance
       ((shape (Result InstanceForm Malformed))))
      (PendingDynamic
       ((shape (Result DynamicForm Malformed))))
      (PendingExtern
       ((head Head)
        (shape (Result ExternForm Malformed))))
      (PendingEffect
       ((head Head)
        (operations (List OperationForm))
        (clauses (Result EffectClauses Malformed))))
      (PendingExpose
       ((shape (Result ExposeForm Malformed))))
      (PendingStatement
       ((form Marked)))
      (PendingScope
       ((sets (List Marked))
        (items (List Item))
        (loc Loc)))
      (PendingSet
       ((global Global)
        (items (List Item))
        (loc Loc))))

    ;; What a declaration says of itself: the name it declares, the
    ;; parameters its types are written over, none for an effect or an
    ;; extern, its annotations, and where it is.
    (struct Head
      ((name Named)
       (params (List Named))
       (annotations (List Annotation))
       (loc Loc)))

    ;; A field once its functions are bound, so its label is a name.
    (struct ScannedField
      ((label Named)
       (mutable? Bool)
       (type Marked)
       (annotations (List Annotation))))

    (struct ScannedCase
      ((name Named)
       (fields (List ScannedField))
       (annotations (List Annotation))))

    ;; A class's member, in the order written.
    (enum ScannedMember
      (ScannedOutput
       ((output OutputForm)))
      (ScannedMethod
       ((method MethodForm))))

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
               (unchanged state (item-found (PendingStatement form) scopes))))
          ((None) (unchanged state (item-found (PendingStatement form) scopes))))))

    (: declaration-keywords (List String))
    (define declaration-keywords
      (list ":" "struct" "enum" "type" "typeclass" "instance" "extern" "effect" "expose"))

    (: item-found (impl (Fn Item Scopes -> (Result Scan (List Feedback)))))
    (define (item-found item scopes)
      (Ok (Scan (list item) scopes)))

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
             (unchanged state
                        (item-found (PendingDynamic (dynamic-instances-form declaration)) scopes)))
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
        ((NamedDefinition name name-loc value)
         (result-let* ((bound (bind-value scopes (Named name name-loc))))
           (item-found (PendingDefinition (top-global scopes name) value (marked-loc form)) bound)))
        ((MalformedDefinition place message) (fail place message))))

    ;; A declaration binds its names and is found as its kind. What a
    ;; signature, an instance and an expose say is checked after the scan.
    (: scan-declared
       (impl (Fn Scopes String Marked (List Annotation) -> (Result Scan (List Feedback)))))
    (define (scan-declared scopes keyword form annotations)
      (match (form-tail form)
        ((Cons head rest) (declaration-item scopes keyword head rest form annotations))
        ((Nil) (fail (marked-loc form) "expected a declaration"))))

    (: declaration-item
       (impl (Fn Scopes String Marked (List Marked) Marked (List Annotation)
                 -> (Result Scan (List Feedback)))))
    (define (declaration-item scopes keyword head rest form annotations)
      (match keyword
        (":"
         (item-found (PendingSignature (signature-shape form) annotations (marked-loc form))
                     scopes))
        ("struct" (scan-struct scopes head form annotations))
        ("enum" (scan-enum scopes head form annotations))
        ("type" (scan-alias scopes head rest form annotations))
        ("typeclass" (scan-class scopes head rest form annotations))
        ("instance" (item-found (PendingInstance (instance-form form)) scopes))
        ("extern" (scan-extern scopes head form annotations))
        ("effect" (scan-effect scopes head rest form annotations))
        ;; `expose`, the last of the declaration keywords.
        (_ (item-found (PendingExpose (expose-form form)) scopes))))

    ;; ---- Structs and enums ----

    ;; A struct binds its name, then its fields' functions; then its
    ;; deriving clauses are checked, which `derive` makes instances of.
    (: scan-struct
       (impl (Fn Scopes Marked Marked (List Annotation) -> (Result Scan (List Feedback)))))
    (define (scan-struct scopes head form annotations)
      (result-let* ((name (refused (declared-name head)))
                    (params (refused (declared-params head)))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (TypeName (top-global scopes (::identifier name)) #t)))
                    (written (refused (struct-fields form)))
                    (fields
                     (bind-fields bound name (top-global scopes (::identifier name)) written #t))
                    (derivations (derivations-of form (any? ::mutable? (::second fields)))))
        (item-found (PendingStruct (Head name params annotations (marked-loc form))
                                   (::second fields)
                                   derivations)
                    (::first fields))))

    ;; An enum binds its name, then each case and its fields' functions,
    ;; in order; then its deriving clauses are checked.
    (: scan-enum
       (impl (Fn Scopes Marked Marked (List Annotation) -> (Result Scan (List Feedback)))))
    (define (scan-enum scopes head form annotations)
      (result-let* ((name (refused (declared-name head)))
                    (params (refused (declared-params head)))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (TypeName (top-global scopes (::identifier name)) #f)))
                    (cases (scan-cases bound (enum-cases form)))
                    (derivations (derivations-of form #f)))
        (item-found (PendingEnum (Head name params annotations (marked-loc form))
                                 (::second cases)
                                 derivations)
                    (::first cases))))

    (: scan-cases
       (impl (Fn Scopes (List Marked)
                 -> (Result (Pair Scopes (List ScannedCase)) (List Feedback)))))
    (define (scan-cases scopes cases)
      (let loop ((scopes scopes)
                 (cases cases)
                 (scanned (Nil)))
        (match cases
          ((Nil) (Ok (Pair scopes (reverse scanned))))
          ((Cons case rest)
           (result-let* ((parts (refused (case-form case)))
                         (with-case (bind-value scopes (::name parts)))
                         (fields (bind-fields with-case
                                              (::name parts)
                                              (top-global scopes (::identifier (::name parts)))
                                              (::fields parts)
                                              #f)))
             (loop (::first fields)
                   rest
                   (Cons (ScannedCase (::name parts) (::second fields) (::annotations parts))
                         scanned)))))))

    ;; Every field is parsed, then each is checked to be allowed mutable,
    ;; then each, its label named, binds its functions in order: a struct
    ;; with no mutable field reserves its field's accessor name.
    (: bind-fields
       (impl (Fn Scopes Named Global (List Marked) Bool
                 -> (Result (Pair Scopes (List ScannedField)) (List Feedback)))))
    (define (bind-fields scopes owner case fields struct?)
      (result-let* ((parsed (map-results (lambda (field) (refused (field-form field))) fields))
                    (allowed (map-results (lambda (field) (mutable-allowed scopes field)) parsed)))
        (let ((pure? (not (any? ::mutable? parsed))))
          (let loop ((scopes scopes)
                     (parsed parsed)
                     (scanned (Nil)))
            (match parsed
              ((Nil) (Ok (Pair scopes (reverse scanned))))
              ((Cons field rest)
               (result-let* ((label (refused (named (::name field) "a field name")))
                             (bound (bind-field scopes owner case label field struct? pure?)))
                 (loop bound
                       rest
                       (Cons (ScannedField label
                                           (::mutable? field)
                                           (::type field)
                                           (::annotations field))
                             scanned)))))))))

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
       (impl (Fn Scopes Named Global Named FieldForm Bool Bool -> (Result Scopes (List Feedback)))))
    (define (bind-field scopes owner case label field struct? pure?)
      (result-let* ((reserved (if (and struct? pure?)
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

    ;; The classes the deriving clauses name, each one `derive` knows. A
    ;; struct with a mutable field has identity, so it derives nothing but
    ;; Move.
    (: derivations-of (impl (Fn Marked Bool -> (Result (List Derivation) (List Feedback)))))
    (define (derivations-of form identity?)
      (if (and identity? (any? (lambda (class) (not (move? class))) (derived-classes form)))
          (fail (marked-loc form)
                "a struct with a mutable field has identity, so it cannot derive an instance")
          (map-results (lambda (class) (refused (derivation class))) (derived-classes form))))

    (: move? (impl (Fn Marked -> Bool)))
    (define (move? class)
      (match class
        ((Ident (Identifier "Move" _) _) #t)
        (_ #f)))

    ;; ---- Aliases, classes and effects ----

    ;; An alias's body resolves at this top level, where it is used.
    (: scan-alias
       (impl (Fn Scopes Marked (List Marked) Marked (List Annotation)
                 -> (Result Scan (List Feedback)))))
    (define (scan-alias scopes head rest form annotations)
      (result-let* ((name (refused (declared-name head)))
                    (body (refused (alias-body rest form)))
                    (params (refused (declared-params head)))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (TypeAlias (top-global scopes (::identifier name))
                                            (map ::identifier params)
                                            body
                                            (::library scopes)))))
        (item-found (PendingAlias (Head name params annotations (marked-loc form))) bound)))

    ;; A class binds its name, then each member in order, a method as a
    ;; value and an associated output as `Class.Output`, once its
    ;; parameters and outputs are found distinct. Its outputs are taken
    ;; apart before its parameters, its methods where they are bound.
    (: scan-class
       (impl (Fn Scopes Marked (List Marked) Marked (List Annotation)
                 -> (Result Scan (List Feedback)))))
    (define (scan-class scopes head members form annotations)
      (result-let* ((name (refused (declared-name head)))
                    (written (map-results (lambda (member) (written-member member)) members))
                    (params (refused (declared-params head)))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (ClassName (top-global scopes (::identifier name)))))
                    (distinct (distinct-parameters (append params (output-names written))
                                                   (marked-loc head)))
                    (scanned (scan-members bound name written)))
        (item-found
         (PendingClass (Head name params annotations (marked-loc form)) (::second scanned))
         (::first scanned))))

    ;; A member, with its output when it is one.
    (: written-member
       (impl (Fn Marked -> (Result (Pair Marked (Option OutputForm)) (List Feedback)))))
    (define (written-member member)
      (if (associated-form? member)
          (result-let* ((output (refused (output-form member))))
            (Ok (Pair member (Some output))))
          (Ok (Pair member (None)))))

    (: output-names (impl (Fn (List (Pair Marked (Option OutputForm))) -> (List Named))))
    (define (output-names written)
      (match written
        ((Nil) (Nil))
        ((Cons (Pair _ (Some output)) rest) (Cons (::name output) (output-names rest)))
        ((Cons _ rest) (output-names rest))))

    (: distinct-parameters (impl (Fn (List Named) Loc -> (Result Bool (List Feedback)))))
    (define (distinct-parameters names loc)
      (let ((written (map (lambda (name) (::name (::identifier name))) names)))
        (if (= (length written) (length (delete-duplicates string=? written)))
            (Ok #t)
            (fail loc "class parameters and associated types must be distinct"))))

    (: scan-members
       (impl (Fn Scopes Named (List (Pair Marked (Option OutputForm)))
                 -> (Result (Pair Scopes (List ScannedMember)) (List Feedback)))))
    (define (scan-members scopes class written)
      (let loop ((scopes scopes)
                 (written written)
                 (scanned (Nil)))
        (match written
          ((Nil) (Ok (Pair scopes (reverse scanned))))
          ((Cons (Pair member output) rest)
           (result-let* ((next (scan-member scopes class member output)))
             (loop (::first next) rest (Cons (::second next) scanned)))))))

    (: scan-member
       (impl (Fn Scopes Named Marked (Option OutputForm)
                 -> (Result (Pair Scopes ScannedMember) (List Feedback)))))
    (define (scan-member scopes class member output)
      (match output
        ((Some form)
         (result-let* ((bound (bind scopes
                                    (suffixed (::identifier class)
                                              (string-append "."
                                                             (::name (::identifier (::name form)))))
                                    (::loc form)
                                    (Associated (top-global scopes (::identifier class))
                                                (::name (::identifier (::name form)))))))
           (Ok (Pair bound (ScannedOutput form)))))
        ((None)
         (result-let* ((method (refused (method-form member)))
                       (bound (bind-value scopes (::name method))))
           (Ok (Pair bound (ScannedMethod method)))))))

    ;; An effect binds its name, then each operation in order. Its clauses
    ;; are checked with the declarations.
    (: scan-effect
       (impl (Fn Scopes Marked (List Marked) Marked (List Annotation)
                 -> (Result Scan (List Feedback)))))
    (define (scan-effect scopes head rest form annotations)
      (result-let* ((name (refused (named head "an effect name")))
                    (bound (bind scopes
                                 (::identifier name)
                                 (::loc name)
                                 (EffectName (top-global scopes (::identifier name)))))
                    (parts (refused (effect-form rest form)))
                    (operations (scan-operations bound (::operations parts))))
        (item-found (PendingEffect (Head name (Nil) annotations (marked-loc form))
                                   (::second operations)
                                   (effect-clauses (::clauses parts)))
                    (::first operations))))

    (: scan-operations
       (impl (Fn Scopes (List Marked)
                 -> (Result (Pair Scopes (List OperationForm)) (List Feedback)))))
    (define (scan-operations scopes operations)
      (let loop ((scopes scopes)
                 (operations operations)
                 (scanned (Nil)))
        (match operations
          ((Nil) (Ok (Pair scopes (reverse scanned))))
          ((Cons operation more)
           (result-let* ((parts (refused (operation-form operation)))
                         (bound (bind-value scopes (::name parts))))
             (loop bound more (Cons parts scanned)))))))

    ;; An extern binds its name; what follows it is checked with the
    ;; declarations.
    (: scan-extern
       (impl (Fn Scopes Marked Marked (List Annotation) -> (Result Scan (List Feedback)))))
    (define (scan-extern scopes head form annotations)
      (result-let* ((name (refused (named head "a name")))
                    (bound (bind-value scopes name)))
        (item-found
         (PendingExtern (Head name (Nil) annotations (marked-loc form)) (extern-form form))
         bound)))

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
        (test-order)
        (test-items))

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
                            ((PendingDefinition _ _ _) "define")
                            ((PendingSignature _ _ _) ":")
                            ((PendingStatement _) "statement")
                            ((PendingScope _ items _)
                             (string-append "scope " (i64->string (length items))))
                            (_ "other")))
                        (::items scan))
                   (list "define" "scope 1" ":")))
          ((Err feedback) (expect feedback (list)))))

      ;; Each item holds its shape, and a shape checked after the scan
      ;; waits in it, malformed.
      (define (test-items)
        (match (scanned main '((struct P
                                 ((x I64))) (instance Show) (effect E () (bad))))
          ((Ok scan)
           (match (::items scan)
             ((Cons (PendingStruct head (Cons field (Nil)) _)
                    (Cons (PendingInstance shape) (Cons (PendingEffect _ (Nil) clauses) (Nil))))
              (expect (::name head) (Named (Identifier "P" (Nil)) loc))
              (expect (::label field) (Named (Identifier "x" (Nil)) loc))
              (expect shape
                      (Err (Malformed loc "expected (instance (Class type ...) definition ...)")))
              (expect clauses (Err (Malformed loc "expected a default clause or (around-main)"))))
             (other (expect other "a struct, an instance and an effect"))))
          ((Err feedback) (expect feedback (list)))))))
   (else)))
