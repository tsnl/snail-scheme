;; The core language shared by every pass after expansion. The expander
;; produces a Program: entity tables keyed by unique names, and an ordered list
;; of top-level items. The checker fills in each expression's type; the
;; monomorphizer replaces type arguments with ground types.
(define-library (lofi compiler core)
  (export
   Type
   TCon
   TFun
   TRow
   TVar
   TRigid
   TVar-cell
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
   labels->string
   type=?
   types=?
   short-name
   substitute
   substitute-constraint
   label-union
   label-difference
   builtin-types
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
   Effect-host
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
   Program
   empty-program
   Program-instances
   Program-effects
   program-value
   program-type
   program-class
   program-effect
   class-instances
   add-value!
   add-type!
   add-class!
   add-instance!
   add-effect!
   add-item!
   add-unit!
   program-items
   unit-items
   name-owner
   primitives
   fnv-1a
   case-type-id
   wire-schemas)
  (import
   (lofi base)
   (lofi table)
   (lofi compiler read))
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
       ((id I64)
        (cell (Ref (Option Type)))))
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

    (: builtin-types (List (Pair String I64)))
    (define builtin-types
      (list (Pair "Any" 0) (Pair "U8" 0) (Pair "I32" 0) (Pair "I64" 0) (Pair "F32" 0) (Pair "F64" 0) (Pair "Bool" 0)
            (Pair "Char" 0) (Pair "Unit" 0) (Pair "String" 0) (Pair "Array" 1) (Pair "Vector" 1) (Pair "Ref" 1)))

    ;; Unique names look like `lofi.base:map`; diagnostics show the source
    ;; name. Text is scanned as a vector of characters, which both hosts index
    ;; in constant time.
    (: short-name (-> String String))
    (define (short-name name)
      (let ((chars (string->vector name)))
        (let loop ((index (- (vector-length chars) 1)))
          (cond ((< index 0) name)
                ((char=? (vector-ref chars index) #\:) (substring name (+ index 1) (string-length name)))
                (else (loop (- index 1)))))))

    (: type->string (-> Type String ! mut))
    (define (type->string type)
      (match type
        ((TCon name (Nil)) (short-name name))
        ((TCon name args) (string-append "(" (short-name name) (types->string args) ")"))
        ((TFun params result row)
         (string-append "(->" (types->string params) " " (type->string result) (row->string row) ")"))
        ((TRow _ _) (string-append "{" (row->string type) " }"))
        ((TVar id cell)
         (match (ref-get cell)
           ((Some bound) (type->string bound))
           ((None) (string-append "?" (i64->string id)))))
        ((TRigid name) name)))

    (: types->string (-> (List Type) String ! mut))
    (define (types->string types)
      (string-concatenate (map (lambda (type) (string-append " " (type->string type))) types)))

    (: row->string (-> Type String ! mut))
    (define (row->string row)
      (let* ((parts (row-parts row (Nil))) (labels (Pair-first parts)) (tail (Pair-second parts)))
        (match tail
          ((None) (if (null? labels) "" (string-append " !" (labels->string labels))))
          ((Some tail) (string-append " !" (labels->string labels) " " (type->string tail))))))

    (: labels->string (-> (List String) String))
    (define (labels->string labels)
      (string-concatenate (map (lambda (label) (string-append " " (short-name label))) labels)))

    ;; The labels of a row, following bound tails, and its final tail.
    (: row-parts (-> Type (List String) (Pair (List String) (Option Type)) ! mut))
    (define (row-parts row labels)
      (match row
        ((TRow more (Some tail)) (row-parts tail (label-union labels more)))
        ((TRow more (None)) (Pair (label-union labels more) (None)))
        ((TVar _ cell)
         (match (ref-get cell)
           ((Some bound) (row-parts bound labels))
           ((None) (Pair labels (Some row)))))
        (_ (Pair labels (Some row)))))

    ;; A unique text for a ground type, with full names; it names
    ;; specializations and Wasm types. A row argument, as in (Task e), does
    ;; not affect representation.
    (: type-key (-> Type String))
    (define (type-key type)
      (match type
        ((TCon name (Nil)) name)
        ((TCon name args) (string-append name "<" (string-join (map type-key args) ",") ">"))
        ((TFun params result _) (string-append "fn<" (string-join (map type-key params) ",") "->" (type-key result) ">"))
        ((TRow _ _) "row")
        ((TRigid name) name)
        ((TVar id _) (string-append "?" (i64->string id)))))

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
           ((TFun others other-result other-row) (and (types=? params others) (type=? result other-result) (type=? row other-row)))
           (_ #f)))
        ((TRow labels tail)
         (match b
           ((TRow others other-tail)
            (and (= (length labels) (length others)) (every? (lambda (label) (member? label others)) labels)
                 (match tail
                   ((Some tail) (match other-tail ((Some other) (type=? tail other)) ((None) #f)))
                   ((None) (match other-tail ((Some _) #f) ((None) #t))))))
           (_ #f)))
        ((TVar id _)
         (match b
           ((TVar other _) (= id other))
           (_ #f)))
        ((TRigid name)
         (match b
           ((TRigid other) (string=? name other))
           (_ #f)))))

    (: types=? (-> (List Type) (List Type) Bool))
    (define (types=? as bs)
      (and (= (length as) (length bs)) (every? (lambda (pair) (type=? (Pair-first pair) (Pair-second pair))) (zip as bs))))

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
         (TFun (map (lambda (param) (substitute substitution param)) params) (substitute substitution result)
               (substitute substitution row)))
        ((TRow labels (Some tail))
         (match (substitute substitution tail)
           ((TRow more rest) (TRow (label-union labels more) rest))
           (other (TRow labels (Some other)))))
        (_ type)))

    (: substitute-constraint (-> Substitution Constraint Constraint))
    (define (substitute-constraint substitution constraint)
      (Constraint (Constraint-class constraint)
                  (map (lambda (type) (substitute substitution type)) (Constraint-types constraint))))

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
       ((cell (Ref (Option Evidence))))))

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
    (: collect-references (-> (Pair (Table Bool) (List String)) Expr (Pair (Table Bool) (List String))))
    (define (collect-references found expr)
      (let ((collect collect-references))
        (match (Expr-term expr)
          ((Lit _) found)
          ((Var name _ _)
           (match found
             ((Pair seen names) (if (table-contains? seen name) found (Pair (table-set seen name #t) (Cons name names))))))
          ((Lambda _ body) (collect found body))
          ((App callee args) (fold-left collect found (Cons callee args)))
          ((If test then otherwise) (fold-left collect found (list test then otherwise)))
          ((Let _ value body) (collect (collect found value) body))
          ((Seq first rest) (collect (collect found first) rest))
          ((Match scrutinee clauses) (fold-left collect (collect found scrutinee) (map Clause-body clauses)))
          ((Ann inner _) (collect found inner))
          ((Convert inner _) (collect found inner))
          ((Handle _ implementations body) (collect (fold-left collect found (map Pair-second implementations)) body)))))

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

    ;; Host defaults map operation names to Wasm imports.
    (struct Effect
      ((name String)
       (operations (List String))
       (host (List (Pair String Import)))))

    ;; What a unique value name denotes.
    (enum Value
      (Defined
        ((scheme (Option Scheme))))
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
        ((Defined scheme) scheme)
        ((Constructor _ scheme) (Some scheme))
        ((Accessor _ _ scheme) (Some scheme))
        ((Replacer _ _ scheme) (Some scheme))
        ((Method _ scheme) (Some scheme))
        ((Operation _ scheme) (Some scheme))
        ((Primitive scheme) (Some scheme))
        ((Foreign _ scheme) (Some scheme))))

    ;; Top-level items run in order when the program starts. An exposed
    ;; function is exported to the host under `symbol`.
    (enum Item
      (Define
        ((name String)
         (value Expr)))
      (Do
       ((expr Expr)))
      (Expose
       ((name String)
        (symbol String)
        (loc Loc))))

    ;; ---- Programs ----

    ;; A program is a value: the expander builds it up in one cell, and the
    ;; later passes only read it. Items are kept newest first. `units` names
    ;; each library, newest first, with the number of items it added: a
    ;; library's items are contiguous, after those of the libraries it
    ;; imports, so the program's items divide into one run per library.
    (struct Program
      ((values (Table Value))
       (types (Table DataType))
       (classes (Table Class))
       (instances (Table (List Instance)))
       (effects (Table Effect))
       (items (List Item))
       (units (List (Pair String I64)))))

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

    ;; Each addition replaces the expander's program with a larger one.
    (: add-value! (-> (Ref Program) String Value Unit ! mut))
    (define (add-value! cell name value)
      (let ((program (ref-get cell)))
        (ref-set! cell (Program-values-set program (table-set (Program-values program) name value)))))

    (: add-type! (-> (Ref Program) DataType Unit ! mut))
    (define (add-type! cell data)
      (let ((program (ref-get cell)))
        (ref-set! cell (Program-types-set program (table-set (Program-types program) (DataType-name data) data)))))

    (: add-class! (-> (Ref Program) Class Unit ! mut))
    (define (add-class! cell class)
      (let ((program (ref-get cell)))
        (ref-set! cell (Program-classes-set program (table-set (Program-classes program) (Class-name class) class)))))

    (: add-instance! (-> (Ref Program) Instance Unit ! mut))
    (define (add-instance! cell instance)
      (let* ((program (ref-get cell)) (class (Instance-class instance)))
        (ref-set! cell (Program-instances-set program (table-set (Program-instances program) class
                                                                 (append (class-instances program class) (list instance)))))))

    (: add-effect! (-> (Ref Program) Effect Unit ! mut))
    (define (add-effect! cell effect)
      (let ((program (ref-get cell)))
        (ref-set! cell (Program-effects-set program (table-set (Program-effects program) (Effect-name effect) effect)))))

    (: add-item! (-> (Ref Program) Item Unit ! mut))
    (define (add-item! cell item)
      (let ((program (ref-get cell)))
        (ref-set! cell (Program-items-set program (Cons item (Program-items program))))))

    (: program-items (-> Program (List Item)))
    (define (program-items program)
      (reverse (Program-items program)))

    (: add-unit! (-> (Ref Program) String I64 Unit ! mut))
    (define (add-unit! cell name count)
      (let ((program (ref-get cell)))
        (ref-set! cell (Program-units-set program (Cons (Pair name count) (Program-units program))))))

    ;; Divides items in program order, such as the program's own or their
    ;; checked copies, into each library's run.
    (: unit-items (-> Program (List Item) (List (Pair String (List Item)))))
    (define (unit-items program items)
      (let loop ((units (reverse (Program-units program))) (items items) (out (Nil)))
        (match units
          ((Cons (Pair name count) rest) (loop rest (list-tail items count) (Cons (Pair name (take items count)) out)))
          ((Nil) (reverse out)))))

    ;; The library that defines a global: its name up to the first colon.
    (: name-owner (-> String String))
    (define (name-owner name)
      (let ((chars (string->vector name)))
        (let loop ((index 0))
          (cond ((= index (vector-length chars)) "")
                ((char=? (vector-ref chars index) #\:) (substring name 0 index))
                (else (loop (+ index 1)))))))

    ;; ---- Wire identities ----

    ;; FNV-1a over the code points, as an unsigned 32-bit value. The product
    ;; stays below 2^56, so it never overflows I64.
    (: fnv-1a (-> String I64))
    (define (fnv-1a text)
      (vector-fold (lambda (hash c) (i64-and (* (i64-xor hash (char->integer c)) 16777619) 4294967295)) 2166136261 (string->vector text)))

    ;; A case's TypeId hashes its declaring library, type, name and fields,
    ;; as a signed 32-bit value. Field types contribute their own schemas,
    ;; cut at recursive references, so the identity changes exactly when the
    ;; encoded shape can change.
    (: case-type-id (-> Program Case I64))
    (define (case-type-id program case)
      (let ((hash (fnv-1a (case-schema program case (Nil)))))
        (if (>= hash 2147483648) (- hash 4294967296) hash)))

    (: case-schema (-> Program Case (List String) String))
    (define (case-schema program case visiting)
      (let* ((data (program-type program (Case-type case))) (visiting (Cons (DataType-name data) visiting)))
        (string-append (Case-name case) "("
                       (string-concatenate
                        (map (lambda (field)
                               (string-append (Field-name field) ":"
                                              (type-schema program (Field-type field) (DataType-params data) visiting) ";"))
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
                        (string-concatenate (map (lambda (arg) (string-append (type-schema program arg params visiting) ",")) args))
                        ">"
                        (if (or (member? name visiting) (not (table-contains? (Program-types program) name)))
                            ""
                            (string-concatenate (map (lambda (case) (case-schema program case visiting))
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
                 (if (table-contains? (Program-types program) name) (data-schema program (program-type program name)) ""))
                (_ "")))
            (class-instances program "lofi.wire:Serialize"))))

    (: data-schema (-> Program DataType String))
    (define (data-schema program data)
      (string-append
       "(" (DataType-name data)
       (string-concatenate
        (map (lambda (case)
               (string-append "\n  (" (short-name (Case-name case)) " " (i64->string (case-type-id program case))
                              (string-concatenate
                               (map (lambda (field) (string-append " (" (Field-name field) " " (type-key (Field-type field)) ")"))
                                    (Case-fields case)))
                              ")"))
             (DataType-cases data)))
       ")\n"))

    ;; ---- Primitives ----

    ;; Operations the backend implements directly, with their signatures in
    ;; Lofi type syntax: the variables are A, B and C, and the row variable e.
    ;; `mut` marks operations on mutable storage; everything else is total,
    ;; though some can trap. `unsafe-total` calls a thunk and discards its
    ;; effects, unchecked: the standard library uses it where the checker
    ;; cannot confirm that mutation stays in storage the function allocates.
    (: primitive-signatures (List String))
    (define primitive-signatures
      (list
       "(unit (-> Unit)) (panic (-> String A)) (unsafe-total (-> (-> A ! e) A))"
       "(i32-add (-> I32 I32 I32)) (i32-sub (-> I32 I32 I32)) (i32-mul (-> I32 I32 I32))"
       "(i32-quotient (-> I32 I32 I32)) (i32-remainder (-> I32 I32 I32))"
       "(i32-and (-> I32 I32 I32)) (i32-or (-> I32 I32 I32)) (i32-xor (-> I32 I32 I32))"
       "(i32-shift-left (-> I32 I32 I32)) (i32-shift-right (-> I32 I32 I32))"
       "(i32-shift-right/logical (-> I32 I32 I32))"
       "(i32-eq (-> I32 I32 Bool)) (i32-lt (-> I32 I32 Bool)) (i32-le (-> I32 I32 Bool))"
       "(i32-gt (-> I32 I32 Bool)) (i32-ge (-> I32 I32 Bool))"
       "(i64-add (-> I64 I64 I64)) (i64-sub (-> I64 I64 I64)) (i64-mul (-> I64 I64 I64))"
       "(i64-quotient (-> I64 I64 I64)) (i64-remainder (-> I64 I64 I64))"
       "(i64-and (-> I64 I64 I64)) (i64-or (-> I64 I64 I64)) (i64-xor (-> I64 I64 I64))"
       "(i64-shift-left (-> I64 I64 I64)) (i64-shift-right (-> I64 I64 I64))"
       "(i64-shift-right/logical (-> I64 I64 I64))"
       "(i64-eq (-> I64 I64 Bool)) (i64-lt (-> I64 I64 Bool)) (i64-le (-> I64 I64 Bool))"
       "(i64-gt (-> I64 I64 Bool)) (i64-ge (-> I64 I64 Bool))"
       "(f32-add (-> F32 F32 F32)) (f32-sub (-> F32 F32 F32)) (f32-mul (-> F32 F32 F32))"
       "(f32-div (-> F32 F32 F32)) (f32-min (-> F32 F32 F32)) (f32-max (-> F32 F32 F32))"
       "(f32-eq (-> F32 F32 Bool)) (f32-lt (-> F32 F32 Bool)) (f32-le (-> F32 F32 Bool))"
       "(f32-gt (-> F32 F32 Bool)) (f32-ge (-> F32 F32 Bool))"
       "(f32-sqrt (-> F32 F32)) (f32-abs (-> F32 F32)) (f32-negate (-> F32 F32))"
       "(f32-floor (-> F32 F32)) (f32-ceiling (-> F32 F32)) (f32-truncate (-> F32 F32))"
       "(f32-round (-> F32 F32))"
       "(f64-add (-> F64 F64 F64)) (f64-sub (-> F64 F64 F64)) (f64-mul (-> F64 F64 F64))"
       "(f64-div (-> F64 F64 F64)) (f64-min (-> F64 F64 F64)) (f64-max (-> F64 F64 F64))"
       "(f64-eq (-> F64 F64 Bool)) (f64-lt (-> F64 F64 Bool)) (f64-le (-> F64 F64 Bool))"
       "(f64-gt (-> F64 F64 Bool)) (f64-ge (-> F64 F64 Bool))"
       "(f64-sqrt (-> F64 F64)) (f64-abs (-> F64 F64)) (f64-negate (-> F64 F64))"
       "(f64-floor (-> F64 F64)) (f64-ceiling (-> F64 F64)) (f64-truncate (-> F64 F64))"
       "(f64-round (-> F64 F64))"
       "(i32->i64 (-> I32 I64)) (i64->i32 (-> I64 I32)) (i64->f64 (-> I64 F64))"
       "(f64->i64 (-> F64 I64)) (i32->f64 (-> I32 F64)) (f64->i32 (-> F64 I32))"
       "(i32->f32 (-> I32 F32)) (f32->i32 (-> F32 I32)) (i64->f32 (-> I64 F32)) (f32->i64 (-> F32 I64))"
       "(f32->f64 (-> F32 F64)) (f64->f32 (-> F64 F32))"
       "(f32->bits (-> F32 I32)) (bits->f32 (-> I32 F32)) (f64->bits (-> F64 I64)) (bits->f64 (-> I64 F64))"
       "(bool->i32 (-> Bool I32)) (i32->bool (-> I32 Bool)) (u8->i32 (-> U8 I32)) (i32->u8 (-> I32 U8))"
       "(char->i32 (-> Char I32)) (i32->char (-> I32 Char))"
       "(string-length (-> String I64)) (string-ref (-> String I64 Char))"
       "(string-append (-> String String String)) (substring (-> String I64 I64 String))"
       "(string=? (-> String String Bool)) (string-compare (-> String String I32))"
       "(make-string (-> I64 Char String))"
       "(string->vector (-> String (Vector Char))) (vector->string (-> (Vector Char) String))"
       "(vector-length (-> (Vector A) I64)) (vector-ref (-> (Vector A) I64 A))"
       "(vector-append (-> (Vector A) (Vector A) (Vector A))) (subvector (-> (Vector A) I64 I64 (Vector A)))"
       "(make-vector (-> I64 A (Vector A))) (vector-set (-> (Vector A) I64 A (Vector A)))"
       "(vector-generate (-> I64 (-> I64 A ! e) (Vector A) ! e))"
       "(string-generate (-> I64 (-> I64 Char ! e) String ! e))"
       "(make-array (-> I64 A (Array A) ! mut)) (array-length (-> (Array A) I64))"
       "(array-ref (-> (Array A) I64 A ! mut)) (array-set! (-> (Array A) I64 A Unit ! mut))"
       "(array->vector (-> (Array A) (Vector A) ! mut)) (vector->array (-> (Vector A) (Array A) ! mut))"
       "(array-copy! (-> (Array A) I64 (Array A) I64 I64 Unit ! mut))"
       "(vector-copy! (-> (Array A) I64 (Vector A) I64 I64 Unit ! mut))"
       "(ref (-> A (Ref A) ! mut)) (ref-get (-> (Ref A) A ! mut)) (ref-set! (-> (Ref A) A Unit ! mut))"))

    ;; Each primitive's name and scheme, quantified over every variable it uses.
    (: primitives (-> (List (Pair String Scheme))))
    (define (primitives)
      (map (lambda (form)
             (match form
               ((Form (Cons (Ident name _ _) (Cons signature (Nil))) _)
                (let ((type (signature->type signature)))
                  (Pair name (Scheme (delete-duplicates string=? (rigid-names type)) (Nil) type))))
               (_ (panic "internal error: malformed primitive signature"))))
           (read-text (string-join primitive-signatures " ") "primitives")))

    (: signature->type (-> Syntax Type))
    (define (signature->type syntax)
      (match syntax
        ((Ident name _ _) (if (member? name (list "A" "B" "C" "e")) (TRigid name) (TCon name (Nil))))
        ((Form (Cons (Ident "->" _ _) items) _) (arrow->type items (Nil)))
        ((Form (Cons (Ident name _ _) args) _) (TCon name (map signature->type args)))
        (_ (panic "internal error: malformed primitive type"))))

    ;; `(-> A B R)` or `(-> A B R ! label ... [e])`.
    (: arrow->type (-> (List Syntax) (List Type) Type))
    (define (arrow->type items params)
      (match items
        ((Cons result (Nil)) (TFun (reverse params) (signature->type result) empty-row))
        ((Cons result (Cons (Ident "!" _ _) labels))
         (let ((names (map (lambda (label) (match label ((Ident name _ _) name) (_ "?"))) labels)))
           (TFun (reverse params) (signature->type result)
                 (TRow (filter (lambda (name) (not (string=? name "e"))) names)
                       (if (member? "e" names) (Some (TRigid "e")) (None))))))
        ((Cons param rest) (arrow->type rest (Cons (signature->type param) params)))
        ((Nil) (panic "internal error: an arrow needs a result"))))

    (: rigid-names (-> Type (List String)))
    (define (rigid-names type)
      (match type
        ((TRigid name) (list name))
        ((TCon _ args) (concatenate (map rigid-names args)))
        ((TFun params result row) (append (concatenate (map rigid-names params)) (append (rigid-names result) (rigid-names row))))
        ((TRow _ (Some tail)) (rigid-names tail))
        (_ (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-core)
    (import
     (lofi testing))
    (begin
      (define (primitive-type name)
        (match (find (lambda (entry) (string=? (Pair-first entry) name)) (primitives))
          ((Some entry) (Scheme-type (Pair-second entry)))))
      (define (test-core)
        (expect (type->string (primitive-type "vector-ref")) "(-> (Vector A) I64 A)")
        (expect (type->string (primitive-type "vector-generate")) "(-> I64 (-> I64 A ! e) (Vector A) ! e)")
        (expect (type->string (primitive-type "ref-get")) "(-> (Ref A) A ! mut)")
        (expect (short-name "lofi.base:map") "map")
        (expect (label-union (list "b" "d") (list "c" "a" "b")) (list "a" "b" "c" "d")))))
   (else)))
