;; Dispatched, the tree `dispatch` writes: a declared library in which every
;; instance has its methods. An instance written with a dispatch clause has
;; the methods the clause stands for, and each `dynamic-instances` form is
;; the instances it generates, each with its methods.
;;
;;   Dispatched  ::= Defined library Top* first-unused-number
;;                 | Program Top* first-unused-number                no Loc
;;   Top         ::= LinkImport Global name* digest file
;;                 | Define Global Expr Signed? Annotation*
;;                 | Statement Expr                                  no Loc but its expression's
;;                 | Expose TopValue symbol dynamic?
;;                 | TopData Data                                    no Loc but its data's
;;                 | Alias Global parameter* Annotation*
;;                 | TopClass Class                                  no Loc but its class's
;;                 | TopInstance Instance                            no Loc but its instance's
;;                 | InstanceSet Global Instance*
;;                 | InstanceScope Global* Top*
;;                 | Extern Global module symbol Type Annotation*
;;                 | TopEffect Effect                                no Loc but its effect's
;;                 | Primitive Global PrimitiveType
;;   Instance    ::= Instance Global ClassRef TypeVariable* Type* Type* Requirement*
;;                            TypeVariable* InstanceMethod*
;;
;; Every other rule is Declared's, (snail compiler declare language), which
;; `dispatch` writes but never looks inside: Signed, Data, Class, Effect,
;; PrimitiveType, InstanceMethod and Member, Expr and every rule it holds;
;; and through Declared, Expanded's Annotation. The types, Scheme and
;; Requirement are the vocabulary's, (snail compiler types type) and
;; (snail compiler types scheme), as the names and literals are.
;;
;; Over the Declared library it comes from, Dispatched guarantees:
;;
;; - No dispatch clause and no `dynamic-instances` form remains. Every
;;   instance has its methods, and an instance set holds instances alone.
;;   Nothing else is added, removed or moved. Who wrote an instance's
;;   methods, the source or `dispatch`, is not kept: the old compiler marks
;;   a written method's value `function? #f` and a dispatched one's `#t`,
;;   and reads the mark only for a value a program names, which no
;;   dispatched method is.
;; - An instance written with a dispatch clause is the instance it was: its
;;   Global, class, head and place. Its methods are, for each method of its
;;   class as known where the instance is written, which is none when the
;;   class is declared later in the library, in the class's order, one
;;   InstanceMethod: the member, an implementation Global of its own named
;;   for the member, and a ClosedLambda, which reads only its parameters,
;;   as the old compiler's has no environment. For the erased parameter E,
;;   the first of the class's parameters, its outputs last, that the head
;;   gives Any; the targets T1 ... Tn; and a method m whose type, at the
;;   head's other types, is (Fn P0 ... Pk -> R ! effects), where Ps is the
;;   first parameter that is E, the ClosedLambda is what this source
;;   stands for, up to the names of locals:
;;
;;     (fn (p0 ... pk)
;;       (match (try-convert ps T1)
;;         ((Ok selected) (m a0 ... ak))
;;         (_ (match (try-convert ps T2)
;;              ...
;;              (_ (match (conversion-failed
;;                         (CastError (UnsupportedInstance)
;;                                    (Cons "T1" (Cons "T2" ... (Nil)))
;;                                    (any-type-id ps)
;;                                    "FILE:LINE:COLUMN"
;;                                    "LIBRARY:m"
;;                                    s))))))))
;;
;;   where, in the branch for Tj, as is `selected`; ai, for another
;;   parameter Pi that is E, is
;;
;;     (match (try-convert pi Tj)
;;       ((Ok recovered) recovered)
;;       (_ (match (conversion-failed
;;                  (CastError (ArgumentMismatch) (Cons "Tj" (Nil))
;;                             (any-type-id pi) "FILE:LINE:COLUMN" "LIBRARY:m" i)))))
;;
;;   and pi otherwise; and the call is `(convert (m ...) Any)` when R is E.
;;   The `m` called is the class's method, a TopRef of its Global; a field
;;   class's reader is the read `(::label selected)` itself, a PathApply,
;;   as `expand` writes it. A `match` there with no clause is one of no
;;   clauses, typed by where it is: `conversion-failed` never returns.
;; - Each `dynamic-instances` form is, in its place among its set's
;;   members, the instances it generates, at the form. For a class
;;   (C e A B) with output O and methods m ..., and for each pair (L R) of
;;   the domain the one source instance S active where the form is, whose
;;   head matches the pair, with S's output and closed row at that match,
;;   the heads are, for the pairs in order, (Any R), (L Any) and (Any Any),
;;   each once, in the order first met. The instance for head (H1 H2) is
;;   what this source stands for:
;;
;;     (instance (C (! dyn-cast effect ...) H1 H2)
;;       (type O output)
;;       (define m (fn (left right) body)) ...)
;;
;;   Its cases are the domain's pairs it accepts, each side Any or the
;;   pair's, in domain order. Its output is the one output its cases share,
;;   or Any; its row, dyn-cast and every effect of its cases' rows. It has
;;   a Global of its own, named `dynamic`, and no variables, requirements
;;   or Copy variables; its methods are one for each method of the class,
;;   in order, each with an implementation Global named for its member.
;;   Each body tries the cases in order. A case recovers each side its
;;   head erases:
;;
;;     (match (try-convert left L)            ; only H1 is Any
;;       ((Ok left1) (S.m left1 right))
;;       (_ next))
;;     (match (Pair (try-convert left L) (try-convert right R))   ; both are
;;       ((Pair (Ok left1) (Ok right1)) (S.m left1 right1))
;;       (_ next))
;;
;;   where S.m is the implementation Global of m in the case's source,
;;   called directly, as `(convert (S.m ...) Any)` when the instance's
;;   output is Any and the case's is not. After the last case, when H1 is
;;   concrete, it fails for the right side, the cases' Rs and index 1:
;;
;;     (match (conversion-failed
;;             (CastError (UnsupportedInstance) (Cons "R" ... (Nil))
;;                        (any-type-id right) "FILE:LINE:COLUMN" "LIBRARY:m" 1)))
;;
;;   when H2 is, for the left side, the Ls, index 0; when both are Any,
;;   for each distinct L in order, `(if (type-test left L) <the right
;;   side's failure over the cases of that L> next)`, ending in the left
;;   side's failure over every L.
;; - The texts a CastError holds are the old compiler's, as
;;   (snail compiler dispatch text) writes them: each type as it writes a
;;   type, the place as it writes a Loc, and the method by its library and
;;   name, the old unique name of a method no macro wrote.
;; - Every node `dispatch` writes is at the instance's form, or at the
;;   form's. Every Global it names but its own is the old compiler's
;;   constant: of (snail core base), Ok, Pair, Cons, Nil, CastError,
;;   UnsupportedInstance, ArgumentMismatch, conversion-failed and dyn-cast;
;;   of ("prim"), any-type-id; of (snail core forms), Any.
;; - Every check `dispatch` makes holds: a dispatch clause's head is ground
;;   with one Any and a class no lifecycle class, its targets are distinct
;;   ground types and none Any, and each method of its class is a function
;;   of the class's parameters alone, with no requirement but its class,
;;   whose result and parameters are E or do not mention it, one of them
;;   E; a form's class is binary, with one row, one output and methods of
;;   type (Fn A B -> Output ! e), its domain nonempty and distinct pairs of
;;   two ground types, none Any, each with one active source of no
;;   requirements, a determined output and a closed row, and no head
;;   gives a type parameter a row.
;; - The root's `first-unused-number` counts the instances, implementations
;;   and locals `dispatch` wrote, numbered from Declared's.
(define-library (snail compiler dispatch language)
  (export
   Dispatched
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
   Instance)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries)
   (only (snail compiler expand language) Annotation)
   (only (snail compiler names globals) Global TopValue ClassRef)
   (only (snail compiler declare language)
         Signed
         Data
         Class
         Effect
         PrimitiveType
         InstanceMethod
         Expr)
   (only (snail compiler types type) Type TypeVariable)
   (only (snail compiler types scheme) Requirement))
  (begin

    ;; ---- Libraries ----

    ;; As Declared's, with the first number the library has not used once
    ;; `dispatch` has numbered its instances, implementations and the
    ;; locals of the lambdas it wrote.
    (enum Dispatched
      (Defined
        ((name LibraryName)
         (tops (List Top))
         (first-unused-number I64)
         (loc Loc)))
      (Program
       ((tops (List Top))
        (first-unused-number I64))))

    ;; ---- Declarations ----

    ;; As Declared's, but that an instance set holds instances alone: each
    ;; it held, and in place of each `dynamic-instances` form, the
    ;; instances it generates.
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
        (instances (List Instance))
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

    ;; ---- Instances ----

    ;; As Declared's, but that it has its methods in place of a body.
    ;; `types` gives each of the class's written parameters, a row for each
    ;; parameter known to be a row where the instance is written and a
    ;; type that is no row for each other, and `outputs` each output. Its
    ;; methods implement every method of its class as known where it is
    ;; written, each a top-level definition of its own Global: those
    ;; written, in the order written, or those `dispatch` wrote, in the
    ;; class's order. A generated instance is at its form and has no
    ;; variables, requirements or Copy variables.
    (struct Instance
      ((global Global)
       (class ClassRef)
       (variables (List TypeVariable))
       (types (List Type))
       (outputs (List Type))
       (requirements (List Requirement))
       (copied (List TypeVariable))
       (methods (List InstanceMethod))
       (loc Loc)))

    ))
