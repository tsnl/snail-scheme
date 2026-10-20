;; Monomorphic program to WasmGC text. This pass decides representations:
;; scalars are Wasm numbers, enums whose cases have no fields are i32 tags,
;; other data are GC structs (enum cases are subtypes of a tagged base),
;; sequences are GC arrays, and functions are closures holding a typed
;; function reference. Calls in tail position become `return_call`.
(define-library (lofi compiler wasm)
  (export
   emit-module
   wat->string)
  (import
   (scheme base)
   (scheme char)
   (scheme cxr)
   (scheme inexact)
   (scheme write)
   (srfi 1)
   (srfi 69)
   (lofi compiler shim)
   (lofi compiler read)
   (lofi compiler core)
   (lofi compiler mono))
  (begin

    ;; ---- Module state ----

    ;; Every GC type lives in one recursion group, registered on first use.
    ;; `memo` caches helper functions, closure wrappers and string literals.
    (struct Module
      ((program Program)
       (definitions HashTable)
       (type-ids HashTable)
       (types (Ref (List Datum)))
       (imports (Ref (List Datum)))
       (globals (Ref (List Datum)))
       (functions (Ref (List Datum)))
       (declared (Ref (List Symbol)))
       (exports (Ref (List Datum)))
       (memo HashTable)
       (counter (Ref I64))))

    (define (push! cell value)
      (ref-set! cell (cons value (ref-get cell))))

    (define (next-number! m)
      (let ((count (+ (ref-get (Module-counter m)) 1)))
        (ref-set! (Module-counter m) count)
        count))

    (define (memoize! m key make)
      (or (hash-table-ref/default (Module-memo m) key #f)
          (let ((value (make)))
            (hash-table-set! (Module-memo m) key value)
            value)))

    (define (program-of m)
      (Module-program m))

    ;; ---- Names ----

    ;; Characters outside Wasm's identifier set are replaced.
    (define (mangle text)
      (list->string
       (map (lambda (char)
              (case char
                ((#\space) #\_) ((#\,) #\~) ((#\() #\<) ((#\)) #\>) ((#\" #\; #\[ #\] #\{ #\}) #\_)
                (else (if (and (char>? char #\space) (char<? char #\delete)) char #\_))))
            (string->list text))))

    (define (wasm-id . parts)
      (string->symbol (string-append "$" (mangle (apply string-append (map (lambda (part) (if (symbol? part) (symbol->string part) part)) parts))))))

    (define (fresh-id m prefix)
      (wasm-id prefix "." (number->string (next-number! m))))

    ;; ---- Representations ----

    (define (ref-of id)
      (list 'ref id))

    (define (rep-key rep)
      (if (symbol? rep) (symbol->string rep) (let ((id (symbol->string (cadr rep)))) (substring id 1 (string-length id)))))

    ;; A unique textual key for a ground type, used to name its Wasm types.
    (define (type-key type)
      (match type
        ((TCon name '()) (symbol->string name))
        ((TCon name args) (string-append (symbol->string name) "<" (keys->string (map type-key args)) ">"))
        ((TFun params result _) (string-append "fn<" (keys->string (map type-key params)) "->" (type-key result) ">"))))

    (define (keys->string keys)
      (if (null? keys) "" (fold (lambda (key text) (string-append text "," key)) (car keys) (cdr keys))))

    (define (rep m type)
      (match type
        ((TCon name args)
         (case name
           ((U8 I32 Bool Char Unit) 'i32)
           ((I64) 'i64)
           ((F32) 'f32)
           ((F64) 'f64)
           ((String) (ref-of (array-type m 'i32)))
           ((Array Vector) (ref-of (array-type m (element-rep m (car args)))))
           ((Ref) (ref-of (cell-type m (rep m (car args)))))
           (else (if (tag-enum? m name) 'i32 (ref-of (data-type m type))))))
        ((TFun params result _) (ref-of (closure-type m (map (lambda (p) (rep m p)) params) (rep m result))))))

    ;; Byte arrays are packed; a byte is an i32 everywhere else.
    (define (element-rep m type)
      (match type
        ((TCon 'U8 '()) 'i8)
        (_ (rep m type))))

    (define (array-get array)
      (if (eq? array '$arr.i8) 'array.get_u 'array.get))

    (define (register-type! m key id definition)
      (hash-table-set! (Module-type-ids m) key id)
      (push! (Module-types m) definition)
      id)

    (define (known-type m key)
      (hash-table-ref/default (Module-type-ids m) key #f))

    (define (array-type m element)
      (let ((key (string-append "arr." (rep-key element))))
        (or (known-type m key) (register-type! m key (wasm-id key) `(type ,(wasm-id key) (array (mut ,element)))))))

    (define (cell-type m content)
      (let ((key (string-append "cell." (rep-key content))))
        (or (known-type m key) (register-type! m key (wasm-id key) `(type ,(wasm-id key) (struct (field (mut ,content))))))))

    ;; A closure is a struct whose first field is its code. Each lambda with
    ;; captured variables extends the base struct with their fields.
    (define (signature-key params result)
      (string-append (keys->string (map rep-key params)) "->" (rep-key result)))

    (define (closure-type m params result)
      (let* ((signature (signature-key params result)) (key (string-append "clo." signature)))
        (or (known-type m key)
            (let ((closure (wasm-id key)) (code (wasm-id "fn." signature)))
              (hash-table-set! (Module-type-ids m) key closure)
              (register-type! m (string-append "fn." signature) code
                              `(type ,code (func (param (ref ,closure)) ,@(map (lambda (p) `(param ,p)) params) (result ,result))))
              (register-type! m key closure `(type ,closure (sub (struct (field (ref ,code))))))))))

    ;; Every closure subtype shares its base's code type.
    (define (code-type m closure)
      (let ((name (symbol->string closure)))
        (string->symbol (string-append "$fn." (substring name 5 (string-length name))))))

    (define (function-signature m type)
      (match type
        ((TFun params result _) (values (map (lambda (p) (rep m p)) params) (rep m result)))))

    (define (data-type-of m name)
      (program-type (program-of m) name))

    (define (tag-enum? m name)
      (let ((data (data-type-of m name)))
        (and (DataType-enum? data) (every (lambda (case) (null? (Case-fields case))) (DataType-cases data)))))

    (define (case-fields m type case)
      (match type
        ((TCon name args)
         (let ((substitution (map cons (DataType-params (data-type-of m name)) args)))
           (map (lambda (field) (rep m (substitute substitution (Field-type field)))) (Case-fields case))))))

    ;; A struct is one GC struct. An enum is a base struct holding the tag,
    ;; with one final subtype per case; the base is registered first because a
    ;; supertype must precede its subtypes.
    (define (data-type m type)
      (let ((key (type-key type)))
        (or (known-type m key)
            (let ((id (wasm-id key)) (data (data-type-of m (TCon-name type))))
              (hash-table-set! (Module-type-ids m) key id)
              (if (DataType-enum? data)
                  (begin (push! (Module-types m) `(type ,id (sub (struct (field i32)))))
                         (for-each (lambda (case) (case-type m type case)) (DataType-cases data)))
                  (let ((fields (case-fields m type (car (DataType-cases data)))))
                    (push! (Module-types m) `(type ,id (struct ,@(map (lambda (f) `(field ,f)) fields))))))
              id))))

    (define (case-type m type case)
      (let ((key (string-append (type-key type) "." (short-name (Case-name case)))))
        (or (known-type m key)
            (let* ((base (data-type m type)) (id (wasm-id key)) (fields (case-fields m type case)))
              (register-type! m key id `(type ,id (sub final ,base (struct (field i32) ,@(map (lambda (f) `(field ,f)) fields)))))))))

    (define (TCon-name type)
      (match type ((TCon name _) name)))

    (define (default-value rep)
      (case rep
        ((i32) '(i32.const 0))
        ((i64) '(i64.const 0))
        ((f32) '(f32.const 0))
        ((f64) '(f64.const 0))
        (else `(ref.null ,(cadr rep)))))

    (define (nullable rep)
      (if (symbol? rep) rep `(ref null ,(cadr rep))))

    ;; ---- Functions ----

    ;; `access` maps each visible local name to the instruction that reads it,
    ;; and `reps` to its representation.
    (struct Fn
      ((module Module)
       (locals (Ref (List Datum)))
       (access HashTable)
       (reps HashTable)))

    (define (new-fn m)
      (Fn m (ref '()) (make-hash-table eq?) (make-hash-table eq?)))

    (define (bind-local! fn name read rep)
      (hash-table-set! (Fn-access fn) name read)
      (hash-table-set! (Fn-reps fn) name rep))

    (define (declare-local! fn name rep)
      (let ((id (wasm-id name)))
        (push! (Fn-locals fn) `(local ,id ,rep))
        (bind-local! fn name `(local.get ,id) rep)
        id))

    (define (declare-temp! fn rep)
      (let ((id (fresh-id (Fn-module fn) "tmp")))
        (push! (Fn-locals fn) `(local ,id ,rep))
        id))

    (define (local-access fn name)
      (hash-table-ref/default (Fn-access fn) name #f))

    (define (fn-rep fn type)
      (rep (Fn-module fn) type))

    ;; A function definition: parameters, declared locals, then the body.
    (define (function-datum fn id params result body)
      `(func ,id ,@params (result ,result) ,@(reverse (ref-get (Fn-locals fn))) ,@body))

    (define (emit-function! m name function)
      (match (Expr-term function)
        ((Lambda params body)
         (let ((fn (new-fn m)))
           (let-values (((param-reps result) (function-signature m (Expr-type function))))
             (let ((param-decls (map (lambda (param rep) `(param ,(wasm-id param) ,rep)) params param-reps)))
               (for-each (lambda (param rep) (bind-local! fn param `(local.get ,(wasm-id param)) rep)) params param-reps)
               (let ((code (emit fn body #t)))
                 (push! (Module-functions m) (function-datum fn (wasm-id name) param-decls result code)))))))))

    ;; ---- Expressions ----

    ;; Returns a list of instructions that leave one value on the stack.
    (define (emit fn expr tail?)
      (let ((type (Expr-type expr)))
        (match (Expr-term expr)
          ((Lit value) (list (literal fn value type)))
          ((Var name _ _) (list (variable fn name type)))
          ((Lambda params body) (list (closure fn expr #f)))
          ((App callee args) (emit-call fn expr callee args tail?))
          ((If test then else)
           `((if (result ,(fn-rep fn type)) ,(emit1 fn test)
                 (then ,@(emit fn then tail?)) (else ,@(emit fn else tail?)))))
          ((Let name value body) (emit-let fn name value body tail?))
          ((Seq first rest) (cons `(drop ,(emit1 fn first)) (emit fn rest tail?)))
          ((Match scrutinee clauses) (emit-match fn expr scrutinee clauses tail?))
          ((Handle effect implementations body) (emit-handle fn expr effect implementations body)))))

    ;; One instruction, wrapping a sequence in a block when needed.
    (define (emit1 fn expr)
      (emit1-tail fn expr #f))

    (define (emit1-tail fn expr tail?)
      (let ((code (emit fn expr tail?)))
        (if (and (pair? code) (null? (cdr code)))
            (car code)
            `(block (result ,(fn-rep fn (Expr-type expr))) ,@code))))

    (define (literal fn value type)
      (cond ((boolean? value) `(i32.const ,(if value 1 0)))
            ((char? value) `(i32.const ,(char->integer value)))
            ((string? value) (string-literal (Fn-module fn) value))
            ((eq? value 'unit) '(i32.const 0))
            (else (let ((r (fn-rep fn type)))
                    `(,(symbol-append r '.const) ,(if (memq r '(i32 i64)) value (float-text value)))))))

    (define (symbol-append a b)
      (string->symbol (string-append (symbol->string a) (symbol->string b))))

    (define (float-text value)
      (let ((value (inexact value)))
        (cond ((nan? value) 'nan)
              ((infinite? value) (if (> value 0) 'inf '-inf))
              (else value))))

    ;; String literals are immutable globals, built once.
    (define (string-literal m text)
      (memoize! m (cons 'string text)
                (lambda ()
                  (let ((id (fresh-id m "string")) (array (array-type m 'i32)))
                    (push! (Module-globals m)
                           `(global ,id (ref ,array)
                                    (array.new_fixed ,array ,(string-length text)
                                                     ,@(map (lambda (c) `(i32.const ,(char->integer c))) (string->list text)))))
                    `(global.get ,id)))))

    (define (emit-let fn name value body tail?)
      (let* ((recursive? (match (Expr-term value) ((Lambda _ _) (memq name (references value))) (_ #f)))
             (code (if recursive? (closure fn value name) (emit1 fn value)))
             (id (declare-local! fn name (fn-rep fn (Expr-type value)))))
        (cons `(local.set ,id ,code) (emit fn body tail?))))

    (define (references expr)
      (match (Expr-term expr)
        ((Lit _) '())
        ((Var name _ _) (list name))
        ((Lambda _ body) (references body))
        ((App callee args) (append-map references (cons callee args)))
        ((If test then else) (append-map references (list test then else)))
        ((Let _ value body) (append (references value) (references body)))
        ((Seq first rest) (append (references first) (references rest)))
        ((Match scrutinee clauses) (append (references scrutinee) (append-map (lambda (c) (references (Clause-body c))) clauses)))
        ((Handle _ implementations body) (append (append-map (lambda (e) (references (cdr e))) implementations) (references body)))))

    ;; ---- Variables ----

    ;; A global function or operation used as a value becomes a closure.
    (define (variable fn name type)
      (or (local-access fn name)
          (let* ((m (Fn-module fn)) (definition (hash-table-ref/default (Module-definitions m) name #f)))
            (cond ((and definition (lambda-expr? definition)) (function-value m name type))
                  (definition (let ((r (fn-rep fn type)))
                                (if (symbol? r) `(global.get ,(wasm-id name)) `(ref.as_non_null (global.get ,(wasm-id name))))))
                  (else (match (program-value (program-of m) name)
                          ((Constructor case _) (if (null? (Case-fields case)) (construct fn case type '()) (function-value m name type)))
                          (#f (error "internal: unknown variable" name))
                          (_ (function-value m name type))))))))

    (define (lambda-expr? expr)
      (match (Expr-term expr)
        ((Lambda _ _) #t)
        (_ #f)))

    ;; An immutable global closure whose code calls `name` with its arguments.
    (define (function-value m name type)
      (memoize! m (list 'closure name (type-key type))
                (lambda ()
                  (match type
                    ((TFun params result row)
                     (let* ((names (map (lambda (index) (string->symbol (string-append "argument." (number->string index)))) (iota (length params))))
                            (call (Expr (App (Expr (Var name '() '()) type #f)
                                             (map (lambda (name param) (Expr (Var name '() '()) param #f)) names params))
                                        result #f)))
                       (closure-value m (Expr (Lambda names call) type #f))))))))

    ;; ---- Closures ----

    ;; A lambda becomes a function taking its closure first. Captured
    ;; variables are copied into the closure and loaded on entry; `self` names
    ;; a recursive local function, which reads as the closure itself.
    (define (closure fn function self)
      (let* ((m (Fn-module fn))
             (captured (filter (lambda (name) (and (not (eq? name self)) (local-access fn name)))
                               (delete-duplicates (references function) eq?))))
        (if (null? captured)
            (closure-value m function self)
            (closure-with-captures fn function self captured))))

    (define (closure-value m function . self)
      (let-values (((params result) (function-signature m (Expr-type function))))
        (let* ((base (closure-type m params result)) (code (lambda-function! m function (if (pair? self) (car self) #f) '() base))
               (id (fresh-id m "closure")))
          (push! (Module-globals m) `(global ,id (ref ,base) (struct.new ,base (ref.func ,code))))
          `(global.get ,id))))

    (define (closure-with-captures fn function self captured)
      (let ((m (Fn-module fn)))
        (let-values (((params result) (function-signature m (Expr-type function))))
          (let* ((base (closure-type m params result)) (id (fresh-id m "closure"))
                 (captured-reps (map (lambda (name) (capture-rep fn name)) captured)))
            (register-type! m (symbol->string id) id
                            `(type ,id (sub final ,base (struct (field (ref ,(code-type m base))) ,@(map (lambda (r) `(field ,r)) captured-reps)))))
            (let ((code (lambda-function! m function self (map cons captured captured-reps) id)))
              `(struct.new ,id (ref.func ,code) ,@(map (lambda (name) (local-access fn name)) captured)))))))

    (define (capture-rep fn name)
      (hash-table-ref (Fn-reps fn) name))

    (define (lambda-function! m function self captured closure)
      (match (Expr-term function)
        ((Lambda params body)
         (let-values (((param-reps result) (function-signature m (Expr-type function))))
           (let* ((fn (new-fn m)) (id (fresh-id m "lambda")) (base (closure-type m param-reps result)))
             (push! (Module-declared m) id)
             (when self (bind-local! fn self '(local.get $closure) (ref-of base)))
             (for-each (lambda (param rep) (bind-local! fn param `(local.get ,(wasm-id param)) rep)) params param-reps)
             (let* ((loads (map (lambda (entry index)
                                  `(local.set ,(declare-local! fn (car entry) (cdr entry))
                                              (struct.get ,closure ,(+ index 1) (ref.cast (ref ,closure) (local.get $closure)))))
                                captured (iota (length captured))))
                    (code (emit fn body #t)))
               ;; The function's type must be the closure's code type itself,
               ;; not a structurally equal one, for `ref.func` to fit the field.
               (push! (Module-functions m)
                      (function-datum fn id (cons* `(type ,(code-type m base)) `(param $closure (ref ,base))
                                                   (map (lambda (p r) `(param ,(wasm-id p) ,r)) params param-reps))
                                      result (append loads code)))
               id))))))

    ;; ---- Calls ----

    (define (emit-call fn expr callee args tail?)
      (let ((m (Fn-module fn)))
        (match (Expr-term callee)
          ((Var name _ _)
           (cond ((local-access fn name) (closure-call fn expr callee args tail?))
                 ((hash-table-ref/default (Module-definitions m) name #f)
                  => (lambda (definition)
                       (if (lambda-expr? definition)
                           `((,(if tail? 'return_call 'call) ,(wasm-id name) ,@(map (lambda (arg) (emit1 fn arg)) args)))
                           (closure-call fn expr callee args tail?))))
                 (else (builtin-call fn expr name args))))
          (_ (closure-call fn expr callee args tail?)))))

    (define (builtin-call fn expr name args)
      (match (program-value (program-of (Fn-module fn)) name)
        ((Constructor case _) (list (construct fn case (Expr-type expr) (map (lambda (arg) (emit1 fn arg)) args))))
        ((Accessor case index _) (list (field-access fn case index (car args))))
        ((Replacer case index _) (list (replace-field fn case index (car args) (cadr args))))
        ((Primitive _) (emit-primitive fn name args (Expr-type expr)))
        ((Operation effect _) (perform fn effect name args (Expr-type expr)))
        ((Foreign module symbol scheme) (foreign-call fn name module symbol (Scheme-type scheme) args))))

    (define (closure-call fn expr callee args tail?)
      (let-values (((params result) (function-signature (Fn-module fn) (Expr-type callee))))
        (let* ((m (Fn-module fn)) (base (closure-type m params result)) (value (emit1 fn callee))
               (temp (and (not (memq (car value) '(local.get global.get))) (declare-temp! fn (ref-of base))))
               (read (if temp `(local.get ,temp) value)))
          `(,@(if temp `((local.set ,temp ,value)) '())
            (,(if tail? 'return_call_ref 'call_ref) ,(code-type m base) ,read ,@(map (lambda (arg) (emit1 fn arg)) args)
             (struct.get ,base 0 ,read))))))

    (define (data-case-type m type case)
      (case-type m type case))

    ;; Tag enums are i32 constants; nullary cases of other enums are shared
    ;; immutable globals.
    (define (construct fn case type args)
      (let* ((m (Fn-module fn)) (name (Case-type case)))
        (cond ((tag-enum? m name) `(i32.const ,(Case-tag case)))
              ((not (DataType-enum? (data-type-of m name))) `(struct.new ,(data-type m type) ,@args))
              ((null? args) (singleton m type case))
              (else `(struct.new ,(case-type m type case) (i32.const ,(Case-tag case)) ,@args)))))

    (define (singleton m type case)
      (memoize! m (list 'singleton (type-key type) (Case-name case))
                (lambda ()
                  (let ((id (fresh-id m "value")) (case-id (case-type m type case)))
                    (push! (Module-globals m) `(global ,id (ref ,case-id) (struct.new ,case-id (i32.const ,(Case-tag case)))))
                    `(global.get ,id)))))

    (define (field-access fn case index value)
      (let* ((m (Fn-module fn)) (type (Expr-type value)))
        (if (DataType-enum? (data-type-of m (Case-type case)))
            (let ((case-id (case-type m type case)))
              `(struct.get ,case-id ,(+ index 1) (ref.cast (ref ,case-id) ,(emit1 fn value))))
            `(struct.get ,(data-type m type) ,index ,(emit1 fn value)))))

    (define (replace-field fn case index value replacement)
      (let* ((m (Fn-module fn)) (id (data-type m (Expr-type value)))
             (temp (declare-temp! fn (ref-of id))))
        `(block (result (ref ,id))
                (local.set ,temp ,(emit1 fn value))
                (struct.new ,id ,@(map (lambda (i) (if (= i index) (emit1 fn replacement) `(struct.get ,id ,i (local.get ,temp))))
                                       (iota (length (Case-fields case))))))))

    (define (foreign-call fn name module symbol type args)
      (let-values (((params result) (function-signature (Fn-module fn) type)))
        (let ((id (import! (Fn-module fn) module symbol params (if (unit-type? type) #f result))))
          (if (unit-type? type)
              `((call ,id ,@(map (lambda (arg) (emit1 fn arg)) args)) (i32.const 0))
              `((call ,id ,@(map (lambda (arg) (emit1 fn arg)) args)))))))

    (define (unit-type? function-type)
      (match function-type
        ((TFun _ (TCon 'Unit '()) _) #t)
        (_ #f)))

    (define (import! m module symbol params result)
      (memoize! m (list 'import module symbol)
                (lambda ()
                  (let ((id (wasm-id "import." symbol)))
                    (push! (Module-imports m)
                           `(import ,module ,symbol (func ,id ,@(map (lambda (p) `(param ,p)) params) ,@(if result `((result ,result)) '()))))
                    id))))

    ;; ---- Pattern matching ----

    ;; Clauses are tried in order. Each clause is a block that its failing
    ;; tests branch out of; a matching clause branches to `done` with its value.
    (define (emit-match fn expr scrutinee clauses tail?)
      (let* ((m (Fn-module fn)) (value (declare-temp! fn (fn-rep fn (Expr-type scrutinee))))
             (done (fresh-id m "match")))
        `((local.set ,value ,(emit1 fn scrutinee))
          (block ,done (result ,(fn-rep fn (Expr-type expr)))
                 ,@(map (lambda (clause)
                          ;; The pattern declares the locals its body reads.
                          (let* ((next (fresh-id m "clause"))
                                 (tests (pattern-code fn (Clause-pattern clause) `(local.get ,value) next))
                                 (body (emit1-tail fn (Clause-body clause) tail?)))
                            `(block ,next ,@tests (br ,done ,body))))
                        clauses)
                 (unreachable)))))

    (define (pattern-code fn pattern value fail)
      (match pattern
        ((PWild _) '())
        ((PVar name type) `((local.set ,(declare-local! fn name (fn-rep fn type)) ,value)))
        ((PLit literal-value type) `((br_if ,fail ,(literal-differs fn literal-value type value))))
        ((PCon constructor args type) (constructor-pattern-code fn constructor args type value fail))))

    (define (literal-differs fn literal-value type scrutinee)
      (let ((r (fn-rep fn type)) (constant (literal fn literal-value type)))
        (if (symbol? r)
            `(,(symbol-append r '.ne) ,scrutinee ,constant)
            `(i32.eqz (call ,(string-equal-helper (Fn-module fn)) ,scrutinee ,constant)))))

    (define (constructor-pattern-code fn constructor args type value fail)
      (let* ((m (Fn-module fn)) (case (match (program-value (program-of m) constructor) ((Constructor case _) case)))
             (name (Case-type case)))
        (cond ((tag-enum? m name) `((br_if ,fail (i32.ne ,value (i32.const ,(Case-tag case))))))
              ((not (DataType-enum? (data-type-of m name)))
               (fields-code fn (data-type m type) 0 args (case-field-types m type case) value fail))
              (else
               (let ((base (data-type m type)) (case-id (case-type m type case)))
                 (cons `(br_if ,fail (i32.ne (struct.get ,base 0 ,value) (i32.const ,(Case-tag case))))
                       (if (every wild? args)
                           '()
                           (let ((cast (declare-temp! fn (ref-of case-id))))
                             (cons `(local.set ,cast (ref.cast (ref ,case-id) ,value))
                                   (fields-code fn case-id 1 args (case-field-types m type case) `(local.get ,cast) fail))))))))))

    (define (case-field-types m type case)
      (match type
        ((TCon name args)
         (let ((substitution (map cons (DataType-params (data-type-of m name)) args)))
           (map (lambda (field) (substitute substitution (Field-type field))) (Case-fields case))))))

    (define (wild? pattern)
      (match pattern
        ((PWild _) #t)
        (_ #f)))

    ;; Sub-patterns read their field once, into a temporary unless the
    ;; pattern is a variable or a wildcard.
    (define (fields-code fn id offset args types value fail)
      (append-map (lambda (arg type index)
                    (let ((field `(struct.get ,id ,(+ index offset) ,value)))
                      (match arg
                        ((PWild _) '())
                        ((PVar _ _) (pattern-code fn arg field fail))
                        (_ (let ((temp (declare-temp! fn (fn-rep fn type))))
                             (cons `(local.set ,temp ,field) (pattern-code fn arg `(local.get ,temp) fail)))))))
                  args types (iota (length args))))

    ;; ---- Effect handlers ----

    ;; Each effect has a global stack of handlers, linked through `outer`. An
    ;; operation runs its implementation with the stack popped, so the
    ;; implementation's own operations go to the enclosing handler; an empty
    ;; stack means the host default.
    (define (handler-type m effect)
      (let ((key (string-append "handler." (symbol->string effect))))
        (or (known-type m key)
            (let ((id (wasm-id key)))
              (hash-table-set! (Module-type-ids m) key id)
              (let ((fields (map (lambda (operation) `(field ,(rep m (operation-type m operation))))
                                 (Effect-operations (program-effect (program-of m) effect)))))
                (push! (Module-types m) `(type ,id (struct ,@fields
                                                     (field (ref null ,id)))))
                (push! (Module-globals m) `(global ,(wasm-id key ".current") (mut (ref null ,id)) (ref.null ,id)))
                id)))))

    (define (operation-type m operation)
      (match (program-value (program-of m) operation)
        ((Operation _ (Scheme _ _ (TFun params result _))) (TFun params result empty-row))))

    (define (emit-handle fn expr effect implementations body)
      (let* ((m (Fn-module fn)) (id (handler-type m effect))
             (current (wasm-id "handler." (symbol->string effect) ".current"))
             (saved (declare-temp! fn `(ref null ,id))) (result (declare-temp! fn (fn-rep fn (Expr-type expr)))))
        `((local.set ,saved (global.get ,current))
          (global.set ,current
                      (struct.new ,id ,@(map (lambda (operation) (emit1 fn (cdr (assq operation implementations))))
                                             (Effect-operations (program-effect (program-of m) effect)))
                                  (local.get ,saved)))
          (local.set ,result ,(emit1 fn body))
          (global.set ,current (local.get ,saved))
          (local.get ,result))))

    (define (perform fn effect operation args type)
      (let* ((m (Fn-module fn)) (id (handler-type m effect)) (info (program-effect (program-of m) effect))
             (current (wasm-id "handler." (symbol->string effect) ".current"))
             (index (list-index (lambda (o) (eq? o operation)) (Effect-operations info)))
             (op-type (operation-type m operation))
             (temps (map (lambda (arg) (declare-temp! fn (fn-rep fn (Expr-type arg)))) args))
             (handler (declare-temp! fn `(ref null ,id))) (result-rep (fn-rep fn type)) (result (declare-temp! fn result-rep)))
        (let-values (((params result-type) (function-signature m op-type)))
          (let* ((base (closure-type m params result-type)) (implementation (declare-temp! fn (ref-of base))))
            `(,@(map (lambda (temp arg) `(local.set ,temp ,(emit1 fn arg))) temps args)
              (local.set ,handler (global.get ,current))
              (if (result ,result-rep) (ref.is_null (local.get ,handler))
                  (then ,@(host-default fn info operation op-type temps))
                  (else (local.set ,implementation (struct.get ,id ,index (local.get ,handler)))
                        (global.set ,current (struct.get ,id ,(length (Effect-operations info)) (local.get ,handler)))
                        (local.set ,result (call_ref ,(code-type m base) (local.get ,implementation)
                                                     ,@(map (lambda (temp) `(local.get ,temp)) temps)
                                                     (struct.get ,base 0 (local.get ,implementation))))
                        (global.set ,current (local.get ,handler))
                        (local.get ,result))))))))

    (define (host-default fn info operation type temps)
      (let ((import
             (assq operation (Effect-host info))))
        (if import
            (let-values (((params result) (function-signature (Fn-module fn) type)))
              (let* ((id (import! (Fn-module fn) (cadr import) (cddr import) params (if (unit-type? type) #f result)))
                     (call `(call ,id ,@(map (lambda (temp) `(local.get ,temp)) temps))))
                (if (unit-type? type) (list call '(i32.const 0)) (list call))))
            `((call ,(panic-helper (Fn-module fn)) ,(string-literal (Fn-module fn) (string-append "unhandled effect operation " (short-name operation))))
              (unreachable)))))

    ;; ---- Primitives ----

    ;; Primitives with a single Wasm instruction.
    (define instruction-primitives
      '((i32-add . i32.add) (i32-sub . i32.sub) (i32-mul . i32.mul) (i32-quotient . i32.div_s)
        (i32-remainder . i32.rem_s) (i32-and . i32.and) (i32-or . i32.or) (i32-xor . i32.xor)
        (i32-shift-left . i32.shl) (i32-shift-right . i32.shr_s) (i32-shift-right/logical . i32.shr_u)
        (i32-eq . i32.eq) (i32-lt . i32.lt_s) (i32-le . i32.le_s) (i32-gt . i32.gt_s) (i32-ge . i32.ge_s)
        (i64-add . i64.add) (i64-sub . i64.sub) (i64-mul . i64.mul) (i64-quotient . i64.div_s)
        (i64-remainder . i64.rem_s) (i64-and . i64.and) (i64-or . i64.or) (i64-xor . i64.xor)
        (i64-shift-left . i64.shl) (i64-shift-right . i64.shr_s) (i64-shift-right/logical . i64.shr_u)
        (i64-eq . i64.eq) (i64-lt . i64.lt_s) (i64-le . i64.le_s) (i64-gt . i64.gt_s) (i64-ge . i64.ge_s)
        (f32-add . f32.add) (f32-sub . f32.sub) (f32-mul . f32.mul) (f32-div . f32.div)
        (f32-min . f32.min) (f32-max . f32.max) (f32-eq . f32.eq) (f32-lt . f32.lt) (f32-le . f32.le)
        (f32-gt . f32.gt) (f32-ge . f32.ge) (f32-sqrt . f32.sqrt) (f32-abs . f32.abs) (f32-negate . f32.neg)
        (f32-floor . f32.floor) (f32-ceiling . f32.ceil) (f32-truncate . f32.trunc) (f32-round . f32.nearest)
        (f64-add . f64.add) (f64-sub . f64.sub) (f64-mul . f64.mul) (f64-div . f64.div)
        (f64-min . f64.min) (f64-max . f64.max) (f64-eq . f64.eq) (f64-lt . f64.lt) (f64-le . f64.le)
        (f64-gt . f64.gt) (f64-ge . f64.ge) (f64-sqrt . f64.sqrt) (f64-abs . f64.abs) (f64-negate . f64.neg)
        (f64-floor . f64.floor) (f64-ceiling . f64.ceil) (f64-truncate . f64.trunc) (f64-round . f64.nearest)
        (i32->i64 . i64.extend_i32_s) (i64->i32 . i32.wrap_i64) (i64->f64 . f64.convert_i64_s)
        (f64->i64 . i64.trunc_sat_f64_s) (i32->f64 . f64.convert_i32_s) (f64->i32 . i32.trunc_sat_f64_s)
        (i32->f32 . f32.convert_i32_s) (f32->i32 . i32.trunc_sat_f32_s) (i64->f32 . f32.convert_i64_s)
        (f32->i64 . i64.trunc_sat_f32_s) (f32->f64 . f64.promote_f32) (f64->f32 . f32.demote_f64)
        (f32->bits . i32.reinterpret_f32) (bits->f32 . f32.reinterpret_i32)
        (f64->bits . i64.reinterpret_f64) (bits->f64 . f64.reinterpret_i64)))

    (define (emit-primitive fn name args type)
      (let* ((m (Fn-module fn)) (operation (string->symbol (substring (symbol->string name) 5 (string-length (symbol->string name)))))
             (code (map (lambda (arg) (emit1 fn arg)) args))
             (arg-types (map Expr-type args))
             (index (lambda (i) `(i32.wrap_i64 ,i))))
        (cond ((assq operation instruction-primitives) => (lambda (entry) `((,(cdr entry) ,@code))))
              (else
               (case operation
                 ((unit) '((i32.const 0)))
                 ((unsafe-total) (closure-call fn #f (car args) '() #f))
                 ((panic) `((call ,(panic-helper m) ,@code) (unreachable)))
                 ;; Strings and character vectors share one representation.
                 ((bool->i32 char->i32 i32->char string->vector vector->string u8->i32) code)
                 ((i32->u8) `((i32.and ,(car code) (i32.const 255))))
                 ((i32->bool) `((i32.ne ,(car code) (i32.const 0))))
                 ((string-length vector-length array-length) `((i64.extend_i32_u (array.len ,(car code)))))
                 ((string-ref vector-ref array-ref)
                  (let ((array (sequence-type m (car arg-types))))
                    `((,(array-get array) ,array ,(car code) ,(index (cadr code))))))
                 ((array-set!)
                  `((array.set ,(sequence-type m (car arg-types)) ,(car code) ,(index (cadr code)) ,(caddr code)) (i32.const 0)))
                 ((make-string make-vector make-array)
                  `((array.new ,(sequence-type m type) ,(cadr code) ,(index (car code)))))
                 ((string-append vector-append) `((call ,(append-helper m (sequence-type m type)) ,@code)))
                 ((substring subvector) `((call ,(slice-helper m (sequence-type m type)) ,@code)))
                 ((vector-set) `((call ,(set-helper m (sequence-type m type) (fn-rep fn (caddr arg-types))) ,@code)))
                 ((array->vector vector->array) `((call ,(copy-helper m (sequence-type m type)) ,@code)))
                 ((array-copy! vector-copy!)
                  (let ((id (sequence-type m (car arg-types))))
                    `((array.copy ,id ,id ,(car code) ,(index (cadr code)) ,(caddr code) ,(index (cadddr code))
                                  ,(index (list-ref code 4)))
                      (i32.const 0))))
                 ((string=?) `((call ,(string-equal-helper m) ,@code)))
                 ((string-compare) `((call ,(string-compare-helper m) ,@code)))
                 ((vector-generate string-generate)
                  `((call ,(generate-helper m (sequence-type m type) (cadr arg-types)) ,@code)))
                 ((ref) `((struct.new ,(cell-type m (fn-rep fn (car arg-types))) ,@code)))
                 ((ref-get) `((struct.get ,(cell-type m (fn-rep fn type)) 0 ,@code)))
                 ((ref-set!) `((struct.set ,(cell-type m (fn-rep fn (cadr arg-types))) 0 ,@code) (i32.const 0)))
                 (else (error "internal: unknown primitive" name)))))))

    (define (sequence-type m type)
      (cadr (rep m type)))

    ;; ---- Runtime helpers ----

    ;; Helpers are written once per array type. A new array needs an
    ;; initial element, so empty results come from `array.new_fixed`.
    (define (helper! m key make)
      (memoize! m key
                (lambda ()
                  (let ((id (fresh-id m (car key))))
                    (push! (Module-functions m) (make id))
                    id))))

    (define (append-helper m array)
      (helper! m (list "append" array)
               (lambda (id)
                 `(func ,id (param $a (ref ,array)) (param $b (ref ,array)) (result (ref ,array))
                        (local $result (ref ,array))
                        (if (i32.eqz (array.len (local.get $a))) (then (return (local.get $b))))
                        (if (i32.eqz (array.len (local.get $b))) (then (return (local.get $a))))
                        (local.set $result (array.new ,array (,(array-get array) ,array (local.get $a) (i32.const 0))
                                                      (i32.add (array.len (local.get $a)) (array.len (local.get $b)))))
                        (array.copy ,array ,array (local.get $result) (array.len (local.get $a)) (local.get $b) (i32.const 0)
                                    (array.len (local.get $b)))
                        (array.copy ,array ,array (local.get $result) (i32.const 0) (local.get $a) (i32.const 0)
                                    (array.len (local.get $a)))
                        (local.get $result)))))

    (define (slice-helper m array)
      (helper! m (list "slice" array)
               (lambda (id)
                 `(func ,id (param $a (ref ,array)) (param $start i64) (param $end i64) (result (ref ,array))
                        (local $result (ref ,array)) (local $length i32)
                        (local.set $length (i32.wrap_i64 (i64.sub (local.get $end) (local.get $start))))
                        (if (i32.eqz (local.get $length)) (then (return (array.new_fixed ,array 0))))
                        (local.set $result (array.new ,array (,(array-get array) ,array (local.get $a) (i32.wrap_i64 (local.get $start)))
                                                      (local.get $length)))
                        (array.copy ,array ,array (local.get $result) (i32.const 0) (local.get $a) (i32.wrap_i64 (local.get $start))
                                    (local.get $length))
                        (local.get $result)))))

    (define (copy-helper m array)
      (helper! m (list "copy" array)
               (lambda (id)
                 `(func ,id (param $a (ref ,array)) (result (ref ,array))
                        (local $result (ref ,array))
                        (if (i32.eqz (array.len (local.get $a))) (then (return (array.new_fixed ,array 0))))
                        (local.set $result (array.new ,array (,(array-get array) ,array (local.get $a) (i32.const 0)) (array.len (local.get $a))))
                        (array.copy ,array ,array (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
                        (local.get $result)))))

    (define (set-helper m array element)
      (helper! m (list "set" array)
               (lambda (id)
                 `(func ,id (param $a (ref ,array)) (param $index i64) (param $value ,element) (result (ref ,array))
                        (local $result (ref ,array))
                        (local.set $result (array.new ,array (local.get $value) (array.len (local.get $a))))
                        (array.copy ,array ,array (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
                        (array.set ,array (local.get $result) (i32.wrap_i64 (local.get $index)) (local.get $value))
                        (local.get $result)))))

    (define (generate-helper m array function-type)
      (let-values (((params result) (function-signature m function-type)))
        (let* ((base (closure-type m params result)) (code (code-type m base))
               (call (lambda (index) `(call_ref ,code (local.get $f) ,index (struct.get ,base 0 (local.get $f))))))
          (helper! m (list "generate" array base)
                   (lambda (id)
                     `(func ,id (param $count i64) (param $f (ref ,base)) (result (ref ,array))
                            (local $result (ref ,array)) (local $length i32) (local $index i32)
                            (local.set $length (i32.wrap_i64 (local.get $count)))
                            (if (i32.eqz (local.get $length)) (then (return (array.new_fixed ,array 0))))
                            (local.set $result (array.new ,array ,(call '(i64.const 0)) (local.get $length)))
                            (local.set $index (i32.const 1))
                            (block $done
                                   (loop $next
                                         (br_if $done (i32.ge_u (local.get $index) (local.get $length)))
                                         (array.set ,array (local.get $result) (local.get $index) ,(call '(i64.extend_i32_u (local.get $index))))
                                         (local.set $index (i32.add (local.get $index) (i32.const 1)))
                                         (br $next)))
                            (local.get $result)))))))

    (define (string-equal-helper m)
      (let ((array (array-type m 'i32)))
        (helper! m (list "string-equal")
                 (lambda (id)
                   `(func ,id (param $a (ref ,array)) (param $b (ref ,array)) (result i32)
                          (i32.eqz (call ,(string-compare-helper m) (local.get $a) (local.get $b))))))))

    ;; Lexicographic comparison by Unicode scalar: -1, 0 or 1.
    (define (string-compare-helper m)
      (let ((array (array-type m 'i32)))
        (helper! m (list "string-compare")
                 (lambda (id)
                   `(func ,id (param $a (ref ,array)) (param $b (ref ,array)) (result i32)
                          (local $index i32) (local $x i32) (local $y i32)
                          (block $done
                                 (loop $next
                                       (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $a))))
                                       (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $b))))
                                       (local.set $x (array.get ,array (local.get $a) (local.get $index)))
                                       (local.set $y (array.get ,array (local.get $b) (local.get $index)))
                                       (if (i32.lt_u (local.get $x) (local.get $y)) (then (return (i32.const -1))))
                                       (if (i32.gt_u (local.get $x) (local.get $y)) (then (return (i32.const 1))))
                                       (local.set $index (i32.add (local.get $index) (i32.const 1)))
                                       (br $next)))
                          (i32.sub (i32.gt_u (array.len (local.get $a)) (array.len (local.get $b)))
                                   (i32.lt_u (array.len (local.get $a)) (array.len (local.get $b)))))))))

    ;; Sends the message to the runtime one scalar at a time, then stops.
    (define (panic-helper m)
      (let ((array (array-type m 'i32))
            (character (import! m "snail.library" "snail:panic/character" '(i32) #f))
            (raise (import! m "snail.library" "snail:panic/raise" '() #f)))
        (helper! m (list "panic")
                 (lambda (id)
                   `(func ,id (param $message (ref ,array))
                          (local $index i32)
                          (block $done
                                 (loop $next
                                       (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $message))))
                                       (call ,character (array.get ,array (local.get $message) (local.get $index)))
                                       (local.set $index (i32.add (local.get $index) (i32.const 1)))
                                       (br $next)))
                          (call ,raise)
                          (unreachable))))))

    ;; ---- Modules ----

    ;; Functions become Wasm functions and other definitions become globals.
    ;; `main` initializes the globals and runs the statements in program order.
    (define (emit-module mono)
      (let* ((m (Module (Mono-program mono) (make-hash-table eq?) (make-hash-table equal?) (ref '()) (ref '()) (ref '())
                        (ref '()) (ref '()) (ref '()) (make-hash-table equal?) (ref 0)))
             (items (Mono-items mono)))
        (for-each (lambda (item) (match item ((Define name value) (hash-table-set! (Module-definitions m) name value)) (_ #f))) items)
        (for-each (lambda (item)
                    (match item
                      ((Define name value) (when (lambda-expr? value) (emit-function! m name value)))
                      (_ #f)))
                  items)
        (emit-main! m items)
        `(module
          ,@(if (null? (ref-get (Module-types m))) '() `((rec ,@(reverse (ref-get (Module-types m))))))
          ,@(reverse (ref-get (Module-imports m)))
          ,@(reverse (ref-get (Module-globals m)))
          ,@(if (null? (ref-get (Module-declared m))) '() `((elem declare func ,@(reverse (ref-get (Module-declared m))))))
          ,@(reverse (ref-get (Module-exports m)))
          ,@(reverse (ref-get (Module-functions m))))))

    (define (emit-main! m items)
      (let* ((fn (new-fn m))
             (code (append-map
                    (lambda (item)
                      (match item
                        ((Define name value)
                         (if (lambda-expr? value)
                             '()
                             (let ((r (rep m (Expr-type value))))
                               (push! (Module-globals m) `(global ,(wasm-id name) (mut ,(nullable r)) ,(default-value r)))
                               `((global.set ,(wasm-id name) ,(emit1 fn value))))))
                        ((Do expr) `((drop ,(emit1 fn expr))))
                        ((Expose name symbol loc)
                         (unless (lambda-expr? (hash-table-ref (Module-definitions m) name))
                           (compile-error loc "an exposed function must be defined with lambda"))
                         (push! (Module-exports m) `(export ,symbol (func ,(wasm-id name))))
                         '())))
                    items)))
        (push! (Module-functions m)
               `(func $main (export "main") (result i32) ,@(reverse (ref-get (Fn-locals fn))) ,@code (i32.const 0)))))

    ;; ---- Text ----

    ;; Top-level module fields and function instructions start new lines.
    (define (wat->string module)
      (let ((port (open-output-string)))
        (write-string "(module" port)
        (for-each (lambda (field) (newline port) (write-string "  " port) (write-field field port)) (cdr module))
        (write-string ")\n" port)
        (get-output-string port)))

    (define (write-field field port)
      (if (and (pair? field) (memq (car field) '(func rec)))
          (begin (write-string "(" port)
                 (write-datum (car field) port)
                 (for-each (lambda (part)
                             (if (own-line? (car field) part)
                                 (begin (newline port) (write-string "    " port))
                                 (write-string " " port))
                             (write-datum part port))
                           (cdr field))
                 (write-string ")" port))
          (write-datum field port)))

    (define (own-line? head part)
      (and (pair? part) (or (eq? head 'rec) (not (memq (car part) '(type param result local export))))))

    ;; A named loop: the host's `for-each` is several times slower here.
    (define (write-datum datum port)
      (cond ((pair? datum)
             (write-string "(" port)
             (write-datum (car datum) port)
             (let loop ((parts (cdr datum)))
               (when (pair? parts)
                 (write-string " " port)
                 (write-datum (car parts) port)
                 (loop (cdr parts))))
             (write-string ")" port))
            ((null? datum) (write-string "()" port))
            ((string? datum) (write-wat-string datum port))
            ((symbol? datum) (write-string (symbol->string datum) port))
            ((and (exact-integer? datum) (<= 0 datum) (< datum (vector-length small-integers)))
             (write-string (vector-ref small-integers datum) port))
            (else (write-string (number->string datum) port))))

    ;; The host's number printing is slow, and most numbers in a module are
    ;; small indices and constants.
    (define small-integers
      (let ((texts (make-vector 4096)))
        (do ((index 0 (+ index 1))) ((= index 4096) texts)
          (vector-set! texts index (number->string index)))))

    ;; Wasm strings are UTF-8 bytes; anything beyond printable ASCII is escaped.
    (define (write-wat-string text port)
      (write-char #\" port)
      (for-each (lambda (byte)
                  (if (and (>= byte 32) (< byte 127) (not (memv byte '(34 92))))
                      (write-char (integer->char byte) port)
                      (begin (write-char #\\ port)
                             (write-string (string-pad (number->string byte 16) 2) port))))
                (bytevector->list (string->utf8 text)))
      (write-char #\" port))

    (define (string-pad text width)
      (if (< (string-length text) width) (string-append (make-string (- width (string-length text)) #\0) text) text))

    (define (bytevector->list bytes)
      (let loop ((index (- (bytevector-length bytes) 1)) (out '()))
        (if (< index 0) out (loop (- index 1) (cons (bytevector-u8-ref bytes index) out)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm)
    (import
     (lofi testing))
    (begin
      (define (test-wasm)
        (expect (mangle "a b,c(d)") "a_b~c<d>"))))
   (else)))
