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
   (lofi base)
   (lofi table)
   (lofi compiler read)
   (lofi compiler core)
   (lofi compiler mono))
  (begin

    ;; ---- Text ----

    ;; A WAT S-expression is a word, such as a keyword, identifier, number,
    ;; string literal or a preformatted helper, or a parenthesized node.
    (enum Wat
      (Word
       ((text String)))
      (Node
       ((items (List Wat)))))

    ;; `(wat "i32.add" a b)` is the node `(i32.add a b)`.
    (define-syntax wat
      (syntax-rules ()
        ((_ head item ...) (Node (list (Word head) item ...)))))

    ;; A node whose items after the head form a list.
    (: wat* (-> String (List Wat) Wat))
    (define (wat* head items)
      (Node (Cons (Word head) items)))

    (: int (-> I64 Wat))
    (define (int n)
      (Word (i64->string n)))

    ;; Top-level module fields and function instructions start new lines.
    (: wat->string (-> Wat String))
    (define (wat->string module)
      (match module
        ((Node (Cons _ fields))
         (string-concatenate
          (reverse (Cons ")\n" (fold-left (lambda (pieces field) (write-field field (Cons "\n  " pieces))) (list "(module") fields)))))
        (_ (panic "internal error: not a module"))))

    (: write-field (-> Wat (List String) (List String)))
    (define (write-field field pieces)
      (match field
        ((Node (Cons (Word head) parts))
         (if (or (string=? head "func") (string=? head "rec"))
             (Cons ")" (fold-left (lambda (pieces part) (write-wat part (Cons (if (own-line? head part) "\n    " " ") pieces)))
                                  (Cons head (Cons "(" pieces)) parts))
             (write-wat field pieces)))
        (_ (write-wat field pieces))))

    (: own-line? (-> String Wat Bool))
    (define (own-line? head part)
      (match part
        ((Node (Cons (Word inner) _))
         (or (string=? head "rec") (not (member? inner (list "type" "param" "result" "local" "export")))))
        (_ #f)))

    ;; Pieces accumulate in reverse.
    (: write-wat (-> Wat (List String) (List String)))
    (define (write-wat wat pieces)
      (match wat
        ((Word text) (Cons text pieces))
        ((Node (Nil)) (Cons "()" pieces))
        ((Node (Cons first rest))
         (Cons ")" (fold-left (lambda (pieces item) (write-wat item (Cons " " pieces))) (write-wat first (Cons "(" pieces)) rest)))))

    ;; Wasm strings are UTF-8 bytes; anything beyond printable ASCII is escaped.
    (: wat-string (-> String Wat))
    (define (wat-string text)
      (Word (string-append "\"" (string-concatenate (map escape-char (string->list text))) "\"")))

    (: escape-char (-> Char String))
    (define (escape-char c)
      (let ((code (char->integer c)))
        (if (and (>= code 32) (< code 127) (not (= code 34)) (not (= code 92)))
            (list->string (list c))
            (string-concatenate (map (lambda (byte) (string-append "\\" (hex-digit (quotient byte 16)) (hex-digit (remainder byte 16))))
                                     (utf-8-bytes code))))))

    (: hex-digit (-> I64 String))
    (define (hex-digit value)
      (substring "0123456789abcdef" value (+ value 1)))

    (: utf-8-bytes (-> I64 (List I64)))
    (define (utf-8-bytes code)
      (cond ((< code 128) (list code))
            ((< code 2048) (list (+ 192 (quotient code 64)) (+ 128 (remainder code 64))))
            ((< code 65536)
             (list (+ 224 (quotient code 4096)) (+ 128 (remainder (quotient code 64) 64)) (+ 128 (remainder code 64))))
            (else (list (+ 240 (quotient code 262144)) (+ 128 (remainder (quotient code 4096) 64))
                        (+ 128 (remainder (quotient code 64) 64)) (+ 128 (remainder code 64))))))

    ;; Fills each `{name}` in a template of fixed WAT text.
    (: fill (-> String (List (Pair String String)) String))
    (define (fill template bindings)
      (let loop ((chars (string->list template)) (pieces (Nil)))
        (match chars
          ((Nil) (string-concatenate (reverse pieces)))
          ((Cons #\{ rest)
           (let ((name (list->string (take-until rest #\}))))
             (match (assoc-ref bindings name)
               ((Some value) (loop (drop rest (+ (string-length name) 1)) (Cons value pieces)))
               ((None) (loop rest (Cons "{" pieces))))))
          ((Cons c rest) (loop rest (Cons (list->string (list c)) pieces))))))

    (: take-until (-> (List Char) Char (List Char)))
    (define (take-until chars stop)
      (let loop ((chars chars) (taken (Nil)))
        (match chars
          ((Cons c rest) (if (char=? c stop) (reverse taken) (loop rest (Cons c taken))))
          ((Nil) (reverse taken)))))

    ;; ---- Module state ----

    ;; Every GC type lives in one recursion group, registered on first use.
    ;; `memo` caches closures for global functions, singletons and string
    ;; literals; `helpers` caches imports and helper functions by key.
    (struct Module
      ((program Program)
       (definitions (Table Expr))
       (type-ids (Table String))
       (types (Ref (List Wat)))
       (imports (Ref (List Wat)))
       (globals (Ref (List Wat)))
       (functions (Ref (List Wat)))
       (declared (Ref (List String)))
       (exports (Ref (List Wat)))
       (memo (Table Wat))
       (helpers (Table String))
       (counter (Ref I64))))

    (: push! (All (T) (-> (Ref (List T)) T Unit ! mut)))
    (define (push! cell value)
      (ref-set! cell (Cons value (ref-get cell))))

    (: next-number! (-> Module I64 ! mut))
    (define (next-number! m)
      (let ((count (+ (ref-get (Module-counter m)) 1)))
        (ref-set! (Module-counter m) count)
        count))

    (: memoize! (-> Module String (-> Wat ! mut) Wat ! mut))
    (define (memoize! m key make)
      (match (table-ref (Module-memo m) key)
        ((Some value) value)
        ((None)
         (let ((value (make)))
           (table-set! (Module-memo m) key value)
           value))))

    (: program-of (-> Module Program))
    (define (program-of m)
      (Module-program m))

    ;; A location for code the backend writes itself.
    (: no-loc Loc)
    (define no-loc (Loc "" 0 0))

    ;; ---- Names ----

    ;; Characters outside Wasm's identifier set are replaced.
    (: mangle (-> String String))
    (define (mangle text)
      (vector->string (vector-map mangle-char (string->vector text))))

    (: mangle-char (-> Char Char))
    (define (mangle-char c)
      (cond ((char=? c #\space) #\_)
            ((char=? c #\,) #\~)
            ((char=? c #\() #\<)
            ((char=? c #\)) #\>)
            ((member? c (list #\" #\; #\[ #\] #\{ #\})) #\_)
            ((and (> (char->integer c) 32) (< (char->integer c) 127)) c)
            (else #\_)))

    (: wasm-id (-> String String))
    (define (wasm-id text)
      (string-append "$" (mangle text)))

    (: fresh-id (-> Module String String ! mut))
    (define (fresh-id m prefix)
      (wasm-id (string-append prefix "." (i64->string (next-number! m)))))

    (: id (-> String Wat))
    (define (id name)
      (Word name))

    ;; ---- Representations ----

    ;; A value's Wasm type: a number type, or a non-null reference to a
    ;; declared type. `i8` appears only as the element of a byte array.
    (enum Rep
      (Scalar
       ((name String)))
      (Reference
       ((type String))))

    (: rep->wat (-> Rep Wat))
    (define (rep->wat rep)
      (match rep
        ((Scalar name) (Word name))
        ((Reference type) (wat "ref" (id type)))))

    (: nullable (-> Rep Wat))
    (define (nullable rep)
      (match rep
        ((Scalar name) (Word name))
        ((Reference type) (wat "ref" (Word "null") (id type)))))

    (: rep-key (-> Rep String))
    (define (rep-key rep)
      (match rep
        ((Scalar name) name)
        ((Reference type) (substring type 1 (string-length type)))))

    (: reference-type (-> Rep String))
    (define (reference-type rep)
      (match rep
        ((Reference type) type)
        ((Scalar name) (panic (string-append "internal error: not a reference: " name)))))

    (: default-value (-> Rep Wat))
    (define (default-value rep)
      (match rep
        ((Scalar name) (wat (string-append name ".const") (Word "0")))
        ((Reference type) (wat "ref.null" (id type)))))

    (: rep (-> Module Type Rep ! mut))
    (define (rep m type)
      (match type
        ((TCon name args)
         (case name
           (("U8" "I32" "Bool" "Char" "Unit") (Scalar "i32"))
           (("I64") (Scalar "i64"))
           (("F32") (Scalar "f32"))
           (("F64") (Scalar "f64"))
           (("String") (Reference (array-type m (Scalar "i32"))))
           (("Any") (Reference (any-type m)))
           (("Array" "Vector") (Reference (array-type m (element-rep m (first-type args)))))
           (("Ref") (Reference (cell-type m (rep m (first-type args)))))
           (else (if (tag-enum? m name) (Scalar "i32") (Reference (data-type m type))))))
        ((TFun params result _) (Reference (closure-type m (map (lambda (param) (rep m param)) params) (rep m result))))
        (_ (panic (string-append "internal error: not a ground type: " (type-key type))))))

    (: first-type (-> (List Type) Type))
    (define (first-type types)
      (match types
        ((Cons type _) type)
        ((Nil) (panic "internal error: missing type argument"))))

    ;; Byte arrays are packed; a byte is an i32 everywhere else.
    (: element-rep (-> Module Type Rep ! mut))
    (define (element-rep m type)
      (match type
        ((TCon "U8" (Nil)) (Scalar "i8"))
        (_ (rep m type))))

    (: array-get (-> String String))
    (define (array-get array)
      (if (string=? array "$arr.i8") "array.get_u" "array.get"))

    (: register-type! (-> Module String String Wat String ! mut))
    (define (register-type! m key type definition)
      (table-set! (Module-type-ids m) key type)
      (push! (Module-types m) definition)
      type)

    (: known-type (-> Module String (Option String) ! mut))
    (define (known-type m key)
      (table-ref (Module-type-ids m) key))

    (: array-type (-> Module Rep String ! mut))
    (define (array-type m element)
      (let ((key (string-append "arr." (rep-key element))))
        (match (known-type m key)
          ((Some type) type)
          ((None) (register-type! m key (wasm-id key) (wat "type" (id (wasm-id key)) (wat "array" (wat "mut" (rep->wat element)))))))))

    (: cell-type (-> Module Rep String ! mut))
    (define (cell-type m content)
      (let ((key (string-append "cell." (rep-key content))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m key (wasm-id key) (wat "type" (id (wasm-id key)) (wat "struct" (wat "field" (wat "mut" (rep->wat content))))))))))

    ;; A closure is a struct whose first field is its code. Each lambda with
    ;; captured variables extends the base struct with their fields.
    (: closure-type (-> Module (List Rep) Rep String ! mut))
    (define (closure-type m params result)
      (let* ((signature (string-append (string-join (map rep-key params) ",") "->" (rep-key result)))
             (key (string-append "clo." signature)))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (let ((closure (wasm-id key)) (code (wasm-id (string-append "fn." signature))))
             (table-set! (Module-type-ids m) key closure)
             (table-set! (Module-type-ids m) (string-append "code:" closure) code)
             (register-type! m (string-append "fn." signature) code
                             (wat "type" (id code)
                                  (wat* "func" (append (Cons (wat "param" (wat "ref" (id closure)))
                                                             (map (lambda (param) (wat "param" (rep->wat param))) params))
                                                       (list (wat "result" (rep->wat result)))))))
             (register-type! m key closure (wat "type" (id closure) (wat "sub" (wat "struct" (wat "field" (wat "ref" (id code))))))))))))

    ;; Every closure subtype shares its base's code type.
    (: code-type (-> Module String String ! mut))
    (define (code-type m closure)
      (match (known-type m (string-append "code:" closure))
        ((Some code) code)
        ((None) (panic "internal error: closure without a code type"))))

    (: function-signature (-> Module Type (Pair (List Rep) Rep) ! mut))
    (define (function-signature m type)
      (match type
        ((TFun params result _) (Pair (map (lambda (param) (rep m param)) params) (rep m result)))
        (_ (panic "internal error: not a function type"))))

    (: data-type-of (-> Module String DataType ! mut))
    (define (data-type-of m name)
      (program-type (program-of m) name))

    (: tag-enum? (-> Module String Bool ! mut))
    (define (tag-enum? m name)
      (let ((data (data-type-of m name)))
        (and (DataType-enum? data) (every? (lambda (case) (null? (Case-fields case))) (DataType-cases data)))))

    (: case-field-types (-> Module Type Case (List Type) ! mut))
    (define (case-field-types m type case)
      (match type
        ((TCon name args)
         (let ((substitution (zip (DataType-params (data-type-of m name)) args)))
           (map (lambda (field) (substitute substitution (Field-type field))) (Case-fields case))))
        (_ (panic "internal error: not a data type"))))

    (: case-fields (-> Module Type Case (List Wat) ! mut))
    (define (case-fields m type case)
      (map (lambda (field) (wat "field" (rep->wat (rep m field)))) (case-field-types m type case)))

    (: type-name (-> Type String))
    (define (type-name type)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: not a named type"))))

    ;; A struct is one GC struct. An enum is a base struct holding the tag,
    ;; with a final subtype for each case that has fields; a field-less case
    ;; is the base struct itself. The base is registered first because a
    ;; supertype must precede its subtypes.
    (: data-type (-> Module Type String ! mut))
    (define (data-type m type)
      (let ((key (type-key type)))
        (match (known-type m key)
          ((Some found) found)
          ((None)
           (let ((type-id (wasm-id key)) (data (data-type-of m (type-name type))))
             (table-set! (Module-type-ids m) key type-id)
             (if (DataType-enum? data)
                 (begin (push! (Module-types m) (wat "type" (id type-id) (wat "sub" (wat "struct" (wat "field" (Word "i32"))))))
                        (for-each (lambda (case) (case-type m type case) (unit))
                                  (filter (lambda (case) (not (null? (Case-fields case)))) (DataType-cases data))))
                 (match (DataType-cases data)
                   ((Cons case _) (push! (Module-types m) (wat "type" (id type-id) (wat* "struct" (case-fields m type case)))))
                   ((Nil) (panic "internal error: a struct has one case"))))
             type-id)))))

    (: case-type (-> Module Type Case String ! mut))
    (define (case-type m type case)
      (let ((key (string-append (type-key type) "." (short-name (Case-name case)))))
        (match (known-type m key)
          ((Some found) found)
          ((None)
           (let* ((base (data-type m type)) (case-id (wasm-id key)))
             (register-type! m key case-id
                             (wat "type" (id case-id)
                                  (wat "sub" (Word "final") (id base) (wat* "struct" (Cons (wat "field" (Word "i32")) (case-fields m type case)))))))))))

    ;; ---- Functions ----

    ;; `access` maps each visible local name to the instruction that reads it,
    ;; and `reps` to its representation. In a recursive lambda, `self` pairs
    ;; its own name with its Wasm function, so it can call itself directly.
    (struct Fn
      ((module Module)
       (locals (Ref (List Wat)))
       (access (Table Wat))
       (reps (Table Rep))
       (self (Option (Pair String String)))))

    (: new-fn (-> Module Fn ! mut))
    (define (new-fn m)
      (Fn m (ref (Nil)) (make-table) (make-table) (None)))

    (: bind-local! (-> Fn String Wat Rep Unit ! mut))
    (define (bind-local! fn name read rep)
      (table-set! (Fn-access fn) name read)
      (table-set! (Fn-reps fn) name rep))

    (: declare-local! (-> Fn String Rep String ! mut))
    (define (declare-local! fn name rep)
      (let ((local (wasm-id name)))
        (push! (Fn-locals fn) (wat "local" (id local) (rep->wat rep)))
        (bind-local! fn name (wat "local.get" (id local)) rep)
        local))

    ;; A temporary takes any value type, including a nullable reference.
    (: declare-temp! (-> Fn Wat String ! mut))
    (define (declare-temp! fn type)
      (let ((local (fresh-id (Fn-module fn) "tmp")))
        (push! (Fn-locals fn) (wat "local" (id local) type))
        local))

    (: local-access (-> Fn String (Option Wat) ! mut))
    (define (local-access fn name)
      (table-ref (Fn-access fn) name))

    (: local? (-> Fn String Bool ! mut))
    (define (local? fn name)
      (table-contains? (Fn-access fn) name))

    (: fn-rep (-> Fn Type Rep ! mut))
    (define (fn-rep fn type)
      (rep (Fn-module fn) type))

    ;; A function definition: its name, parameters and result, the locals it
    ;; declared, then the body.
    (: function-wat (-> Fn String (List Wat) Rep (List Wat) Wat ! mut))
    (define (function-wat fn name params result body)
      (wat* "func" (Cons (id name) (append params (Cons (wat "result" (rep->wat result)) (append (reverse (ref-get (Fn-locals fn))) body))))))

    (: param-wats (-> (List String) (List Rep) (List Wat)))
    (define (param-wats params reps)
      (map (lambda (pair) (wat "param" (id (wasm-id (Pair-first pair))) (rep->wat (Pair-second pair)))) (zip params reps)))

    (: emit-function! (-> Module String Expr Unit ! mut))
    (define (emit-function! m name function)
      (match (Expr-term function)
        ((Lambda params body)
         (let* ((fn (new-fn m)) (signature (function-signature m (Expr-type function))) (reps (Pair-first signature)))
           (for-each (lambda (pair) (bind-local! fn (Pair-first pair) (wat "local.get" (id (wasm-id (Pair-first pair)))) (Pair-second pair)))
                     (zip params reps))
           (let ((code (emit fn body #t)))
             (push! (Module-functions m) (function-wat fn (wasm-id name) (param-wats params reps) (Pair-second signature) code)))))
        (_ (panic "internal error: not a function"))))

    ;; ---- Expressions ----

    ;; A list of instructions that leave one value on the stack.
    (: emit (-> Fn Expr Bool (List Wat) ! mut))
    (define (emit fn expr tail?)
      (let ((type (Expr-type expr)))
        (match (Expr-term expr)
          ((Lit value) (list (literal fn value type)))
          ((Var name _ _) (list (variable fn name type)))
          ((Lambda _ _) (list (closure fn expr (None))))
          ((App callee args) (emit-call fn expr callee args tail?))
          ((If test then otherwise)
           (list (wat "if" (wat "result" (rep->wat (fn-rep fn type))) (emit1 fn test)
                      (wat* "then" (emit fn then tail?)) (wat* "else" (emit fn otherwise tail?)))))
          ((Let name value body) (emit-let fn name value body tail?))
          ((Seq first rest) (Cons (wat "drop" (emit1 fn first)) (emit fn rest tail?)))
          ((Match scrutinee clauses) (emit-match fn expr scrutinee clauses tail?))
          ((Handle effect implementations body) (emit-handle fn expr effect implementations body))
          ((Convert inner target) (emit-convert fn inner target (Expr-loc expr)))
          ((Ann inner _) (emit fn inner tail?)))))

    ;; One instruction, wrapping a sequence in a block when needed.
    (: emit1 (-> Fn Expr Wat ! mut))
    (define (emit1 fn expr)
      (emit1-tail fn expr #f))

    (: emit1-tail (-> Fn Expr Bool Wat ! mut))
    (define (emit1-tail fn expr tail?)
      (match (emit fn expr tail?)
        ((Cons single (Nil)) single)
        (code (wat* "block" (Cons (wat "result" (rep->wat (fn-rep fn (Expr-type expr)))) code)))))

    (: emit-args (-> Fn (List Expr) (List Wat) ! mut))
    (define (emit-args fn args)
      (map (lambda (arg) (emit1 fn arg)) args))

    (: literal (-> Fn Datum Type Wat ! mut))
    (define (literal fn value type)
      (match value
        ((DBool true?) (wat "i32.const" (int (if true? 1 0))))
        ((DChar c) (wat "i32.const" (int (char->integer c))))
        ((DString text) (string-literal (Fn-module fn) text))
        ((DUnit) (wat "i32.const" (int 0)))
        ((DInt n) (wat (string-append (rep-key (fn-rep fn type)) ".const") (int n)))
        ((DFloat text) (wat (string-append (rep-key (fn-rep fn type)) ".const") (Word (float-text text))))))

    ;; WAT needs a digit before a decimal point, as in `0.5` or `-0.5`.
    (: float-text (-> String String))
    (define (float-text text)
      (cond ((and (> (string-length text) 0) (char=? (string-ref text 0) #\.)) (string-append "0" text))
            ((and (> (string-length text) 1) (char=? (string-ref text 1) #\.)
                  (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
             (string-append (substring text 0 1) "0" (substring text 1 (string-length text))))
            (else text)))

    ;; String literals are immutable globals, built once.
    (: string-literal (-> Module String Wat ! mut))
    (define (string-literal m text)
      (memoize! m (string-append "string:" text)
                (lambda ()
                  (let ((global (fresh-id m "string")) (array (array-type m (Scalar "i32"))))
                    (push! (Module-globals m)
                           (wat "global" (id global) (wat "ref" (id array))
                                (wat* "array.new_fixed"
                                      (Cons (id array)
                                            (Cons (int (string-length text))
                                                  (map (lambda (c) (wat "i32.const" (int (char->integer c)))) (string->list text)))))))
                    (wat "global.get" (id global))))))

    (: emit-let (-> Fn String Expr Expr Bool (List Wat) ! mut))
    (define (emit-let fn name value body tail?)
      (let* ((code (if (and (lambda-expr? value) (member? name (expr-references value))) (closure fn value (Some name)) (emit1 fn value)))
             (local (declare-local! fn name (fn-rep fn (Expr-type value)))))
        (Cons (wat "local.set" (id local) code) (emit fn body tail?))))

    ;; ---- Variables ----

    ;; A global function or operation used as a value becomes a closure.
    (: variable (-> Fn String Type Wat ! mut))
    (define (variable fn name type)
      (let ((m (Fn-module fn)))
        (match (local-access fn name)
          ((Some access) access)
          ((None)
           (match (table-ref (Module-definitions m) name)
             ((Some definition)
              (cond ((lambda-expr? definition) (function-value m name type))
                    ((scalar? (fn-rep fn type)) (wat "global.get" (id (wasm-id name))))
                    (else (wat "ref.as_non_null" (wat "global.get" (id (wasm-id name)))))))
             ((None)
              (match (program-value (program-of m) name)
                ((Some (Constructor case _)) (if (null? (Case-fields case)) (construct fn case type (Nil)) (function-value m name type)))
                ((Some _) (function-value m name type))
                ((None) (panic (string-append "internal error: unknown variable " name))))))))))

    (: scalar? (-> Rep Bool))
    (define (scalar? rep)
      (match rep
        ((Scalar _) #t)
        (_ #f)))

    ;; An immutable global closure whose code calls `name` with its arguments.
    (: function-value (-> Module String Type Wat ! mut))
    (define (function-value m name type)
      (memoize! m (string-append "closure:" name ":" (type-key type))
                (lambda ()
                  (match type
                    ((TFun params result _)
                     (let* ((names (map (lambda (index) (string-append "argument." (i64->string index))) (iota (length params))))
                            (call (Expr (App (Expr (Var name (Nil) (Nil)) type no-loc)
                                             (map (lambda (pair) (Expr (Var (Pair-first pair) (Nil) (Nil)) (Pair-second pair) no-loc))
                                                  (zip names params)))
                                        result no-loc)))
                       (closure-value m (Expr (Lambda names call) type no-loc) (None))))
                    (_ (panic "internal error: a function value needs a function type"))))))

    ;; ---- Closures ----

    ;; A lambda becomes a function taking its closure first. Captured
    ;; variables are copied into the closure and loaded on entry; `self` names
    ;; a recursive local function, which reads as the closure itself.
    (: closure (-> Fn Expr (Option String) Wat ! mut))
    (define (closure fn function self)
      (let ((captured (filter (lambda (name) (and (not (self-name? self name)) (local? fn name)))
                              (expr-references function))))
        (if (null? captured)
            (closure-value (Fn-module fn) function self)
            (closure-with-captures fn function self captured))))

    (: self-name? (-> (Option String) String Bool))
    (define (self-name? self name)
      (match self
        ((Some own) (string=? own name))
        ((None) #f)))

    ;; A closure without captures is one immutable global.
    (: closure-value (-> Module Expr (Option String) Wat ! mut))
    (define (closure-value m function self)
      (let* ((signature (function-signature m (Expr-type function)))
             (base (closure-type m (Pair-first signature) (Pair-second signature)))
             (code (lambda-function! m function self (Nil) base))
             (global (fresh-id m "closure")))
        (push! (Module-globals m) (wat "global" (id global) (wat "ref" (id base)) (wat "struct.new" (id base) (wat "ref.func" (id code)))))
        (wat "global.get" (id global))))

    (: closure-with-captures (-> Fn Expr (Option String) (List String) Wat ! mut))
    (define (closure-with-captures fn function self captured)
      (let* ((m (Fn-module fn)) (signature (function-signature m (Expr-type function)))
             (base (closure-type m (Pair-first signature) (Pair-second signature))) (subtype (fresh-id m "closure"))
             (reps (map (lambda (name) (capture-rep fn name)) captured)))
        (register-type! m subtype subtype
                        (wat "type" (id subtype)
                             (wat "sub" (Word "final") (id base)
                                  (wat* "struct" (Cons (wat "field" (wat "ref" (id (code-type m base))))
                                                       (map (lambda (r) (wat "field" (rep->wat r))) reps))))))
        (let ((code (lambda-function! m function self (zip captured reps) subtype)))
          (wat* "struct.new" (Cons (id subtype) (Cons (wat "ref.func" (id code)) (map (lambda (name) (variable fn name unchecked)) captured)))))))

    (: capture-rep (-> Fn String Rep ! mut))
    (define (capture-rep fn name)
      (match (table-ref (Fn-reps fn) name)
        ((Some rep) rep)
        ((None) (panic (string-append "internal error: no representation for " name)))))

    (: lambda-function! (-> Module Expr (Option String) (List (Pair String Rep)) String String ! mut))
    (define (lambda-function! m function self captured closure)
      (match (Expr-term function)
        ((Lambda params body)
         (let* ((signature (function-signature m (Expr-type function))) (reps (Pair-first signature))
                (function-id (fresh-id m "lambda"))
                (fn (Fn-self-set (new-fn m) (match self ((Some name) (Some (Pair name function-id))) ((None) (None)))))
                (base (closure-type m reps (Pair-second signature))))
           (push! (Module-declared m) function-id)
           (match self
             ((Some name) (bind-local! fn name (wat "local.get" (Word "$closure")) (Reference base)))
             ((None) (unit)))
           (for-each (lambda (pair) (bind-local! fn (Pair-first pair) (wat "local.get" (id (wasm-id (Pair-first pair)))) (Pair-second pair)))
                     (zip params reps))
           (let* ((loads (map-indexed (lambda (index entry)
                                        (wat "local.set" (id (declare-local! fn (Pair-first entry) (Pair-second entry)))
                                             (wat "struct.get" (id closure) (int (+ index 1))
                                                  (wat "ref.cast" (wat "ref" (id closure)) (wat "local.get" (Word "$closure"))))))
                                      captured))
                  (code (emit fn body #t)))
             ;; The function's type must be the closure's code type itself,
             ;; not a structurally equal one, for `ref.func` to fit the field.
             (push! (Module-functions m)
                    (function-wat fn function-id
                                  (Cons (wat "type" (id (code-type m base)))
                                        (Cons (wat "param" (Word "$closure") (wat "ref" (id base))) (param-wats params reps)))
                                  (Pair-second signature) (append loads code)))
             function-id)))
        (_ (panic "internal error: not a lambda"))))

    ;; ---- Calls ----

    (: call-op (-> Bool String))
    (define (call-op tail?)
      (if tail? "return_call" "call"))

    (: emit-call (-> Fn Expr Expr (List Expr) Bool (List Wat) ! mut))
    (define (emit-call fn expr callee args tail?)
      (match (Expr-term callee)
        ((Var name _ _)
         (match (Fn-self fn)
           ((Some (Pair own function-id))
            (if (string=? own name)
                (list (wat* (call-op tail?) (Cons (id function-id) (Cons (wat "local.get" (Word "$closure")) (emit-args fn args)))))
                (named-call fn expr callee name args tail?)))
           ((None) (named-call fn expr callee name args tail?))))
        (_ (closure-call fn callee args tail?))))

    (: named-call (-> Fn Expr Expr String (List Expr) Bool (List Wat) ! mut))
    (define (named-call fn expr callee name args tail?)
      (if (local? fn name)
          (closure-call fn callee args tail?)
          (match (table-ref (Module-definitions (Fn-module fn)) name)
            ((Some definition)
             (if (lambda-expr? definition)
                 (list (wat* (call-op tail?) (Cons (id (wasm-id name)) (emit-args fn args))))
                 (closure-call fn callee args tail?)))
            ((None) (builtin-call fn expr name args)))))

    (: builtin-call (-> Fn Expr String (List Expr) (List Wat) ! mut))
    (define (builtin-call fn expr name args)
      (let ((m (Fn-module fn)))
        (match (program-value (program-of m) name)
          ((Some (Constructor case _)) (list (construct fn case (Expr-type expr) (emit-args fn args))))
          ((Some (Accessor case index _)) (list (field-access fn case index (first-arg args))))
          ((Some (Replacer case index _)) (list (replace-field fn case index (first-arg args) (list-ref args 1))))
          ((Some (Primitive _)) (emit-primitive fn name args (Expr-type expr)))
          ((Some (Operation effect _)) (list (wat* "call" (Cons (id (performer m effect name)) (emit-args fn args)))))
          ((Some (Foreign import scheme)) (foreign-call fn import (Scheme-type scheme) args))
          (_ (panic (string-append "internal error: cannot call " name))))))

    (: first-arg (-> (List Expr) Expr))
    (define (first-arg args)
      (match args
        ((Cons arg _) arg)
        ((Nil) (panic "internal error: missing argument"))))

    ;; The callee is evaluated once, into a temporary unless it is already a
    ;; variable read.
    (: closure-call (-> Fn Expr (List Expr) Bool (List Wat) ! mut))
    (define (closure-call fn callee args tail?)
      (let* ((m (Fn-module fn)) (signature (function-signature m (Expr-type callee)))
             (base (closure-type m (Pair-first signature) (Pair-second signature))) (value (emit1 fn callee)))
        (if (variable-read? value)
            (list (closure-call-wat m base value (emit-args fn args) tail?))
            (let ((temp (declare-temp! fn (rep->wat (Reference base)))))
              (list (wat "local.set" (id temp) value)
                    (closure-call-wat m base (wat "local.get" (id temp)) (emit-args fn args) tail?))))))

    (: closure-call-wat (-> Module String Wat (List Wat) Bool Wat ! mut))
    (define (closure-call-wat m base read args tail?)
      (wat* (if tail? "return_call_ref" "call_ref")
            (Cons (id (code-type m base)) (Cons read (append args (list (wat "struct.get" (id base) (int 0) read)))))))

    (: variable-read? (-> Wat Bool))
    (define (variable-read? code)
      (match code
        ((Node (Cons (Word head) _)) (or (string=? head "local.get") (string=? head "global.get")))
        (_ #f)))

    ;; Tag enums are i32 constants; field-less cases of other enums are shared
    ;; immutable globals of the base type, so constructing them allocates
    ;; nothing.
    (: construct (-> Fn Case Type (List Wat) Wat ! mut))
    (define (construct fn case type args)
      (let* ((m (Fn-module fn)) (name (Case-type case)))
        (cond ((tag-enum? m name) (wat "i32.const" (int (Case-tag case))))
              ((not (DataType-enum? (data-type-of m name))) (wat* "struct.new" (Cons (id (data-type m type)) args)))
              ((null? args) (singleton m type case))
              (else (wat* "struct.new" (Cons (id (case-type m type case)) (Cons (wat "i32.const" (int (Case-tag case))) args)))))))

    (: singleton (-> Module Type Case Wat ! mut))
    (define (singleton m type case)
      (memoize! m (string-append "singleton:" (type-key type) ":" (Case-name case))
                (lambda ()
                  (let ((global (fresh-id m "value")) (base (data-type m type)))
                    (push! (Module-globals m)
                           (wat "global" (id global) (wat "ref" (id base)) (wat "struct.new" (id base) (wat "i32.const" (int (Case-tag case))))))
                    (wat "global.get" (id global))))))

    (: field-access (-> Fn Case I64 Expr Wat ! mut))
    (define (field-access fn case index value)
      (let* ((m (Fn-module fn)) (type (Expr-type value)))
        (if (DataType-enum? (data-type-of m (Case-type case)))
            (let ((case-id (case-type m type case)))
              (wat "struct.get" (id case-id) (int (+ index 1)) (wat "ref.cast" (wat "ref" (id case-id)) (emit1 fn value))))
            (wat "struct.get" (id (data-type m type)) (int index) (emit1 fn value)))))

    (: replace-field (-> Fn Case I64 Expr Expr Wat ! mut))
    (define (replace-field fn case index value replacement)
      (let* ((m (Fn-module fn)) (type-id (data-type m (Expr-type value))) (temp (declare-temp! fn (rep->wat (Reference type-id)))))
        (wat "block" (wat "result" (wat "ref" (id type-id)))
             (wat "local.set" (id temp) (emit1 fn value))
             (wat* "struct.new"
                   (Cons (id type-id)
                         (map (lambda (i) (if (= i index) (emit1 fn replacement) (wat "struct.get" (id type-id) (int i) (wat "local.get" (id temp)))))
                              (iota (length (Case-fields case)))))))))

    (: foreign-call (-> Fn Import Type (List Expr) (List Wat) ! mut))
    (define (foreign-call fn import type args)
      (let* ((signature (function-signature (Fn-module fn) type))
             (function-id (import! (Fn-module fn) import (Pair-first signature) (if (unit-type? type) (None) (Some (Pair-second signature)))))
             (call (wat* "call" (Cons (id function-id) (emit-args fn args)))))
        (if (unit-type? type) (list call (wat "i32.const" (int 0))) (list call))))

    (: unit-type? (-> Type Bool))
    (define (unit-type? function-type)
      (match function-type
        ((TFun _ (TCon "Unit" (Nil)) _) #t)
        (_ #f)))

    (: import! (-> Module Import (List Rep) (Option Rep) String ! mut))
    (define (import! m import params result)
      (let ((key (string-append "import:" (Import-module import) ":" (Import-symbol import))))
        (match (table-ref (Module-helpers m) key)
          ((Some function-id) function-id)
          ((None)
           (let ((function-id (wasm-id (string-append "import." (Import-symbol import)))))
             (table-set! (Module-helpers m) key function-id)
             (push! (Module-imports m)
                    (wat "import" (wat-string (Import-module import)) (wat-string (Import-symbol import))
                         (wat* "func" (Cons (id function-id)
                                            (append (map (lambda (param) (wat "param" (rep->wat param))) params)
                                                    (match result ((Some r) (list (wat "result" (rep->wat r)))) ((None) (Nil))))))))
             function-id)))))

    ;; ---- Pattern matching ----

    ;; Clauses are tried in order. Each clause is a block that its failing
    ;; tests branch out of; a matching clause branches to `done` with its value.
    (: emit-match (-> Fn Expr Expr (List Clause) Bool (List Wat) ! mut))
    (define (emit-match fn expr scrutinee clauses tail?)
      (let* ((m (Fn-module fn)) (value (declare-temp! fn (rep->wat (fn-rep fn (Expr-type scrutinee))))) (done (fresh-id m "match")))
        (list (wat "local.set" (id value) (emit1 fn scrutinee))
              (wat* "block"
                    (Cons (id done)
                          (Cons (wat "result" (rep->wat (fn-rep fn (Expr-type expr))))
                                (append (map (lambda (clause) (clause-block fn clause value done tail?)) clauses)
                                        (list (wat "unreachable")))))))))

    ;; The pattern declares the locals its body reads.
    (: clause-block (-> Fn Clause String String Bool Wat ! mut))
    (define (clause-block fn clause value done tail?)
      (let* ((next (fresh-id (Fn-module fn) "clause"))
             (tests (pattern-code fn (Clause-pattern clause) (wat "local.get" (id value)) next))
             (body (emit1-tail fn (Clause-body clause) tail?)))
        (wat* "block" (Cons (id next) (append tests (list (wat "br" (id done) body)))))))

    (: pattern-code (-> Fn Pattern Wat String (List Wat) ! mut))
    (define (pattern-code fn pattern value fail)
      (match pattern
        ((PWild _) (Nil))
        ((PVar name type) (list (wat "local.set" (id (declare-local! fn name (fn-rep fn type))) value)))
        ((PLit literal-value type) (list (wat "br_if" (id fail) (literal-differs fn literal-value type value))))
        ((PCon constructor args type) (constructor-pattern-code fn constructor args type value fail))))

    (: literal-differs (-> Fn Datum Type Wat Wat ! mut))
    (define (literal-differs fn literal-value type scrutinee)
      (let ((constant (literal fn literal-value type)))
        (match (fn-rep fn type)
          ((Scalar name) (wat (string-append name ".ne") scrutinee constant))
          ((Reference _) (wat "i32.eqz" (wat "call" (id (string-equal-helper (Fn-module fn))) scrutinee constant))))))

    (: constructor-pattern-code (-> Fn String (List Pattern) Type Wat String (List Wat) ! mut))
    (define (constructor-pattern-code fn constructor args type value fail)
      (let* ((m (Fn-module fn))
             (case (match (program-value (program-of m) constructor)
                     ((Some (Constructor case _)) case)
                     (_ (panic "internal error: not a constructor"))))
             (name (Case-type case)) (types (case-field-types m type case)))
        (cond ((tag-enum? m name) (list (wat "br_if" (id fail) (wat "i32.ne" value (wat "i32.const" (int (Case-tag case)))))))
              ((not (DataType-enum? (data-type-of m name))) (fields-code fn (data-type m type) 0 args types value fail))
              (else
               (let ((base (data-type m type)) (case-id (case-type m type case)))
                 (Cons (wat "br_if" (id fail) (wat "i32.ne" (wat "struct.get" (id base) (int 0) value) (wat "i32.const" (int (Case-tag case)))))
                       (if (every? wild? args)
                           (Nil)
                           (let ((cast (declare-temp! fn (rep->wat (Reference case-id)))))
                             (Cons (wat "local.set" (id cast) (wat "ref.cast" (wat "ref" (id case-id)) value))
                                   (fields-code fn case-id 1 args types (wat "local.get" (id cast)) fail))))))))))

    (: wild? (-> Pattern Bool))
    (define (wild? pattern)
      (match pattern
        ((PWild _) #t)
        (_ #f)))

    ;; Sub-patterns read their field once, into a temporary unless the
    ;; pattern is a variable or a wildcard.
    (: fields-code (-> Fn String I64 (List Pattern) (List Type) Wat String (List Wat) ! mut))
    (define (fields-code fn type-id offset args types value fail)
      (concatenate
       (map-indexed (lambda (index pair)
                      (let ((arg (Pair-first pair)) (field (wat "struct.get" (id type-id) (int (+ index offset)) value)))
                        (match arg
                          ((PWild _) (Nil))
                          ((PVar _ _) (pattern-code fn arg field fail))
                          (_ (let ((temp (declare-temp! fn (rep->wat (fn-rep fn (Pair-second pair))))))
                               (Cons (wat "local.set" (id temp) field) (pattern-code fn arg (wat "local.get" (id temp)) fail)))))))
                    (zip args types))))

    ;; ---- Dynamic values ----

    ;; An Any is the TypeId of its value's ground type with the value itself;
    ;; a scalar is boxed so every payload is a reference.
    (: any-type (-> Module String ! mut))
    (define (any-type m)
      (match (known-type m "any")
        ((Some type) type)
        ((None) (register-type! m "any" "$any" (wat "type" (Word "$any") (wat "struct" (wat "field" (Word "i32")) (wat "field" (Word "anyref"))))))))

    (: box-type (-> Module Rep String ! mut))
    (define (box-type m r)
      (let ((key (string-append "box." (rep-key r))))
        (match (known-type m key)
          ((Some type) type)
          ((None) (register-type! m key (wasm-id key) (wat "type" (id (wasm-id key)) (wat "struct" (wat "field" (rep->wat r)))))))))

    (: any-type-id (-> Type I64))
    (define (any-type-id type)
      (let ((hash (fnv-1a (type-key type))))
        (if (>= hash 2147483648) (- hash 4294967296) hash)))

    (: any-type? (-> Type Bool))
    (define (any-type? type)
      (match type
        ((TCon "Any" (Nil)) #t)
        (_ #f)))

    ;; To Any boxes; from Any checks the TypeId and panics on a mismatch. A
    ;; downcast of a value just upcast from the same type is removed.
    (: emit-convert (-> Fn Expr Type Loc (List Wat) ! mut))
    (define (emit-convert fn inner target loc)
      (let ((source (Expr-type inner)) (m (Fn-module fn)))
        (cond ((string=? (type-key source) (type-key target)) (emit fn inner #f))
              ((match (Expr-term inner) ((Convert original _) (string=? (type-key (Expr-type original)) (type-key target))) (_ #f))
               (match (Expr-term inner)
                 ((Convert original _) (emit fn original #f))
                 (_ (Nil))))
              ((any-type? target) (list (to-any m source (emit1 fn inner))))
              ((any-type? source) (list (from-any fn target (emit1 fn inner))))
              (else (compile-error loc (string-append "type-convert converts to or from Any, not from " (type->string source) " to "
                                                      (type->string target)))))))

    (: to-any (-> Module Type Wat Wat ! mut))
    (define (to-any m type value)
      (wat "struct.new" (id (any-type m)) (wat "i32.const" (int (any-type-id type)))
           (match (rep m type)
             ((Scalar _) (wat "struct.new" (id (box-type m (rep m type))) value))
             ((Reference _) value))))

    (: from-any (-> Fn Type Wat Wat ! mut))
    (define (from-any fn type value)
      (let* ((m (Fn-module fn)) (r (fn-rep fn type)) (any (declare-temp! fn (rep->wat (Reference (any-type m)))))
             (payload (wat "struct.get" (Word "$any") (int 1) (wat "local.get" (id any)))))
        (wat "block" (wat "result" (rep->wat r))
             (wat "local.set" (id any) value)
             (wat "if" (wat "i32.ne" (wat "struct.get" (Word "$any") (int 0) (wat "local.get" (id any))) (wat "i32.const" (int (any-type-id type))))
                  (wat "then" (wat "call" (id (panic-helper m)) (string-literal m (string-append "type-convert: the value is not a " (type->string type))))
                       (wat "unreachable")))
             (match r
               ((Scalar _) (wat "struct.get" (id (box-type m r)) (int 0) (wat "ref.cast" (wat "ref" (id (box-type m r))) payload)))
               ((Reference _) (wat "ref.cast" (rep->wat r) payload))))))

    ;; ---- Effect handlers ----

    ;; Each effect has a global stack of handlers, linked through `outer`. An
    ;; operation runs its implementation with the stack popped, so the
    ;; implementation's own operations go to the enclosing handler; an empty
    ;; stack means the host default.
    (: handler-type (-> Module String String ! mut))
    (define (handler-type m effect)
      (let ((key (string-append "handler." effect)))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (let ((type-id (wasm-id key)))
             (table-set! (Module-type-ids m) key type-id)
             (let ((fields (map (lambda (operation) (wat "field" (rep->wat (rep m (operation-type m operation)))))
                                (Effect-operations (program-effect (program-of m) effect)))))
               (push! (Module-types m) (wat "type" (id type-id) (wat* "struct" (append fields (list (wat "field" (wat "ref" (Word "null") (id type-id))))))))
               (push! (Module-globals m)
                      (wat "global" (id (handler-global effect)) (wat "mut" (wat "ref" (Word "null") (id type-id))) (wat "ref.null" (id type-id))))
               type-id))))))

    (: operation-type (-> Module String Type ! mut))
    (define (operation-type m operation)
      (match (program-value (program-of m) operation)
        ((Some (Operation _ (Scheme _ _ (TFun params result _)))) (TFun params result empty-row))
        (_ (panic "internal error: not an operation"))))

    (: emit-handle (-> Fn Expr String (List (Pair String Expr)) Expr (List Wat) ! mut))
    (define (emit-handle fn expr effect implementations body)
      (let* ((m (Fn-module fn)) (type-id (handler-type m effect)) (current (handler-global effect))
             (saved (declare-temp! fn (nullable (Reference type-id)))) (result (declare-temp! fn (rep->wat (fn-rep fn (Expr-type expr))))))
        (list (wat "local.set" (id saved) (wat "global.get" (id current)))
              (wat "global.set" (id current)
                   (wat* "struct.new"
                         (Cons (id type-id)
                               (append (map (lambda (operation)
                                              (match (assoc-ref implementations operation)
                                                ((Some implementation) (emit1 fn implementation))
                                                ((None) (panic "internal error: missing implementation"))))
                                            (Effect-operations (program-effect (program-of m) effect)))
                                       (list (wat "local.get" (id saved)))))))
              (wat "local.set" (id result) (emit1 fn body))
              (wat "global.set" (id current) (wat "local.get" (id saved)))
              (wat "local.get" (id result)))))

    (: handler-global (-> String String))
    (define (handler-global effect)
      (wasm-id (string-append "handler." effect ".current")))

    ;; Each operation is one function, so its call sites are ordinary calls.
    ;; It runs the innermost handler's implementation with that handler
    ;; popped, then restores it; with no handler it uses the host default.
    (: performer (-> Module String String String ! mut))
    (define (performer m effect operation)
      (helper! m "perform" operation
               (lambda (function-id)
                 (let* ((signature (function-signature m (operation-type m operation))) (params (Pair-first signature))
                        (result (Pair-second signature))
                        (names (map (lambda (index) (string-append "$argument." (i64->string index))) (iota (length params))))
                        (handler-id (handler-type m effect)) (info (program-effect (program-of m) effect)))
                   (wat* "func"
                         (append (Cons (id function-id) (map (lambda (pair) (wat "param" (id (Pair-first pair)) (rep->wat (Pair-second pair))))
                                                             (zip names params)))
                                 (append (list (wat "result" (rep->wat result))
                                               (wat "local" (Word "$handler") (wat "ref" (Word "null") (id handler-id)))
                                               (wat "local" (Word "$value") (rep->wat result))
                                               (wat "local.set" (Word "$handler") (wat "global.get" (id (handler-global effect))))
                                               (wat "if" (wat "ref.is_null" (wat "local.get" (Word "$handler")))
                                                    (wat "then" (wat* "return" (host-default m info operation names)))))
                                         (call-implementation m info operation names params result))))))))

    (: call-implementation (-> Module Effect String (List String) (List Rep) Rep (List Wat) ! mut))
    (define (call-implementation m info operation names params result)
      (let* ((handler-id (handler-type m (Effect-name info))) (base (closure-type m params result))
             (current (handler-global (Effect-name info)))
             (index (match (list-index (lambda (o) (string=? o operation)) (Effect-operations info))
                      ((Some index) index)
                      ((None) (panic "internal error: unknown operation"))))
             (implementation (wat "struct.get" (id handler-id) (int index) (wat "local.get" (Word "$handler")))))
        (list (wat "global.set" (id current) (wat "struct.get" (id handler-id) (int (length (Effect-operations info))) (wat "local.get" (Word "$handler"))))
              (wat "local.set" (Word "$value")
                   (wat* "call_ref" (Cons (id (code-type m base))
                                          (Cons implementation (append (map (lambda (name) (wat "local.get" (id name))) names)
                                                                       (list (wat "struct.get" (id base) (int 0) implementation)))))))
              (wat "global.set" (id current) (wat "local.get" (Word "$handler")))
              (wat "local.get" (Word "$value")))))

    (: host-default (-> Module Effect String (List String) (List Wat) ! mut))
    (define (host-default m info operation names)
      (let ((type (operation-type m operation)))
        (match (assoc-ref (Effect-host info) operation)
          ((Some import)
           (let* ((signature (function-signature m type))
                  (function-id (import! m import (Pair-first signature) (if (unit-type? type) (None) (Some (Pair-second signature)))))
                  (call (wat* "call" (Cons (id function-id) (map (lambda (name) (wat "local.get" (id name))) names)))))
             (if (unit-type? type) (list call (wat "i32.const" (int 0))) (list call))))
          ((None)
           (list (wat "call" (id (panic-helper m)) (string-literal m (string-append "unhandled effect operation " (short-name operation))))
                 (wat "unreachable"))))))

    ;; ---- Primitives ----

    ;; Primitives with a single Wasm instruction.
    (: instruction-primitives (List (Pair String String)))
    (define instruction-primitives
      (list (Pair "i32-add" "i32.add") (Pair "i32-sub" "i32.sub") (Pair "i32-mul" "i32.mul") (Pair "i32-quotient" "i32.div_s")
            (Pair "i32-remainder" "i32.rem_s") (Pair "i32-and" "i32.and") (Pair "i32-or" "i32.or") (Pair "i32-xor" "i32.xor")
            (Pair "i32-shift-left" "i32.shl") (Pair "i32-shift-right" "i32.shr_s") (Pair "i32-shift-right/logical" "i32.shr_u")
            (Pair "i32-eq" "i32.eq") (Pair "i32-lt" "i32.lt_s") (Pair "i32-le" "i32.le_s") (Pair "i32-gt" "i32.gt_s")
            (Pair "i32-ge" "i32.ge_s")
            (Pair "i64-add" "i64.add") (Pair "i64-sub" "i64.sub") (Pair "i64-mul" "i64.mul") (Pair "i64-quotient" "i64.div_s")
            (Pair "i64-remainder" "i64.rem_s") (Pair "i64-and" "i64.and") (Pair "i64-or" "i64.or") (Pair "i64-xor" "i64.xor")
            (Pair "i64-shift-left" "i64.shl") (Pair "i64-shift-right" "i64.shr_s") (Pair "i64-shift-right/logical" "i64.shr_u")
            (Pair "i64-eq" "i64.eq") (Pair "i64-lt" "i64.lt_s") (Pair "i64-le" "i64.le_s") (Pair "i64-gt" "i64.gt_s")
            (Pair "i64-ge" "i64.ge_s")
            (Pair "f32-add" "f32.add") (Pair "f32-sub" "f32.sub") (Pair "f32-mul" "f32.mul") (Pair "f32-div" "f32.div")
            (Pair "f32-min" "f32.min") (Pair "f32-max" "f32.max") (Pair "f32-eq" "f32.eq") (Pair "f32-lt" "f32.lt")
            (Pair "f32-le" "f32.le") (Pair "f32-gt" "f32.gt") (Pair "f32-ge" "f32.ge") (Pair "f32-sqrt" "f32.sqrt")
            (Pair "f32-abs" "f32.abs") (Pair "f32-negate" "f32.neg") (Pair "f32-floor" "f32.floor") (Pair "f32-ceiling" "f32.ceil")
            (Pair "f32-truncate" "f32.trunc") (Pair "f32-round" "f32.nearest")
            (Pair "f64-add" "f64.add") (Pair "f64-sub" "f64.sub") (Pair "f64-mul" "f64.mul") (Pair "f64-div" "f64.div")
            (Pair "f64-min" "f64.min") (Pair "f64-max" "f64.max") (Pair "f64-eq" "f64.eq") (Pair "f64-lt" "f64.lt")
            (Pair "f64-le" "f64.le") (Pair "f64-gt" "f64.gt") (Pair "f64-ge" "f64.ge") (Pair "f64-sqrt" "f64.sqrt")
            (Pair "f64-abs" "f64.abs") (Pair "f64-negate" "f64.neg") (Pair "f64-floor" "f64.floor") (Pair "f64-ceiling" "f64.ceil")
            (Pair "f64-truncate" "f64.trunc") (Pair "f64-round" "f64.nearest")
            (Pair "i32->i64" "i64.extend_i32_s") (Pair "i64->i32" "i32.wrap_i64") (Pair "i64->f64" "f64.convert_i64_s")
            (Pair "f64->i64" "i64.trunc_sat_f64_s") (Pair "i32->f64" "f64.convert_i32_s") (Pair "f64->i32" "i32.trunc_sat_f64_s")
            (Pair "i32->f32" "f32.convert_i32_s") (Pair "f32->i32" "i32.trunc_sat_f32_s") (Pair "i64->f32" "f32.convert_i64_s")
            (Pair "f32->i64" "i64.trunc_sat_f32_s") (Pair "f32->f64" "f64.promote_f32") (Pair "f64->f32" "f32.demote_f64")
            (Pair "f32->bits" "i32.reinterpret_f32") (Pair "bits->f32" "f32.reinterpret_i32")
            (Pair "f64->bits" "i64.reinterpret_f64") (Pair "bits->f64" "f64.reinterpret_i64")))

    (: index (-> Wat Wat))
    (define (index value)
      (wat "i32.wrap_i64" value))

    (: emit-primitive (-> Fn String (List Expr) Type (List Wat) ! mut))
    (define (emit-primitive fn name args type)
      (let ((operation (substring name 5 (string-length name))))
        (match (assoc-ref instruction-primitives operation)
          ((Some instruction) (list (wat* instruction (emit-args fn args))))
          ((None) (special-primitive fn operation args (emit-args fn args) (map Expr-type args) type)))))

    ;; Strings and character vectors share one representation.
    (: special-primitive (-> Fn String (List Expr) (List Wat) (List Type) Type (List Wat) ! mut))
    (define (special-primitive fn operation args code types type)
      (let* ((m (Fn-module fn))
             (arg (lambda (n) (list-ref code n)))
             (sequence (lambda (t) (reference-type (rep m t)))))
        (case operation
          (("unit") (list (wat "i32.const" (int 0))))
          (("unsafe-total") (closure-call fn (first-arg args) (Nil) #f))
          (("panic") (list (wat* "call" (Cons (id (panic-helper m)) code)) (wat "unreachable")))
          (("bool->i32" "char->i32" "i32->char" "string->vector" "vector->string" "u8->i32") code)
          (("i32->u8") (list (wat "i32.and" (arg 0) (wat "i32.const" (int 255)))))
          (("i32->bool") (list (wat "i32.ne" (arg 0) (wat "i32.const" (int 0)))))
          (("string-length" "vector-length" "array-length") (list (wat "i64.extend_i32_u" (wat "array.len" (arg 0)))))
          (("string-ref" "vector-ref" "array-ref")
           (let ((array (sequence (first-type types))))
             (list (wat (array-get array) (id array) (arg 0) (index (arg 1))))))
          (("array-set!")
           (list (wat "array.set" (id (sequence (first-type types))) (arg 0) (index (arg 1)) (arg 2)) (wat "i32.const" (int 0))))
          (("make-string" "make-vector" "make-array") (list (wat "array.new" (id (sequence type)) (arg 1) (index (arg 0)))))
          (("string-append" "vector-append") (list (wat* "call" (Cons (id (append-helper m (sequence type))) code))))
          (("substring" "subvector") (list (wat* "call" (Cons (id (slice-helper m (sequence type))) code))))
          (("vector-set") (list (wat* "call" (Cons (id (set-helper m (sequence type) (fn-rep fn (list-ref types 2)))) code))))
          (("array->vector" "vector->array") (list (wat* "call" (Cons (id (copy-helper m (sequence type))) code))))
          (("array-copy!" "vector-copy!")
           (let ((array (id (sequence (first-type types)))))
             (list (wat "array.copy" array array (arg 0) (index (arg 1)) (arg 2) (index (arg 3)) (index (arg 4))) (wat "i32.const" (int 0)))))
          (("string=?") (list (wat* "call" (Cons (id (string-equal-helper m)) code))))
          (("string-compare") (list (wat* "call" (Cons (id (string-compare-helper m)) code))))
          (("vector-generate" "string-generate")
           (list (wat* "call" (Cons (id (generate-helper m (sequence type) (list-ref types 1))) code))))
          (("ref") (list (wat* "struct.new" (Cons (id (cell-type m (fn-rep fn (first-type types)))) code))))
          (("ref-get") (list (wat* "struct.get" (Cons (id (cell-type m (fn-rep fn type))) (Cons (int 0) code)))))
          (("ref-set!")
           (list (wat* "struct.set" (Cons (id (cell-type m (fn-rep fn (list-ref types 1)))) (Cons (int 0) code))) (wat "i32.const" (int 0))))
          (else (panic (string-append "internal error: unknown primitive " operation))))))

    ;; ---- Runtime helpers ----

    ;; Helpers are fixed WAT, written once per array type and filled in from
    ;; a template. A new array needs an initial element, so empty results
    ;; come from `array.new_fixed`.
    (: helper! (-> Module String String (-> String Wat ! mut) String ! mut))
    (define (helper! m prefix key make)
      (let ((full-key (string-append prefix ":" key)))
        (match (table-ref (Module-helpers m) full-key)
          ((Some function-id) function-id)
          ((None)
           (let ((function-id (fresh-id m prefix)))
             (table-set! (Module-helpers m) full-key function-id)
             (push! (Module-functions m) (make function-id))
             function-id)))))

    (: template-helper! (-> Module String String String (List (Pair String String)) String ! mut))
    (define (template-helper! m prefix key template bindings)
      (helper! m prefix key (lambda (function-id) (Word (fill template (Cons (Pair "id" function-id) bindings))))))

    (: append-helper (-> Module String String ! mut))
    (define (append-helper m array)
      (template-helper! m "append" array
                        "(func {id} (param $a (ref {array})) (param $b (ref {array})) (result (ref {array}))
    (local $result (ref {array}))
    (if (i32.eqz (array.len (local.get $a))) (then (return (local.get $b))))
    (if (i32.eqz (array.len (local.get $b))) (then (return (local.get $a))))
    (local.set $result (array.new {array} ({get} {array} (local.get $a) (i32.const 0))
                                  (i32.add (array.len (local.get $a)) (array.len (local.get $b)))))
    (array.copy {array} {array} (local.get $result) (array.len (local.get $a)) (local.get $b) (i32.const 0)
                (array.len (local.get $b)))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
    (local.get $result))"
                        (list (Pair "array" array) (Pair "get" (array-get array)))))

    (: slice-helper (-> Module String String ! mut))
    (define (slice-helper m array)
      (template-helper! m "slice" array
                        "(func {id} (param $a (ref {array})) (param $start i64) (param $end i64) (result (ref {array}))
    (local $result (ref {array})) (local $length i32)
    (local.set $length (i32.wrap_i64 (i64.sub (local.get $end) (local.get $start))))
    (if (i32.eqz (local.get $length)) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} ({get} {array} (local.get $a) (i32.wrap_i64 (local.get $start))) (local.get $length)))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.wrap_i64 (local.get $start))
                (local.get $length))
    (local.get $result))"
                        (list (Pair "array" array) (Pair "get" (array-get array)))))

    (: copy-helper (-> Module String String ! mut))
    (define (copy-helper m array)
      (template-helper! m "copy" array
                        "(func {id} (param $a (ref {array})) (result (ref {array}))
    (local $result (ref {array}))
    (if (i32.eqz (array.len (local.get $a))) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} ({get} {array} (local.get $a) (i32.const 0)) (array.len (local.get $a))))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
    (local.get $result))"
                        (list (Pair "array" array) (Pair "get" (array-get array)))))

    (: set-helper (-> Module String Rep String ! mut))
    (define (set-helper m array element)
      (template-helper! m "set" array
                        "(func {id} (param $a (ref {array})) (param $index i64) (param $value {element}) (result (ref {array}))
    (local $result (ref {array}))
    (local.set $result (array.new {array} (local.get $value) (array.len (local.get $a))))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
    (array.set {array} (local.get $result) (i32.wrap_i64 (local.get $index)) (local.get $value))
    (local.get $result))"
                        (list (Pair "array" array) (Pair "element" (wat->text (rep->wat element))))))

    (: generate-helper (-> Module String Type String ! mut))
    (define (generate-helper m array function-type)
      (let* ((signature (function-signature m function-type)) (base (closure-type m (Pair-first signature) (Pair-second signature))))
        (template-helper! m "generate" (string-append array " " base)
                          "(func {id} (param $count i64) (param $f (ref {base})) (result (ref {array}))
    (local $result (ref {array})) (local $length i32) (local $index i32)
    (local.set $length (i32.wrap_i64 (local.get $count)))
    (if (i32.eqz (local.get $length)) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} (call_ref {code} (local.get $f) (i64.const 0) (struct.get {base} 0 (local.get $f)))
                                  (local.get $length)))
    (local.set $index (i32.const 1))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (local.get $length)))
        (array.set {array} (local.get $result) (local.get $index)
                   (call_ref {code} (local.get $f) (i64.extend_i32_u (local.get $index)) (struct.get {base} 0 (local.get $f))))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    (local.get $result))"
                          (list (Pair "array" array) (Pair "base" base) (Pair "code" (code-type m base))))))

    (: string-equal-helper (-> Module String ! mut))
    (define (string-equal-helper m)
      (let* ((array (array-type m (Scalar "i32"))) (compare (string-compare-helper m)))
        (template-helper! m "string-equal" ""
                          "(func {id} (param $a (ref {array})) (param $b (ref {array})) (result i32)
    (i32.eqz (call {compare} (local.get $a) (local.get $b))))"
                          (list (Pair "array" array) (Pair "compare" compare)))))

    ;; Lexicographic comparison by Unicode scalar: -1, 0 or 1.
    (: string-compare-helper (-> Module String ! mut))
    (define (string-compare-helper m)
      (template-helper! m "string-compare" ""
                        "(func {id} (param $a (ref {array})) (param $b (ref {array})) (result i32)
    (local $index i32) (local $x i32) (local $y i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $a))))
        (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $b))))
        (local.set $x (array.get {array} (local.get $a) (local.get $index)))
        (local.set $y (array.get {array} (local.get $b) (local.get $index)))
        (if (i32.lt_u (local.get $x) (local.get $y)) (then (return (i32.const -1))))
        (if (i32.gt_u (local.get $x) (local.get $y)) (then (return (i32.const 1))))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    (i32.sub (i32.gt_u (array.len (local.get $a)) (array.len (local.get $b)))
             (i32.lt_u (array.len (local.get $a)) (array.len (local.get $b)))))"
                        (list (Pair "array" (array-type m (Scalar "i32"))))))

    ;; Sends the message to the runtime one scalar at a time, then stops.
    (: panic-helper (-> Module String ! mut))
    (define (panic-helper m)
      (let ((character (import! m (Import "snail.library" "snail:panic/character") (list (Scalar "i32")) (None)))
            (raise (import! m (Import "snail.library" "snail:panic/raise") (Nil) (None))))
        (template-helper! m "panic" ""
                          "(func {id} (param $message (ref {array}))
    (local $index i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $message))))
        (call {character} (array.get {array} (local.get $message) (local.get $index)))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    (call {raise})
    (unreachable))"
                          (list (Pair "array" (array-type m (Scalar "i32"))) (Pair "character" character) (Pair "raise" raise)))))

    (: wat->text (-> Wat String))
    (define (wat->text wat)
      (string-concatenate (reverse (write-wat wat (Nil)))))

    ;; ---- Modules ----

    ;; Functions become Wasm functions and other definitions become globals.
    ;; `main` initializes the globals and runs the statements in program order.
    (: emit-module (-> Mono Wat ! mut))
    (define (emit-module mono)
      (let ((m (Module (Mono-program mono) (make-table) (make-table) (ref (Nil)) (ref (Nil)) (ref (Nil)) (ref (Nil)) (ref (Nil)) (ref (Nil))
                       (make-table) (make-table) (ref 0)))
            (items (Mono-items mono)))
        (for-each (lambda (item)
                    (match item
                      ((Define name value) (table-set! (Module-definitions m) name value))
                      (_ (unit))))
                  items)
        (for-each (lambda (item)
                    (match item
                      ((Define name value) (when (lambda-expr? value) (emit-function! m name value)))
                      (_ (unit))))
                  items)
        (emit-main! m items)
        (wat* "module"
              (concatenate
               (list (if (null? (ref-get (Module-types m))) (Nil) (list (wat* "rec" (reverse (ref-get (Module-types m))))))
                     (reverse (ref-get (Module-imports m)))
                     (reverse (ref-get (Module-globals m)))
                     (if (null? (ref-get (Module-declared m)))
                         (Nil)
                         (list (wat* "elem" (Cons (Word "declare") (Cons (Word "func") (map id (reverse (ref-get (Module-declared m)))))))))
                     (reverse (ref-get (Module-exports m)))
                     (reverse (ref-get (Module-functions m))))))))

    (: emit-main! (-> Module (List Item) Unit ! mut))
    (define (emit-main! m items)
      (let* ((fn (new-fn m)) (code (concatenate (map (lambda (item) (main-item-code m fn item)) items))))
        (push! (Module-functions m)
               (wat* "func" (Cons (Word "$main")
                                  (Cons (wat "export" (wat-string "main"))
                                        (Cons (wat "result" (Word "i32"))
                                              (append (reverse (ref-get (Fn-locals fn))) (append code (list (wat "i32.const" (int 0))))))))))))

    ;; A value becomes a mutable global set at startup; a statement runs and
    ;; its value is dropped; an exposed function is exported.
    (: main-item-code (-> Module Fn Item (List Wat) ! mut))
    (define (main-item-code m fn item)
      (match item
        ((Define name value)
         (if (lambda-expr? value)
             (Nil)
             (let ((r (rep m (Expr-type value))))
               (push! (Module-globals m) (wat "global" (id (wasm-id name)) (wat "mut" (nullable r)) (default-value r)))
               (list (wat "global.set" (id (wasm-id name)) (emit1 fn value))))))
        ((Do expr) (list (wat "drop" (emit1 fn expr))))
        ((Expose name symbol loc)
         (match (table-ref (Module-definitions m) name)
           ((Some definition) (unless (lambda-expr? definition) (compile-error loc "an exposed function must be defined with lambda")))
           ((None) (compile-error loc "an exposed function must be defined")))
         (push! (Module-exports m) (wat "export" (wat-string symbol) (wat "func" (id (wasm-id name)))))
         (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm)
    (import
     (lofi testing))
    (begin
      (define (test-wasm)
        (expect (mangle "a b,c(d)") "a_b~c<d>")
        (expect (fill "(call {f} {x})" (list (Pair "f" "$g") (Pair "x" "1"))) "(call $g 1)")
        (expect (wat->string (wat "module" (wat "func" (Word "$f") (wat "result" (Word "i32")) (wat "i32.const" (int 1)))))
                "(module\n  (func $f (result i32)\n    (i32.const 1)))\n")
        (expect (wat->text (wat-string "é\n")) "\"\\c3\\a9\\0a\""))))
   (else)))
