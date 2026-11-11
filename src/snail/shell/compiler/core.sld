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

    (: empty-row Type)
    (define empty-row (TRow (Nil) (None)))

    ;; Borrow is a scoped, non-owning value type. It remains visible in
    ;; locals and signatures through checking; only representation lowering
    ;; uses its target. Lexical ownership checking proves where it may live.
    (: borrow-type? (impl (Fn Type -> Bool)))
    (define (borrow-type? type)
      (match type
        ((TCon "Borrow" (Cons _ (Nil))) #t)
        (_ #f)))

    (: borrow-target (impl (Fn Type -> Type)))
    (define (borrow-target type)
      (match type
        ((TCon "Borrow" (Cons value (Nil))) value)
        (_ type)))

    ;; The signature a callable holds, including `(fn A -> B ! e)` code; any
    ;; other type is its own.
    (: fn-arrow (impl (Fn Type -> Type)))
    (define (fn-arrow type)
      (match (callable-arrow type)
        ((Some arrow) arrow)
        ((None) type)))

    ;; ---- Callable contracts ----

    ;; A concrete closure keeps its construction identity and capture types.
    ;; Its first argument is its calling signature; the remaining arguments
    ;; are the owned environment. Generic instantiation substitutes both.
    ;; These compiler names cannot be written as source type constructors.
    (: concrete-callable (impl (Fn String String Type (List Type) -> Type)))
    (define (concrete-callable kind identity arrow captures)
      (TCon (string-append "$callable." kind ":" identity) (Cons arrow captures)))

    (: concrete-callable? (impl (Fn Type -> Bool)))
    (define (concrete-callable? type)
      (match type
        ((TCon name _)
         (and (>= (string-length name) 10) (string=? (substring name 0 10) "$callable.")))
        (_ #f)))

    (: impl-callable? (impl (Fn Type -> Bool)))
    (define (impl-callable? type)
      (match type
        ((TCon name _) (member? name (list "$impl.Fn" "$impl.FnMut" "$impl.FnOnce")))
        (_ #f)))

    (: callable-captures (impl (Fn Type -> (List Type))))
    (define (callable-captures type)
      (match type
        ((TCon _ (Cons _ captures)) (if (concrete-callable? type) captures (Nil)))
        (_ (Nil))))

    (: callable-class (impl (Fn String -> String)))
    (define (callable-class kind)
      (string-append "snail.core.base:" kind))

    (: callable-class? (impl (Fn String -> Bool)))
    (define (callable-class? name)
      (member? name (map callable-class (list "Fn" "FnMut" "FnOnce"))))

    ;; This implication is about receiver access, never Copy or purity.
    (: callable-implies? (impl (Fn String String -> Bool)))
    (define (callable-implies? actual required)
      (or (string=? actual required)
          (string=? actual "Fn")
          (and (string=? actual "FnMut") (string=? required "FnOnce"))))

    (: callable-kind (impl (Fn Type -> (Option String))))
    (define (callable-kind type)
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

    (: callable-arrow (impl (Fn Type -> (Option Type))))
    (define (callable-arrow type)
      (match type
        ((TFun _ _ _) (Some type))
        ((TCon _ (Cons arrow _))
         (match (callable-kind type) ((Some _) (Some arrow)) ((None) (None))))
        (_ (None))))

    ;; An invocation records the receiver operation the checker selected.
    ;; It remains attached through specialization: a FnOnce requirement
    ;; consumes its receiver even when the concrete value also implements Fn.
    (: invocation-mode (impl (Fn Expr -> (Option String))))
    (define (invocation-mode callee)
      (match (::term callee)
        ((Ann _ (TCon "$invoke" (Cons (TCon mode (Nil)) _))) (Some mode))
        (_ (None))))

    ;; The row of an operation on a mutable field, which reads or writes
    ;; storage and nothing else.
    (: mut-row Type)
    (define mut-row (TRow (list "mut") (None)))

    ;; The type of an expression the checker has not yet seen. The checker
    ;; rebuilds every expression, so no later pass meets it.
    (: unchecked Type)
    (define unchecked (TCon "unchecked" (Nil)))

    (struct Constraint
      ((class String)
       (types (List Type))))

    ;; A scheme quantifies rigid variables, which may stand for types or rows.
    ;; `copy` names those a `(requires (Copy A))` declares ω, whose values
    ;; may be duplicated and discarded. It is no class constraint, as it has
    ;; no evidence: a constraint's evidence is its position among the
    ;; constraints. The others will be linear (#550); until then every
    ;; variable ranges over ω types.
    (struct Scheme
      ((vars (List String))
       (constraints (List Constraint))
       (copy (List String))
       (type Type)))

    (: mono-scheme (impl (Fn Type -> Scheme)))
    (define (mono-scheme type)
      (Scheme (Nil) (Nil) (Nil) type))

    ;; The names of the core forms, which the expander binds in
    ;; (snail core forms) and (snail shell highlight) colors as keywords.
    (: core-keywords (List String))
    (define core-keywords
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

    (: builtin-types (List (Pair String I64)))
    (define builtin-types
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
    (: short-name (impl (Fn String -> String)))
    (define (short-name name)
      (let ((chars (string->vector name)))
        (let loop ((index (- (vector-length chars) 1)))
          (cond ((< index 0) name)
                ((char=? (vector-ref chars index) #\:)
                 (substring name (+ index 1) (string-length name)))
                (else (loop (- index 1)))))))

    ;; A local's source name: its unique name without the `.N` suffix.
    (: local-name (impl (Fn String -> String)))
    (define (local-name name)
      (match (last-dot name)
        ((Some index) (substring name 0 index))
        ((None) name)))

    (: last-dot (impl (Fn String -> (Option I64))))
    (define (last-dot name)
      (let loop ((index (- (string-length name) 1)))
        (cond ((< index 0) (None))
              ((char=? (string-ref name index) #\.) (Some index))
              (else (loop (- index 1))))))

    ;; The library that defines a global: its name up to the first colon.
    (: name-owner (impl (Fn String -> String)))
    (define (name-owner name)
      (let ((chars (string->vector name)))
        (let loop ((index 0))
          (cond ((= index (vector-length chars)) "")
                ((char=? (vector-ref chars index) #\:) (substring name 0 index))
                (else (loop (+ index 1)))))))

    ;; The host can hold an opaque Any or null, without constructing a GC
    ;; enum. This is a boundary convention, not Option's internal layout.
    (: optional-any-type? (impl (Fn Type -> Bool)))
    (define (optional-any-type? type)
      (match type
        ((TCon "snail.core.base:Option" (Cons (TCon "Any" (Nil)) (Nil))) #t)
        (_ #f)))

    (: type->string (impl (Fn Type -> String)))
    (define (type->string type)
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

    (: callable->string (impl (Fn String Type -> String)))
    (define (callable->string former type)
      (match (Pair (callable-kind type) (callable-arrow type))
        ((Pair (Some kind) (Some (TFun params result row)))
         (string-append "(" former " " (arrow->string kind params result row) ")"))
        (_ (panic "internal error: printing a callable without its signature"))))

    (: arrow->string (impl (Fn String (List Type) Type Type -> String)))
    (define (arrow->string kind params result row)
      (string-append "(" kind (types->string params) " -> " (type->string result)
                     (row->string row) ")"))

    (: types->string (impl (Fn (List Type) -> String)))
    (define (types->string types)
      (string-concatenate (map (lambda (type) (string-append " " (type->string type))) types)))

    (: row->string (impl (Fn Type -> String)))
    (define (row->string row)
      (let* ((parts (row-parts row (Nil))) (labels (::first parts)) (tail (::second parts)))
        (match tail
          ((None) (if (null? labels) "" (string-append " !" (labels->string labels))))
          ((Some tail) (string-append " !" (labels->string labels) " " (type->string tail))))))

    (: labels->string (impl (Fn (List String) -> String)))
    (define (labels->string labels)
      (string-concatenate (map (lambda (label) (string-append " " (short-name label))) labels)))

    ;; The labels of a row, following bound tails, and its final tail.
    (: row-parts (impl (Fn Type (List String) -> (Pair (List String) (Option Type)))))
    (define (row-parts row labels)
      (match row
        ((TRow more (Some tail)) (row-parts tail (label-union labels more)))
        ((TRow more (None)) (Pair (label-union labels more) (None)))
        (_ (Pair labels (Some row)))))

    ;; Types the backend gives a representation of their own: Any boxes a
    ;; TypeId with its value, and a String or Bytes argument to a host
    ;; function is staged into the runtime's buffer, so it can come only last.
    (: any-type? (impl (Fn Type -> Bool)))
    (define (any-type? type)
      (match type
        ((TCon "Any" (Nil)) #t)
        (_ #f)))

    ;; (snail core base)'s type with no values. A control operation that
    ;; answers it never resumes, so its yield saves nothing.
    (: never-type? (impl (Fn Type -> Bool)))
    (define (never-type? type)
      (match type
        ((TCon "snail.core.base:Never" (Nil)) #t)
        (_ #f)))

    ;; The lifecycle classes, whose methods release a value, `(Drop e T)`,
    ;; and copy one, `(Clone e T)`, performing `e` for a T. What they run,
    ;; and so their rows, is found from T's structure, glue for a type
    ;; without an instance, rather than chosen by matching instances, so the
    ;; checker and mono treat them apart from other classes over a row.
    (: drop-class String)
    (define drop-class "snail.core.base:Drop")

    (: clone-class String)
    (define clone-class "snail.core.base:Clone")

    (: lifecycle-class? (impl (Fn String -> Bool)))
    (define (lifecycle-class? class)
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
    (: field-class? (impl (Fn String -> Bool)))
    (define (field-class? class)
      (and (>= (string-length class) 2) (string=? (substring class 0 2) "::")))

    (: field-class-name (impl (Fn String -> String)))
    (define (field-class-name label)
      (string-append "::" label))

    ;; The program with a label's class and method declared.
    (: program-with-field-class (impl (Fn Program String -> Program)))
    (define (program-with-field-class program label)
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
    (: program-with-field-instance (impl (Fn Program DataType String Type String -> Program)))
    (define (program-with-field-instance program data label type accessor)
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
    (: field-instance-accessor (impl (Fn Program String String -> (Option Value))))
    (define (field-instance-accessor program class instance)
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

    (: string-type? (impl (Fn Type -> Bool)))
    (define (string-type? type)
      (match type
        ((TCon "String" (Nil)) #t)
        (_ #f)))

    (: bytes-type? (impl (Fn Type -> Bool)))
    (define (bytes-type? type)
      (match type
        ((TCon "Vector" (Cons (TCon "U8" (Nil)) (Nil))) #t)
        (_ #f)))

    (: buffer-type? (impl (Fn Type -> Bool)))
    (define (buffer-type? type)
      (or (string-type? type) (bytes-type? type)))

    ;; A unique text for a ground type, with full names; it names
    ;; specializations and Wasm types. A row argument, as in (Task e), does
    ;; not affect representation.
    (: type-key (impl (Fn Type -> String)))
    (define (type-key type)
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
    (: hidden-effects (impl (Fn Type -> (Option Type))))
    (define (hidden-effects type)
      (match type
        ((TFun params result row)
         (if (empty-row? row) (first-hidden-effects (Cons result params)) (Some type)))
        ((TCon _ args) (first-hidden-effects args))
        ((TRow _ _) (if (empty-row? type) (None) (Some type)))
        ((TRigid _) (Some type))
        ((TVar _) (panic "internal error: an unsolved type in a conversion"))))

    (: first-hidden-effects (impl (Fn (List Type) -> (Option Type))))
    (define (first-hidden-effects types)
      (match types
        ((Cons type rest)
         (match (hidden-effects type)
           ((Some part) (Some part))
           ((None) (first-hidden-effects rest))))
        ((Nil) (None))))

    (: empty-row? (impl (Fn Type -> Bool)))
    (define (empty-row? row)
      (match (row-parts row (Nil))
        ((Pair (Nil) (None)) #t)
        (_ #f)))

    ;; Structural equality of types without bound metavariables.
    (: type=? (impl (Fn Type Type -> Bool)))
    (define (type=? a b)
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

    (: types=? (impl (Fn (List Type) (List Type) -> Bool)))
    (define (types=? as bs)
      (and (= (length as) (length bs))
           (every? (lambda (pair) (type=? (::first pair) (::second pair))) (zip as bs))))

    ;; ---- Label sets ----

    ;; Row labels are sorted lists without duplicates, so equal sets print
    ;; alike.
    (: label-insert (impl (Fn String (List String) -> (List String))))
    (define (label-insert label labels)
      (match labels
        ((Nil) (list label))
        ((Cons first rest)
         (cond ((string=? label first) labels)
               ((string<? label first) (Cons label labels))
               (else (Cons first (label-insert label rest)))))))

    (: label-union (impl (Fn (List String) (List String) -> (List String))))
    (define (label-union a b)
      (fold-left (lambda (labels label) (label-insert label labels)) a b))

    (: label-difference (impl (Fn (List String) (List String) -> (List String))))
    (define (label-difference a b)
      (filter (lambda (label) (not (member? label b))) a))

    ;; ---- Substitution ----

    (type Substitution (List (Pair String Type)))

    ;; Replaces rigid variables by the types a substitution gives them.
    (: substitute (impl (Fn Substitution Type -> Type)))
    (define (substitute substitution type)
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

    (: substitute-constraint (impl (Fn Substitution Constraint -> Constraint)))
    (define (substitute-constraint substitution constraint)
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

    (: lambda-expr? (impl (Fn Expr -> Bool)))
    (define (lambda-expr? expr)
      (match (::term expr)
        ((Lambda _ _ _) #t)
        (_ #f)))

    ;; Immediate structural children, in source order, including lambda
    ;; bodies. This describes the IR shape, not when an expression runs.
    (: expr-children (impl (Fn Expr -> (List Expr))))
    (define (expr-children expr)
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
    (: expr-references (impl (Fn Expr -> (List String))))
    (define (expr-references expr)
      (reverse (::second (collect-references (Pair empty-table (Nil)) expr))))

    ;; Adds the names not yet seen to the found list, newest first, and to
    ;; the seen table.
    (: collect-references
       (impl (Fn (Pair (Table Bool) (List String)) Expr -> (Pair (Table Bool) (List String)))))
    (define (collect-references found expr)
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
    (: row-arguments (impl (Fn Class (List Type) -> (List Type))))
    (define (row-arguments class types)
      (map ::second
           (filter (lambda (pair) (member? (::first pair) (::rows class)))
                   (zip (::params class) types))))

    (: type-arguments (impl (Fn Class (List Type) -> (List Type))))
    (define (type-arguments class types)
      (map ::second
           (filter (lambda (pair)
                     (not (member? (::first pair)
                                   (append (::rows class) (::outputs class)))))
                   (zip (::params class) types))))

    ;; Associated members are hidden trailing arguments. Like rows they
    ;; are established by the selected evidence, never used to select it.
    (: output-arguments (impl (Fn Class (List Type) -> (List Type))))
    (define (output-arguments class types)
      (list-drop types (- (length (::params class)) (length (::outputs class)))))

    ;; One-way matching of an instance head; only its own variables bind.
    (: match-types
       (impl (Fn (List String) (List Type) (List Type) Substitution -> (Option Substitution))))
    (define (match-types vars patterns types bindings)
      (if (= (length patterns) (length types))
          (fold-left (lambda (result pair)
                       (match result
                         ((Some bindings)
                          (match-type vars (::first pair) (::second pair) bindings))
                         ((None) (None))))
                     (Some bindings) (zip patterns types))
          (None)))

    (: match-type (impl (Fn (List String) Type Type Substitution -> (Option Substitution))))
    (define (match-type vars pattern type bindings)
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
    (: row-variable (impl (Fn Type -> (List String))))
    (define (row-variable row)
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
    (: value-scheme (impl (Fn Value -> (Option Scheme))))
    (define (value-scheme value)
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
    (: operation-latent (impl (Fn String Scheme -> (List String))))
    (define (operation-latent effect scheme)
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
    (: item-definitions (impl (Fn (List Item) -> (Table Expr))))
    (define (item-definitions items)
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

    (: empty-program Program)
    (define empty-program
      (Program empty-table empty-table empty-table empty-table empty-table empty-table (Nil) (Nil)))

    (: metadata-of (impl (Fn Program String -> Metadata)))
    (define (metadata-of program name)
      (match (table-ref (::metadata program) name)
        ((Some metadata) metadata)
        ((None) (Metadata (Nil) empty-table))))

    (: program-annotations (impl (Fn Program String -> (List Annotation))))
    (define (program-annotations program name)
      (::annotations (metadata-of program name)))

    (: program-field-annotations (impl (Fn Program String String -> (List Annotation))))
    (define (program-field-annotations program constructor field)
      (match (table-ref (::fields (metadata-of program constructor)) field)
        ((Some annotations) annotations)
        ((None) (Nil))))

    (: program-with-annotations (impl (Fn Program String (List Annotation) -> Program)))
    (define (program-with-annotations program name annotations)
      (let ((before (metadata-of program name)))
        (if (null? annotations)
            program
            (Program-metadata-set program
                                  (table-set (::metadata program) name
                                             (Metadata
                                              (append (::annotations before) annotations)
                                              (::fields before)))))))

    (: program-with-field-annotations
       (impl (Fn Program String String (List Annotation) -> Program)))
    (define (program-with-field-annotations program constructor field annotations)
      (let ((before (metadata-of program constructor)))
        (if (null? annotations)
            program
            (Program-metadata-set program
                                  (table-set (::metadata program) constructor
                                             (Metadata (::annotations before)
                                                       (table-set (::fields before)
                                                                  field
                                                                  annotations)))))))

    (: program-value (impl (Fn Program String -> (Option Value))))
    (define (program-value program name)
      (table-ref (::values program) name))

    ;; Types, classes and effects are looked up by names the expander
    ;; resolved, so each lookup succeeds.
    (: program-type (impl (Fn Program String -> DataType)))
    (define (program-type program name)
      (match (table-ref (::types program) name)
        ((Some data) data)
        ((None) (panic (string-append "internal error: no type " name)))))

    (: program-class (impl (Fn Program String -> Class)))
    (define (program-class program name)
      (match (table-ref (::classes program) name)
        ((Some class) class)
        ((None) (panic (string-append "internal error: no class " name)))))

    (: program-effect (impl (Fn Program String -> Effect)))
    (define (program-effect program name)
      (match (table-ref (::effects program) name)
        ((Some effect) effect)
        ((None) (panic (string-append "internal error: no effect " name)))))

    (: class-instances (impl (Fn Program String -> (List Instance))))
    (define (class-instances program class)
      (match (table-ref (::instances program) class)
        ((Some instances) instances)
        ((None) (Nil))))

    ;; Named instances are available only inside an explicit lexical scope.
    ;; All instances remain in the program: selected evidence names them
    ;; even when a later caller has a different active policy.
    (: visible-instances (impl (Fn Program String (List String) -> (List Instance))))
    (define (visible-instances program class sets)
      (filter (lambda (instance)
                (match (::set instance)
                  ((None) #t)
                  ((Some name) (member? name sets))))
              (class-instances program class)))

    (: check-active-instances (impl (Fn Program (List String) Loc -> Unit ! compile)))
    (define (check-active-instances program sets loc)
      (for-each (lambda (class)
                  (let ((visible (visible-instances program (::name class) sets)))
                    (for-each (lambda (instance)
                                (check-instance-overlap program instance visible loc)) visible)))
                (table-values (::classes program))))

    (: check-instance-overlap (impl (Fn Program Instance (List Instance) Loc -> Unit ! compile)))
    (define (check-instance-overlap program instance others loc)
      (let ((class (program-class program (::class instance))))
        (for-each (lambda (other)
                    (when (and (not (string=? (::name instance) (::name other)))
                               (heads-overlap? (type-arguments class (::types instance))
                                               (type-arguments class (::types other))))
                      (compile-error loc
                                     "this instance overlaps another instance of the class on its input types")))
                  others)))

    (: heads-overlap? (impl (Fn (List Type) (List Type) -> Bool)))
    (define (heads-overlap? as bs)
      (and (= (length as) (length bs))
           (every? (lambda (pair) (head-overlaps? (::first pair) (::second pair)))
                   (zip as bs))))

    (: head-overlaps? (impl (Fn Type Type -> Bool)))
    (define (head-overlaps? a b)
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
    (: selected-method-arguments
       (impl (Fn Program String (List Type) (List Evidence) -> (List Type))))
    (define (selected-method-arguments program class types evidence)
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
    (: program-with-value (impl (Fn Program String Value -> Program)))
    (define (program-with-value program name value)
      (Program-values-set program (table-set (::values program) name value)))

    (: program-with-type (impl (Fn Program DataType -> Program)))
    (define (program-with-type program data)
      (Program-types-set program (table-set (::types program) (::name data) data)))

    (: program-with-class (impl (Fn Program Class -> Program)))
    (define (program-with-class program class)
      (Program-classes-set program (table-set (::classes program) (::name class) class)))

    (: program-with-instance (impl (Fn Program Instance -> Program)))
    (define (program-with-instance program instance)
      (let ((class (::class instance)))
        (Program-instances-set program (table-set (::instances program) class
                                                  (append (class-instances program class)
                                                          (list instance))))))

    (: program-with-effect (impl (Fn Program Effect -> Program)))
    (define (program-with-effect program effect)
      (Program-effects-set program
                           (table-set (::effects program) (::name effect) effect)))

    (: program-items (impl (Fn Program -> (List Item))))
    (define (program-items program)
      (reverse (::items program)))

    ;; A library's run joins the program whole: its items, newest first,
    ;; become the program's newest, and the count it records is theirs. A
    ;; library loaded while another expands joins first, so it can never be
    ;; counted in the other's run.
    (: program-with-library (impl (Fn Program String (List Item) -> Program)))
    (define (program-with-library program name items)
      (Program-libraries-set (Program-items-set program (append items (::items program)))
                             (Cons (Pair name (length items)) (::libraries program))))

    ;; What the newest library added: the globals named for it, and its run
    ;; of items, which are the newest. A later build replays it with
    ;; `program-with` instead of expanding the library again.
    (: program-delta (impl (Fn Program String -> Program)))
    (define (program-delta program owner)
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
    (: owned (All (V) (requires (Copy V)) (impl (Fn (Table V) String -> (Table V)))))
    (define (owned table owner)
      (fold-left (lambda (result key)
                   (match (table-ref table key)
                     ((Some value)
                      (if (or (string=? (name-owner key) owner) (string=? (name-owner key) ""))
                          (table-set result key value)
                          result))
                     ((None) result)))
                 empty-table (table-keys table)))

    (: owned-instances (impl (Fn (Table (List Instance)) String -> (Table (List Instance)))))
    (define (owned-instances table owner)
      (fold-left (lambda (result class)
                   (match (filter (lambda (instance)
                                    (string=? (name-owner (::name instance)) owner))
                                  (class-list table class))
                     ((Nil) result)
                     (instances (table-set result class instances))))
                 empty-table (table-keys table)))

    (: class-list (impl (Fn (Table (List Instance)) String -> (List Instance))))
    (define (class-list table class)
      (match (table-ref table class)
        ((Some instances) instances)
        ((None) (Nil))))

    ;; The program with a library's additions from an earlier build. Its
    ;; globals are its own, so it replaces nothing; the order of instances
    ;; within a class does not matter, since no two of them overlap.
    (: program-with (impl (Fn Program Program -> Program)))
    (define (program-with program delta)
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
    (: table-union (All (V) (requires (Copy V)) (impl (Fn (Table V) (Table V) -> (Table V)))))
    (define (table-union table additions)
      (fold-left (lambda (result key)
                   (match (table-ref additions key)
                     ((Some value) (table-set result key value))
                     ((None) result)))
                 table (table-keys additions)))

    ;; Divides items in program order, such as the program's own or their
    ;; checked copies, into each library's run.
    (: library-items (impl (Fn Program (List Item) -> (List (Pair String (List Item))))))
    (define (library-items program items)
      (let loop ((libraries (reverse (::libraries program))) (items items) (out (Nil)))
        (match libraries
          ((Cons (Pair name count) rest)
           (loop rest (list-tail items count) (Cons (Pair name (take items count)) out)))
          ((Nil) (reverse out)))))

    ;; ---- Wire identities ----

    ;; FNV-1a, as an unsigned 32-bit value: starting from `fnv-offset`,
    ;; `fnv-step` mixes in each code, a code point or a byte, in turn. The
    ;; product stays below 2^56, so it never overflows I64.
    (: fnv-offset I64)
    (define fnv-offset 2166136261)

    (: fnv-step (impl (Fn I64 I64 -> I64)))
    (define (fnv-step hash code)
      (i64-and (* (i64-xor hash code) 16777619) 4294967295))

    ;; FNV-1a over the code points.
    (: fnv-1a (impl (Fn String -> I64)))
    (define (fnv-1a text)
      (vector-fold (lambda (hash c) (fnv-step hash (char->integer c)))
                   fnv-offset
                   (string->vector text)))

    ;; A TypeId is a hash as a signed 32-bit value, which Wasm's i32 holds.
    (: type-id (impl (Fn String -> I64)))
    (define (type-id text)
      (let ((hash (fnv-1a text)))
        (if (>= hash 2147483648) (- hash 4294967296) hash)))

    ;; A case's TypeId hashes its declaring library, type, name and fields.
    ;; Field types contribute their own schemas, cut at recursive
    ;; references, so the identity changes exactly when the encoded shape
    ;; can change.
    (: case-type-id (impl (Fn Program Case -> I64)))
    (define (case-type-id program case)
      (type-id (case-schema program case (Nil))))

    ;; An Any's TypeId hashes the type with its structure as the wire schema
    ;; writes it: fields and cases, recursively. A type whose fields or cases
    ;; change gets a new one even when its name stays, so a program relinked
    ;; with such a change cannot take an old value for a new one.
    (: any-type-id (impl (Fn Program Type -> I64)))
    (define (any-type-id program type)
      (type-id (type-identity program type)))

    ;; The same identity in 64 bits, for a dynamic export's signature: it is
    ;; compared once, when a program looks the function up, rather than
    ;; carried by every value.
    (: wide-type-id (impl (Fn Program Type -> I64)))
    (define (wide-type-id program type)
      (wide-hash (type-identity program type)))

    (: type-identity (impl (Fn Program Type -> String)))
    (define (type-identity program type)
      (string-append (type-key type) "\n" (type-schema program type (Nil) (Nil))))

    ;; FNV-1a in 64 bits over the code points, as a signed I64. The state is
    ;; two unsigned 32-bit halves, high and low, so that every product stays
    ;; below 2^42 and both hosts compute the same value; the prime is
    ;; 2^40 + 435, whose 2^40 shifts the low half eight bits into the high.
    (: wide-hash (impl (Fn String -> I64)))
    (define (wide-hash text)
      (let ((state (vector-fold (lambda (state c) (wide-step state (char->integer c)))
                                (Pair 3421674724 2216829733)
                                (string->vector text))))
        (+ (* (if (>= (::first state) 2147483648)
                  (- (::first state) 4294967296)
                  (::first state))
              4294967296)
           (::second state))))

    (: wide-step (impl (Fn (Pair I64 I64) I64 -> (Pair I64 I64))))
    (define (wide-step state code)
      (let* ((low (i64-xor (::second state) code)) (product (* low 435)))
        (Pair (i64-and (+ (+ (* (::first state) 435) (quotient product 4294967296))
                          (* (i64-and low 16777215) 256))
                       4294967295)
              (i64-and product 4294967295))))

    (: case-schema (impl (Fn Program Case (List String) -> String)))
    (define (case-schema program case visiting)
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
    (: type-schema (impl (Fn Program Type (List String) (List String) -> String)))
    (define (type-schema program type params visiting)
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
    (: wire-schemas (impl (Fn Program -> String)))
    (define (wire-schemas program)
      (string-concatenate
       (map (lambda (instance)
              (match (::types instance)
                ((Cons (TCon name _) (Nil))
                 (if (table-contains? (::types program) name)
                     (data-schema program (program-type program name))
                     ""))
                (_ "")))
            (class-instances program "snail.shell.wire:Serialize"))))

    (: data-schema (impl (Fn Program DataType -> String)))
    (define (data-schema program data)
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

    (: strong-components (impl (Fn (Vector (List I64)) -> (List (List I64)))))
    (define (strong-components edges)
      (let ((search (fold-left
                     (lambda (search node) (if (reached? search node) search (visit search node)))
                     (Search edges empty-table empty-table empty-table (Nil) 0 (Nil))
                     (iota (vector-length edges)))))
        (reverse (::components search))))

    (: node-key (impl (Fn I64 -> String)))
    (define (node-key node)
      (i64->string node))

    (: reached? (impl (Fn Search I64 -> Bool)))
    (define (reached? search node)
      (match (table-ref (::index search) (node-key node))
        ((Some _) #t)
        ((None) #f)))

    (: node-index (impl (Fn Search I64 -> I64)))
    (define (node-index search node)
      (match (table-ref (::index search) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (: node-low (impl (Fn Search I64 -> I64)))
    (define (node-low search node)
      (match (table-ref (::low search) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (: open? (impl (Fn Search I64 -> Bool)))
    (define (open? search node)
      (match (table-ref (::open search) (node-key node))
        ((Some flag) flag)
        ((None) #f)))

    ;; Numbers `node`, pushes it, follows its edges, and closes a component
    ;; when nothing it reached leads back past it.
    (: visit (impl (Fn Search I64 -> Search)))
    (define (visit search node)
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
    (: follow (impl (Fn Search I64 I64 -> Search)))
    (define (follow search node next)
      (cond ((not (reached? search next))
             (let ((search (visit search next)))
               (lower search node (node-low search next))))
            ((open? search next) (lower search node (node-index search next)))
            (else search)))

    (: lower (impl (Fn Search I64 I64 -> Search)))
    (define (lower search node number)
      (Search-low-set search
                      (table-set (::low search)
                                 (node-key node)
                                 (min (node-low search node) number))))

    ;; Pops the stack down to `node`; those nodes are one component.
    (: pop-component (impl (Fn Search I64 -> Search)))
    (define (pop-component search node)
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
    (: primitive-global (impl (Fn String -> String)))
    (define (primitive-global name)
      (string-append "prim:" name))

    ;; What the primitive library adds to a program, for a later build to
    ;; replay: its values alone. It has no module, since the backend
    ;; implements everything it declares, so it records no run of items.
    (: primitive-delta (impl (Fn Program -> Program)))
    (define (primitive-delta program)
      (Program-values-set empty-program (owned (::values program) "prim")))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-core)
    (import
     (snail stage0 testing))
    (begin
      (define (test-core)
        (expect (short-name "snail.core.base:map") "map")
        (expect (label-union (list "b" "d") (list "c" "a" "b")) (list "a" "b" "c" "d"))
        (expect (wide-hash "") -3750763034362895579)
        (expect (wide-hash "a") -5808556873153909620)
        (expect (wide-hash "foobar") -8821353812377114648)
        (test-hidden-effects)
        (test-references))

      ;; Structural traversal enters latent lambda bodies and handler
      ;; implementations, preserving first occurrence while deduplicating.
      (define (test-references)
        (let* ((at (Loc "references" 1 1))
               (wrap (lambda (term) (Expr term unchecked at)))
               (read (lambda (name) (wrap (Var name (Nil) (Nil)))))
               (body (wrap (App (read "later") (list (read "first") (read "last")))))
               (handler (wrap (Lambda (list "unused") (read "first") #t)))
               (expr (wrap (Handle "effect" (list (Pair "operation" handler)) body))))
          (expect (expr-references expr) (list "first" "later" "last"))))

      ;; A total function hides nothing; an effectful one is found at any
      ;; depth of the type, and a type variable may be one.
      (define (test-hidden-effects)
        (let* ((i64 (TCon "I64" (Nil)))
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
          (expect (hidden-effects (TCon "Holder" (list (TRigid "A")))) (Some (TRigid "A")))))))
   (else)))
