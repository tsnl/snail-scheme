;; The core language shared by every pass after expansion. The expander
;; produces a Program: entity tables keyed by unique names, and an ordered list
;; of top-level items. The checker fills in each expression's type; the
;; monomorphizer replaces type arguments with ground types.
(define-library (snail shell compiler core)
  (export
   Type
   TCon
   TFun
   TRow
   TVar
   TRigid
   TVar-id
   empty-row
   fn-arrow
   callable-kind
   callable-arrow
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
   FieldRead
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
   expr-reference-types
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
   Entry
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













    ;; This implication is about receiver access, never Copy or purity.



    (define (callable-kind (type Type)) (→ (Option String))
      (match type
        ((TFun _ _ _) (Some "Fn"))
        ((TCon "FnOnce" _) (Some "FnOnce"))
        ((TCon "fn" _) (Some "Fn"))
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
            "●"
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
            (Pair "Rc" 1)
            (Pair "WeakRc" 1)
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
            (Pair "Fn" 0)
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
      (match type
        ((TFun params result row) (arrow->string "Fn" params result row))
        ((TCon "FnOnce" (Cons (TFun params result row) (Nil)))
         (arrow->string "FnOnce" params result row))
        ((TCon "fn" (Cons (TFun params result row) (Nil)))
         (arrow->string "fn" params result row))
        ((TCon name (Nil)) (short-name name))
        ((TCon name args) (string-append "(" (short-name name) (types->string args) ")"))
        ((TRow _ _) (string-append "{" (row->string type) " }"))
        ((TVar id) (string-append "?" (i64->string id)))
        ((TRigid name) name)))



    (define (arrow->string (kind String) (params (List Type)) (result Type) (row Type)) (→ String)
      (string-append "(" kind (types->string params) " → " (type->string result)
                     (row->string row) ")"))

    (define (types->string (types (List Type))) (→ String)
      (string-concatenate (map (lambda (type) (string-append " " (type->string type))) types)))

    (define (row->string (row Type)) (→ String)
      (let* ((parts (row-parts row (Nil))) (labels (● parts first)) (tail (● parts second)))
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
           (every? (lambda (pair) (type=? (● pair first) (● pair second))) (zip as bs))))

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
      (Constraint (● constraint class)
                  (map (lambda (type) (substitute substitution type))
                       (● constraint types))))

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
      ;; A nominal field selection. Checking records its resolved accessor
      ;; expression in the solution; zonking removes this surface operation.
      (FieldRead
       ((record Expr)
        (label String)
        (resolution (Option I64))))
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
      (match (● expr term)
        ((Lambda _ _ _) #t)
        (_ #f)))

    ;; Immediate structural children, in source order, including lambda
    ;; bodies. This describes the IR shape, not when an expression runs.

    (define (expr-children (expr Expr)) (→ (List Expr))
      (match (● expr term)
        ((Lit _) (Nil))
        ((Var _ _ _) (Nil))
        ((Lambda _ body _) (list body))
        ((App callee args) (Cons callee args))
        ((FieldRead record _ _) (list record))
        ((If test then otherwise) (list test then otherwise))
        ((Let _ value body) (list value body))
        ((Seq first rest) (list first rest))
        ((Match scrutinee clauses) (Cons scrutinee (map (lambda (record) (● record body)) clauses)))
        ((ScopedInstances _ body) (list body))
        ((Ann inner _) (list inner))
        ((Convert inner _) (list inner))
        ((TryConvert inner _) (list inner))
        ((TypeTest inner _) (list inner))
        ((Handle _ implementations body)
         (append (map (lambda (record) (● record second)) implementations) (list body)))))

    ;; Every name an expression refers to, once each, in order of first
    ;; occurrence. Locals are included, since names are unique.

    (define (expr-references (expr Expr)) (→ (List String))
      (reverse (● (collect-references (Pair empty-table (Nil)) expr) second)))

    ;; Adds the names not yet seen to the found list, newest first, and to
    ;; the seen table.

    (define (collect-references (found (Pair (Table Bool) (List String))) (expr Expr))
      (→ (Pair (Table Bool) (List String)))
      (match (● expr term)
        ((Var name _ _)
         (match found
           ((Pair seen names)
            (if (table-contains? seen name)
                found
                (Pair (table-set seen name #t) (Cons name names))))))
        (_ (fold-left collect-references found (expr-children expr)))))

    ;; Local names are unique after resolution. Closure layouts and control
    ;; ownership use the type carried by each resolved read.
    (define (expr-reference-types (expr Expr)) (→ (Table Type))
      (collect-reference-types empty-table expr))

    (define (collect-reference-types (found (Table Type)) (expr Expr)) (→ (Table Type))
      (match (● expr term)
        ((Var name _ _) (table-set found name (● expr type)))
        (_ (fold-left collect-reference-types found (expr-children expr)))))

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
       (type Type)))

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
      (map (lambda (record) (● record second))
           (filter (lambda (pair) (member? (● pair first) (● class rows)))
                   (zip (● class params) types))))

    (define (type-arguments (class Class) (types (List Type))) (→ (List Type))
      (map (lambda (record) (● record second))
           (filter (lambda (pair)
                     (not (member? (● pair first)
                                   (append (● class rows) (● class outputs)))))
                   (zip (● class params) types))))

    ;; Associated members are hidden trailing arguments. Like rows they
    ;; are established by the selected evidence, never used to select it.

    (define (output-arguments (class Class) (types (List Type))) (→ (List Type))
      (list-drop types (- (length (● class params)) (length (● class outputs)))))

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
                          (match-type vars (● pair first) (● pair second) bindings))
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
    ;; operations: an Accessor reads it, `(● record field)`; a Replacer copies an
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
      (match (● scheme type)
        ((TFun _ _ (TRow labels _)) (filter (lambda (label) (not (string=? label effect))) labels))
        (_ (Nil))))

    ;; Definitions contain functions or compile-time values. Entry names the
    ;; root program's optional main; libraries have no startup phase. An
    ;; exposed function is exported under `symbol`; a `dynamic` one is
    ;; exported instead for programs that load it while they run, behind a
    ;; wrapper that takes and returns Any values, beside its signature.
    (enum Item
      (Define
        ((name String)
         (value Expr)))
      (Entry
       ((name String)
        (loc Loc)))
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
      (match (table-ref (● program metadata) name)
        ((Some metadata) metadata)
        ((None) (Metadata (Nil) empty-table))))

    (define (program-annotations (program Program) (name String)) (→ (List Annotation))
      (● (metadata-of program name) annotations))

    (define (program-field-annotations (program Program) (constructor String) (field String))
      (→ (List Annotation))
      (match (table-ref (● (metadata-of program constructor) fields) field)
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
                                  (table-set (● program metadata) name
                                             (Metadata
                                              (append (● before annotations) annotations)
                                              (● before fields)))))))

    (define (program-with-field-annotations (program Program)
                                            (constructor String)
                                            (field String)
                                            (annotations (List Annotation)))
      (→ Program)
      (let ((before (metadata-of program constructor)))
        (if (null? annotations)
            program
            (Program-metadata-set program
                                  (table-set (● program metadata) constructor
                                             (Metadata (● before annotations)
                                                       (table-set (● before fields)
                                                                  field
                                                                  annotations)))))))

    (define (program-value (program Program) (name String)) (→ (Option Value))
      (table-ref (● program values) name))

    ;; Types, classes and effects are looked up by names the expander
    ;; resolved, so each lookup succeeds.

    (define (program-type (program Program) (name String)) (→ DataType)
      (match (table-ref (● program types) name)
        ((Some data) data)
        ((None) (panic (string-append "internal error: no type " name)))))

    (define (program-class (program Program) (name String)) (→ Class)
      (match (table-ref (● program classes) name)
        ((Some class) class)
        ((None) (panic (string-append "internal error: no class " name)))))

    (define (program-effect (program Program) (name String)) (→ Effect)
      (match (table-ref (● program effects) name)
        ((Some effect) effect)
        ((None) (panic (string-append "internal error: no effect " name)))))

    (define (class-instances (program Program) (class String)) (→ (List Instance))
      (match (table-ref (● program instances) class)
        ((Some instances) instances)
        ((None) (Nil))))

    ;; Named instances are available only inside an explicit lexical scope.
    ;; All instances remain in the program: selected evidence names them
    ;; even when a later caller has a different active policy.

    (define (visible-instances (program Program) (class String) (sets (List String)))
      (→ (List Instance))
      (filter (lambda (instance)
                (match (● instance set)
                  ((None) #t)
                  ((Some name) (member? name sets))))
              (class-instances program class)))

    (define (check-active-instances (program Program) (sets (List String)) (loc Loc))
      (→ Unit)
      (! compile)
      (for-each (lambda (class)
                  (let ((visible (visible-instances program (● class name) sets)))
                    (for-each (lambda (instance)
                                (check-instance-overlap program instance visible loc)) visible)))
                (table-values (● program classes))))

    (define (check-instance-overlap (program Program)
                                    (instance Instance)
                                    (others (List Instance))
                                    (loc Loc))
      (→ Unit)
      (! compile)
      (let ((class (program-class program (● instance class))))
        (for-each (lambda (other)
                    (when (and (not (string=? (● instance name) (● other name)))
                               (heads-overlap? (type-arguments class (● instance types))
                                               (type-arguments class (● other types))))
                      (compile-error loc
                                     "this instance overlaps another instance of the class on its input types")))
                  others)))

    (define (heads-overlap? (as (List Type)) (bs (List Type))) (→ Bool)
      (and (= (length as) (length bs))
           (every? (lambda (pair) (head-overlaps? (● pair first) (● pair second)))
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
         (match (find (lambda (instance) (string=? (● instance name) id))
                      (class-instances program class))
           ((Some instance)
            (let ((bindings (zip (● instance vars) arguments)))
              (append (map (lambda (type) (substitute bindings type)) (● instance types))
                      (list-drop types (length (● instance types))))))
           ((None) types)))
        (_ types)))

    ;; Each addition is a larger program, sharing everything else with the
    ;; one it was given.

    (define (program-with-value (program Program) (name String) (value Value)) (→ Program)
      (Program-values-set program (table-set (● program values) name value)))

    (define (program-with-type (program Program) (data DataType)) (→ Program)
      (Program-types-set program (table-set (● program types) (● data name) data)))

    (define (program-with-class (program Program) (class Class)) (→ Program)
      (Program-classes-set program (table-set (● program classes) (● class name) class)))

    (define (program-with-instance (program Program) (instance Instance)) (→ Program)
      (let ((class (● instance class)))
        (Program-instances-set program (table-set (● program instances) class
                                                  (append (class-instances program class)
                                                          (list instance))))))

    (define (program-with-effect (program Program) (effect Effect)) (→ Program)
      (Program-effects-set program
                           (table-set (● program effects) (● effect name) effect)))

    (define (program-items (program Program)) (→ (List Item))
      (reverse (● program items)))

    ;; A library's run joins the program whole: its items, newest first,
    ;; become the program's newest, and the count it records is theirs. A
    ;; library loaded while another expands joins first, so it can never be
    ;; counted in the other's run.

    (define (program-with-library (program Program) (name String) (items (List Item))) (→ Program)
      (Program-libraries-set (Program-items-set program (append items (● program items)))
                             (Cons (Pair name (length items)) (● program libraries))))

    ;; What the newest library added: the globals named for it, and its run
    ;; of items, which are the newest. A later build replays it with
    ;; `program-with` instead of expanding the library again.

    (define (program-delta (program Program) (owner String)) (→ Program)
      (let ((count (match (● program libraries)
                     ((Cons (Pair _ count) _) count)
                     ((Nil) 0))))
        (Program (owned (● program values) owner)
                 (owned (● program types) owner)
                 (owned (● program classes) owner)
                 (owned-instances (● program instances) owner)
                 (owned (● program effects) owner)
                 (owned (● program metadata) owner)
                 (take (● program items) count) (take (● program libraries) 1))))

    (define (owned (table (Table V)) (owner String))
      (→ (Table V))
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (fold-left (lambda (result key)
                   (match (table-ref table key)
                     ((Some value)
                      (if (string=? (name-owner key) owner)
                          (table-set result key value)
                          result))
                     ((None) result)))
                 empty-table (table-keys table)))

    (define (owned-instances (table (Table (List Instance))) (owner String))
      (→ (Table (List Instance)))
      (fold-left (lambda (result class)
                   (match (filter (lambda (instance)
                                    (string=? (name-owner (● instance name)) owner))
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
      (Program (table-union (● program values) (● delta values))
               (table-union (● program types) (● delta types))
               (table-union (● program classes) (● delta classes))
               (fold-left (lambda (table class)
                            (table-set table
                                       class
                                       (append (class-list table class)
                                               (class-list (● delta instances) class))))
                          (● program instances) (table-keys (● delta instances)))
               (table-union (● program effects) (● delta effects))
               (table-union (● program metadata) (● delta metadata))
               (append (● delta items) (● program items))
               (append (● delta libraries) (● program libraries))))

    ;; `table` with every entry of `additions`, which win where both have a
    ;; key.

    (define (table-union (table (Table V)) (additions (Table V)))
      (→ (Table V))
      (! e)
      (∀ V e)
      (⊨ (Copy V) (Drop e V))
      (fold-left (lambda (result key)
                   (match (table-ref additions key)
                     ((Some value) (table-set result key value))
                     ((None) result)))
                 table (table-keys additions)))

    ;; Divides items in program order, such as the program's own or their
    ;; checked copies, into each library's run.

    (define (library-items (program Program) (items (List Item)))
      (→ (List (Pair String (List Item))))
      (let loop ((libraries (reverse (● program libraries))) (items items) (out (Nil)))
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
        (+ (* (if (>= (● state first) 2147483648)
                  (- (● state first) 4294967296)
                  (● state first))
              4294967296)
           (● state second))))

    (define (wide-step (state (Pair I64 I64)) (code I64)) (→ (Pair I64 I64))
      (let* ((low (i64-xor (● state second) code)) (product (* low 435)))
        (Pair (i64-and (+ (+ (* (● state first) 435) (quotient product 4294967296))
                          (* (i64-and low 16777215) 256))
                       4294967295)
              (i64-and product 4294967295))))

    (define (case-schema (program Program) (case Case) (visiting (List String))) (→ String)
      (let* ((data (program-type program (● case type)))
             (visiting (Cons (● data name) visiting)))
        (string-append (● case name) "("
                       (string-concatenate
                        (map (lambda (field)
                               (string-append (● field name)
                                              ":"
                                              (type-schema program
                                                           (● field type)
                                                           (● data params)
                                                           visiting)
                                              ";"))
                             (● case fields)))
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
                                (not (table-contains? (● program types) name)))
                            ""
                            (string-concatenate
                             (map (lambda (case) (case-schema program case visiting))
                                  (● (program-type program name) cases))))))
        (_ "fn")))

    ;; ---- Wire schemas ----

    ;; Every data type with a Serialize instance, as text: `(Type (Case
    ;; type-id (field type) ...) ...)` with full names. Programs that agree on
    ;; a case's line agree on its encoding.

    (define (wire-schemas (program Program)) (→ String)
      (string-concatenate
       (map (lambda (instance)
              (match (● instance types)
                ((Cons (TCon name _) (Nil))
                 (if (table-contains? (● program types) name)
                     (data-schema program (program-type program name))
                     ""))
                (_ "")))
            (class-instances program "snail.shell.wire:Serialize"))))

    (define (data-schema (program Program) (data DataType)) (→ String)
      (string-append
       "(" (● data name)
       (string-concatenate
        (map (lambda (case)
               (string-append "\n  ("
                              (short-name (● case name))
                              " "
                              (i64->string (case-type-id program case))
                              (string-concatenate
                               (map (lambda (field)
                                      (string-append " ("
                                                     (● field name)
                                                     " "
                                                     (type-key (● field type))
                                                     ")"))
                                    (● case fields)))
                              ")"))
             (● data cases)))
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
        (reverse (● search components))))

    (define (node-key (node I64)) (→ String)
      (i64->string node))

    (define (reached? (search Search) (node I64)) (→ Bool)
      (match (table-ref (● search index) (node-key node))
        ((Some _) #t)
        ((None) #f)))

    (define (node-index (search Search) (node I64)) (→ I64)
      (match (table-ref (● search index) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (define (node-low (search Search) (node I64)) (→ I64)
      (match (table-ref (● search low) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (define (open? (search Search) (node I64)) (→ Bool)
      (match (table-ref (● search open) (node-key node))
        ((Some flag) flag)
        ((None) #f)))

    ;; Numbers `node`, pushes it, follows its edges, and closes a component
    ;; when nothing it reached leads back past it.

    (define (visit (search Search) (node I64)) (→ Search)
      (let* ((number (● search count))
             (entered (Search (● search edges)
                              (table-set (● search index) (node-key node) number)
                              (table-set (● search low) (node-key node) number)
                              (table-set (● search open) (node-key node) #t)
                              (Cons node (● search stack))
                              (+ number 1)
                              (● search components)))
             (followed (fold-left (lambda (search next) (follow search node next))
                                  entered (vector-ref (● search edges) node))))
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
                      (table-set (● search low)
                                 (node-key node)
                                 (min (node-low search node) number))))

    ;; Pops the stack down to `node`; those nodes are one component.

    (define (pop-component (search Search) (node I64)) (→ Search)
      (let loop ((search search) (component (Nil)))
        (match (● search stack)
          ((Cons top rest)
           (let ((search (Search-open-set (Search-stack-set search rest)
                                          (table-set (● search open) (node-key top) #f))))
             (if (= top node)
                 (Search-components-set search
                                        (Cons (Cons top component) (● search components)))
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
      (Program-values-set empty-program (owned (● program values) "prim")))

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
