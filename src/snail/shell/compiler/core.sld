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
   unchecked
   Constraint
   Constraint-class
   Constraint-types
   Scheme
   Scheme-vars
   Scheme-constraints
   Scheme-type
   mono-scheme
   Substitution
   type->string
   type-key
   any-type?
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
   EvHole
   Expr
   Expr-term
   Expr-type
   Expr-loc
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
   Handle
   Convert
   TypeTest
   Clause
   Clause-pattern
   Clause-body
   Pattern
   PWild
   PVar
   PLit
   PCon
   pattern-type
   lambda-expr?
   expr-references
   DataType
   DataType-name
   DataType-params
   DataType-cases
   DataType-enum?
   Case
   Case-name
   Case-type
   Case-tag
   Case-fields
   Field
   Field-name
   Field-type
   Class
   Class-name
   Class-params
   Class-methods
   Instance
   Instance-name
   Instance-class
   Instance-vars
   Instance-types
   Instance-requires
   Instance-methods
   Instance-methods-set
   Import
   Import-module
   Import-symbol
   Effect
   Effect-name
   Effect-operations
   Effect-control
   Effect-defaults
   Default
   HostDefault
   SnailDefault
   operation-latent
   Value
   Defined
   Constructor
   Accessor
   Replacer
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
   empty-program
   primitive-global
   primitive-delta
   Program-instances
   Program-types
   Program-effects
   program-value
   program-type
   program-class
   program-effect
   class-instances
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

    (: empty-row Type)
    (define empty-row (TRow (Nil) (None)))

    ;; The type of an expression the checker has not yet seen. The checker
    ;; rebuilds every expression, so no later pass meets it.
    (: unchecked Type)
    (define unchecked (TCon "unchecked" (Nil)))

    (struct Constraint
      ((class String)
       (types (List Type))))

    ;; A scheme quantifies rigid variables, which may stand for types or rows.
    (struct Scheme
      ((vars (List String))
       (constraints (List Constraint))
       (type Type)))

    (: mono-scheme (-> Type Scheme))
    (define (mono-scheme type)
      (Scheme (Nil) (Nil) type))

    ;; The names of the core forms, which the expander binds in
    ;; (snail core forms) and (snail shell highlight) colors as keywords.
    (: core-keywords (List String))
    (define core-keywords
      (list "define"
            "lambda"
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
            "match"
            "ann"
            "extern"
            "primitive"
            "effect"
            "handle"
            "expose"
            "case-id"
            "type-convert"
            "type-test"
            "artifact-files" "link-file"))

    (: builtin-types (List (Pair String I64)))
    (define builtin-types
      (list (Pair "Any" 0)
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
            (Pair "Ref" 1)
            (Pair "Once" 1)))

    ;; Unique names look like `snail.core.base:map`; diagnostics show the source
    ;; name. Text is scanned as a vector of characters, which both hosts index
    ;; in constant time.
    (: short-name (-> String String))
    (define (short-name name)
      (let ((chars (string->vector name)))
        (let loop ((index (- (vector-length chars) 1)))
          (cond ((< index 0) name)
                ((char=? (vector-ref chars index) #\:)
                 (substring name (+ index 1) (string-length name)))
                (else (loop (- index 1)))))))

    ;; The library that defines a global: its name up to the first colon.
    (: name-owner (-> String String))
    (define (name-owner name)
      (let ((chars (string->vector name)))
        (let loop ((index 0))
          (cond ((= index (vector-length chars)) "")
                ((char=? (vector-ref chars index) #\:) (substring name 0 index))
                (else (loop (+ index 1)))))))

    ;; The host can hold an opaque Any or null, without constructing a GC
    ;; enum. This is a boundary convention, not Option's internal layout.
    (: optional-any-type? (-> Type Bool))
    (define (optional-any-type? type)
      (match type
        ((TCon "snail.core.base:Option" (Cons (TCon "Any" (Nil)) (Nil))) #t)
        (_ #f)))

    (: type->string (-> Type String))
    (define (type->string type)
      (match type
        ((TCon name (Nil)) (short-name name))
        ((TCon name args) (string-append "(" (short-name name) (types->string args) ")"))
        ((TFun params result row)
         (string-append "(->"
                        (types->string params)
                        " "
                        (type->string result)
                        (row->string row)
                        ")"))
        ((TRow _ _) (string-append "{" (row->string type) " }"))
        ((TVar id) (string-append "?" (i64->string id)))
        ((TRigid name) name)))

    (: types->string (-> (List Type) String))
    (define (types->string types)
      (string-concatenate (map (lambda (type) (string-append " " (type->string type))) types)))

    (: row->string (-> Type String))
    (define (row->string row)
      (let* ((parts (row-parts row (Nil))) (labels (Pair-first parts)) (tail (Pair-second parts)))
        (match tail
          ((None) (if (null? labels) "" (string-append " !" (labels->string labels))))
          ((Some tail) (string-append " !" (labels->string labels) " " (type->string tail))))))

    (: labels->string (-> (List String) String))
    (define (labels->string labels)
      (string-concatenate (map (lambda (label) (string-append " " (short-name label))) labels)))

    ;; The labels of a row, following bound tails, and its final tail.
    (: row-parts (-> Type (List String) (Pair (List String) (Option Type))))
    (define (row-parts row labels)
      (match row
        ((TRow more (Some tail)) (row-parts tail (label-union labels more)))
        ((TRow more (None)) (Pair (label-union labels more) (None)))
        (_ (Pair labels (Some row)))))

    ;; Types the backend gives a representation of their own: Any boxes a
    ;; TypeId with its value, and a String or Bytes argument to a host
    ;; function is staged into the runtime's buffer, so it can come only last.
    (: any-type? (-> Type Bool))
    (define (any-type? type)
      (match type
        ((TCon "Any" (Nil)) #t)
        (_ #f)))

    (: string-type? (-> Type Bool))
    (define (string-type? type)
      (match type
        ((TCon "String" (Nil)) #t)
        (_ #f)))

    (: bytes-type? (-> Type Bool))
    (define (bytes-type? type)
      (match type
        ((TCon "Vector" (Cons (TCon "U8" (Nil)) (Nil))) #t)
        (_ #f)))

    (: buffer-type? (-> Type Bool))
    (define (buffer-type? type)
      (or (string-type? type) (bytes-type? type)))

    ;; A unique text for a ground type, with full names; it names
    ;; specializations and Wasm types. A row argument, as in (Task e), does
    ;; not affect representation.
    (: type-key (-> Type String))
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
    (: hidden-effects (-> Type (Option Type)))
    (define (hidden-effects type)
      (match type
        ((TFun params result row)
         (if (empty-row? row) (first-hidden-effects (Cons result params)) (Some type)))
        ((TCon _ args) (first-hidden-effects args))
        ((TRow _ _) (if (empty-row? type) (None) (Some type)))
        ((TRigid _) (Some type))
        ((TVar _) (panic "internal error: an unsolved type in a conversion"))))

    (: first-hidden-effects (-> (List Type) (Option Type)))
    (define (first-hidden-effects types)
      (match types
        ((Cons type rest)
         (match (hidden-effects type)
           ((Some part) (Some part))
           ((None) (first-hidden-effects rest))))
        ((Nil) (None))))

    (: empty-row? (-> Type Bool))
    (define (empty-row? row)
      (match (row-parts row (Nil))
        ((Pair (Nil) (None)) #t)
        (_ #f)))

    ;; Structural equality of types without bound metavariables.
    (: type=? (-> Type Type Bool))
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

    (: types=? (-> (List Type) (List Type) Bool))
    (define (types=? as bs)
      (and (= (length as) (length bs))
           (every? (lambda (pair) (type=? (Pair-first pair) (Pair-second pair))) (zip as bs))))

    ;; ---- Label sets ----

    ;; Row labels are sorted lists without duplicates, so equal sets print
    ;; alike.
    (: label-insert (-> String (List String) (List String)))
    (define (label-insert label labels)
      (match labels
        ((Nil) (list label))
        ((Cons first rest)
         (cond ((string=? label first) labels)
               ((string<? label first) (Cons label labels))
               (else (Cons first (label-insert label rest)))))))

    (: label-union (-> (List String) (List String) (List String)))
    (define (label-union a b)
      (fold-left (lambda (labels label) (label-insert label labels)) a b))

    (: label-difference (-> (List String) (List String) (List String)))
    (define (label-difference a b)
      (filter (lambda (label) (not (member? label b))) a))

    ;; ---- Substitution ----

    (type Substitution (List (Pair String Type)))

    ;; Replaces rigid variables by the types a substitution gives them.
    (: substitute (-> Substitution Type Type))
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

    (: substitute-constraint (-> Substitution Constraint Constraint))
    (define (substitute-constraint substitution constraint)
      (Constraint (Constraint-class constraint)
                  (map (lambda (type) (substitute substitution type))
                       (Constraint-types constraint))))

    ;; ---- Class evidence ----

    ;; Evidence says which instance satisfies a constraint: an instance applied
    ;; to type arguments and the evidence for its requirements, or the
    ;; enclosing definition's own requirement at `index`. Holes exist only
    ;; while checking.
    (enum Evidence
      (EvInstance
       ((instance String)
        (types (List Type))
        (subs (List Evidence))))
      (EvParam
       ((index I64)))
      (EvHole
       ((id I64))))

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
      (Lambda
       ((params (List String))
        (body Expr)))
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

    (: pattern-type (-> Pattern Type))
    (define (pattern-type pattern)
      (match pattern
        ((PWild type) type)
        ((PVar _ type) type)
        ((PLit _ type) type)
        ((PCon _ _ type) type)))

    (: lambda-expr? (-> Expr Bool))
    (define (lambda-expr? expr)
      (match (Expr-term expr)
        ((Lambda _ _) #t)
        (_ #f)))

    ;; Every name an expression refers to, once each, in order of first
    ;; occurrence. Locals are included, since names are unique.
    (: expr-references (-> Expr (List String)))
    (define (expr-references expr)
      (reverse (Pair-second (collect-references (Pair empty-table (Nil)) expr))))

    ;; Adds the names not yet seen to the found list, newest first, and to
    ;; the seen table.
    (: collect-references
       (-> (Pair (Table Bool) (List String)) Expr (Pair (Table Bool) (List String))))
    (define (collect-references found expr)
      (let ((collect collect-references))
        (match (Expr-term expr)
          ((Lit _) found)
          ((Var name _ _)
           (match found
             ((Pair seen names)
              (if (table-contains? seen name)
                  found
                  (Pair (table-set seen name #t) (Cons name names))))))
          ((Lambda _ body) (collect found body))
          ((App callee args) (fold-left collect found (Cons callee args)))
          ((If test then otherwise) (fold-left collect found (list test then otherwise)))
          ((Let _ value body) (collect (collect found value) body))
          ((Seq first rest) (collect (collect found first) rest))
          ((Match scrutinee clauses)
           (fold-left collect (collect found scrutinee) (map Clause-body clauses)))
          ((Ann inner _) (collect found inner))
          ((Convert inner _) (collect found inner))
          ((TypeTest inner _) (collect found inner))
          ((Handle _ implementations body)
           (collect (fold-left collect found (map Pair-second implementations)) body)))))

    ;; ---- Declared entities ----

    ;; A struct is a data type with one case named after it.
    (struct DataType
      ((name String)
       (params (List String))
       (cases (List Case))
       (enum? Bool)))

    (struct Case
      ((name String)
       (type String)
       (tag I64)
       (fields (List Field))))

    (struct Field
      ((name String)
       (type Type)))

    ;; Method schemes quantify the class parameters first and require the
    ;; class itself as their first constraint.
    (struct Class
      ((name String)
       (params (List String))
       (methods (List String))))

    ;; Each method maps to the top-level definition that implements it.
    (struct Instance
      ((name String)
       (class String)
       (vars (List String))
       (types (List Type))
       (requires (List Constraint))
       (methods (List (Pair String String)))))

    (struct Import
      ((module String)
       (symbol String)))

    ;; `control` names the operations whose implementations receive the rest
    ;; of the handled computation as `resume`; the others return to their
    ;; caller. `defaults` maps operation names to what performs them when no
    ;; handler is in scope.
    (struct Effect
      ((name String)
       (operations (List String))
       (control (List String))
       (defaults (List (Pair String Default)))))

    ;; An operation's default: a Wasm import, or a Snail-Core function the
    ;; effect's declaration defines, which runs under the performer's
    ;; handlers.
    (enum Default
      (HostDefault
       ((import Import)))
      (SnailDefault
       ((function String))))

    ;; What a unique value name denotes. A definition's scheme is its
    ;; signature's, or none until it is inferred, and `signature` is where
    ;; that `(: name type)` was written. An instance method has its class
    ;; method's scheme and no signature of its own.
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
    (: value-scheme (-> Value (Option Scheme)))
    (define (value-scheme value)
      (match value
        ((Defined scheme _) scheme)
        ((Constructor _ scheme) (Some scheme))
        ((Accessor _ _ scheme) (Some scheme))
        ((Replacer _ _ scheme) (Some scheme))
        ((Method _ scheme) (Some scheme))
        ((Operation _ scheme) (Some scheme))
        ((Primitive scheme) (Some scheme))
        ((Foreign _ scheme) (Some scheme))))

    ;; The effects an operation's type names besides its own: its latent
    ;; row, which its callers are charged and its implementations may
    ;; perform, under the handlers in scope where it is performed.
    (: operation-latent (-> String Scheme (List String)))
    (define (operation-latent effect scheme)
      (match (Scheme-type scheme)
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
    (: item-definitions (-> (List Item) (Table Expr)))
    (define (item-definitions items)
      (fold-left (lambda (table item)
                   (match item
                     ((Define name value) (table-set table name value))
                     (_ table)))
                 empty-table items))

    ;; ---- Programs ----

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
       (items (List Item))
       (libraries (List (Pair String I64)))))

    (: empty-program Program)
    (define empty-program
      (Program empty-table empty-table empty-table empty-table empty-table (Nil) (Nil)))

    (: program-value (-> Program String (Option Value)))
    (define (program-value program name)
      (table-ref (Program-values program) name))

    ;; Types, classes and effects are looked up by names the expander
    ;; resolved, so each lookup succeeds.
    (: program-type (-> Program String DataType))
    (define (program-type program name)
      (match (table-ref (Program-types program) name)
        ((Some data) data)
        ((None) (panic (string-append "internal error: no type " name)))))

    (: program-class (-> Program String Class))
    (define (program-class program name)
      (match (table-ref (Program-classes program) name)
        ((Some class) class)
        ((None) (panic (string-append "internal error: no class " name)))))

    (: program-effect (-> Program String Effect))
    (define (program-effect program name)
      (match (table-ref (Program-effects program) name)
        ((Some effect) effect)
        ((None) (panic (string-append "internal error: no effect " name)))))

    (: class-instances (-> Program String (List Instance)))
    (define (class-instances program class)
      (match (table-ref (Program-instances program) class)
        ((Some instances) instances)
        ((None) (Nil))))

    ;; Each addition is a larger program, sharing everything else with the
    ;; one it was given.
    (: program-with-value (-> Program String Value Program))
    (define (program-with-value program name value)
      (Program-values-set program (table-set (Program-values program) name value)))

    (: program-with-type (-> Program DataType Program))
    (define (program-with-type program data)
      (Program-types-set program (table-set (Program-types program) (DataType-name data) data)))

    (: program-with-class (-> Program Class Program))
    (define (program-with-class program class)
      (Program-classes-set program (table-set (Program-classes program) (Class-name class) class)))

    (: program-with-instance (-> Program Instance Program))
    (define (program-with-instance program instance)
      (let ((class (Instance-class instance)))
        (Program-instances-set program (table-set (Program-instances program) class
                                                  (append (class-instances program class)
                                                          (list instance))))))

    (: program-with-effect (-> Program Effect Program))
    (define (program-with-effect program effect)
      (Program-effects-set program
                           (table-set (Program-effects program) (Effect-name effect) effect)))

    (: program-items (-> Program (List Item)))
    (define (program-items program)
      (reverse (Program-items program)))

    ;; A library's run joins the program whole: its items, newest first,
    ;; become the program's newest, and the count it records is theirs. A
    ;; library loaded while another expands joins first, so it can never be
    ;; counted in the other's run.
    (: program-with-library (-> Program String (List Item) Program))
    (define (program-with-library program name items)
      (Program-libraries-set (Program-items-set program (append items (Program-items program)))
                             (Cons (Pair name (length items)) (Program-libraries program))))

    ;; What the newest library added: the globals named for it, and its run
    ;; of items, which are the newest. A later build replays it with
    ;; `program-with` instead of expanding the library again.
    (: program-delta (-> Program String Program))
    (define (program-delta program owner)
      (let ((count (match (Program-libraries program)
                     ((Cons (Pair _ count) _) count)
                     ((Nil) 0))))
        (Program (owned (Program-values program) owner)
                 (owned (Program-types program) owner)
                 (owned (Program-classes program) owner)
                 (owned-instances (Program-instances program) owner)
                 (owned (Program-effects program) owner)
                 (take (Program-items program) count) (take (Program-libraries program) 1))))

    (: owned (All (V) (-> (Table V) String (Table V))))
    (define (owned table owner)
      (fold-left (lambda (result key)
                   (match (table-ref table key)
                     ((Some value)
                      (if (string=? (name-owner key) owner) (table-set result key value) result))
                     ((None) result)))
                 empty-table (table-keys table)))

    (: owned-instances (-> (Table (List Instance)) String (Table (List Instance))))
    (define (owned-instances table owner)
      (fold-left (lambda (result class)
                   (match (filter (lambda (instance)
                                    (string=? (name-owner (Instance-name instance)) owner))
                                  (class-list table class))
                     ((Nil) result)
                     (instances (table-set result class instances))))
                 empty-table (table-keys table)))

    (: class-list (-> (Table (List Instance)) String (List Instance)))
    (define (class-list table class)
      (match (table-ref table class)
        ((Some instances) instances)
        ((None) (Nil))))

    ;; The program with a library's additions from an earlier build. Its
    ;; globals are its own, so it replaces nothing; the order of instances
    ;; within a class does not matter, since no two of them overlap.
    (: program-with (-> Program Program Program))
    (define (program-with program delta)
      (Program (table-union (Program-values program) (Program-values delta))
               (table-union (Program-types program) (Program-types delta))
               (table-union (Program-classes program) (Program-classes delta))
               (fold-left (lambda (table class)
                            (table-set table
                                       class
                                       (append (class-list table class)
                                               (class-list (Program-instances delta) class))))
                          (Program-instances program) (table-keys (Program-instances delta)))
               (table-union (Program-effects program) (Program-effects delta))
               (append (Program-items delta) (Program-items program))
               (append (Program-libraries delta) (Program-libraries program))))

    ;; `table` with every entry of `additions`, which win where both have a
    ;; key.
    (: table-union (All (V) (-> (Table V) (Table V) (Table V))))
    (define (table-union table additions)
      (fold-left (lambda (result key)
                   (match (table-ref additions key)
                     ((Some value) (table-set result key value))
                     ((None) result)))
                 table (table-keys additions)))

    ;; Divides items in program order, such as the program's own or their
    ;; checked copies, into each library's run.
    (: library-items (-> Program (List Item) (List (Pair String (List Item)))))
    (define (library-items program items)
      (let loop ((libraries (reverse (Program-libraries program))) (items items) (out (Nil)))
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

    (: fnv-step (-> I64 I64 I64))
    (define (fnv-step hash code)
      (i64-and (* (i64-xor hash code) 16777619) 4294967295))

    ;; FNV-1a over the code points.
    (: fnv-1a (-> String I64))
    (define (fnv-1a text)
      (vector-fold (lambda (hash c) (fnv-step hash (char->integer c)))
                   fnv-offset
                   (string->vector text)))

    ;; A TypeId is a hash as a signed 32-bit value, which Wasm's i32 holds.
    (: type-id (-> String I64))
    (define (type-id text)
      (let ((hash (fnv-1a text)))
        (if (>= hash 2147483648) (- hash 4294967296) hash)))

    ;; A case's TypeId hashes its declaring library, type, name and fields.
    ;; Field types contribute their own schemas, cut at recursive
    ;; references, so the identity changes exactly when the encoded shape
    ;; can change.
    (: case-type-id (-> Program Case I64))
    (define (case-type-id program case)
      (type-id (case-schema program case (Nil))))

    ;; An Any's TypeId hashes the type with its structure as the wire schema
    ;; writes it: fields and cases, recursively. A type whose fields or cases
    ;; change gets a new one even when its name stays, so a program relinked
    ;; with such a change cannot take an old value for a new one.
    (: any-type-id (-> Program Type I64))
    (define (any-type-id program type)
      (type-id (type-identity program type)))

    ;; The same identity in 64 bits, for a dynamic export's signature: it is
    ;; compared once, when a program looks the function up, rather than
    ;; carried by every value.
    (: wide-type-id (-> Program Type I64))
    (define (wide-type-id program type)
      (wide-hash (type-identity program type)))

    (: type-identity (-> Program Type String))
    (define (type-identity program type)
      (string-append (type-key type) "\n" (type-schema program type (Nil) (Nil))))

    ;; FNV-1a in 64 bits over the code points, as a signed I64. The state is
    ;; two unsigned 32-bit halves, high and low, so that every product stays
    ;; below 2^42 and both hosts compute the same value; the prime is
    ;; 2^40 + 435, whose 2^40 shifts the low half eight bits into the high.
    (: wide-hash (-> String I64))
    (define (wide-hash text)
      (let ((state (vector-fold (lambda (state c) (wide-step state (char->integer c)))
                                (Pair 3421674724 2216829733)
                                (string->vector text))))
        (+ (* (if (>= (Pair-first state) 2147483648)
                  (- (Pair-first state) 4294967296)
                  (Pair-first state))
              4294967296)
           (Pair-second state))))

    (: wide-step (-> (Pair I64 I64) I64 (Pair I64 I64)))
    (define (wide-step state code)
      (let* ((low (i64-xor (Pair-second state) code)) (product (* low 435)))
        (Pair (i64-and (+ (+ (* (Pair-first state) 435) (quotient product 4294967296))
                          (* (i64-and low 16777215) 256))
                       4294967295)
              (i64-and product 4294967295))))

    (: case-schema (-> Program Case (List String) String))
    (define (case-schema program case visiting)
      (let* ((data (program-type program (Case-type case)))
             (visiting (Cons (DataType-name data) visiting)))
        (string-append (Case-name case) "("
                       (string-concatenate
                        (map (lambda (field)
                               (string-append (Field-name field) ":"
                                              (type-schema program
                                                           (Field-type field)
                                                           (DataType-params data)
                                                           visiting)
                                              ";"))
                             (Case-fields case)))
                       ")")))

    ;; A type parameter is written by its position, so renaming it keeps the
    ;; identity.
    (: type-schema (-> Program Type (List String) (List String) String))
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
                                (not (table-contains? (Program-types program) name)))
                            ""
                            (string-concatenate
                             (map (lambda (case) (case-schema program case visiting))
                                  (DataType-cases (program-type program name)))))))
        (_ "fn")))

    ;; ---- Wire schemas ----

    ;; Every data type with a Serialize instance, as text: `(Type (Case
    ;; type-id (field type) ...) ...)` with full names. Programs that agree on
    ;; a case's line agree on its encoding.
    (: wire-schemas (-> Program String))
    (define (wire-schemas program)
      (string-concatenate
       (map (lambda (instance)
              (match (Instance-types instance)
                ((Cons (TCon name _) (Nil))
                 (if (table-contains? (Program-types program) name)
                     (data-schema program (program-type program name))
                     ""))
                (_ "")))
            (class-instances program "snail.shell.wire:Serialize"))))

    (: data-schema (-> Program DataType String))
    (define (data-schema program data)
      (string-append
       "(" (DataType-name data)
       (string-concatenate
        (map (lambda (case)
               (string-append "\n  ("
                              (short-name (Case-name case))
                              " "
                              (i64->string (case-type-id program case))
                              (string-concatenate
                               (map (lambda (field)
                                      (string-append " ("
                                                     (Field-name field)
                                                     " "
                                                     (type-key (Field-type field))
                                                     ")"))
                                    (Case-fields case)))
                              ")"))
             (DataType-cases data)))
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

    (: strong-components (-> (Vector (List I64)) (List (List I64))))
    (define (strong-components edges)
      (let ((search (fold-left
                     (lambda (search node) (if (reached? search node) search (visit search node)))
                     (Search edges empty-table empty-table empty-table (Nil) 0 (Nil))
                     (iota (vector-length edges)))))
        (reverse (Search-components search))))

    (: node-key (-> I64 String))
    (define (node-key node)
      (i64->string node))

    (: reached? (-> Search I64 Bool))
    (define (reached? search node)
      (match (table-ref (Search-index search) (node-key node))
        ((Some _) #t)
        ((None) #f)))

    (: node-index (-> Search I64 I64))
    (define (node-index search node)
      (match (table-ref (Search-index search) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (: node-low (-> Search I64 I64))
    (define (node-low search node)
      (match (table-ref (Search-low search) (node-key node))
        ((Some number) number)
        ((None) (panic "internal error: the search has not reached this node"))))

    (: open? (-> Search I64 Bool))
    (define (open? search node)
      (match (table-ref (Search-open search) (node-key node))
        ((Some flag) flag)
        ((None) #f)))

    ;; Numbers `node`, pushes it, follows its edges, and closes a component
    ;; when nothing it reached leads back past it.
    (: visit (-> Search I64 Search))
    (define (visit search node)
      (let* ((number (Search-count search))
             (entered (Search (Search-edges search)
                              (table-set (Search-index search) (node-key node) number)
                              (table-set (Search-low search) (node-key node) number)
                              (table-set (Search-open search) (node-key node) #t)
                              (Cons node (Search-stack search))
                              (+ number 1)
                              (Search-components search)))
             (followed (fold-left (lambda (search next) (follow search node next))
                                  entered (vector-ref (Search-edges search) node))))
        (if (= (node-low followed node) number) (pop-component followed node) followed)))

    ;; Lowers `node`'s link through its edge to `next`, visiting `next`
    ;; first if the search has not reached it.
    (: follow (-> Search I64 I64 Search))
    (define (follow search node next)
      (cond ((not (reached? search next))
             (let ((search (visit search next)))
               (lower search node (node-low search next))))
            ((open? search next) (lower search node (node-index search next)))
            (else search)))

    (: lower (-> Search I64 I64 Search))
    (define (lower search node number)
      (Search-low-set search
                      (table-set (Search-low search)
                                 (node-key node)
                                 (min (node-low search node) number))))

    ;; Pops the stack down to `node`; those nodes are one component.
    (: pop-component (-> Search I64 Search))
    (define (pop-component search node)
      (let loop ((search search) (component (Nil)))
        (match (Search-stack search)
          ((Cons top rest)
           (let ((search (Search-open-set (Search-stack-set search rest)
                                          (table-set (Search-open search) (node-key top) #f))))
             (if (= top node)
                 (Search-components-set search
                                        (Cons (Cons top component) (Search-components search)))
                 (loop search (Cons top component)))))
          ((Nil) (panic "internal error: empty search stack")))))

    ;; ---- Primitives ----

    ;; Operations the backend implements directly. (snail core primitive)
    ;; declares each with its type, and the program holds its value under
    ;; `prim:NAME`, the name the checker, mono and the backend know it by.
    ;; Its owner is `prim`, which no library may be named, rather than the
    ;; library that declares it.
    (: primitive-global (-> String String))
    (define (primitive-global name)
      (string-append "prim:" name))

    ;; What the primitive library adds to a program, for a later build to
    ;; replay: its values alone. It has no module, since the backend
    ;; implements everything it declares, so it records no run of items.
    (: primitive-delta (-> Program Program))
    (define (primitive-delta program)
      (Program-values-set empty-program (owned (Program-values program) "prim")))

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
        (test-hidden-effects))

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
