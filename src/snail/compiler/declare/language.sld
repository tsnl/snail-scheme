;; Declared, the tree `declare` writes: a derived library whose written
;; types are types, whose declarations are entities, and whose labels are
;; the members they name. What a declared library offers the declaration
;; of each library whose import closure holds it is the other language
;; `declare` writes, (snail compiler declare offer).
;;
;;   Declared    ::= Defined library Top* first-unused-number
;;                 | Program Top* Expr? first-unused-number          no Loc
;;   Top         ::= LinkImport Global name* digest file
;;                 | Define Global Expr Signed? Annotation*
;;                 | Statement Expr                                  no Loc but its expression's
;;                 | Expose TopValue symbol dynamic?
;;                 | TopData Data                                    no Loc but its data's
;;                 | Alias Global parameter* Annotation*
;;                 | TopClass Class                                  no Loc but its class's
;;                 | TopInstance Instance                            no Loc but its instance's
;;                 | InstanceSet Global SetMember*
;;                 | InstanceScope Global* Top*
;;                 | Extern Global module symbol Type Annotation*
;;                 | TopEffect Effect                                no Loc but its effect's
;;                 | Primitive Global PrimitiveType
;;   Signed      ::= Signed Scheme
;;
;;   Data        ::= Data Global parameter* DataCase* DataKind move? drop? Annotation*
;;   DataKind    ::= StructData | EnumData                           no Loc
;;   DataCase    ::= DataCase Global tag DataField* Annotation*
;;   DataField   ::= DataField label mutable? Type Annotation*
;;
;;   Class       ::= Class Global ClassParameter* Output* Method* Annotation*
;;   ClassParameter ::= TypeParameter name | RowParameter name      no Loc
;;   Output      ::= Output Label Annotation*                        no Loc but its label's
;;   Method      ::= Method Global Scheme Annotation*
;;
;;   Instance    ::= Instance Global ClassRef TypeVariable* Type* Type* Requirement*
;;                            TypeVariable* InstanceBody
;;   InstanceBody ::= Dispatch Type* | Methods InstanceMethod*       Methods: no Loc
;;   InstanceMethod ::= InstanceMethod Member Global Expr
;;   Member      ::= ClassMethod Global | FieldReader label          no Loc
;;   SetMember   ::= SetInstance Instance                            no Loc but its instance's
;;                 | DynamicInstances ClassRef (Type*)*
;;
;;   Effect      ::= Effect Global Operation* Default* around-main? Annotation*
;;   Operation   ::= Operation Global control? Type* Type Global* Annotation*
;;   Default     ::= Default Global Global Expr
;;   PrimitiveType ::= PrimitiveScheme Scheme | CallableOnce         no Loc
;;
;;   Expr        ::= Literal Constant | LocalRef Local | TopRef TopValue
;;                 | Path label* | PathApply label* Expr
;;                 | Lambda Local* Expr | ClosedLambda Local* Expr | Call Expr Expr*
;;                 | If Expr Expr Expr | Seq Expr Expr
;;                 | Let Local Scheme? Expr Expr
;;                 | Match Expr Clause* | Handle Global Implementation* Expr
;;                 | WithInstances Global* Expr
;;                 | Ann Expr Type | Convert Expr Type | TryConvert Expr Type
;;                 | TypeTest Expr Type | CaseId Global id
;;   Clause      ::= Clause Pattern Expr
;;   Implementation ::= Implementation Global Expr
;;   Pattern     ::= Wild | Bind Local | Equals Datum | Destructure TopValue Pattern*
;;
;;   Type        ::= Con Global Type* | Callable Former Contract Arrow | Code Arrow
;;                 | Row Effects | Var TypeVariable                  no Loc
;;   Arrow       ::= Arrow Type* Type Effects                        no Loc
;;   Effects     ::= Effects Global* Type?                           no Loc
;;   TypeVariable ::= Written name | Associated number label
;;                  | CallableArgument number | Own TypeVariable     no Loc
;;   Scheme      ::= Scheme TypeVariable* Requirement* TypeVariable* Type   no Loc
;;   Requirement ::= ClassRequirement ClassRef Type*
;;                 | CallableRequirement Contract Type Arrow         no Loc
;;
;; Every other rule is Expanded's, (snail compiler expand language):
;; Constant, Local, Global, TopValue, FieldRole, Label, Annotation, ClassRef,
;; Former and Contract; and Datum is Syntax's.
;;
;; Over the Derived library it comes from, Declared guarantees:
;;
;; - Every written type is a Type, and every signature a Scheme. A Con is
;;   a struct, an enum or a builtin of (snail core forms), at as many
;;   arguments as it takes. No alias remains, nor a projection: each is
;;   the type the one requirement in scope of its class, matched on the
;;   class's selecting arguments, gives the output. Types carry no Loc:
;;   they are values, compared and substituted as values.
;; - A row's labels are a set: each effect once, in the order of their
;;   Globals (library, then name, then serial). Its tail, when it has one,
;;   is what the row was written to end with: a variable, or, where an
;;   alias's parameter ends it, the type the alias's argument wrote, kept
;;   as written, which may be a row itself or any other type. Two rows
;;   with the same labels and the same tail are the same value; a row
;;   whose tail is a row is not the same value as the one row they make.
;; - A scheme quantifies, in this order, its written variables; then each
;;   output a class requirement leaves unwritten, `(Associated n label)`
;;   for its requirement at position `n` among the scheme's requirements,
;;   in the order of the requirements and, within one, of its class's
;;   outputs; then, when its type is a callable or code, a variable for
;;   each `impl` parameter of it, `(CallableArgument n)` at position `n`
;;   among the scheme's variables, in the order of the parameters. Each
;;   such parameter is that variable, and a callable requirement of it,
;;   at the parameter's contract and arrow, follows the written ones, in
;;   the same order. A number names a variable by its position in the
;;   scheme that introduces it, as the old compiler names it, and keeps it
;;   when the scheme is combined with another. An instance quantifies its
;;   head's variables, then its requirements' unwritten outputs, alike.
;; - When a scheme's type is a callable or code, its result is no `impl`
;;   callable, and no `impl` is within its result or a parameter where the
;;   old compiler looks: a Con's arguments, and the parameters and results
;;   of callables and code, but not a row.
;; - A class requirement gives each of its class's parameters, its
;;   outputs last, in the class's order, and each row parameter a row or a
;;   variable, as far as the class's rows were known where it was written.
;;   A callable requirement is the compiler's, never an instance's. The
;;   variables a scheme says `Copy` are apart from its requirements, which
;;   have evidence, by position.
;; - Every declaration is its entity. A struct or an enum is Data, with
;;   each case's tag its position and each field its type; whether it
;;   derives Move, and whether its library declares a Drop instance for
;;   it. A class knows which of its parameters are rows, and each method's
;;   own scheme over the class's parameters and outputs. An operation is
;;   its parameters, result and latent effects, without its own effect.
;;   A method's, an operation's and a primitive's scheme, and an extern's
;;   type, is operational: a callable or code there is `(Callable Dyn
;;   FnContract arrow)` of its arrow, as the old compiler makes executable
;;   code's type its bare arrow.
;; - Every label is the member it names: a method definition's is a
;;   method of its instance's class, a default's and a handler clause's an
;;   operation of the effect, and an equation's an output, which the head
;;   or the requirement now gives in place. A path's labels stay labels,
;;   since each names its field class, which every label has.
;; - Each instance has a Global of its own; so does each method
;;   implementation and each default, and a default written as a name is
;;   the lambda that calls it, with locals of its own. A `case-id` is its
;;   case and the case's TypeId. Each definition carries the last
;;   signature written for it and the annotations of every one.
;; - No Signature, LocalSignature, Struct, Enum or Equation remains; every
;;   check `declare` makes holds.
;; - The root's `first-unused-number` counts the Globals and locals
;;   `declare` wrote.
;; - Declarations stay in the order written, so `dispatch` can find the
;;   instances written before a `dynamic-instances` form, and the adapter
;;   the old compiler's order of items and of each class's instances.
(define-library (snail compiler declare language)
  (export
   Declared
   Defined
   Program
   Top
   LinkImport
   Define
   Statement
   Expose
   TopData
   Alias
   TopClass
   TopInstance
   InstanceSet
   InstanceScope
   Extern
   TopEffect
   Primitive
   Signed
   Data
   DataKind
   StructData
   EnumData
   DataCase
   DataField
   Class
   ClassParameter
   TypeParameter
   RowParameter
   Output
   Method
   Instance
   InstanceBody
   Dispatch
   Methods
   InstanceMethod
   Member
   ClassMethod
   FieldReader
   SetMember
   SetInstance
   DynamicInstances
   Effect
   Operation
   Default
   PrimitiveType
   PrimitiveScheme
   CallableOnce
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
   Destructure
   Type
   Con
   Callable
   Code
   Row
   Var
   Arrow
   Effects
   TypeVariable
   Written
   Associated
   CallableArgument
   Own
   Scheme
   Requirement
   ClassRequirement
   CallableRequirement)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler read language) Datum)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language)
         Constant
         Local
         Global
         TopValue
         Label
         Annotation
         ClassRef
         Former
         Contract))
  (begin

    ;; ---- Libraries ----

    ;; As Derived's, with the first number the library has not used once
    ;; `declare` has numbered its instances, implementations and the
    ;; locals of the lambdas it wrote.
    (enum Declared
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

    ;; In the order written. A Define carries the last signature written
    ;; for its Global, the one the old compiler's signature table keeps,
    ;; and the annotations of every signature written for it; a signature
    ;; naming any other value leaves nothing but its annotations, on that
    ;; value's entity when this library declares it. An Alias is kept for
    ;; its annotations only.
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
         (signature (Option Signed))
         (annotations (List Annotation))
         (loc Loc)))
      (Statement
       ((expr Expr)))
      (Expose
       ((target TopValue)
        (symbol String)
        (dynamic? Bool)
        (loc Loc)))
      (TopData
       ((data Data)))
      (Alias
       ((global Global)
        (parameters (List String))
        (annotations (List Annotation))
        (loc Loc)))
      (TopClass
       ((class Class)))
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
        (type Type)
        (annotations (List Annotation))
        (loc Loc)))
      (TopEffect
       ((effect Effect)))
      (Primitive
       ((global Global)
        (type PrimitiveType)
        (loc Loc))))

    ;; A signature, at its `(:` form, which the old compiler records as
    ;; where the definition's signature was written.
    (struct Signed
      ((scheme Scheme)
       (loc Loc)))

    ;; ---- Data ----

    ;; A struct is one case, whose Global is the struct's own; an enum's
    ;; cases are its constructors, each tagged by its position. A struct
    ;; with no mutable field is a value read by path: each of its fields
    ;; implies the instance of its label's field class that reads it.
    ;; `move?` says that a deriving clause of the declaration names Move,
    ;; and `drop?` that its library declares a Drop instance for it, which
    ;; only that library can and which decides who may take its values
    ;; apart; either makes its values moved, never copied. Field functions
    ;; and their schemes follow from the kind and each field.
    (struct Data
      ((global Global)
       (parameters (List String))
       (cases (List DataCase))
       (kind DataKind)
       (move? Bool)
       (drop? Bool)
       (annotations (List Annotation))
       (loc Loc)))

    (enum DataKind
      (StructData)
      (EnumData))

    (struct DataCase
      ((global Global)
       (tag I64)
       (fields (List DataField))
       (annotations (List Annotation))
       (loc Loc)))

    (struct DataField
      ((label String)
       (mutable? Bool)
       (type Type)
       (annotations (List Annotation))
       (loc Loc)))

    ;; ---- Classes ----

    ;; A class's written parameters, each a type or, when a method's type
    ;; ends a row with it, a row; then its outputs, which are types. Each
    ;; method's scheme is its own: the variables and requirements its
    ;; signature writes, over the class's parameters and outputs as Written
    ;; variables. The scheme of the method as a value, which quantifies the
    ;; class's parameters first and requires the class first, follows.
    (struct Class
      ((global Global)
       (parameters (List ClassParameter))
       (outputs (List Output))
       (methods (List Method))
       (annotations (List Annotation))
       (loc Loc)))

    (enum ClassParameter
      (TypeParameter
       ((name String)))
      (RowParameter
       ((name String))))

    (struct Output
      ((label Label)
       (annotations (List Annotation))))

    (struct Method
      ((global Global)
       (scheme Scheme)
       (annotations (List Annotation))
       (loc Loc)))

    ;; ---- Instances ----

    ;; An instance, named by a Global `declare` numbers. Its variables are
    ;; the names its head leaves unbound, in the order first written, then
    ;; each output its requirements leave unwritten. `types` gives each of
    ;; the class's written parameters, in order, a row for each row
    ;; parameter and a type that is no row for each other; `outputs` gives
    ;; each output, in the class's order, the type its equation wrote. So
    ;; the types an instance is selected by are the head's types that are
    ;; no row. Whether it is in a named set is where it is: inside an
    ;; InstanceSet. Its methods, when written, implement each method of
    ;; the class once, in the order written, each a top-level definition of
    ;; its own Global; a dispatch clause's types wait for `dispatch`.
    (struct Instance
      ((global Global)
       (class ClassRef)
       (variables (List TypeVariable))
       (types (List Type))
       (outputs (List Type))
       (requirements (List Requirement))
       (copied (List TypeVariable))
       (body InstanceBody)
       (loc Loc)))

    (enum InstanceBody
      (Dispatch
       ((types (List Type))
        (loc Loc)))
      (Methods
       ((methods (List InstanceMethod)))))

    ;; A method definition, at its name: the member it implements, the
    ;; Global that holds the implementation, and its value. Its scheme is
    ;; the member's at the instance's head.
    (struct InstanceMethod
      ((member Member)
       (implementation Global)
       (value Expr)
       (loc Loc)))

    ;; A declared class's method, or the one method of a label's field
    ;; class, `::label`, which reads the field.
    (enum Member
      (ClassMethod
       ((global Global)))
      (FieldReader
       ((label String))))

    (enum SetMember
      (SetInstance
       ((instance Instance)))
      (DynamicInstances
       ((class ClassRef)
        (pairs (List (List Type)))
        (loc Loc))))

    ;; ---- Effects ----

    ;; An operation's parameters and result, and its latent effects: what
    ;; its implementations may perform where it is performed, a closed set,
    ;; in the order of their Globals, without the effect itself. Its type
    ;; as a value adds the effect.
    (struct Effect
      ((global Global)
       (operations (List Operation))
       (defaults (List Default))
       (around-main? Bool)
       (annotations (List Annotation))
       (loc Loc)))

    (struct Operation
      ((global Global)
       (control? Bool)
       (parameters (List Type))
       (result Type)
       (latent (List Global))
       (annotations (List Annotation))
       (loc Loc)))

    ;; A default, at its entry: the operation, the Global that holds its
    ;; implementation, and the implementation, a Lambda or a ClosedLambda.
    ;; One written as a function's name is the lambda that calls it with
    ;; the operation's arguments.
    (struct Default
      ((operation Global)
       (implementation Global)
       (value Expr)
       (loc Loc)))

    ;; A primitive's operational scheme, or `callable-once`, the signature
    ;; of `once`, whose type would need a variable standing for an arrow,
    ;; which no Type writes.
    (enum PrimitiveType
      (PrimitiveScheme
       ((scheme Scheme)))
      (CallableOnce))

    ;; ---- Expressions ----

    ;; As Derived's, but: every type is a Type, and a let's signature a
    ;; Scheme; a local signature that annotates no definition is gone,
    ;; checked; a handler's clause names its operation; and a `case-id` is
    ;; the case its constructor makes, with that case's TypeId, which no
    ;; later pass computes again.
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
        (type Type)
        (loc Loc)))
      (Convert
       ((expr Expr)
        (type Type)
        (loc Loc)))
      (TryConvert
       ((expr Expr)
        (type Type)
        (loc Loc)))
      (TypeTest
       ((expr Expr)
        (type Type)
        (loc Loc)))
      (CaseId
       ((case Global)
        (id I64)
        (loc Loc))))

    (struct Clause
      ((pattern Pattern)
       (body Expr)
       (loc Loc)))

    ;; A handler's implementation of the operation it names.
    (struct Implementation
      ((operation Global)
       (value Expr)
       (loc Loc)))

    ;; ---- Patterns ----

    ;; As Derived's. A Destructure's constructor of a type with a Drop
    ;; instance is in that type's library. A value that is no constructor
    ;; stays as written, for the checker to refuse, as the old one does.
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

    ;; ---- Types ----

    ;; A declared or builtin type at its arguments. `(impl (Fn ...))` and
    ;; `(dyn (FnMut ...))` are Callables; `(dyn (Fn ...))` is a Callable
    ;; too, which the old compiler writes as its bare arrow. `(fn ...)` is
    ;; Code. A Row is `(! effect ... tail)` as a type argument, as `e` in
    ;; `(Store (! io) S)`.
    (enum Type
      (Con
       ((type Global)
        (arguments (List Type))))
      (Callable
       ((former Former)
        (contract Contract)
        (arrow Arrow)))
      (Code
       ((arrow Arrow)))
      (Row
       ((effects Effects)))
      (Var
       ((variable TypeVariable))))

    (struct Arrow
      ((parameters (List Type))
       (result Type)
       (effects Effects)))

    ;; A set of effects, each once, in the order of their Globals, and the
    ;; type the row ends with, as written.
    (struct Effects
      ((labels (List Global))
       (tail (Option Type))))

    ;; A variable the source names; an output the requirement at position
    ;; `number` of the scheme that introduces it leaves unwritten; the type
    ;; the caller chooses for an `impl` parameter, the variable at position
    ;; `number` of the scheme that introduces it; or, in the scheme of an
    ;; instance's implementation of a method, one of the method's own
    ;; variables, kept apart from the instance's. None is ever a name the
    ;; compiler joined.
    (enum TypeVariable
      (Written
       ((name String)))
      (Associated
       ((number I64)
        (label String)))
      (CallableArgument
       ((number I64)))
      (Own
       ((variable TypeVariable))))

    (struct Scheme
      ((variables (List TypeVariable))
       (requirements (List Requirement))
       (copied (List TypeVariable))
       (type Type)))

    ;; A class at each of its parameters, its outputs last; or one of the
    ;; compiler's callable classes, at a receiver and an arrow, whose
    ;; evidence the compiler finds from the receiver's representation.
    (enum Requirement
      (ClassRequirement
       ((class ClassRef)
        (types (List Type))))
      (CallableRequirement
       ((contract Contract)
        (receiver Type)
        (arrow Arrow))))

    ))
