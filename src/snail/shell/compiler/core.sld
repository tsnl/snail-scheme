;; The core language shared by every pass after expansion. The expander
;; produces a Program: entity tables keyed by unique names, and an ordered list
;; of top-level items. The checker fills in each expression's type; the
;; monomorphizer replaces type arguments with ground types.
(define-library (snail shell compiler core)
  (export
   Type
   TCon
   TFun
   borrow-type?
   borrow-target
   TRow
   TVar
   TRigid
   TVar-id
   empty-row
   fn-arrow
   callable-class?
   callable-class
   callable-implies?
   callable-kind
   callable-arrow
   concrete-callable?
   concrete-callable
   impl-callable?
   callable-captures
   invocation-mode
   mut-row
   unchecked
   Constraint
   Scheme
   mono-scheme
   Substitution
   type->string
   type-key
   any-type?
   never-type?
   drop-class
   clone-class
   lifecycle-class?
   field-class?
   field-class-name
   program-with-field-class
   program-with-field-instance
   field-instance-accessor
   local-name
   string-type?
   bytes-type?
   buffer-type?
   hidden-effects
   labels->string
   type=?
   types=?
   optional-any-type?
   short-name
   name-owner
   substitute
   substitute-constraint
   label-union
   label-difference
   builtin-types
   core-keywords
   Evidence
   EvInstance
   EvParam
   EvDerived
   EvHole
   Plan
   Trivial
   Implemented
   Glue
   Refused
   Expr
   Term
   Lit
   Var
   Lambda
   App
   If
   Let
   Seq
   Match
   Ann
   ScopedInstances
   Handle
   Convert
   TryConvert
   TypeTest
   Clause
   Pattern
   PWild
   PVar
   PLit
   PCon
   lambda-expr?
   expr-references
   expr-children
   DataType
   DataType-owned?-set
   Case
   Field
   Class
   row-arguments
   type-arguments
   match-types
   match-type
   output-arguments
   row-variable
   Instance
   Instance-methods-set
   Import
   Effect
   operation-latent
   Value
   Defined
   Constructor
   Accessor
   Replacer
   Setter
   Swapper
   Method
   Operation
   Primitive
   Foreign
   value-scheme
   Item
   Define
   Define-name
   Define-value
   Do
   Expose
   item-definitions
   Program
   Program-items-set
   empty-program
   primitive-global
   primitive-delta
   program-annotations
   program-field-annotations
   program-with-annotations
   program-with-field-annotations
   program-value
   program-type
   program-class
   program-effect
   class-instances
   visible-instances
   check-instance-overlap
   check-active-instances
   selected-method-arguments
   program-with-value
   program-with-type
   program-with-class
   program-with-instance
   program-with-effect
   program-with-library
   program-delta
   program-with
   table-union
   program-items
   library-items
   fnv-offset
   fnv-step
   fnv-1a
   type-id
   case-type-id
   any-type-id
   wide-hash
   wide-type-id
   wire-schemas
   strong-components)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler annotations))
  (begin

    ;; ---- Types ----

    ;; `TCon` names a builtin or declared type by its unique name. A row is a
    ;; set of effect labels, kept sorted, with an optional tail: a type
    ;; variable standing for more labels. Metavariables exist only inside the
    ;; checker, which binds their cells.
    (enum Type
      (TCon
       ((name String)
        (args (List Type))))
      (TFun
       ((params (List Type))
        (result Type)
        (row Type)))
      (TRow
       ((labels (List String))
        (tail (Option Type))))
      (TVar
       ((id I64)))
      (TRigid
       ((name String))))

    (define empty-row (→ Type) (TRow (Nil) (None)))

    ;; Borrow is a scoped, non-owning value type. It remains visible in
    ;; locals and signatures through checking; only representation lowering
    ;; uses its target. Lexical ownership checking proves where it may live.

    (define (borrow-type? (type Type)) (→ Bool)
      (match type
        ((TCon "Borrow" (Cons _ (Nil))) #t)
        (_ #f)))

    (define (borrow-target (type Type)) (→ Type)
      (match type
        ((TCon "Borrow" (Cons value (Nil))) value)
        (_ type)))

    ;; The signature a callable holds, including `(fn A → B ! e)` code; any
    ;; other type is its own.

    (define (fn-arrow (type Type)) (→ Type)
      (match (callable-arrow type)
        ((Some arrow) arrow)
        ((None) type)))

    ;; ---- Callable contracts ----

    ;; A concrete closure keeps its construction identity and capture types.
    ;; Its first argument is its calling signature; the remaining arguments
    ;; are the owned environment. Generic instantiation substitutes both.
    ;; These compiler names cannot be written as source type constructors.

    (define (concrete-callable (kind String) (identity String) (arrow Type) (captures (List Type)))
      (→ Type)
      (TCon (string-append "$callable." kind ":" identity) (Cons arrow captures)))

    (define (concrete-callable? (type Type)) (→ Bool)
      (match type
        ((TCon name _)
         (and (>= (string-length name) 10) (string=? (substring name 0 10) "$callable.")))
        (_ #f)))

    (define (impl-callable? (type Type)) (→ Bool)
      (match type
        ((TCon name _) (member? name (list "$impl.Fn" "$impl.FnMut" "$impl.FnOnce")))
        (_ #f)))

    (define (callable-captures (type Type)) (→ (List Type))
      (match type
        ((TCon _ (Cons _ captures)) (if (concrete-callable? type) captures (Nil)))
        (_ (Nil))))

    (define (callable-class (kind String)) (→ String)
      (string-append "snail.core.base:" kind))

    (define (callable-class? (name String)) (→ Bool)
      (member? name (map callable-class (list "Fn" "FnMut" "FnOnce"))))

    ;; This implication is about receiver access, never Copy or purity.

    (define (callable-implies? (actual String) (required String)) (→ Bool)
      (or (string=? actual required)
          (string=? actual "Fn")
          (and (string=? actual "FnMut") (string=? required "FnOnce"))))

    (define (callable-kind (type Type)) (→ (Option String))
      (match type
        ((TFun _ _ _) (Some "Fn"))
        ((TCon name _)
         (cond ((string=? name "fn") (Some "Fn"))
               ((member? name (list "FnMut" "FnOnce")) (Some name))
               ((impl-callable? type)
                (Some (substring name 6 (string-length name))))
               ((concrete-callable? type)
                (let ((tail (substring name 10 (string-length name))))
                  (match (string-index tail #\:)
                    ((Some end) (Some (substring tail 0 end)))
                    ((None) (None)))))
               (else (None))))
        (_ (None))))

    (define (callable-arrow (type Type)) (→ (Option Type))
      (match type
        ((TFun _ _ _) (Some type))
        ((TCon _ (Cons arrow _))
         (match (callable-kind type) ((Some _) (Some arrow)) ((None) (None))))
        (_ (None))))

    ;; An invocation records the receiver operation the checker selected.
    ;; It remains attached through specialization: a FnOnce requirement
    ;; consumes its receiver even when the concrete value also implements Fn.

    (define (invocation-mode (callee Expr)) (→ (Option String))
      (match (::term callee)
        ((Ann _ (TCon "$invoke" (Cons (TCon mode (Nil)) _))) (Some mode))
        (_ (None))))

    ;; The row of an operation on a mutable field, which reads or writes
    ;; storage and nothing else.

    (define mut-row (→ Type) (TRow (list "mut") (None)))

    ;; The type of an expression the checker has not yet seen. The checker
    ;; rebuilds every expression, so no later pass meets it.

    (define unchecked (→ Type) (TCon "unchecked" (Nil)))

    (struct Constraint
      ((class String)
       (types (List Type))))

    ;; A scheme quantifies rigid variables, which may stand for types or rows.
    ;; `copy` names those a `(⊨ (Copy A))` declares ω, whose values
    ;; may be duplicated and discarded. It is no class constraint, as it has
    ;; no evidence: a constraint's evidence is its position among the
    ;; constraints. The others will be linear (#550); until then every
    ;; variable ranges over ω types.
    (struct Scheme
      ((vars (List String))
       (constraints (List Constraint))
       (copy (List String))
       (type Type)))

    (define (mono-scheme (type Type)) (→ Scheme)
      (Scheme (Nil) (Nil) (Nil) type))

    ;; The names of the core forms, which the expander binds in
    ;; (snail core forms) and (snail shell highlight) colors as keywords.

    (define core-keywords (→ (List String))
      (list "define"
            "lambda"
            "fn"
            "if"
            "begin"
            "let"
            "define-syntax"
            "syntax-rules"
            "quote"
            ":"
            "struct"
            "enum"
            "type"
            "typeclass"
            "instance"
            "define-instance-set"
            "with-instances"
            "match"
            "ann"
            "extern"
            "primitive"
            "effect"
            "handle"
            "expose"
            "case-id"
            "type-convert"
            "try-convert"
            "type-test"
            "artifact-files" "link-handle"))

    (define builtin-types (→ (List (Pair String I64)))
      (list (Pair "Any" 0)
            (Pair "Borrow" 1)
            (Pair "Funcref" 0)
            (Pair "U8" 0)
            (Pair "I32" 0)
            (Pair "I64" 0)
            (Pair "F32" 0)
            (Pair "F64" 0)
            (Pair "Bool" 0)
            (Pair "Char" 0)
            (Pair "Unit" 0)
            (Pair "String" 0)
            (Pair "Array" 1)
            (Pair "Vector" 1)
            (Pair "FnOnce" 1)
            (Pair "FnMut" 1)
            (Pair "fn" 1)))

    ;; Unique names look like `snail.core.base:map`; diagnostics show the source
    ;; name. Text is scanned as a vector of characters, which both hosts index
    ;; in constant time.

    (define (short-name (name String)) (→ String)
      (let ((chars (string->vector name)))
        (let loop ((index (- (vector-length chars) 1)))
          (cond ((< index 0) name)
                ((char=? (vector-ref chars index) #\:)
                 (substring name (+ index 1) (string-length name)))
                (else (loop (- index 1)))))))

    ;; A local's source name: its unique name without the `.N` suffix.

    (define (local-name (name String)) (→ String)
      (match (last-dot name)
        ((Some index) (substring name 0 index))
        ((None) name)))

    (define (last-dot (name String)) (→ (Option I64))
      (let loop ((index (- (string-length name) 1)))
        (cond ((< index 0) (None))
              ((char=? (string-ref name index) #\.) (Some index))
              (else (loop (- index 1))))))

    ;; The library that defines a global: its name up to the first colon.

    (define (name-owner (name String)) (→ String)
      (let ((chars (string->vector name)))
        (let loop ((index 0))
          (cond ((= index (vector-length chars)) "")
                ((char=? (vector-ref chars index) #\:) (substring name 0 index))
                (else (loop (+ index 1)))))))

    ;; The host can hold an opaque Any or null, without constructing a GC
    ;; enum. This is a boundary convention, not Option's internal layout.

    (define (optional-any-type? (type Type)) (→ Bool)
      (match type
        ((TCon "snail.core.base:Option" (Cons (TCon "Any" (Nil)) (Nil))) #t)
        (_ #f)))

    (define (type->string (type Type)) (→ String)
      (if (or (concrete-callable? type) (impl-callable? type))
          (callable->string "impl" type)
          (match type
            ((TCon "FnOnce" _) (callable->string "dyn" type))
            ((TCon "FnMut" _) (callable->string "dyn" type))
            ((TCon "fn" (Cons (TFun params result row) (Nil)))
             (arrow->string "fn" params result row))
            ((TCon name (Nil)) (short-name name))
            ((TCon name args) (string-append "(" (short-name name) (types->string args) ")"))
            ((TFun _ _ _) (callable->string "dyn" type))
            ((TRow _ _) (string-append "{" (row->string type) " }"))
            ((TVar id) (string-append "?" (i64->string id)))
            ((TRigid name) name))))

    (define (callable->string (former String) (type Type)) (→ String)
      (match (Pair (callable-kind type) (callable-arrow type))
        ((Pair (Some kind) (Some (TFun params result row)))
         (string-append "(" former " " (arrow->string kind params result row) ")"))
        (_ (panic "internal error: printing a callable without its signature"))))

    (define (arrow->string (kind String) (params (List Type)) (result Type) (row Type)) (→ String)
      (string-append "(" kind (types->string params) " → " (type->string result)
                     (row->string row) ")"))

    (define (types->string (types (List Type))) (→ String)
      (string-concatenate (map (lambda (type) (string-append " " (type->string type))) types)))

    (define (row->string (row Type)) (→ String)
      (let* ((parts (row-parts row (Nil))) (labels (::first parts)) (tail (::second parts)))
        (match tail
          ((None) (if (null? labels) "" (string-append " !" (labels->string labels))))
          ((Some tail) (string-append " !" (labels->string labels) " " (type->string tail))))))

    (define (labels->string (labels (List String))) (→ String)
      (string-concatenate (map (lambda (label) (string-append " " (short-name label))) labels)))

    ;; The labels of a row, following bound tails, and its final tail.

    (define (row-parts (row Type) (labels (List String))) (→ (Pair (List String) (Option Type)))
      (match row
        ((TRow more (Some tail)) (row-parts tail (label-union labels more)))
        ((TRow more (None)) (Pair (label-union labels more) (None)))
        (_ (Pair labels (Some row)))))

    ;; Types the backend gives a representation of their own: Any boxes a
    ;; TypeId with its value, and a String or Bytes argument to a host
    ;; function is staged into the runtime's buffer, so it can come only last.

    (define (any-type? (type Type)) (→ Bool)
      (match type
        ((TCon "Any" (Nil)) #t)
        (_ #f)))

    ;; (snail core base)'s type with no values. A control operation that
    ;; answers it never resumes, so its yield saves nothing.

    (define (never-type? (type Type)) (→ Bool)
      (match type
        ((TCon "snail.core.base:Never" (Nil)) #t)
        (_ #f)))

    ;; The lifecycle classes, whose methods release a value, `(Drop e T)`,
    ;; and copy one, `(Clone e T)`, performing `e` for a T. What they run,
    ;; and so their rows, is found from T's structure, glue for a type
    ;; without an instance, rather than chosen by matching instances, so the
    ;; checker and mono treat them apart from other classes over a row.

    (define drop-class (→ String) "snail.core.base:Drop")

    (define clone-class (→ String) "snail.core.base:Clone")

    (define (lifecycle-class? (class String)) (→ Bool)
      (or (string=? class drop-class) (string=? class clone-class)))

    ;; ---- Field classes ----

    ;; Every field label `f` names a class `::f` over a record type and the
    ;; field's type, with the one method `::f`, so `(::f r)` reads the field
    ;; `f` of whatever struct `r` is. A struct without mutable fields has an
    ;; instance per field whose method is the field's accessor
    ;; (`with-field-values` in expand.sld), and a library may add an
    ;; instance for a type that computes the field. The record's type
    ;; decides the field's: the one instance whose record type matches
    ;; gives it (`improve-types` in check.sld). The class is global, with
    ;; no library prefix: `count` is the same label in every library.

    (define (field-class? (class String)) (→ Bool)
      (and (>= (string-length class) 2) (string=? (substring class 0 2) "::")))

    (define (field-class-name (label String)) (→ String)
      (string-append "::" label))

    ;; The program with a label's class and method declared.

    (define (program-with-field-class (program Program) (label String)) (→ Program)
      (let ((class (field-class-name label)))
        (if (table-contains? (::classes program) class)
            program
            (program-with-value
             (program-with-class program (Class class (list "R" "T") (Nil) (Nil) (list class)))
             class
             (Method class
                     (Scheme (list "R" "T")
                             (list (Constraint class (list (TRigid "R") (TRigid "T"))))
                             (Nil)
                             (TFun (list (TRigid "R")) (TRigid "T") empty-row)))))))

    ;; A struct's instance for one of its fields: the record type and the
    ;; field's type, read by the field's accessor. The instance is named in
    ;; the struct's library, so a replay of that library carries it.

    (define (program-with-field-instance (program Program)
                                         (data DataType)
                                         (label String)
                                         (type Type)
                                         (accessor String))
      (→ Program)
      (let ((class (field-class-name label)) (params (::params data)))
        (program-with-instance (program-with-field-class program label)
                               (Instance (string-append (name-owner (::name data))
                                                        ":"
                                                        class
                                                        "@"
                                                        (short-name (::name data)))
                                         class
                                         params
                                         (list (TCon (::name data) (map TRigid params)) type)
                                         (Nil)
                                         (Nil)
                                         (list (Pair class accessor))
                                         (None)))))

    ;; The accessor a struct's own field instance reads with, when the
    ;; instance is one; a declared instance computes its field instead.

    (define (field-instance-accessor (program Program) (class String) (instance String))
      (→ (Option Value))
      (match (find (lambda (candidate) (string=? (::name candidate) instance))
                   (class-instances program class))
        ((Some found)
         (match (assoc-ref (::methods found) class)
           ((Some target)
            (match (program-value program target)
              ((Some (Accessor case index scheme)) (Some (Accessor case index scheme)))
              (_ (None))))
           ((None) (None))))
        ((None) (None))))

    (define (string-type? (type Type)) (→ Bool)
      (match type
        ((TCon "String" (Nil)) #t)
        (_ #f)))

    (define (bytes-type? (type Type)) (→ Bool)
      (match type
        ((TCon "Vector" (Cons (TCon "U8" (Nil)) (Nil))) #t)
        (_ #f)))

    (define (buffer-type? (type Type)) (→ Bool)
      (or (string-type? type) (bytes-type? type)))

    ;; A unique text for a ground type, with full names; it names
    ;; specializations and Wasm types. A row argument, as in (Task e), does
    ;; not affect representation.

    (define (type-key (type Type)) (→ String)
      (match type
        ((TCon name (Nil)) name)
        ((TCon name args) (string-append name "<" (string-join (map type-key args) ",") ">"))
        ((TFun params result _)
         (string-append "fn<" (string-join (map type-key params) ",") "->" (type-key result) ">"))
        ((TRow _ _) "row")
        ((TRigid name) name)
        ((TVar id) (string-append "?" (i64->string id)))))

    ;; The first part of a solved type whose effects `type-key`, and so an
    ;; Any's TypeId, would hide: a function or a row argument that may
    ;; perform something, or a type variable, which may stand for either. A
    ;; data type's fields keep the rows they were declared with, so only the
    ;; type's own structure is searched.

    (define (hidden-effects (type Type)) (→ (Option Type))
      (match type
        ((TFun params result row)
         (if (empty-row? row) (first-hidden-effects (Cons result params)) (Some type)))
        ((TCon _ args) (first-hidden-effects args))
        ((TRow _ _) (if (empty-row? type) (None) (Some type)))
        ((TRigid _) (Some type))
        ((TVar _) (panic "internal error: an unsolved type in a conversion"))))

    (define (first-hidden-effects (types (List Type))) (→ (Option Type))
      (match types
        ((Cons type rest)
         (match (hidden-effects type)
           ((Some part) (Some part))
           ((None) (first-hidden-effects rest))))
        ((Nil) (None))))

    (define (empty-row? (row Type)) (→ Bool)
      (match (row-parts row (Nil))
        ((Pair (Nil) (None)) #t)
        (_ #f)))

    ;; Structural equality of types without bound metavariables.

    (define (type=? (a Type) (b Type)) (→ Bool)
      (match a
        ((TCon name args)
         (match b
           ((TCon other others) (and (string=? name other) (types=? args others)))
           (_ #f)))
        ((TFun params result row)
         (match b
           ((TFun others other-result other-row)
            (and (types=? params others) (type=? result other-result) (type=? row other-row)))
           (_ #f)))
        ((TRow labels tail)
         (match b
           ((TRow others other-tail)
            (and (= (length labels) (length others))
                 (every? (lambda (label) (member? label others)) labels)
                 (match tail
                   ((Some tail) (match other-tail ((Some other) (type=? tail other)) ((None) #f)))
                   ((None) (match other-tail ((Some _) #f) ((None) #t))))))
           (_ #f)))
        ((TVar id)
         (match b
           ((TVar other) (= id other))
           (_ #f)))
        ((TRigid name)
         (match b
           ((TRigid other) (string=? name other))
           (_ #f)))))

    (define (types=? (as (List Type)) (bs (List Type))) (→ Bool)
      (and (= (length as) (length bs))
           (every? (lambda (pair) (type=? (::first pair) (::second pair))) (zip as bs))))

    ;; ---- Label sets ----

    ;; Row labels are sorted lists without duplicates, so equal sets print
    ;; alike.

    (define (label-insert (label String) (labels (List String))) (→ (List String))
      (match labels
        ((Nil) (list label))
        ((Cons first rest)
         (cond ((string=? label first) labels)
               ((string<? label first) (Cons label labels))
               (else (Cons first (label-insert label rest)))))))

    (define (label-union (a (List String)) (b (List String))) (→ (List String))
      (fold-left (lambda (labels label) (label-insert label labels)) a b))

    (define (label-difference (a (List String)) (b (List String))) (→ (List String))
      (filter (lambda (label) (not (member? label b))) a))

    ;; ---- Substitution ----

    (type Substitution (List (Pair String Type)))

    ;; Replaces rigid variables by the types a substitution gives them.

    (define (substitute (substitution Substitution) (type Type)) (→ Type)
      (match type
        ((TRigid name)
         (match (assoc-ref substitution name)
           ((Some replacement) replacement)
           ((None) type)))
        ((TCon name args) (TCon name (map (lambda (arg) (substitute substitution arg)) args)))
        ((TFun params result row)
         (TFun (map (lambda (param) (substitute substitution param)) params)
               (substitute substitution result)
               (substitute substitution row)))
        ((TRow labels (Some tail))
         (match (substitute substitution tail)
           ((TRow more rest) (TRow (label-union labels more) rest))
           (other (TRow labels (Some other)))))
        (_ type)))

    (define (substitute-constraint (substitution Substitution) (constraint Constraint))
      (→ Constraint)
      (Constraint (::class constraint)
                  (map (lambda (type) (substitute substitution type))
                       (::types constraint))))

    ;; ---- Class evidence ----

    ;; Evidence says which instance satisfies a constraint: an instance applied
    ;; to type arguments and the evidence for its requirements, or the
    ;; enclosing definition's own requirement at `index`. A Drop or Clone
    ;; constraint's is derived: the checker records the plan it charged,
    ;; or None for a type variable, whose instantiation's plan its caller
    ;; charged, and mono finds the plan again from the ground type and
    ;; checks that it runs no more (`plan-covers?` in capabilities.sld).
    ;; Holes exist only while checking.
    (enum Evidence
      (EvInstance
       ((instance String)
        (types (List Type))
        (subs (List Evidence))))
      (EvParam
       ((index I64)))
      (EvDerived
       ((plan (Option Plan))))
      (EvHole
       ((id I64))))

    ;; What a drop or a clone of a type runs: nothing but a discard or a
    ;; share, an instance's method, or glue, which takes the value apart, or
    ;; why it cannot run (`lifecycle-plan` in capabilities.sld).
    (enum Plan
      (Trivial)
      (Implemented
       ((instance Instance)))
      (Glue)
      (Refused
       ((reason String))))

    ;; ---- Expressions ----

    ;; Every expression has a type, `unchecked` until checked, and a location.
    (struct Expr
      ((term Term)
       (type Type)
       (loc Loc)))

    ;; Names are unique: locals are `x.12`, globals `library:name`. A variable
    ;; records the type arguments and class evidence of its instantiation.
    (enum Term
      (Lit
       ((value Datum)))
      (Var
       ((name String)
        (types (List Type))
        (evidence (List Evidence))))
      ;; A closure. `captures?` says whether it may read the locals around
      ;; it: the surface `lambda` may, a `fn` may not, and neither may a
      ;; top-level function, which has none around it. The checker refuses a
      ;; closure that reads one it may not (`check-closed`), so a closure
      ;; marked so has no environment wherever it is compiled.
      (Lambda
       ((params (List String))
        (body Expr)
        (captures? Bool)))
      (App
       ((callee Expr)
        (args (List Expr))))
      (If
       ((test Expr)
        (then Expr)
        (otherwise Expr)))
      (Let
       ((name String)
        (value Expr)
        (body Expr)))
      (Seq
       ((first Expr)
        (rest Expr)))
      (Match
       ((scrutinee Expr)
        (clauses (List Clause))))
      (ScopedInstances
       ((sets (List String))
        (body Expr)))
      (Ann
       ((expr Expr)
        (type Type)))
      (Handle
       ((effect String)
        (implementations (List (Pair String Expr)))
        (body Expr)))
      (Convert
       ((expr Expr)
        (target Type)))
      (TryConvert
       ((expr Expr)
        (target Type)))
      (TypeTest
       ((expr Expr)
        (target Type))))

    (struct Clause
      ((pattern Pattern)
       (body Expr)))

    (enum Pattern
      (PWild
       ((type Type)))
      (PVar
       ((name String)
        (type Type)))
      (PLit
       ((value Datum)
        (type Type)))
      (PCon
       ((constructor String)
        (args (List Pattern))
        (type Type))))

    (define (lambda-expr? (expr Expr)) (→ Bool)
      (match (::term expr)
        ((Lambda _ _ _) #t)
        (_ #f)))

    ;; Immediate structural children, in source order, including lambda
    ;; bodies. This describes the IR shape, not when an expression runs.

    (define (expr-children (expr Expr)) (→ (List Expr))
      (match (::term expr)
        ((Lit _) (Nil))
        ((Var _ _ _) (Nil))
        ((Lambda _ body _) (list body))
        ((App callee args) (Cons callee args))
        ((If test then otherwise) (list test then otherwise))
        ((Let _ value body) (list value body))
        ((Seq first rest) (list first rest))
        ((Match scrutinee clauses) (Cons scrutinee (map ::body clauses)))
        ((ScopedInstances _ body) (list body))
        ((Ann inner _) (list inner))
        ((Convert inner _) (list inner))
        ((TryConvert inner _) (list inner))
        ((TypeTest inner _) (list inner))
        ((Handle _ implementations body) (append (map ::second implementations) (list body)))))

    ;; Every name an expression refers to, once each, in order of first
    ;; occurrence. Locals are included, since names are unique.

    (define (expr-references (expr Expr)) (→ (List String))
      (reverse (::second (collect-references (Pair empty-table (Nil)) expr))))

    ;; Adds the names not yet seen to the found list, newest first, and to
    ;; the seen table.

    (define (collect-references (found (Pair (Table Bool) (List String))) (expr Expr))
      (→ (Pair (Table Bool) (List String)))
      (match (::term expr)
        ((Var name _ _)
         (match found
           ((Pair seen names)
            (if (table-contains? seen name)
                found
                (Pair (table-set seen name #t) (Cons name names))))))
        (_ (fold-left collect-references found (expr-children expr)))))

    ;; ---- Declared entities ----

    ;; A struct is a data type with one case named after it. An `owned?`
    ;; type is linear by its declaration, whatever its fields: it says
    ;; `(deriving Move)`, or has a Drop instance.
    (struct DataType
      ((name String)
       (params (List String))
       (cases (List Case))
       (enum? Bool)
       (owned? Bool)))

    (struct Case
      ((name String)
       (type String)
       (tag I64)
       (fields (List Field))))

    ;; A mutable field is a place: it is read and written in the struct
    ;; that holds it, so a struct with one has identity.
    (struct Field
      ((name String)
       (type Type)
       (mutable? Bool)))

    ;; Method schemes quantify the class parameters first and require the
    ;; class itself as their first constraint. `rows` are the parameters
    ;; its methods perform, as `e` in (Store e S): an instance writes each
    ;; as a row in its head. `outputs` are hidden trailing associated type
    ;; arguments. The remaining input parameters choose the evidence that
    ;; establishes outputs and the rows a method use performs.
    (struct Class
      ((name String)
       (params (List String))
       (rows (List String))
       (outputs (List String))
       (methods (List String))))

    ;; The arguments a class's constraint or instance head gives its row
    ;; parameters, and those it gives its types, each in order.

    (define (row-arguments (class Class) (types (List Type))) (→ (List Type))
      (map ::second
           (filter (lambda (pair) (member? (::first pair) (::rows class)))
                   (zip (::params class) types))))

    (define (type-arguments (class Class) (types (List Type))) (→ (List Type))
      (map ::second
           (filter (lambda (pair)
                     (not (member? (::first pair)
                                   (append (::rows class) (::outputs class)))))
                   (zip (::params class) types))))

    ;; Associated members are hidden trailing arguments. Like rows they
    ;; are established by the selected evidence, never used to select it.

    (define (output-arguments (class Class) (types (List Type))) (→ (List Type))
      (list-drop types (- (length (::params class)) (length (::outputs class)))))

    ;; One-way matching of an instance head; only its own variables bind.

    (define (match-types (vars (List String))
                         (patterns (List Type))
                         (types (List Type))
                         (bindings Substitution))
      (→ (Option Substitution))
      (if (= (length patterns) (length types))
          (fold-left (lambda (result pair)
                       (match result
                         ((Some bindings)
                          (match-type vars (::first pair) (::second pair) bindings))
                         ((None) (None))))
                     (Some bindings) (zip patterns types))
          (None)))

    (define (match-type (vars (List String)) (pattern Type) (type Type) (bindings Substitution))
      (→ (Option Substitution))
      (match pattern
        ((TRigid name)
         (if (member? name vars)
             (match (assoc-ref bindings name)
               ((None) (Some (Cons (Pair name type) bindings)))
               ((Some bound) (if (type=? bound type) (Some bindings) (None))))
             (if (type=? pattern type) (Some bindings) (None))))
        ((TCon name args)
         (match type
           ((TCon other others)
            (if (string=? name other) (match-types vars args others bindings) (None)))
           (_ (None))))
        ((TFun params result _)
         (match type
           ((TFun others other-result _)
            (match-types vars (Cons result params) (Cons other-result others) bindings))
           (_ (None))))
        (_ (None))))

    ;; The variable a row ends with, as `e` in `(! log e)`, if any.

    (define (row-variable (row Type)) (→ (List String))
      (match row
        ((TRow _ (Some (TRigid name))) (list name))
        (_ (Nil))))

    ;; Each method maps to the top-level definition that implements it.
    ;; `copy` names the instance variables its requirements declare ω, as a
    ;; scheme's does.
    (struct Instance
      ((name String)
       (class String)
       (vars (List String))
       (types (List Type))
       (requires (List Constraint))
       (copy (List String))
       (methods (List (Pair String String)))
       (set (Option String))))

    (struct Import
      ((module String)
       (symbol String)))

    ;; `control` names the operations whose implementations receive the rest
    ;; of the handled computation as `resume`; the others return to their
    ;; caller. `defaults` maps operation names to what performs them when no
    ;; handler is in scope.
    ;; Each default is an operation's and the global of the Snail-Core
    ;; function the effect's declaration defines for it, which runs under
    ;; the performer's handlers.
    ;; An effect: its operations, those among them that are control
    ;; operations, the defaults its declaration gives, and whether the host
    ;; handles it around a program's body, as `tasks` is handled, since a
    ;; program's statements run as its first task, so the body may perform
    ;; it although no default could.
    (struct Effect
      ((name String)
       (operations (List String))
       (control (List String))
       (defaults (List (Pair String String)))
       (around-main Bool)))

    ;; What a unique value name denotes. A definition's scheme is its
    ;; signature's, or none until it is inferred, and `signature` is where
    ;; that `(: name type)` was written; `function?` says its value is a
    ;; lambda, which a top-level definition's has no environment around, so
    ;; its name has type fn where one is expected. An instance method has
    ;; its class method's scheme and no signature of its own, and like a
    ;; default no program names it. A field has four
    ;; operations: an Accessor reads it, `::field`; a Replacer copies an
    ;; immutable struct with it replaced, `Name-field-set`; and a mutable
    ;; field's Setter writes it in place, `Name-field-set!`, as its Swapper
    ;; does while answering the old content, `Name-field-replace!`.
    (enum Value
      (Defined
        ((scheme (Option Scheme))
         (signature (Option Loc))
         (function? Bool)))
      (Constructor
       ((case Case)
        (scheme Scheme)))
      (Accessor
       ((case Case)
        (index I64)
        (scheme Scheme)))
      (Replacer
       ((case Case)
        (index I64)
        (scheme Scheme)))
      (Setter
       ((case Case)
        (index I64)
        (scheme Scheme)))
      (Swapper
       ((case Case)
        (index I64)
        (scheme Scheme)))
      (Method
       ((class String)
        (scheme Scheme)))
      (Operation
       ((effect String)
        (scheme Scheme)))
      (Primitive
       ((scheme Scheme)))
      (Foreign
       ((import Import)
        (scheme Scheme))))

    ;; The declared scheme of a value; a definition without a signature has
    ;; none until it is inferred.

    (define (value-scheme (value Value)) (→ (Option Scheme))
      (match value
        ((Defined scheme _ _) scheme)
        ((Constructor _ scheme) (Some scheme))
        ((Accessor _ _ scheme) (Some scheme))
        ((Replacer _ _ scheme) (Some scheme))
        ((Setter _ _ scheme) (Some scheme))
        ((Swapper _ _ scheme) (Some scheme))
        ((Method _ scheme) (Some scheme))
        ((Operation _ scheme) (Some scheme))
        ((Primitive scheme) (Some scheme))
        ((Foreign _ scheme) (Some scheme))))

    ;; The effects an operation's type names besides its own: its latent
    ;; row, which its callers are charged and its implementations may
    ;; perform, under the handlers in scope where it is performed.

    (define (operation-latent (effect String) (scheme Scheme)) (→ (List String))
      (match (::type scheme)
        ((TFun _ _ (TRow labels _)) (filter (lambda (label) (not (string=? label effect))) labels))
        (_ (Nil))))

    ;; Top-level items run in order when the program starts. An exposed
    ;; function is exported to the host under `symbol`; a `dynamic` one is
    ;; exported instead for programs that load it while they run, behind a
    ;; wrapper that takes and returns Any values, beside its signature.
    (enum Item
      (Define
        ((name String)
         (value Expr)))
      (Do
       ((expr Expr)))
      (Expose
       ((name String)
        (symbol String)
        (dynamic Bool)
        (loc Loc))))

    ;; The value of each definition among `items`, by name.

    (define (item-definitions (items (List Item))) (→ (Table Expr))
      (fold-left (lambda (table item)
                   (match item
                     ((Define name value) (table-set table name value))
                     (_ table)))
                 empty-table items))

    ;; ---- Programs ----

    ;; Metadata belongs to a canonical declaration. Fields belong to their
    ;; canonical constructor and field name, not to the generated accessor
    ;; functions. Accessor/Setter/Replacer already carry that origin as a
    ;; Case and field index. Metadata never enters type identity or layout.
    (struct Metadata
      ((annotations (List Annotation))
       (fields (Table (List Annotation)))))

    ;; A program is a value: the expander threads it through expansion,
    ;; handing each addition the newest, and the later passes only read it.
    ;; Items are kept newest first. `libraries` names each library, newest
    ;; first, with the number of items it added; the program's own body
    ;; counts as a library named `main`. A library's items join the program
    ;; as one run, after those of every library loaded before it, so the
    ;; program's items divide into one run per library.
    (struct Program
      ((values (Table Value))
       (types (Table DataType))
       (classes (Table Class))
       (instances (Table (List Instance)))
       (effects (Table Effect))
       (metadata (Table Metadata))
       (items (List Item))
       (libraries (List (Pair String I64)))))

    (define empty-program (→ Program)
      (Program empty-table empty-table empty-table empty-table empty-table empty-table (Nil) (Nil)))

    (define (metadata-of (program Program) (name String)) (→ Metadata)
      (match (table-ref (::metadata program) name)
        ((Some metadata) metadata)
        ((None) (Metadata (Nil) empty-table))))

    (define (program-annotations (program Program) (name String)) (→ (List Annotation))
      (::annotations (metadata-of program name)))

    (define (program-field-annotations (program Program) (constructor String) (field String))
      (→ (List Annotation))
      (match (table-ref (::fields (metadata-of program constructor)) field)
        ((Some annotations) annotations)
        ((None) (Nil))))

    (define (program-with-annotations (program Program)
                                      (name String)
                                      (annotations (List Annotation)))
      (→ Program)
      (let ((before (metadata-of program name)))
        (if (null? annotations)
            program
            (Program-metadata-set program
                                  (table-set (::metadata program) name
                                             (Metadata
                                              (append (::annotations before) annotations)
                                              (::fields before)))))))

    (define (program-with-field-annotations (program Program)
                                            (constructor String)
                                            (field String)
                                            (annotations (List Annotation)))
      (→ Program)
      (let ((before (metadata-of program constructor)))
        (if (null? annotations)
            program
            (Program-metadata-set program
                                  (table-set (::metadata program) constructor
                                             (Metadata (::annotations before)
                                                       (table-set (::fields before)
                                                                  field
                                                                  annotations)))))))

    (define (program-value (program Program) (name String)) (→ (Option Value))
      (table-ref (::values program) name))

    ;; Types, classes and effects are looked up by names the expander
    ;; resolved, so each lookup succeeds.

    (define (program-type (program Program) (name String)) (→ DataType)
      (match (table-ref (::types program) name)
        ((Some data) data)
        ((None) (panic (string-append "internal error: no type " name)))))

    (define (program-class (program Program) (name String)) (→ Class)
      (match (table-ref (::classes program) name)
        ((Some class) class)
        ((None) (panic (string-append "internal error: no class " name)))))

    (define (program-effect (program Program) (name String)) (→ Effect)
      (match (table-ref (::effects program) name)
        ((Some effect) effect)
        ((None) (panic (string-append "internal error: no effect " name)))))

    (define (class-instances (program Program) (class String)) (→ (List Instance))
      (match (table-ref (::instances program) class)
        ((Some instances) instances)
        ((None) (Nil))))

    ;; Named instances are available only inside an explicit lexical scope.
    ;; All instances remain in the program: selected evidence names them
    ;; even when a later caller has a different active policy.

    (define (visible-instances (program Program) (class String) (sets (List String)))
      (→ (List Instance))
      (filter (lambda (instance)
                (match (::set instance)
                  ((None) #t)
                  ((Some name) (member? name sets))))
              (class-instances program class)))

    (define (check-active-instances (program Program) (sets (List String)) (loc Loc))
      (→ Unit)
      (! compile)
      (for-each (lambda (class)
                  (let ((visible (visible-instances program (::name class) sets)))
                    (for-each (lambda (instance)
                                (check-instance-overlap program instance visible loc)) visible)))
                (table-values (::classes program))))

    (define (check-instance-overlap (program Program)
                                    (instance Instance)
                                    (others (List Instance))
                                    (loc Loc))
      (→ Unit)
      (! compile)
      (let ((class (program-class program (::class instance))))
        (for-each (lambda (other)
                    (when (and (not (string=? (::name instance) (::name other)))
                               (heads-overlap? (type-arguments class (::types instance))
                                               (type-arguments class (::types other))))
                      (compile-error loc
                                     "this instance overlaps another instance of the class on its input types")))
                  others)))

    (define (heads-overlap? (as (List Type)) (bs (List Type))) (→ Bool)
      (and (= (length as) (length bs))
           (every? (lambda (pair) (head-overlaps? (::first pair) (::second pair)))
                   (zip as bs))))

    (define (head-overlaps? (a Type) (b Type)) (→ Bool)
      (match a
        ((TCon name args)
         (match b
           ((TCon other others) (and (string=? name other) (heads-overlap? args others)))
           ((TRigid _) #t)
           (_ #f)))
        (_ #t)))

    ;; A method's use row is opened to its context, but a selected instance
    ;; supplies the rows it actually performs. Class parameters come first;
    ;; method-local type arguments follow them and retain their use's types.

    (define (selected-method-arguments (program Program)
                                       (class String)
                                       (types (List Type))
                                       (evidence (List Evidence)))
      (→ (List Type))
      (match evidence
        ((Cons (EvInstance id arguments _) _)
         (match (find (lambda (instance) (string=? (::name instance) id))
                      (class-instances program class))
           ((Some instance)
            (let ((bindings (zip (::vars instance) arguments)))
              (append (map (lambda (type) (substitute bindings type)) (::types instance))
                      (list-drop types (length (::types instance))))))
           ((None) types)))
        (_ types)))

    ;; Each addition is a larger program, sharing everything else with the
    ;; one it was given.

    (define (program-with-value (program Program) (name String) (value Value)) (→ Program)
      (Program-values-set program (table-set (::values program) name value)))

    (define (program-with-type (program Program) (data DataType)) (→ Program)
      (Program-types-set program (table-set (::types program) (::name data) data)))

    (define (program-with-class (program Program) (class Class)) (→ Program)
      (Program-classes-set program (table-set (::classes program) (::name class) class)))

    (define (program-with-instance (program Program) (instance Instance)) (→ Program)
      (let ((class (::class instance)))
        (Program-instances-set program (table-set (::instances program) class
                                                  (append (class-instances program class)
                                                          (list instance))))))

    (define (program-with-effect (program Program) (effect Effect)) (→ Program)
      (Program-effects-set program
                           (table-set (::effects program) (::name effect) effect)))

    (define (program-items (program Program)) (→ (List Item))
      (reverse (::items program)))

    ;; A library's run joins the program whole: its items, newest first,
    ;; become the program's newest, and the count it records is theirs. A
    ;; library loaded while another expands joins first, so it can never be
    ;; counted in the other's run.

    (define (program-with-library (program Program) (name String) (items (List Item))) (→ Program)
      (Program-libraries-set (Program-items-set program (append items (::items program)))
                             (Cons (Pair name (length items)) (::libraries program))))

    ;; What the newest library added: the globals named for it, and its run
    ;; of items, which are the newest. A later build replays it with
    ;; `program-with` instead of expanding the library again.

    (define (program-delta (program Program) (owner String)) (→ Program)
      (let ((count (match (::libraries program)
                     ((Cons (Pair _ count) _) count)
                     ((Nil) 0))))
        (Program (owned (::values program) owner)
                 (owned (::types program) owner)
                 (owned (::classes program) owner)
                 (owned-instances (::instances program) owner)
                 (owned (::effects program) owner)
                 (owned (::metadata program) owner)
                 (take (::items program) count) (take (::libraries program) 1))))

    ;; A field class and its method belong to no library, so every delta
    ;; carries the ones known when it was made; a replay unions them back.

    (define (owned (table (Table V)) (owner String)) (→ (Table V)) (∀ V) (⊨ (Copy V))
      (fold-left (lambda (result key)
                   (match (table-ref table key)
                     ((Some value)
                      (if (or (string=? (name-owner key) owner) (string=? (name-owner key) ""))
                          (table-set result key value)
                          result))
                     ((None) result)))
                 empty-table (table-keys table)))

    (define (owned-instances (table (Table (List Instance))) (owner String))
      (→ (Table (List Instance)))
      (fold-left (lambda (result class)
                   (match (filter (lambda (instance)
                                    (string=? (name-owner (::name instance)) owner))
                                  (class-list table class))
                     ((Nil) result)
                     (instances (table-set result class instances))))
                 empty-table (table-keys table)))

    (define (class-list (table (Table (List Instance))) (class String)) (→ (List Instance))
      (match (table-ref table class)
        ((Some instances) instances)
        ((None) (Nil))))

    ;; The program with a library's additions from an earlier build. Its
    ;; globals are its own, so it replaces nothing; the order of instances
    ;; within a class does not matter, since no two of them overlap.

    (define (program-with (program Program) (delta Program)) (→ Program)
      (Program (table-union (::values program) (::values delta))
               (table-union (::types program) (::types delta))
               (table-union (::classes program) (::classes delta))
               (fold-left (lambda (table class)
                            (table-set table
                                       class
                                       (append (class-list table class)
                                               (class-list (::instances delta) class))))
                          (::instances program) (table-keys (::instances delta)))
               (table-union (::effects program) (::effects delta))
               (table-union (::metadata program) (::metadata delta))
               (append (::items delta) (::items program))
               (append (::libraries delta) (::libraries program))))

    ;; `table` with every entry of `additions`, which win where both have a
    ;; key.

    (define (table-union (table (Table V)) (additions (Table V))) (→ (Table V)) (∀ V) (⊨ (Copy V))
      (fold-left (lambda (result key)
                   (match (table-ref additions key)
                     ((Some value) (table-set result key value))
                     ((None) result)))
                 table (table-keys additions)))

    ;; Divides items in program order, such as the program's own or their
    ;; checked copies, into each library's run.

    (define (library-items (program Program) (items (List Item)))
      (→ (List (Pair String (List Item))))
      (let loop ((libraries (reverse (::libraries program))) (items items) (out (Nil)))
        (match libraries
          ((Cons (Pair name count) rest)
           (loop rest (list-tail items count) (Cons (Pair name (take items count)) out)))
          ((Nil) (reverse out)))))

    ;; ---- Wire identities ----

    ;; FNV-1a, as an unsigned 32-bit value: starting from `fnv-offset`,
    ;; `fnv-step` mixes in each code, a code point or a byte, in turn. The
    ;; product stays below 2^56, so it never overflows I64.

    (define fnv-offset (→ I64) 2166136261)

    (define (fnv-step (hash I64) (code I64)) (→ I64)
      (i64-and (* (i64-xor hash code) 16777619) 4294967295))

    ;; FNV-1a over the code points.

    (define (fnv-1a (text String)) (→ I64)
      (vector-fold (lambda (hash c) (fnv-step hash (char->integer c)))
                   fnv-offset
                   (string->vector text)))

    ;; A TypeId is a hash as a signed 32-bit value, which Wasm's i32 holds.

    (define (type-id (text String)) (→ I64)
      (let ((hash (fnv-1a text)))
        (if (>= hash 2147483648) (- hash 4294967296) hash)))

    ;; A case's TypeId hashes its declaring library, type, name and fields.
    ;; Field types contribute their own schemas, cut at recursive
    ;; references, so the identity changes exactly when the encoded shape
    ;; can change.

    (define (case-type-id (program Program) (case Case)) (→ I64)
      (type-id (case-schema program case (Nil))))

    ;; An Any's TypeId hashes the type with its structure as the wire schema
    ;; writes it: fields and cases, recursively. A type whose fields or cases
    ;; change gets a new one even when its name stays, so a program relinked
    ;; with such a change cannot take an old value for a new one.

    (define (any-type-id (program Program) (type Type)) (→ I64)
      (type-id (type-identity program type)))

    ;; The same identity in 64 bits, for a dynamic export's signature: it is
    ;; compared once, when a program looks the function up, rather than
    ;; carried by every value.

    (define (wide-type-id (program Program) (type Type)) (→ I64)
      (wide-hash (type-identity program type)))

    (define (type-identity (program Program) (type Type)) (→ String)
      (string-append (type-key type) "\n" (type-schema program type (Nil) (Nil))))

    ;; FNV-1a in 64 bits over the code points, as a signed I64. The state is
    ;; two unsigned 32-bit halves, high and low, so that every product stays
    ;; below 2^42 and both hosts compute the same value; the prime is
    ;; 2^40 + 435, whose 2^40 shifts the low half eight bits into the high.

    (define (wide-hash (text String)) (→ I64)
      (let ((state (vector-fold (lambda (state c) (wide-step state (char->integer c)))
                                (Pair 3421674724 2216829733)
                                (string->vector text))))
        (+ (* (if (>= (::first state) 2147483648)
                  (- (::first state) 4294967296)
                  (::first state))
              4294967296)
           (::second state))))

    (define (wide-step (state (Pair I64 I64)) (code I64)) (→ (Pair I64 I64))
      (let* ((low (i64-xor (::second state) code)) (product (* low 435)))
        (Pair (i64-and (+ (+ (* (::first state) 435) (quotient product 4294967296))
                          (* (i64-and low 16777215) 256))
                       4294967295)
              (i64-and product 4294967295))))

    (define (case-schema (program Program) (case Case) (visiting (List String))) (→ String)
      (let* ((data (program-type program (::type case)))
             (visiting (Cons (::name data) visiting)))
        (string-append (::name case) "("
                       (string-concatenate
                        (map (lambda (field)
                               (string-append (::name field)
                                              (if (::mutable? field) " mut:" ":")
                                              (type-schema program
                                                           (::type field)
                                                           (::params data)
                                                           visiting)
                                              ";"))
                             (::fields case)))
                       ")")))

    ;; A type parameter is written by its position, so renaming it keeps the
    ;; identity.

    (define (type-schema (program Program)
                         (type Type)
                         (params (List String))
                         (visiting (List String)))
      (→ String)
      (match type
        ((TRigid name)
         (match (list-index (lambda (param) (string=? param name)) params)
           ((Some index) (string-append "#" (i64->string (+ index 1))))
           ((None) "#?")))
        ((TCon name args)
         (string-append name "<"
                        (string-concatenate (map (lambda (arg)
                                                   (string-append
                                                    (type-schema program arg params visiting)
                                                    ","))
                                                 args))
                        ">"
                        (if (or (member? name visiting)
                                (not (table-contains? (::types program) name)))
                            ""
                            (string-concatenate
                             (map (lambda (case) (case-schema program case visiting))
                                  (::cases (program-type program name)))))))
        (_ "fn")))

    ;; ---- Wire schemas ----

    ;; Every data type with a Serialize instance, as text: `(Type (Case
    ;; type-id (field type) ...) ...)` with full names. Programs that agree on
    ;; a case's line agree on its encoding.

    (define (wire-schemas (program Program)) (→ String)
      (string-concatenate
       (map (lambda (instance)
              (match (::types instance)
                ((Cons (TCon name _) (Nil))
                 (if (table-contains? (::types program) name)
                     (data-schema program (program-type program name))
                     ""))
                (_ "")))
            (class-instances program "snail.shell.wire:Serialize"))))

    (define (data-schema (program Program) (data DataType)) (→ String)
      (string-append
       "(" (::name data)
       (string-concatenate
        (map (lambda (case)
               (string-append "\n  ("
                              (short-name (::name case))
                              " "
                              (i64->string (case-type-id program case))
                              (string-concatenate
                               (map (lambda (field)
                                      (string-append " ("
                                                     (::name field)
                                                     " "
                                                     (type-key (::type field))
                                                     ")"))
                                    (::fields case)))
                              ")"))
             (::cases data)))
       ")\n"))

    ;; ---- Strongly connected components ----

    ;; Tarjan's algorithm over a graph whose nodes are numbered from 0: node
    ;; i leads to the nodes in `(vector-ref edges i)`. The search starts
    ;; from each node in turn and follows edges in order. Each component
    ;; lists its nodes in the order the search reached them, and comes after
    ;; every component it leads to.
    ;;
    ;; The search carries what it has learned and hands it back, so the whole
    ;; pass is a function of its graph: `index` numbers the nodes as the
    ;; search reaches them and has no entry until then, `low` is the least
    ;; number a node leads back to, and `open` holds the nodes on the stack.
    ;; Nodes are dense small integers, so a key is just the decimal text.
    (struct Search
      ((edges (Vector (List I64)))
       (index (Table I64))
       (low (Table I64))
       (open (Table Bool))
       (stack (List I64))
       (count I64)
       (components (List (List I64)))))

    (define (strong-components (edges (Vector (List I64)))) (→ (List (List I64)))
      (let ((search (fold-left
                     (lambda (search node) (if (reached? search node) search (visit search node)))
                     (Search edges empty-table empty-table empty-table (Nil) 0 (Nil))
                     (iota (vector-length edges)))))
        (reverse (::components search))))

    (define (node-key (node I64)) (→ String)
      (i64->string node))

    (define (reached? (search Search) (node I64)) (→ Bool)
      (match (table-ref (::index search) (node-key node))
        ((Some _) #t)
        ((None) #f)))

    (define (node-index (search Search) (node I64)) (→ I64)
      (match (table-ref (::index search) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (define (node-low (search Search) (node I64)) (→ I64)
      (match (table-ref (::low search) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (define (open? (search Search) (node I64)) (→ Bool)
      (match (table-ref (::open search) (node-key node))
        ((Some flag) flag)
        ((None) #f)))

    ;; Numbers `node`, pushes it, follows its edges, and closes a component
    ;; when nothing it reached leads back past it.

    (define (visit (search Search) (node I64)) (→ Search)
      (let* ((number (::count search))
             (entered (Search (::edges search)
                              (table-set (::index search) (node-key node) number)
                              (table-set (::low search) (node-key node) number)
                              (table-set (::open search) (node-key node) #t)
                              (Cons node (::stack search))
                              (+ number 1)
                              (::components search)))
             (followed (fold-left (lambda (search next) (follow search node next))
                                  entered (vector-ref (::edges search) node))))
        (if (= (node-low followed node) number) (pop-component followed node) followed)))

    ;; Lowers `node`'s link through its edge to `next`, visiting `next`
    ;; first if the search has not reached it.

    (define (follow (search Search) (node I64) (next I64)) (→ Search)
      (cond ((not (reached? search next))
             (let ((search (visit search next)))
               (lower search node (node-low search next))))
            ((open? search next) (lower search node (node-index search next)))
            (else search)))

    (define (lower (search Search) (node I64) (number I64)) (→ Search)
      (Search-low-set search
                      (table-set (::low search)
                                 (node-key node)
                                 (min (node-low search node) number))))

    ;; Pops the stack down to `node`; those nodes are one component.

    (define (pop-component (search Search) (node I64)) (→ Search)
      (let loop ((search search) (component (Nil)))
        (match (::stack search)
          ((Cons top rest)
           (let ((search (Search-open-set (Search-stack-set search rest)
                                          (table-set (::open search) (node-key top) #f))))
             (if (= top node)
                 (Search-components-set search
                                        (Cons (Cons top component) (::components search)))
                 (loop search (Cons top component)))))
          ((Nil) (panic "internal error: empty search stack")))))

    ;; ---- Primitives ----

    ;; Operations the backend implements directly. (snail core primitive)
    ;; declares each with its type, and the program holds its value under
    ;; `prim:NAME`, the name the checker, mono and the backend know it by.
    ;; Its owner is `prim`, which no library may be named, rather than the
    ;; library that declares it.

    (define (primitive-global (name String)) (→ String)
      (string-append "prim:" name))

    ;; What the primitive library adds to a program, for a later build to
    ;; replay: its values alone. It has no module, since the backend
    ;; implements everything it declares, so it records no run of items.

    (define (primitive-delta (program Program)) (→ Program)
      (Program-values-set empty-program (owned (::values program) "prim")))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-core)
    (import
     (snail stage0 testing))
    (begin
      (define test-core
        (lambda () (expect (short-name "snail.core.base:map") "map")
                (expect (label-union (list "b" "d") (list "c" "a" "b")) (list "a" "b" "c" "d"))
                (expect (wide-hash "") -3750763034362895579)
                (expect (wide-hash "a") -5808556873153909620)
                (expect (wide-hash "foobar") -8821353812377114648)
                (test-hidden-effects)
                (test-references)))

      ;; Structural traversal enters latent lambda bodies and handler
      ;; implementations, preserving first occurrence while deduplicating.
      (define test-references
        (lambda () (let* ((at (Loc "references" 1 1))
                          (wrap (lambda (term) (Expr term unchecked at)))
                          (read (lambda (name) (wrap (Var name (Nil) (Nil)))))
                          (body (wrap (App (read "later") (list (read "first") (read "last")))))
                          (handler (wrap (Lambda (list "unused") (read "first") #t)))
                          (expr (wrap (Handle "effect" (list (Pair "operation" handler)) body))))
                     (expect (expr-references expr) (list "first" "later" "last")))))

      ;; A total function hides nothing; an effectful one is found at any
      ;; depth of the type, and a type variable may be one.
      (define test-hidden-effects
        (lambda () (let* ((i64 (TCon "I64" (Nil)))
                          (total (TFun (Nil) i64 empty-row))
                          (logging (TFun (Nil) i64 (TRow (list "t:Log") (None))))
                          (open (TFun (Nil) i64 (TRow (Nil) (Some (TRigid "e"))))))
                     (expect (hidden-effects (TCon "List" (list total))) (None))
                     (expect (hidden-effects (TFun (list total) i64 empty-row)) (None))
                     (expect (hidden-effects logging) (Some logging))
                     (expect (hidden-effects open) (Some open))
                     (expect (hidden-effects (TCon "List" (list logging))) (Some logging))
                     (expect (hidden-effects (TFun (list logging) i64 empty-row)) (Some logging))
                     (expect (hidden-effects (TCon "Task" (list (TRow (list "t:Log") (None)))))
                             (Some (TRow (list "t:Log") (None))))
                     (expect (hidden-effects (TCon "Task" (list empty-row))) (None))
                     (expect (hidden-effects (TCon "Holder" (list (TRigid "A"))))
                             (Some (TRigid "A"))))))))
   (else)))
