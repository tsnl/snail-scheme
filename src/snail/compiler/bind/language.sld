;; Bound, the tree `bind` writes: an expanded library with what its
;; build supplied in place of each linked file and each request for
;; another target's files.
;;
;;   Bound       ::= Defined library Top* first-unused-number
;;                 | Program Top* Expr? first-unused-number          no Loc
;;   Top         ::= LinkImport Global name* digest file
;;                 | Define Global Expr
;;                 | Signature TopValue Scheme Annotation*
;;                 | Statement Expr                                  no Loc but its expression's
;;                 | Expose TopValue symbol dynamic?
;;                 | Struct Global parameter* Field* Derivation* Annotation*
;;                 | Enum Global parameter* Case* Derivation* Annotation*
;;                 | Alias Global parameter* Annotation*
;;                 | Class Global parameter* Member* Annotation*
;;                 | TopInstance Instance                            no Loc but its instance's
;;                 | InstanceSet Global SetMember*
;;                 | InstanceScope Global* Top*
;;                 | Extern Global module symbol TypeExpr Annotation*
;;                 | Effect Global Operation* Default* around-main? Annotation*
;;                 | Primitive Global PrimitiveType
;;   Instance    ::= Instance ClassRef variable* TypeExpr* Requirement* Equation* InstanceBody
;;   InstanceBody ::= Dispatch TypeExpr* | Methods InstanceMethod*   Methods: no Loc
;;   InstanceMethod ::= InstanceMethod MethodName Expr               no Loc but its name's
;;   SetMember   ::= SetInstance Instance                            no Loc but its instance's
;;                 | DynamicInstances ClassRef (TypeExpr*)*
;;   Default     ::= Default Label Expr
;;
;;   Expr        ::= Literal Constant | LocalRef Local | TopRef TopValue
;;                 | Path label* | PathApply label* Expr
;;                 | Lambda Local* Expr | ClosedLambda Local* Expr | Call Expr Expr*
;;                 | If Expr Expr Expr | Seq Expr Expr
;;                 | Let Local Scheme? Expr Expr | LocalSignature Scheme Expr
;;                 | Match Expr Clause* | Handle Global Implementation* Expr
;;                 | WithInstances Global* Expr
;;                 | Ann Expr TypeExpr | Convert Expr TypeExpr | TryConvert Expr TypeExpr
;;                 | TypeTest Expr TypeExpr | CaseId TopValue
;;   Clause      ::= Clause Pattern Expr
;;   Implementation ::= Implementation Label Expr
;;   Pattern     ::= Wild | Bind Local | Equals Datum | Destructure TopValue Pattern*
;;
;; Every other rule is Expanded's, (snail compiler expand language): Field,
;; Case, CaseField, Derivation, Member, MethodName, Operation,
;; PrimitiveType, Annotation, Constant, TypeExpr and the rules it holds,
;; Scheme, Requirement, ClassRef, Equation, Local, Global, TopValue,
;; FieldRole and Label.
;;
;; Over the Expanded library it comes from, Bound guarantees:
;;
;; - No LinkedFile and no ArtifactFiles remains.
;; - Each file the library links is declared once, by a LinkImport among
;;   its first tops, in the order the library first names its files, at
;;   the place it first names this one. A LinkImport binds its Global to
;;   the import from "snail.runtime.link" named `digest`, the SHA-256 of
;;   the file's bytes in lowercase hex, a function of no arguments that
;;   answers the file's handle as an I32; `name*` is the path the library
;;   wrote, as canonical names, and `file` is where the build found the
;;   file. The Global is named "link-handle", with a serial of its own.
;;   Each `(link-handle "path")` is a call of that Global with no
;;   arguments, at the form.
;; - A request for a target's files is the list of them: for each file,
;;   in the order the build supplied them, `(prepend (file path bytes)
;;   rest)`, ending in `(empty)`, each call at the request. The first
;;   file's `prepend` and `file` are the expressions expand wrote, and
;;   each later file's are copies with locals of their own, as the old
;;   expander expands the form again for each file; a target without files
;;   is `(empty)` alone.
;; - Every Local's number is unique in its library, and the root's
;;   `first-unused-number` is the first number the library has not used
;;   for a local, a mark or a serial, counting the serials of its
;;   LinkImports and the locals of its copies.
(define-library (snail compiler bind language)
  (export
   Bound
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
   Primitive
   Instance
   InstanceBody
   Dispatch
   Methods
   InstanceMethod
   SetMember
   SetInstance
   DynamicInstances
   Default
   Expr
   Literal
   LocalRef
   TopRef
   Path
   PathApply
   Lambda
   ClosedLambda
   Call
   If
   Seq
   Let
   LocalSignature
   Match
   Handle
   WithInstances
   Ann
   Convert
   TryConvert
   TypeTest
   CaseId
   Clause
   Implementation
   Pattern
   Wild
   Bind
   Equals
   Destructure)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler read language) Datum)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language)
         Field
         Case
         Derivation
         Member
         MethodName
         Operation
         PrimitiveType
         Annotation
         Constant
         TypeExpr
         Scheme
         Requirement
         ClassRef
         Equation
         Local
         Global
         TopValue
         Label))
  (begin

    ;; ---- Libraries ----

    ;; As Expanded's, with the first number the library has not used once
    ;; `bind` has numbered what it wrote.
    (enum Bound
      (Defined
        ((name LibraryName)
         (tops (List Top))
         (first-unused-number I64)
         (loc Loc)))
      (Program
       ((tops (List Top))
        (body (Option Expr))
        (first-unused-number I64))))

    ;; ---- Declarations ----

    ;; As Expanded's, and a LinkImport for each file the library links: the
    ;; Global its uses call, the path as the library names it, the digest
    ;; that names its import, and the file the build found.
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
        (derivations (List Derivation))
        (annotations (List Annotation))
        (name-loc Loc)
        (loc Loc)))
      (Enum
       ((global Global)
        (parameters (List String))
        (cases (List Case))
        (derivations (List Derivation))
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

    ;; ---- Instances ----

    (struct Instance
      ((class ClassRef)
       (variables (List String))
       (types (List TypeExpr))
       (requirements (List Requirement))
       (equations (List Equation))
       (body InstanceBody)
       (loc Loc)))

    (enum InstanceBody
      (Dispatch
       ((types (List TypeExpr))
        (loc Loc)))
      (Methods
       ((methods (List InstanceMethod)))))

    (struct InstanceMethod
      ((name MethodName)
       (value Expr)))

    (enum SetMember
      (SetInstance
       ((instance Instance)))
      (DynamicInstances
       ((class ClassRef)
        (pairs (List (List TypeExpr)))
        (loc Loc))))

    ;; ---- Effects ----

    (struct Default
      ((label Label)
       (value Expr)
       (loc Loc)))

    ;; ---- Expressions ----

    ;; As Expanded's, without LinkedFile and ArtifactFiles.
    (enum Expr
      (Literal
       ((constant Constant)
        (loc Loc)))
      (LocalRef
       ((local Local)
        (loc Loc)))
      (TopRef
       ((value TopValue)
        (loc Loc)))
      (Path
       ((labels (List String))
        (loc Loc)))
      (PathApply
       ((labels (List String))
        (record Expr)
        (loc Loc)))
      (Lambda
       ((parameters (List Local))
        (body Expr)
        (loc Loc)))
      (ClosedLambda
       ((parameters (List Local))
        (body Expr)
        (loc Loc)))
      (Call
       ((callee Expr)
        (arguments (List Expr))
        (loc Loc)))
      (If
       ((test Expr)
        (consequent Expr)
        (alternative Expr)
        (loc Loc)))
      (Seq
       ((first Expr)
        (rest Expr)
        (loc Loc)))
      (Let
       ((local Local)
        (signature (Option Scheme))
        (value Expr)
        (body Expr)
        (loc Loc)))
      (LocalSignature
       ((scheme Scheme)
        (body Expr)
        (loc Loc)))
      (Match
       ((scrutinee Expr)
        (clauses (List Clause))
        (loc Loc)))
      (Handle
       ((effect Global)
        (implementations (List Implementation))
        (body Expr)
        (loc Loc)))
      (WithInstances
       ((sets (List Global))
        (body Expr)
        (loc Loc)))
      (Ann
       ((expr Expr)
        (type TypeExpr)
        (loc Loc)))
      (Convert
       ((expr Expr)
        (type TypeExpr)
        (loc Loc)))
      (TryConvert
       ((expr Expr)
        (type TypeExpr)
        (loc Loc)))
      (TypeTest
       ((expr Expr)
        (type TypeExpr)
        (loc Loc)))
      (CaseId
       ((constructor TopValue)
        (constructor-loc Loc)
        (loc Loc))))

    (struct Clause
      ((pattern Pattern)
       (body Expr)
       (loc Loc)))

    (struct Implementation
      ((label Label)
       (value Expr)
       (loc Loc)))

    ;; ---- Patterns ----

    ;; As Expanded's: `bind` renames the locals a copied pattern binds.
    (enum Pattern
      (Wild
       ((loc Loc)))
      (Bind
       ((local Local)
        (loc Loc)))
      (Equals
       ((datum Datum)
        (loc Loc)))
      (Destructure
       ((constructor TopValue)
        (arguments (List Pattern))
        (loc Loc))))

    ))
