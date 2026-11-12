;; Who may take apart a value of a type with a Drop instance, or replace
;; its fields: only the type's own library, which the instance trusts to
;; release what a value holds. Elsewhere a value of it is dropped, or given
;; to a function of its library. This is the old compiler's
;; `check-own-library` (src/snail/shell/compiler/expand.sld), which
;; `pattern-constructor` asks of a pattern's constructor and of a
;; `case-id`'s, and `expand-reference` of a reference to a replacer,
;; `Name-field-set`. Only a type of another library is refused, and a
;; body reads whether it has a Drop instance once every declaration is
;; reached, so the type's mark is made.
(define-library (snail compiler declare owned)
  (export
   destructure-problem
   reference-problem)
  (import
   (snail core base)
   (snail compiler names libraries)
   (only (snail compiler names globals) TopValue TopGlobal FieldFunction Replacer)
   (snail compiler declare language)
   (snail compiler declare known))
  (begin

    ;; ---- Owned types ----

    ;; What a body does to a value: take it apart, or replace a field.
    (enum Handling
      (Destructuring)
      (Replacing))

    (: owned-problem (impl (Fn Known Data Handling -> (Option String))))
    (define (owned-problem known data handling)
      (if (and (::drop? data) (not (same-library? (::library (::global data)) (::library known))))
          (Some (string-append (::name (::global data))
                               " has a Drop instance, so only its own library can "
                               (match handling
                                 ((Destructuring) "take it apart; drop it instead")
                                 ((Replacing) "replace its fields"))))
          (None)))

    ;; ---- Uses ----

    ;; A pattern's or a `case-id`'s constructor, when it is one.
    (: destructure-problem (impl (Fn Known TopValue -> (Option String))))
    (define (destructure-problem known constructor)
      (match constructor
        ((TopGlobal global)
         (match (constructor-case known global)
           ((Some found) (owned-problem known (::first found) (Destructuring)))
           ((None) (None))))
        ((FieldFunction _ _ _) (None))))

    ;; A reference to a value, when it is a replacer of a struct's field.
    (: reference-problem (impl (Fn Known TopValue -> (Option String))))
    (define (reference-problem known value)
      (match value
        ((FieldFunction case _ (Replacer))
         (match (constructor-case known case)
           ((Some found) (owned-problem known (::first found) (Replacing)))
           ((None) (None))))
        (_ (None))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-owned)
    (import
     (snail core table)
     (snail compiler source)
     (only (snail compiler names globals) Local Global Accessor)
     (snail compiler declare offer)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-owned)
        (test-destructuring)
        (test-replacing))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define handles (list "owned" "handle"))
      (define i64 (Con (Global forms-library "I64" 0) (list)))

      (define (struct-data library name drop?)
        (let ((global (Global library name 0)))
          (Data global
                (list)
                (list (DataCase global 0 (list (DataField "name" #f i64 (list) loc)) (list) loc))
                (StructData)
                drop?
                drop?
                (list)
                loc)))

      ;; (owned handle) offers Handle, with a Drop instance, and Plain,
      ;; without; (main) declares Local, with one.
      (define known
        (Known main
               (Scanned empty-table empty-table)
               (Declarations main
                             (by-name empty-table "Local" (struct-data main "Local" #t))
                             empty-table
                             empty-table)
               (list (Declarations handles
                                   (by-name (by-name empty-table
                                                     "Handle"
                                                     (struct-data handles "Handle" #t))
                                            "Plain"
                                            (struct-data handles "Plain" #f))
                                   empty-table
                                   empty-table))))

      (define handle (Global handles "Handle" 0))

      ;; Read off error-drop-match.sld.
      (define (test-destructuring)
        (expect (destructure-problem known (TopGlobal handle))
                (Some
                 "Handle has a Drop instance, so only its own library can take it apart; drop it instead"))
        (expect (destructure-problem known (TopGlobal (Global handles "Plain" 0))) (None))
        (expect (destructure-problem known (TopGlobal (Global main "Local" 0))) (None))
        (expect (destructure-problem known (TopGlobal (Global handles "rename" 0))) (None))
        (expect (destructure-problem known (FieldFunction handle "name" (Replacer))) (None)))

      ;; Read off error-replace-owned.sld: a replacer only.
      (define (test-replacing)
        (expect (reference-problem known (FieldFunction handle "name" (Replacer)))
                (Some "Handle has a Drop instance, so only its own library can replace its fields"))
        (expect (reference-problem known (FieldFunction handle "name" (Accessor))) (None))
        (expect (reference-problem known (FieldFunction (Global main "Local" 0) "name" (Replacer)))
                (None))
        (expect (reference-problem known (TopGlobal handle)) (None)))))
   (else)))
