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
   require-type-capacity
   never-type?
   drop-class
   drop-class?
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
   Expr
   Term
   Lit
   Var
   Lambda
   App
   New
   Initializer
   FieldRead
   If
   Let
   Seq
   Match
   Ann
   Handle
   BoxAny
   Downcast
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
   field-operation-name
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
   Entry
   Expose
   item-definitions
   Program
   Program-items-set
   empty-program
   primitive-global
   program-value
   program-type
   program-class
   program-effect
   class-instances
   check-instance-overlap
   selected-method-arguments
   program-with-value
   program-with-type
   program-with-class
   program-with-instance
   program-with-effect
   program-with-library
   table-union
   program-items
   library-items
   fnv-offset
   fnv-step
   fnv-1a
   type-id
   case-type-id
   any-type-id
   wire-schemas
   strong-components)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read))
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

    (define (empty-row) (→ Type) (TRow (Nil) (None)))

    ;; The signature a callable holds; any other type is its own.

    (define (fn-arrow (type Type)) (→ Type)
      (match (callable-arrow type)
        ((Some arrow) arrow)
        ((None) type)))

    ;; ---- Procedure types ----

    ;; Fn is a reusable closure; FnOnce consumes its captures. Both contain
    ;; the same argument/result/effect shape.

    (define (callable-kind (type Type)) (→ (Option String))
      (match type
        ((TFun _ _ _) (Some "Fn"))
        ((TCon "FnOnce" _) (Some "FnOnce"))

        (_ (None))))

    (define (callable-arrow (type Type)) (→ (Option Type))
      (match type
        ((TFun _ _ _) (Some type))
        ((TCon _ (Cons arrow _))
         (match (callable-kind type) ((Some _) (Some arrow)) ((None) (None))))
        (_ (None))))

    ;; Writing a field changes storage; reading it has no mutation effect.

    (define (mut-row) (→ Type) (TRow (list "mut") (None)))

    ;; The type of an expression the checker has not yet seen. The checker
    ;; rebuilds every expression, so no later pass meets it.

    (define (unchecked) (→ Type) (TCon "unchecked" (Nil)))

    (record Constraint
      ((class String)
       (types (List Type))))

    ;; A scheme quantifies rigid variables, which may stand for types or rows.
    ;; `copy` names those a `(⊨ (Copy A))` declares ω, whose values
    ;; may be duplicated and discarded. It is no class constraint, as it has
    ;; no evidence: a constraint's evidence is its position among the
    ;; constraints. The others will be linear (#550); until then every
    ;; variable ranges over ω types.
    (record Scheme
      ((vars (List String))
       (constraints (List Constraint))
       (copy (List String))
       (type Type)))

    (define (mono-scheme (type Type)) (→ Scheme)
      (new Scheme (vars (Nil)) (constraints (Nil)) (copy (Nil)) (type type)))

    ;; The names of the core forms, which the expander binds in
    ;; (snail core forms) and (snail shell highlight) colors as keywords.

    (define (core-keywords) (→ (List String))
      (list "define"
            "lambda"
            "if"
            "begin"
            "let"
            "define-syntax"
            "syntax-rules"
            "quote"
            "declare"
            "record"
            "new"
            "enum"
            "type"
            "typeclass"
            "instance"
            "match"
            "●"
            "ann"
            "extern"
            "primitive"
            "effect"
            "handle"
            "expose"
            "case-id"
            "downcast"
            "artifact-files" "link-handle"))

    (define (builtin-types) (→ (List (Pair String I64)))
      (list (new Pair (first "Any") (second 0))
            (new Pair (first "Rc") (second 1))
            (new Pair (first "WeakRc") (second 1))
            (new Pair (first "Funcref") (second 0))
            (new Pair (first "U8") (second 0))
            (new Pair (first "I32") (second 0))
            (new Pair (first "I64") (second 0))
            (new Pair (first "F32") (second 0))
            (new Pair (first "F64") (second 0))
            (new Pair (first "Bool") (second 0))
            (new Pair (first "Char") (second 0))
            (new Pair (first "Unit") (second 0))
            (new Pair (first "String") (second 0))
            (new Pair (first "Vector") (second 1))
            (new Pair (first "FnOnce") (second 1))
            (new Pair (first "Fn") (second 0))
            ))

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
        ((TRow more (None)) (new Pair (first (label-union labels more)) (second (None))))
        (_ (new Pair (first labels) (second (Some row))))))

    ;; (snail core base)'s type with no values. A control operation that
    ;; answers it never resumes, so its yield saves nothing.

    (define (never-type? (type Type)) (→ Bool)
      (match type
        ((TCon "snail.core.base:Never" (Nil)) #t)
        (_ #f)))

    ;; `(Drop e T)` releases a T, performing e. Without a declared instance,
    ;; its implementation and row come from T's fields. The checker and
    ;; specialization derive this plan rather than matching ordinary instances.

    (define (drop-class) (→ String) "snail.core.base:Drop")

    (define (drop-class? (class String)) (→ Bool)
      (string=? class (drop-class)))

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

    ;; Specialization can grow types indefinitely under polymorphic recursion.
    ;; Bound expanded syntax before serializing a key. Count occurrences, not
    ;; shared object identities: Pair<T,T> writes T twice. This is a compiler
    ;; capacity limit, not a test for whether a recursive type is regular.
    (define (require-type-capacity (type Type)) (→ Unit)
      (when (< (type-capacity-left type 4096) 0)
        (panic "type expansion exceeds the compiler limit of 4096 type nodes")))

    (define (type-capacity-left (type Type) (remaining I64)) (→ I64)
      (if (<= remaining 0) -1
          (match type
            ((TCon _ args) (types-capacity-left args (- remaining 1)))
            ((TFun params result row)
             (types-capacity-left (Cons result (Cons row params)) (- remaining 1)))
            ((TRow _ (Some tail)) (type-capacity-left tail (- remaining 1)))
            (_ (- remaining 1)))))

    (define (types-capacity-left (types (List Type)) (remaining I64)) (→ I64)
      (if (< remaining 0) -1
          (match types
            ((Nil) remaining)
            ((Cons type rest)
             (types-capacity-left rest (type-capacity-left type remaining))))))

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
      (new Constraint (class (● constraint class))
           (types (map (lambda (type) (substitute substitution type))
                       (● constraint types)))))

    ;; ---- Class evidence ----

    ;; Evidence says which instance satisfies a constraint: an instance applied
    ;; to type arguments and the evidence for its requirements, or the
    ;; enclosing definition's own requirement at `index`. A Drop
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

    ;; What dropping a type runs: a discard, its instance's method, or
    ;; glue that releases its fields (`drop-plan` in capabilities.sld).
    (enum Plan
      (Trivial)
      (Implemented
       ((instance Instance)))
      (Glue))

    ;; ---- Expressions ----

    ;; Every expression has a type, `unchecked` until checked, and a location.
    (record Expr
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
      (Lambda
       ((params (List String))
        (body Expr)
        ))
      (App
       ((callee Expr)
        (args (List Expr))))
      ;; Only resolution and checking see named construction. Initializers
      ;; are in written order; their slots form a complete permutation.
      (New
       ((callee Expr)
        (fields (List Initializer))))
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
      (Ann
       ((expr Expr)
        (type Type)))
      (Handle
       ((effect String)
        (implementations (List (Pair String Expr)))
        (body Expr)))
      (BoxAny ((expr Expr)))
      (Downcast
       ((expr Expr)
        (target Type))))

    (record Initializer
      ((slot I64)
       (name String)
       (value Expr)))

    (record Clause
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
        ((Lambda _ _ ) #t)
        (_ #f)))

    ;; Immediate structural children, in source order, including lambda
    ;; bodies. This describes the IR shape, not when an expression runs.

    (define (expr-children (expr Expr)) (→ (List Expr))
      (match (● expr term)
        ((Lit _) (Nil))
        ((Var _ _ _) (Nil))
        ((Lambda _ body ) (list body))
        ((App callee args) (Cons callee args))
        ((New callee fields) (Cons callee (map (lambda (field) (● field value)) fields)))
        ((FieldRead record _ _) (list record))
        ((If test then otherwise) (list test then otherwise))
        ((Let _ value body) (list value body))
        ((Seq first rest) (list first rest))
        ((Match scrutinee clauses) (Cons scrutinee (map (lambda (record) (● record body)) clauses)))

        ((Ann inner _) (list inner))
        ((BoxAny inner) (list inner))
        ((Downcast inner _) (list inner))
        ((Handle _ implementations body)
         (append (map (lambda (record) (● record second)) implementations) (list body)))))

    ;; Every name an expression refers to, once each, in order of first
    ;; occurrence. Locals are included, since names are unique.

    (define (expr-references (expr Expr)) (→ (List String))
      (reverse
       (● (collect-references (new Pair (first (empty-table)) (second (Nil))) expr) second)))

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
                (new Pair (first (table-set seen name #t)) (second (Cons name names)))))))
        (_ (fold-left collect-references found (expr-children expr)))))

    ;; Local names are unique after resolution. Closure layouts and control
    ;; ownership use the type carried by each resolved read.
    (define (expr-reference-types (expr Expr)) (→ (Table Type))
      (collect-reference-types (empty-table) expr))

    (define (collect-reference-types (found (Table Type)) (expr Expr)) (→ (Table Type))
      (match (● expr term)
        ((Var name _ _) (table-set found name (● expr type)))
        (_ (fold-left collect-reference-types found (expr-children expr)))))

    ;; ---- Declared entities ----

    ;; A record is a data type with one case named after it. An `owned?`
    ;; type has a Drop instance and is linear regardless of its fields.
    (record DataType
      ((name String)
       (params (List String))
       (cases (List Case))
       (enum? Bool)
       (owned? Bool)))

    (record Case
      ((name String)
       (type String)
       (tag I64)
       (fields (List Field))))

    ;; A mutable field is a place: it is read and written in the record
    ;; that holds it, so a record with one has identity.
    (record Field
      ((name String)
       (type Type)))

    ;; Method schemes quantify the class parameters first and require the
    ;; class itself as their first constraint. `rows` are the parameters
    ;; its methods perform, as `e` in (Store e S): an instance writes each
    ;; as a row in its head. `outputs` are hidden trailing associated type
    ;; arguments. The remaining input parameters choose the evidence that
    ;; establishes outputs and the rows a method use performs.
    (record Class
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
               ((None) (Some (Cons (new Pair (first name) (second type)) bindings)))
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
    (record Instance
      ((name String)
       (class String)
       (vars (List String))
       (types (List Type))
       (requires (List Constraint))
       (copy (List String))
       (methods (List (Pair String String)))))

    (record Import
      ((module String)
       (symbol String)))

    ;; `control` names the operations whose implementations receive the rest
    ;; of the handled computation as `resume`; the others return to their
    ;; caller. `defaults` maps operation names to what performs them when no
    ;; handler is in scope.
    ;; Each default is an operation's and the global of the Snail Scheme
    ;; function the effect's declaration defines for it, which runs under
    ;; the performer's handlers.
    ;; An effect: its operations, those among them that are control
    ;; operations, the defaults its declaration gives, and whether the host
    ;; handles it around a program's body, as `tasks` is handled, since a
    ;; program's statements run as its first task, so the body may perform
    ;; it although no default could.
    (record Effect
      ((name String)
       (operations (List String))
       (control (List String))
       (defaults (List (Pair String String)))
       (around-main Bool)))

    ;; What a unique value name denotes. A definition's scheme is its
    ;; signature's, or none until it is inferred, and `signature` is where
    ;; its typed header was written. Every definition is a function. An instance method has
    ;; its class method's scheme and no signature of its own, and like a
    ;; default no program names it. Internal field operations describe
    ;; path reads, pure record copies, writes and swaps. Only the pure
    ;; replacement has a source function name; enum fields are read by match.
    (define (field-operation-name (case Case) (index I64) (operation String)) (→ String)
      (string-append "%" operation ":" (● case name) "-"
                     (● (list-ref (● case fields) index) name)))

    (enum Value
      (Defined
        ((scheme (Option Scheme))
         (signature (Option Loc))))
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
        ((Defined scheme _ ) scheme)
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

    ;; Definitions contain functions. Entry names the
    ;; root program's optional main; libraries have no startup phase. An
    ;; exposed function is exported under `symbol` through a host adapter.
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
        (loc Loc))))

    ;; The value of each definition among `items`, by name.

    (define (item-definitions (items (List Item))) (→ (Table Expr))
      (fold-left (lambda (table item)
                   (match item
                     ((Define name value) (table-set table name value))
                     (_ table)))
                 (empty-table) items))

    ;; ---- Programs ----

    ;; A program is a value: the expander threads it through expansion,
    ;; handing each addition the newest, and the later passes only read it.
    ;; Items are kept newest first. `libraries` names each library, newest
    ;; first, with the number of items it added; the program's own body
    ;; counts as a library named `main`. A library's items join the program
    ;; as one run, after those of every library loaded before it, so the
    ;; program's items divide into one run per library.
    (record Program
      ((values (Table Value))
       (types (Table DataType))
       (classes (Table Class))
       (instances (Table (List Instance)))
       (effects (Table Effect))
       (items (List Item))
       (libraries (List (Pair String I64)))))

    (define (empty-program) (→ Program)
      (new Program
        (values (empty-table))
        (types (empty-table))
        (classes (empty-table))
        (instances (empty-table))
        (effects (empty-table))
        (items (Nil))
        (libraries (Nil))))

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
                             (Cons (new Pair (first name) (second (length items)))
                                   (● program libraries))))

    ;; `table` with every entry of `additions`, which win where both have a
    ;; key.

    (define (table-union (table (Table V)) (additions (Table V)))
      (→ (Table V))
      (! e)
      (∀ (V e))
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
           (loop rest
                 (list-tail items count)
                 (Cons (new Pair (first name) (second (take items count))) out)))
          ((Nil) (reverse out)))))

    ;; ---- Wire identities ----

    ;; FNV-1a, as an unsigned 32-bit value: starting from `fnv-offset`,
    ;; `fnv-step` mixes in each code, a code point or a byte, in turn. The
    ;; product stays below 2^56, so it never overflows I64.

    (define (fnv-offset) (→ I64) 2166136261)

    (define (fnv-step (hash I64) (code I64)) (→ I64)
      (i64-and (* (i64-xor hash code) 16777619) 4294967295))

    ;; FNV-1a over the code points.

    (define (fnv-1a (text String)) (→ I64)
      (vector-fold (lambda (hash c) (fnv-step hash (char->integer c)))
                   (fnv-offset)
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

    (define (type-identity (program Program) (type Type)) (→ String)
      (string-append (type-key type) "\n" (type-schema program type (Nil) (Nil))))

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
        ((TFun arguments result row)
         (string-append "Fn("
                        (string-join (map (lambda (argument)
                                            (type-schema program argument params visiting))
                                          arguments) ",")
                        "→" (type-schema program result params visiting)
                        (type-schema program row params visiting) ")"))
        ((TRow _ _)
         (let ((parts (row-parts type (Nil))))
           (string-append "!(" (string-join (● parts first) ",")
                          (match (● parts second)
                            ((None) "")
                            ((Some tail)
                             (string-append "|" (type-schema program tail params visiting))))
                          ")")))
        (_ (panic "internal error: unresolved type in a schema"))))

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
    (record Search
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
                     (new Search
                       (edges edges)
                       (index (empty-table))
                       (low (empty-table))
                       (open (empty-table))
                       (stack (Nil))
                       (count 0)
                       (components (Nil)))
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
             (entered (new Search (edges (● search edges))
                           (index (table-set (● search index) (node-key node) number))
                           (low (table-set (● search low) (node-key node) number))
                           (open (table-set (● search open) (node-key node) #t))
                           (stack (Cons node (● search stack)))
                           (count (+ number 1))
                           (components (● search components))))
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

    ;; What the primitive library adds to a program: its values alone.
    ;; It has no module, since the backend
    ;; implements everything it declares, so it records no run of items.

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

                (test-type-identities)
                (test-hidden-effects)
                (test-references)))

      ;; A boxed closure may cross a relink. Its nominal parameter/result
      ;; schemas and nested callback effects must change its identity even
      ;; when all involved Wasm layouts remain identical.
      (define (identity-fixture (label String) (field Type)) (→ Program)
        (program-with-type (empty-program)
                           (new DataType (name "test:Payload") (params (Nil))
                                (cases
                                 (list (new Case (name "test:Payload") (type "test:Payload") (tag 0)
                                            (fields (list (new Field (name label) (type field)))))))
                                (enum? #f)
                                (owned? #f))))

      (define (test-type-identities) (→ Unit)
        (let* ((i64 (TCon "I64" (Nil))) (payload (TCon "test:Payload" (Nil)))
               (callback (TFun (list payload) payload (empty-row)))
               (old (identity-fixture "before" i64))
               (changed (identity-fixture "after" i64))
               (pure (identity-fixture "call" (TFun (Nil) i64 (empty-row))))
               (effectful
                (identity-fixture "call" (TFun (Nil) i64 (TRow (list "test:Log") (None))))))
          (expect (= (any-type-id old callback) (any-type-id changed callback)) #f)
          (expect (= (any-type-id pure callback) (any-type-id effectful callback)) #f)))

      ;; Structural traversal enters latent lambda bodies and handler
      ;; implementations, preserving first occurrence while deduplicating.
      (define test-references
        (lambda () (let* ((at (new Loc (file "references") (line 1) (column 1)))
                          (wrap (lambda (term) (new Expr (term term) (type (unchecked)) (loc at))))
                          (read (lambda (name) (wrap (Var name (Nil) (Nil)))))
                          (body (wrap (App (read "later") (list (read "first") (read "last")))))
                          (handler (wrap (Lambda (list "unused") (read "first") )))
                          (expr (wrap (Handle "effect"
                                              (list (new Pair (first "operation") (second handler)))
                                              body))))
                     (expect (expr-references expr) (list "first" "later" "last")))))

      ;; A total function hides nothing; an effectful one is found at any
      ;; depth of the type, and a type variable may be one.
      (define test-hidden-effects
        (lambda () (let* ((i64 (TCon "I64" (Nil)))
                          (total (TFun (Nil) i64 (empty-row)))
                          (logging (TFun (Nil) i64 (TRow (list "t:Log") (None))))
                          (open (TFun (Nil) i64 (TRow (Nil) (Some (TRigid "e"))))))
                     (expect (hidden-effects (TCon "List" (list total))) (None))
                     (expect (hidden-effects (TFun (list total) i64 (empty-row))) (None))
                     (expect (hidden-effects logging) (Some logging))
                     (expect (hidden-effects open) (Some open))
                     (expect (hidden-effects (TCon "List" (list logging))) (Some logging))
                     (expect (hidden-effects (TFun (list logging) i64 (empty-row))) (Some logging))
                     (expect (hidden-effects (TCon "Task" (list (TRow (list "t:Log") (None)))))
                             (Some (TRow (list "t:Log") (None))))
                     (expect (hidden-effects (TCon "Task" (list (empty-row)))) (None))
                     (expect (hidden-effects (TCon "Holder" (list (TRigid "A"))))
                             (Some (TRigid "A"))))))))
   (else)))
