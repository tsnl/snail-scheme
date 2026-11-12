;; A case's TypeId, the identity a `case-id` writes, which the wire format
;; carries before a case's fields: FNV-1a over the case's schema, its name
;; and each field's name and type, with each field type's own cases, cut
;; where a type is reached again, as a signed 32-bit value. This is the old
;; compiler's `case-type-id` (src/snail/shell/compiler/core.sld), so the
;; identity changes exactly when the encoded shape can.
;;
;; The schema is a wire format, hashed and never looked up, and it must be
;; spelled as the old compiler spells it, or wire data an old program wrote
;; stops reading, so each Global in it is spelled as (snail compiler
;; declare spellings) says.
(define-library (snail compiler declare identities)
  (export
   case-type-id)
  (import
   (snail core base)
   (only (snail compiler source) fnv-1a)
   (only (snail compiler expand language) Impl Dyn FnContract FnMutContract FnOnceContract)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare equality)
   (only (snail compiler names globals) Global same-global?)
   (only (snail compiler names spellings) global-spelling))
  (begin

    ;; ---- Identities ----

    ;; The TypeId of `case`, a case of `data`, where every type its fields
    ;; name is known.
    (: case-type-id (impl (Fn Known Data DataCase -> I64)))
    (define (case-type-id known data case)
      (type-id (case-schema known data case (Nil))))

    ;; The hash, (snail compiler source)'s FNV-1a, as a signed 32-bit
    ;; value, which Wasm's i32 holds.
    (: type-id (impl (Fn String -> I64)))
    (define (type-id text)
      (let ((hash (fnv-1a text)))
        (if (>= hash 2147483648) (- hash 4294967296) hash)))

    ;; ---- Schemas ----

    ;; `Name(field:type;...)`, the types seen from `data`, which is being
    ;; visited, so a field of its own type is cut there.
    (: case-schema (impl (Fn Known Data DataCase (List Global) -> String)))
    (define (case-schema known data case visiting)
      (let ((inside (Cons (::global data) visiting)))
        (string-append (global-spelling (::global case))
                       "("
                       (string-concatenate
                        (map (lambda (field)
                               (string-append (::label field)
                                              (if (::mutable? field) " mut:" ":")
                                              (type-schema known
                                                           (::type field)
                                                           (::parameters data)
                                                           inside)
                                              ";"))
                             (::fields case)))
                       ")")))

    ;; A parameter by its position, so renaming it keeps the identity; a
    ;; data type with its arguments and then its cases, unless it is being
    ;; visited; any type but a data type or a builtin as the old compiler's
    ;; type writes it: a function as `fn`, a callable that holds one as
    ;; that type at `fn`, and a row as `fn`.
    (: type-schema (impl (Fn Known Type (List String) (List Global) -> String)))
    (define (type-schema known type parameters visiting)
      (match type
        ((Var (Written name))
         (match (list-index (lambda (parameter) (string=? parameter name)) parameters)
           ((Some index) (string-append "#" (i64->string (+ index 1))))
           ((None) "#?")))
        ((Var _) "#?")
        ((Con global arguments)
         (string-append (global-spelling global)
                        (arguments-schema known arguments parameters visiting)
                        (cases-schema known global visiting)))
        ((Callable (Dyn) (FnContract) _) "fn")
        ((Callable (Dyn) (FnMutContract) _) "FnMut<fn,>")
        ((Callable (Dyn) (FnOnceContract) _) "FnOnce<fn,>")
        ((Callable (Impl) (FnContract) _) "$impl.Fn<fn,>")
        ((Callable (Impl) (FnMutContract) _) "$impl.FnMut<fn,>")
        ((Callable (Impl) (FnOnceContract) _) "$impl.FnOnce<fn,>")
        ((Code _) "fn<fn,>")
        ((Row _) "fn")))

    (: arguments-schema (impl (Fn Known (List Type) (List String) (List Global) -> String)))
    (define (arguments-schema known arguments parameters visiting)
      (string-append "<"
                     (string-concatenate
                      (map (lambda (argument)
                             (string-append (type-schema known argument parameters visiting) ","))
                           arguments))
                     ">"))

    (: cases-schema (impl (Fn Known Global (List Global) -> String)))
    (define (cases-schema known global visiting)
      (if (any? (lambda (visited) (same-global? visited global)) visiting)
          ""
          (match (known-data known global)
            ((Some data)
             (string-concatenate (map (lambda (case) (case-schema known data case visiting))
                                      (::cases data))))
            ((None) ""))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-identities)
    (import
     (snail core table)
     (snail compiler source)
     (snail compiler declare offer)
     (only (snail compiler names libraries) forms-library)
     (snail stage0 testing))
    (begin
      (define (test-identities)
        (test-schemas))

      (define loc (Loc "t.sld" 1 1))
      (define main (list "main"))
      (define base (list "snail" "core" "base"))

      (define (global library name)
        (Global library name 0))

      (define (builtin name)
        (Con (Global forms-library name 0) (list)))

      (define (field label type)
        (DataField label #f type (list) loc))

      (define (data-of global parameters cases)
        (Data global parameters cases (EnumData) #f #f (list) loc))

      ;; (snail core base) offers (Option a); (main) declares (List a),
      ;; whose Link holds a List.
      (define option
        (data-of (global base "Option")
                 (list "a")
                 (list (DataCase (global base "None") 0 (list) (list) loc)
                       (DataCase (global base "Some")
                                 1
                                 (list (field "value" (Var (Written "a"))))
                                 (list)
                                 loc))))

      (define list-type
        (data-of (global main "List")
                 (list "a")
                 (list (DataCase (global main "Empty") 0 (list) (list) loc)
                       (DataCase (global main "Link")
                                 1
                                 (list (field "head" (Var (Written "a")))
                                       (field "tail"
                                              (Con (global main "List")
                                                   (list (Var (Written "a"))))))
                                 (list)
                                 loc))))

      (define known
        (Known main
               (Scanned empty-table empty-table)
               (Declarations main (by-name empty-table "List" list-type) empty-table empty-table)
               (list
                (Declarations base (by-name empty-table "Option" option) empty-table empty-table))))

      ;; (Pair) holds an (Option I64) and a mutable (dyn (FnMut -> I64)).
      (define pair-case
        (DataCase (global main "Pair")
                  0
                  (list (field "x" (Con (global base "Option") (list (builtin "I64"))))
                        (DataField "f"
                                   #t
                                   (Callable (Dyn)
                                             (FnMutContract)
                                             (Arrow (list) (builtin "I64") (Effects (list) (None))))
                                   (list)
                                   loc))
                  (list)
                  loc))

      (define pair
        (Data (global main "Pair") (list) (list pair-case) (StructData) #f #f (list) loc))

      ;; Read off `case-schema` and `type-schema`: parameters by position, a
      ;; type visited cut, a field type's cases followed, and the TypeId of
      ;; each schema as the old `type-id` hashes it.
      (define (test-schemas)
        (let ((link (list-ref (::cases list-type) 1)))
          (expect (case-schema known list-type link (Nil))
                  "main:Link(head:#1;tail:main:List<#1,>;)")
          (expect (case-schema known pair pair-case (Nil))
                  (string-append "main:Pair(x:snail.core.base:Option<I64<>,>"
                                 "snail.core.base:None()snail.core.base:Some(value:#1;);"
                                 "f mut:FnMut<fn,>;)"))
          ;; FNV-1a of "" and of "a", signed.
          (expect (type-id "") -2128831035)
          (expect (type-id "a") -468965076)
          (expect (case-type-id known list-type link)
                  (type-id "main:Link(head:#1;tail:main:List<#1,>;)"))))))
   (else)))
