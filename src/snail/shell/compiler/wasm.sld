;; Monomorphic program to WasmGC text. This pass decides representations:
;; scalars are Wasm numbers, enums whose cases have no fields are i32 tags,
;; other data are GC structs (enum cases are subtypes of a tagged base),
;; sequences are GC arrays, and functions are closures holding a typed
;; function reference. Calls in tail position become `return_call`. A whole
;; program becomes one module; one library becomes a module that imports
;; what it uses from the modules of other libraries. A control operation
;; leaves a record in one global, which each caller tests after a call that
;; may yield, saving the rest of its work as a frame, back to the handle it
;; is aimed at; `resume` runs those frames again.
(define-library (snail shell compiler wasm)
  (export
   emit-module
   emit-library
   emit-control-module
   wat->string)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (snail shell compiler mono)
   (snail shell compiler control))
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
          (reverse (Cons ")\n"
                         (fold-left (lambda (pieces field) (write-field field (Cons "\n  " pieces)))
                                    (list "(module")
                                    fields)))))
        (_ (panic "internal error: not a module"))))

    (: field->string (-> Wat String))
    (define (field->string field)
      (string-concatenate (reverse (write-field field (Nil)))))

    (: write-field (-> Wat (List String) (List String)))
    (define (write-field field pieces)
      (match field
        ((Node (Cons (Word head) parts))
         (if (or (string=? head "func") (string=? head "rec"))
             (Cons ")"
                   (fold-left (lambda (pieces part)
                                (write-wat part
                                           (Cons (if (own-line? head part) "\n    " " ") pieces)))
                              (Cons head (Cons "(" pieces)) parts))
             (write-wat field pieces)))
        (_ (write-wat field pieces))))

    (: own-line? (-> String Wat Bool))
    (define (own-line? head part)
      (match part
        ((Node (Cons (Word inner) _))
         (or (string=? head "rec")
             (not (member? inner (list "type" "param" "result" "local" "export")))))
        (_ #f)))

    ;; Pieces accumulate in reverse.
    (: write-wat (-> Wat (List String) (List String)))
    (define (write-wat wat pieces)
      (match wat
        ((Word text) (Cons text pieces))
        ((Node (Nil)) (Cons "()" pieces))
        ((Node (Cons first rest))
         (Cons ")"
               (fold-left (lambda (pieces item) (write-wat item (Cons " " pieces)))
                          (write-wat first (Cons "(" pieces))
                          rest)))))

    ;; Wasm strings are UTF-8 bytes; anything beyond printable ASCII is escaped.
    (: wat-string (-> String Wat))
    (define (wat-string text)
      (Word (string-append "\"" (string-concatenate (map escape-char (string->list text))) "\"")))

    (: escape-char (-> Char String))
    (define (escape-char c)
      (let ((code (char->integer c)))
        (if (and (>= code 32) (< code 127) (not (= code 34)) (not (= code 92)))
            (list->string (list c))
            (string-concatenate (map (lambda (byte)
                                       (string-append "\\"
                                                      (hex-digit (quotient byte 16))
                                                      (hex-digit (remainder byte 16))))
                                     (utf-8-bytes code))))))

    (: hex-digit (-> I64 String))
    (define (hex-digit value)
      (substring "0123456789abcdef" value (+ value 1)))

    (: utf-8-bytes (-> I64 (List I64)))
    (define (utf-8-bytes code)
      (cond ((< code 128) (list code))
            ((< code 2048) (list (+ 192 (quotient code 64)) (+ 128 (remainder code 64))))
            ((< code 65536)
             (list (+ 224 (quotient code 4096))
                   (+ 128 (remainder (quotient code 64) 64))
                   (+ 128 (remainder code 64))))
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
               ((Some value) (loop (list-drop rest (+ (string-length name) 1)) (Cons value pieces)))
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
    ;; libraries' definitions it imports. `callees` describes what the
    ;; module's calls reach when the program has control effects, so that
    ;; some call may yield.
    (struct Module
      ((program Program)
       (definitions (Table Expr))
       (owner (Option String))
       (externals (Table Expr))
       (type-ids (Ref (Table String)))
       (types (Ref (List Wat)))
       (imports (Ref (List Wat)))
       (globals (Ref (List Wat)))
       (functions (Ref (List (Pair String String))))
       (declared (Ref (List String)))
       (exports (Ref (List Wat)))
       (data (Ref (List Wat)))
       (memo (Ref (Table Wat)))
       (helpers (Ref (Table String)))
       (callees (Option Callees))))

    (: push! (All (T) (requires (Copy T)) (-> (Ref (List T)) T Unit ! mut)))
    (define (push! cell value)
      (ref-set! cell (Cons value (ref-get cell))))

    ;; Replaces a cell's table with one that maps `key` to `value`.
    (: put! (All (V) (requires (Copy V)) (-> (Ref (Table V)) String V Unit ! mut)))
    (define (put! cell key value)
      (ref-set! cell (table-set (ref-get cell) key value)))

    ;; A function is written out as soon as it is emitted. The module's
    ;; functions are most of its text, and holding their trees until the end
    ;; made every collection copy them.
    (: push-function! (-> Module String Wat Unit ! mut))
    (define (push-function! m name function)
      (push! (Module-functions m) (Pair name (field->string function))))

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

    ;; A name derived from what it names, so the text comes out the same
    ;; whichever order a host evaluated the emission in: the prefix, then
    ;; FNV-1a of the key. Declarations are kept once per full key, so two
    ;; keys with one hash would surface as a duplicate declaration the
    ;; assembler rejects, never as wrong code.
    (: keyed-id (-> String String String))
    (define (keyed-id prefix key)
      (wasm-id (string-append prefix "." (i64->string (fnv-1a key)))))

    ;; A name that extends another's: a closure's global extends its code.
    (: derived-id (-> String String String))
    (define (derived-id prefix id)
      (wasm-id (string-append prefix "." (substring id 1 (string-length id)))))

    ;; FNV-1a over a tree's words in order, with a separator per word and
    ;; per node, so `(a b)` and `(a (b))` differ.
    (: wat-hash (-> I64 Wat I64))
    (define (wat-hash hash tree)
      (match tree
        ((Word text)
         (vector-fold (lambda (h c) (fnv-step h (char->integer c)))
                      (fnv-step hash 32)
                      (string->vector text)))
        ((Node items) (fold-left wat-hash (fnv-step hash 40) items))))

    (: wat=? (-> Wat Wat Bool))
    (define (wat=? a b)
      (match (Pair a b)
        ((Pair (Word x) (Word y)) (string=? x y))
        ((Pair (Node xs) (Node ys))
         (and (= (length xs) (length ys))
              (every? (lambda (pair) (wat=? (Pair-first pair) (Pair-second pair))) (zip xs ys))))
        (_ #f)))

    (: wat-rename (-> String String Wat Wat))
    (define (wat-rename from to tree)
      (match tree
        ((Word text) (if (string=? text from) (Word to) tree))
        ((Node items) (Node (map (lambda (item) (wat-rename from to item)) items)))))

    ;; A declaration's name: an export's exported name, else its first `$id`.
    (: declaration-id (-> Wat String))
    (define (declaration-id declaration)
      (match declaration
        ((Node (Cons (Word "export") (Cons (Word name) _))) name)
        (_ (match (first-id declaration)
             ((Some name) name)
             ((None) (panic "internal error: a declaration without a name"))))))

    (: first-id (-> Wat (Option String)))
    (define (first-id tree)
      (match tree
        ((Word text)
         (if (and (> (string-length text) 0) (char=? (string-ref text 0) #\$)) (Some text) (None)))
        ((Node items)
         (fold-left (lambda (found item) (match found ((Some _) found) ((None) (first-id item))))
                    (ann (None) (Option String))
                    items))))

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
      (if (linear-type? (program-of m) (Nil) type)
          (Reference (owned-type m))
          (unrestricted-rep m type)))

    (: unrestricted-rep (-> Module Type Rep ! mut))
    (define (unrestricted-rep m type)
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
        ((TFun params result _)
         (Reference (closure-type m (map (lambda (param) (rep m param)) params) (rep m result))))
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
          ((None)
           (register-type! m
                           key
                           (wasm-id key)
                           (wat "type"
                                (id (wasm-id key))
                                (wat "array" (wat "mut" (rep->wat element)))))))))

    (: cell-type (-> Module Rep String ! mut))
    (define (cell-type m content)
      (let ((key (string-append "cell." (rep-key content))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m
                           key
                           (wasm-id key)
                           (wat "type"
                                (id (wasm-id key))
                                (wat "struct" (wat "field" (wat "mut" (rep->wat content))))))))))

    ;; A closure is a struct whose first field is its code. Each lambda with
    ;; captured variables extends the base struct with their fields.
    (: closure-type (-> Module (List Rep) Rep String ! mut))
    (define (closure-type m params result)
      (let* ((signature
              (string-append (string-join (map rep-key params) ",") "->" (rep-key result)))
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
                                                             (Cons (wat "param" (evidence-ref m))
                                                                   (map (lambda (param)
                                                                          (wat "param"
                                                                               (rep->wat param)))
                                                                        params)))
                                                       (list (wat "result" (rep->wat result)))))))
             (register-type! m
                             key
                             closure
                             (wat "type"
                                  (id closure)
                                  (wat "sub"
                                       (wat "struct" (wat "field" (wat "ref" (id code))))))))))))

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
        (and (DataType-enum? data)
             (every? (lambda (case) (null? (Case-fields case))) (DataType-cases data)))))

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
                 (begin
                   (push! (Module-types m)
                          (wat "type"
                               (id type-id)
                               (wat "sub" (wat "struct" (wat "field" (Word "i32"))))))
                   (for-each (lambda (case) (case-type m type case) (unit))
                             (filter (lambda (case) (not (null? (Case-fields case))))
                                     (DataType-cases data))))
                 (match (DataType-cases data)
                   ((Cons case _)
                    (push! (Module-types m)
                           (wat "type" (id type-id) (wat* "struct" (case-fields m type case)))))
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
                                  (wat "sub"
                                       (Word "final")
                                       (id base)
                                       (wat* "struct"
                                             (Cons (wat "field" (Word "i32"))
                                                   (case-fields m type case)))))))))))

    ;; ---- Functions ----

    ;; `access` maps each visible local name to the instruction that reads it,
    ;; and `reps` to its representation. In a recursive lambda, `self` pairs
    ;; its own name with its Wasm function, so it can call itself directly.
    ;; `exit` is where a yield leaves the code being emitted (see Control).
    (struct Fn
      ((module Module)
       (locals (Ref (List Wat)))
       (access (Ref (Table Wat)))
       (reps (Ref (Table Rep)))
       (self (Option (Pair String String)))
       (names (Ref I64))
       (evidence Wat)
       (exit (Option Exit))))

    ;; A function's evidence is its `$ev` parameter, the handlers in scope at
    ;; the call; a `handle` body reads the node it installed instead.
    (: new-fn (-> Module Fn ! mut))
    (define (new-fn m)
      (Fn m
          (ref (Nil))
          (ref empty-table)
          (ref empty-table)
          (None)
          (ref 0)
          (wat "local.get" (Word "$ev"))
          (None)))

    ;; Temporaries and labels are numbered within their function, so a name
    ;; depends on nothing outside the body it appears in.
    (: local-id (-> Fn String String ! mut))
    (define (local-id fn prefix)
      (let ((count (+ (ref-get (Fn-names fn)) 1)))
        (ref-set! (Fn-names fn) count)
        (wasm-id (string-append prefix "." (i64->string count)))))

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
      (let ((local (local-id fn "tmp")))
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
      (wat* "func"
            (Cons (id name)
                  (append params
                          (Cons (wat "result" (rep->wat result))
                                (append (reverse (ref-get (Fn-locals fn))) body))))))

    (: bind-params! (-> Fn (List String) (List Rep) Unit ! mut))
    (define (bind-params! fn params reps)
      (for-each (lambda (pair)
                  (bind-local! fn
                               (Pair-first pair)
                               (wat "local.get" (id (wasm-id (Pair-first pair))))
                               (Pair-second pair)))
                (zip params reps)))

    (: param-wats (-> (List String) (List Rep) (List Wat)))
    (define (param-wats params reps)
      (map
       (lambda (pair) (wat "param" (id (wasm-id (Pair-first pair))) (rep->wat (Pair-second pair))))
       (zip params reps)))

    (: emit-function! (-> Module String Expr Unit ! mut))
    (define (emit-function! m name function)
      (match (Expr-term function)
        ((Lambda params body)
         (let* ((fn (Fn-exit-set (new-fn m) (function-exit (Expr-type function))))
                (signature (function-signature m (Expr-type function)))
                (reps (Pair-first signature)))
           (bind-params! fn params reps)
           (let ((code (emit fn body #t)))
             (push-function! m (wasm-id name)
                             (function-wat fn
                                           (wasm-id name)
                                           (Cons (evidence-param m) (param-wats params reps))
                                           (Pair-second signature)
                                           code)))))
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
           (let* ((test-code (emit1 fn test))
                  (then-code (emit fn then tail?))
                  (else-code (emit fn otherwise tail?)))
             (list (wat "if"
                        (wat "result" (rep->wat (fn-rep fn type)))
                        test-code
                        (wat* "then" then-code)
                        (wat* "else" else-code)))))
          ((Let name value body) (emit-let fn name value body tail?))
          ((Seq first rest)
           (let ((first-code (emit1 fn first)))
             (Cons (wat "drop" first-code) (emit fn rest tail?))))
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
        ((DFloat text)
         (wat (string-append (rep-key (fn-rep fn type)) ".const") (Word (float-text text))))))

    ;; WAT needs a digit before a decimal point, as in `0.5` or `-0.5`.
    (: float-text (-> String String))
    (define (float-text text)
      (cond
       ((and (> (string-length text) 0) (char=? (string-ref text 0) #\.)) (string-append "0" text))
       ((and (> (string-length text) 1) (char=? (string-ref text 1) #\.)
             (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
        (string-append (substring text 0 1) "0" (substring text 1 (string-length text))))
       (else text)))

    ;; String literals are immutable globals, built once.
    (: string-literal (-> Module String Wat ! mut))
    (define (string-literal m text)
      (memoize! m (string-append "string:" text)
                (lambda ()
                  (let ((global (keyed-id "string" text)) (array (array-type m (Scalar "i32"))))
                    (push! (Module-globals m)
                           (wat "global" (id global) (wat "ref" (id array))
                                (wat* "array.new_fixed"
                                      (Cons (id array)
                                            (Cons (int (string-length text))
                                                  (map (lambda (c)
                                                         (wat "i32.const" (int (char->integer c))))
                                                       (string->list text)))))))
                    (wat "global.get" (id global))))))

    ;; A byte literal is a passive data segment, one byte per byte, so large
    ;; data such as images costs no more than its size. `array.new_data` is
    ;; not a constant instruction, so each evaluation copies the segment into
    ;; a fresh array; a top-level definition evaluates once.
    (: bytes-literal (-> Module Bytes Wat ! mut))
    (define (bytes-literal m bytes)
      (let ((text (bytes-wat-string bytes)))
        (memoize! m (string-append "bytes:" text)
                  (lambda ()
                    (let ((segment (keyed-id "bytes" text)))
                      (push! (Module-data m) (wat "data" (id segment) (Word text)))
                      (wat "array.new_data"
                           (id (array-type m (Scalar "i8")))
                           (id segment)
                           (wat "i32.const" (int 0))
                           (wat "i32.const" (int (vector-length bytes)))))))))

    ;; Every byte is a two-digit escape, so the text is three characters per
    ;; byte, generated in one pass: images make literals of millions of
    ;; bytes, too many to build from a piece of text per byte.
    (: bytes-wat-string (-> Bytes String))
    (define (bytes-wat-string bytes)
      (string-append "\""
                     (string-generate (* 3 (vector-length bytes))
                                      (lambda (index)
                                        (let ((byte (i32->i64 (u8->i32 (vector-ref bytes
                                                                                   (quotient index
                                                                                             3))))))
                                          (match (remainder index 3)
                                            (0 #\\)
                                            (1 (hex-char (quotient byte 16)))
                                            (_ (hex-char (remainder byte 16)))))))
                     "\""))

    (: hex-char (-> I64 Char))
    (define (hex-char value)
      (string-ref "0123456789abcdef" value))

    ;; A let whose value may yield tests for the yield before its body.
    (: emit-let (-> Fn String Expr Expr Bool (List Wat) ! mut))
    (define (emit-let fn name value body tail?)
      (let* ((code (if (and (lambda-expr? value) (member? name (expr-references value)))
                       (closure fn value (Some name))
                       (emit-let-value fn value)))
             (local (declare-local! fn name (fn-rep fn (Expr-type value)))))
        (Cons (wat "local.set" (id local) code) (let-rest fn name value body tail?))))

    ;; ---- Variables ----

    ;; A global function or operation used as a value becomes a closure.
    (: variable (-> Fn String Type Wat ! mut))
    (define (variable fn name type)
      (let ((m (Fn-module fn)))
        (match (local-access fn name)
          ((Some access) (move-value m (capture-rep fn name) access))
          ((None)
           (match (definition-of m name)
             ((Some definition)
              (cond ((lambda-expr? definition) (function-value m name type))
                    ((scalar? (fn-rep fn type)) (wat "global.get" (id (global-id m name type))))
                    (else (wat "ref.as_non_null" (wat "global.get" (id (global-id m name type)))))))
             ((None)
              (match (program-value (program-of m) name)
                ((Some (Constructor case _))
                 (if (null? (Case-fields case))
                     (construct fn case type (Nil))
                     (function-value m name type)))
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
           (import! m
                    (Import (name-owner name) name)
                    (Cons (evidence-rep m) (Pair-first signature))
                    (Some (Pair-second signature)))))
        ((None) (wasm-id name))))

    ;; Another library's value is a mutable global of its module, imported.
    (: global-id (-> Module String Type String ! mut))
    (define (global-id m name type)
      (if (table-contains? (Module-externals m) name)
          (import-once! m (string-append "global:" name) (wasm-id (string-append "global:" name))
                        (lambda (global)
                          (wat "import" (wat-string (name-owner name)) (wat-string name)
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
                     (let* ((names
                             (map (lambda (index) (string-append "argument." (i64->string index)))
                                  (iota (length params))))
                            (call (Expr (App (Expr (Var name (Nil) (Nil)) type no-loc)
                                             (map (lambda (pair)
                                                    (Expr (Var (Pair-first pair) (Nil) (Nil))
                                                          (Pair-second pair)
                                                          no-loc))
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
             (code (lambda-function! m function self (Nil) base)))
        (memoize! m (string-append "closure-value:" code)
                  (lambda ()
                    (let ((global (derived-id "closure" code)))
                      (push! (Module-globals m)
                             (wat "global"
                                  (id global)
                                  (wat "ref" (id base))
                                  (wat "struct.new" (id base) (wat "ref.func" (id code)))))
                      (wat "global.get" (id global)))))))

    (: closure-with-captures (-> Fn Expr (Option String) (List String) Wat ! mut))
    (define (closure-with-captures fn function self captured)
      (let* ((m (Fn-module fn)) (signature (function-signature m (Expr-type function)))
             (base (closure-type m (Pair-first signature) (Pair-second signature)))
             (reps (map (lambda (name) (capture-rep fn name)) captured))
             (subtype (capture-type m base reps))
             (code (lambda-function! m function self (zip captured reps) subtype)))
        (wat* "struct.new"
              (Cons (id subtype)
                    (Cons (wat "ref.func" (id code))
                          (map (lambda (name) (variable fn name unchecked)) captured))))))

    ;; The captures extend the base struct with their fields. Closures with
    ;; one base and one list of representations share the subtype.
    (: capture-type (-> Module String (List Rep) String ! mut))
    (define (capture-type m base reps)
      (let ((name (wasm-id (string-append (substring base 1 (string-length base))
                                          "+"
                                          (string-join (map rep-key reps) ",")))))
        (match (known-type m name)
          ((Some type) type)
          ((None)
           (register-type! m name name
                           (wat "type" (id name)
                                (wat "sub" (Word "final") (id base)
                                     (wat* "struct"
                                           (Cons (wat "field" (wat "ref" (id (code-type m base))))
                                                 (map (lambda (r) (wat "field" (rep->wat r)))
                                                      reps))))))))))

    (: capture-rep (-> Fn String Rep ! mut))
    (define (capture-rep fn name)
      (match (table-ref (ref-get (Fn-reps fn)) name)
        ((Some rep) rep)
        ((None) (panic (string-append "internal error: no representation for " name)))))

    (: lambda-function!
       (-> Module Expr (Option String) (List (Pair String Rep)) String String ! mut))
    (define (lambda-function! m function self captured closure)
      (match (Expr-term function)
        ((Lambda params body)
         (let* ((signature (function-signature m (Expr-type function)))
                (reps (Pair-first signature))
                (base (closure-type m reps (Pair-second signature)))
                (fn (Fn-exit-set (lambda-fn m self "$lambda.self" base)
                                 (function-exit (Expr-type function)))))
           (bind-params! fn params reps)
           (let* ((loads (capture-loads fn captured closure)) (code (emit fn body #t))
                  ;; The function's type must be the closure's code type itself,
                  ;; not a structurally equal one, for `ref.func` to fit the field.
                  (draft (function-wat fn "$lambda.self"
                                       (Cons (wat "type" (id (code-type m base)))
                                             (Cons
                                              (wat "param" (Word "$closure") (wat "ref" (id base)))
                                              (Cons (evidence-param m) (param-wats params reps))))
                                       (Pair-second signature) (append loads code))))
             (lambda-id m "lambda" draft 0))))
        (_ (panic "internal error: not a lambda"))))

    ;; A lambda, or a join function, is named by the hash of its own text,
    ;; written with its name as a placeholder, so identical lambdas share one
    ;; function and a name depends on nothing but the body. Two different
    ;; lambdas with one hash take the next salt, the one place a name can
    ;; still depend on the order of emission.
    (: lambda-id (-> Module String Wat I64 String ! mut))
    (define (lambda-id m prefix draft salt)
      (let* ((hash (i64->string (wat-hash fnv-offset draft)))
             (name (wasm-id (string-append prefix
                                           "."
                                           hash
                                           (if (= salt 0)
                                               ""
                                               (string-append "." (i64->string salt))))))
             (key (string-append "lambda:" name)))
        (match (table-ref (ref-get (Module-memo m)) key)
          ((Some stored) (if (wat=? stored draft) name (lambda-id m prefix draft (+ salt 1))))
          ((None)
           (put! (Module-memo m) key draft)
           (push! (Module-declared m) name)
           (push-function! m name (wat-rename "$lambda.self" name draft))
           name))))

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
                     (wat "local.set"
                          (id (declare-local! fn (Pair-first entry) (Pair-second entry)))
                          (wat "struct.get" (id closure) (int (+ index 1))
                               (wat "ref.cast"
                                    (wat "ref" (id closure))
                                    (wat "local.get" (Word "$closure"))))))
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
                (list (wat* (call-op tail?)
                            (Cons (id function-id)
                                  (Cons (wat "local.get" (Word "$closure"))
                                        (Cons (Fn-evidence fn) (emit-args fn args))))))
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
                 (list (wat* (call-op tail?)
                             (Cons (id (function-id (Fn-module fn) name))
                                   (Cons (Fn-evidence fn) (emit-args fn args)))))
                 (closure-call fn callee args tail?)))
            ((None) (builtin-call fn expr name args)))))

    (: builtin-call (-> Fn Expr String (List Expr) (List Wat) ! mut))
    (define (builtin-call fn expr name args)
      (let ((m (Fn-module fn)))
        (match (program-value (program-of m) name)
          ((Some (Constructor case _))
           (list (construct fn case (Expr-type expr) (emit-args fn args))))
          ((Some (Accessor case index _)) (list (field-access fn case index (first-arg args))))
          ((Some (Replacer case index _))
           (list (replace-field fn case index (first-arg args) (list-ref args 1))))
          ((Some (Primitive _)) (emit-primitive fn name args (Expr-type expr)))
          ((Some (Operation effect _))
           (list (wat* "call"
                       (Cons (id (performer m effect name))
                             (Cons (Fn-evidence fn) (emit-args fn args))))))
          ((Some (Foreign import scheme))
           (host-call m import (Scheme-type scheme) (emit-args fn args) (Expr-loc expr)))
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
      (match (Expr-type callee)
        ((TCon "Once" (Cons procedure (Nil))) (once-call fn callee procedure args tail?))
        (_ (plain-closure-call fn callee args tail?))))

    ;; Calling a `Once` takes its procedure out of the owner, which traps if
    ;; it was taken already, and calls it.
    (: once-call (-> Fn Expr Type (List Expr) Bool (List Wat) ! mut))
    (define (once-call fn callee procedure args tail?)
      (let* ((m (Fn-module fn)) (signature (function-signature m procedure))
             (base (closure-type m (Pair-first signature) (Pair-second signature)))
             (owner (emit1 fn callee))
             (arguments (emit-args fn args))
             (temp (declare-temp! fn (rep->wat (Reference base)))))
        (list (wat "local.set"
                   (id temp)
                   (wat "ref.cast"
                        (wat "ref" (id base))
                        (wat "call" (id (take-owned-helper m)) owner)))
              (closure-call-wat m
                                base
                                (wat "local.get" (id temp))
                                (Cons (Fn-evidence fn) arguments)
                                tail?))))

    (: plain-closure-call (-> Fn Expr (List Expr) Bool (List Wat) ! mut))
    (define (plain-closure-call fn callee args tail?)
      (let* ((m (Fn-module fn)) (signature (function-signature m (Expr-type callee)))
             (base (closure-type m (Pair-first signature) (Pair-second signature)))
             (value (emit1 fn callee)))
        (if (variable-read? value)
            (list (closure-call-wat m base value (Cons (Fn-evidence fn) (emit-args fn args)) tail?))
            (let ((temp (declare-temp! fn (rep->wat (Reference base)))))
              (list (wat "local.set" (id temp) value)
                    (closure-call-wat m
                                      base
                                      (wat "local.get" (id temp))
                                      (Cons (Fn-evidence fn) (emit-args fn args))
                                      tail?))))))

    ;; The arguments begin with the evidence.
    (: closure-call-wat (-> Module String Wat (List Wat) Bool Wat ! mut))
    (define (closure-call-wat m base read args tail?)
      (wat* (if tail? "return_call_ref" "call_ref")
            (Cons (id (code-type m base))
                  (Cons read (append args (list (wat "struct.get" (id base) (int 0) read)))))))

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
      (let ((value (construct-data fn case type args)))
        (if (linear-type? (program-of (Fn-module fn)) (Nil) type)
            (wat "struct.new" (id (owned-type (Fn-module fn))) value)
            value)))

    (: construct-data (-> Fn Case Type (List Wat) Wat ! mut))
    (define (construct-data fn case type args)
      (let* ((m (Fn-module fn)) (name (Case-type case)))
        (cond ((tag-enum? m name) (wat "i32.const" (int (Case-tag case))))
              ((not (DataType-enum? (data-type-of m name)))
               (wat* "struct.new" (Cons (id (data-type m type)) args)))
              ((null? args) (singleton m type case))
              (else (wat* "struct.new"
                          (Cons (id (case-type m type case))
                                (Cons (wat "i32.const" (int (Case-tag case))) args)))))))

    (: singleton (-> Module Type Case Wat ! mut))
    (define (singleton m type case)
      (let ((key (string-append (type-key type) ":" (Case-name case))))
        (memoize! m (string-append "singleton:" key)
                  (lambda ()
                    (let ((global (keyed-id "value" key)) (base (data-type m type)))
                      (push! (Module-globals m)
                             (wat "global"
                                  (id global)
                                  (wat "ref" (id base))
                                  (wat "struct.new"
                                       (id base)
                                       (wat "i32.const" (int (Case-tag case))))))
                      (wat "global.get" (id global)))))))

    (: field-access (-> Fn Case I64 Expr Wat ! mut))
    (define (field-access fn case index value)
      (let* ((m (Fn-module fn)) (type (Expr-type value)))
        (if (DataType-enum? (data-type-of m (Case-type case)))
            (let ((case-id (case-type m type case)))
              (wat "struct.get"
                   (id case-id)
                   (int (+ index 1))
                   (wat "ref.cast" (wat "ref" (id case-id)) (emit1 fn value))))
            (wat "struct.get" (id (data-type m type)) (int index) (emit1 fn value)))))

    (: replace-field (-> Fn Case I64 Expr Expr Wat ! mut))
    (define (replace-field fn case index value replacement)
      (let* ((m (Fn-module fn))
             (type-id (data-type m (Expr-type value)))
             (temp (declare-temp! fn (rep->wat (Reference type-id)))))
        (wat "block" (wat "result" (wat "ref" (id type-id)))
             (wat "local.set" (id temp) (emit1 fn value))
             (wat* "struct.new"
                   (Cons (id type-id)
                         (map (lambda (i)
                                (if (= i index)
                                    (emit1 fn replacement)
                                    (wat "struct.get"
                                         (id type-id)
                                         (int i)
                                         (wat "local.get" (id temp)))))
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
         (let* ((function-id (import! m
                                      import
                                      (host-params m params loc)
                                      (if (unit-type? type) (None) (Some (rep m result)))))
                (call (wat* "call" (Cons (id function-id) (host-args m params args)))))
           (if (unit-type? type) (list call (wat "i32.const" (int 0))) (list call))))
        (_ (panic "internal error: a host function needs a function type"))))

    (: host-params (-> Module (List Type) Loc (List Rep) ! mut))
    (define (host-params m params loc)
      (map-indexed (lambda (index param)
                     (cond ((not (buffer-type? param)) (rep m param))
                           ((= index (- (length params) 1)) (Scalar "i32"))
                           (else
                            (panic
                             "internal error: a host function's buffer is not its last argument"))))
                   params))

    (: host-args (-> Module (List Type) (List Wat) (List Wat) ! mut))
    (define (host-args m params args)
      (map (lambda (pair) (if (buffer-type? (Pair-first pair))
                              (wat "call"
                                   (id (stage-helper m (bytes-type? (Pair-first pair))))
                                   (Pair-second pair))
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
                    (wasm-id
                     (string-append "import." (Import-module import) ":" (Import-symbol import)))
                    (lambda (function-id)
                      (wat "import"
                           (wat-string (Import-module import))
                           (wat-string (Import-symbol import))
                           (wat* "func" (Cons (id function-id)
                                              (append
                                               (map (lambda (param) (wat "param" (rep->wat param)))
                                                    params)
                                               (match result
                                                 ((Some r) (list (wat "result" (rep->wat r))))
                                                 ((None) (Nil))))))))))

    ;; ---- Exposed handovers ----

    ;; Inside Snail-Core, Option keeps its normal enum representation. Only the
    ;; exported wrapper maps None to null and Some Any to its opaque payload.
    (: exposed-value-type (-> Module Type Wat ! mut))
    (define (exposed-value-type m type)
      (if (optional-any-type? type) (nullable (Reference (any-type m))) (rep->wat (rep m type))))

    (: option-case (-> Module Bool Case))
    (define (option-case m some?)
      (match (find (lambda (case) (= (length (Case-fields case)) (if some? 1 0)))
                   (DataType-cases (data-type-of m "snail.core.base:Option")))
        ((Some case) case)
        ((None) (panic "internal error: missing Option case"))))

    (: import-handover (-> Fn Type Wat Wat ! mut))
    (define (import-handover fn type value)
      (if (optional-any-type? type)
          (let ((m (Fn-module fn)))
            (wat "if" (wat "result" (rep->wat (rep m type))) (wat "ref.is_null" value)
                 (wat "then" (construct fn (option-case m #f) type (Nil)))
                 (wat "else"
                      (construct fn (option-case m #t) type (list (wat "ref.as_non_null" value))))))
          value))

    (: export-handover (-> Fn Type Wat Wat ! mut))
    (define (export-handover fn type value)
      (if (optional-any-type? type)
          (let* ((m (Fn-module fn)) (temp (declare-temp! fn (rep->wat (rep m type))))
                 (read (wat "local.get" (id temp))) (some (case-type m type (option-case m #t))))
            (wat "block"
                 (wat "result" (exposed-value-type m type))
                 (wat "local.set" (id temp) value)
                 (wat "if" (wat "result" (exposed-value-type m type))
                      (wat "i32.eq"
                           (wat "struct.get" (id (data-type m type)) (int 0) read)
                           (wat "i32.const" (int (Case-tag (option-case m #f)))))
                      (wat "then" (wat "ref.null" (id (any-type m))))
                      (wat "else"
                           (wat "struct.get"
                                (id some)
                                (int 1)
                                (wat "ref.cast" (wat "ref" (id some)) read))))))
          value))

    (: exposed-function (-> Module String Type String ! mut))
    (define (exposed-function m name type)
      (match type
        ((TFun params result _) (handover-wrapper! m name params result))
        (_ (panic "internal error: exposed value is not a function"))))

    (: handover-wrapper! (-> Module String (List Type) Type String ! mut))
    (define (handover-wrapper! m name params result)
      (let* ((fn (new-fn m))
             (wrapper (wasm-id (string-append "exposed." name)))
             (names
              (map (lambda (i) (string-append "$arg." (i64->string i))) (iota (length params))))
             (args (map (lambda (pair)
                          (import-handover fn
                                           (Pair-first pair)
                                           (wat "local.get" (id (Pair-second pair)))))
                        (zip params names)))
             (value (export-handover fn
                                     result
                                     (wat* "call"
                                           (Cons (id (wasm-id name))
                                                 (Cons (evidence-none m) args))))))
        (push-function! m wrapper (wat* "func" (Cons (id wrapper)
                                                     (append (map (lambda (pair)
                                                                    (wat "param"
                                                                         (id (Pair-second pair))
                                                                         (exposed-value-type m
                                                                                             (Pair-first
                                                                                              pair))))
                                                                  (zip params names))
                                                             (Cons (wat "result"
                                                                        (exposed-value-type m
                                                                                            result))
                                                                   (append
                                                                    (reverse (ref-get (Fn-locals
                                                                                       fn)))
                                                                    (list value)))))))
        wrapper))

    ;; ---- Pattern matching ----

    ;; Clauses are tried in order. Each clause is a block that its failing
    ;; tests branch out of; a matching clause branches to `done` with its value.
    (: emit-match (-> Fn Expr Expr (List Clause) Bool (List Wat) ! mut))
    (define (emit-match fn expr scrutinee clauses tail?)
      (let* ((value (declare-temp! fn (rep->wat (fn-rep fn (Expr-type scrutinee)))))
             (done (local-id fn "match"))
             (scrutinee-code (emit1 fn scrutinee)))
        (list (wat "local.set" (id value) scrutinee-code)
              (wat* "block"
                    (Cons (id done)
                          (Cons (wat "result" (rep->wat (fn-rep fn (Expr-type expr))))
                                (append
                                 (map (lambda (clause) (clause-block fn clause value done tail?))
                                      clauses)
                                 (list (wat "unreachable")))))))))

    ;; The pattern declares the locals its body reads.
    (: clause-block (-> Fn Clause String String Bool Wat ! mut))
    (define (clause-block fn clause value done tail?)
      (let* ((next (local-id fn "clause"))
             (pattern (Clause-pattern clause))
             (tests (if (linear-type? (program-of (Fn-module fn)) (Nil) (pattern-type pattern))
                        (let ((plan (owned-pattern fn pattern (wat "local.get" (id value)) next)))
                          (append (Pair-first plan) (Pair-second plan)))
                        (pattern-code fn pattern (wat "local.get" (id value)) next)))
             (body (emit1-tail fn (Clause-body clause) tail?)))
        (wat* "block" (Cons (id next) (append tests (list (wat "br" (id done) body)))))))

    (: pattern-code (-> Fn Pattern Wat String (List Wat) ! mut))
    (define (pattern-code fn pattern value fail)
      (match pattern
        ((PWild _) (Nil))
        ((PVar name type)
         (list (wat "local.set" (id (declare-local! fn name (fn-rep fn type))) value)))
        ((PLit literal-value type)
         (list (wat "br_if" (id fail) (literal-differs fn literal-value type value))))
        ((PCon constructor args type)
         (constructor-pattern-code fn constructor args type value fail))))

    ;; Owned matches test first, then move bindings and clear containers.
    ;; Peeks stay on the operand stack: a failed clause must leave neither
    ;; changed owners nor raw payload scratch roots reaching their children.
    (: owned-pattern (-> Fn Pattern Wat String (Pair (List Wat) (List Wat)) ! mut))
    (define (owned-pattern fn pattern value fail)
      (match pattern
        ((PWild _) (Pair (Nil) (Nil)))
        ((PVar name type)
         (let ((representation (fn-rep fn type)))
           (Pair (Nil) (list (wat "local.set" (id (declare-local! fn name representation))
                                  (move-value (Fn-module fn) representation value))))))
        ((PLit literal-value type)
         (Pair (list (wat "br_if" (id fail) (literal-differs fn literal-value type value))) (Nil)))
        ((PCon constructor args type)
         (owned-constructor-pattern fn constructor args type value fail))))

    (: owned-constructor-pattern
       (-> Fn String (List Pattern) Type Wat String (Pair (List Wat) (List Wat)) ! mut))
    (define (owned-constructor-pattern fn constructor args type value fail)
      (let* ((m (Fn-module fn))
             (case (match (program-value (program-of m) constructor)
                     ((Some (Constructor case _)) case)
                     (_ (panic "internal error: not a constructor"))))
             (owned (linear-type? (program-of m) (Nil) type))
             (raw (if owned (wat "ref.cast" (wat "ref" (id (data-type m type)))
                                 (wat "struct.get" (id (owned-type m)) (int 0) value)) value))
             (plan (data-pattern fn case args type raw fail)))
        (Pair (Pair-first plan)
              (append (Pair-second plan) (if owned (list (clear-owner m value)) (Nil))))))

    (: data-pattern (-> Fn Case (List Pattern) Type Wat String (Pair (List Wat) (List Wat)) ! mut))
    (define (data-pattern fn case args type value fail)
      (let* ((m (Fn-module fn))
             (name (Case-type case))
             (enum? (DataType-enum? (data-type-of m name))))
        (if (tag-enum? m name)
            (Pair (list (wat "br_if"
                             (id fail)
                             (wat "i32.ne" value (wat "i32.const" (int (Case-tag case))))))
                  (Nil))
            (let* ((container (if enum? (case-type m type case) (data-type m type)))
                   (raw (if enum? (wat "ref.cast" (wat "ref" (id container)) value) value))
                   (fields (map-indexed (lambda (index arg)
                                          (owned-pattern fn
                                                         arg
                                                         (wat "struct.get"
                                                              (id container)
                                                              (int (+ index (if enum? 1 0)))
                                                              raw)
                                                         fail))
                                        args))
                   (tag (if enum? (list (wat "br_if" (id fail)
                                             (wat "i32.ne"
                                                  (wat "struct.get"
                                                       (id (data-type m type))
                                                       (int 0)
                                                       value)
                                                  (wat "i32.const" (int (Case-tag case))))))
                            (Nil))))
              (Pair (append tag (concatenate (map Pair-first fields)))
                    (concatenate (map Pair-second fields)))))))

    (: literal-differs (-> Fn Datum Type Wat Wat ! mut))
    (define (literal-differs fn literal-value type scrutinee)
      (let ((constant (literal fn literal-value type)))
        (match (fn-rep fn type)
          ((Scalar name) (wat (string-append name ".ne") scrutinee constant))
          ((Reference _)
           (wat "i32.eqz"
                (wat "call" (id (string-equal-helper (Fn-module fn))) scrutinee constant))))))

    (: constructor-pattern-code (-> Fn String (List Pattern) Type Wat String (List Wat) ! mut))
    (define (constructor-pattern-code fn constructor args type value fail)
      (let* ((m (Fn-module fn))
             (case (match (program-value (program-of m) constructor)
                     ((Some (Constructor case _)) case)
                     (_ (panic "internal error: not a constructor"))))
             (name (Case-type case)) (types (case-field-types m type case)))
        (cond ((tag-enum? m name)
               (list (wat "br_if"
                          (id fail)
                          (wat "i32.ne" value (wat "i32.const" (int (Case-tag case)))))))
              ((not (DataType-enum? (data-type-of m name)))
               (fields-code fn (data-type m type) 0 args types value fail))
              (else
               ;; A case's own type is registered only when its fields are
               ;; read, so a field-less case never declares one.
               (let ((base (data-type m type)))
                 (Cons (wat "br_if"
                            (id fail)
                            (wat "i32.ne"
                                 (wat "struct.get" (id base) (int 0) value)
                                 (wat "i32.const" (int (Case-tag case)))))
                       (if (every? wild? args)
                           (Nil)
                           (let* ((case-id (case-type m type case))
                                  (cast (declare-temp! fn (rep->wat (Reference case-id)))))
                             (Cons (wat "local.set"
                                        (id cast)
                                        (wat "ref.cast" (wat "ref" (id case-id)) value))
                                   (fields-code fn
                                                case-id
                                                1
                                                args
                                                types
                                                (wat "local.get" (id cast))
                                                fail))))))))))

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
                      (let ((arg (Pair-first pair))
                            (field (wat "struct.get" (id type-id) (int (+ index offset)) value)))
                        (match arg
                          ((PWild _) (Nil))
                          ((PVar _ _) (pattern-code fn arg field fail))
                          (_ (let ((temp
                                    (declare-temp! fn (rep->wat (fn-rep fn (Pair-second pair))))))
                               (Cons (wat "local.set" (id temp) field)
                                     (pattern-code fn arg (wat "local.get" (id temp)) fail)))))))
                    (zip args types))))

    ;; ---- Dynamic values ----

    ;; An Any is the TypeId of its value's ground type with the value itself;
    ;; a scalar is boxed so every payload is a reference.
    (: any-type (-> Module String ! mut))
    (define (any-type m)
      (match (known-type m "any")
        ((Some type) type)
        ((None)
         (register-type! m
                         "any"
                         "$any"
                         (wat "type"
                              (Word "$any")
                              (wat "struct"
                                   (wat "field" (Word "i32"))
                                   (wat "field" (Word "anyref"))))))))

    (: box-type (-> Module Rep String ! mut))
    (define (box-type m r)
      (let ((key (string-append "box." (rep-key r))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m
                           key
                           (wasm-id key)
                           (wat "type"
                                (id (wasm-id key))
                                (wat "struct" (wat "field" (rep->wat r)))))))))

    ;; To Any boxes; from Any checks the TypeId and panics on a mismatch. A
    ;; downcast of a value just upcast from the same type is removed. Keys
    ;; and TypeIds leave rows out, which is exact only because the checker
    ;; refuses a conversion whose types hold a function with effects.
    (: emit-convert (-> Fn Expr Type Loc (List Wat) ! mut))
    (define (emit-convert fn inner target loc)
      (let ((source (Expr-type inner)) (m (Fn-module fn)))
        (cond ((string=? (type-key source) (type-key target)) (emit fn inner #f))
              ((match (Expr-term inner)
                 ((Convert original _) (string=? (type-key (Expr-type original)) (type-key target)))
                 (_ #f))
               (match (Expr-term inner)
                 ((Convert original _) (emit fn original #f))
                 (_ (Nil))))
              ((any-type? target) (list (to-any m source (emit1 fn inner))))
              ((any-type? source) (list (from-any fn target (emit1 fn inner))))
              (else (panic "internal error: a conversion neither to nor from Any")))))

    (: to-any (-> Module Type Wat Wat ! mut))
    (define (to-any m type value)
      (let ((r (rep m type)))
        (wat "struct.new"
             (id (any-type m))
             (wat "i32.const" (int (any-type-id (program-of m) type)))
             (match r
               ((Scalar _) (wat "struct.new" (id (held-type m r)) value))
               ((Reference _) value)))))

    (: from-any (-> Fn Type Wat Wat ! mut))
    (define (from-any fn type value)
      (let* ((m (Fn-module fn))
             (r (fn-rep fn type))
             (any (declare-temp! fn (rep->wat (Reference (any-type m)))))
             (held (wat "ref.cast"
                        (wat "ref" (id (held-type m r)))
                        (wat "struct.get" (Word "$any") (int 1) (wat "local.get" (id any))))))
        (wat "block" (wat "result" (rep->wat r))
             (wat "local.set" (id any) value)
             (wat "if"
                  (wat "i32.ne"
                       (wat "struct.get" (Word "$any") (int 0) (wat "local.get" (id any)))
                       (wat "i32.const" (int (any-type-id (program-of m) type))))
                  (wat "then"
                       (wat "call"
                            (id (panic-helper m))
                            (string-literal m
                                            (string-append "type-convert: the value is not a "
                                                           (type->string type))))
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
             (field (lambda (index)
                      (wat "struct.get" (Word "$any") (int index) (wat "local.get" (id any))))))
        (wat "block" (wat "result" (Word "i32"))
             (wat "local.set" (id any) (emit1 fn inner))
             (wat "if"
                  (wat "result" (Word "i32"))
                  (wat "i32.eq" (field 0) (wat "i32.const" (int (any-type-id (program-of m) type))))
                  (wat "then"
                       (wat "ref.test" (wat "ref" (id (held-type m (fn-rep fn type)))) (field 1)))
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
    ;; and nothing compares Snail-Core types, which is what makes the cast unsafe.
    ;; That type is a Snail-Core function's, which takes the evidence first,
    ;; so the held function is one another module compiled from Snail-Core.
    (: funcref-closure (-> Module Type Wat Wat ! mut))
    (define (funcref-closure m type reference)
      (match type
        ((TFun _ _ _)
         (let* ((signature (function-signature m type))
                (base (closure-type m (Pair-first signature) (Pair-second signature)))
                (holder (funcref-holder-type m base)))
           (wat "struct.new"
                (id holder)
                (wat "ref.func" (id (funcref-code m signature base holder)))
                reference)))
        (_ (panic (string-append "unsafe-cast makes a function, not a " (type->string type))))))

    (: funcref-holder-type (-> Module String String ! mut))
    (define (funcref-holder-type m base)
      (let ((key (string-append "holder." (substring base 1 (string-length base)))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m key (wasm-id key)
                           (wat "type" (id (wasm-id key))
                                (wat "sub"
                                     (Word "final")
                                     (id base)
                                     (wat "struct"
                                          (wat "field" (wat "ref" (id (code-type m base))))
                                          (wat "field" (Word "funcref"))))))))))

    ;; The code takes the closure, the evidence and the arguments, and calls
    ;; the function the closure holds with the evidence and the arguments, at
    ;; that function's own type, which takes no closure.
    (: funcref-code (-> Module (Pair (List Rep) Rep) String String String ! mut))
    (define (funcref-code m signature base holder)
      (let ((params (Pair-first signature)) (result (Pair-second signature)))
        (helper! m "funcref" holder
                 (lambda (function-id)
                   (push! (Module-declared m) function-id)
                   (wat* "func"
                         (concatenate
                          (list (list (id function-id) (wat "type" (id (code-type m base)))
                                      (wat "param" (wat "ref" (id base)))
                                      (wat "param" (evidence-ref m)))
                                (map (lambda (param) (wat "param" (rep->wat param))) params)
                                (list (wat "result" (rep->wat result))
                                      (held-call m params result holder)))))))))

    ;; The held function runs under the handlers in scope where the closure
    ;; is called: the code passes on its own evidence, local 1, and the
    ;; parameters that follow it.
    (: held-call (-> Module (List Rep) Rep String Wat ! mut))
    (define (held-call m params result holder)
      (let ((own (funcref-type m params result))
            (held (wat "struct.get"
                       (id holder)
                       (int 1)
                       (wat "ref.cast" (wat "ref" (id holder)) (wat "local.get" (int 0))))))
        (wat* "call_ref"
              (append (Cons (id own)
                            (map (lambda (index) (wat "local.get" (int (+ index 1))))
                                 (iota (+ (length params) 1))))
                      (list (wat "ref.cast" (wat "ref" (id own)) held))))))

    ;; The Wasm type of the function a Funcref refers to, which takes the
    ;; evidence and no closure.
    (: funcref-type (-> Module (List Rep) Rep String ! mut))
    (define (funcref-type m params result)
      (let ((key (string-append "funcref."
                                (string-join (map rep-key params) ",")
                                "->"
                                (rep-key result))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m key (wasm-id key)
                           (wat "type" (id (wasm-id key))
                                (wat* "func"
                                      (append (Cons (wat "param" (evidence-ref m))
                                                    (map
                                                     (lambda (param) (wat "param" (rep->wat param)))
                                                     params))
                                              (list (wat "result" (rep->wat result)))))))))))

    ;; ---- Dynamic functions ----

    ;; `(expose name "symbol" dynamic)` exports a function for programs that
    ;; load it while they run, in two parts: "symbol", which takes the
    ;; evidence and an Any for each parameter and returns an Any, and
    ;; "symbol:signature", which returns the function's signature: its
    ;; arity, then the 64-bit identity of each parameter's type and of the
    ;; result's (`wide-type-id`). The checker has made sure each is data,
    ;; which its identity names all of, and that the function is pure. A
    ;; program that loads the function compares the signature once, when it
    ;; looks it up, and `dynamic-cast` holds the export in a closure of the
    ;; plain type. Values cross by reference: one declaration is one GC type
    ;; in every module that declares it.
    (: signature-words (-> Module Type (List I64)))
    (define (signature-words m type)
      (match type
        ((TFun params result _)
         (Cons (length params)
               (map (lambda (t) (wide-type-id (program-of m) t)) (append params (list result)))))
        (_ (panic "internal error: a dynamic function has a function type"))))

    (: signature-wat (-> Module Type Wat ! mut))
    (define (signature-wat m type)
      (let ((words (signature-words m type)))
        (wat* "array.new_fixed"
              (Cons (id (array-type m (Scalar "i64")))
                    (Cons (int (length words))
                          (map (lambda (word) (wat "i64.const" (int word))) words))))))

    ;; The Wasm type of a dynamic export of `arity` parameters.
    (: dynamic-type (-> Module I64 String ! mut))
    (define (dynamic-type m arity)
      (let ((key (string-append "dynamic." (i64->string arity)))
            (any (wat "ref" (id (any-type m)))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m key (wasm-id key)
                           (wat "type" (id (wasm-id key))
                                (wat* "func"
                                      (append (Cons (wat "param" (evidence-ref m))
                                                    (map (lambda (index) (wat "param" any))
                                                         (iota arity)))
                                              (list (wat "result" any))))))))))

    ;; Both exports of `name`, whose definition has `type`.
    (: export-dynamic! (-> Module String String Type Unit ! mut))
    (define (export-dynamic! m name symbol type)
      (push! (Module-exports m)
             (wat "export" (wat-string symbol) (wat "func" (id (dynamic-wrapper! m name type)))))
      (push! (Module-exports m)
             (wat "export"
                  (wat-string (string-append symbol ":signature"))
                  (wat "func" (id (signature-function! m name type))))))

    ;; The wrapper takes each argument out of its Any, which checks its
    ;; TypeId, and calls the definition with the empty evidence list, as an
    ;; exposed function's does: the loading program's handlers are not
    ;; passed on, and the checker has made the function pure.
    (: dynamic-wrapper! (-> Module String Type String ! mut))
    (define (dynamic-wrapper! m name type)
      (match type
        ((TFun params result _)
         (let* ((fn (new-fn m)) (wrapper (wasm-id (string-append "dynamic-export." name)))
                (names (map (lambda (index) (string-append "$any." (i64->string index)))
                            (iota (length params))))
                (args (map (lambda (pair)
                             (from-any fn
                                       (Pair-first pair)
                                       (wat "local.get" (id (Pair-second pair)))))
                           (zip params names)))
                (value (to-any m
                               result
                               (wat* "call"
                                     (Cons (id (wasm-id name)) (Cons (evidence-none m) args))))))
           (push-function! m wrapper
                           (function-wat fn wrapper
                                         (Cons (wat "type" (id (dynamic-type m (length params))))
                                               (Cons (evidence-param m)
                                                     (map (lambda (param)
                                                            (wat "param"
                                                                 (id param)
                                                                 (wat "ref" (id (any-type m)))))
                                                          names)))
                                         (Reference (any-type m)) (list value)))
           wrapper))
        (_ (panic "internal error: a dynamic export is a function"))))

    ;; The signature takes the evidence, as every Snail-Core function does,
    ;; so a program that loads it calls it as a function of no arguments.
    (: signature-function! (-> Module String Type String ! mut))
    (define (signature-function! m name type)
      (let ((function-id (wasm-id (string-append "dynamic-signature." name))))
        (push-function! m function-id
                        (wat "func"
                             (id function-id)
                             (evidence-param m)
                             (wat "result" (wat "ref" (id (array-type m (Scalar "i64")))))
                             (signature-wat m type)))
        function-id))

    ;; `dynamic-cast` calls the policy with the signature of the function
    ;; type the context expects and, if the policy accepts it, holds the
    ;; Funcref in a closure of that type, in a vector of one; otherwise the
    ;; vector is empty. Both operands are evaluated first, in order.
    (: dynamic-cast (-> Fn Type Type Wat Wat Wat ! mut))
    (define (dynamic-cast fn type policy-type reference policy)
      (let* ((m (Fn-module fn))
             (vector (reference-type (fn-rep fn type)))
             (base (reference-type (fn-rep fn policy-type)))
             (held (declare-temp! fn (Word "funcref")))
             (accepts (declare-temp! fn (rep->wat (Reference base)))))
        (wat "block" (wat "result" (wat "ref" (id vector)))
             (wat "local.set" (id held) reference)
             (wat "local.set" (id accepts) policy)
             (wat "if" (wat "result" (wat "ref" (id vector)))
                  (closure-call-wat m
                                    base
                                    (wat "local.get" (id accepts))
                                    (list (Fn-evidence fn) (signature-wat m (vector-element type)))
                                    #f)
                  (wat "then"
                       (wat "array.new_fixed"
                            (id vector)
                            (int 1)
                            (dynamic-closure m (vector-element type) (wat "local.get" (id held)))))
                  (wat "else" (wat "array.new_fixed" (id vector) (int 0)))))))

    (: vector-element (-> Type Type))
    (define (vector-element type)
      (match type
        ((TCon "Vector" (Cons element (Nil))) element)
        (_ (panic "internal error: not a vector type"))))

    ;; The expected type is a function of data, as a dynamic export's is, or
    ;; no signature could be its.
    (: dynamic-closure (-> Module Type Wat Wat ! mut))
    (define (dynamic-closure m type reference)
      (match type
        ((TFun params result _)
         (unless (every? (lambda (t) (first-order-type? (program-of m) t)) (Cons result params))
           (panic
            (string-append "dynamic-cast makes a function of data, not a " (type->string type))))
         (let* ((signature (function-signature m type))
                (base (closure-type m (Pair-first signature) (Pair-second signature)))
                (holder (funcref-holder-type m base)))
           (wat "struct.new"
                (id holder)
                (wat "ref.func" (id (dynamic-code m type base holder)))
                reference)))
        (_ (panic (string-append "dynamic-cast makes a function, not a " (type->string type))))))

    ;; The code passes the closure's arguments as Any values, with its own
    ;; evidence, to the export it holds, and takes the result out of the Any
    ;; that returns, which checks its TypeId. TypeIds depend on the
    ;; Snail-Core types and not only on their representations, so the code
    ;; is kept per type.
    (: dynamic-code (-> Module Type String String String ! mut))
    (define (dynamic-code m type base holder)
      (helper! m "dynamic-call" (type-key type)
               (lambda (function-id)
                 (push! (Module-declared m) function-id)
                 (let ((fn (new-fn m)) (signature (function-signature m type)))
                   (function-wat fn function-id
                                 (append (list (wat "type" (id (code-type m base)))
                                               (wat "param" (wat "ref" (id base)))
                                               (wat "param" (evidence-ref m)))
                                         (map (lambda (param) (wat "param" (rep->wat param)))
                                              (Pair-first signature)))
                                 (Pair-second signature) (list (dynamic-call fn type holder)))))))

    ;; The export takes the evidence, local 1, then an Any for each of the
    ;; parameters that follow it.
    (: dynamic-call (-> Fn Type String Wat ! mut))
    (define (dynamic-call fn type holder)
      (match type
        ((TFun params result _)
         (let* ((m (Fn-module fn)) (export (dynamic-type m (length params)))
                (held (wat "struct.get"
                           (id holder)
                           (int 1)
                           (wat "ref.cast" (wat "ref" (id holder)) (wat "local.get" (int 0)))))
                (anys (map-indexed
                       (lambda (index param) (to-any m param (wat "local.get" (int (+ index 2)))))
                       params)))
           (from-any fn
                     result
                     (wat* "call_ref"
                           (append (Cons (id export) (Cons (wat "local.get" (int 1)) anys))
                                   (list (wat "ref.cast" (wat "ref" (id export)) held)))))))
        (_ (panic "internal error: not a function type"))))

    ;; ---- Effect handlers ----

    ;; Handlers are evidence passed to every function: a list of nodes, each
    ;; an effect's label, its handler and the node outside it. A `handle`
    ;; extends the list for its body; an operation walks it for its effect's
    ;; label and calls that handler's implementation with the list outside
    ;; the node, so the implementation's own operations go to the next
    ;; handler out, and a list with no such node means the host default.
    ;; Nothing is global, so a task carries its handlers on its own stack.
    ;; The node outside is mutable because `resume` sets it to the evidence
    ;; of its caller, so a resumed computation runs under the handlers in
    ;; scope where it is resumed (see Resuming); nothing else writes it.
    (: evidence-type (-> Module String ! mut))
    (define (evidence-type m)
      (match (known-type m "evidence")
        ((Some type) type)
        ((None)
         (push! (Module-globals m)
                (wat "global" (id "$evidence.none") (wat "ref" (id "$evidence"))
                     (wat "struct.new"
                          (id "$evidence")
                          (wat "i32.const" (int -1))
                          (wat "ref.null" (Word "any"))
                          (wat "ref.null" (id "$evidence")))))
         (register-type! m "evidence" "$evidence"
                         (wat "type" (id "$evidence")
                              (wat "struct"
                                   (wat "field" (Word "i32"))
                                   (wat "field" (wat "ref" (Word "null") (Word "any")))
                                   (wat "field"
                                        (wat "mut"
                                             (wat "ref" (Word "null") (id "$evidence"))))))))))

    (: evidence-rep (-> Module Rep ! mut))
    (define (evidence-rep m)
      (Reference (evidence-type m)))

    (: evidence-ref (-> Module Wat ! mut))
    (define (evidence-ref m)
      (rep->wat (evidence-rep m)))

    (: evidence-param (-> Module Wat ! mut))
    (define (evidence-param m)
      (wat "param" (Word "$ev") (evidence-ref m)))

    ;; The empty list: one node no effect's label matches, outside everything.
    (: evidence-none (-> Module Wat ! mut))
    (define (evidence-none m)
      (evidence-type m)
      (wat "global.get" (id "$evidence.none")))

    (: effect-label (-> String Wat))
    (define (effect-label effect)
      (wat "i32.const" (int (type-id effect))))

    ;; A handler is a struct of the effect's implementations, in operation order.
    (: handler-type (-> Module String String ! mut))
    (define (handler-type m effect)
      (let ((key (string-append "handler." effect)))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (let* ((info (program-effect (program-of m) effect))
                  (fields
                   (map (lambda (operation) (wat "field" (implementation-field m info operation)))
                        (Effect-operations info))))
             (register-type! m
                             key
                             (wasm-id key)
                             (wat "type" (id (wasm-id key)) (wat* "struct" fields))))))))

    ;; A control implementation's type depends on its handle's result, and
    ;; only its handle site calls it, so its field holds any reference.
    (: implementation-field (-> Module Effect String Wat ! mut))
    (define (implementation-field m info operation)
      (if (member? operation (Effect-control info))
          (wat "ref" (Word "any"))
          (rep->wat (rep m (operation-type m operation)))))

    (: operation-type (-> Module String Type))
    (define (operation-type m operation)
      (match (program-value (program-of m) operation)
        ((Some (Operation _ (Scheme _ _ _ (TFun params result _)))) (TFun params result empty-row))
        (_ (panic "internal error: not an operation"))))

    (: operation-result (-> Module String Type))
    (define (operation-result m operation)
      (match (operation-type m operation)
        ((TFun _ result _) result)
        (_ (panic "internal error: an operation is a function"))))

    ;; An operation that answers Never cannot return to its performer: its
    ;; implementation is handed no `resume`, and its yields save nothing.
    (: answers-never? (-> Module String Bool))
    (define (answers-never? m operation)
      (never-type? (operation-result m operation)))

    ;; The implementations are values of the surrounding evidence; the body
    ;; runs with the new node as its evidence. A handle of a control effect
    ;; also catches the yields aimed at its node (see Control).
    (: emit-handle (-> Fn Expr String (List (Pair String Expr)) Expr (List Wat) ! mut))
    (define (emit-handle fn expr effect implementations body)
      (if (null? (Effect-control (program-effect (program-of (Fn-module fn)) effect)))
          (emit-returning-handle fn expr effect implementations body)
          (emit-control-handle fn expr effect implementations body)))

    (: emit-returning-handle (-> Fn Expr String (List (Pair String Expr)) Expr (List Wat) ! mut))
    (define (emit-returning-handle fn expr effect implementations body)
      (let* ((installed (install-handler fn effect implementations)) (node (Pair-first installed)))
        (list (Pair-second installed)
              (move-value (Fn-module fn)
                          (fn-rep fn (Expr-type expr))
                          (emit1 (Fn-evidence-set fn (wat "local.get" (id node))) body)))))

    ;; A new evidence node in a local: the local's name, and the instruction
    ;; that sets it to the node holding the handler.
    (: install-handler (-> Fn String (List (Pair String Expr)) (Pair String Wat) ! mut))
    (define (install-handler fn effect implementations)
      (let* ((m (Fn-module fn)) (type-id (handler-type m effect)) (node (local-id fn "ev"))
             (handler (wat* "struct.new"
                            (Cons (id type-id)
                                  (map (lambda (operation)
                                         (emit1 fn
                                                (handler-implementation implementations operation)))
                                       (Effect-operations
                                        (program-effect (program-of m) effect)))))))
        (push! (Fn-locals fn) (wat "local" (id node) (evidence-ref m)))
        (Pair node
              (wat "local.set"
                   (id node)
                   (wat "struct.new"
                        (id (evidence-type m))
                        (effect-label effect)
                        handler
                        (Fn-evidence fn))))))

    (: handler-implementation (-> (List (Pair String Expr)) String Expr))
    (define (handler-implementation implementations operation)
      (match (assoc-ref implementations operation)
        ((Some implementation) implementation)
        ((None) (panic "internal error: missing implementation"))))

    ;; Each operation is one function, so its call sites are ordinary calls.
    ;; It walks the evidence for its effect's node and calls that handler's
    ;; implementation with the evidence outside it, which forwards the
    ;; effects its latent row names (see Latent effects); with no node it
    ;; uses the default. A control operation records a yield at the node
    ;; instead (see Control).
    (: performer (-> Module String String String ! mut))
    (define (performer m effect operation)
      (helper! m "perform" operation
               (lambda (function-id)
                 (let* ((signature (function-signature m (operation-type m operation)))
                        (params (Pair-first signature))
                        (result (Pair-second signature))
                        (names
                         (map (lambda (index) (string-append "$argument." (i64->string index)))
                              (iota (length params))))
                        (info (program-effect (program-of m) effect)))
                   (wat* "func"
                         (concatenate
                          (list (Cons (id function-id)
                                      (Cons (evidence-param m)
                                            (map (lambda (pair)
                                                   (wat "param"
                                                        (id (Pair-first pair))
                                                        (rep->wat (Pair-second pair))))
                                                 (zip names params))))
                                (list (wat "result" (rep->wat result))
                                      (wat "local"
                                           (Word "$node")
                                           (wat "ref" (Word "null") (id (evidence-type m)))))
                                (forwarding-locals m operation result)
                                (list
                                 (wat "local.set" (Word "$node") (wat "local.get" (Word "$ev")))
                                 (wat* "loop"
                                       (Cons (Word "$walk")
                                             (handler-search m info operation names params result)))
                                 (wat "unreachable")))))))))

    ;; One step of the walk: the default past the last node, the
    ;; implementation at the effect's node, else the next node out.
    (: handler-search (-> Module Effect String (List String) (List Rep) Rep (List Wat) ! mut))
    (define (handler-search m info operation names params result)
      (let ((node (wat "local.get" (Word "$node"))) (evidence (evidence-type m)))
        (list
         (wat "if" (wat "ref.is_null" node) (wat* "then" (default-call m info operation names)))
         (wat "if"
              (wat "i32.eq"
                   (wat "struct.get" (id evidence) (int 0) node)
                   (effect-label (Effect-name info)))
              (wat* "then" (at-handler m info operation names params result)))
         (wat "local.set" (Word "$node") (wat "struct.get" (id evidence) (int 2) node))
         (wat "br" (Word "$walk")))))

    ;; At the effect's node an ordinary operation calls the implementation
    ;; there and returns its result, under forwarding nodes when its latent
    ;; row names effects with operations; a control operation records the
    ;; yield and returns a placeholder.
    (: at-handler (-> Module Effect String (List String) (List Rep) Rep (List Wat) ! mut))
    (define (at-handler m info operation names params result)
      (cond ((member? operation (Effect-control info))
             (list (record-yield m info operation names params)
                   (wat "return" (placeholder m (operation-result m operation) no-loc))))
            ((null? (forwarded-effects m operation))
             (list (wat "return"
                        (implementation-call m
                                             info
                                             operation
                                             names
                                             params
                                             result
                                             (node-outside m (wat "local.get" (Word "$node")))))))
            (else (forwarding-call m info operation names params result))))

    ;; The implementation at the walk's node, called under `evidence`.
    (: implementation-call (-> Module Effect String (List String) (List Rep) Rep Wat Wat ! mut))
    (define (implementation-call m info operation names params result evidence)
      (let* ((handler-id (handler-type m (Effect-name info))) (base (closure-type m params result))
             (implementation
              (wat "struct.get" (id handler-id) (int (operation-index info operation))
                   (wat "ref.cast"
                        (wat "ref" (id handler-id))
                        (wat "struct.get"
                             (id (evidence-type m))
                             (int 1)
                             (wat "local.get" (Word "$node")))))))
        (wat* "call_ref" (Cons (id (code-type m base))
                               (Cons implementation
                                     (Cons evidence
                                           (append
                                            (map (lambda (name) (wat "local.get" (id name))) names)
                                            (list (wat "struct.get"
                                                       (id base)
                                                       (int 0)
                                                       implementation)))))))))

    ;; The evidence outside a node.
    (: node-outside (-> Module Wat Wat ! mut))
    (define (node-outside m node)
      (wat "ref.as_non_null" (wat "struct.get" (id (evidence-type m)) (int 2) node)))

    ;; Past the last node: the host import, or the Snail-Core function,
    ;; called under the performer's evidence, or a trap.
    (: default-call (-> Module Effect String (List String) (List Wat) ! mut))
    (define (default-call m info operation names)
      (let ((arguments (map (lambda (name) (wat "local.get" (id name))) names)))
        (match (assoc-ref (Effect-defaults info) operation)
          ((Some (HostDefault import))
           (list
            (wat* "return" (host-call m import (operation-type m operation) arguments no-loc))))
          ((Some (SnailDefault function))
           (list (wat* "return_call"
                       (Cons (id (function-id m function))
                             (Cons (wat "local.get" (Word "$ev")) arguments)))))
          ((None)
           (list (wat "return"
                      (wat "call"
                           (id (panic-helper m))
                           (string-literal m
                                           (string-append "unhandled effect operation "
                                                          (short-name operation))))
                      (wat "unreachable")))))))

    ;; ---- Control ----

    ;; Performing a control operation records the yield in one global: the
    ;; node of the handler it is aimed at, the operation's index in its
    ;; effect, its arguments, and the frames saved so far. The performer
    ;; then returns a placeholder of its result type. Each call that may
    ;; yield is the value of a let, as (snail shell compiler control)
    ;; arranges, and after that let the record is tested: while it is set,
    ;; the let saves its body as a frame on the record (see Frames) and
    ;; leaves with a placeholder, a function to its caller and a handle body
    ;; to the end of its block, until the handle whose node the record
    ;; names. That handle clears the record and calls the operation's
    ;; implementation in its own context, with the recorded arguments and a
    ;; `resume` holding the frames (see Resuming); the implementation's
    ;; result is the handle's. A yield of an operation that answers Never
    ;; is never resumed, so where every effect a call may yield to is of
    ;; that kind, its test leaves without saving a frame, and no join is
    ;; built for the rest. A call whose value flows straight out needs
    ;; no test, so a tail call stays a tail call. Nothing reads a
    ;; placeholder, since every caller tests first and leaves too. The
    ;; record is clear whenever Snail-Core code runs outside a yield, so
    ;; none is live across a host suspension.

    ;; Where a yield leaves the code being emitted, with a placeholder: a
    ;; function returns one of its result type to its caller; a block, the
    ;; body of a handle or the value of a let, branches to its end with one
    ;; of its type; a join function returns null to the runner, for the
    ;; boxed value it would have returned.
    (enum Exit
      (ToCaller
       ((result Type)))
      (ToBlock
       ((label String)
        (result Type)))
      (ToRunner))

    (: function-exit (-> Type (Option Exit)))
    (define (function-exit type)
      (match type
        ((TFun _ result _) (Some (ToCaller result)))
        (_ (panic "internal error: not a function type"))))

    (: yield-type (-> Module String ! mut))
    (define (yield-type m)
      (match (known-type m "yield")
        ((Some type) type)
        ((None)
         (let ((frames (frames-type m)))
           (register-type! m "yield" "$yield"
                           (wat "type" (id "$yield")
                                (wat "struct"
                                     (wat "field" (evidence-ref m))
                                     (wat "field" (Word "i32"))
                                     (wat "field" (Word "anyref"))
                                     (wat "field"
                                          (wat "mut" (wat "ref" (Word "null") (id frames)))))))))))

    ;; The global holding the record, null while nothing yields. A whole
    ;; program declares it. A library's module imports it from the control
    ;; module, which a library build links first, so every module of a
    ;; program shares one.
    (: yielding (-> Module String ! mut))
    (define (yielding m)
      (let ((type (wat "mut" (wat "ref" (Word "null") (id (yield-type m))))))
        (match (Module-owner m)
          ((Some _)
           (import-once! m "yielding" "$yielding"
                         (lambda (global)
                           (wat "import"
                                (wat-string "snail.core.control")
                                (wat-string "yielding")
                                (wat "global" (id global) type)))))
          ((None)
           (unless (table-contains? (ref-get (Module-helpers m)) "yielding")
             (put! (Module-helpers m) "yielding" "$yielding")
             (push! (Module-globals m)
                    (wat "global" (id "$yielding") type (wat "ref.null" (id "$yield")))))
           "$yielding"))))

    ;; The module a library build links first when its program has control
    ;; effects: it declares the record's global and exports it, and its
    ;; text never changes.
    (: emit-control-module (-> Program Wat ! mut))
    (define (emit-control-module program)
      (let ((m (new-module (Mono program (Nil) empty-table (Nil)) (None))))
        (push! (Module-exports m)
               (wat "export" (wat-string "yielding") (wat "global" (id (yielding m)))))
        (emit-main! m (Nil))
        (module-wat m)))

    (: yielding? (-> Module Wat ! mut))
    (define (yielding? m)
      (wat "i32.eqz" (wat "ref.is_null" (wat "global.get" (id (yielding m))))))

    ;; Whether the record, which is set, names `node`.
    (: aimed-at? (-> Module Wat Wat ! mut))
    (define (aimed-at? m node)
      (wat "ref.eq"
           (wat "struct.get"
                (id (yield-type m))
                (int 0)
                (wat "ref.as_non_null" (wat "global.get" (id (yielding m)))))
           node))

    (: may-yield? (-> Fn Expr Bool))
    (define (may-yield? fn value)
      (match (Module-callees (Fn-module fn))
        ((Some callees) (not (null? (yields callees value))))
        ((None) #f)))

    ;; The rest of a let after its value. When the value may yield, a test
    ;; comes first: while the record is set, it saves the let's body as a
    ;; frame and leaves. In a join function, whose own rest the body is,
    ;; the body then runs in that frame, by a tail call as the runner would
    ;; make, so each join holds its body only up to the next yield point.
    ;; A yield that nothing can resume saves nothing, so its test only
    ;; leaves, and the body follows in the same function.
    (: let-rest (-> Fn String Expr Expr Bool (List Wat) ! mut))
    (define (let-rest fn name value body tail?)
      (cond ((not (may-yield? fn value)) (emit fn body tail?))
            ((aborts? fn value)
             (Cons (wat "if" (yielding? (Fn-module fn)) (wat "then" (leave fn (Expr-loc value))))
                   (emit fn body tail?)))
            ((match (Fn-exit fn) ((Some (ToRunner)) #t) (_ #f))
             (continue-in-frame fn name value body))
            (else (let ((test (yield-test fn (frame fn name value body) (Expr-loc value))))
                    (append test (emit fn body tail?))))))

    ;; Whether every effect `value` may yield to aborts: each of its control
    ;; operations answers Never, so its handler is handed no `resume`, and
    ;; nothing will run what follows the yield.
    (: aborts? (-> Fn Expr Bool))
    (define (aborts? fn value)
      (let ((m (Fn-module fn)))
        (match (Module-callees m)
          ((Some callees)
           (every? (lambda (label)
                     (every? (lambda (operation) (answers-never? m operation))
                             (Effect-control (program-effect (program-of m) label))))
                   (yields callees value)))
          ((None) #f))))

    (: yield-test (-> Fn Wat Loc (List Wat) ! mut))
    (define (yield-test fn saved loc)
      (let* ((m (Fn-module fn)) (exit (leave fn loc)))
        (list (wat "if" (yielding? m) (wat "then" (wat "call" (id (push-helper m)) saved) exit)))))

    (: continue-in-frame (-> Fn String Expr Expr (List Wat) ! mut))
    (define (continue-in-frame fn name value body)
      (let* ((m (Fn-module fn))
             (base (frame-type m))
             (temp (declare-temp! fn (wat "ref" (id base))))
             (saved (wat "local.get" (id temp)))
             (set (wat "local.set" (id temp) (frame fn name value body)))
             (test (yield-test fn saved (Expr-loc value)))
             (argument (box-value m (Expr-type value) (variable fn name unchecked))))
        (Cons set
              (append test
                      (list (wat "return_call_ref"
                                 (id (code-type m base))
                                 saved
                                 argument
                                 (wat "struct.get" (id base) (int 0) saved)))))))

    ;; A let's value that holds yield points of its own is a block they
    ;; leave, so that the let's own test then saves the let's body too.
    (: emit-let-value (-> Fn Expr Wat ! mut))
    (define (emit-let-value fn value)
      (match (Module-callees (Fn-module fn))
        ((Some callees)
         (if (holds-yield-point? callees value)
             (let ((label (local-id fn "yield")) (type (Expr-type value)))
               (wat* "block"
                     (Cons (id label)
                           (Cons (wat "result" (rep->wat (fn-rep fn type)))
                                 (emit (Fn-exit-set fn (Some (ToBlock label type))) value #f)))))
             (emit1 fn value)))
        ((None) (emit1 fn value))))

    (: leave (-> Fn Loc Wat ! mut))
    (define (leave fn loc)
      (match (Fn-exit fn)
        ((Some (ToCaller result)) (wat "return" (placeholder (Fn-module fn) result loc)))
        ((Some (ToBlock label result))
         (wat "br" (id label) (placeholder (Fn-module fn) result loc)))
        ((Some (ToRunner)) (wat "return" (wat "ref.null" (Word "any"))))
        ((None) (panic "internal error: a yield outside any function"))))

    ;; ---- Frames ----

    ;; A frame is a closure over the rest of a function at a yield point:
    ;; the body of a let whose value yielded. Its code takes the frame and
    ;; the let's value and returns the body's, each boxed when a scalar, so
    ;; one code type serves every frame. It holds the live locals the body
    ;; reads and, last, the evidence the body runs under, whose nodes reach
    ;; the handler the yield is aimed at. Outside join functions a frame is
    ;; built only on the path that leaves, so the fast path allocates none.
    (: frame-type (-> Module String ! mut))
    (define (frame-type m)
      (match (known-type m "frame")
        ((Some type) type)
        ((None)
         (put! (Module-type-ids m) "code:$frame" "$frame.code")
         (register-type! m "frame.code" "$frame.code"
                         (wat "type"
                              (id "$frame.code")
                              (wat "func"
                                   (wat "param" (wat "ref" (id "$frame")))
                                   (wat "param" (Word "anyref"))
                                   (wat "result" (Word "anyref")))))
         (register-type! m
                         "frame"
                         "$frame"
                         (wat "type"
                              (id "$frame")
                              (wat "sub"
                                   (wat "struct" (wat "field" (wat "ref" (id "$frame.code"))))))))))

    ;; A list of frames. The record's grows at its head as the yield leaves
    ;; each frame, so its outermost frame comes first; a continuation's is
    ;; reversed, into the order the frames run in.
    (: frames-type (-> Module String ! mut))
    (define (frames-type m)
      (match (known-type m "frames")
        ((Some type) type)
        ((None)
         (let ((frame (frame-type m)))
           (register-type! m "frames" "$frames"
                           (wat "type"
                                (id "$frames")
                                (wat "struct"
                                     (wat "field" (wat "ref" (id frame)))
                                     (wat "field" (wat "ref" (Word "null") (id "$frames"))))))))))

    ;; The frame of the let binding `name` to `value`: the join function of
    ;; its body, the locals the body reads, moved, then the evidence.
    (: frame (-> Fn String Expr Expr Wat ! mut))
    (define (frame fn name value body)
      (let* ((m (Fn-module fn))
             (captured (filter (lambda (local) (and (not (string=? local name)) (local? fn local)))
                               (expr-references body)))
             (entries (map (lambda (local) (Pair local (capture-rep fn local))) captured))
             (type (capture-type m
                                 (frame-type m)
                                 (append (map Pair-second entries) (list (evidence-rep m)))))
             (join
              (emit-join! (Fn-exit-set (new-fn m) (Some (ToRunner))) name value body entries type)))
        (wat* "struct.new" (Cons (id type) (Cons (wat "ref.func" (id join))
                                                 (append (map (lambda (local)
                                                                (variable fn local unchecked))
                                                              captured)
                                                         (list (Fn-evidence fn))))))))

    ;; A let's body as a function of its frame and its boxed value: it
    ;; loads the frame's locals and evidence and binds the value, runs the
    ;; body, which a yield leaves with null, and boxes the body's value.
    ;; The body runs to the let's end and no further, since the frames
    ;; outside it continue from there, and its tail calls are calls, since
    ;; their results are boxed. It is named by its text, as a lambda is,
    ;; so the joins of one let, which the function and the join of the
    ;; let before it both need, are one function.
    (: emit-join! (-> Fn String Expr Expr (List (Pair String Rep)) String String ! mut))
    (define (emit-join! join name value body entries type)
      (push! (Fn-locals join) (wat "local" (Word "$ev") (evidence-ref (Fn-module join))))
      (let* ((m (Fn-module join))
             (frame (wat "ref.cast" (wat "ref" (id type)) (wat "local.get" (Word "$closure"))))
             (evidence (wat "local.set"
                            (Word "$ev")
                            (wat "struct.get" (id type) (int (+ (length entries) 1)) frame)))
             (loads (capture-loads join entries type))
             (local (declare-local! join name (fn-rep join (Expr-type value))))
             (argument (wat "local.set"
                            (id local)
                            (unbox-value m (Expr-type value) (wat "local.get" (Word "$value")))))
             (result (box-value m (Expr-type body) (emit1 join body))))
        (lambda-id m
                   "join"
                   (join-wat join (Cons evidence (append loads (list argument result))))
                   0)))

    (: join-wat (-> Fn (List Wat) Wat ! mut))
    (define (join-wat join code)
      (let* ((m (Fn-module join)) (frame (frame-type m)))
        (wat* "func" (append (list (Word "$lambda.self") (wat "type" (id (code-type m frame)))
                                   (wat "param" (Word "$closure") (wat "ref" (id frame)))
                                   (wat "param" (Word "$value") (Word "anyref"))
                                   (wat "result" (Word "anyref")))
                             (append (reverse (ref-get (Fn-locals join))) code)))))

    ;; A value as frames pass it: a reference as it is, a scalar boxed as
    ;; an Any holds it.
    (: box-value (-> Module Type Wat Wat ! mut))
    (define (box-value m type value)
      (match (rep m type)
        ((Scalar name) (wat "struct.new" (id (box-type m (Scalar name))) value))
        ((Reference _) value)))

    (: unbox-value (-> Module Type Wat Wat ! mut))
    (define (unbox-value m type value)
      (match (rep m type)
        ((Scalar name)
         (let ((box (box-type m (Scalar name))))
           (wat "struct.get" (id box) (int 0) (wat "ref.cast" (wat "ref" (id box)) value))))
        ((Reference type-id) (wat "ref.cast" (wat "ref" (id type-id)) value))))

    ;; Saves a frame on the record, as the yield leaves it.
    (: push-helper (-> Module String ! mut))
    (define (push-helper m)
      (template-helper! m "control" "push"
                        "(func {id} (param $frame (ref {frame}))
  (local $record (ref {yield}))
  (local.set $record (ref.as_non_null (global.get {yielding})))
  (struct.set {yield} 3 (local.get $record) (struct.new {frames} (local.get $frame) (struct.get {yield} 3 (local.get $record)))))"
                        (list (Pair "frame" (frame-type m))
                              (Pair "yield" (yield-type m))
                              (Pair "yielding" (yielding m))
                              (Pair "frames" (frames-type m)))))

    ;; ---- Placeholders ----

    ;; A value of `type` to leave with. Nothing reads it, so any value of
    ;; its representation will do: zero, an empty array, an enum's base
    ;; with no case's tag, a closure whose code is unreachable, a struct of
    ;; placeholders, each kept in a global. An owner is a fresh one with a
    ;; payload, since moving a value out of an owner, as a handle site and
    ;; a drop do, requires one.
    (: placeholder (-> Module Type Loc Wat ! mut))
    (define (placeholder m type loc)
      (match (rep m type)
        ((Reference "$owned") (fresh-owner m))
        ((Reference representation)
         (memoize! m (string-append "placeholder:" (type-key type))
                   (lambda ()
                     (let ((global (keyed-id "placeholder" (type-key type))))
                       (push! (Module-globals m)
                              (wat "global"
                                   (id global)
                                   (wat "ref" (id representation))
                                   (placeholder-value m type (Nil) loc)))
                       (wat "global.get" (id global))))))
        (scalar (default-value scalar))))

    ;; A constant expression for a placeholder; `seen` holds the structs it
    ;; is inside.
    (: placeholder-value (-> Module Type (List String) Loc Wat ! mut))
    (define (placeholder-value m type seen loc)
      (match (rep m type)
        ((Scalar name) (default-value (Scalar name)))
        ((Reference "$owned") (fresh-owner m))
        ((Reference representation)
         (match type
           ((TCon "Any" _)
            (wat "struct.new"
                 (id representation)
                 (wat "i32.const" (int -1))
                 (wat "ref.null" (Word "any"))))
           ((TCon "Ref" (Cons content _))
            (wat "struct.new" (id representation) (placeholder-value m content seen loc)))
           ((TCon name _)
            (if (member? name (list "String" "Array" "Vector"))
                (wat "array.new_fixed" (id representation) (int 0))
                (data-placeholder m type seen loc)))
           (_ (wat "struct.new"
                   (id representation)
                   (wat "ref.func" (id (unreachable-code m type representation)))))))))

    ;; A struct that contains itself has no placeholder.
    (: data-placeholder (-> Module Type (List String) Loc Wat ! mut))
    (define (data-placeholder m type seen loc)
      (let ((data (data-type-of m (type-name type))) (key (type-key type)))
        (cond ((DataType-enum? data)
               (wat "struct.new" (id (data-type m type)) (wat "i32.const" (int -1))))
              ((member? key seen) (panic "internal error: a struct that contains itself"))
              (else
               (match (DataType-cases data)
                 ((Cons case _)
                  (wat* "struct.new" (Cons (id (data-type m type))
                                           (map (lambda (field)
                                                  (placeholder-value m field (Cons key seen) loc))
                                                (case-field-types m type case)))))
                 ((Nil) (panic "internal error: a struct has one case")))))))

    (: unreachable-code (-> Module Type String String ! mut))
    (define (unreachable-code m type base)
      (let ((signature (function-signature m type)))
        (helper! m "unreachable" base
                 (lambda (function-id)
                   (push! (Module-declared m) function-id)
                   (wat* "func"
                         (concatenate (list (list (id function-id)
                                                  (wat "type" (id (code-type m base)))
                                                  (wat "param" (wat "ref" (id base)))
                                                  (evidence-param m))
                                            (map (lambda (param) (wat "param" (rep->wat param)))
                                                 (Pair-first signature))
                                            (list (wat "result" (rep->wat (Pair-second signature)))
                                                  (wat "unreachable")))))))))

    (: fresh-owner (-> Module Wat ! mut))
    (define (fresh-owner m)
      (wat "struct.new" (id (owned-type m)) (wat "ref.i31" (wat "i32.const" (int 0)))))

    ;; ---- Performing and catching ----

    ;; The yield of `operation` at the node the performer's walk is on,
    ;; with no frames yet.
    (: record-yield (-> Module Effect String (List String) (List Rep) Wat ! mut))
    (define (record-yield m info operation names params)
      (wat "global.set" (id (yielding m))
           (wat "struct.new"
                (id (yield-type m))
                (wat "ref.as_non_null" (wat "local.get" (Word "$node")))
                (wat "i32.const" (int (operation-index info operation)))
                (wat* "struct.new"
                      (Cons (id (arguments-type m operation params))
                            (map (lambda (name) (wat "local.get" (id name))) names)))
                (wat "ref.null" (id (frames-type m))))))

    (: operation-index (-> Effect String I64))
    (define (operation-index info operation)
      (match (list-index (lambda (o) (string=? o operation)) (Effect-operations info))
        ((Some index) index)
        ((None) (panic "internal error: unknown operation"))))

    ;; An operation's arguments, as the record holds them.
    (: arguments-type (-> Module String (List Rep) String ! mut))
    (define (arguments-type m operation params)
      (let ((key (string-append "arguments." operation)))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (register-type! m
                           key
                           (wasm-id key)
                           (wat "type"
                                (id (wasm-id key))
                                (wat* "struct"
                                      (map (lambda (param) (wat "field" (rep->wat param)))
                                           params))))))))

    ;; A handle of a control effect runs its body in a block, which a yield
    ;; leaves by branching to its end with a placeholder. There the handle
    ;; catches a yield aimed at its own node; any other yield leaves the
    ;; placeholder as the handle's value, and the record set for its caller,
    ;; with the handle saved as a frame of its own (see Resuming).
    (: emit-control-handle (-> Fn Expr String (List (Pair String Expr)) Expr (List Wat) ! mut))
    (define (emit-control-handle fn expr effect implementations body)
      (let* ((info (program-effect (program-of (Fn-module fn)) effect))
             (installed (install-handler fn effect implementations))
             (label (local-id fn "handle")))
        (Cons (Pair-second installed)
              (handled-body fn expr info (Pair-first installed) label body))))

    ;; The body's value, or the implementation's when the handle catches.
    (: handled-body (-> Fn Expr Effect String String Expr (List Wat) ! mut))
    (define (handled-body fn expr info node label body)
      (let* ((m (Fn-module fn))
             (type (Expr-type expr))
             (result (fn-rep fn type))
             (value (declare-temp! fn (rep->wat result)))
             (code (emit (Fn-exit-set (Fn-evidence-set fn (wat "local.get" (id node)))
                                      (Some (ToBlock label type)))
                         body
                         #f))
             (catch (catch-yield m info type (wat "local.get" (id node)) value (Expr-loc expr))))
        (list (wat "local.set"
                   (id value)
                   (wat* "block" (Cons (id label) (Cons (wat "result" (rep->wat result)) code))))
              catch
              (move-value m result (wat "local.get" (id value))))))

    (: catch-yield (-> Module Effect Type Wat String Loc Wat ! mut))
    (define (catch-yield m info type node value loc)
      (wat "if"
           (yielding? m)
           (wat "then"
                (wat "local.set" (id value) (wat "call" (id (catcher m info type loc)) node)))))

    ;; What a handle does with the yield that has reached it, for one
    ;; effect and handle result type; the handle site and `resume` both
    ;; end here. A yield aimed at another node leaves the handle, which
    ;; saves itself as one frame, and the handle's value is a placeholder.
    ;; One aimed at `node` is caught: the record is cleared, the yield's
    ;; frames become a continuation, and the implementation of the recorded
    ;; operation runs in the context outside the node, with the recorded
    ;; arguments and a `resume` holding the continuation. Its call is a
    ;; tail call, so a handler that resumes in tail position runs in
    ;; constant stack however many times its operation is performed.
    (: catcher (-> Module Effect Type Loc String ! mut))
    (define (catcher m info type loc)
      (helper! m "catch" (string-append (Effect-name info) " " (type-key type))
               (lambda (function-id)
                 (wat* "func"
                       (concatenate (list (list (id function-id)
                                                (wat "param" (Word "$node") (evidence-ref m))
                                                (wat "result" (rep->wat (rep m type))))
                                          (dispatch-locals m info type)
                                          (list (pass-on m info type loc))
                                          (take-continuation m)
                                          (map (lambda (operation)
                                                 (dispatch-case m info type operation loc))
                                               (Effect-control info))
                                          (list (wat "unreachable"))))))))

    (: pass-on (-> Module Effect Type Loc Wat ! mut))
    (define (pass-on m info type loc)
      (let ((node (wat "local.get" (Word "$node"))))
        (wat "if"
             (wat "i32.eqz" (aimed-at? m node))
             (wat "then"
                  (enclose m (Handling info loc) type node)
                  (wat "return" (placeholder m type loc))))))

    (: dispatch-locals (-> Module Effect Type (List Wat) ! mut))
    (define (dispatch-locals m info type)
      (append (list (wat "local" (Word "$record") (wat "ref" (id (yield-type m))))
                    (wat "local" (Word "$continuation") (wat "ref" (id (continuation-type m)))))
              (map (lambda (operation)
                     (wat "local"
                          (implementation-local info operation)
                          (wat "ref" (id (implementation-base m operation type)))))
                   (Effect-control info))))

    (: take-continuation (-> Module (List Wat) ! mut))
    (define (take-continuation m)
      (let ((frames
             (wat "struct.get" (id (yield-type m)) (int 3) (wat "local.get" (Word "$record")))))
        (list (wat "local.set"
                   (Word "$record")
                   (wat "ref.as_non_null" (wat "global.get" (id (yielding m)))))
              (wat "global.set" (id (yielding m)) (wat "ref.null" (id (yield-type m))))
              (wat "local.set" (Word "$continuation")
                   (wat "struct.new"
                        (id (continuation-type m))
                        (wat "call" (id (reverse-helper m)) frames)
                        (wat "local.get" (Word "$node")))))))

    ;; The implementation of a control operation, if the record names it,
    ;; taken from the handler at the node.
    (: dispatch-case (-> Module Effect Type String Loc Wat ! mut))
    (define (dispatch-case m info type operation loc)
      (let* ((index (operation-index info operation))
             (base (implementation-base m operation type))
             (local (implementation-local info operation))
             (node (wat "local.get" (Word "$node")))
             (outer (wat "ref.as_non_null" (wat "struct.get" (id (evidence-type m)) (int 2) node)))
             (arguments (recorded-arguments m operation (wat "local.get" (Word "$record")))))
        (wat "if"
             (wat "i32.eq"
                  (wat "struct.get" (id (yield-type m)) (int 1) (wat "local.get" (Word "$record")))
                  (wat "i32.const" (int index)))
             (wat "then"
                  (wat "local.set"
                       local
                       (wat "ref.cast" (wat "ref" (id base)) (handler-field m info node index)))
                  (closure-call-wat m
                                    base
                                    (wat "local.get" local)
                                    (Cons outer
                                          (if (answers-never? m operation)
                                              arguments
                                              (append arguments
                                                      (list
                                                       (resume-owner m info operation type loc)))))
                                    #t)))))

    (: implementation-local (-> Effect String Wat))
    (define (implementation-local info operation)
      (Word (string-append "$implementation." (i64->string (operation-index info operation)))))

    ;; An implementation's closure type: the operation's arguments and
    ;; `resume`, an owner, to the handle's result. An operation that answers
    ;; Never has no `resume`.
    (: implementation-base (-> Module String Type String ! mut))
    (define (implementation-base m operation type)
      (let ((params (Pair-first (function-signature m (operation-type m operation)))))
        (closure-type m
                      (if (answers-never? m operation)
                          params
                          (append params (list (Reference (owned-type m)))))
                      (rep m type))))

    (: handler-field (-> Module Effect Wat I64 Wat ! mut))
    (define (handler-field m info node index)
      (let ((handler (handler-type m (Effect-name info))))
        (wat "struct.get"
             (id handler)
             (int index)
             (wat "ref.cast"
                  (wat "ref" (id handler))
                  (wat "struct.get" (id (evidence-type m)) (int 1) node)))))

    (: recorded-arguments (-> Module String Wat (List Wat) ! mut))
    (define (recorded-arguments m operation record)
      (let* ((params (Pair-first (function-signature m (operation-type m operation))))
             (type (arguments-type m operation params))
             (held (wat "ref.cast"
                        (wat "ref" (id type))
                        (wat "struct.get" (id (yield-type m)) (int 2) record))))
        (map-indexed (lambda (index param) (wat "struct.get" (id type) (int index) held)) params)))

    ;; ---- Resuming ----

    ;; A continuation is the frames saved inside a handle's body, innermost
    ;; first, and the handle's node. `resume` is a closure over the one a
    ;; caught yield saved, which its owner makes one-shot. Calling it takes
    ;; the frames out, sets the node's outer evidence to the caller's, so
    ;; that the computation resumes under the handlers in scope where
    ;; `resume` is called, and runs the frames on the answer, as the handle
    ;; again: the handler is deep, so a yield aimed at the node runs the
    ;; handler again, in tail position, as the handle site would, even after
    ;; that handle has returned. A handle that any other yield leaves, at
    ;; its site or resumed, becomes one frame holding the continuation
    ;; inside it, so resuming the outer computation enters the handle again
    ;; too. Dropping `resume` drops the continuation: its frames are garbage,
    ;; and the owned values they hold are dropped with them, as with any
    ;; dropped `Once`.
    (: continuation-type (-> Module String ! mut))
    (define (continuation-type m)
      (match (known-type m "continuation")
        ((Some type) type)
        ((None)
         (let ((frames (frames-type m)))
           (register-type! m "continuation" "$continuation"
                           (wat "type" (id "$continuation")
                                (wat "struct"
                                     (wat "field" (wat "mut" (wat "ref" (Word "null") (id frames))))
                                     (wat "field" (evidence-ref m)))))))))

    ;; `resume`, a closure of the operation's answer to the handle's result.
    (: resume-type (-> Module String String ! mut))
    (define (resume-type m base)
      (let ((name (wasm-id (string-append (substring base 1 (string-length base)) "+resume"))))
        (match (known-type m name)
          ((Some type) type)
          ((None)
           (register-type! m name name
                           (wat "type" (id name)
                                (wat "sub" (Word "final") (id base)
                                     (wat "struct"
                                          (wat "field" (wat "ref" (id (code-type m base))))
                                          (wat "field"
                                               (wat "ref" (id (continuation-type m))))))))))))

    (: resume-base (-> Module String Type String ! mut))
    (define (resume-base m operation type)
      (closure-type m (list (rep m (operation-result m operation))) (rep m type)))

    (: resume-owner (-> Module Effect String Type Loc Wat ! mut))
    (define (resume-owner m info operation type loc)
      (let ((base (resume-base m operation type)))
        (wat "struct.new" (id (owned-type m))
             (wat "struct.new"
                  (id (resume-type m base))
                  (wat "ref.func" (id (resume-code m info operation type loc)))
                  (wat "local.get" (Word "$continuation"))))))

    ;; The code of an operation's `resume`: the handle again, run on the
    ;; boxed answer under the caller's evidence.
    (: resume-code (-> Module Effect String Type Loc String ! mut))
    (define (resume-code m info operation type loc)
      (helper! m "resume" (string-append operation " " (type-key type))
               (lambda (function-id)
                 (let* ((base (resume-base m operation type)) (resume (resume-type m base)))
                   (push! (Module-declared m) function-id)
                   (Word
                    (fill
                     "(func {id} (type {code}) (param $closure (ref {base})) (param $ev (ref {evidence})) (param $answer {answer}) (result {result})
  (return_call {rehandle} (struct.get {resume} 1 (ref.cast (ref {resume}) (local.get $closure))) (local.get $ev) {boxed}))"
                     (list (Pair "id" function-id)
                           (Pair "code" (code-type m base))
                           (Pair "base" base)
                           (Pair "evidence" (evidence-type m))
                           (Pair "answer"
                                 (wat->text (rep->wat (rep m (operation-result m operation)))))
                           (Pair "result" (wat->text (rep->wat (rep m type))))
                           (Pair "rehandle" (rehandler m (Handling info loc) type))
                           (Pair "resume" resume)
                           (Pair "boxed"
                                 (wat->text (box-value m
                                                       (operation-result m operation)
                                                       (wat "local.get" (Word "$answer"))))))))))))

    ;; Where a handle's saved frames end when a yield reaches them: at an
    ;; effect's handler, which catches the yields aimed at its node, or at
    ;; a forwarding node's catch, which re-aims them (see Latent effects).
    ;; Each has its own helpers, named by the effect and the handle's type.
    (enum Catch
      (Handling
       ((info Effect)
        (loc Loc)))
      (Forwarding
       ((info Effect))))

    (: catch-helper (-> Module Catch Type String ! mut))
    (define (catch-helper m catch type)
      (match catch
        ((Handling info loc) (catcher m info type loc))
        ((Forwarding info) (forwarder m info type))))

    (: catch-prefix (-> Catch String String))
    (define (catch-prefix catch prefix)
      (match catch
        ((Handling _ _) prefix)
        ((Forwarding _) (string-append "forward-" prefix))))

    (: catch-key (-> Catch Type String))
    (define (catch-key catch type)
      (let ((info (match catch ((Handling info _) info) ((Forwarding info) info))))
        (string-append (Effect-name info) " " (type-key type))))

    ;; The handle again, for one catch and handle result type: the
    ;; continuation run on a boxed value under `$ev`, ending, if a yield
    ;; reaches it, in the handle's catch, in tail position.
    (: rehandler (-> Module Catch Type String ! mut))
    (define (rehandler m catch type)
      (helper! m (catch-prefix catch "rehandle") (catch-key catch type)
               (lambda (function-id)
                 (Word
                  (fill
                   "(func {id} (param $continuation (ref {continuation})) (param $ev (ref {evidence})) (param $value anyref) (result {result})
  (local.set $value (call {continue} (local.get $continuation) (local.get $ev) (local.get $value)))
  (if {yielding} (then (return_call {catch} (struct.get {continuation} 1 (local.get $continuation)))))
  {unboxed})"
                   (list (Pair "id" function-id)
                         (Pair "continuation" (continuation-type m))
                         (Pair "evidence" (evidence-type m))
                         (Pair "result" (wat->text (rep->wat (rep m type))))
                         (Pair "continue" (continue-helper m))
                         (Pair "yielding" (wat->text (yielding? m)))
                         (Pair "catch" (catch-helper m catch type))
                         (Pair "unboxed"
                               (wat->text
                                (unbox-value m type (wat "local.get" (Word "$value")))))))))))

    ;; A handle that a yield leaves, saved as a frame: the frames saved
    ;; inside its body, as a continuation for its node. Run, it is the
    ;; handle again, under the evidence outside its node as it stands,
    ;; since whatever resumed the computation around it rebased that, and
    ;; it boxes the handle's result.
    (: handled-type (-> Module String ! mut))
    (define (handled-type m)
      (match (known-type m "handled")
        ((Some type) type)
        ((None)
         (let ((frame (frame-type m)))
           (register-type! m "handled" "$handled"
                           (wat "type" (id "$handled")
                                (wat "sub" (Word "final") (id frame)
                                     (wat "struct"
                                          (wat "field" (wat "ref" (id (code-type m frame))))
                                          (wat "field"
                                               (wat "ref" (id (continuation-type m))))))))))))

    (: handled-code (-> Module Catch Type String ! mut))
    (define (handled-code m catch type)
      (helper! m (catch-prefix catch "handled") (catch-key catch type)
               (lambda (function-id)
                 (let ((frame (frame-type m)) (continuation (continuation-type m)))
                   (push! (Module-declared m) function-id)
                   (Word
                    (fill
                     "(func {id} (type {code}) (param $frame (ref {frame})) (param $value anyref) (result anyref)
  (local $continuation (ref {continuation}))
  (local.set $continuation (struct.get {handled} 1 (ref.cast (ref {handled}) (local.get $frame))))
  {boxed})"
                     (list (Pair "id" function-id)
                           (Pair "code" (code-type m frame))
                           (Pair "frame" frame)
                           (Pair "continuation" continuation)
                           (Pair "handled" (handled-type m))
                           (Pair "boxed"
                                 (wat->text (box-value m
                                                       type
                                                       (wat "call"
                                                            (id (rehandler m catch type))
                                                            (wat "local.get" (Word "$continuation"))
                                                            (wat "ref.as_non_null"
                                                                 (wat "struct.get"
                                                                      (id (evidence-type m))
                                                                      (int 2)
                                                                      (wat "struct.get"
                                                                           (id continuation)
                                                                           (int 1)
                                                                           (wat "local.get"
                                                                                (Word
                                                                                 "$continuation")))))
                                                            (wat "local.get"
                                                                 (Word "$value")))))))))))))

    ;; Saves the handle at `node`, which a yield is leaving, as one frame
    ;; in place of the frames saved inside its body.
    (: enclose (-> Module Catch Type Wat Wat ! mut))
    (define (enclose m catch type node)
      (wat "call" (id (enclose-helper m)) node (wat "ref.func" (id (handled-code m catch type)))))

    (: enclose-helper (-> Module String ! mut))
    (define (enclose-helper m)
      (template-helper! m "control" "enclose"
                        "(func {id} (param $node (ref {evidence})) (param $code (ref {code}))
  (local $record (ref {yield}))
  (local.set $record (ref.as_non_null (global.get {yielding})))
  (struct.set {yield} 3 (local.get $record)
    (struct.new {frames}
      (struct.new {handled} (local.get $code) (struct.new {continuation} (call {reverse} (struct.get {yield} 3 (local.get $record))) (local.get $node)))
      (ref.null {frames}))))"
                        (list (Pair "evidence" (evidence-type m))
                              (Pair "code" (code-type m (frame-type m)))
                              (Pair "yield" (yield-type m))
                              (Pair "yielding" (yielding m))
                              (Pair "frames" (frames-type m))
                              (Pair "handled" (handled-type m))
                              (Pair "continuation" (continuation-type m))
                              (Pair "reverse" (reverse-helper m)))))

    ;; Runs a continuation: it rebases the node on the caller's evidence
    ;; and takes the frames out, so that neither the continuation nor
    ;; `resume` holds them while they run. Then each frame runs in turn,
    ;; innermost first, on the value the one before produced. When a frame
    ;; yields, the frames after it are saved on the record in turn, as if
    ;; the yield were leaving them, and the loop returns with the record
    ;; set, so its caller leaves too. A handle among the frames is one
    ;; frame that runs the frames inside it itself, so a yield aimed at
    ;; that handle is caught there and never passes through this loop.
    (: continue-helper (-> Module String ! mut))
    (define (continue-helper m)
      (let ((frame (frame-type m)))
        (template-helper! m "control" "continue"
                          "(func {id} (param $continuation (ref {continuation})) (param $ev (ref {evidence})) (param $value anyref) (result anyref)
  (local $frames (ref null {frames}))
  (local $frame (ref {frame}))
  (struct.set {evidence} 2 (struct.get {continuation} 1 (local.get $continuation)) (local.get $ev))
  (local.set $frames (struct.get {continuation} 0 (local.get $continuation)))
  (struct.set {continuation} 0 (local.get $continuation) (ref.null {frames}))
  (loop $next
    (if (ref.is_null (local.get $frames)) (then (return (local.get $value))))
    (local.set $frame (struct.get {frames} 0 (ref.as_non_null (local.get $frames))))
    (local.set $frames (struct.get {frames} 1 (ref.as_non_null (local.get $frames))))
    (if (ref.is_null (global.get {yielding}))
      (then (local.set $value (call_ref {code} (local.get $frame) (local.get $value) (struct.get {frame} 0 (local.get $frame)))))
      (else (call {push} (local.get $frame))))
    (br $next))
  (unreachable))"
                          (list (Pair "continuation" (continuation-type m))
                                (Pair "evidence" (evidence-type m))
                                (Pair "frames" (frames-type m))
                                (Pair "frame" frame)
                                (Pair "code" (code-type m frame))
                                (Pair "yielding" (yielding m))
                                (Pair "push" (push-helper m))))))

    (: reverse-helper (-> Module String ! mut))
    (define (reverse-helper m)
      (template-helper! m "control" "reverse"
                        "(func {id} (param $frames (ref null {frames})) (result (ref null {frames}))
  (local $reversed (ref null {frames}))
  (block $done
    (loop $next
      (br_if $done (ref.is_null (local.get $frames)))
      (local.set $reversed (struct.new {frames} (struct.get {frames} 0 (ref.as_non_null (local.get $frames))) (local.get $reversed)))
      (local.set $frames (struct.get {frames} 1 (ref.as_non_null (local.get $frames))))
      (br $next)))
  (local.get $reversed))"
                        (list (Pair "frames" (frames-type m)))))

    ;; ---- Latent effects ----

    ;; An ordinary operation's implementation runs under the handlers
    ;; outside its own, except for the effects its latent row names, which
    ;; go to the handlers in scope where the operation was performed: the
    ;; performer was charged those, so they are the ones every frame between
    ;; the two tests for. The performer therefore calls the implementation
    ;; under a forwarding node for each such effect, over the evidence
    ;; outside its handler. A forwarding node's handler holds the
    ;; performer's evidence in each control field, and in each ordinary
    ;; field a closure that performs the operation again under it. A yield
    ;; aimed at a forwarding node is caught as the call returns, re-aimed
    ;; at the first node for its effect in the performer's evidence, and
    ;; passed on, with the forwarding node's catch saved as a frame, so a
    ;; yield after the implementation is resumed is re-aimed too. Resumed
    ;; elsewhere, the implementation keeps the evidence outside its handler,
    ;; whose handles may have returned; that is sound because its yields go
    ;; only to forwarded effects (see control.sld), so only ordinary
    ;; operations reach that evidence. The builtin effects, mut and tasks,
    ;; which no evidence carries, need no node.
    (: forwarded-effects (-> Module String (List Effect)))
    (define (forwarded-effects m operation)
      (match (program-value (program-of m) operation)
        ((Some (Operation effect scheme))
         (map (lambda (label) (program-effect (program-of m) label))
              (filter (lambda (label) (table-contains? (Program-effects (program-of m)) label))
                      (operation-latent effect scheme))))
        (_ (panic "internal error: not an operation"))))

    ;; The performer's locals for forwarding: the result, and a node per
    ;; forwarded effect.
    (: forwarding-locals (-> Module String Rep (List Wat) ! mut))
    (define (forwarding-locals m operation result)
      (let ((effects (forwarded-effects m operation)))
        (if (null? effects)
            (Nil)
            (Cons (wat "local" (Word "$forwarded") (rep->wat result))
                  (map (lambda (index) (wat "local" (latent-local index) (evidence-ref m)))
                       (iota (length effects)))))))

    (: latent-local (-> I64 Wat))
    (define (latent-local index)
      (Word (string-append "$latent." (i64->string index))))

    ;; At the effect's node: a forwarding node per forwarded effect, each
    ;; over the one before and the first over the evidence outside the
    ;; node; the implementation called under the last; then the catch of
    ;; each node of a control effect, innermost first.
    (: forwarding-call (-> Module Effect String (List String) (List Rep) Rep (List Wat) ! mut))
    (define (forwarding-call m info operation names params result)
      (let* ((effects (forwarded-effects m operation))
             (last-node (wat "local.get" (latent-local (- (length effects) 1))))
             (outside (lambda (index)
                        (if (= index 0)
                            (node-outside m (wat "local.get" (Word "$node")))
                            (wat "local.get" (latent-local (- index 1)))))))
        (concatenate
         (list (map-indexed (lambda (index effect)
                              (wat "local.set"
                                   (latent-local index)
                                   (forwarding-node m effect (outside index))))
                            effects)
               (list (wat "local.set"
                          (Word "$forwarded")
                          (implementation-call m info operation names params result last-node)))
               (reverse (forwarding-catches m effects (operation-result m operation)))
               (list (wat "return" (wat "local.get" (Word "$forwarded"))))))))

    (: forwarding-catches (-> Module (List Effect) Type (List Wat) ! mut))
    (define (forwarding-catches m effects type)
      (concatenate (map-indexed (lambda (index effect)
                                  (if (null? (Effect-control effect))
                                      (Nil)
                                      (list (wat "if" (yielding? m)
                                                 (wat "then" (wat "local.set" (Word "$forwarded")
                                                                  (wat "call"
                                                                       (id
                                                                        (forwarder m effect type))
                                                                       (wat "local.get"
                                                                            (latent-local
                                                                             index)))))))))
                                effects)))

    ;; A forwarding node for an effect over `outside`, whose handler sends
    ;; each of the effect's operations to the performer's evidence, `$ev`.
    (: forwarding-node (-> Module Effect Wat Wat ! mut))
    (define (forwarding-node m info outside)
      (wat "struct.new" (id (evidence-type m)) (effect-label (Effect-name info))
           (wat* "struct.new"
                 (Cons (id (handler-type m (Effect-name info)))
                       (map (lambda (operation) (forwarding-field m info operation))
                            (Effect-operations info))))
           outside))

    (: forwarding-field (-> Module Effect String Wat ! mut))
    (define (forwarding-field m info operation)
      (if (member? operation (Effect-control info))
          (wat "local.get" (Word "$ev"))
          (wat "struct.new"
               (id (forwarding-closure m operation))
               (wat "ref.func" (id (forwarding-code m info operation)))
               (wat "local.get" (Word "$ev")))))

    ;; An ordinary operation's closure that holds the evidence to perform it
    ;; under.
    (: forwarding-closure (-> Module String String ! mut))
    (define (forwarding-closure m operation)
      (let ((signature (function-signature m (operation-type m operation))))
        (capture-type m
                      (closure-type m (Pair-first signature) (Pair-second signature))
                      (list (evidence-rep m)))))

    ;; Its code: the operation performed under the evidence it holds.
    (: forwarding-code (-> Module Effect String String ! mut))
    (define (forwarding-code m info operation)
      (helper! m "forward" operation
               (lambda (function-id)
                 (let* ((signature (function-signature m (operation-type m operation)))
                        (closure (forwarding-closure m operation))
                        (base (closure-type m (Pair-first signature) (Pair-second signature)))
                        (names
                         (map (lambda (index) (string-append "$argument." (i64->string index)))
                              (iota (length (Pair-first signature)))))
                        (held (wat "struct.get"
                                   (id closure)
                                   (int 1)
                                   (wat "ref.cast"
                                        (wat "ref" (id closure))
                                        (wat "local.get" (Word "$closure"))))))
                   (push! (Module-declared m) function-id)
                   (wat* "func"
                         (concatenate (list (list (id function-id)
                                                  (wat "type" (id (code-type m base)))
                                                  (wat "param"
                                                       (Word "$closure")
                                                       (wat "ref" (id base)))
                                                  (evidence-param m))
                                            (map (lambda (pair)
                                                   (wat "param"
                                                        (id (Pair-first pair))
                                                        (rep->wat (Pair-second pair))))
                                                 (zip names (Pair-first signature)))
                                            (list (wat "result" (rep->wat (Pair-second signature)))
                                                  (wat* "return_call"
                                                        (Cons (id (performer m
                                                                             (Effect-name info)
                                                                             operation))
                                                              (Cons held
                                                                    (map (lambda (name)
                                                                           (wat "local.get"
                                                                                (id name)))
                                                                         names))))))))))))

    ;; A forwarding node's catch: a yield aimed at the node is re-aimed at
    ;; the performer's handler. Either way the yield leaves, and the node's
    ;; catch is saved as a frame (see Resuming).
    (: forwarder (-> Module Effect Type String ! mut))
    (define (forwarder m info type)
      (helper! m "forward-catch" (string-append (Effect-name info) " " (type-key type))
               (lambda (function-id)
                 (let ((node (wat "local.get" (Word "$node"))))
                   (wat "func"
                        (id function-id)
                        (wat "param" (Word "$node") (evidence-ref m))
                        (wat "result" (rep->wat (rep m type)))
                        (wat "if"
                             (aimed-at? m node)
                             (wat "then" (wat "call" (id (retargeter m info)) node)))
                        (enclose m (Forwarding info) type node)
                        (placeholder m type no-loc))))))

    ;; Sets the record, aimed at a forwarding node, to aim at the first node
    ;; for the node's effect in the performer's evidence, which the node's
    ;; handler holds, with the same operation, arguments and frames.
    (: retargeter (-> Module Effect String ! mut))
    (define (retargeter m info)
      (template-helper! m "retarget" (Effect-name info)
                        "(func {id} (param $node (ref {evidence}))
  (local $record (ref {yield}))
  (local $target (ref null {evidence}))
  (local.set $record (ref.as_non_null (global.get {yielding})))
  (local.set $target (ref.cast (ref {evidence}) (struct.get {handler} {index} (ref.cast (ref {handler}) (struct.get {evidence} 1 (local.get $node))))))
  (loop $walk
    (if (ref.is_null (local.get $target)) (then (call {panic} {message}) (unreachable)))
    (if (i32.eq (struct.get {evidence} 0 (local.get $target)) {label})
      (then (global.set {yielding} (struct.new {yield} (ref.as_non_null (local.get $target)) (struct.get {yield} 1 (local.get $record))
                                     (struct.get {yield} 2 (local.get $record)) (struct.get {yield} 3 (local.get $record))))
            (return)))
    (local.set $target (struct.get {evidence} 2 (local.get $target)))
    (br $walk)))"
                        (list (Pair "evidence" (evidence-type m))
                              (Pair "yield" (yield-type m))
                              (Pair "yielding" (yielding m))
                              (Pair "handler" (handler-type m (Effect-name info)))
                              (Pair "index"
                                    (i64->string (operation-index info (first-control info))))
                              (Pair "panic" (panic-helper m))
                              (Pair "message"
                                    (wat->text (string-literal m
                                                               (string-append "unhandled effect "
                                                                              (short-name
                                                                               (Effect-name
                                                                                info))))))
                              (Pair "label" (wat->text (effect-label (Effect-name info)))))))

    (: first-control (-> Effect String))
    (define (first-control info)
      (match (Effect-control info)
        ((Cons operation _) operation)
        ((Nil) (panic "internal error: not a control effect"))))

    ;; ---- Primitives ----

    ;; Primitives with a single Wasm instruction.
    (: instruction-primitives (List (Pair String String)))
    (define instruction-primitives
      (list (Pair "i32-add" "i32.add")
            (Pair "i32-sub" "i32.sub")
            (Pair "i32-mul" "i32.mul")
            (Pair "i32-quotient" "i32.div_s")
            (Pair "i32-remainder" "i32.rem_s")
            (Pair "i32-and" "i32.and")
            (Pair "i32-or" "i32.or")
            (Pair "i32-xor" "i32.xor")
            (Pair "i32-shift-left" "i32.shl")
            (Pair "i32-shift-right" "i32.shr_s")
            (Pair "i32-shift-right/logical" "i32.shr_u")
            (Pair "i32-eq" "i32.eq")
            (Pair "i32-lt" "i32.lt_s")
            (Pair "i32-le" "i32.le_s")
            (Pair "i32-gt" "i32.gt_s")
            (Pair "i32-ge" "i32.ge_s")
            (Pair "i64-add" "i64.add")
            (Pair "i64-sub" "i64.sub")
            (Pair "i64-mul" "i64.mul")
            (Pair "i64-quotient" "i64.div_s")
            (Pair "i64-remainder" "i64.rem_s")
            (Pair "i64-and" "i64.and")
            (Pair "i64-or" "i64.or")
            (Pair "i64-xor" "i64.xor")
            (Pair "i64-shift-left" "i64.shl")
            (Pair "i64-shift-right" "i64.shr_s")
            (Pair "i64-shift-right/logical" "i64.shr_u")
            (Pair "i64-eq" "i64.eq")
            (Pair "i64-lt" "i64.lt_s")
            (Pair "i64-le" "i64.le_s")
            (Pair "i64-gt" "i64.gt_s")
            (Pair "i64-ge" "i64.ge_s")
            (Pair "f32-add" "f32.add")
            (Pair "f32-sub" "f32.sub")
            (Pair "f32-mul" "f32.mul")
            (Pair "f32-div" "f32.div")
            (Pair "f32-min" "f32.min")
            (Pair "f32-max" "f32.max")
            (Pair "f32-eq" "f32.eq")
            (Pair "f32-lt" "f32.lt")
            (Pair "f32-le" "f32.le")
            (Pair "f32-gt" "f32.gt")
            (Pair "f32-ge" "f32.ge")
            (Pair "f32-sqrt" "f32.sqrt")
            (Pair "f32-abs" "f32.abs")
            (Pair "f32-negate" "f32.neg")
            (Pair "f32-floor" "f32.floor")
            (Pair "f32-ceiling" "f32.ceil")
            (Pair "f32-truncate" "f32.trunc") (Pair "f32-round" "f32.nearest")
            (Pair "f64-add" "f64.add")
            (Pair "f64-sub" "f64.sub")
            (Pair "f64-mul" "f64.mul")
            (Pair "f64-div" "f64.div")
            (Pair "f64-min" "f64.min")
            (Pair "f64-max" "f64.max")
            (Pair "f64-eq" "f64.eq")
            (Pair "f64-lt" "f64.lt")
            (Pair "f64-le" "f64.le")
            (Pair "f64-gt" "f64.gt")
            (Pair "f64-ge" "f64.ge")
            (Pair "f64-sqrt" "f64.sqrt")
            (Pair "f64-abs" "f64.abs")
            (Pair "f64-negate" "f64.neg")
            (Pair "f64-floor" "f64.floor")
            (Pair "f64-ceiling" "f64.ceil")
            (Pair "f64-truncate" "f64.trunc") (Pair "f64-round" "f64.nearest")
            (Pair "i32->i64" "i64.extend_i32_s")
            (Pair "i64->i32" "i32.wrap_i64")
            (Pair "i64->f64" "f64.convert_i64_s")
            (Pair "f64->i64" "i64.trunc_sat_f64_s")
            (Pair "i32->f64" "f64.convert_i32_s")
            (Pair "f64->i32" "i32.trunc_sat_f64_s")
            (Pair "i32->f32" "f32.convert_i32_s")
            (Pair "f32->i32" "i32.trunc_sat_f32_s")
            (Pair "i64->f32" "f32.convert_i64_s")
            (Pair "f32->i64" "i64.trunc_sat_f32_s")
            (Pair "f32->f64" "f64.promote_f32")
            (Pair "f64->f32" "f32.demote_f64")
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
          ((None)
           (special-primitive fn operation args (emit-args fn args) (map Expr-type args) type)))))

    ;; Strings and character vectors share one representation.
    (: special-primitive (-> Fn String (List Expr) (List Wat) (List Type) Type (List Wat) ! mut))
    (define (special-primitive fn operation args code types type)
      (let* ((m (Fn-module fn))
             (arg (lambda (n) (list-ref code n)))
             (sequence (lambda (t) (reference-type (rep m t)))))
        (case operation
          (("unit") (list (wat "i32.const" (int 0))))
          (("once") (list (wat "struct.new" (id (owned-type m)) (arg 0))))
          (("call-once") (list (wat "call" (id (call-once-helper m)) (arg 0) (Fn-evidence fn))))
          (("dispatch-local") (dispatch-work m (arg 0) (Fn-evidence fn)))
          (("yield-task" "sleep-task" "park-task" "unpark-task" "current-task")
           (host-call m (task-import operation) (TFun types type empty-row) code no-loc))
          (("drop") (list (clear-owner m (arg 0)) (wat "i32.const" (int 0))))
          (("unsafe-total") (closure-call fn (first-arg args) (Nil) #f))
          (("unsafe-cast") (list (funcref-closure m type (arg 0))))
          (("dynamic-cast") (list (dynamic-cast fn type (list-ref types 1) (arg 0) (arg 1))))
          (("panic") (list (wat* "call" (Cons (id (panic-helper m)) code)) (wat "unreachable")))
          (("bool->i32" "char->i32" "i32->char" "string->vector" "vector->string" "u8->i32") code)
          (("i32->u8") (list (wat "i32.and" (arg 0) (wat "i32.const" (int 255)))))
          (("i32->bool") (list (wat "i32.ne" (arg 0) (wat "i32.const" (int 0)))))
          (("string-length" "vector-length" "array-length")
           (list (wat "i64.extend_i32_u" (wat "array.len" (arg 0)))))
          (("string-ref" "vector-ref" "array-ref")
           (let ((array (sequence (first-type types))))
             (list (wat (array-get array) (id array) (arg 0) (index (arg 1))))))
          (("array-set!")
           (list
            (wat "array.set" (id (sequence (first-type types))) (arg 0) (index (arg 1)) (arg 2))
            (wat "i32.const" (int 0))))
          (("make-string" "make-vector" "make-array")
           (list (wat "array.new" (id (sequence type)) (arg 1) (index (arg 0)))))
          (("string-append" "vector-append")
           (list (wat* "call" (Cons (id (append-helper m (sequence type))) code))))
          (("substring" "subvector")
           (list (wat* "call" (Cons (id (slice-helper m (sequence type))) code))))
          (("vector-set")
           (list (wat* "call"
                       (Cons (id (set-helper m (sequence type) (fn-rep fn (list-ref types 2))))
                             code))))
          (("array->vector" "vector->array")
           (list (wat* "call" (Cons (id (copy-helper m (sequence type))) code))))
          (("array-copy!" "vector-copy!")
           (let ((array (id (sequence (first-type types)))))
             (list (wat "array.copy"
                        array
                        array
                        (arg 0)
                        (index (arg 1))
                        (arg 2)
                        (index (arg 3))
                        (index (arg 4)))
                   (wat "i32.const" (int 0)))))
          (("string=?") (list (wat* "call" (Cons (id (string-equal-helper m)) code))))
          (("string-compare") (list (wat* "call" (Cons (id (string-compare-helper m)) code))))
          (("vector-generate" "string-generate")
           (list (wat* "call"
                       (Cons (id (generate-helper m (sequence type) (list-ref types 1)))
                             (append code (list (Fn-evidence fn)))))))
          (("ref")
           (list (wat* "struct.new" (Cons (id (cell-type m (fn-rep fn (first-type types)))) code))))
          (("ref-get")
           (list
            (wat* "struct.get" (Cons (id (cell-type m (fn-rep fn type))) (Cons (int 0) code)))))
          (("ref-set!")
           (list (wat* "struct.set"
                       (Cons (id (cell-type m (fn-rep fn (list-ref types 1)))) (Cons (int 0) code)))
                 (wat "i32.const" (int 0))))
          (else (panic (string-append "internal error: unknown primitive " operation))))))

    ;; ---- Owned values ----

    ;; Every linear value is a cell with a nullable payload. A move clears
    ;; its source and allocates a fresh cell, so stale locals and captures
    ;; cannot retain owned descendants after the new owner drops them.
    ;; This is shallow transfer, not a deep copy or a GC timing promise.
    (: owned-type (-> Module String ! mut))
    (define (owned-type m)
      (match (known-type m "owned")
        ((Some type) type)
        ((None) (register-type! m "owned" "$owned"
                                (wat "type"
                                     (id "$owned")
                                     (wat "struct" (wat "field" (wat "mut" (Word "anyref")))))))))

    (: clear-owner (-> Module Wat Wat ! mut))
    (define (clear-owner m value)
      (wat "struct.set" (id (owned-type m)) (int 0) value (wat "ref.null" (Word "any"))))

    (: move-value (-> Module Rep Wat Wat ! mut))
    (define (move-value m representation value)
      (match representation
        ((Reference "$owned")
         (wat "struct.new" (id (owned-type m)) (wat "call" (id (take-owned-helper m)) value)))
        (_ value)))

    ;; The raw payload lives only in this helper's frame. In particular it
    ;; never remains in a caller's scratch local across an I/O suspension.
    (: take-owned-helper (-> Module String ! mut))
    (define (take-owned-helper m)
      (template-helper! m "take-owned" ""
                        "(func {id} (param $owner (ref {owner})) (result (ref any))
  (local $value (ref any))
  (local.set $value (ref.as_non_null (struct.get {owner} 0 (local.get $owner))))
  (struct.set {owner} 0 (local.get $owner) (ref.null any))
  (local.get $value))" (list (Pair "owner" (owned-type m)))))

    (: call-once-helper (-> Module String ! mut))
    (define (call-once-helper m)
      (let ((closure (closure-type m (Nil) (Scalar "i32"))))
        (template-helper! m "call-once" ""
                          "(func {id} (param $owner (ref {owner})) (param $ev (ref {evidence})) (result i32)
  (local $closure (ref {closure}))
  (local.set $closure (ref.cast (ref {closure}) (call {take} (local.get $owner))))
  (return_call_ref {code} (local.get $closure) (local.get $ev) (struct.get {closure} 0 (local.get $closure))))"
                          (list (Pair "owner" (owned-type m))
                                (Pair "closure" closure)
                                (Pair "code" (code-type m closure))
                                (Pair "take" (take-owned-helper m))
                                (Pair "evidence" (evidence-type m))))))

    ;; The host receives an opaque owner, the evidence of the dispatch, and
    ;; two typed Wasm entry points. It runs the work once with that evidence,
    ;; or clears queued work on cancellation. No Snail-Core value is erased
    ;; to Any and no host needs to inspect a closure display.
    (: dispatch-work (-> Module Wat Wat (List Wat) ! mut))
    (define (dispatch-work m owner evidence)
      (let* ((run (call-once-helper m)) (release (drop-owned-helper m))
             (host (import! m (Import "snail.runtime.tasks" "dispatch")
                            (list (Scalar "funcref")
                                  (Scalar "funcref")
                                  (Reference (owned-type m))
                                  (evidence-rep m))
                            (None))))
        (push! (Module-declared m) run)
        (push! (Module-declared m) release)
        (list
         (wat "call"
              (id host)
              (wat "ref.func" (id run))
              (wat "ref.func" (id release))
              owner
              evidence)
         (wat "i32.const" (int 0)))))

    ;; The scheduler's waits and wakes are imports of "snail.runtime.tasks", each
    ;; named by its primitive without "-task": `yield`, `sleep`, `park`,
    ;; `unpark` and `current`.
    (: task-import (-> String Import))
    (define (task-import operation)
      (Import "snail.runtime.tasks" (substring operation 0 (- (string-length operation) 5))))

    (: drop-owned-helper (-> Module String ! mut))
    (define (drop-owned-helper m)
      (template-helper! m "drop-owned" ""
                        "(func {id} (param $owner (ref {owner}))
  (struct.set {owner} 0 (local.get $owner) (ref.null any)))"
                        (list (Pair "owner" (owned-type m)))))

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
           (let ((function-id (wasm-id (string-append prefix "." key))))
             (put! (Module-helpers m) full-key function-id)
             (push-function! m function-id (make function-id))
             function-id)))))

    (: template-helper! (-> Module String String String (List (Pair String String)) String ! mut))
    (define (template-helper! m prefix key template bindings)
      (helper! m
               prefix
               key
               (lambda (function-id)
                 (Word (fill template (Cons (Pair "id" function-id) bindings))))))

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
                        (list (Pair "array" array)
                              (Pair "element" (wat->text (rep->wat element))))))

    (: generate-helper (-> Module String Type String ! mut))
    (define (generate-helper m array function-type)
      (let* ((signature (function-signature m function-type))
             (base (closure-type m (Pair-first signature) (Pair-second signature))))
        (template-helper! m "generate" (string-append array " " base)
                          "(func {id} (param $count i64) (param $f (ref {base})) (param $ev (ref {evidence})) (result (ref {array}))
    (local $result (ref {array})) (local $length i32) (local $index i32)
    (local.set $length (i32.wrap_i64 (local.get $count)))
    (if (i32.eqz (local.get $length)) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} (call_ref {code} (local.get $f) (local.get $ev) (i64.const 0) (struct.get {base} 0 (local.get $f)))
                                  (local.get $length)))
    (local.set $index (i32.const 1))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (local.get $length)))
        (array.set {array} (local.get $result) (local.get $index)
                   (call_ref {code} (local.get $f) (local.get $ev) (i64.extend_i32_u (local.get $index)) (struct.get {base} 0 (local.get $f))))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    (local.get $result))"
                          (list (Pair "array" array)
                                (Pair "base" base)
                                (Pair "code" (code-type m base))
                                (Pair "evidence" (evidence-type m))))))

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
      (let ((stage (import! m
                            (Import "snail.core.support" "snail:io/stage")
                            (list (Scalar "i32"))
                            (Some (Scalar "i32")))))
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
                          (list (Pair "array" (array-type m (Scalar (if bytes? "i8" "i32"))))
                                (Pair "stage" stage)
                                (Pair "guard"
                                      (if bytes?
                                          "(if (i32.eq (array.len (local.get $text)) (i32.const -1)) (then (unreachable)))"
                                          ""))
                                (Pair "capacity"
                                      (if bytes?
                                          "(i32.add (array.len (local.get $text)) (i32.const 1))"
                                          "(array.len (local.get $text))"))
                                (Pair "header"
                                      (if bytes?
                                          "(i32.store (local.get $address) (array.len (local.get $text)))"
                                          ""))
                                (Pair "store" (if bytes? "i32.store8" "i32.store"))
                                (Pair "get" (if bytes? "array.get_u" "array.get"))
                                (Pair "offset" (if bytes? "4" "0"))
                                (Pair "shift" (if bytes? "0" "2"))
                                (Pair "result"
                                      (if bytes?
                                          "(local.get $address)"
                                          "(array.len (local.get $text))"))))))

    ;; Sends the message to the runtime one scalar at a time, then stops.
    (: panic-helper (-> Module String ! mut))
    (define (panic-helper m)
      (let ((character (import! m
                                (Import "snail.core.support" "snail:panic/character")
                                (list (Scalar "i32"))
                                (None)))
            (raise (import! m (Import "snail.core.support" "snail:panic/raise") (Nil) (None))))
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
                          (list (Pair "array" (array-type m (Scalar "i32")))
                                (Pair "character" character)
                                (Pair "raise" raise)))))

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
    (: type-groups (-> (List Wat) (List Wat)))
    (define (type-groups definitions)
      (let* ((named (fold-left (lambda (table definition)
                                 (table-set table (type-definition-name definition) definition))
                               empty-table definitions))
             (names (list->vector (sort-strings (map type-definition-name definitions))))
             (numbers
              (fold-left (lambda (table index) (table-set table (vector-ref names index) index))
                         empty-table
                         (iota (vector-length names)))))
        (map (lambda (component)
               (group-wat named (map (lambda (index) (vector-ref names index)) component)))
             (strong-components
              (vector-map (lambda (name) (type-edges named numbers name)) names)))))

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
           (sort-strings (delete-duplicates string=?
                                            (filter (lambda (word)
                                                      (and (not (string=? word name))
                                                           (table-contains? numbers word)))
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
            (merge-strings (sort-strings (take strings (quotient count 2)))
                           (sort-strings (list-drop strings (quotient count 2)))))))

    (: merge-strings (-> (List String) (List String) (List String)))
    (define (merge-strings a b)
      (match (Pair a b)
        ((Pair (Nil) _) b)
        ((Pair _ (Nil)) a)
        ((Pair (Cons x xs) (Cons y ys))
         (if (string<? y x) (Cons y (merge-strings a ys)) (Cons x (merge-strings xs b))))))

    ;; ---- Modules ----

    ;; Functions become Wasm functions and other definitions become globals.
    ;; `main` initializes the globals and runs the statements in program order.
    (: emit-module (-> Mono Wat ! mut))
    (define (emit-module mono)
      (let ((m (new-module mono (None))))
        (emit-items! m (Mono-items mono))
        (module-wat m)))

    ;; A library's module exports its monomorphic definitions under their
    ;; global names, for the modules that import them. Its `main` initializes
    ;; it; the loader runs each module's in program order.
    (: emit-library (-> Mono String Wat ! mut))
    (define (emit-library mono owner)
      (let ((m (new-module mono (Some owner))))
        (emit-items! m (Mono-items mono))
        (for-each (lambda (name) (export-definition! m name)) (Mono-exported mono))
        (module-wat m)))

    (: new-module (-> Mono (Option String) Module ! mut))
    (define (new-module mono owner)
      (Module (Mono-program mono)
              (item-definitions (Mono-items mono))
              owner
              (Mono-externals mono)
              (ref empty-table)
              (ref (Nil))
              (ref (Nil))
              (ref (Nil))
              (ref (Nil))
              (ref (Nil))
              (ref (Nil))
              (ref (Nil))
              (ref empty-table)
              (ref empty-table)
              (let ((control (control-effects (Mono-program mono))))
                (if (null? control) (None) (Some (module-callees mono control))))))

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
         (push! (Module-exports m)
                (wat "export"
                     (wat-string name)
                     (wat (if (lambda-expr? definition) "func" "global") (id (wasm-id name))))))
        ((None) (panic (string-append "internal error: nothing to export for " name)))))

    ;; The fields in the order Wasm requires: types in their recursion
    ;; groups, then imports, globals, declared function references, exports,
    ;; code and the data segments of byte literals. Every module imports the
    ;; runtime's linear memory, where staged text goes; once linked, the two
    ;; share it.
    ;; Declarations are listed by name, so the text is the same whichever
    ;; order they were emitted in. Only the types constrain their order, and
    ;; `type-groups` settles it.
    (: module-wat (-> Module Wat ! mut))
    (define (module-wat m)
      (let ((declared (sort-strings (delete-duplicates string=? (ref-get (Module-declared m))))))
        (wat* "module"
              (concatenate
               (list (type-groups (reverse (ref-get (Module-types m))))
                     (Cons (wat "import"
                                (wat-string "snail.core.support")
                                (wat-string "memory")
                                (wat "memory" (int 0)))
                           (sorted-declarations (ref-get (Module-imports m))))
                     (sorted-declarations (ref-get (Module-globals m)))
                     (if (null? declared)
                         (Nil)
                         (list (wat* "elem"
                                     (Cons (Word "declare")
                                           (Cons (Word "func") (map id declared))))))
                     (sorted-declarations (ref-get (Module-exports m)))
                     (map (lambda (entry) (Word (Pair-second entry)))
                          (sort-named (ref-get (Module-functions m))))
                     (sorted-declarations (ref-get (Module-data m))))))))

    (: sorted-declarations (-> (List Wat) (List Wat)))
    (define (sorted-declarations declarations)
      (map (lambda (entry) (Pair-second entry))
           (sort-named (map (lambda (declaration) (Pair (declaration-id declaration) declaration))
                            declarations))))

    (: sort-named (All (A) (requires (Copy A)) (-> (List (Pair String A)) (List (Pair String A)))))
    (define (sort-named entries)
      (let ((count (length entries)))
        (if (< count 2)
            entries
            (merge-named (sort-named (take entries (quotient count 2)))
                         (sort-named (list-drop entries (quotient count 2)))))))

    (: merge-named
       (All (A)
            (requires (Copy A))
            (-> (List (Pair String A)) (List (Pair String A)) (List (Pair String A)))))
    (define (merge-named a b)
      (match (Pair a b)
        ((Pair (Nil) _) b)
        ((Pair _ (Nil)) a)
        ((Pair (Cons x xs) (Cons y ys))
         (if (string<? (Pair-first y) (Pair-first x))
             (Cons y (merge-named a ys))
             (Cons x (merge-named xs b))))))

    (: emit-main! (-> Module (List Item) Unit ! mut))
    (define (emit-main! m items)
      (let* ((fn (Fn-evidence-set (new-fn m) (evidence-none m)))
             (code (concatenate (map (lambda (item) (main-item-code m fn item)) items))))
        (push-function! m "$main"
                        (wat* "func" (Cons (Word "$main")
                                           (Cons (wat "export" (wat-string "main"))
                                                 (Cons (wat "result" (Word "i32"))
                                                       (append (reverse (ref-get (Fn-locals fn)))
                                                               (append code
                                                                       (list (wat "i32.const"
                                                                                  (int 0))))))))))))

    ;; A value becomes a mutable global set at startup; a statement runs and
    ;; its value is dropped; an exposed function is exported, behind the
    ;; wrapper the host or a loading program calls.
    (: main-item-code (-> Module Fn Item (List Wat) ! mut))
    (define (main-item-code m fn item)
      (match item
        ((Define name value)
         (if (lambda-expr? value)
             (Nil)
             (let ((r (rep m (Expr-type value))))
               (push! (Module-globals m)
                      (wat "global" (id (wasm-id name)) (wat "mut" (nullable r)) (default-value r)))
               (list (wat "global.set" (id (wasm-id name)) (emit1 fn value))))))
        ((Do expr) (list (wat "drop" (emit1 fn expr))))
        ((Expose name symbol dynamic loc)
         (match (definition-of m name)
           ((Some definition)
            (unless (lambda-expr? definition)
              (panic "internal error: an exposed function is not a lambda"))
            (if dynamic
                (export-dynamic! m name symbol (Expr-type definition))
                (push! (Module-exports m)
                       (wat "export"
                            (wat-string symbol)
                            (wat "func" (id (exposed-function m name (Expr-type definition))))))))
           ((None) (panic "internal error: an exposed function has no definition")))
         (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm)
    (import
     (snail stage0 testing))
    (begin
      (define (test-wasm)
        (expect (mangle "a b,c(d)") "a_b~c<d>")
        (expect (fill "(call {f} {x})" (list (Pair "f" "$g") (Pair "x" "1"))) "(call $g 1)")
        (expect (wat->string (wat "module"
                                  (wat "func"
                                       (Word "$f")
                                       (wat "result" (Word "i32"))
                                       (wat "i32.const" (int 1)))))
                "(module\n  (func $f (result i32)\n    (i32.const 1)))\n")
        (expect (wat->text (wat-string "é\n")) "\"\\c3\\a9\\0a\""))))
   (else)))
