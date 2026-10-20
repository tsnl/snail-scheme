;; The core language shared by every pass after expansion. The expander
;; produces a Program: entity tables keyed by unique names, and an ordered list
;; of top-level items. The checker fills in each expression's type; the
;; monomorphizer replaces type arguments with ground types.
(define-library (lofi compiler core)
  (export
   TCon
   TFun
   TRow
   TVar
   TRigid
   TVar-cell
   empty-row
   Constraint
   Constraint-class
   Constraint-types
   Scheme
   Scheme-vars
   Scheme-constraints
   Scheme-type
   mono-scheme
   type->string
   datum->type
   substitute
   substitute-constraint
   builtin-types
   EvInstance
   EvParam
   EvHole
   EvHole-cell
   Expr
   Expr-term
   Expr-type
   Expr-loc
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
   Clause
   Clause-pattern
   Clause-body
   PWild
   PVar
   PLit
   PCon
   pattern-type
   expr->datum
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
   Effect
   Effect-name
   Effect-operations
   Effect-host
   Defined
   Constructor
   Accessor
   Replacer
   Method
   Operation
   Primitive
   Foreign
   Define
   Define-name
   Define-value
   Do
   Do-expr
   Expose
   Program
   make-program
   Program-values
   Program-types
   Program-classes
   Program-instances
   Program-effects
   Program-items
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
   program-item-list
   primitives
   short-name
   case-type-id)
  (import
   (scheme base)
   (scheme char)
   (srfi 1)
   (srfi 69)
   (lofi compiler shim)
   (lofi compiler read))
  (begin

    ;; ---- Types ----

    ;; `TCon` names a builtin or declared type by its unique name. A row is a
    ;; set of effect labels whose tail is #f when closed, or a type variable.
    ;; Metavariables exist only inside the checker.
    (enum Type
      (TCon
       ((name Symbol)
        (args (List Type))))
      (TFun
       ((params (List Type))
        (result Type)
        (row Type)))
      (TRow
       ((labels (List Symbol))
        (tail Type)))
      (TVar
       ((id I64)
        (cell (Ref Type))))
      (TRigid
       ((name Symbol))))

    (define empty-row (TRow '() #f))

    (struct Constraint
      ((class Symbol)
       (types (List Type))))

    ;; A scheme quantifies rigid variables, which may stand for types or rows.
    (struct Scheme
      ((vars (List Symbol))
       (constraints (List Constraint))
       (type Type)))

    (define (mono-scheme type)
      (Scheme '() '() type))

    (define builtin-types
      '((U8 . 0) (I32 . 0) (I64 . 0) (F32 . 0) (F64 . 0) (Bool . 0) (Char . 0) (Unit . 0)
        (String . 0) (Array . 1) (Vector . 1) (Ref . 1)))

    ;; Unique names look like `lofi.base:map`; diagnostics show the source name.
    (define (short-name name)
      (let* ((text (symbol->string name)) (length (string-length text)))
        (let loop ((index (- length 1)))
          (cond ((< index 0) text)
                ((char=? (string-ref text index) #\:) (substring text (+ index 1) length))
                (else (loop (- index 1)))))))

    (define (type->string type)
      (match type
        ((TCon name '()) (short-name name))
        ((TCon name args) (string-append "(" (short-name name) (types->string args) ")"))
        ((TFun params result row)
         (string-append "(->" (types->string params) " " (type->string result) (row->string row) ")"))
        ((TRow labels tail) (string-append "{" (row->string type) " }"))
        ((TVar id cell)
         (let ((bound (ref-get cell)))
           (if bound (type->string bound) (string-append "?" (number->string id)))))
        ((TRigid name) (symbol->string name))))

    (define (types->string types)
      (apply string-append (map (lambda (type) (string-append " " (type->string type))) types)))

    (define (row->string row)
      (let* ((flat (row-parts row '())) (labels (car flat)) (tail (cdr flat)))
        (if (and (null? labels) (not tail))
            ""
            (string-append " !" (apply string-append (map (lambda (label) (string-append " " (short-name label))) labels))
                           (if tail (string-append " " (type->string tail)) "")))))

    ;; The labels of a row, following bound tails, and its final tail.
    (define (row-parts row labels)
      (match row
        ((TRow more tail) (if tail (row-parts tail (append labels more)) (cons (append labels more) #f)))
        ((TVar _ cell) (if (ref-get cell) (row-parts (ref-get cell) labels) (cons labels row)))
        (_ (cons labels row))))

    ;; Replaces rigid variables by the types an association list gives them.
    (define (substitute substitution type)
      (match type
        ((TRigid name) (let ((entry (assq name substitution))) (if entry (cdr entry) type)))
        ((TCon name args) (TCon name (map (lambda (arg) (substitute substitution arg)) args)))
        ((TFun params result row) (TFun (map (lambda (p) (substitute substitution p)) params)
                                        (substitute substitution result) (substitute substitution row)))
        ((TRow labels tail)
         (match (and tail (substitute substitution tail))
           ((TRow more rest) (TRow (append labels (filter (lambda (label) (not (memq label labels))) more)) rest))
           (other (TRow labels other))))
        (_ type)))

    (define (substitute-constraint substitution constraint)
      (Constraint (Constraint-class constraint)
                  (map (lambda (type) (substitute substitution type)) (Constraint-types constraint))))

    ;; Primitive signatures are written as Lofi type syntax: capitalized
    ;; single letters are type variables, `e` is a row variable.
    (define (datum->type datum)
      (cond ((memq datum '(A B C)) (TRigid datum))
            ((symbol? datum) (TCon datum '()))
            ((eq? (car datum) '->) (arrow-datum->type (cdr datum) '()))
            (else (TCon (car datum) (map datum->type (cdr datum))))))

    (define (arrow-datum->type items params)
      (cond ((null? (cdr items)) (TFun (reverse params) (datum->type (car items)) empty-row))
            ((eq? (cadr items) '!)
             (TFun (reverse params) (datum->type (car items))
                   (TRow (filter-labels (cddr items)) (if (memq 'e (cddr items)) (TRigid 'e) #f))))
            (else (arrow-datum->type (cdr items) (cons (datum->type (car items)) params)))))

    (define (filter-labels items)
      (cond ((null? items) '())
            ((eq? (car items) 'e) (filter-labels (cdr items)))
            (else (cons (car items) (filter-labels (cdr items))))))

    ;; ---- Class evidence ----

    ;; Evidence says which instance satisfies a constraint: an instance applied
    ;; to type arguments and the evidence for its requirements, or the
    ;; enclosing definition's own requirement at `index`. Holes exist only
    ;; while checking.
    (enum Evidence
      (EvInstance
       ((instance Symbol)
        (types (List Type))
        (subs (List Evidence))))
      (EvParam
       ((index I64)))
      (EvHole
       ((cell (Ref Evidence)))))

    ;; ---- Expressions ----

    ;; Every expression has a type (#f until checked) and a location.
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
       ((name Symbol)
        (types (List Type))
        (evidence (List Evidence))))
      (Lambda
       ((params (List Symbol))
        (body Expr)))
      (App
       ((callee Expr)
        (args (List Expr))))
      (If
       ((test Expr)
        (then Expr)
        (else Expr)))
      (Let
       ((name Symbol)
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
       ((effect Symbol)
        (implementations (List (Pair Symbol Expr)))
        (body Expr))))

    (struct Clause
      ((pattern Pattern)
       (body Expr)))

    (enum Pattern
      (PWild
       ((type Type)))
      (PVar
       ((name Symbol)
        (type Type)))
      (PLit
       ((value Datum)
        (type Type)))
      (PCon
       ((constructor Symbol)
        (args (List Pattern))
        (type Type))))

    (define (pattern-type pattern)
      (match pattern
        ((PWild type) type)
        ((PVar _ type) type)
        ((PLit _ type) type)
        ((PCon _ _ type) type)))

    ;; A readable rendering for tests and debugging.
    (define (expr->datum expr)
      (match (Expr-term expr)
        ((Lit value) value)
        ((Var name '() '()) name)
        ((Var name types _) (cons name (map type->string types)))
        ((Lambda params body) (list 'lambda params (expr->datum body)))
        ((App callee args) (map expr->datum (cons callee args)))
        ((If test then else) (list 'if (expr->datum test) (expr->datum then) (expr->datum else)))
        ((Let name value body) (list 'let name (expr->datum value) (expr->datum body)))
        ((Seq first rest) (list 'seq (expr->datum first) (expr->datum rest)))
        ((Match scrutinee clauses)
         (cons 'match (cons (expr->datum scrutinee)
                            (map (lambda (clause) (list (pattern->datum (Clause-pattern clause)) (expr->datum (Clause-body clause))))
                                 clauses))))
        ((Ann expr type) (list 'ann (expr->datum expr) (type->string type)))
        ((Handle effect implementations body)
         (list 'handle effect (map (lambda (entry) (list (car entry) (expr->datum (cdr entry)))) implementations)
               (expr->datum body)))))

    (define (pattern->datum pattern)
      (match pattern
        ((PWild _) '_)
        ((PVar name _) name)
        ((PLit value _) value)
        ((PCon constructor args _) (cons constructor (map pattern->datum args)))))

    ;; ---- Declared entities ----

    ;; A struct is a data type with one case named after it.
    (struct DataType
      ((name Symbol)
       (params (List Symbol))
       (cases (List Case))
       (enum? Bool)))

    (struct Case
      ((name Symbol)
       (type Symbol)
       (tag I64)
       (fields (List Field))))

    (struct Field
      ((name Symbol)
       (type Type)))

    ;; Method schemes quantify the class parameters first and require the
    ;; class itself as their first constraint.
    (struct Class
      ((name Symbol)
       (params (List Symbol))
       (methods (List Symbol))))

    ;; Each method maps to the top-level definition that implements it.
    (struct Instance
      ((name Symbol)
       (class Symbol)
       (vars (List Symbol))
       (types (List Type))
       (requires (List Constraint))
       (methods (List (Pair Symbol Symbol)))))

    ;; Host defaults map operation names to (module . symbol) imports.
    (struct Effect
      ((name Symbol)
       (operations (List Symbol))
       (host (List (Pair Symbol (Pair String String))))))

    ;; What a unique value name denotes.
    (enum Value
      (Defined
       ((scheme Scheme)))
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
       ((class Symbol)
        (scheme Scheme)))
      (Operation
       ((effect Symbol)
        (scheme Scheme)))
      (Primitive
       ((scheme Scheme)))
      (Foreign
       ((module String)
        (symbol String)
        (scheme Scheme))))

    ;; Top-level items run in order when the program starts. An exposed
    ;; function is exported to the host under `symbol`.
    (enum Item
      (Define
       ((name Symbol)
        (value Expr)))
      (Do
       ((expr Expr)))
      (Expose
       ((name Symbol)
        (symbol String)
        (loc Loc))))

    ;; ---- Programs ----

    (struct Program
      ((values HashTable)
       (types HashTable)
       (classes HashTable)
       (instances HashTable)
       (effects HashTable)
       (items (Ref (List Item)))))

    (define (make-program)
      (Program (make-hash-table eq?) (make-hash-table eq?) (make-hash-table eq?)
               (make-hash-table eq?) (make-hash-table eq?) (ref '())))

    (define (program-value program name)
      (hash-table-ref/default (Program-values program) name #f))

    (define (program-type program name)
      (hash-table-ref/default (Program-types program) name #f))

    (define (program-class program name)
      (hash-table-ref/default (Program-classes program) name #f))

    (define (program-effect program name)
      (hash-table-ref/default (Program-effects program) name #f))

    (define (class-instances program class)
      (hash-table-ref/default (Program-instances program) class '()))

    (define (add-value! program name value)
      (hash-table-set! (Program-values program) name value))

    (define (add-type! program data-type)
      (hash-table-set! (Program-types program) (DataType-name data-type) data-type))

    (define (add-class! program class)
      (hash-table-set! (Program-classes program) (Class-name class) class))

    (define (add-instance! program instance)
      (hash-table-update!/default (Program-instances program) (Instance-class instance)
                                  (lambda (instances) (append instances (list instance))) '()))

    (define (add-effect! program effect)
      (hash-table-set! (Program-effects program) (Effect-name effect) effect))

    (define (add-item! program item)
      (ref-set! (Program-items program) (cons item (ref-get (Program-items program)))))

    (define (program-item-list program)
      (reverse (ref-get (Program-items program))))

    ;; ---- Wire identities ----

    ;; A case's TypeId hashes its declaring library, type, name and fields.
    ;; Field types contribute their own schemas, cut at recursive references,
    ;; so the identity changes exactly when the encoded shape can change.
    (define (case-type-id program case)
      (let ((hash (fnv-1a (case-schema program case '()))))
        (if (>= hash (expt 2 31)) (- hash (expt 2 32)) hash)))

    (define (case-schema program case visiting)
      (let* ((data (program-type program (Case-type case))) (params (DataType-params data))
             (visiting (cons (DataType-name data) visiting)))
        (string-append (symbol->string (Case-name case)) "("
                       (apply string-append
                              (map (lambda (field)
                                     (string-append (symbol->string (Field-name field)) ":"
                                                    (type-schema program (Field-type field) params visiting) ";"))
                                   (Case-fields case)))
                       ")")))

    (define (type-schema program type params visiting)
      (match type
        ((TRigid name) (string-append "#" (number->string (length (memq name (reverse params))))))
        ((TCon name args)
         (let ((data (program-type program name))
               (arguments (apply string-append (map (lambda (arg) (string-append (type-schema program arg params visiting) ",")) args))))
           (string-append (symbol->string name) "<" arguments ">"
                          (if (and data (not (memq name visiting)))
                              (apply string-append (map (lambda (case) (case-schema program case visiting)) (DataType-cases data)))
                              ""))))
        (_ "fn")))

    (define (fnv-1a text)
      (let loop ((hash 2166136261) (chars (string->list text)))
        (if (null? chars)
            hash
            (loop (modulo (* (exclusive-or hash (char->integer (car chars))) 16777619) 4294967296) (cdr chars)))))

    (define (exclusive-or a b)
      (let loop ((a a) (b b) (bit 1) (result 0))
        (if (and (= a 0) (= b 0))
            result
            (loop (quotient a 2) (quotient b 2) (* bit 2)
                  (if (= (modulo a 2) (modulo b 2)) result (+ result bit))))))

    ;; ---- Primitives ----

    ;; Operations the backend implements directly. `mut` marks operations on
    ;; mutable storage; everything else is total, though some can trap.
    ;; `unsafe-total` calls a thunk and discards its effects: the standard
    ;; library uses it where mutation is confined to storage it allocates.
    (define primitives
      '((unit (-> Unit)) (panic (-> String A)) (unsafe-total (-> (-> A ! e) A))
        (i32-add (-> I32 I32 I32)) (i32-sub (-> I32 I32 I32)) (i32-mul (-> I32 I32 I32))
        (i32-quotient (-> I32 I32 I32)) (i32-remainder (-> I32 I32 I32))
        (i32-and (-> I32 I32 I32)) (i32-or (-> I32 I32 I32)) (i32-xor (-> I32 I32 I32))
        (i32-shift-left (-> I32 I32 I32)) (i32-shift-right (-> I32 I32 I32))
        (i32-shift-right/logical (-> I32 I32 I32))
        (i32-eq (-> I32 I32 Bool)) (i32-lt (-> I32 I32 Bool)) (i32-le (-> I32 I32 Bool))
        (i32-gt (-> I32 I32 Bool)) (i32-ge (-> I32 I32 Bool))
        (i64-add (-> I64 I64 I64)) (i64-sub (-> I64 I64 I64)) (i64-mul (-> I64 I64 I64))
        (i64-quotient (-> I64 I64 I64)) (i64-remainder (-> I64 I64 I64))
        (i64-and (-> I64 I64 I64)) (i64-or (-> I64 I64 I64)) (i64-xor (-> I64 I64 I64))
        (i64-shift-left (-> I64 I64 I64)) (i64-shift-right (-> I64 I64 I64))
        (i64-shift-right/logical (-> I64 I64 I64))
        (i64-eq (-> I64 I64 Bool)) (i64-lt (-> I64 I64 Bool)) (i64-le (-> I64 I64 Bool))
        (i64-gt (-> I64 I64 Bool)) (i64-ge (-> I64 I64 Bool))
        (f32-add (-> F32 F32 F32)) (f32-sub (-> F32 F32 F32)) (f32-mul (-> F32 F32 F32))
        (f32-div (-> F32 F32 F32)) (f32-min (-> F32 F32 F32)) (f32-max (-> F32 F32 F32))
        (f32-eq (-> F32 F32 Bool)) (f32-lt (-> F32 F32 Bool)) (f32-le (-> F32 F32 Bool))
        (f32-gt (-> F32 F32 Bool)) (f32-ge (-> F32 F32 Bool))
        (f32-sqrt (-> F32 F32)) (f32-abs (-> F32 F32)) (f32-negate (-> F32 F32))
        (f32-floor (-> F32 F32)) (f32-ceiling (-> F32 F32)) (f32-truncate (-> F32 F32))
        (f32-round (-> F32 F32))
        (f64-add (-> F64 F64 F64)) (f64-sub (-> F64 F64 F64)) (f64-mul (-> F64 F64 F64))
        (f64-div (-> F64 F64 F64)) (f64-min (-> F64 F64 F64)) (f64-max (-> F64 F64 F64))
        (f64-eq (-> F64 F64 Bool)) (f64-lt (-> F64 F64 Bool)) (f64-le (-> F64 F64 Bool))
        (f64-gt (-> F64 F64 Bool)) (f64-ge (-> F64 F64 Bool))
        (f64-sqrt (-> F64 F64)) (f64-abs (-> F64 F64)) (f64-negate (-> F64 F64))
        (f64-floor (-> F64 F64)) (f64-ceiling (-> F64 F64)) (f64-truncate (-> F64 F64))
        (f64-round (-> F64 F64))
        (i32->i64 (-> I32 I64)) (i64->i32 (-> I64 I32)) (i64->f64 (-> I64 F64))
        (f64->i64 (-> F64 I64)) (i32->f64 (-> I32 F64)) (f64->i32 (-> F64 I32))
        (i32->f32 (-> I32 F32)) (f32->i32 (-> F32 I32)) (i64->f32 (-> I64 F32)) (f32->i64 (-> F32 I64))
        (f32->f64 (-> F32 F64)) (f64->f32 (-> F64 F32))
        (f32->bits (-> F32 I32)) (bits->f32 (-> I32 F32)) (f64->bits (-> F64 I64)) (bits->f64 (-> I64 F64))
        (bool->i32 (-> Bool I32)) (i32->bool (-> I32 Bool)) (u8->i32 (-> U8 I32)) (i32->u8 (-> I32 U8))
        (char->i32 (-> Char I32)) (i32->char (-> I32 Char))
        (string-length (-> String I64)) (string-ref (-> String I64 Char))
        (string-append (-> String String String)) (substring (-> String I64 I64 String))
        (string=? (-> String String Bool)) (string-compare (-> String String I32))
        (make-string (-> I64 Char String))
        (string->vector (-> String (Vector Char))) (vector->string (-> (Vector Char) String))
        (vector-length (-> (Vector A) I64)) (vector-ref (-> (Vector A) I64 A))
        (vector-append (-> (Vector A) (Vector A) (Vector A))) (subvector (-> (Vector A) I64 I64 (Vector A)))
        (make-vector (-> I64 A (Vector A))) (vector-set (-> (Vector A) I64 A (Vector A)))
        (vector-generate (-> I64 (-> I64 A ! e) (Vector A) ! e))
        (string-generate (-> I64 (-> I64 Char ! e) String ! e))
        (make-array (-> I64 A (Array A) ! mut)) (array-length (-> (Array A) I64))
        (array-ref (-> (Array A) I64 A ! mut)) (array-set! (-> (Array A) I64 A Unit ! mut))
        (array->vector (-> (Array A) (Vector A) ! mut)) (vector->array (-> (Vector A) (Array A) ! mut))
        (array-copy! (-> (Array A) I64 (Array A) I64 I64 Unit ! mut))
        (vector-copy! (-> (Array A) I64 (Vector A) I64 I64 Unit ! mut))
        (ref (-> A (Ref A) ! mut)) (ref-get (-> (Ref A) A ! mut)) (ref-set! (-> (Ref A) A Unit ! mut))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-core)
    (import
     (lofi host test-utils))
    (begin
      (define (test-core)
        (expect (type->string (datum->type '(-> I64 (Vector A) A))) "(-> I64 (Vector A) A)")
        (expect (type->string (datum->type '(-> I64 (-> I64 A ! e) (Vector A) ! e)))
                "(-> I64 (-> I64 A ! e) (Vector A) ! e)")
        (expect (type->string (datum->type '(-> (Ref A) A ! mut))) "(-> (Ref A) A ! mut)")
        (expect (short-name 'lofi.base:map) "map"))))
   (else)))
