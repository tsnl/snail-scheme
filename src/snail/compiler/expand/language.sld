;; Expanded, the tree `expand` writes: a library with its macros run,
;; every identifier resolved and every core form parsed. What the library
;; offers the libraries that import it is the other language `expand`
;; writes, (snail compiler expand offer), which only another library's
;; expansion reads, and the syntax `expand` works on is (snail compiler
;; expand marked)'s.
;;
;;   Expanded    ::= Defined library Top* first-unused-number
;;                 | Program Top* Expr? first-unused-number          no Loc
;;   Top         ::= Define Global Expr
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
;;   Field       ::= Field label mutable? TypeExpr Annotation*
;;   Case        ::= Case Global CaseField* Annotation*
;;   CaseField   ::= CaseField label TypeExpr Annotation*
;;   Derivation  ::= DeriveMove | DeriveSerialize | DeriveDeserialize
;;   Member      ::= MethodSignature Global Scheme Annotation*
;;                 | AssociatedOutput Label Annotation*              no Loc but its label's
;;   Instance    ::= Instance ClassRef variable* TypeExpr* Requirement* Equation* InstanceBody
;;   InstanceBody ::= Dispatch TypeExpr* | Methods InstanceMethod*   Methods: no Loc
;;   InstanceMethod ::= InstanceMethod Label Expr                    no Loc but its label's
;;   SetMember   ::= SetInstance Instance                            no Loc but its instance's
;;                 | DynamicInstances ClassRef (TypeExpr*)*
;;   Operation   ::= Operation Global control? Scheme Annotation*
;;   Default     ::= Default Label Expr
;;   PrimitiveType ::= PrimitiveScheme Scheme | CallableOnce         no Loc
;;   Annotation  ::= Documentation text
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
;;                 | LinkedFile name* | ArtifactFiles target Expr Expr Expr
;;   Clause      ::= Clause Pattern Expr
;;   Implementation ::= Implementation Label Expr
;;   Pattern     ::= Wild | Bind Local | Equals Datum | Destructure TopValue Pattern*
;;   Constant    ::= Integer integer | Float text | Text text | Character character
;;                 | ByteVector bytes | Boolean boolean | UnitValue    no Loc
;;
;;   TypeExpr    ::= Applied Global written TypeExpr* | Variable name
;;                 | Projection Global member TypeExpr*
;;                 | Callable Former Contract Arrow | Code Arrow | Row Effects
;;   Arrow       ::= Arrow TypeExpr* TypeExpr Effects                no Loc
;;   Effects     ::= Effects Global* TypeExpr?                       no Loc
;;   Former      ::= Impl | Dyn                                      no Loc
;;   Contract    ::= FnContract | FnMutContract | FnOnceContract     no Loc
;;   Scheme      ::= Scheme variable* Requirement* TypeExpr
;;   Requirement ::= CopyRequirement variable
;;                 | ClassRequirement ClassRef TypeExpr* Equation*
;;                 | CallableRequirement Contract TypeExpr Arrow
;;   ClassRef    ::= ClassGlobal Global | FieldClass label           no Loc
;;   Equation    ::= Equation Label TypeExpr                         no Loc but its label's
;;
;;   Local       ::= Local name number                               no Loc
;;   Global      ::= Global library name serial                      no Loc
;;   TopValue    ::= TopGlobal Global | FieldFunction Global label FieldRole   no Loc
;;   FieldRole   ::= Accessor | Replacer | Setter | Swapper          no Loc
;;   Label       ::= Label name
;;
;; Over the Library it comes from, Expanded guarantees:
;;
;; - No macro remains, used or defined, nor a top-level `begin`, nor an
;;   `include-bytes` form: each node is the core form it is named for,
;;   well formed as the old expander's messages decide.
;; - Every identifier is resolved. A value is a Local, a Global or one of
;;   the functions a field declares; a type is its declaration, a builtin
;;   of (snail core forms), a variable or a class's associated output; a
;;   class, an effect and an instance set are their declarations. A Global
;;   is the library that defines it and the name written there, with a
;;   serial of its own when a macro's template wrote the name. A Local's
;;   number is unique in its library.
;; - The root's `first-unused-number` is the first number the library has
;;   not used for a local, a mark or a serial: every Local's number in the
;;   tree, and the serial of every Global the library defines, is below
;;   it. A later pass that writes locals of its own numbers them from it,
;;   and says in its own root where it stopped.
;; - A label is the one name not resolved here: a field's, a path's, and
;;   that of a member of a class or an effect, as a method definition, an
;;   associated output, a default or a handler's clause writes it. The
;;   pass that has the declaration a label belongs to resolves it.
;; - Types are as written, with their names resolved, except that an alias
;;   is expanded where it is used, as a macro is, so no type names an
;;   alias.
;; - Declarations come in the order written once macros are run. A
;;   program's statements are its body, each under the instance sets in
;;   scope where it was written; a library's stay statements.
;; - An `if` has its alternative: one written without has the unit value
;;   there, which no Datum writes, so Expanded's expressions have constants
;;   of their own. A pattern's literal stays the Datum written.
;; - Nothing is syntax. A macro's rules and an alias's body, which an
;;   importer still expands, are in the library's offer instead.
(define-library (snail compiler expand language)
  (export
   Expanded
   Defined
   Program
   Top
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
   Field
   Case
   CaseField
   Derivation
   DeriveMove
   DeriveSerialize
   DeriveDeserialize
   Member
   MethodSignature
   AssociatedOutput
   Instance
   InstanceBody
   Dispatch
   Methods
   InstanceMethod
   SetMember
   SetInstance
   DynamicInstances
   Operation
   Default
   PrimitiveType
   PrimitiveScheme
   CallableOnce
   Annotation
   Documentation
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
   LinkedFile
   ArtifactFiles
   Clause
   Implementation
   Pattern
   Wild
   Bind
   Equals
   Destructure
   Constant
   Integer
   Float
   Text
   Character
   ByteVector
   Boolean
   UnitValue
   TypeExpr
   Applied
   Variable
   Projection
   Callable
   Code
   Row
   Arrow
   Effects
   Former
   Impl
   Dyn
   Contract
   FnContract
   FnMutContract
   FnOnceContract
   Scheme
   Requirement
   CopyRequirement
   ClassRequirement
   CallableRequirement
   ClassRef
   ClassGlobal
   FieldClass
   Equation
   Local
   Global
   TopValue
   TopGlobal
   FieldFunction
   FieldRole
   Accessor
   Replacer
   Setter
   Swapper
   Label)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler read language) Datum)
   (only (snail compiler outline language) LibraryName))
  (begin

    ;; ---- Libraries ----

    ;; A library is at its `define-library` form. A program is the library
    ;; ("main"), whose Globals name that library; its statements, in order,
    ;; are its body, which runs once every definition is initialized, so no
    ;; Statement is among its tops. Either holds the first number its
    ;; library has not used, from which a later pass numbers its locals.
    (enum Expanded
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

    ;; A declaration is at its form. A Define's value is a Lambda when it
    ;; was written `(define (name parameter ...) body ...)`. A Signature's
    ;; scheme is written for the top-level value it names, whichever
    ;; declares it. A struct's name is both its type and its constructor,
    ;; and `name-loc` is where that name is written. An alias's body is
    ;; expanded where the alias is used, so only its name and parameters
    ;; remain. An InstanceScope is `(with-instances (set ...) top ...)` at
    ;; the top level, and the declarations it holds are written under those
    ;; sets. A Primitive is declared only in (snail core primitive), and its
    ;; Global is in the library ("prim").
    (enum Top
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

    ;; A struct's field, at its name. Only (snail core base) and
    ;; (snail shell slot) declare a mutable one.
    (struct Field
      ((label String)
       (mutable? Bool)
       (type TypeExpr)
       (annotations (List Annotation))
       (loc Loc)))

    ;; An enum's case, whose Global is its constructor. Its fields are
    ;; never mutable.
    (struct Case
      ((global Global)
       (fields (List CaseField))
       (annotations (List Annotation))
       (loc Loc)))

    (struct CaseField
      ((label String)
       (type TypeExpr)
       (annotations (List Annotation))
       (loc Loc)))

    ;; A class a `deriving` clause names, at its name: Move makes the type
    ;; linear, and the others ask for an instance.
    (enum Derivation
      (DeriveMove
       ((loc Loc)))
      (DeriveSerialize
       ((loc Loc)))
      (DeriveDeserialize
       ((loc Loc))))

    ;; A class's member. A method is a top-level value of the library. An
    ;; associated output is a variable of the class's types, and its
    ;; projection elsewhere is `Class.Output`.
    (enum Member
      (MethodSignature
       ((global Global)
        (scheme Scheme)
        (annotations (List Annotation))
        (loc Loc)))
      (AssociatedOutput
       ((label Label)
        (annotations (List Annotation)))))

    ;; ---- Instances ----

    ;; `(instance (Class type ...) (requires ...) member ...)`. Its
    ;; variables are the names its head leaves unbound, in the order they
    ;; are first written, and its head's types, requirements and equations
    ;; are written over them. Its methods' values are expanded where the
    ;; instance is, where those variables are not in scope.
    (struct Instance
      ((class ClassRef)
       (variables (List String))
       (types (List TypeExpr))
       (requirements (List Requirement))
       (equations (List Equation))
       (body InstanceBody)
       (loc Loc)))

    ;; An instance's methods are a `(dispatch type ...)` clause, its only
    ;; member besides its equations, or definitions.
    (enum InstanceBody
      (Dispatch
       ((types (List TypeExpr))
        (loc Loc)))
      (Methods
       ((methods (List InstanceMethod)))))

    ;; A method definition: the method it names, as written, and its value.
    (struct InstanceMethod
      ((label Label)
       (value Expr)))

    ;; An instance set holds instances and `(dynamic-instances Class
    ;; (type ...) ...)` declarations, which are written nowhere else.
    (enum SetMember
      (SetInstance
       ((instance Instance)))
      (DynamicInstances
       ((class ClassRef)
        (pairs (List (List TypeExpr)))
        (loc Loc))))

    ;; ---- Effects ----

    ;; An operation is a top-level value of the library; a control
    ;; operation is written `(ctl name type)`.
    (struct Operation
      ((global Global)
       (control? Bool)
       (scheme Scheme)
       (annotations (List Annotation))
       (loc Loc)))

    ;; One entry of a `(default ((operation implementation) ...))` clause.
    (struct Default
      ((label Label)
       (value Expr)
       (loc Loc)))

    ;; A primitive's type, or `callable-once`, the signature the compiler
    ;; gives `once`, which no type can write.
    (enum PrimitiveType
      (PrimitiveScheme
       ((scheme Scheme)))
      (CallableOnce))

    ;; `(doc "text")` in a declaration's `(annotations ...)` list.
    (enum Annotation
      (Documentation
       ((text String)
        (loc Loc))))

    ;; ---- Expressions ----

    ;; An expression is at its form, or at its atom or identifier. A path
    ;; `::a::b` has a label for each of its fields, in order, one or more,
    ;; and applied to one argument it is the chain of reads itself. A
    ;; ClosedLambda is `(fn (parameter ...) body ...)`, which reads no local
    ;; around it. An `if` written without an alternative has the constant
    ;; UnitValue as its alternative, at the `if`. A Let's signature is a local `(: name type)` that
    ;; came just before its definition, and a LocalSignature one that
    ;; annotates no definition, whose type is still to be checked. A Seq is
    ;; at its first expression. CaseId is `(case-id Constructor)`, with its
    ;; constructor written at `constructor-loc`. A LinkedFile is
    ;; `(link-handle "path")`, the path's names, each a name of a file or
    ;; directory, relative to the file `written` is in. ArtifactFiles is
    ;; `(artifact-files "target" file prepend empty)`, the target's files as
    ;; a list built from the three expressions.
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
        (loc Loc)))
      (LinkedFile
       ((path (List String))
        (written Loc)
        (loc Loc)))
      (ArtifactFiles
       ((target String)
        (file Expr)
        (prepend Expr)
        (empty Expr)
        (loc Loc))))

    ;; A match clause, at its form.
    (struct Clause
      ((pattern Pattern)
       (body Expr)
       (loc Loc)))

    ;; A handler's implementation of the operation its label names.
    (struct Implementation
      ((label Label)
       (value Expr)
       (loc Loc)))

    ;; ---- Patterns ----

    ;; A pattern is at its atom or identifier, and a Destructure at its
    ;; constructor. Each Bind binds a local of its own. An Equals is a
    ;; literal as the reader decodes it, and never a byte vector.
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

    ;; ---- Constants ----

    ;; An expression's literal value: a Datum of Syntax, under the same
    ;; names, or the unit value, which an `if` without an alternative has
    ;; and no literal writes.
    (enum Constant
      (Integer
       ((integer I64)))
      (Float
       ((text String)))
      (Text
       ((text String)))
      (Character
       ((character Char)))
      (ByteVector
       ((bytes Bytes)))
      (Boolean
       ((boolean Bool)))
      (UnitValue))

    ;; ---- Types ----

    ;; A type is at its form or identifier. An Applied type is a declared
    ;; or builtin type at its arguments, `written` as the name its use
    ;; spells. A Variable is a type variable a binder in scope names: a
    ;; scheme's, a declaration's or a class's parameter, or an instance's
    ;; variable. A Projection is `(Class.member type ...)`. A Callable is
    ;; `(impl (Fn ...))` or `(dyn (FnMut ...))`, Code is `(fn ...)`, and a
    ;; Row is `(! effect ... tail)`.
    (enum TypeExpr
      (Applied
       ((type Global)
        (written String)
        (arguments (List TypeExpr))
        (loc Loc)))
      (Variable
       ((name String)
        (loc Loc)))
      (Projection
       ((class Global)
        (member String)
        (arguments (List TypeExpr))
        (loc Loc)))
      (Callable
       ((former Former)
        (contract Contract)
        (arrow Arrow)
        (loc Loc)))
      (Code
       ((arrow Arrow)
        (loc Loc)))
      (Row
       ((effects Effects)
        (loc Loc))))

    ;; `parameter ... -> result ! effect ...`; no `!` is no effects.
    (struct Arrow
      ((parameters (List TypeExpr))
       (result TypeExpr)
       (effects Effects)))

    ;; Effects in the order written, and the type a row ends with, which an
    ;; alias's argument may be.
    (struct Effects
      ((labels (List Global))
       (tail (Option TypeExpr))))

    (enum Former
      (Impl)
      (Dyn))

    (enum Contract
      (FnContract)
      (FnMutContract)
      (FnOnceContract))

    ;; `(All (variable ...) (requires requirement ...) type)`, or a type
    ;; alone, which quantifies nothing.
    (struct Scheme
      ((variables (List String))
       (requirements (List Requirement))
       (type TypeExpr)
       (loc Loc)))

    ;; A requirement is at its form: `(Copy variable)`, a class's at types
    ;; and equations `(type Output type)`, or one of the compiler's
    ;; callable classes, `(Fn receiver parameter ... -> result ! effect)`.
    (enum Requirement
      (CopyRequirement
       ((variable String)
        (loc Loc)))
      (ClassRequirement
       ((class ClassRef)
        (types (List TypeExpr))
        (equations (List Equation))
        (loc Loc)))
      (CallableRequirement
       ((contract Contract)
        (receiver TypeExpr)
        (arrow Arrow)
        (loc Loc))))

    ;; A declared class, or the field class of a label, written `::label`,
    ;; which every label has.
    (enum ClassRef
      (ClassGlobal
       ((global Global)))
      (FieldClass
       ((label String))))

    ;; `(type Output type)`, in an instance or a requirement.
    (struct Equation
      ((label Label)
       (type TypeExpr)))

    ;; ---- Names ----

    ;; A local is the name written at its binder, numbered within the
    ;; library, so two locals are one when their numbers are.
    (struct Local
      ((name String)
       (number I64)))

    ;; A value, type, class, effect or instance set a library's top level
    ;; defines. `serial` is 0 for a name the library writes; a name a
    ;; macro's template wrote has a serial of its own, unique in the
    ;; library, since two expansions may write it.
    (struct Global
      ((library LibraryName)
       (name String)
       (serial I64)))

    ;; A top-level value: a Global, or one of the functions a field of the
    ;; case whose constructor is `case` declares. An enum case's field has
    ;; an Accessor, `Case-field`; a struct's mutable field an Accessor, a
    ;; Setter and a Swapper, `Name-field`, `Name-field-set!` and
    ;; `Name-field-replace!`; and a field of a struct without one a
    ;; Replacer, `Name-field-set`.
    (enum TopValue
      (TopGlobal
       ((global Global)))
      (FieldFunction
       ((case Global)
        (label String)
        (role FieldRole))))

    (enum FieldRole
      (Accessor)
      (Replacer)
      (Setter)
      (Swapper))

    ;; A member's name as written, where it is written.
    (struct Label
      ((name String)
       (loc Loc)))

    ))
