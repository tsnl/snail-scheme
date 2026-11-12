;; Derived, the tree `derive` writes: a bound library whose `deriving`
;; clauses are what they ask for. A clause that names Serialize or
;; Deserialize is an instance, and one that names Move is said on the
;; type.
;;
;;   Derived     ::= Defined library Top* first-unused-number
;;                 | Program Top* first-unused-number                no Loc
;;   Top         ::= LinkImport Global name* digest file
;;                 | Define Global Expr
;;                 | Signature TopValue Scheme Annotation*
;;                 | Statement Expr                                  no Loc but its expression's
;;                 | Expose TopValue symbol dynamic?
;;                 | Struct Global parameter* Field* move? Annotation*
;;                 | Enum Global parameter* Case* move? Annotation*
;;                 | Alias Global parameter* Annotation*
;;                 | Class Global parameter* Member* Annotation*
;;                 | TopInstance Instance                            no Loc but its instance's
;;                 | InstanceSet Global SetMember*
;;                 | InstanceScope Global* Top*
;;                 | Extern Global module symbol TypeExpr Annotation*
;;                 | Effect Global Operation* Default* around-main? Annotation*
;;                 | Primitive Global PrimitiveType
;;
;; Every other rule is Bound's, (snail compiler bind language): Instance,
;; SetMember, Default, Expr and the rules it holds; or Expanded's, as
;; Bound reuses them: Field, Case, Member, Operation, PrimitiveType,
;; Annotation, TypeExpr, Scheme, Global, TopValue and the rest.
;;
;; Over the Bound library it comes from, Derived guarantees:
;;
;; - No Derivation remains. A struct or an enum says `move?` when a
;;   deriving clause of its declaration names Move, which makes its values
;;   moved, never copied. That is not all of the old compiler's `owned?`:
;;   a Drop instance makes a type's values moved too, which is the
;;   instance's to say, and Derived does not.
;; - Each Serialize and each Deserialize a deriving clause names is an
;;   instance, a TopInstance among the tops its declaration is in, right
;;   after the declaration, in the order the clauses name them: where the
;;   old expander scans the instance it writes for the clause. Nothing
;;   else is added, removed or moved.
;; - A derived instance is what the old expander's syntax for it expands
;;   to, up to the names of locals, for the type `T` declared with
;;   parameters `a ...` and the constructors `C`, each with its fields:
;;
;;     (instance (Serialize (T a ...)) (requires (Serialize a) ...)
;;       (define (encode value encoder)
;;         (match value
;;           ((C field0 ...)
;;            (encode-case-id encoder (case-id C))
;;            (encode field0 encoder) ...
;;            (unit))
;;           ...)))
;;     (instance (Deserialize (T a ...)) (requires (Deserialize a) ...)
;;       (define (decode decoder)
;;         (let ((id (decode-case-id decoder)))
;;           (if (case-id=? id (case-id C))
;;               (let ((field0 (decode decoder))) ... (C field0 ...))
;;               ...
;;               (panic "wire data has a different schema")))))
;;
;;   The instance's variables are the type's parameters. Its classes and
;;   functions are those the implicit libraries, (snail core primitive)
;;   and (snail shell wire), export under those names, a later library's
;;   hiding an earlier's; nothing resolves in the library's own scope. A
;;   constructor is the declaration's, a struct's being the struct. Every
;;   node is at the declaration's form, but that a constructor, in a
;;   pattern, a call or a `case-id`, is where its name is written.
;; - Every Local's number is unique in its library, and the root's
;;   `first-unused-number` is the first number the library has not used,
;;   counting the locals of the derived instances, which are numbered
;;   from Bound's.
(define-library (snail compiler derive language)
  (export
   Derived
   Defined
   Program
   Top
   LinkImport
   Define
   Signature
   Statement
   Expose
   Struct
   Enum
   Alias
   Class
   TopInstance
   InstanceSet
   InstanceScope
   Extern
   Effect
   Primitive)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language)
         Field
         Case
         Member
         Operation
         PrimitiveType
         Annotation
         TypeExpr
         Scheme
         Global
         TopValue)
   (only (snail compiler bind language) Instance SetMember Default Expr))
  (begin

    ;; ---- Libraries ----

    ;; As Bound's, with the first number the library has not used once
    ;; `derive` has numbered the locals of its instances.
    (enum Derived
      (Defined
        ((name LibraryName)
         (tops (List Top))
         (first-unused-number I64)
         (loc Loc)))
      (Program
       ((tops (List Top))
        (first-unused-number I64))))

    ;; ---- Declarations ----

    ;; As Bound's, but that a struct or an enum says whether it derives
    ;; Move in place of its deriving clauses.
    (enum Top
      (LinkImport
       ((global Global)
        (path (List String))
        (digest String)
        (file String)
        (loc Loc)))
      (Define
        ((global Global)
         (value Expr)
         (loc Loc)))
      (Signature
       ((target TopValue)
        (scheme Scheme)
        (annotations (List Annotation))
        (loc Loc)))
      (Statement
       ((expr Expr)))
      (Expose
       ((target TopValue)
        (symbol String)
        (dynamic? Bool)
        (loc Loc)))
      (Struct
       ((global Global)
        (parameters (List String))
        (fields (List Field))
        (move? Bool)
        (annotations (List Annotation))
        (name-loc Loc)
        (loc Loc)))
      (Enum
       ((global Global)
        (parameters (List String))
        (cases (List Case))
        (move? Bool)
        (annotations (List Annotation))
        (loc Loc)))
      (Alias
       ((global Global)
        (parameters (List String))
        (annotations (List Annotation))
        (loc Loc)))
      (Class
       ((global Global)
        (parameters (List String))
        (members (List Member))
        (annotations (List Annotation))
        (loc Loc)))
      (TopInstance
       ((instance Instance)))
      (InstanceSet
       ((global Global)
        (members (List SetMember))
        (loc Loc)))
      (InstanceScope
       ((sets (List Global))
        (tops (List Top))
        (loc Loc)))
      (Extern
       ((global Global)
        (module String)
        (symbol String)
        (type TypeExpr)
        (annotations (List Annotation))
        (loc Loc)))
      (Effect
       ((global Global)
        (operations (List Operation))
        (defaults (List Default))
        (around-main? Bool)
        (annotations (List Annotation))
        (loc Loc)))
      (Primitive
       ((global Global)
        (type PrimitiveType)
        (loc Loc))))

    ))
