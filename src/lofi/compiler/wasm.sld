;; Monomorphic program to WasmGC text. This pass decides representations:
;; scalars are Wasm numbers, enums whose cases have no fields are i32 tags,
;; other data are GC structs (enum cases are subtypes of a tagged base),
;; sequences are GC arrays, and functions are closures holding a typed
;; function reference. Calls in tail position become `return_call`. A whole
;; program becomes one module; one library becomes a module that imports
;; what it uses from the modules of other libraries.
(define-library (lofi compiler wasm)
  (export
   emit-module
   emit-library
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

    (: field->string (-> Wat String))
    (define (field->string field)
      (string-concatenate (reverse (write-field field (Nil)))))

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

    ;; GC types are registered on first use. Functions are kept as text,
    ;; other fields as trees. `memo` caches closures for global functions, singletons and
    ;; string literals; `helpers` caches imports and helper functions by key.
    ;; A library's module names its `owner`, and `externals` holds the other
    ;; libraries' definitions it imports.
    (struct Module
      ((program Program)
       (definitions (Table Expr))
       (owner (Option String))
       (externals (Table Expr))
       (type-ids (Ref (Table String)))
       (types (Ref (List Wat)))
       (imports (Ref (List Wat)))
       (globals (Ref (List Wat)))
       (functions (Ref (List String)))
       (declared (Ref (List String)))
       (exports (Ref (List Wat)))
       (data (Ref (List Wat)))
       (memo (Ref (Table Wat)))
       (helpers (Ref (Table String)))
       (counter (Ref I64))))

    (: push! (All (T) (-> (Ref (List T)) T Unit ! mut)))
    (define (push! cell value)
      (ref-set! cell (Cons value (ref-get cell))))

    ;; Replaces a cell's table with one that maps `key` to `value`.
    (: put! (All (V) (-> (Ref (Table V)) String V Unit ! mut)))
    (define (put! cell key value)
      (ref-set! cell (table-set (ref-get cell) key value)))

    ;; A function is written out as soon as it is emitted. The module's
    ;; functions are most of its text, and holding their trees until the end
    ;; made every collection copy them.
    (: push-function! (-> Module Wat Unit ! mut))
    (define (push-function! m function)
      (push! (Module-functions m) (field->string function)))

    (: next-number! (-> Module I64 ! mut))
    (define (next-number! m)
      (let ((count (+ (ref-get (Module-counter m)) 1)))
        (ref-set! (Module-counter m) count)
        count))

    (: memoize! (-> Module String (-> Wat ! mut) Wat ! mut))
    (define (memoize! m key make)
      (match (table-ref (ref-get (Module-memo m)) key)
        ((Some value) value)
        ((None)
         (let ((value (make)))
           (put! (Module-memo m) key value)
           value))))

    ;; An import declared once: the first request for `key` declares it
    ;; under `name`, and later ones find that name.
    (: import-once! (-> Module String String (-> String Wat ! mut) String ! mut))
    (define (import-once! m key name declaration)
      (match (table-ref (ref-get (Module-helpers m)) key)
        ((Some found) found)
        ((None)
         (put! (Module-helpers m) key name)
         (push! (Module-imports m) (declaration name))
         name)))

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
        ((Scalar "funcref") (wat "ref.null" (Word "func")))
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
           (("Funcref") (Scalar "funcref"))
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
      (put! (Module-type-ids m) key type)
      (push! (Module-types m) definition)
      type)

    (: known-type (-> Module String (Option String) ! mut))
    (define (known-type m key)
      (table-ref (ref-get (Module-type-ids m)) key))

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
             (put! (Module-type-ids m) key closure)
             (put! (Module-type-ids m) (string-append "code:" closure) code)
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

    (: data-type-of (-> Module String DataType))
    (define (data-type-of m name)
      (program-type (program-of m) name))

    (: tag-enum? (-> Module String Bool))
    (define (tag-enum? m name)
      (let ((data (data-type-of m name)))
        (and (DataType-enum? data) (every? (lambda (case) (null? (Case-fields case))) (DataType-cases data)))))

    (: case-field-types (-> Module Type Case (List Type)))
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
             (put! (Module-type-ids m) key type-id)
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
      ;; Registering the base also registers its cases. Look up the case
      ;; afterwards, including when it was the first representation requested.
      (let* ((base (data-type m type))
             (key (string-append (type-key type) "." (short-name (Case-name case)))))
        (match (known-type m key)
          ((Some found) found)
          ((None)
           (let ((case-id (wasm-id key)))
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
       (access (Ref (Table Wat)))
       (reps (Ref (Table Rep)))
       (self (Option (Pair String String)))))

    (: new-fn (-> Module Fn ! mut))
    (define (new-fn m)
      (Fn m (ref (Nil)) (ref empty-table) (ref empty-table) (None)))

    (: bind-local! (-> Fn String Wat Rep Unit ! mut))
    (define (bind-local! fn name read rep)
      (put! (Fn-access fn) name read)
      (put! (Fn-reps fn) name rep))

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
      (table-ref (ref-get (Fn-access fn)) name))

    (: local? (-> Fn String Bool ! mut))
    (define (local? fn name)
      (table-contains? (ref-get (Fn-access fn)) name))

    (: fn-rep (-> Fn Type Rep ! mut))
    (define (fn-rep fn type)
      (rep (Fn-module fn) type))

    ;; A function definition: its name, parameters and result, the locals it
    ;; declared, then the body.
    (: function-wat (-> Fn String (List Wat) Rep (List Wat) Wat ! mut))
    (define (function-wat fn name params result body)
      (wat* "func" (Cons (id name) (append params (Cons (wat "result" (rep->wat result)) (append (reverse (ref-get (Fn-locals fn))) body))))))

    (: bind-params! (-> Fn (List String) (List Rep) Unit ! mut))
    (define (bind-params! fn params reps)
      (for-each (lambda (pair) (bind-local! fn (Pair-first pair) (wat "local.get" (id (wasm-id (Pair-first pair)))) (Pair-second pair)))
                (zip params reps)))

    (: param-wats (-> (List String) (List Rep) (List Wat)))
    (define (param-wats params reps)
      (map (lambda (pair) (wat "param" (id (wasm-id (Pair-first pair))) (rep->wat (Pair-second pair)))) (zip params reps)))

    (: emit-function! (-> Module String Expr Unit ! mut))
    (define (emit-function! m name function)
      (match (Expr-term function)
        ((Lambda params body)
         (let* ((fn (new-fn m)) (signature (function-signature m (Expr-type function))) (reps (Pair-first signature)))
           (bind-params! fn params reps)
           (let ((code (emit fn body #t)))
             (push-function! m (function-wat fn (wasm-id name) (param-wats params reps) (Pair-second signature) code)))))
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
          ((TypeTest inner target) (list (type-test fn inner target)))
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
        ((DBytes bytes) (bytes-literal (Fn-module fn) bytes))
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

    ;; A byte literal is a passive data segment, one byte per byte, so large
    ;; data such as images costs no more than its size. `array.new_data` is
    ;; not a constant instruction, so each evaluation copies the segment into
    ;; a fresh array; a top-level definition evaluates once.
    (: bytes-literal (-> Module Bytes Wat ! mut))
    (define (bytes-literal m bytes)
      (let ((segment (fresh-id m "bytes")))
        (push! (Module-data m) (wat "data" (id segment) (Word (bytes-wat-string bytes))))
        (wat "array.new_data" (id (array-type m (Scalar "i8"))) (id segment) (wat "i32.const" (int 0))
             (wat "i32.const" (int (vector-length bytes))))))

    ;; Every byte is a two-digit escape, so the text is three characters per
    ;; byte, generated in one pass: images make literals of millions of
    ;; bytes, too many to build from a piece of text per byte.
    (: bytes-wat-string (-> Bytes String))
    (define (bytes-wat-string bytes)
      (string-append "\""
                     (string-generate (* 3 (vector-length bytes))
                                      (lambda (index)
                                        (let ((byte (i32->i64 (u8->i32 (vector-ref bytes (quotient index 3))))))
                                          (match (remainder index 3)
                                            (0 #\\)
                                            (1 (hex-char (quotient byte 16)))
                                            (_ (hex-char (remainder byte 16)))))))
                     "\""))

    (: hex-char (-> I64 Char))
    (define (hex-char value)
      (string-ref "0123456789abcdef" value))

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
           (match (definition-of m name)
             ((Some definition)
              (cond ((lambda-expr? definition) (function-value m name type))
                    ((scalar? (fn-rep fn type)) (wat "global.get" (id (global-id m name type))))
                    (else (wat "ref.as_non_null" (wat "global.get" (id (global-id m name type)))))))
             ((None)
              (match (program-value (program-of m) name)
                ((Some (Constructor case _)) (if (null? (Case-fields case)) (construct fn case type (Nil)) (function-value m name type)))
                ((Some _) (function-value m name type))
                ((None) (panic (string-append "internal error: unknown variable " name))))))))))

    ;; A definition of this module, or one it imports from another library's.
    (: definition-of (-> Module String (Option Expr)))
    (define (definition-of m name)
      (match (table-ref (Module-definitions m) name)
        ((Some definition) (Some definition))
        ((None) (table-ref (Module-externals m) name))))

    ;; Another library's function is imported from its module, by its global
    ;; name.
    (: function-id (-> Module String String ! mut))
    (define (function-id m name)
      (match (table-ref (Module-externals m) name)
        ((Some definition)
         (let ((signature (function-signature m (Expr-type definition))))
           (import! m (Import (name-owner name) name) (Pair-first signature) (Some (Pair-second signature)))))
        ((None) (wasm-id name))))

    ;; Another library's value is a mutable global of its module, imported.
    (: global-id (-> Module String Type String ! mut))
    (define (global-id m name type)
      (if (table-contains? (Module-externals m) name)
          (import-once! m (string-append "global:" name) (wasm-id (string-append "global:" name))
                        (lambda (global) (wat "import" (wat-string (name-owner name)) (wat-string name)
                                              (wat "global" (id global) (wat "mut" (nullable (rep m type)))))))
          (wasm-id name)))

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
      (match (table-ref (ref-get (Fn-reps fn)) name)
        ((Some rep) rep)
        ((None) (panic (string-append "internal error: no representation for " name)))))

    (: lambda-function! (-> Module Expr (Option String) (List (Pair String Rep)) String String ! mut))
    (define (lambda-function! m function self captured closure)
      (match (Expr-term function)
        ((Lambda params body)
         (let* ((signature (function-signature m (Expr-type function))) (reps (Pair-first signature))
                (function-id (fresh-id m "lambda")) (base (closure-type m reps (Pair-second signature)))
                (fn (lambda-fn m self function-id base)))
           (push! (Module-declared m) function-id)
           (bind-params! fn params reps)
           (let* ((loads (capture-loads fn captured closure)) (code (emit fn body #t)))
             ;; The function's type must be the closure's code type itself,
             ;; not a structurally equal one, for `ref.func` to fit the field.
             (push-function! m
                             (function-wat fn function-id
                                           (Cons (wat "type" (id (code-type m base)))
                                                 (Cons (wat "param" (Word "$closure") (wat "ref" (id base))) (param-wats params reps)))
                                           (Pair-second signature) (append loads code)))
             function-id)))
        (_ (panic "internal error: not a lambda"))))

    ;; A recursive lambda reads its own name as its closure.
    (: lambda-fn (-> Module (Option String) String String Fn ! mut))
    (define (lambda-fn m self function-id base)
      (match self
        ((Some name)
         (let ((fn (Fn-self-set (new-fn m) (Some (Pair name function-id)))))
           (bind-local! fn name (wat "local.get" (Word "$closure")) (Reference base))
           fn))
        ((None) (new-fn m))))

    ;; On entry, each captured variable is copied from the closure to a local.
    (: capture-loads (-> Fn (List (Pair String Rep)) String (List Wat) ! mut))
    (define (capture-loads fn captured closure)
      (map-indexed (lambda (index entry)
                     (wat "local.set" (id (declare-local! fn (Pair-first entry) (Pair-second entry)))
                          (wat "struct.get" (id closure) (int (+ index 1))
                               (wat "ref.cast" (wat "ref" (id closure)) (wat "local.get" (Word "$closure"))))))
                   captured))

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
          (match (definition-of (Fn-module fn) name)
            ((Some definition)
             (if (lambda-expr? definition)
                 (list (wat* (call-op tail?) (Cons (id (function-id (Fn-module fn) name)) (emit-args fn args))))
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
          ((Some (Foreign import scheme)) (host-call m import (Scheme-type scheme) (emit-args fn args) (Expr-loc expr)))
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

    ;; ---- Host calls ----

    ;; The runtime reads only scalars. A String or Bytes argument, which must come
    ;; last, is copied into the runtime's staging buffer just before the call,
    ;; and the host receives its scalar count or byte-record address.
    ;; A Unit result is no result.
    (: host-call (-> Module Import Type (List Wat) Loc (List Wat) ! mut))
    (define (host-call m import type args loc)
      (match type
        ((TFun params result _)
         (let* ((function-id (import! m import (host-params m params loc) (if (unit-type? type) (None) (Some (rep m result)))))
                (call (wat* "call" (Cons (id function-id) (host-args m params args)))))
           (if (unit-type? type) (list call (wat "i32.const" (int 0))) (list call))))
        (_ (panic "internal error: a host function needs a function type"))))

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

    (: host-params (-> Module (List Type) Loc (List Rep) ! mut))
    (define (host-params m params loc)
      (map-indexed (lambda (index param)
                     (cond ((not (buffer-type? param)) (rep m param))
                           ((= index (- (length params) 1)) (Scalar "i32"))
                           (else (compile-error loc "a host function can take a String or Bytes only as its last argument"))))
                   params))

    (: host-args (-> Module (List Type) (List Wat) (List Wat) ! mut))
    (define (host-args m params args)
      (map (lambda (pair) (if (buffer-type? (Pair-first pair))
                              (wat "call" (id (stage-helper m (bytes-type? (Pair-first pair)))) (Pair-second pair))
                              (Pair-second pair)))
           (zip params args)))

    (: unit-type? (-> Type Bool))
    (define (unit-type? function-type)
      (match function-type
        ((TFun _ (TCon "Unit" (Nil)) _) #t)
        (_ #f)))

    ;; A function the module imports from the host or another module.
    (: import! (-> Module Import (List Rep) (Option Rep) String ! mut))
    (define (import! m import params result)
      (import-once! m (string-append "import:" (Import-module import) ":" (Import-symbol import))
                    (fresh-id m "import")
                    (lambda (function-id)
                      (wat "import" (wat-string (Import-module import)) (wat-string (Import-symbol import))
                           (wat* "func" (Cons (id function-id)
                                              (append (map (lambda (param) (wat "param" (rep->wat param))) params)
                                                      (match result ((Some r) (list (wat "result" (rep->wat r)))) ((None) (Nil))))))))))

    ;; ---- Exposed handovers ----

    ;; Inside Lofi, Option keeps its normal enum representation. Only the
    ;; exported wrapper maps None to null and Some Any to its opaque payload.
    (: exposed-value-type (-> Module Type Wat ! mut))
    (define (exposed-value-type m type)
      (if (optional-any-type? type) (nullable (Reference (any-type m))) (rep->wat (rep m type))))

    (: option-case (-> Module Bool Case))
    (define (option-case m some?)
      (match (find (lambda (case) (= (length (Case-fields case)) (if some? 1 0)))
                   (DataType-cases (data-type-of m "lofi.base:Option")))
        ((Some case) case)
        ((None) (panic "internal error: missing Option case"))))

    (: import-handover (-> Fn Type Wat Wat ! mut))
    (define (import-handover fn type value)
      (if (optional-any-type? type)
          (let ((m (Fn-module fn)))
            (wat "if" (wat "result" (rep->wat (rep m type))) (wat "ref.is_null" value)
                 (wat "then" (construct fn (option-case m #f) type (Nil)))
                 (wat "else" (construct fn (option-case m #t) type (list (wat "ref.as_non_null" value))))))
          value))

    (: export-handover (-> Fn Type Wat Wat ! mut))
    (define (export-handover fn type value)
      (if (optional-any-type? type)
          (let* ((m (Fn-module fn)) (temp (declare-temp! fn (rep->wat (rep m type))))
                 (read (wat "local.get" (id temp))) (some (case-type m type (option-case m #t))))
            (wat "block" (wat "result" (exposed-value-type m type)) (wat "local.set" (id temp) value)
                 (wat "if" (wat "result" (exposed-value-type m type))
                      (wat "i32.eq" (wat "struct.get" (id (data-type m type)) (int 0) read) (wat "i32.const" (int (Case-tag (option-case m #f)))))
                      (wat "then" (wat "ref.null" (id (any-type m))))
                      (wat "else" (wat "struct.get" (id some) (int 1) (wat "ref.cast" (wat "ref" (id some)) read))))))
          value))

    (: exposed-function (-> Module String Type String ! mut))
    (define (exposed-function m name type)
      (match type
        ((TFun params result _)
         (if (any? optional-any-type? (Cons result params)) (handover-wrapper! m name params result) (wasm-id name)))
        (_ (panic "internal error: exposed value is not a function"))))

    (: handover-wrapper! (-> Module String (List Type) Type String ! mut))
    (define (handover-wrapper! m name params result)
      (let* ((fn (new-fn m)) (wrapper (fresh-id m "exposed")) (names (map (lambda (i) (string-append "$arg." (i64->string i))) (iota (length params))))
             (args (map (lambda (pair) (import-handover fn (Pair-first pair) (wat "local.get" (id (Pair-second pair))))) (zip params names)))
             (value (export-handover fn result (wat* "call" (Cons (id (wasm-id name)) args)))))
        (push-function! m (wat* "func" (Cons (id wrapper)
                                             (append (map (lambda (pair) (wat "param" (id (Pair-second pair)) (exposed-value-type m (Pair-first pair)))) (zip params names))
                                                     (Cons (wat "result" (exposed-value-type m result))
                                                           (append (reverse (ref-get (Fn-locals fn))) (list value)))))))
        wrapper))

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
               ;; A case's own type is registered only when its fields are
               ;; read, so a field-less case never declares one.
               (let ((base (data-type m type)))
                 (Cons (wat "br_if" (id fail) (wat "i32.ne" (wat "struct.get" (id base) (int 0) value) (wat "i32.const" (int (Case-tag case)))))
                       (if (every? wild? args)
                           (Nil)
                           (let* ((case-id (case-type m type case)) (cast (declare-temp! fn (rep->wat (Reference case-id)))))
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
      (let ((r (rep m type)))
        (wat "struct.new" (id (any-type m)) (wat "i32.const" (int (any-type-id (program-of m) type)))
             (match r
               ((Scalar _) (wat "struct.new" (id (held-type m r)) value))
               ((Reference _) value)))))

    ;; A shared message has no reachable mutable storage, opaque value or
    ;; closure. Check ground arguments and declared fields; cutting recursive
    ;; declarations by name terminates even a polymorphically recursive type.
    (: shareable? (-> Module Type (List String) Bool))
    (define (shareable? m type visiting)
      (match type
        ((TCon name args)
         (and (not (member? name (list "Ref" "Array" "Any" "Funcref")))
              (every? (lambda (arg) (shareable? m arg visiting)) args)
              (or (member? name visiting)
                  (any? (lambda (entry) (string=? (Pair-first entry) name)) builtin-types)
                  (shareable-fields? m type (Cons name visiting)))))
        (_ #f)))

    (: shareable-fields? (-> Module Type (List String) Bool))
    (define (shareable-fields? m type visiting)
      (every? (lambda (case)
                (every? (lambda (field) (shareable? m field visiting)) (case-field-types m type case)))
              (DataType-cases (data-type-of m (type-name type)))))

    (: share-value (-> Module Expr Wat Wat ! mut))
    (define (share-value m expr code)
      (unless (shareable? m (Expr-type expr) (Nil))
        (compile-error (Expr-loc expr) "a shared message cannot contain mutable storage, Any or functions"))
      (to-any m (Expr-type expr) code))

    (: shared-value (-> Fn Type Loc Wat Wat ! mut))
    (define (shared-value fn type loc code)
      (unless (shareable? (Fn-module fn) type (Nil))
        (compile-error loc "a shared message cannot contain mutable storage, Any or functions"))
      (from-any fn type code))

    (: from-any (-> Fn Type Wat Wat ! mut))
    (define (from-any fn type value)
      (let* ((m (Fn-module fn)) (r (fn-rep fn type)) (any (declare-temp! fn (rep->wat (Reference (any-type m)))))
             (held (wat "ref.cast" (wat "ref" (id (held-type m r))) (wat "struct.get" (Word "$any") (int 1) (wat "local.get" (id any))))))
        (wat "block" (wat "result" (rep->wat r))
             (wat "local.set" (id any) value)
             (wat "if" (wat "i32.ne" (wat "struct.get" (Word "$any") (int 0) (wat "local.get" (id any))) (wat "i32.const" (int (any-type-id (program-of m) type))))
                  (wat "then" (wat "call" (id (panic-helper m)) (string-literal m (string-append "type-convert: the value is not a " (type->string type))))
                       (wat "unreachable")))
             (match r
               ((Scalar _) (wat "struct.get" (id (held-type m r)) (int 0) held))
               ((Reference _) held)))))

    ;; An Any holds a value of `type` when its TypeId is the type's and its
    ;; value has the type's representation, which `ref.test` checks without
    ;; trapping.
    (: type-test (-> Fn Expr Type Wat ! mut))
    (define (type-test fn inner type)
      (let* ((m (Fn-module fn)) (any (declare-temp! fn (rep->wat (Reference (any-type m)))))
             (field (lambda (index) (wat "struct.get" (Word "$any") (int index) (wat "local.get" (id any))))))
        (wat "block" (wat "result" (Word "i32"))
             (wat "local.set" (id any) (emit1 fn inner))
             (wat "if" (wat "result" (Word "i32")) (wat "i32.eq" (field 0) (wat "i32.const" (int (any-type-id (program-of m) type))))
                  (wat "then" (wat "ref.test" (wat "ref" (id (held-type m (fn-rep fn type)))) (field 1)))
                  (wat "else" (wat "i32.const" (int 0)))))))

    ;; What an Any holds for a value of representation `r`: the value, or a
    ;; box around a scalar.
    (: held-type (-> Module Rep String ! mut))
    (define (held-type m r)
      (match r
        ((Scalar _) (box-type m r))
        ((Reference type) type)))

    ;; ---- Funcref closures ----

    ;; A Funcref becomes a closure that holds it, whose code casts it to the
    ;; Wasm type of a function of the expected type and calls it. The cast is
    ;; the only check: the engine traps if the function's Wasm type differs,
    ;; and nothing compares Lofi types, which is what makes the cast unsafe.
    (: funcref-closure (-> Module Type Wat Wat ! mut))
    (define (funcref-closure m type reference)
      (match type
        ((TFun _ _ _)
         (let* ((signature (function-signature m type)) (base (closure-type m (Pair-first signature) (Pair-second signature)))
                (holder (funcref-holder-type m base)))
           (wat "struct.new" (id holder) (wat "ref.func" (id (funcref-code m signature base holder))) reference)))
        (_ (panic (string-append "unsafe-cast makes a function, not a " (type->string type))))))

    (: funcref-holder-type (-> Module String String ! mut))
    (define (funcref-holder-type m base)
      (let ((key (string-append "holder." (substring base 1 (string-length base)))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m key (wasm-id key)
                           (wat "type" (id (wasm-id key))
                                (wat "sub" (Word "final") (id base) (wat "struct" (wat "field" (wat "ref" (id (code-type m base)))) (wat "field" (Word "funcref"))))))))))

    ;; The code takes the closure and the arguments, and calls the function
    ;; the closure holds with the arguments, at that function's own type,
    ;; which takes no closure.
    (: funcref-code (-> Module (Pair (List Rep) Rep) String String String ! mut))
    (define (funcref-code m signature base holder)
      (let ((params (Pair-first signature)) (result (Pair-second signature)))
        (helper! m "funcref" holder
                 (lambda (function-id)
                   (push! (Module-declared m) function-id)
                   (wat* "func" (concatenate (list (list (id function-id) (wat "type" (id (code-type m base))) (wat "param" (wat "ref" (id base))))
                                                   (map (lambda (param) (wat "param" (rep->wat param))) params)
                                                   (list (wat "result" (rep->wat result)) (held-call m params result holder)))))))))

    (: held-call (-> Module (List Rep) Rep String Wat ! mut))
    (define (held-call m params result holder)
      (let ((own (funcref-type m params result))
            (held (wat "struct.get" (id holder) (int 1) (wat "ref.cast" (wat "ref" (id holder)) (wat "local.get" (int 0))))))
        (wat* "call_ref" (append (Cons (id own) (map (lambda (index) (wat "local.get" (int (+ index 1)))) (iota (length params))))
                                 (list (wat "ref.cast" (wat "ref" (id own)) held))))))

    ;; The Wasm type of the function a Funcref refers to, which takes no
    ;; closure.
    (: funcref-type (-> Module (List Rep) Rep String ! mut))
    (define (funcref-type m params result)
      (let ((key (string-append "funcref." (string-join (map rep-key params) ",") "->" (rep-key result))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m key (wasm-id key)
                           (wat "type" (id (wasm-id key))
                                (wat* "func" (append (map (lambda (param) (wat "param" (rep->wat param))) params) (list (wat "result" (rep->wat result)))))))))))

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
             (put! (Module-type-ids m) key type-id)
             (let ((fields (map (lambda (operation) (wat "field" (rep->wat (rep m (operation-type m operation)))))
                                (Effect-operations (program-effect (program-of m) effect)))))
               (push! (Module-types m) (wat "type" (id type-id) (wat* "struct" (append fields (list (wat "field" (wat "ref" (Word "null") (id type-id))))))))
               (declare-handler-global! m effect type-id)
               type-id))))))

    ;; In a program linked from library modules, the module of the library
    ;; that declares an effect holds its handler stack and exports it, and
    ;; the others import it.
    (: declare-handler-global! (-> Module String String Unit ! mut))
    (define (declare-handler-global! m effect type-id)
      (let ((type (wat "mut" (wat "ref" (Word "null") (id type-id)))) (symbol (string-append "handler." effect)))
        (match (Module-owner m)
          ((Some owner)
           (if (string=? owner (name-owner effect))
               (begin (push! (Module-globals m) (wat "global" (id (handler-global effect)) type (wat "ref.null" (id type-id))))
                      (push! (Module-exports m) (wat "export" (wat-string symbol) (wat "global" (id (handler-global effect))))))
               (push! (Module-imports m) (wat "import" (wat-string (name-owner effect)) (wat-string symbol) (wat "global" (id (handler-global effect)) type)))))
          ((None)
           (push! (Module-globals m) (wat "global" (id (handler-global effect)) type (wat "ref.null" (id type-id))))
           (push! (Module-exports m) (wat "export" (wat-string symbol) (wat "global" (id (handler-global effect)))))))))

    (: operation-type (-> Module String Type))
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
          ((Some import) (host-call m import type (map (lambda (name) (wat "local.get" (id name))) names) no-loc))
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
          (("unsafe-cast") (list (funcref-closure m type (arg 0))))
          (("share-value") (list (share-value m (first-arg args) (arg 0))))
          (("shared-value") (list (shared-value fn type (Expr-loc (first-arg args)) (arg 0))))
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
        (match (table-ref (ref-get (Module-helpers m)) full-key)
          ((Some function-id) function-id)
          ((None)
           (let ((function-id (fresh-id m prefix)))
             (put! (Module-helpers m) full-key function-id)
             (push-function! m (make function-id))
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

    ;; Strings transfer UTF32 scalars and return their count. Bytes transfer
    ;; a little-endian u32 length followed by packed bytes and return its
    ;; address, so a leaf host import reads memory without reentering Wasm.
    ;; stage reserves four bytes per slot: count+1 safely holds either layout.
    (: stage-helper (-> Module Bool String ! mut))
    (define (stage-helper m bytes?)
      (let ((stage (import! m (Import "snail.library" "snail:io/stage") (list (Scalar "i32")) (Some (Scalar "i32")))))
        (template-helper! m (if bytes? "stage.bytes" "stage.text") ""
                          "(func {id} (param $text (ref {array})) (result i32)
    (local $address i32) (local $index i32)
    {guard}
    (local.set $address (call {stage} {capacity}))
    {header}
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $text))))
        ({store} (i32.add (i32.add (local.get $address) (i32.const {offset})) (i32.shl (local.get $index) (i32.const {shift})))
                 ({get} {array} (local.get $text) (local.get $index)))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    {result})"
                          (list (Pair "array" (array-type m (Scalar (if bytes? "i8" "i32")))) (Pair "stage" stage)
                                (Pair "guard" (if bytes? "(if (i32.eq (array.len (local.get $text)) (i32.const -1)) (then (unreachable)))" ""))
                                (Pair "capacity" (if bytes? "(i32.add (array.len (local.get $text)) (i32.const 1))" "(array.len (local.get $text))"))
                                (Pair "header" (if bytes? "(i32.store (local.get $address) (array.len (local.get $text)))" ""))
                                (Pair "store" (if bytes? "i32.store8" "i32.store")) (Pair "get" (if bytes? "array.get_u" "array.get"))
                                (Pair "offset" (if bytes? "4" "0")) (Pair "shift" (if bytes? "0" "2"))
                                (Pair "result" (if bytes? "(local.get $address)" "(array.len (local.get $text))"))))))

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

    ;; ---- Type groups ----

    ;; Two modules share a GC type only when both declare it in identical
    ;; recursion groups, so a module puts each type in the smallest group it
    ;; can: the types that refer to one another. That group is closed under
    ;; references, so every module that uses one of its types declares all
    ;; of them; listed by name, and after the groups they refer to, they are
    ;; declared the same way everywhere. Cases of one enum with the same
    ;; fields may share a type, since a match tests the tag before it casts.
    ;; Types are numbered in the order of their names.
    (: type-groups (-> (List Wat) (List Wat) ! mut))
    (define (type-groups definitions)
      (let* ((named (fold-left (lambda (table definition) (table-set table (type-definition-name definition) definition))
                               empty-table definitions))
             (names (list->vector (sort-strings (map type-definition-name definitions))))
             (numbers (fold-left (lambda (table index) (table-set table (vector-ref names index) index)) empty-table (iota (vector-length names)))))
        (map (lambda (component) (group-wat named (map (lambda (index) (vector-ref names index)) component)))
             (strong-components (vector-map (lambda (name) (type-edges named numbers name)) names)))))

    (: type-definition-name (-> Wat String))
    (define (type-definition-name definition)
      (match definition
        ((Node (Cons _ (Cons (Word name) _))) name)
        (_ (panic "internal error: not a type definition"))))

    ;; The numbers of the types a definition refers to, in the order of
    ;; their names: its fields, parameters, results and supertype.
    (: type-edges (-> (Table Wat) (Table I64) String (List I64)))
    (define (type-edges named numbers name)
      (map (lambda (word) (table-number numbers word))
           (sort-strings (delete-duplicates string=? (filter (lambda (word) (and (not (string=? word name)) (table-contains? numbers word)))
                                                             (wat-words (table-ref-or-wat named name)))))))

    (: table-number (-> (Table I64) String I64))
    (define (table-number table key)
      (match (table-ref table key)
        ((Some number) number)
        ((None) (panic "internal error: unknown type"))))

    (: table-ref-or-wat (-> (Table Wat) String Wat))
    (define (table-ref-or-wat table key)
      (match (table-ref table key)
        ((Some value) value)
        ((None) (panic "internal error: unknown type"))))

    (: wat-words (-> Wat (List String)))
    (define (wat-words wat)
      (match wat
        ((Word text) (list text))
        ((Node items) (concatenate (map wat-words items)))))

    (: group-wat (-> (Table Wat) (List String) Wat))
    (define (group-wat named group)
      (match group
        ((Cons name (Nil)) (table-ref-or-wat named name))
        (_ (wat* "rec" (map (lambda (name) (table-ref-or-wat named name)) (sort-strings group))))))

    (: sort-strings (-> (List String) (List String)))
    (define (sort-strings strings)
      (let ((count (length strings)))
        (if (< count 2)
            strings
            (merge-strings (sort-strings (take strings (quotient count 2))) (sort-strings (drop strings (quotient count 2)))))))

    (: merge-strings (-> (List String) (List String) (List String)))
    (define (merge-strings a b)
      (match (Pair a b)
        ((Pair (Nil) _) b)
        ((Pair _ (Nil)) a)
        ((Pair (Cons x xs) (Cons y ys)) (if (string<? y x) (Cons y (merge-strings a ys)) (Cons x (merge-strings xs b))))))

    ;; ---- Modules ----

    ;; Functions become Wasm functions and other definitions become globals.
    ;; `main` initializes the globals and runs the statements in program order.
    (: emit-module (-> Mono Wat ! mut))
    (define (emit-module mono)
      (let ((m (new-module mono (None))))
        (emit-items! m (Mono-items mono))
        (module-wat m)))

    ;; A library's module also holds the handler stacks of the effects its
    ;; library declares, and exports its monomorphic definitions under their
    ;; global names, for the modules that import them. Its `main` initializes
    ;; it; the loader runs each module's in program order.
    (: emit-library (-> Mono String Wat ! mut))
    (define (emit-library mono owner)
      (let ((m (new-module mono (Some owner))))
        (for-each (lambda (effect) (handler-type m effect) (unit))
                  (sort-strings (filter (lambda (effect) (string=? (name-owner effect) owner))
                                        (table-keys (Program-effects (Mono-program mono))))))
        (emit-items! m (Mono-items mono))
        (for-each (lambda (name) (export-definition! m name)) (Mono-exported mono))
        (module-wat m)))

    (: new-module (-> Mono (Option String) Module ! mut))
    (define (new-module mono owner)
      (Module (Mono-program mono) (item-definitions (Mono-items mono)) owner (Mono-externals mono) (ref empty-table) (ref (Nil))
              (ref (Nil)) (ref (Nil)) (ref (Nil)) (ref (Nil)) (ref (Nil)) (ref (Nil)) (ref empty-table) (ref empty-table) (ref 0)))

    (: emit-items! (-> Module (List Item) Unit ! mut))
    (define (emit-items! m items)
      (for-each (lambda (item)
                  (match item
                    ((Define name value) (when (lambda-expr? value) (emit-function! m name value)))
                    (_ (unit))))
                items)
      (emit-main! m items))

    (: export-definition! (-> Module String Unit ! mut))
    (define (export-definition! m name)
      (match (table-ref (Module-definitions m) name)
        ((Some definition)
         (push! (Module-exports m) (wat "export" (wat-string name) (wat (if (lambda-expr? definition) "func" "global") (id (wasm-id name))))))
        ((None) (panic (string-append "internal error: nothing to export for " name)))))

    ;; The fields in the order Wasm requires: types in their recursion
    ;; groups, then imports, globals, declared function references, exports,
    ;; code and the data segments of byte literals. Every module imports the
    ;; runtime's linear memory, where staged text goes; once linked, the two
    ;; share it.
    (: module-wat (-> Module Wat ! mut))
    (define (module-wat m)
      (let ((declared (reverse (ref-get (Module-declared m)))))
        (wat* "module"
              (concatenate
               (list (type-groups (reverse (ref-get (Module-types m))))
                     (Cons (wat "import" (wat-string "snail.library") (wat-string "memory") (wat "memory" (int 0)))
                           (reverse (ref-get (Module-imports m))))
                     (reverse (ref-get (Module-globals m)))
                     (if (null? declared) (Nil) (list (wat* "elem" (Cons (Word "declare") (Cons (Word "func") (map id declared))))))
                     (reverse (ref-get (Module-exports m)))
                     (map Word (reverse (ref-get (Module-functions m))))
                     (reverse (ref-get (Module-data m))))))))

    (: emit-main! (-> Module (List Item) Unit ! mut))
    (define (emit-main! m items)
      (let* ((fn (new-fn m)) (code (concatenate (map (lambda (item) (main-item-code m fn item)) items))))
        (push-function! m
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
         (match (definition-of m name)
           ((Some definition)
            (unless (lambda-expr? definition) (compile-error loc "an exposed function must be defined with lambda"))
            (push! (Module-exports m)
                   (wat "export" (wat-string symbol) (wat "func" (id (exposed-function m name (Expr-type definition)))))))
           ((None) (compile-error loc "an exposed function must be defined")))
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
