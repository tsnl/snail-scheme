;; Prepared concrete code to WasmGC. Declarations and function bodies are
;; fixed before emission; no source specialization or validation happens here.
;; This backend decides representations:
;; scalars are Wasm numbers, enums whose cases have no fields are i32 tags,
;; other data are GC structs (enum cases are subtypes of a tagged base), a
;; field holding a record keeps a reference to that object,
;; sequences are GC arrays, and functions are closures holding a typed
;; function reference. Calls in tail position become `return_call`. A whole
;; program becomes one module. A suspension
;; leaves a record in one global, which each caller tests after a call that
;; may yield, saving the rest of its work as a frame, back to the
;; `with-prompt` it is aimed at; `resume` runs those frames again, once.
(define-library (snail shell compiler wasm)
  (export
   emit-module
   wat->string)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (only (snail shell compiler specialize)
         Declarations)
   (only (snail shell compiler prepare)
         Prepared
         Suspensions
         yields
         holds-yield-point?
         may-resume?))
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

    (define (wat* (head String) (items (List Wat))) (→ Wat)
      (Node (Cons (Word head) items)))

    (define (int (n I64)) (→ Wat)
      (Word (i64->string n)))

    ;; Top-level module fields and function instructions start new lines.

    (define (wat->string (module Wat)) (→ String)
      (match module
        ((Node (Cons _ fields))
         (string-concatenate
          (reverse (Cons ")\n"
                         (fold-left (lambda (pieces field) (write-field field (Cons "\n  " pieces)))
                                    (list "(module")
                                    fields)))))
        (_ (panic "internal error: not a module"))))

    (define (field->string (field Wat)) (→ String)
      (string-concatenate (reverse (write-field field (Nil)))))

    (define (write-field (field Wat) (pieces (List String))) (→ (List String))
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

    (define (own-line? (head String) (part Wat)) (→ Bool)
      (match part
        ((Node (Cons (Word inner) _))
         (or (string=? head "rec")
             (not (member? inner (list "type" "param" "result" "local" "export")))))
        (_ #f)))

    ;; Pieces accumulate in reverse.

    (define (write-wat (wat Wat) (pieces (List String))) (→ (List String))
      (match wat
        ((Word text) (Cons text pieces))
        ((Node (Nil)) (Cons "()" pieces))
        ((Node (Cons first rest))
         (Cons ")"
               (fold-left (lambda (pieces item) (write-wat item (Cons " " pieces)))
                          (write-wat first (Cons "(" pieces))
                          rest)))))

    ;; Wasm strings are UTF-8 bytes; anything beyond printable ASCII is escaped.

    (define (wat-string (text String)) (→ Wat)
      (Word (string-append "\"" (string-concatenate (map escape-char (string->list text))) "\"")))

    (define (escape-char (c Char)) (→ String)
      (let ((code (char->integer c)))
        (if (and (>= code 32) (< code 127) (not (= code 34)) (not (= code 92)))
            (list->string (list c))
            (string-concatenate (map (lambda (byte)
                                       (string-append "\\"
                                                      (hex-digit (quotient byte 16))
                                                      (hex-digit (remainder byte 16))))
                                     (utf-8-bytes code))))))

    (define (hex-digit (value I64)) (→ String)
      (substring "0123456789abcdef" value (+ value 1)))

    (define (utf-8-bytes (code I64)) (→ (List I64))
      (cond ((< code 128) (list code))
            ((< code 2048) (list (+ 192 (quotient code 64)) (+ 128 (remainder code 64))))
            ((< code 65536)
             (list (+ 224 (quotient code 4096))
                   (+ 128 (remainder (quotient code 64) 64))
                   (+ 128 (remainder code 64))))
            (else (list (+ 240 (quotient code 262144)) (+ 128 (remainder (quotient code 4096) 64))
                        (+ 128 (remainder (quotient code 64) 64)) (+ 128 (remainder code 64))))))

    ;; Fills each `{name}` in a template of fixed WAT text.

    (define (fill (template String) (bindings (List (Pair String String)))) (→ String)
      (let loop ((chars (string->list template)) (pieces (Nil)))
        (match chars
          ((Nil) (string-concatenate (reverse pieces)))
          ((Cons #\{ rest)
           (let ((name (list->string (take-until rest #\}))))
             (match (assoc-ref bindings name)
               ((Some value) (loop (list-drop rest (+ (string-length name) 1)) (Cons value pieces)))
               ((None) (loop rest (Cons "{" pieces))))))
          ((Cons c rest) (loop rest (Cons (list->string (list c)) pieces))))))

    (define (take-until (chars (List Char)) (stop Char)) (→ (List Char))
      (let loop ((chars chars) (taken (Nil)))
        (match chars
          ((Cons c rest) (if (char=? c stop) (reverse taken) (loop rest (Cons c taken))))
          ((Nil) (reverse taken)))))

    ;; ---- Module state ----

    ;; GC types are registered on first use. Functions are kept as text,
    ;; other fields as trees. `lambdas` holds each lambda's text by its
    ;; name; `helpers` caches imports and helper functions by key.
    ;; `declarations` is fixed metadata: it holds no source bodies, recipes
    ;; or pending work. Only the Wasm output builders change during emission.
    (record Module
      ((declarations Declarations)
       (suspensions Suspensions)
       (type-ids (Table String))
       (remaining-data-types I64)
       (types (List Wat))
       (imports (List Wat))
       (globals (List Wat))
       (functions (List (Pair String String)))
       (declared (List String))
       (exports (List Wat))
       (data (List Wat))
       (lambdas (Table Wat))
       (helpers (Table String))))

    ;; Output builders update a selected mutable field. Every use selects
    ;; a field on an already named module or function builder.
    (define-syntax push!
      (syntax-rules ()
        ((_ place value) (set! place (Cons value place)))))

    (define-syntax put!
      (syntax-rules ()
        ((_ place key value) (set! place (table-set place key value)))))

    ;; A function is written out as soon as it is emitted. The module's
    ;; functions are most of its text, and holding their trees until the end
    ;; made every collection copy them.

    (define (push-function! (m Module) (name String) (function Wat)) (→ Unit)
      (push! (● m functions) (new Pair (first name) (second (field->string function)))))

    ;; A global or data segment that a module declares once, at its first
    ;; use, is declared by a cached function of the module and what names
    ;; it: a later use skips the declaration and gets the same reference,
    ;; since a cache hit skips the function's writes. A cache's keys
    ;; compare strings and numbers by value and the module by identity, so
    ;; such a function takes those and nothing else.

    ;; An import declared once: the first request for `key` declares it
    ;; under `name`, and later ones find that name.

    (define (import-once! (m Module)
                          (key String)
                          (name String)
                          (declaration (Fn String → Wat)))
      (→ String)
      (match (table-ref (● m helpers) key)
        ((Some found) found)
        ((None)
         (put! (● m helpers) key name)
         (push! (● m imports) (declaration name))
         name)))

    (define (program-of (m Module)) (→ Program)
      (● (● m declarations) program))

    ;; A location for code the backend writes itself.

    (define no-loc (→ Loc) (new Loc (file "") (line 0) (column 0)))

    ;; ---- Names ----

    ;; Characters outside Wasm's identifier set are replaced.

    (define (mangle (text String)) (→ String)
      (array->string (array-map mangle-char (string->array text))))

    (define (mangle-char (c Char)) (→ Char)
      (cond ((char=? c #\space) #\_)
            ((char=? c #\,) #\~)
            ((char=? c #\() #\<)
            ((char=? c #\)) #\>)
            ((member? c (list #\" #\; #\[ #\] #\{ #\})) #\_)
            ((and (> (char->integer c) 32) (< (char->integer c) 127)) c)
            (else #\_)))

    (define (wasm-id (text String)) (→ String)
      (string-append "$" (mangle text)))

    ;; A name derived from what it names, so the text comes out the same
    ;; whichever order a host evaluated the emission in: the prefix, then
    ;; FNV-1a of the key. Declarations are kept once per full key, so two
    ;; keys with one hash would surface as a duplicate declaration the
    ;; assembler rejects, never as wrong code.

    (define (keyed-id (prefix String) (key String)) (→ String)
      (wasm-id (string-append prefix "." (i64->string (fnv-1a key)))))

    ;; A name that extends another's: a closure's global extends its code.

    (define (derived-id (prefix String) (id String)) (→ String)
      (wasm-id (string-append prefix "." (substring id 1 (string-length id)))))

    ;; FNV-1a over a tree's words in order, with a separator per word and
    ;; per node, so `(a b)` and `(a (b))` differ.

    (define (wat-hash (hash I64) (tree Wat)) (→ I64)
      (match tree
        ((Word text)
         (array-fold (lambda (h c) (fnv-step h (char->integer c)))
                     (fnv-step hash 32)
                     (string->array text)))
        ((Node items) (fold-left wat-hash (fnv-step hash 40) items))))

    (define (wat=? (a Wat) (b Wat)) (→ Bool)
      (match (new Pair (first a) (second b))
        ((Pair (Word x) (Word y)) (string=? x y))
        ((Pair (Node xs) (Node ys))
         (and (= (length xs) (length ys))
              (every? (lambda (pair) (wat=? (● pair first) (● pair second))) (zip xs ys))))
        (_ #f)))

    (define (wat-rename (from String) (to String) (tree Wat)) (→ Wat)
      (match tree
        ((Word text) (if (string=? text from) (Word to) tree))
        ((Node items) (Node (map (lambda (item) (wat-rename from to item)) items)))))

    ;; A declaration's name: an export's exported name, else its first `$id`.

    (define (declaration-id (declaration Wat)) (→ String)
      (match declaration
        ((Node (Cons (Word "export") (Cons (Word name) _))) name)
        (_ (match (first-id declaration)
             ((Some name) name)
             ((None) (panic "internal error: a declaration without a name"))))))

    (define (first-id (tree Wat)) (→ (Option String))
      (match tree
        ((Word text)
         (if (and (> (string-length text) 0) (char=? (string-ref text 0) #\$)) (Some text) (None)))
        ((Node items)
         (fold-left (lambda (found item) (match found ((Some _) found) ((None) (first-id item))))
                    (ann (None) (Option String))
                    items))))

    (define (id (name String)) (→ Wat)
      (Word name))

    ;; ---- Representations ----

    ;; A value's Wasm type: a number type, or a reference to a
    ;; declared type. Active source values are non-null; nullable machine
    ;; references also hold inactive slots during control unwinding. No
    ;; source use may precede the yield test.
    ;; `i8` appears only as the element of a byte array.
    (enum Rep
      (Scalar
       ((name String)))
      (Reference
       ((type String))))

    (define (ref-wat (type String)) (→ Wat)
      (wat "ref" (Word "null") (id type)))

    (define (rep->wat (rep Rep)) (→ Wat)
      (match rep
        ((Scalar name) (Word name))
        ((Reference type) (ref-wat type))))

    (define (nonnull (rep Rep)) (→ Wat)
      (match rep
        ((Scalar name) (Word name))
        ((Reference type) (wat "ref" (id type)))))

    (define (rep-key (rep Rep)) (→ String)
      (match rep
        ((Scalar name) name)
        ((Reference type) (substring type 1 (string-length type)))))

    (define (reference-type (rep Rep)) (→ String)
      (match rep
        ((Reference type) type)
        ((Scalar name) (panic (string-append "internal error: not a reference: " name)))))

    (define (default-value (rep Rep)) (→ Wat)
      (match rep
        ((Scalar "funcref") (wat "ref.null" (Word "func")))
        ((Scalar name) (wat (string-append name ".const") (Word "0")))
        ((Reference type) (wat "ref.null" (id type)))))

    ;; A function value is a reference to its closure.

    (define (rep (m Module) (type Type)) (→ Rep)
      (match type
        ((TCon name args)
         (case name
           (("U8" "I32" "Bool" "Char" "Unit") (Scalar "i32"))
           (("I64") (Scalar "i64"))
           (("F32") (Scalar "f32"))
           (("F64") (Scalar "f64"))
           (("String") (Reference (array-type m (Scalar "i32"))))
           (("Any") (Reference (any-type m)))
           (("Prompt") (Reference (prompt-type m)))
           (("Funcref") (Scalar "funcref"))
           (("Array" "ConstantArray")
            (Reference (array-type m (element-rep m (first-type args)))))
           (else (if (tag-enum? m name) (Scalar "i32") (Reference (data-type m type))))))
        ((TFun params result)
         (Reference
          (closure-type m (map (lambda (param) (rep m param)) params) (rep m result))))
        (_ (panic (string-append "internal error: not a ground type: " (type-key type))))))

    (define (first-type (types (List Type))) (→ Type)
      (match types
        ((Cons type _) type)
        ((Nil) (panic "internal error: missing type argument"))))

    ;; Byte arrays are packed; a byte is an i32 everywhere else.

    (define (element-rep (m Module) (type Type)) (→ Rep)
      (match type
        ((TCon "U8" (Nil)) (Scalar "i8"))
        (_ (rep m type))))

    (define (array-get (array String)) (→ String)
      (if (string=? array "$arr.i8") "array.get_u" "array.get"))

    (define (register-type! (m Module) (key String) (type String) (definition Wat))
      (→ String)
      (put! (● m type-ids) key type)
      (push! (● m types) definition)
      type)

    (define (known-type (m Module) (key String)) (→ (Option String))
      (table-ref (● m type-ids) key))

    (define (array-type (m Module) (element Rep)) (→ String)
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

    ;; A closure is a struct whose first field is its code. Each lambda with
    ;; captured variables extends the base struct with their fields.

    (define (closure-type (m Module) (params (List Rep)) (result Rep)) (→ String)
      (let* ((signature
              (string-append (string-join (map rep-key params) ",") "->" (rep-key result)))
             (key (string-append "clo." signature)))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (let ((closure (wasm-id key)) (code (wasm-id (string-append "fn." signature))))
             (put! (● m type-ids) key closure)
             (put! (● m type-ids) (string-append "code:" closure) code)
             (register-type! m (string-append "fn." signature) code
                             (wat "type" (id code)
                                  (wat* "func"
                                        (append
                                         (list (wat "param" (ref-wat closure)))
                                         (append (map (lambda (param)
                                                        (wat "param"
                                                             (rep->wat param)))
                                                      params)
                                                 (list (wat "result"
                                                            (rep->wat result))))))))
             (register-type! m key closure
                             (wat "type" (id closure)
                                  (wat "sub" (wat* "struct" (closure-fields m closure))))))))))

    ;; Every closure subtype shares its base's code type.

    (define (code-type (m Module) (closure String)) (→ String)
      (match (known-type m (string-append "code:" closure))
        ((Some code) code)
        ((None) (panic "internal error: closure without a code type"))))

    (define (function-signature (m Module) (type Type)) (→ (Pair (List Rep) Rep))
      (match type
        ((TFun params result)
         (new Pair
           (first (map (lambda (param) (rep m param)) params))
           (second (rep m result))))
        (_ (panic "internal error: not a function type"))))

    (define (data-type-of (m Module) (name String)) (→ DataType)
      (program-type (program-of m) name))

    (define (tag-enum? (m Module) (name String)) (→ Bool)
      (let ((data (data-type-of m name)))
        (and (● data enum?)
             (every? (lambda (case) (null? (● case fields))) (● data cases)))))

    (define (case-field-types (m Module) (type Type) (case Case)) (→ (List Type))
      (match type
        ((TCon name args)
         (let ((substitution (zip (● (data-type-of m name) params) args)))
           (map (lambda (field) (substitute substitution (● field type))) (● case fields))))
        (_ (panic "internal error: not a data type"))))

    ;; Every source field occupies one mutable Wasm field.
    (define (case-fields (m Module) (type Type) (case Case)) (→ (List Wat))
      (map (lambda (type) (wat "field" (wat "mut" (rep->wat (rep m type)))))
           (case-field-types m type case)))

    (define (type-name (type Type)) (→ String)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: not a named type"))))

    ;; A record is one GC struct. An enum is a base struct holding the tag,
    ;; with a final subtype for each case that has fields; a field-less case
    ;; is the base struct itself. The base is registered first because a
    ;; supertype must precede its subtypes.

    (define (data-type (m Module) (type Type)) (→ String)
      (require-type-capacity type)
      (let ((key (type-key type)))
        (match (known-type m key)
          ((Some found) found)
          ((None)
           (when (= (● m remaining-data-types) 0)
             (panic "compilation exceeds the limit of 65536 concrete aggregate types"))
           (set! (● m remaining-data-types) (- (● m remaining-data-types) 1))
           (let ((type-id (wasm-id key)) (data (data-type-of m (type-name type))))
             (put! (● m type-ids) key type-id)
             (if (● data enum?)
                 (begin
                   (push! (● m types)
                          (wat "type" (id type-id)
                               (wat "sub" (wat "struct" (wat "field" (Word "i32"))))))
                   (for-each (lambda (case) (case-type m type case) (unit))
                             (filter (lambda (case) (not (null? (● case fields)))) (● data cases))))
                 (push! (● m types)
                        (wat "type" (id type-id)
                             (wat* "struct" (case-fields m type (record-case m type))))))
             type-id)))))

    (define (case-type (m Module) (type Type) (case Case)) (→ String)
      (let* ((base (data-type m type))
             (key (string-append (type-key type) "." (short-name (● case name)))))
        (match (known-type m key)
          ((Some found) found)
          ((None)
           (let ((case-id (wasm-id key)))
             (register-type! m key case-id
                             (wat "type" (id case-id) (wat "sub" (Word "final") (id base)
                                                           (wat* "struct"
                                                                 (Cons (wat "field" (Word "i32"))
                                                                       (case-fields m
                                                                                    type
                                                                                    case)))))))))))

    ;; A record has one case, whose declared fields are its complete layout.
    (define (record-case (m Module) (type Type)) (→ Case)
      (match (● (data-type-of m (type-name type)) cases)
        ((Cons case _) case)
        ((Nil) (panic "internal error: a record has one case"))))

    ;; ---- Functions ----

    ;; `access` maps each visible local name to the instruction that reads it,
    ;; and `reps` to its representation. A closure's `self` records exact
    ;; aliases of the incoming closure and its code.
    ;; Fresh function and control-frame contexts inherit none of those facts.
    ;; `exit` is where a yield leaves the code being emitted (see Control).
    (record FnState
      ((locals (List Wat))
       (access (Table Wat))
       (reps (Table Rep))
       (names I64)))

    (record Fn
      ((module Module)
       (state FnState)
       (self (Option Self))
       (exit (Option Exit))))

    (record Self
      ((names (List String))
       (code String)))

    ;; Context replacements share this function's output builder while
    ;; changing only immutable control metadata.
    (define (new-fn (m Module)) (→ Fn)
      (new Fn
        (module m)
        (state (new FnState (locals (Nil)) (access (empty-table)) (reps (empty-table)) (names 0)))
        (self (None))
        (exit (None))))

    ;; Temporaries and labels are numbered within their function, so a name
    ;; depends on nothing outside the body it appears in.

    (define (local-id (fn Fn) (prefix String)) (→ String)
      (let ((count (+ (● (● fn state) names) 1)))
        (set! (● (● fn state) names) count)
        (wasm-id (string-append prefix "." (i64->string count)))))

    (define (bind-local! (fn Fn) (name String) (read Wat) (rep Rep)) (→ Unit)
      (put! (● (● fn state) access) name read)
      (put! (● (● fn state) reps) name rep))

    (define (declare-local! (fn Fn) (name String) (rep Rep)) (→ String)
      (let ((local (wasm-id name)))
        (push! (● (● fn state) locals) (wat "local" (id local) (rep->wat rep)))
        (bind-local! fn name (wat "local.get" (id local)) rep)
        local))

    ;; A temporary takes any value type, including a nullable reference.

    (define (declare-temp! (fn Fn) (type Wat)) (→ String)
      (let ((local (local-id fn "tmp")))
        (push! (● (● fn state) locals) (wat "local" (id local) type))
        local))

    (define (local-access (fn Fn) (name String)) (→ (Option Wat))
      (table-ref (● (● fn state) access) name))

    (define (local? (fn Fn) (name String)) (→ Bool)
      (table-contains? (● (● fn state) access) name))

    (define (fn-rep (fn Fn) (type Type)) (→ Rep)
      (rep (● fn module) type))

    ;; A function definition: its name, parameters and result, the locals it
    ;; declared, then the body.

    (define (function-wat (fn Fn) (name String) (params (List Wat)) (result Rep) (body (List Wat)))
      (→ Wat)
      (wat* "func"
            (Cons (id name)
                  (append params
                          (Cons (wat "result" (rep->wat result))
                                (append (reverse (● (● fn state) locals)) body))))))

    (define (bind-params! (fn Fn) (params (List String)) (reps (List Rep))) (→ Unit)
      (for-each (lambda (pair)
                  (bind-local! fn
                               (● pair first)
                               (wat "local.get" (id (wasm-id (● pair first))))
                               (● pair second)))
                (zip params reps)))

    (define (param-wats (params (List String)) (reps (List Rep))) (→ (List Wat))
      (map
       (lambda (pair) (wat "param" (id (wasm-id (● pair first))) (rep->wat (● pair second))))
       (zip params reps)))

    (define (emit-function! (m Module) (name String) (function Expr)) (→ Unit)
      (match (● function term)
        ((Lambda params body)
         (let* ((fn (Fn-exit-set (new-fn m) (function-exit (● function type))))
                (signature (function-signature m (● function type)))
                (reps (● signature first)))
           (bind-params! fn params reps)
           (let ((code (emit fn body #t)))
             (push-function! m (wasm-id name)
                             (function-wat fn
                                           (wasm-id name)
                                           (param-wats params reps)
                                           (● signature second)
                                           code)))))
        ((App (Expr (Var "prim:cached-thunk" _ _) _ _) (Cons thunk (Nil)))
         (emit-cached-thunk! m name thunk))
        (_ (panic "internal error: not a function"))))

    ;; A top-level value is the result of its thunk, which its module keeps
    ;; in a slot that starts as zero or null, like any inactive result. State
    ;; 1 is set before the initializer runs, so one that reads its own value
    ;; panics instead of recursing without end; state 2 says the slot holds
    ;; the value. A literal needs no slot: evaluating it again gives the
    ;; same value, so its thunk is an ordinary function. An initializer that
    ;; suspends has kept nothing: the yield leaves the slot empty, and the
    ;; next read runs the initializer again.

    (define (emit-cached-thunk! (m Module) (name String) (thunk Expr)) (→ Unit)
      (match (● thunk term)
        ((Ann inner _) (emit-cached-thunk! m name inner))
        ((Lambda (Nil) (Expr (Lit _) _ _)) (emit-function! m name thunk))
        ((Lambda (Nil) body)
         (let* ((fn (Fn-exit-set (new-fn m) (Some (ToBlock "$initializer" (● body type)))))
                (result (rep m (● body type)))
                (state (wasm-id (string-append name "%state")))
                (slot (wasm-id (string-append name "%value")))
                (code (emit fn body #f))
                (unset (if (may-yield? fn body)
                           (wat "if" (yielding? m)
                                (wat "then"
                                     (wat "global.set" (id state) (wat "i32.const" (int 0)))
                                     (wat "return" (default-value result))))
                           (wat "nop"))))
           (push! (● m globals)
                  (wat "global" (id state) (wat "mut" (Word "i32")) (wat "i32.const" (int 0))))
           (push! (● m globals)
                  (wat "global" (id slot) (wat "mut" (rep->wat result)) (default-value result)))
           (push-function! m (wasm-id name)
                           (function-wat fn
                                         (wasm-id name)
                                         (Nil)
                                         result
                                         (cached-thunk-body
                                          m
                                          name
                                          state
                                          slot
                                          result
                                          code
                                          unset)))))
        (_ (panic "internal error: a cached thunk is a lambda of no parameters"))))

    (define (cached-thunk-body (m Module)
                               (name String)
                               (state String)
                               (slot String)
                               (result Rep)
                               (code (List Wat))
                               (unset Wat))
      (→ (List Wat))
      (list (wat "if" (wat "i32.eq" (wat "global.get" (id state)) (wat "i32.const" (int 1)))
                 (wat "then"
                      (wat "call" (id (panic-helper m))
                           (string-literal m
                                           (string-append "initialization cycle: "
                                                          (short-name name))))))
            (wat "if" (wat "i32.eqz" (wat "global.get" (id state)))
                 (wat "then"
                      (wat "global.set" (id state) (wat "i32.const" (int 1)))
                      (wat "global.set" (id slot)
                           (wat* "block"
                                 (Cons (Word "$initializer")
                                       (Cons (wat "result" (rep->wat result)) code))))
                      unset
                      (wat "global.set" (id state) (wat "i32.const" (int 2)))))
            (wat "global.get" (id slot))))

    ;; ---- Expressions ----

    ;; A list of instructions that leave one value on the stack.

    (define (emit (fn Fn) (expr Expr) (tail? Bool)) (→ (List Wat))
      (let ((type (● expr type)))
        (match (● expr term)
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
          ((BoxAny inner) (list (to-any (● fn module) (● inner type) (emit1 fn inner))))
          ((Downcast inner target) (list (emit-downcast fn inner target (● expr type))))
          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((FieldWrite _ _ _ _) (panic "internal error: field selection survived checking"))
          ((New _ _) (panic "internal error: named construction survived checking"))
          ((Ann inner _) (emit fn inner tail?)))))

    ;; One instruction, wrapping a sequence in a block when needed.

    (define (emit1 (fn Fn) (expr Expr)) (→ Wat)
      (emit1-tail fn expr #f))

    (define (emit1-tail (fn Fn) (expr Expr) (tail? Bool)) (→ Wat)
      (match (emit fn expr tail?)
        ((Cons single (Nil)) single)
        (code (wat* "block" (Cons (wat "result" (rep->wat (fn-rep fn (● expr type)))) code)))))

    (define (emit-args (fn Fn) (args (List Expr))) (→ (List Wat))
      (map (lambda (arg) (emit1 fn arg)) args))

    (define (literal (fn Fn) (value Datum) (type Type)) (→ Wat)
      (match value
        ((DBool true?) (wat "i32.const" (int (if true? 1 0))))
        ((DChar c) (wat "i32.const" (int (char->integer c))))
        ((DString text) (string-literal (● fn module) text))
        ((DBytes bytes) (bytes-literal (● fn module) bytes))
        ((DUnit) (wat "i32.const" (int 0)))
        ((DConstants element values) (constant-array-literal (● fn module) element values))
        ((DInt n) (wat (string-append (rep-key (fn-rep fn type)) ".const") (int n)))
        ((DFloat text)
         (wat (string-append (rep-key (fn-rep fn type)) ".const") (Word (float-text text))))))

    ;; WAT needs a digit before a decimal point, as in `0.5` or `-0.5`.

    (define (float-text (text String)) (→ String)
      (cond
       ((and (> (string-length text) 0) (char=? (string-ref text 0) #\.)) (string-append "0" text))
       ((and (> (string-length text) 1) (char=? (string-ref text 1) #\.)
             (or (char=? (string-ref text 0) #\-) (char=? (string-ref text 0) #\+)))
        (string-append (substring text 0 1) "0" (substring text 1 (string-length text))))
       (else text)))

    ;; String literals are immutable globals, built once.

    (define string-literal
      (cache
       (lambda ((m Module) (text String)) (→ Wat)
         (let ((global (keyed-id "string" text)) (array (array-type m (Scalar "i32"))))
           (push! (● m globals)
                  (wat "global" (id global) (ref-wat array)
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
    ;; a fresh mutable array on every evaluation.

    (define (bytes-literal (m Module) (bytes Bytes)) (→ Wat)
      (bytes-segment m (bytes-wat-string bytes) (array-length bytes)))

    (define bytes-segment
      (cache
       (lambda ((m Module) (text String) (length I64)) (→ Wat)
         (let ((segment (keyed-id "bytes" text)))
           (push! (● m data) (wat "data" (id segment) (Word text)))
           (wat "array.new_data"
                (id (array-type m (Scalar "i8")))
                (id segment)
                (wat "i32.const" (int 0))
                (wat "i32.const" (int length)))))))

    ;; ---- Constant arrays ----

    ;; A constant array is built once in a module, and every use shares it,
    ;; since its type has no setter: it has an array's representation, and
    ;; reads and copies are an array's. Its table is a passive data segment
    ;; of its elements, little-endian at their width, read into an array the
    ;; first time a use reaches it, so a table of any size costs its bytes.

    (define (constant-array-literal (m Module) (element String) (values (List Datum)))
      (→ Wat)
      (integer-table m element (bytes-wat-string (table-bytes element values)) (length values)))

    ;; The table of `count` elements whose bytes are `data`.

    (define integer-table
      (cache
       (lambda ((m Module) (element String) (data String) (count I64)) (→ Wat)
         (let* ((array (array-type m (element-rep m (TCon element (Nil)))))
                (key (string-append element ":" data))
                (segment (keyed-id "constants" key))
                (global (keyed-id "table" key)))
           (push! (● m data) (wat "data" (id segment) (Word data)))
           (push! (● m globals)
                  (wat "global"
                       (id global)
                       (wat "mut" (ref-wat array))
                       (wat "ref.null" (id array))))
           (wat "block"
                (wat "result" (ref-wat array))
                (wat "if" (wat "ref.is_null" (wat "global.get" (id global)))
                     (wat "then"
                          (wat "global.set" (id global)
                               (wat "array.new_data" (id array) (id segment)
                                    (wat "i32.const" (int 0))
                                    (wat "i32.const" (int count))))))
                (wat "global.get" (id global)))))))

    ;; Each element's bytes, least significant first, at its width in the
    ;; array: one for U8, eight for I64, four otherwise. A negative value is
    ;; its two's complement, taken a 32-bit word at a time, so no step
    ;; leaves the range both hosts compute alike.

    (define (table-bytes (element String) (values (List Datum))) (→ Bytes)
      (let ((width (cond ((string=? element "U8") 1) ((string=? element "I64") 8) (else 4)))
            (integers (list->array (map table-integer values))))
        (array-generate (* width (array-length integers))
                        (lambda (index)
                          (let ((n (array-ref integers (quotient index width)))
                                (byte (remainder index width)))
                            (i32->u8
                             (i64->i32 (word-byte (if (< byte 4) (low-word n) (high-word n))
                                                  (remainder byte 4)))))))))

    (define (table-integer (value Datum)) (→ I64)
      (match value
        ((DInt n) n)
        ((DBool b) (if b 1 0))
        ((DChar c) (char->integer c))
        (_ (panic "internal error: an integer table holds integers"))))

    (define (low-word (n I64)) (→ I64)
      (modulo n 4294967296))

    (define (high-word (n I64)) (→ I64)
      (modulo (quotient (- n (low-word n)) 4294967296) 4294967296))

    (define (word-byte (word I64) (index I64)) (→ I64)
      (let loop ((word word) (index index))
        (if (= index 0) (remainder word 256) (loop (quotient word 256) (- index 1)))))

    ;; Every byte is a two-digit escape, so the text is three characters per
    ;; byte, generated in one pass: images make literals of millions of
    ;; bytes, too many to build from a piece of text per byte.

    (define (bytes-wat-string (bytes Bytes)) (→ String)
      (string-append "\""
                     (string-generate (* 3 (array-length bytes))
                                      (lambda (index)
                                        (let ((byte (i32->i64 (u8->i32 (array-ref bytes
                                                                                  (quotient index
                                                                                            3))))))
                                          (match (remainder index 3)
                                            (0 #\\)
                                            (1 (hex-char (quotient byte 16)))
                                            (_ (hex-char (remainder byte 16)))))))
                     "\""))

    (define (hex-char (value I64)) (→ Char)
      (string-ref "0123456789abcdef" value))

    ;; A let whose value may yield tests for the yield before its body.

    (define (emit-let (fn Fn) (name String) (value Expr) (body Expr) (tail? Bool))
      (→ (List Wat))
      (let* ((code (if (and (lambda-expr? value) (member? name (expr-references value)))
                       (closure fn value (Some name))
                       (emit-let-value fn value)))
             (local (declare-local! fn name (fn-rep fn (● value type)))))
        (Cons (wat "local.set" (id local) code)
              (let-rest (bind-self fn name value) name value body tail?))))

    ;; ---- Variables ----

    ;; A global function used as a value becomes a closure.

    (define (variable (fn Fn) (name String) (type Type)) (→ Wat)
      (let ((m (● fn module)))
        (match (local-access fn name)
          ((Some access) access)
          ((None)
           (match (declared-type m name)
             ((Some _) (function-value m name type))
             ((None)
              (match (program-value (program-of m) name)
                ((Some (Constructor case _))
                 (if (null? (● case fields))
                     (construct fn case type (Nil))
                     (function-value m name type)))
                ((Some _) (function-value m name type))
                ((None) (panic (string-append "internal error: unknown variable " name))))))))))

    ;; A specialized definition's type, or none for a name that is not one.
    ;; Types suffice to emit references before or after a body is emitted:
    ;; no definition body lives in the module builder.

    (define (declared-type (m Module) (name String)) (→ (Option Type))
      (table-ref (● (● m declarations) types) name))

    ;; An immutable global closure whose code calls `name` with its
    ;; arguments. Each use writes that code again; identical lambdas share
    ;; one function, and a closure without captures one global.

    (define (function-value (m Module) (name String) (type Type)) (→ Wat)
      (match type
        ((TFun params result)
         (let* ((names
                 (map (lambda (index) (string-append "argument." (i64->string index)))
                      (iota (length params))))
                (call (new Expr
                        (term (App (new Expr
                                     (term (Var name (Nil) (Nil)))
                                     (type type)
                                     (loc no-loc))
                                   (map (lambda (pair)
                                          (new Expr
                                            (term (Var (● pair first) (Nil) (Nil)))
                                            (type (● pair second))
                                            (loc no-loc)))
                                        (zip names params))))
                        (type result) (loc no-loc))))
           (closure-value m
                          (new Expr
                            (term (Lambda names call))
                            (type type)
                            (loc no-loc))
                          (None))))
        (_ (panic "internal error: a function value needs a function type"))))

    ;; ---- Closures ----

    ;; A lambda becomes a function taking its closure first. Captured
    ;; variables are copied into the closure and loaded on entry; `self` names
    ;; a recursive local function, which reads as the closure itself. Closures
    ;; without captured locals are immutable globals.

    (define (closure (fn Fn) (function Expr) (self (Option String))) (→ Wat)
      (let ((captured (filter (lambda (name) (and (not (self-name? self name)) (local? fn name)))
                              (expr-references function))))
        (if (null? captured)
            (closure-value (● fn module) function self)
            (closure-with-captures fn function self captured))))

    (define (self-name? (self (Option String)) (name String)) (→ Bool)
      (match self
        ((Some own) (string=? own name))
        ((None) #f)))

    ;; A closure without captures is one immutable global.

    (define (closure-value (m Module) (function Expr) (self (Option String))) (→ Wat)
      (let* ((signature (function-signature m (● function type)))
             (base (closure-type m (● signature first) (● signature second))))
        (closure-global m (lambda-function! m function self (Nil) base) base)))

    (define closure-global
      (cache
       (lambda ((m Module) (code String) (base String)) (→ Wat)
         (let ((global (derived-id "closure" code)))
           (push! (● m globals)
                  (wat "global"
                       (id global)
                       (ref-wat base)
                       (wat "struct.new" (id base) (wat "ref.func" (id code)))))
           (wat "global.get" (id global))))))

    ;; A closure with captures copies each captured local into its fields.
    (define (closure-with-captures (fn Fn)
                                   (function Expr)
                                   (self (Option String))
                                   (captured (List String)))
      (→ Wat)
      (let* ((m (● fn module)) (signature (function-signature m (● function type)))
             (base (closure-type m (● signature first) (● signature second)))
             (reps (map (lambda (name) (capture-rep fn name)) captured))
             (subtype (capture-type m base reps))
             (code (lambda-function! m function self (zip captured reps) subtype)))
        (wat* "struct.new"
              (Cons (id subtype)
                    (Cons (wat "ref.func" (id code))
                          (map (lambda (name) (variable fn name unchecked)) captured))))))

    ;; The captures extend the base struct with their fields. Closures with
    ;; one base and one list of representations share the subtype.

    (define (capture-type (m Module) (base String) (reps (List Rep))) (→ String)
      (let ((name (wasm-id (string-append (substring base 1 (string-length base)) "+"
                                          (string-join (map rep-key reps) ",")))))
        (match (known-type m name)
          ((Some type) type)
          ((None)
           (register-type! m name name
                           (wat "type" (id name) (wat "sub" (Word "final") (id base)
                                                      (wat* "struct" (append (closure-fields m base)
                                                                             (map (lambda (r)
                                                                                    (wat "field"
                                                                                         (rep->wat
                                                                                          r)))
                                                                                  reps))))))))))

    ;; A closure's first field is its code, and its captures follow.
    (define (closure-fields (m Module) (base String)) (→ (List Wat))
      (list (wat "field" (ref-wat (code-type m base)))))

    (define (capture-rep (fn Fn) (name String)) (→ Rep)
      (match (table-ref (● (● fn state) reps) name)
        ((Some rep) rep)
        ((None) (panic (string-append "internal error: no representation for " name)))))

    (define (lambda-function! (m Module)
                              (function Expr)
                              (self (Option String))
                              (captured (List (Pair String Rep)))
                              (closure String))
      (→ String)
      (match (● function term)
        ((Lambda params body)
         (let* ((signature (function-signature m (● function type)))
                (reps (● signature first))
                (base (closure-type m reps (● signature second)))
                (fn (Fn-exit-set (lambda-fn m self "$lambda.self" base)
                                 (function-exit (● function type)))))
           (bind-params! fn params reps)
           (let* ((loads (capture-loads fn captured closure)) (code (emit fn body #t))
                  ;; The function's type must be the closure's code type itself,
                  ;; not a structurally equal one, for `ref.func` to fit the field.
                  (draft (function-wat fn "$lambda.self"
                                       (Cons (wat "type" (id (code-type m base)))
                                             (Cons
                                              (wat "param"
                                                   (Word "$closure")
                                                   (ref-wat base))
                                              (param-wats params reps)))
                                       (● signature second)
                                       (append loads code))))
             (lambda-id m "lambda" draft 0))))
        (_ (panic "internal error: not a lambda"))))

    ;; A lambda, or a join function, is named by the hash of its own text,
    ;; written with its name as a placeholder, so identical lambdas share one
    ;; function and a name depends on nothing but the body. Two different
    ;; lambdas with one hash take the next salt, the one place a name can
    ;; still depend on the order of emission.

    (define (lambda-id (m Module) (prefix String) (draft Wat) (salt I64)) (→ String)
      (let* ((hash (i64->string (wat-hash fnv-offset draft)))
             (name (wasm-id (string-append prefix
                                           "."
                                           hash
                                           (if (= salt 0)
                                               ""
                                               (string-append "." (i64->string salt)))))))
        (match (table-ref (● m lambdas) name)
          ((Some stored) (if (wat=? stored draft) name (lambda-id m prefix draft (+ salt 1))))
          ((None)
           (put! (● m lambdas) name draft)
           (push! (● m declared) name)
           (push-function! m name (wat-rename "$lambda.self" name draft))
           name))))

    ;; A recursive lambda reads its own name as its closure.

    (define (lambda-fn
             (m Module)
             (self (Option String))
             (function-id String)
             (base String))
      (→ Fn)
      (let* ((names (match self ((Some name) (list name)) ((None) (Nil))))
             (fn (Fn-self-set (new-fn m) (Some (new Self (names names) (code function-id))))))
        (match self
          ((Some name)
           (bind-local! fn name (wat "local.get" (Word "$closure")) (Reference base)))
          ((None) (unit)))
        fn))

    ;; On entry, each captured variable is copied from the closure to a local.

    (define (capture-loads (fn Fn) (captured (List (Pair String Rep))) (closure String))
      (→ (List Wat))
      (map-indexed (lambda (index entry)
                     (wat "local.set"
                          (id (declare-local! fn (● entry first) (● entry second)))
                          (wat "struct.get"
                               (id closure)
                               (int (+ index 1))
                               (wat "ref.cast"
                                    (ref-wat closure)
                                    (wat "local.get" (Word "$closure"))))))
                   captured))

    ;; ---- Code references ----

    (define (code-of (m Module) (function-id String)) (→ Wat)
      (push! (● m declared) function-id)
      (wat "ref.func" (id function-id)))

    ;; ---- Calls ----

    (define (call-op (tail? Bool)) (→ String)
      (if tail? "return_call" "call"))

    ;; Resolved locals are immutable. A direct alias keeps the same recursive
    ;; entry point; other expressions establish no such proof. Emit the
    ;; actual callee operand below, preserving its operand evaluation.
    (define (self-target (fn Fn) (callee Expr)) (→ (Option String))
      (match (● callee term)
        ((Var name _ _)
         (match (● fn self)
           ((Some self) (if (member? name (● self names)) (Some (● self code)) (None)))
           ((None) (None))))
        (_ (None))))

    ;; The alias belongs only to this let's body. Fresh function and control
    ;; frame contexts start with no inherited proof about their caller.
    (define (bind-self (fn Fn) (name String) (value Expr)) (→ Fn)
      (match (new Pair (first (● fn self)) (second (self-target fn value)))
        ((Pair (Some self) (Some _))
         (Fn-self-set fn (Some (Self-names-set self (Cons name (● self names))))))
        (_ fn)))

    (define (emit-call (fn Fn) (expr Expr) (callee Expr) (args (List Expr)) (tail? Bool))
      (→ (List Wat))
      (match (self-target fn callee)
        ((Some function-id)
         (list (wat* (call-op tail?)
                     (Cons (id function-id) (Cons (emit1 fn callee) (emit-args fn args))))))
        ((None)
         (match (● callee term)
           ((Var name _ _) (named-call fn expr callee name args tail?))
           (_ (closure-call fn callee args tail?))))))

    (define (named-call (fn Fn)
                        (expr Expr)
                        (callee Expr)
                        (name String)
                        (args (List Expr))
                        (tail? Bool))
      (→ (List Wat))
      (if (local? fn name)
          (closure-call fn callee args tail?)
          (match (declared-type (● fn module) name)
            ((Some _)
             (list (wat* (call-op tail?) (Cons (id (wasm-id name)) (emit-args fn args)))))
            ((None) (builtin-call fn expr name args)))))

    (define (builtin-call (fn Fn) (expr Expr) (name String) (args (List Expr)))
      (→ (List Wat))
      (let ((m (● fn module)))
        (match (program-value (program-of m) name)
          ((Some (Constructor case _))
           (list (construct fn case (● expr type) args)))
          ((Some (Accessor _ index _)) (list (field-access fn index (first-arg args))))
          ((Some (Writer _ index _))
           (list (field-write fn index (first-arg args) (list-ref args 1))
                 (wat "i32.const" (int 0))))
          ((Some (Replacer case index _))
           (list (replace-field fn case index (first-arg args) (list-ref args 1))))
          ((Some (Primitive _)) (emit-primitive fn expr name args))
          ((Some (Foreign import scheme))
           (host-call m import (● scheme type) (emit-args fn args)))
          (_ (panic (string-append "internal error: cannot call " name))))))

    (define (first-arg (args (List Expr))) (→ Expr)
      (match args
        ((Cons arg _) arg)
        ((Nil) (panic "internal error: missing argument"))))

    ;; The callee is evaluated once, into a temporary unless it is already a
    ;; variable read.

    (define (closure-call (fn Fn) (callee Expr) (args (List Expr)) (tail? Bool))
      (→ (List Wat))
      (let* ((m (● fn module))
             (signature (function-signature m (● callee type)))
             (base (closure-type m (● signature first) (● signature second)))
             (value (emit1 fn callee)))
        (if (variable-read? value)
            (list (closure-call-wat m base value (emit-args fn args) tail?))
            (let ((temp (declare-temp! fn (rep->wat (Reference base)))))
              (list (wat "local.set" (id temp) value)
                    (closure-call-wat m
                                      base
                                      (wat "local.get" (id temp))
                                      (emit-args fn args)
                                      tail?))))))

    (define (closure-call-wat (m Module) (base String) (read Wat) (args (List Wat)) (tail? Bool))
      (→ Wat)
      (wat* (if tail? "return_call_ref" "call_ref")
            (Cons (id (code-type m base))
                  (Cons read (append args (list (wat "struct.get" (id base) (int 0) read)))))))

    (define (variable-read? (code Wat)) (→ Bool)
      (match code
        ((Node (Cons (Word head) _)) (or (string=? head "local.get") (string=? head "global.get")))
        (_ #f)))

    ;; The program value a callee names, when it is neither a local nor a
    ;; definition.

    (define (builtin-of (fn Fn) (callee Expr)) (→ (Option Value))
      (match (● callee term)
        ((Var name _ _)
         (if (local? fn name)
             (None)
             (match (declared-type (● fn module) name)
               ((Some _) (None))
               ((None) (program-value (program-of (● fn module)) name)))))
        (_ (None))))

    ;; Arguments become fields in source order. Nested records stay references.
    (define (construct (fn Fn) (case Case) (type Type) (args (List Expr))) (→ Wat)
      (construct-slots fn case type (map (lambda (arg) (emit1 fn arg)) args)))

    ;; Tag enums are i32 constants; field-less cases of other enums are shared
    ;; immutable globals of the base type, so constructing them allocates
    ;; nothing. `slots` contains one value per declared field.

    (define (construct-slots (fn Fn) (case Case) (type Type) (slots (List Wat))) (→ Wat)
      (let* ((m (● fn module)) (name (● case type)))
        (cond ((tag-enum? m name) (wat "i32.const" (int (● case tag))))
              ((not (● (data-type-of m name) enum?))
               (wat* "struct.new" (Cons (id (data-type m type)) slots)))
              ((null? slots) (singleton m type case))
              (else (wat* "struct.new" (Cons (id (case-type m type case))
                                             (Cons (wat "i32.const" (int (● case tag))) slots)))))))

    (define (singleton (m Module) (type Type) (case Case)) (→ Wat)
      (singleton-global m
                        (string-append (type-key type) ":" (● case name))
                        (data-type m type)
                        (● case tag)))

    (define singleton-global
      (cache
       (lambda ((m Module) (key String) (base String) (tag I64)) (→ Wat)
         (let ((global (keyed-id "value" key)))
           (push! (● m globals)
                  (wat "global" (id global) (ref-wat base)
                       (wat "struct.new" (id base) (wat "i32.const" (int tag)))))
           (wat "global.get" (id global))))))

    ;; ---- Arrays ----

    ;; An array is an array of its exact, permanent length, every slot
    ;; initialized, including reference elements. Strings remain separate
    ;; values; conversions copy their character data.
    (define (sequence-element (type Type)) (→ Type)
      (match type
        ((TCon "String" _) (TCon "Char" (Nil)))
        ((TCon _ (Cons element (Nil))) element)
        (_ (panic "internal error: not a sequence"))))

    (define (sequence-type (m Module) (type Type)) (→ String)
      (array-type m (element-rep m (sequence-element type))))

    (define (array-read (m Module) (element Type) (data Wat) (index Wat)) (→ Wat)
      (let ((array (array-type m (element-rep m element))))
        (wat (array-get array) (id array) data index)))

    ;; Validate full-width indices
    ;; before narrowing to Wasm's i32 indices, including zero-length copies.
    (define (range-helper (m Module)) (→ String)
      (template-helper! m "range" ""
                        "(func {id} (param $length i32) (param $start i64) (param $count i64) (result i32)
  (if (i64.gt_u (local.get $start) (i64.extend_i32_u (local.get $length))) (then unreachable))
  (if (i64.gt_u (local.get $count) (i64.sub (i64.extend_i32_u (local.get $length)) (local.get $start))) (then unreachable))
  (i32.wrap_i64 (local.get $start)))" (Nil)))

    (define (size-helper (m Module)) (→ String)
      (template-helper! m "size" ""
                        "(func {id} (param $length i64) (result i32)
  (if (i64.gt_u (local.get $length) (i64.const 2147483647)) (then unreachable))
  (i32.wrap_i64 (local.get $length)))" (Nil)))

    (define (array-storage-bindings (m Module) (element Type))
      (→ (List (Pair String String)))
      (list (new Pair (first "array") (second (array-type m (element-rep m element))))
            (new Pair (first "element") (second (wat->text (rep->wat (rep m element)))))
            (new Pair (first "range") (second (range-helper m)))
            (new Pair
              (first "read")
              (second (wat->text (array-read m element (wat "local.get" (Word "$array"))
                                             (wat "local.get" (Word "$index"))))))))

    (define (array-read-helper (m Module) (element Type)) (→ String)
      (template-helper! m "array-read" (type-key element)
                        "(func {id} (param $array (ref null {array})) (param $at i64) (result {element})
  (local $index i32)
  (local.set $index (call {range} (array.len (local.get $array)) (local.get $at) (i64.const 1)))
  {read})"
                        (array-storage-bindings m element)))

    (define (array-write-helper (m Module) (element Type)) (→ String)
      (template-helper! m "array-write" (type-key element)
                        "(func {id} (param $array (ref null {array})) (param $at i64) (param $value {element}) (result i32)
  (local $index i32)
  (local.set $index (call {range} (array.len (local.get $array)) (local.get $at) (i64.const 1)))
  (array.set {array} (local.get $array) (local.get $index) (local.get $value))
  (i32.const 0))"
                        (array-storage-bindings m element)))

    (define (sequence-slice-helper (m Module) (type Type)) (→ String)
      (template-helper! m "sequence-slice" (type-key type)
                        "(func {id} (param $value (ref null {array})) (param $start i64) (param $end i64) (result (ref null {array}))
  (drop (call {range} (array.len (local.get $value)) (local.get $start) (i64.sub (local.get $end) (local.get $start))))
  (return_call {slice} (local.get $value) (local.get $start) (local.get $end)))"
                        (list (new Pair (first "array") (second (sequence-type m type)))
                              (new Pair (first "range") (second (range-helper m)))
                              (new Pair (first "slice")
                                   (second (slice-helper m (sequence-type m type)))))))

    (define (array-replace-helper (m Module) (element Type)) (→ String)
      (template-helper! m "array-replace" (type-key element)
                        "(func {id} (param $array (ref null {array})) (param $index i64) (param $value {element}) (result (ref null {array}))
  (drop (call {range} (array.len (local.get $array)) (local.get $index) (i64.const 1)))
  (return_call {set} (local.get $array) (local.get $index) (local.get $value)))"
                        (Cons (new Pair (first "set")
                                   (second
                                    (set-helper m (array-type m (element-rep m element))
                                                (rep m element))))
                              (array-storage-bindings m element))))

    (define (array-copy-into-helper (m Module) (element Type)) (→ String)
      (template-helper! m "array-copy-into" (type-key element)
                        "(func {id} (param $to (ref null {array})) (param $at i64) (param $from (ref null {array})) (param $start i64) (param $count i64) (result i32)
  (drop (call {range} (array.len (local.get $to)) (local.get $at) (local.get $count)))
  (drop (call {range} (array.len (local.get $from)) (local.get $start) (local.get $count)))
  (array.copy {array} {array} (local.get $to) (i32.wrap_i64 (local.get $at)) (local.get $from) (i32.wrap_i64 (local.get $start)) (i32.wrap_i64 (local.get $count)))
  (i32.const 0))"
                        (array-storage-bindings m element)))

    ;; ---- Fields ----

    ;; Only a record's fields are read and written this way; an enum's are
    ;; read where a pattern matches its case. A record's reference has its
    ;; own struct type, so a field is one `struct.get` or `struct.set`.

    (define (field-access (fn Fn) (index I64) (record Expr)) (→ Wat)
      (wat "struct.get" (id (data-type (● fn module) (● record type))) (int index)
           (emit1 fn record)))

    ;; Wasm evaluates the record before the incoming value, each once.

    (define (field-write (fn Fn) (index I64) (record Expr) (value Expr)) (→ Wat)
      (wat "struct.set" (id (data-type (● fn module) (● record type))) (int index)
           (emit1 fn record) (emit1 fn value)))

    ;; A pure replacement makes a new record that shares the unchanged field
    ;; values. Evaluate both operands before reading the remaining fields.
    (define (replace-field
             (fn Fn)
             (case Case)
             (index I64)
             (value Expr)
             (replacement Expr))
      (→ Wat)
      (let* ((m (● fn module)) (type (● value type)) (holder (data-type m type))
             (record (declare-temp! fn (rep->wat (Reference holder))))
             (incoming (declare-temp! fn (rep->wat (rep m (● replacement type))))))
        (wat "block" (wat "result" (ref-wat holder))
             (wat "local.set" (id record) (emit1 fn value))
             (wat "local.set" (id incoming) (emit1 fn replacement))
             (construct-slots fn case type
                              (map-indexed (lambda (i field)
                                             (if (= i index) (wat "local.get" (id incoming))
                                                 (wat "struct.get" (id holder) (int i)
                                                      (wat "local.get" (id record)))))
                                           (case-field-types m type case))))))

    ;; ---- Host calls ----

    ;; The runtime reads only scalars. A String or Bytes argument, which must come
    ;; last, is copied into the runtime's staging buffer just before the call,
    ;; and the host receives its scalar count or byte-record address.
    ;; A Unit result is no result.

    (define (host-call (m Module) (import Import) (type Type) (args (List Wat)))
      (→ (List Wat))
      (match type
        ((TFun params result)
         (let* ((function-id (import-wat! m
                                          import
                                          (map nonnull (host-params m params))
                                          (if (unit-type? type)
                                              (None)
                                              (Some (nonnull (rep m result))))))
                (call (wat* "call" (Cons (id function-id) (host-args m params args)))))
           (if (unit-type? type) (list call (wat "i32.const" (int 0))) (list call))))
        (_ (panic "internal error: a host function needs a function type"))))

    (define (host-params (m Module) (params (List Type))) (→ (List Rep))
      (map-indexed (lambda (index param)
                     (cond ((not (buffer-type? param)) (rep m param))
                           ((= index (- (length params) 1)) (Scalar "i32"))
                           (else
                            (panic
                             "internal error: a host function's buffer is not its last argument"))))
                   params))

    (define (host-args (m Module) (params (List Type)) (args (List Wat))) (→ (List Wat))
      (map (lambda (pair) (if (buffer-type? (● pair first))
                              (wat "call"
                                   (id (stage-helper m (bytes-type? (● pair first))))
                                   (● pair second))
                              (match (rep m (● pair first))
                                ((Reference _) (wat "ref.as_non_null" (● pair second)))
                                (_ (● pair second)))))
           (zip params args)))

    (define (unit-type? (function-type Type)) (→ Bool)
      (match function-type
        ((TFun _ (TCon "Unit" (Nil))) #t)
        (_ #f)))

    ;; A function the module imports from the host or another module.

    (define (import! (m Module) (import Import) (params (List Rep)) (result (Option Rep)))
      (→ String)
      (import-wat! m import (map rep->wat params)
                   (match result ((Some r) (Some (rep->wat r))) ((None) (None)))))

    (define (import-wat!
             (m Module)
             (import Import)
             (params (List Wat))
             (result (Option Wat)))
      (→ String)
      (import-once! m (string-append "import:" (● import module) ":" (● import symbol))
                    (wasm-id
                     (string-append "import." (● import module) ":" (● import symbol)))
                    (lambda (function-id)
                      (wat "import"
                           (wat-string (● import module))
                           (wat-string (● import symbol))
                           (wat* "func" (Cons (id function-id)
                                              (append
                                               (map (lambda (param) (wat "param" param))
                                                    params)
                                               (match result
                                                 ((Some r) (list (wat "result" r)))
                                                 ((None) (Nil))))))))))

    ;; ---- Exposed handovers ----

    ;; An exposed function's arguments and result cross as the references
    ;; they are. Option Any crosses as a nullable Any, not as its enum wrapper.

    (define (exposed-value-type (m Module) (type Type)) (→ Wat)
      (if (optional-any-type? type)
          (rep->wat (Reference (any-type m)))
          (nonnull (rep m type))))

    (define (option-case (m Module) (some? Bool)) (→ Case)
      (match (find (lambda (case) (= (length (● case fields)) (if some? 1 0)))
                   (● (data-type-of m "snail.core.base:Option") cases))
        ((Some case) case)
        ((None) (panic "internal error: missing Option case"))))

    (define (import-handover (fn Fn) (type Type) (value Wat)) (→ Wat)
      (let ((m (● fn module)))
        (if (optional-any-type? type)
            (wat "if" (wat "result" (rep->wat (rep m type))) (wat "ref.is_null" value)
                 (wat "then" (construct-slots fn (option-case m #f) type (Nil)))
                 (wat "else"
                      (construct-slots fn (option-case m #t) type
                                       (list (wat "ref.as_non_null" value)))))
            value)))

    (define (export-handover (fn Fn) (type Type) (value Wat)) (→ Wat)
      (if (optional-any-type? type)
          (export-option fn type value)
          (match (fn-rep fn type)
            ((Reference _) (wat "ref.as_non_null" value))
            (_ value))))

    (define (export-option (fn Fn) (type Type) (value Wat)) (→ Wat)
      (let* ((m (● fn module)) (temp (declare-temp! fn (rep->wat (rep m type))))
             (read (wat "local.get" (id temp))) (some (case-type m type (option-case m #t))))
        (wat "block" (wat "result" (exposed-value-type m type))
             (wat "local.set" (id temp) value)
             (wat "if" (wat "result" (exposed-value-type m type))
                  (wat "i32.eq" (wat "struct.get" (id (data-type m type)) (int 0) read)
                       (wat "i32.const" (int (● (option-case m #f) tag))))
                  (wat "then" (wat "ref.null" (id (any-type m))))
                  (wat "else"
                       (wat "struct.get"
                            (id some)
                            (int 1)
                            (wat "ref.cast" (ref-wat some) read)))))))

    (define (exposed-function (m Module) (name String) (type Type)) (→ String)
      (match type
        ((TFun params result) (handover-wrapper! m name params result))
        (_ (panic "internal error: exposed value is not a function"))))

    (define (handover-wrapper!
             (m Module)
             (name String)
             (params (List Type))
             (result Type))
      (→ String)
      (let* ((fn (new-fn m))
             (wrapper (wasm-id (string-append "exposed." name)))
             (names
              (map (lambda (i) (string-append "$arg." (i64->string i))) (iota (length params))))
             (args (map (lambda (pair)
                          (import-handover fn
                                           (● pair first)
                                           (wat "local.get" (id (● pair second)))))
                        (zip params names)))
             (value (export-handover fn
                                     result
                                     (wat* "call" (Cons (id (wasm-id name)) args)))))
        (push-function! m wrapper
                        (wat* "func"
                              (Cons (id wrapper)
                                    (concatenate
                                     (list (map (lambda (pair)
                                                  (wat "param"
                                                       (id (● pair second))
                                                       (exposed-value-type m (● pair first))))
                                                (zip params names))
                                           (wrapper-result m result)
                                           (reverse (● (● fn state) locals))
                                           (entry-clears m)
                                           (list (if (unit-result? result)
                                                     (wat "drop" value)
                                                     value))
                                           (entry-returns m))))))
        wrapper))

    ;; A Unit result is no result, as a foreign import's is (`import!`), so
    ;; a module that imports an exposed function of another, as one the
    ;; engine serves, finds the type it declared.

    (define (wrapper-result (m Module) (result Type)) (→ (List Wat))
      (if (unit-result? result) (Nil) (list (wat "result" (exposed-value-type m result)))))

    (define (unit-result? (type Type)) (→ Bool)
      (match type
        ((TCon "Unit" (Nil)) #t)
        (_ #f)))

    ;; A host entry starts with no yield in flight. Nothing between a
    ;; yield's record and its catch traps, but for a stack overflow in the
    ;; call that saves the first frame, and the task loop goes on after a
    ;; trap (host/browser/tasks.mjs's `drive`), so a record left set would
    ;; unwind the next task. A program that never suspends has no record.

    (define (entry-clears (m Module)) (→ (List Wat))
      (if (● (● m suspensions) quiet)
          (Nil)
          (list (wat "global.set" (id (yielding m)) (wat "ref.null" (id (yield-type m)))))))

    ;; And it ends with none: a yield that reached the host would be one to
    ;; a `with-prompt` running beneath it, which the host's own frames
    ;; cannot unwind to.

    (define (entry-returns (m Module)) (→ (List Wat))
      (if (● (● m suspensions) quiet)
          (Nil)
          (list (wat "if" (yielding? m)
                     (wat "then"
                          (wat "call" (id (panic-helper m))
                               (string-literal m "a suspension cannot leave through the host"))
                          (wat "unreachable"))))))

    ;; ---- Pattern matching ----

    ;; Clauses are tried in order. Each clause is a block that its failing
    ;; tests branch out of; a matching clause branches to `done` with its value.

    (define (emit-match
             (fn Fn)
             (expr Expr)
             (scrutinee Expr)
             (clauses (List Clause))
             (tail? Bool))
      (→ (List Wat))
      (let* ((value (declare-temp! fn (rep->wat (fn-rep fn (● scrutinee type)))))
             (done (local-id fn "match"))
             (scrutinee-code (emit1 fn scrutinee)))
        (list (wat "local.set" (id value) scrutinee-code)
              (wat* "block"
                    (Cons (id done)
                          (Cons (wat "result" (rep->wat (fn-rep fn (● expr type))))
                                (append
                                 (map
                                  (lambda (clause) (clause-block fn clause value done tail?))
                                  clauses)
                                 (list (wat "unreachable")))))))))

    ;; The pattern declares the locals its body reads.

    (define (clause-block
             (fn Fn)
             (clause Clause)
             (value String)
             (done String)
             (tail? Bool))
      (→ Wat)
      (let* ((next (local-id fn "clause"))
             (pattern (● clause pattern))
             (tests (pattern-code fn pattern (wat "local.get" (id value)) next))
             (body (emit1-tail fn (● clause body) tail?)))
        (wat* "block" (Cons (id next) (append tests (list (wat "br" (id done) body)))))))

    (define (pattern-code (fn Fn) (pattern Pattern) (value Wat) (fail String))
      (→ (List Wat))
      (match pattern
        ((PWild _) (Nil))
        ((PVar name type)
         (list (wat "local.set" (id (declare-local! fn name (fn-rep fn type))) value)))
        ((PLit literal-value type)
         (list (wat "br_if" (id fail) (literal-differs fn literal-value type value))))
        ((PCon constructor args type)
         (constructor-pattern-code fn constructor args type value fail))))

    (define (literal-differs (fn Fn) (literal-value Datum) (type Type) (scrutinee Wat))
      (→ Wat)
      (let ((constant (literal fn literal-value type)))
        (match (fn-rep fn type)
          ((Scalar name) (wat (string-append name ".ne") scrutinee constant))
          ((Reference _)
           (wat "i32.eqz"
                (wat "call" (id (string-equal-helper (● fn module))) scrutinee constant))))))

    (define (constructor-pattern-code (fn Fn)
                                      (constructor String)
                                      (args (List Pattern))
                                      (type Type)
                                      (value Wat)
                                      (fail String))
      (→ (List Wat))
      (let* ((m (● fn module))
             (case (match (program-value (program-of m) constructor)
                     ((Some (Constructor case _)) case)
                     (_ (panic "internal error: not a constructor"))))
             (name (● case type)))
        (cond ((tag-enum? m name)
               (list (wat "br_if"
                          (id fail)
                          (wat "i32.ne" value (wat "i32.const" (int (● case tag)))))))
              ((not (● (data-type-of m name) enum?))
               (fields-code fn (data-type m type) 0 case type args value fail))
              (else
               ;; A case's own type is registered only when its fields are
               ;; read, so a field-less case never declares one.
               (let ((base (data-type m type)))
                 (Cons (wat "br_if"
                            (id fail)
                            (wat "i32.ne"
                                 (wat "struct.get" (id base) (int 0) value)
                                 (wat "i32.const" (int (● case tag)))))
                       (if (every? wild? args)
                           (Nil)
                           (let* ((case-id (case-type m type case))
                                  (cast (declare-temp! fn (rep->wat (Reference case-id)))))
                             (Cons (wat "local.set"
                                        (id cast)
                                        (wat "ref.cast"
                                             (ref-wat case-id)
                                             value))
                                   (fields-code fn case-id 1 case type args
                                                (wat "local.get" (id cast)) fail))))))))))

    (define (wild? (pattern Pattern)) (→ Bool)
      (match pattern
        ((PWild _) #t)
        (_ #f)))

    ;; Patterns read each selected field once. A nested pattern follows the
    ;; reference in that field; no enclosing object layout is involved.
    (define (fields-code (fn Fn) (holder String) (offset I64) (case Case)
                         (type Type) (args (List Pattern)) (value Wat) (fail String))
      (→ (List Wat))
      (let ((types (case-field-types (● fn module) type case)))
        (concatenate
         (map-indexed (lambda (index arg)
                        (if (wild? arg) (Nil)
                            (slot-pattern-code fn
                                               (wat "struct.get" (id holder)
                                                    (int (+ offset index)) value)
                                               (list-ref types index) arg fail)))
                      args))))

    (define (slot-pattern-code
             (fn Fn)
             (field Wat)
             (type Type)
             (arg Pattern)
             (fail String))
      (→ (List Wat))
      (match arg
        ((PVar _ _) (pattern-code fn arg field fail))
        (_ (let ((temp (declare-temp! fn (rep->wat (fn-rep fn type)))))
             (Cons (wat "local.set" (id temp) field)
                   (pattern-code fn arg (wat "local.get" (id temp)) fail))))))

    ;; ---- Dynamic values ----

    ;; An Any is the TypeId of its value's ground type with the value itself;
    ;; a scalar is boxed so every payload is a reference.

    (define (any-type (m Module)) (→ String)
      (match (known-type m "any")
        ((Some type) type)
        ((None)
         (register-type! m "any" "$any"
                         (wat "type" (Word "$any")
                              (wat "struct" (wat "field" (Word "i32"))
                                   (wat "field" (Word "anyref"))))))))

    (define (box-type (m Module) (r Rep)) (→ String)
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

    ;; The type test proves both nominal identity and representation before
    ;; reading.

    (define (emit-downcast (fn Fn) (inner Expr) (target Type) (result Type)) (→ Wat)
      (let* ((m (● fn module)) (temp (declare-temp! fn (ref-wat (any-type m))))
             (read (wat "local.get" (id temp))))
        (wat "block" (wat "result" (rep->wat (rep m result)))
             (wat "local.set" (id temp) (emit1 fn inner))
             (wat "if" (wat "result" (rep->wat (rep m result)))
                  (any-holds? fn read target)
                  (wat "then" (construct-slots fn (option-case m #t) result
                                               (list (from-any fn target read))))
                  (wat "else" (construct-slots fn (option-case m #f) result (Nil)))))))

    (define (to-any (m Module) (type Type) (value Wat)) (→ Wat)
      (let ((r (rep m type)))
        (wat "struct.new" (id (any-type m))
             (wat "i32.const" (int (any-type-id (program-of m) type)))
             (match r
               ((Scalar _) (wat "struct.new" (id (held-type m r)) value))
               ((Reference _) value)))))

    (define (from-any (fn Fn) (type Type) (value Wat)) (→ Wat)
      (let* ((m (● fn module)) (r (fn-rep fn type))
             (held (wat "ref.cast" (ref-wat (held-type m r))
                        (wat "struct.get" (id (any-type m)) (int 1) value))))
        (match r
          ((Scalar _) (wat "struct.get" (id (held-type m r)) (int 0) held))
          ((Reference _) held))))

    ;; An Any holds a value of `type` when its TypeId is the type's and its
    ;; value has the type's representation, which `ref.test` checks without
    ;; trapping.

    (define (any-holds? (fn Fn) (value Wat) (type Type)) (→ Wat)
      (let* ((m (● fn module))
             (field (lambda (index) (wat "struct.get" (id (any-type m)) (int index) value))))
        (wat "i32.and"
             (wat "i32.eq" (field 0) (wat "i32.const" (int (any-type-id (program-of m) type))))
             (wat "ref.test" (wat "ref" (id (held-type m (fn-rep fn type)))) (field 1)))))

    ;; What an Any holds for a value of representation `r`: the value, or a
    ;; box around a scalar.

    (define (held-type (m Module) (r Rep)) (→ String)
      (match r
        ((Scalar _) (box-type m r))
        ((Reference type) type)))

    ;; ---- Funcref closures ----

    ;; A Funcref becomes a closure that holds it, whose code casts it to the
    ;; Wasm type of a function of the expected type and calls it. The cast is
    ;; the only check: the engine traps if the function's Wasm type differs,
    ;; and nothing compares `snail-scheme` types, which is what makes the cast unsafe.
    ;; That type is a `snail-scheme` function's, so the held function is one
    ;; another module compiled from `snail-scheme`.

    (define (funcref-closure (m Module) (type Type) (reference Wat)) (→ Wat)
      (match type
        ((TFun _ _)
         (let* ((signature (function-signature m type))
                (base (closure-type m (● signature first) (● signature second)))
                (holder (funcref-holder-type m base)))
           (wat "struct.new"
                (id holder)
                (wat "ref.func" (id (funcref-code m signature base holder)))
                reference)))
        (_ (panic (string-append "unsafe-cast makes a function, not a " (type->string type))))))

    (define (funcref-holder-type (m Module) (base String)) (→ String)
      (capture-type m base (list (Scalar "funcref"))))

    ;; The code takes the closure and the arguments, and calls the function
    ;; the closure holds with the arguments, at that function's own type,
    ;; which takes no closure.

    (define (funcref-code (m Module)
                          (signature (Pair (List Rep) Rep))
                          (base String)
                          (holder String))
      (→ String)
      (let ((params (● signature first)) (result (● signature second)))
        (helper! m "funcref" holder
                 (lambda (function-id)
                   (push! (● m declared) function-id)
                   (wat* "func"
                         (concatenate
                          (list (list (id function-id) (wat "type" (id (code-type m base)))
                                      (wat "param" (ref-wat base)))
                                (map (lambda (param) (wat "param" (rep->wat param))) params)
                                (list (wat "result" (rep->wat result))
                                      (held-call m params result holder)))))))))

    ;; The code passes on its parameters, which follow the closure, local 0.

    (define (held-call (m Module) (params (List Rep)) (result Rep) (holder String))
      (→ Wat)
      (let ((own (funcref-type m params result))
            (held (wat "struct.get"
                       (id holder)
                       (int 1)
                       (wat "ref.cast"
                            (ref-wat holder)
                            (wat "local.get" (int 0))))))
        (wat* "call_ref"
              (append (Cons (id own)
                            (map (lambda (index) (wat "local.get" (int (+ index 1))))
                                 (iota (length params))))
                      (list (wat "ref.cast" (ref-wat own) held))))))

    ;; The Wasm type of the function a Funcref refers to, which takes no
    ;; closure.

    (define (funcref-type (m Module) (params (List Rep)) (result Rep)) (→ String)
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
                                      (append (map (lambda (param) (wat "param" (rep->wat param)))
                                                   params)
                                              (list (wat "result" (rep->wat result)))))))))))

    ;; ---- Control ----

    ;; `suspend` records a yield in one global: the prompt it is aimed at,
    ;; whether anything may resume it, its value, and the frames saved so
    ;; far. It then returns zero or null for its inactive result slot. Each
    ;; call that may yield is the value of a let, as (snail shell compiler
    ;; prepare) arranges, and after that let the record is tested: while it
    ;; is set, the let saves its body as a frame on the record (see Frames)
    ;; and leaves with zero or null, a function to its caller, until the
    ;; `with-prompt` of the record's prompt. That one clears the record and
    ;; calls its handler with the recorded value and a `resume` holding the
    ;; frames (see Resuming); the handler's result is the `with-prompt`'s.
    ;; A yield to a prompt that answers Never is never resumed, so where a
    ;; call may yield to no other, its test leaves without saving a frame,
    ;; and no join is built for the rest. A call whose value flows straight
    ;; out needs no test, so a tail call stays a tail call. Nothing reads
    ;; an inactive slot, since every caller tests first and leaves too. The
    ;; record is clear whenever `snail-scheme` code runs outside a yield,
    ;; so none is live while the host runs between calls.

    ;; Where a yield leaves the code being emitted, with zero or null: a
    ;; function returns its inactive result to its caller; a block, the
    ;; value of a let, branches to its end with one of its type; a join
    ;; function returns null to the runner, for the boxed value it would
    ;; have returned.
    (enum Exit
      (ToCaller
       ((result Type)))
      (ToBlock
       ((label String)
        (result Type)))
      (ToRunner))

    (define (function-exit (type Type)) (→ (Option Exit))
      (match type
        ((TFun _ result) (Some (ToCaller result)))
        (_ (panic "internal error: not a function type"))))

    (define (yield-type (m Module)) (→ String)
      (match (known-type m "yield")
        ((Some type) type)
        ((None)
         (let ((frames (frames-type m)) (prompt (prompt-type m)))
           (register-type! m "yield" "$yield"
                           (wat "type" (id "$yield")
                                (wat "struct"
                                     (wat "field" (ref-wat prompt))
                                     (wat "field" (Word "i32"))
                                     (wat "field" (Word "anyref"))
                                     (wat "field"
                                          (wat "mut" (ref-wat frames))))))))))

    ;; The global holding the record, null while nothing yields, which the
    ;; program declares and exports.

    (define (yielding (m Module)) (→ String)
      (unless (table-contains? (● m helpers) "yielding")
        (put! (● m helpers) "yielding" "$yielding")
        (push! (● m globals)
               (wat "global"
                    (id "$yielding")
                    (wat "mut" (ref-wat (yield-type m)))
                    (wat "ref.null" (id "$yield"))))
        (push! (● m exports)
               (wat "export" (wat-string "yielding") (wat "global" (id "$yielding")))))
      "$yielding")

    (define (yielding? (m Module)) (→ Wat)
      (wat "i32.eqz" (wat "ref.is_null" (wat "global.get" (id (yielding m))))))

    (define (may-yield? (fn Fn) (value Expr)) (→ Bool)
      (not (null? (yields (● (● fn module) suspensions) value))))

    ;; Whether nothing resumes what `value` may yield to: a `with-prompt`
    ;; that catches such a yield is handed a `resume` no value could be
    ;; given to, and nothing will run what follows the yield.

    (define (aborts? (fn Fn) (value Expr)) (→ Bool)
      (let ((suspensions (● (● fn module) suspensions)))
        (not (may-resume? suspensions (yields suspensions value)))))

    ;; The rest of a let after its value. When the value may yield, a test
    ;; comes first: while the record is set, it saves the let's body as a
    ;; frame and leaves. In a join function, whose own rest the body is,
    ;; the body then runs in that frame, by a tail call as the runner would
    ;; make, so each join holds its body only up to the next yield point.
    ;; A yield that nothing can resume saves nothing, so its test only
    ;; leaves, and the body follows in the same function.

    (define (let-rest (fn Fn) (name String) (value Expr) (body Expr) (tail? Bool))
      (→ (List Wat))
      (cond ((not (may-yield? fn value)) (emit fn body tail?))
            ((aborts? fn value)
             (Cons (wat "if" (yielding? (● fn module)) (wat "then" (leave fn)))
                   (emit fn body tail?)))
            ((match (● fn exit) ((Some (ToRunner)) #t) (_ #f))
             (continue-in-frame fn name value body))
            ;; The frame reads the locals declared so far, so it is built
            ;; before the body declares its own.
            (else (let ((test (yield-test fn (frame fn name value body))))
                    (append test (emit fn body tail?))))))

    (define (yield-test (fn Fn) (saved Wat)) (→ (List Wat))
      (let* ((m (● fn module)) (exit (leave fn)))
        (list (wat "if"
                   (yielding? m)
                   (wat "then" (wat "call" (id (push-helper m)) saved) exit)))))

    (define (continue-in-frame (fn Fn) (name String) (value Expr) (body Expr))
      (→ (List Wat))
      (let* ((m (● fn module)) (base (frame-type m))
             (temp (declare-temp! fn (ref-wat base)))
             (saved (wat "local.get" (id temp)))
             (set (wat "local.set" (id temp) (frame fn name value body)))
             (test (yield-test fn saved))
             (argument (box-value m (● value type) (variable fn name unchecked))))
        (Cons set
              (append test (list (wat "return_call" (id (frame-runner m)) saved argument))))))

    ;; A let's value that holds yield points of its own is a block they
    ;; leave, so that the let's own test then saves the let's body too.

    (define (emit-let-value (fn Fn) (value Expr)) (→ Wat)
      (if (holds-yield-point? (● (● fn module) suspensions) value)
          (let ((label (local-id fn "yield")) (type (● value type)))
            (wat* "block"
                  (Cons (id label)
                        (Cons (wat "result" (rep->wat (fn-rep fn type)))
                              (emit (Fn-exit-set fn (Some (ToBlock label type))) value #f)))))
          (emit1 fn value)))

    (define (leave (fn Fn)) (→ Wat)
      (match (● fn exit)
        ((Some (ToCaller result)) (wat "return" (default-value (rep (● fn module) result))))
        ((Some (ToBlock label result))
         (wat "br" (id label) (default-value (rep (● fn module) result))))
        ((Some (ToRunner)) (wat "return" (wat "ref.null" (Word "any"))))
        ((None) (panic "internal error: a yield outside any function"))))

    ;; Code the backend writes itself calls a procedure where no let can
    ;; test: a cache's function, an exposed function. After such a call a
    ;; yield in flight leaves `inactive`, the caller's to test, when the
    ;; program yields at all.

    (define (yield-leaves (m Module) (inactive Wat)) (→ Wat)
      (if (● (● m suspensions) quiet)
          (wat "nop")
          (wat "if" (yielding? m) (wat "then" (wat "return" inactive)))))

    ;; ---- Frames ----

    ;; A frame is a closure over the rest of a function at a yield point:
    ;; the body of a let whose value yielded. Its code takes the frame and
    ;; the let's value and returns the body's, each boxed when a scalar, so
    ;; one code type serves every frame. It holds the locals its body
    ;; reads. Outside join functions a frame is built only on the path that
    ;; leaves, so the fast path allocates none.

    ;; The runner runs one saved frame, detached from its continuation
    ;; before entry.
    (define (frame-runner (m Module)) (→ String)
      (template-helper! m "frame-run" ""
                        "(func {id} (param $frame (ref null {frame})) (param $value anyref) (result anyref)
  (return_call_ref {code} (local.get $frame) (local.get $value) (struct.get {frame} 0 (local.get $frame))))"
                        (list (new Pair (first "frame") (second (frame-type m)))
                              (new Pair (first "code") (second (code-type m (frame-type m)))))))

    (define (frame-type (m Module)) (→ String)
      (match (known-type m "frame")
        ((Some type) type)
        ((None)
         (put! (● m type-ids) "code:$frame" "$frame.code")
         (register-type! m "frame.code" "$frame.code"
                         (wat "type" (id "$frame.code")
                              (wat "func" (wat "param" (ref-wat "$frame"))
                                   (wat "param" (Word "anyref")) (wat "result" (Word "anyref")))))
         (register-type! m "frame" "$frame"
                         (wat "type"
                              (id "$frame")
                              (wat "sub" (wat* "struct" (closure-fields m "$frame"))))))))

    ;; A list of frames. The record's grows at its head as the yield leaves
    ;; each frame, so its outermost frame comes first; a continuation's is
    ;; reversed, into the order the frames run in.

    (define (frames-type (m Module)) (→ String)
      (match (known-type m "frames")
        ((Some type) type)
        ((None)
         (let ((frame (frame-type m)))
           (register-type! m "frames" "$frames"
                           (wat "type"
                                (id "$frames")
                                (wat "struct"
                                     (wat "field" (ref-wat frame))
                                     (wat "field" (ref-wat "$frames")))))))))

    ;; The frame of the let binding `name` to `value`: the join function of
    ;; its body, and the locals the body reads.

    (define (frame (fn Fn) (name String) (value Expr) (body Expr)) (→ Wat)
      (let* ((m (● fn module))
             (captured (filter (lambda (local) (and (not (string=? local name)) (local? fn local)))
                               (delete-duplicates string=? (expr-references body))))
             (entries (map (lambda (local) (new Pair (first local) (second (capture-rep fn local))))
                           captured))
             (type
              (capture-type
               m
               (frame-type m)
               (map (lambda (record) (● record second)) entries)))
             (join
              (emit-join!
               (Fn-exit-set (new-fn m) (Some (ToRunner)))
               name
               value
               body
               entries
               type)))
        (wat* "struct.new"
              (append (list (id type) (wat "ref.func" (id join)))
                      (map (lambda (local) (variable fn local unchecked)) captured)))))

    ;; A let's body as a function of its frame and its boxed value: it
    ;; loads the frame's locals and binds the value, runs the body, which a
    ;; yield leaves with null, and boxes the body's value. The body runs to
    ;; the let's end and no further, since the frames outside it continue
    ;; from there, and its tail calls are calls, since their results are
    ;; boxed. It is named by its text, as a lambda is, so the joins of one
    ;; let, which the function and the join of the let before it both need,
    ;; are one function.

    (define (emit-join! (join Fn)
                        (name String)
                        (value Expr)
                        (body Expr)
                        (entries (List (Pair String Rep)))
                        (type String))
      (→ String)
      (let* ((m (● join module))
             (loads (capture-loads join entries type))
             (local (declare-local! join name (fn-rep join (● value type))))
             (argument (wat "local.set"
                            (id local)
                            (unbox-value m (● value type) (wat "local.get" (Word "$value")))))
             (result (box-value m (● body type) (emit1 join body))))
        (lambda-id m
                   "join"
                   (join-wat join (append loads (list argument result)))
                   0)))

    (define (join-wat (join Fn) (code (List Wat))) (→ Wat)
      (let* ((m (● join module)) (frame (frame-type m)))
        (wat* "func" (append (list (Word "$lambda.self") (wat "type" (id (code-type m frame)))
                                   (wat "param"
                                        (Word "$closure")
                                        (ref-wat frame))
                                   (wat "param" (Word "$value") (Word "anyref"))
                                   (wat "result" (Word "anyref")))
                             (append (reverse (● (● join state) locals)) code)))))

    ;; A value as frames pass it: a reference as it is, a scalar boxed as
    ;; an Any holds it.

    (define (box-value (m Module) (type Type) (value Wat)) (→ Wat)
      (match (rep m type)
        ((Scalar name) (wat "struct.new" (id (box-type m (Scalar name))) value))
        ((Reference _) value)))

    (define (unbox-value (m Module) (type Type) (value Wat)) (→ Wat)
      (match (rep m type)
        ((Scalar name)
         (let ((box (box-type m (Scalar name))))
           (wat "struct.get"
                (id box)
                (int 0)
                (wat "ref.cast" (ref-wat box) value))))
        ((Reference type-id) (wat "ref.cast" (ref-wat type-id) value))))

    ;; Saves a frame on the record, as the yield leaves it.

    (define (push-helper (m Module)) (→ String)
      (template-helper! m "control" "push"
                        "(func {id} (param $frame (ref null {frame}))
  (local $record (ref null {yield}))
  (local.set $record (global.get {yielding}))
  (struct.set {yield} 3 (local.get $record) (struct.new {frames} (local.get $frame) (struct.get {yield} 3 (local.get $record)))))"
                        (list (new Pair (first "frame") (second (frame-type m)))
                              (new Pair (first "yield") (second (yield-type m)))
                              (new Pair (first "yielding") (second (yielding m)))
                              (new Pair (first "frames") (second (frames-type m))))))

    ;; ---- Prompts ----

    ;; A prompt has nothing but its identity and the number of its
    ;; `with-prompt`s that are running. `suspend` reads the count: with
    ;; none, nothing would catch the yield, so it panics instead.

    (define (prompt-type (m Module)) (→ String)
      (match (known-type m "prompt")
        ((Some type) type)
        ((None)
         (register-type! m "prompt" "$prompt"
                         (wat "type" (id "$prompt")
                              (wat "struct" (wat "field" (wat "mut" (Word "i32")))))))))

    (define (new-prompt (m Module)) (→ Wat)
      (wat "struct.new" (id (prompt-type m)) (wat "i32.const" (int 0))))

    ;; The value a prompt's suspensions carry and the answer one resumes
    ;; with.

    (define (prompt-types (type Type)) (→ (Pair Type Type))
      (match type
        ((TCon "Prompt" (Cons value (Cons answer (Nil))))
         (new Pair (first value) (second answer)))
        (_ (panic "internal error: a prompt has the Prompt type"))))

    ;; `$prompt` entering (+1) or leaving (-1) one of its `with-prompt`s.

    (define (prompt-count (m Module) (change String)) (→ String)
      (fill
       "(struct.set {prompt} 0 (local.get $prompt) (i32.add (struct.get {prompt} 0 (local.get $prompt)) (i32.const {change})))"
       (list (new Pair (first "prompt") (second (prompt-type m)))
             (new Pair (first "change") (second change)))))

    ;; `suspend` for one prompt type: the yield, with no frames yet, then
    ;; the inactive answer. Its call sites are ordinary calls, which test
    ;; for the yield as any call that may yield is tested.

    (define (suspender (m Module) (type Type)) (→ String)
      (let* ((types (prompt-types type)) (value (● types first)) (answer (● types second)))
        (template-helper! m "suspend" (type-key type)
                          "(func {id} (param $prompt (ref null {prompt})) (param $value {value}) (result {answer})
  (if (i32.eqz (struct.get {prompt} 0 (local.get $prompt)))
    (then (call {panic} {message}) (unreachable)))
  (global.set {yielding} (struct.new {yield} (local.get $prompt) (i32.const {resumed}) {boxed} (ref.null {frames})))
  {inactive})"
                          (list (new Pair (first "prompt") (second (prompt-type m)))
                                (new Pair
                                  (first "value")
                                  (second (wat->text (rep->wat (rep m value)))))
                                (new Pair
                                  (first "answer")
                                  (second (wat->text (rep->wat (rep m answer)))))
                                (new Pair (first "panic") (second (panic-helper m)))
                                (new Pair
                                  (first "message")
                                  (second
                                   (wat->text
                                    (string-literal m
                                                    "suspend: no with-prompt of this prompt is running"))))
                                (new Pair (first "yielding") (second (yielding m)))
                                (new Pair (first "yield") (second (yield-type m)))
                                (new Pair
                                  (first "resumed")
                                  (second (if (never-type? answer) "0" "1")))
                                (new Pair
                                  (first "boxed")
                                  (second (wat->text (box-value m
                                                                value
                                                                (wat "local.get"
                                                                     (Word "$value"))))))
                                (new Pair (first "frames") (second (frames-type m)))
                                (new Pair
                                  (first "inactive")
                                  (second (wat->text (default-value (rep m answer)))))))))

    ;; One `with-prompt`'s types: its prompt's, and its result's, which is
    ;; its body's and its handler's.
    (record Delimiter
      ((prompt Type)
       (result Type)))

    (define (delimiter-key (delimiter Delimiter)) (→ String)
      (string-append (type-key (● delimiter prompt)) " " (type-key (● delimiter result))))

    ;; `resume`'s closure type, of the prompt's answer to the result, and
    ;; the handler's, of the suspension's value and `resume` to the result.

    (define (resume-base (m Module) (delimiter Delimiter)) (→ String)
      (closure-type m
                    (list (rep m (● (prompt-types (● delimiter prompt)) second)))
                    (rep m (● delimiter result))))

    (define (handler-base (m Module) (delimiter Delimiter)) (→ String)
      (closure-type m
                    (list (rep m (● (prompt-types (● delimiter prompt)) first))
                          (Reference (resume-base m delimiter)))
                    (rep m (● delimiter result))))

    ;; The bindings every delimiter helper's text is filled from.

    (define (delimiter-bindings (m Module) (delimiter Delimiter))
      (→ (List (Pair String String)))
      (let ((result (● delimiter result)))
        (list (new Pair (first "prompt") (second (prompt-type m)))
              (new Pair (first "handler") (second (handler-base m delimiter)))
              (new Pair (first "result") (second (wat->text (rep->wat (rep m result)))))
              (new Pair (first "inactive") (second (wat->text (default-value (rep m result)))))
              (new Pair (first "yielding") (second (wat->text (yielding? m))))
              (new Pair (first "continuation") (second (continuation-type m)))
              (new Pair (first "enter") (second (prompt-count m "1")))
              (new Pair (first "leave") (second (prompt-count m "-1"))))))

    ;; `with-prompt`: the body runs with the prompt counted as running, and
    ;; a yield that comes back from it is the catch's, in tail position.

    (define (delimiter-helper (m Module) (delimiter Delimiter)) (→ String)
      (let ((body (closure-type m (Nil) (rep m (● delimiter result)))))
        (template-helper! m "with-prompt" (delimiter-key delimiter)
                          "(func {id} (param $prompt (ref null {prompt})) (param $body (ref null {body})) (param $handler (ref null {handler})) (result {result})
  (local $value {result})
  {enter}
  (local.set $value {call})
  {leave}
  (if {yielding} (then (return_call {catch} (local.get $prompt) (local.get $handler))))
  (local.get $value))"
                          (append (delimiter-bindings m delimiter)
                                  (list (new Pair (first "body") (second body))
                                        (new Pair
                                          (first "call")
                                          (second (wat->text
                                                   (closure-call-wat m
                                                                     body
                                                                     (wat "local.get"
                                                                          (Word "$body"))
                                                                     (Nil)
                                                                     #f))))
                                        (new Pair
                                          (first "catch")
                                          (second (catcher m delimiter))))))))

    ;; What a `with-prompt` does with the yield that has reached it; its
    ;; call site and `resume` both end here. A yield nothing resumes, aimed
    ;; at another prompt, passes with nothing saved. Otherwise the yield's
    ;; frames become a continuation. A yield aimed at another prompt leaves
    ;; with that continuation as its one frame, and the result stays
    ;; inactive. One aimed at `$prompt` is caught: the record is cleared,
    ;; and the handler runs with the recorded value and a `resume` holding
    ;; the continuation. Its call is a tail
    ;; call, so a handler that resumes in tail position runs in constant
    ;; stack however many times its body suspends.

    (define (catcher (m Module) (delimiter Delimiter)) (→ String)
      (let* ((handler (handler-base m delimiter))
             (resume (resume-base m delimiter))
             (value (● (prompt-types (● delimiter prompt)) first))
             (record (wat "local.get" (Word "$record"))))
        (template-helper! m "catch" (delimiter-key delimiter)
                          "(func {id} (param $prompt (ref null {prompt})) (param $handler (ref null {handler})) (result {result})
  (local $record (ref null {yield})) (local $continuation (ref null {continuation})) (local $own i32)
  (local.set $record (global.get {record}))
  (local.set $own (ref.eq (struct.get {yield} 0 (local.get $record)) (local.get $prompt)))
  (if (i32.eqz (i32.or (local.get $own) (struct.get {yield} 1 (local.get $record))))
    (then (return {inactive})))
  (local.set $continuation
    (struct.new {continuation} (ref.func {handled}) (call {reverse} (struct.get {yield} 3 (local.get $record))) (local.get $prompt) (local.get $handler) (i32.const 0)))
  (if (i32.eqz (local.get $own))
    (then
      (struct.set {yield} 3 (local.get $record) (struct.new {frames} (local.get $continuation) (ref.null {frames})))
      (return {inactive})))
  (global.set {record} (ref.null {yield}))
  (return_call_ref {code} (local.get $handler) {value}
    (struct.new {resume} (ref.func {resume-code}) (local.get $continuation))
    (struct.get {handler} 0 (local.get $handler))))"
                          (append (delimiter-bindings m delimiter)
                                  (list (new Pair (first "record") (second (yielding m)))
                                        (new Pair (first "yield") (second (yield-type m)))
                                        (new Pair (first "frames") (second (frames-type m)))
                                        (new Pair
                                          (first "handled")
                                          (second (handled-code m delimiter)))
                                        (new Pair (first "reverse") (second (reverse-helper m)))
                                        (new Pair (first "code") (second (code-type m handler)))
                                        (new Pair
                                          (first "value")
                                          (second (wat->text
                                                   (unbox-value m
                                                                value
                                                                (wat "struct.get"
                                                                     (id (yield-type m))
                                                                     (int 2)
                                                                     record)))))
                                        (new Pair
                                          (first "resume")
                                          (second (resume-type m resume)))
                                        (new Pair
                                          (first "resume-code")
                                          (second (resume-code m delimiter))))))))

    ;; ---- Resuming ----

    ;; A continuation holds the frames saved inside a `with-prompt`,
    ;; innermost first, its prompt and handler, and whether it has been
    ;; resumed. The `with-prompt` is deep: resumed, the frames run under it
    ;; again, so a yield aimed at its prompt runs the handler again, in tail
    ;; position, as the call site would, even after that call has returned.
    ;; A continuation is itself a frame, whose code is the `with-prompt`
    ;; again: a `with-prompt` that any other yield leaves, at its site or
    ;; resumed, is that one frame among the yield's, so resuming the
    ;; computation around it enters it again too. A continuation runs at
    ;; most once. A `resume` that is never called leaves its frames to the
    ;; collector, and nothing finishes them.

    (define (continuation-type (m Module)) (→ String)
      (match (known-type m "continuation")
        ((Some type) type)
        ((None)
         (let ((frame (frame-type m)) (frames (frames-type m)) (prompt (prompt-type m)))
           (register-type! m "continuation" "$continuation"
                           (wat "type" (id "$continuation")
                                (wat "sub" (Word "final") (id frame)
                                     (wat* "struct"
                                           (append
                                            (closure-fields m frame)
                                            (list (wat "field" (wat "mut" (ref-wat frames)))
                                                  (wat "field" (ref-wat prompt))
                                                  (wat "field" (Word "anyref"))
                                                  (wat "field" (wat "mut" (Word "i32")))))))))))))

    ;; `resume`, a closure of the prompt's answer to the `with-prompt`'s
    ;; result, holding the continuation.

    (define (resume-type (m Module) (base String)) (→ String)
      (capture-type m base (list (Reference (continuation-type m)))))

    ;; The code of `resume`: the `with-prompt` again, run on the boxed
    ;; answer. `resume` is an ordinary function to the checker, so a second
    ;; call is refused here, before it could run frames another call has
    ;; taken.

    (define (resume-code (m Module) (delimiter Delimiter)) (→ String)
      (helper! m "resume" (delimiter-key delimiter)
               (lambda (function-id)
                 (let* ((base (resume-base m delimiter))
                        (answer (● (prompt-types (● delimiter prompt)) second)))
                   (push! (● m declared) function-id)
                   (Word
                    (fill
                     "(func {id} (type {code}) (param $closure (ref null {base})) (param $answer {answer}) (result {result})
  (local $continuation (ref null {continuation}))
  (local.set $continuation (struct.get {resume} 1 (ref.cast (ref null {resume}) (local.get $closure))))
  (if (struct.get {continuation} 4 (local.get $continuation))
    (then (call {panic} {message}) (unreachable)))
  (struct.set {continuation} 4 (local.get $continuation) (i32.const 1))
  (return_call {rehandle} (local.get $continuation) {boxed}))"
                     (append (delimiter-bindings m delimiter)
                             (list (new Pair (first "id") (second function-id))
                                   (new Pair (first "code") (second (code-type m base)))
                                   (new Pair (first "base") (second base))
                                   (new Pair
                                     (first "answer")
                                     (second (wat->text (rep->wat (rep m answer)))))
                                   (new Pair (first "panic") (second (panic-helper m)))
                                   (new Pair
                                     (first "message")
                                     (second
                                      (wat->text (string-literal m "resume called twice"))))
                                   (new Pair
                                     (first "rehandle")
                                     (second (rehandler m delimiter)))
                                   (new Pair (first "resume") (second (resume-type m base)))
                                   (new Pair
                                     (first "boxed")
                                     (second (wat->text
                                              (box-value m
                                                         answer
                                                         (wat "local.get"
                                                              (Word "$answer"))))))))))))))

    ;; The `with-prompt` again: the continuation run on a boxed value with
    ;; its prompt counted as running, ending, if a yield reaches it, in the
    ;; catch, in tail position.

    (define (rehandler (m Module) (delimiter Delimiter)) (→ String)
      (template-helper! m "rehandle" (delimiter-key delimiter)
                        "(func {id} (param $continuation (ref null {continuation})) (param $value anyref) (result {result})
  (local $prompt (ref null {prompt}))
  (local.set $prompt (struct.get {continuation} 2 (local.get $continuation)))
  {enter}
  (local.set $value (call {continue} (local.get $continuation) (local.get $value)))
  {leave}
  (if {yielding}
    (then (return_call {catch} (local.get $prompt)
      (ref.cast (ref null {handler}) (struct.get {continuation} 3 (local.get $continuation))))))
  {unboxed})"
                        (append (delimiter-bindings m delimiter)
                                (list (new Pair (first "continue") (second (continue-helper m)))
                                      (new Pair (first "catch") (second (catcher m delimiter)))
                                      (new Pair
                                        (first "unboxed")
                                        (second (wat->text
                                                 (unbox-value m
                                                              (● delimiter result)
                                                              (wat "local.get"
                                                                   (Word "$value"))))))))))

    ;; A continuation's code as a frame: run, it is the `with-prompt`
    ;; again, and it boxes the result.

    (define (handled-code (m Module) (delimiter Delimiter)) (→ String)
      (helper! m "handled" (delimiter-key delimiter)
               (lambda (function-id)
                 (let ((frame (frame-type m)) (continuation (continuation-type m)))
                   (push! (● m declared) function-id)
                   (Word
                    (fill
                     "(func {id} (type {code}) (param $frame (ref null {frame})) (param $value anyref) (result anyref)
  {boxed})"
                     (list (new Pair (first "id") (second function-id))
                           (new Pair (first "code") (second (code-type m frame)))
                           (new Pair (first "frame") (second frame))
                           (new Pair
                             (first "boxed")
                             (second
                              (wat->text
                               (box-value m
                                          (● delimiter result)
                                          (wat "call"
                                               (id (rehandler m delimiter))
                                               (wat "ref.cast"
                                                    (ref-wat continuation)
                                                    (wat "local.get" (Word "$frame")))
                                               (wat "local.get" (Word "$value"))))))))))))))

    ;; Runs a continuation and takes the frames out, so that neither the
    ;; continuation nor `resume` holds them while they run. Then each frame
    ;; runs in turn, innermost first, on the value the one before produced.
    ;; When a frame yields, the frames after it are saved on the record in
    ;; turn, as if the yield were leaving them, and the loop returns with
    ;; the record set, so its caller leaves too. A `with-prompt` among the
    ;; frames is one frame that runs the frames inside it itself, so a
    ;; yield aimed at its prompt is caught there and never passes through
    ;; this loop.

    (define (continue-helper (m Module)) (→ String)
      (let ((frame (frame-type m)))
        (template-helper! m "control" "continue"
                          "(func {id} (param $continuation (ref null {continuation})) (param $value anyref) (result anyref)
  (local $frames (ref null {frames}))
  (local $frame (ref null {frame}))
  (local.set $frames (struct.get {continuation} 1 (local.get $continuation)))
  (struct.set {continuation} 1 (local.get $continuation) (ref.null {frames}))
  (loop $next
    (if (ref.is_null (local.get $frames)) (then (return (local.get $value))))
    (local.set $frame (struct.get {frames} 0 (local.get $frames)))
    (local.set $frames (struct.get {frames} 1 (local.get $frames)))
    (if (ref.is_null (global.get {yielding}))
      (then (local.set $value (call {run} (local.get $frame) (local.get $value))))
      (else (call {push} (local.get $frame))))
    (br $next))
  (unreachable))"
                          (list (new Pair (first "run") (second (frame-runner m)))
                                (new Pair (first "continuation") (second (continuation-type m)))
                                (new Pair (first "frames") (second (frames-type m)))
                                (new Pair (first "frame") (second frame))
                                (new Pair (first "yielding") (second (yielding m)))
                                (new Pair (first "push") (second (push-helper m)))))))

    (define (reverse-helper (m Module)) (→ String)
      (template-helper! m "control" "reverse"
                        "(func {id} (param $frames (ref null {frames})) (result (ref null {frames}))
  (local $reversed (ref null {frames}))
  (block $done
    (loop $next
      (br_if $done (ref.is_null (local.get $frames)))
      (local.set $reversed (struct.new {frames} (struct.get {frames} 0 (local.get $frames)) (local.get $reversed)))
      (local.set $frames (struct.get {frames} 1 (local.get $frames)))
      (br $next)))
  (local.get $reversed))"
                        (list (new Pair (first "frames") (second (frames-type m))))))

    ;; ---- Primitives ----

    ;; Primitives with a single Wasm instruction.

    (define (primitive-instruction (operation String)) (→ (Option String))
      (case operation
        (("i32-add") (Some "i32.add"))
        (("i32-sub") (Some "i32.sub"))
        (("i32-mul") (Some "i32.mul"))
        (("i32-quotient") (Some "i32.div_s"))
        (("i32-remainder") (Some "i32.rem_s"))
        (("i32-and") (Some "i32.and"))
        (("i32-or") (Some "i32.or"))
        (("i32-xor") (Some "i32.xor"))
        (("i32-shift-left") (Some "i32.shl"))
        (("i32-shift-right") (Some "i32.shr_s"))
        (("i32-shift-right/logical") (Some "i32.shr_u"))
        (("i32-eq") (Some "i32.eq"))
        (("i32-lt") (Some "i32.lt_s"))
        (("i32-le") (Some "i32.le_s"))
        (("i32-gt") (Some "i32.gt_s"))
        (("i32-ge") (Some "i32.ge_s"))
        (("i64-add") (Some "i64.add"))
        (("i64-sub") (Some "i64.sub"))
        (("i64-mul") (Some "i64.mul"))
        (("i64-quotient") (Some "i64.div_s"))
        (("i64-remainder") (Some "i64.rem_s"))
        (("i64-and") (Some "i64.and"))
        (("i64-or") (Some "i64.or"))
        (("i64-xor") (Some "i64.xor"))
        (("i64-shift-left") (Some "i64.shl"))
        (("i64-shift-right") (Some "i64.shr_s"))
        (("i64-shift-right/logical") (Some "i64.shr_u"))
        (("i64-eq") (Some "i64.eq"))
        (("i64-lt") (Some "i64.lt_s"))
        (("i64-le") (Some "i64.le_s"))
        (("i64-gt") (Some "i64.gt_s"))
        (("i64-ge") (Some "i64.ge_s"))
        (("f32-add") (Some "f32.add"))
        (("f32-sub") (Some "f32.sub"))
        (("f32-mul") (Some "f32.mul"))
        (("f32-div") (Some "f32.div"))
        (("f32-min") (Some "f32.min"))
        (("f32-max") (Some "f32.max"))
        (("f32-eq") (Some "f32.eq"))
        (("f32-lt") (Some "f32.lt"))
        (("f32-le") (Some "f32.le"))
        (("f32-gt") (Some "f32.gt"))
        (("f32-ge") (Some "f32.ge"))
        (("f32-sqrt") (Some "f32.sqrt"))
        (("f32-abs") (Some "f32.abs"))
        (("f32-negate") (Some "f32.neg"))
        (("f32-floor") (Some "f32.floor"))
        (("f32-ceiling") (Some "f32.ceil"))
        (("f32-truncate") (Some "f32.trunc"))
        (("f32-round") (Some "f32.nearest"))
        (("f64-add") (Some "f64.add"))
        (("f64-sub") (Some "f64.sub"))
        (("f64-mul") (Some "f64.mul"))
        (("f64-div") (Some "f64.div"))
        (("f64-min") (Some "f64.min"))
        (("f64-max") (Some "f64.max"))
        (("f64-eq") (Some "f64.eq"))
        (("f64-lt") (Some "f64.lt"))
        (("f64-le") (Some "f64.le"))
        (("f64-gt") (Some "f64.gt"))
        (("f64-ge") (Some "f64.ge"))
        (("f64-sqrt") (Some "f64.sqrt"))
        (("f64-abs") (Some "f64.abs"))
        (("f64-negate") (Some "f64.neg"))
        (("f64-floor") (Some "f64.floor"))
        (("f64-ceiling") (Some "f64.ceil"))
        (("f64-truncate") (Some "f64.trunc"))
        (("f64-round") (Some "f64.nearest"))
        (("i32->i64") (Some "i64.extend_i32_s"))
        (("i64->i32") (Some "i32.wrap_i64"))
        (("i64->f64") (Some "f64.convert_i64_s"))
        (("f64->i64") (Some "i64.trunc_sat_f64_s"))
        (("i32->f64") (Some "f64.convert_i32_s"))
        (("f64->i32") (Some "i32.trunc_sat_f64_s"))
        (("i32->f32") (Some "f32.convert_i32_s"))
        (("f32->i32") (Some "i32.trunc_sat_f32_s"))
        (("i64->f32") (Some "f32.convert_i64_s"))
        (("f32->i64") (Some "i64.trunc_sat_f32_s"))
        (("f32->f64") (Some "f64.promote_f32"))
        (("f64->f32") (Some "f32.demote_f64"))
        (("f32->bits") (Some "i32.reinterpret_f32"))
        (("bits->f32") (Some "f32.reinterpret_i32"))
        (("f64->bits") (Some "i64.reinterpret_f64"))
        (("bits->f64") (Some "f64.reinterpret_i64"))
        (else (None))))

    (define (index (value Wat)) (→ Wat)
      (wat "i32.wrap_i64" value))

    ;; A primitive operates on operands emitted first, each once.

    (define (emit-primitive (fn Fn) (expr Expr) (name String) (args (List Expr)))
      (→ (List Wat))
      (let ((operation (substring name 5 (string-length name))))
        (match (primitive-instruction operation)
          ((Some instruction) (list (wat* instruction (emit-args fn args))))
          ((None)
           (special-primitive fn
                              operation
                              (emit-args fn args)
                              (map (lambda (record) (● record type)) args)
                              (● expr type)
                              (may-yield? fn expr))))))

    (define (special-primitive (fn Fn)
                               (operation String)
                               (code (List Wat))
                               (types (List Type))
                               (type Type)
                               (yields? Bool))
      (→ (List Wat))
      (let* ((m (● fn module))
             (arg (lambda (n) (list-ref code n)))
             (sequence (lambda (t) (sequence-type m t))))
        (case operation
          (("cache")
           (list (cached-function m type (wat "i64.const" (int 0)) (arg 0) #f)))
          (("lru-cache")
           (list (cached-function m type (arg 0) (arg 1) #t)))
          (("unit") (list (wat "i32.const" (int 0))))
          (("make-prompt") (list (new-prompt m)))
          (("suspend")
           (list (wat* "call" (Cons (id (suspender m (first-type types))) code))))
          (("with-prompt")
           (list (wat* "call"
                       (Cons (id (delimiter-helper m
                                                   (new Delimiter
                                                     (prompt (first-type types))
                                                     (result type))))
                             code))))
          (("unsafe-cast") (list (funcref-closure m type (arg 0))))
          (("panic") (list (wat* "call" (Cons (id (panic-helper m)) code)) (wat "unreachable")))
          (("bool->i32" "char->i32" "i32->char" "u8->i32") code)
          (("i32->u8") (list (wat "i32.and" (arg 0) (wat "i32.const" (int 255)))))
          (("i32->bool") (list (wat "i32.ne" (arg 0) (wat "i32.const" (int 0)))))
          (("string->array" "array->string" "array-copy" "constant-array->array")
           (list (wat "call" (id (copy-helper m (sequence type))) (arg 0))))
          (("string-length" "array-length" "constant-array-length")
           (list (wat "i64.extend_i32_u" (wat "array.len" (arg 0)))))
          (("string-ref")
           (list (wat "array.get" (id (sequence (first-type types))) (arg 0) (index (arg 1)))))
          (("array-ref" "constant-array-ref")
           (list (wat "call"
                      (id (array-read-helper m (sequence-element (first-type types))))
                      (arg 0)
                      (arg 1))))
          (("array-set!")
           (list (wat "call" (id (array-write-helper m (sequence-element (first-type types))))
                      (arg 0) (arg 1) (arg 2))))
          (("array") (list (wat "array.new_fixed" (id (sequence type)) (int 0))))
          (("make-string" "make-array")
           (list (wat "array.new" (id (sequence type)) (arg 1)
                      (wat "call" (id (size-helper m)) (arg 0)))))
          (("string-append" "array-append")
           (list (wat "call" (id (append-helper m (sequence type))) (arg 0) (arg 1))))
          (("substring" "subarray")
           (list (wat "call" (id (sequence-slice-helper m type)) (arg 0) (arg 1) (arg 2))))
          (("array-set")
           (list (wat "call" (id (array-replace-helper m (sequence-element type)))
                      (arg 0) (arg 1) (arg 2))))
          (("array-copy!")
           (list
            (wat "call" (id (array-copy-into-helper m (sequence-element (first-type types))))
                 (arg 0) (arg 1) (arg 2) (arg 3) (arg 4))))
          (("string=?") (list (wat* "call" (Cons (id (string-equal-helper m)) code))))
          (("string-compare") (list (wat* "call" (Cons (id (string-compare-helper m)) code))))
          (("array-generate" "string-generate")
           (list (wat* "call"
                       (Cons (id (generate-helper m (sequence type) (list-ref types 1) yields?))
                             code))))
          (else (panic (string-append "internal error: unknown primitive " operation))))))

    ;; ---- Memoized closures ----

    ;; A wrapper holds its callback and its state.
    ;; State fields: buckets, entry count, capacity (0 = unbounded), MRU, LRU.
    ;; Entry fields: hash, bucket successor, newer, older, result, argument keys.
    (record CacheLayout
      ((signature Type)
       (base String)
       (holder String)
       (entry String)
       (buckets String)
       (state String)))

    (define (cache-layout (m Module) (type Type)) (→ CacheLayout)
      (match type
        ((TFun params result)
         (let* ((key (type-key type)) (base (reference-type (rep m type)))
                (entry (wasm-id (string-append "cache-entry:" key)))
                (state (wasm-id (string-append "cache-state:" key)))
                (buckets (array-type m (Reference entry))))
           (unless (match (known-type m entry) ((Some _) #t) (_ #f))
             (register-type! m entry entry
                             (wat "type" (id entry)
                                  (wat* "struct"
                                        (append
                                         (list (wat "field" (Word "i64"))
                                               (wat "field" (wat "mut" (ref-wat entry)))
                                               (wat "field" (wat "mut" (ref-wat entry)))
                                               (wat "field" (wat "mut" (ref-wat entry)))
                                               (wat "field"
                                                    (wat "mut" (rep->wat (rep m result)))))
                                         (map
                                          (lambda (type) (wat "field" (rep->wat (rep m type))))
                                          params)))))
             (register-type! m state state
                             (wat "type" (id state)
                                  (wat "struct" (wat "field" (wat "mut" (ref-wat buckets)))
                                       (wat "field" (wat "mut" (Word "i64")))
                                       (wat "field" (Word "i64"))
                                       (wat "field" (wat "mut" (ref-wat entry)))
                                       (wat "field" (wat "mut" (ref-wat entry))))))
             (unit))
           (new CacheLayout (signature type) (base base)
                (holder (capture-type m base (list (Reference base) (Reference state))))
                (entry entry) (buckets buckets) (state state))))
        (_ (panic "internal error: cache requires a function"))))

    (define (cache-bindings (layout CacheLayout)) (→ (List (Pair String String)))
      (list (new Pair (first "entry") (second (● layout entry)))
            (new Pair (first "state") (second (● layout state)))
            (new Pair (first "buckets") (second (● layout buckets)))))

    (define (cache-keys (params (List Type))) (→ (List String))
      (map (lambda (index) (string-append "key." (i64->string index))) (iota (length params))))

    (define (cache-key-reads (params (List Type))) (→ (List Wat))
      (map (lambda (name) (wat "local.get" (id (wasm-id name)))) (cache-keys params)))

    (define (cache-key-equal (m Module) (type Type) (left Wat) (right Wat)) (→ Wat)
      (match type
        ((TCon "String" _) (wat "call" (id (string-equal-helper m)) left right))
        (_ (match (rep m type)
             ((Reference _) (cache-reference-equal m type left right))
             ((Scalar "f32")
              (wat "i32.eq" (wat "i32.reinterpret_f32" left) (wat "i32.reinterpret_f32" right)))
             ((Scalar "f64")
              (wat "i64.eq" (wat "i64.reinterpret_f64" left) (wat "i64.reinterpret_f64" right)))
             ((Scalar scalar) (wat (string-append scalar ".eq") left right))))))

    ;; Nullary enum cases are values, even when linked modules construct
    ;; different singleton objects. Payload cases and structs keep identity.
    (define (cache-reference-equal (m Module) (type Type) (left Wat) (right Wat))
      (→ Wat)
      (let ((identity (wat "ref.eq" left right)))
        (match type
          ((TCon name _)
           (match (table-ref (● (program-of m) types) name)
             ((Some data)
              (if (● data enum?)
                  (let* ((base (data-type m type))
                         (tag (wat "struct.get" (id base) (int 0) left))
                         (same (wat "i32.eq" tag (wat "struct.get" (id base) (int 0) right)))
                         (empty (fold-left
                                 (lambda (answer case)
                                   (wat "i32.or" answer
                                        (wat "i32.eq" tag (wat "i32.const" (int (● case tag))))))
                                 (wat "i32.const" (int 0))
                                 (filter (lambda (case) (null? (● case fields))) (● data cases)))))
                    (wat "i32.or" identity (wat "i32.and" same empty)))
                  identity))
             ((None) identity)))
          (_ identity))))

    (define (cache-key-match (m Module) (layout CacheLayout) (params (List Type)))
      (→ Wat)
      (fold-left (lambda (answer pair)
                   (let ((index (● pair first)) (type (● pair second)))
                     (wat "i32.and" answer
                          (cache-key-equal m type
                                           (wat "struct.get" (id (● layout entry)) (int (+ index 5))
                                                (wat "local.get" (Word "$entry")))
                                           (wat "local.get" (id (wasm-id
                                                                 (string-append "key."
                                                                                (i64->string
                                                                                 index)))))))))
                 (wat "i32.const" (int 1)) (zip (iota (length params)) params)))

    ;; Managed references expose equality but no portable address hash. A
    ;; constant component is collision-safe; other tuple components still mix.
    (define (cache-key-hash (m Module) (type Type) (value Wat)) (→ Wat)
      (match type
        ((TCon "String" _) (wat "call" (id (cache-string-hash m)) value))
        (_ (match (rep m type)
             ((Reference _) (wat "i64.const" (int 0)))
             ((Scalar "i64") value)
             ((Scalar "f64") (wat "i64.reinterpret_f64" value))
             ((Scalar "f32") (wat "i64.extend_i32_u" (wat "i32.reinterpret_f32" value)))
             (_ (wat "i64.extend_i32_u" value))))))

    (define (cache-hash (m Module) (params (List Type))) (→ Wat)
      (wat "call" (id (cache-hash-finish m))
           (fold-left (lambda (hash pair)
                        (wat "i64.mul" (wat "i64.xor" hash
                                            (cache-key-hash m (● pair first) (● pair second)))
                             (wat "i64.const" (int 1099511628211))))
                      (wat "i64.const" (int -3750763034362895579))
                      (zip params (cache-key-reads params)))))

    ;; Bucket indices use low bits. Fold high bits down as well, so common
    ;; floating-point values and wide integer keys do not all collide.
    (define (cache-hash-finish (m Module)) (→ String)
      (template-helper! m "cache-hash-finish" ""
                        "(func {id} (param $hash i64) (result i64)
  (local.set $hash (i64.mul
    (i64.xor (local.get $hash) (i64.shr_u (local.get $hash) (i64.const 32)))
    (i64.const -7046029254386353131)))
  (i64.xor (local.get $hash) (i64.shr_u (local.get $hash) (i64.const 32))))" (Nil)))

    (define (cache-string-hash (m Module)) (→ String)
      (template-helper! m "cache-string-hash" ""
                        "(func {id} (param $text (ref null $arr.i32)) (result i64)
  (local $index i32) (local $hash i64)
  (local.set $hash (i64.const -3750763034362895579))
  (loop $hashing
    (if (i32.eq (local.get $index) (array.len (local.get $text)))
      (then (return (local.get $hash))))
    (local.set $hash (i64.mul
      (i64.xor (local.get $hash)
        (i64.extend_i32_u (array.get $arr.i32 (local.get $text) (local.get $index))))
      (i64.const 1099511628211)))
    (local.set $index (i32.add (local.get $index) (i32.const 1)))
    (br $hashing))
  unreachable)" (Nil)))

    (define (cache-touch (m Module) (layout CacheLayout)) (→ String)
      (template-helper! m "cache-touch" (● layout state)
                        "(func {id} (param $state (ref null {state})) (param $entry (ref null {entry}))
  (local $head (ref null {entry})) (local $newer (ref null {entry})) (local $older (ref null {entry}))
  (if (i64.eqz (struct.get {state} 2 (local.get $state))) (then (return)))
  (local.set $head (struct.get {state} 3 (local.get $state)))
  (if (ref.eq (local.get $head) (local.get $entry)) (then (return)))
  (local.set $newer (struct.get {entry} 2 (local.get $entry)))
  (local.set $older (struct.get {entry} 3 (local.get $entry)))
  (struct.set {entry} 3 (local.get $newer) (local.get $older))
  (if (ref.is_null (local.get $older))
    (then (struct.set {state} 4 (local.get $state) (local.get $newer)))
    (else (struct.set {entry} 2 (local.get $older) (local.get $newer))))
  (struct.set {entry} 2 (local.get $entry) (ref.null {entry}))
  (struct.set {entry} 3 (local.get $entry) (local.get $head))
  (struct.set {entry} 2 (local.get $head) (local.get $entry))
  (struct.set {state} 3 (local.get $state) (local.get $entry)))"
                        (cache-bindings layout)))

    (define (cache-lookup (m Module) (layout CacheLayout) (params (List Type)))
      (→ String)
      (helper! m "cache-find" (● layout state)
               (lambda (name)
                 (let* ((entry (● layout entry)) (buckets (● layout buckets))
                        (read (wat "local.get" (Word "$entry")))
                        (array (wat "struct.get" (id (● layout state)) (int 0)
                                    (wat "local.get" (Word "$state")))))
                   (wat* "func"
                         (concatenate
                          (list
                           (list (id name) (wat "param" (Word "$state") (ref-wat (● layout state)))
                                 (wat "param" (Word "$hash") (Word "i64")))
                           (param-wats (cache-keys params)
                                       (map (lambda (type) (rep m type)) params))
                           (list
                            (wat "result" (ref-wat entry))
                            (wat "local" (Word "$entry") (ref-wat entry))
                            (wat "local.set" (Word "$entry")
                                 (wat "array.get" (id buckets) array
                                      (wat "i32.and"
                                           (wat "i32.wrap_i64" (wat "local.get" (Word "$hash")))
                                           (wat "i32.sub"
                                                (wat "array.len" array)
                                                (wat "i32.const" (int 1))))))
                            (wat "loop" (Word "$search")
                                 (wat "if" (wat "ref.is_null" read)
                                      (wat "then" (wat "return" (wat "ref.null" (id entry)))))
                                 (wat "if"
                                      (wat "i32.and"
                                           (wat "i64.eq" (wat "struct.get" (id entry) (int 0) read)
                                                (wat "local.get" (Word "$hash")))
                                           (cache-key-match m layout params))
                                      (wat "then"
                                           (wat "call" (id (cache-touch m layout))
                                                (wat "local.get" (Word "$state")) read)
                                           (wat "return" read)))
                                 (wat "local.set" (Word "$entry")
                                      (wat "struct.get" (id entry) (int 1) read))
                                 (wat "br" (Word "$search")))
                            (wat "unreachable")))))))))

    ;; Resize traverses the recency list, so changing bucket successors never
    ;; loses unvisited entries. The state and new array remain managed roots.
    (define (cache-grow (m Module) (layout CacheLayout)) (→ String)
      (template-helper! m "cache-grow" (● layout state)
                        "(func {id} (param $state (ref null {state}))
  (local $buckets (ref null {buckets})) (local $entry (ref null {entry}))
  (local $size i32) (local $index i32)
  (local.set $size (array.len (struct.get {state} 0 (local.get $state))))
  (if (i32.ge_u (local.get $size) (i32.const 1073741824)) (then (return)))
  (local.set $size (i32.shl (local.get $size) (i32.const 1)))
  (local.set $buckets (array.new_default {buckets} (local.get $size)))
  (local.set $entry (struct.get {state} 3 (local.get $state)))
  (block $done (loop $rehash
    (br_if $done (ref.is_null (local.get $entry)))
    (local.set $index (i32.and (i32.wrap_i64 (struct.get {entry} 0 (local.get $entry)))
                               (i32.sub (local.get $size) (i32.const 1))))
    (struct.set {entry} 1 (local.get $entry)
      (array.get {buckets} (local.get $buckets) (local.get $index)))
    (array.set {buckets} (local.get $buckets) (local.get $index) (local.get $entry))
    (local.set $entry (struct.get {entry} 3 (local.get $entry)))
    (br $rehash)))
  (struct.set {state} 0 (local.get $state) (local.get $buckets)))"
                        (cache-bindings layout)))

    (define (cache-evict (m Module) (layout CacheLayout)) (→ String)
      (template-helper! m "cache-evict" (● layout state)
                        "(func {id} (param $state (ref null {state}))
  (local $buckets (ref null {buckets})) (local $oldest (ref null {entry}))
  (local $entry (ref null {entry})) (local $previous (ref null {entry}))
  (local $newest (ref null {entry})) (local $index i32)
  (local.set $buckets (struct.get {state} 0 (local.get $state)))
  (local.set $oldest (struct.get {state} 4 (local.get $state)))
  (local.set $index (i32.and (i32.wrap_i64 (struct.get {entry} 0 (local.get $oldest)))
                             (i32.sub (array.len (local.get $buckets)) (i32.const 1))))
  (local.set $entry (array.get {buckets} (local.get $buckets) (local.get $index)))
  (block $found (loop $search
    (br_if $found (ref.eq (local.get $entry) (local.get $oldest)))
    (local.set $previous (local.get $entry))
    (local.set $entry (struct.get {entry} 1 (local.get $entry)))
    (br $search)))
  (if (ref.is_null (local.get $previous))
    (then (array.set {buckets} (local.get $buckets) (local.get $index)
            (struct.get {entry} 1 (local.get $oldest))))
    (else (struct.set {entry} 1 (local.get $previous)
            (struct.get {entry} 1 (local.get $oldest)))))
  (local.set $newest (struct.get {entry} 2 (local.get $oldest)))
  (if (ref.is_null (local.get $newest))
    (then (struct.set {state} 3 (local.get $state) (ref.null {entry})))
    (else (struct.set {entry} 3 (local.get $newest) (ref.null {entry}))))
  (struct.set {state} 4 (local.get $state) (local.get $newest))
  (struct.set {state} 1 (local.get $state)
    (i64.sub (struct.get {state} 1 (local.get $state)) (i64.const 1))))"
                        (cache-bindings layout)))

    (define (cache-insert (m Module) (layout CacheLayout)) (→ String)
      (template-helper! m "cache-insert" (● layout state)
                        "(func {id} (param $state (ref null {state})) (param $entry (ref null {entry}))
  (local $buckets (ref null {buckets})) (local $head (ref null {entry})) (local $index i32)
  (local.set $buckets (struct.get {state} 0 (local.get $state)))
  (local.set $index (i32.and (i32.wrap_i64 (struct.get {entry} 0 (local.get $entry)))
                             (i32.sub (array.len (local.get $buckets)) (i32.const 1))))
  (struct.set {entry} 1 (local.get $entry)
    (array.get {buckets} (local.get $buckets) (local.get $index)))
  (array.set {buckets} (local.get $buckets) (local.get $index) (local.get $entry))
  (local.set $head (struct.get {state} 3 (local.get $state)))
  (struct.set {entry} 3 (local.get $entry) (local.get $head))
  (if (ref.is_null (local.get $head))
    (then (struct.set {state} 4 (local.get $state) (local.get $entry)))
    (else (struct.set {entry} 2 (local.get $head) (local.get $entry))))
  (struct.set {state} 3 (local.get $state) (local.get $entry))
  (struct.set {state} 1 (local.get $state)
    (i64.add (struct.get {state} 1 (local.get $state)) (i64.const 1)))
  (if (i32.and (i64.gt_s (struct.get {state} 2 (local.get $state)) (i64.const 0))
               (i64.gt_s (struct.get {state} 1 (local.get $state))
                         (struct.get {state} 2 (local.get $state))))
    (then (call {evict} (local.get $state))))
  (if (i64.gt_u (struct.get {state} 1 (local.get $state))
                 (i64.extend_i32_u (array.len (local.get $buckets))))
    (then (call {grow} (local.get $state)))))"
                        (append (cache-bindings layout)
                                (list (new Pair (first "evict") (second (cache-evict m layout)))
                                      (new Pair
                                        (first "grow")
                                        (second (cache-grow m layout)))))))

    ;; A lookup never stays live across user code: a reentrant call may
    ;; resize or evict. Publish after success, checking again; the last
    ;; successful completion wins, and each call returns its own result.
    (define (cache-find-call (m Module) (layout CacheLayout) (params (List Type)))
      (→ Wat)
      (let ((state (wat "local.get" (Word "$state"))))
        (if (null? params)
            (wat "struct.get" (id (● layout state)) (int 3) state)
            (wat* "call" (append (list (id (cache-lookup m layout params)) state
                                       (wat "local.get" (Word "$hash")))
                                 (cache-key-reads params))))))

    (define (cache-publish (m Module) (layout CacheLayout) (params (List Type)))
      (→ Wat)
      (let* ((entry (● layout entry)) (state (wat "local.get" (Word "$state")))
             (fresh (wat* "struct.new"
                          (append (list (id entry) (wat "local.get" (Word "$hash"))
                                        (wat "ref.null" (id entry)) (wat "ref.null" (id entry))
                                        (wat "ref.null" (id entry))
                                        (wat "local.get" (Word "$result")))
                                  (cache-key-reads params)))))
        (if (null? params)
            (wat "struct.set" (id (● layout state)) (int 3) state fresh)
            (wat "block"
                 (wat "local.set" (Word "$entry") (cache-find-call m layout params))
                 (wat "if" (wat "ref.is_null" (wat "local.get" (Word "$entry")))
                      (wat "then" (wat "call" (id (cache-insert m layout)) state fresh))
                      (wat "else" (wat "struct.set" (id entry) (int 4)
                                       (wat "local.get" (Word "$entry"))
                                       (wat "local.get" (Word "$result")))))))))

    (define (cache-invoke
             (m Module)
             (layout CacheLayout)
             (params (List Type))
             (result Type))
      (→ String)
      (let* ((base (● layout base)) (holder (● layout holder))
             (callback (wat "local.get" (Word "$callback"))))
        (template-helper! m "cache-invoke" (● layout state)
                          "(func {id} (type {code}) (param $closure (ref null {base}))
  {params} (result {result})
  (local $self (ref null {holder})) (local $state (ref null {state}))
  (local $entry (ref null {entry})) (local $callback (ref null {base}))
  (local $result {result}) (local $hash i64)
  (local.set $self (ref.cast (ref null {holder}) (local.get $closure)))
  (local.set $state (struct.get {holder} 2 (local.get $self)))
  (local.set $hash {hash})
  (local.set $entry {find})
  (if (i32.eqz (ref.is_null (local.get $entry)))
    (then (return (struct.get {entry} 4 (local.get $entry)))))
  (local.set $callback (struct.get {holder} 1 (local.get $self)))
  (local.set $result {call})
  {unpublished}
  {publish}
  (local.get $result))"
                          (append (cache-bindings layout)
                                  (list
                                   (new Pair (first "base") (second base))
                                   (new Pair (first "holder") (second holder))
                                   (new Pair (first "code") (second (code-type m base)))
                                   (new Pair
                                     (first "unpublished")
                                     (second (wat->text
                                              (yield-leaves m
                                                            (wat "local.get" (Word "$result"))))))
                                   (new Pair (first "params") (second (string-join (map wat->text
                                                                                        (param-wats
                                                                                         (cache-keys
                                                                                          params)
                                                                                         (map
                                                                                          (lambda (t)
                                                                                            (rep
                                                                                             m
                                                                                             t))
                                                                                          params)))
                                                                                   " ")))
                                   (new Pair
                                     (first "result")
                                     (second (wat->text (rep->wat (rep m result)))))
                                   (new Pair (first "hash")
                                        (second
                                         (wat->text (if (null? params) (wat "i64.const" (int 0))
                                                        (cache-hash m params)))))
                                   (new Pair
                                     (first "find")
                                     (second (wat->text (cache-find-call m layout params))))
                                   (new Pair
                                     (first "call")
                                     (second (wat->text (closure-call-wat m
                                                                          base
                                                                          callback
                                                                          (cache-key-reads params)
                                                                          #f))))
                                   (new Pair
                                     (first "publish")
                                     (second (wat->text (cache-publish m layout params)))))))))

    ;; The map is a captured local, never a module global. A zero-argument
    ;; cache needs only its result slot.
    (define (cache-new (m Module) (layout CacheLayout) (params (List Type)) (result Type))
      (→ Wat)
      (wat "struct.new" (id (● layout holder))
           (code-of m (cache-invoke m layout params result))
           (wat "local.get" (Word "$callback"))
           (wat "struct.new" (id (● layout state))
                (if (null? params) (wat "ref.null" (id (● layout buckets)))
                    (wat "array.new_default" (id (● layout buckets)) (wat "i32.const" (int 8))))
                (wat "i64.const" (int 0)) (wat "local.get" (Word "$capacity"))
                (wat "ref.null" (id (● layout entry))) (wat "ref.null" (id (● layout entry))))))

    (define (cached-function
             (m Module)
             (type Type)
             (capacity Wat)
             (callback Wat)
             (bounded? Bool))
      (→ Wat)
      (match type
        ((TFun params result)
         (let* ((layout (cache-layout m type)) (base (● layout base))
                (helper (template-helper! m (if bounded? "lru-cache" "cache") (● layout state)
                                          "(func {id} (param $capacity i64) (param $callback (ref null {base}))
  (result (ref null {base}))
  {capacity-check}
  {new})"
                                          (list (new Pair (first "base") (second base))
                                                (new Pair (first "new")
                                                     (second (wat->text
                                                              (cache-new
                                                               m
                                                               layout
                                                               params
                                                               result))))
                                                (new Pair (first "capacity-check")
                                                     (second (if bounded?
                                                                 (string-append
                                                                  "(if (i64.lt_s (local.get $capacity) (i64.const 0)) (then "
                                                                  (wat->text
                                                                   (wat "call"
                                                                        (id (panic-helper m))
                                                                        (string-literal m
                                                                                        "lru-cache capacity must be nonnegative")))
                                                                  " unreachable))\n(if (i64.eqz (local.get $capacity)) (then (return (local.get $callback))))")
                                                                 "")))))))
           (wat "call" (id helper) capacity callback)))
        (_ (panic "internal error: cache requires Fn"))))

    ;; ---- Runtime helpers ----

    ;; Helpers are fixed WAT, written once per array type and filled in from
    ;; a template. A new array needs an initial element, so empty results
    ;; come from `array.new_fixed`.

    (define (helper! (m Module) (prefix String) (key String) (make (Fn String → Wat)))
      (→ String)
      (let ((full-key (string-append prefix ":" key)))
        (match (table-ref (● m helpers) full-key)
          ((Some function-id) function-id)
          ((None)
           (let ((function-id (wasm-id (string-append prefix "." key))))
             (put! (● m helpers) full-key function-id)
             (push-function! m function-id (make function-id))
             function-id)))))

    (define (template-helper! (m Module)
                              (prefix String)
                              (key String)
                              (template String)
                              (bindings (List (Pair String String))))
      (→ String)
      (helper! m
               prefix
               key
               (lambda (function-id)
                 (Word
                  (fill template (Cons (new Pair (first "id") (second function-id)) bindings))))))

    (define (append-helper (m Module) (array String)) (→ String)
      (template-helper! m "append" array
                        "(func {id} (param $a (ref null {array})) (param $b (ref null {array})) (result (ref null {array}))
  (local $result (ref null {array})) (local $size i32)
  (local.set $size (call {size} (i64.add (i64.extend_i32_u (array.len (local.get $a))) (i64.extend_i32_u (array.len (local.get $b))))))
  (local.set $result (array.new_default {array} (local.get $size)))
  (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
  (array.copy {array} {array} (local.get $result) (array.len (local.get $a)) (local.get $b) (i32.const 0) (array.len (local.get $b)))
  (local.get $result))" (list (new Pair (first "array") (second array)) (new Pair (first "size") (second (size-helper m))))))

    (define (slice-helper (m Module) (array String)) (→ String)
      (template-helper! m "slice" array
                        "(func {id} (param $a (ref null {array})) (param $start i64) (param $end i64) (result (ref null {array}))
    (local $result (ref null {array})) (local $length i32)
    (local.set $length (i32.wrap_i64 (i64.sub (local.get $end) (local.get $start))))
    (if (i32.eqz (local.get $length)) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} ({get} {array} (local.get $a) (i32.wrap_i64 (local.get $start))) (local.get $length)))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.wrap_i64 (local.get $start))
                (local.get $length))
    (local.get $result))"
                        (list (new Pair (first "array") (second array))
                              (new Pair (first "get") (second (array-get array))))))

    (define (copy-helper (m Module) (array String)) (→ String)
      (template-helper! m "copy" array
                        "(func {id} (param $a (ref null {array})) (result (ref null {array}))
    (local $result (ref null {array}))
    (if (i32.eqz (array.len (local.get $a))) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} ({get} {array} (local.get $a) (i32.const 0)) (array.len (local.get $a))))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
    (local.get $result))"
                        (list (new Pair (first "array") (second array))
                              (new Pair (first "get") (second (array-get array))))))

    (define (set-helper (m Module) (array String) (element Rep)) (→ String)
      (template-helper! m "set" array
                        "(func {id} (param $a (ref null {array})) (param $index i64) (param $value {element}) (result (ref null {array}))
    (local $result (ref null {array}))
    (local.set $result (array.new {array} (local.get $value) (array.len (local.get $a))))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
    (array.set {array} (local.get $result) (i32.wrap_i64 (local.get $index)) (local.get $value))
    (local.get $result))"
                        (list (new Pair (first "array") (second array))
                              (new Pair
                                (first "element")
                                (second (wat->text (rep->wat element)))))))

    ;; The loop is WAT, so no let tests its calls. Where the function it is
    ;; given may yield, the loop tests each call itself: a yield nothing
    ;; resumes leaves with no array, for the caller's test, and one that
    ;; something might resume panics, since the loop could not go on from
    ;; the middle.

    (define (generate-helper
             (m Module)
             (array String)
             (function-type Type)
             (yields? Bool))
      (→ String)
      (let* ((signature (function-signature m function-type))
             (base (closure-type m (● signature first) (● signature second))))
        (template-helper!
         m
         (if yields? "generate-tested" "generate")
         (string-append array " " base)
         "(func {id} (param $count i64) (param $f (ref null {base})) (result (ref null {array}))
    (local $result (ref null {array})) (local $length i32) (local $index i32) (local $element {element})
    (local.set $length (call {size} (local.get $count)))
    (if (i32.eqz (local.get $length)) (then (return (array.new_fixed {array} 0))))
    (local.set $element (call_ref {code} (local.get $f) (i64.const 0) (struct.get {base} 0 (local.get $f))))
    {test}
    (local.set $result (array.new {array} (local.get $element) (local.get $length)))
    (local.set $index (i32.const 1))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (local.get $length)))
        (local.set $element (call_ref {code} (local.get $f) (i64.extend_i32_u (local.get $index)) (struct.get {base} 0 (local.get $f))))
        {test}
        (array.set {array} (local.get $result) (local.get $index) (local.get $element))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    (local.get $result))"
         (list (new Pair (first "size") (second (size-helper m)))
               (new Pair (first "array") (second array))
               (new Pair (first "base") (second base))
               (new Pair (first "code") (second (code-type m base)))
               (new Pair
                 (first "element")
                 (second (wat->text (rep->wat (● signature second)))))
               (new Pair
                 (first "test")
                 (second (if yields? (generate-test m array) "")))))))

    (define (generate-test (m Module) (array String)) (→ String)
      (fill "(if (i32.eqz (ref.is_null (global.get {yielding})))
      (then
        (if (struct.get {yield} 1 (global.get {yielding}))
          (then (call {panic} {message}) (unreachable)))
        (return (ref.null {array}))))"
            (list (new Pair (first "yielding") (second (yielding m)))
                  (new Pair (first "yield") (second (yield-type m)))
                  (new Pair (first "panic") (second (panic-helper m)))
                  (new Pair
                    (first "message")
                    (second (wat->text
                             (string-literal m
                                             "a suspension that may be resumed cannot leave the function an array or string is generated by"))))
                  (new Pair (first "array") (second array)))))

    ;; Strings of different lengths differ without comparing a character,
    ;; and most comparisons in a lookup are between such names.

    (define (string-equal-helper (m Module)) (→ String)
      (let* ((array (array-type m (Scalar "i32"))) (compare (string-compare-helper m)))
        (template-helper! m "string-equal" ""
                          "(func {id} (param $a (ref null {array})) (param $b (ref null {array})) (result i32)
    (if (i32.ne (array.len (local.get $a)) (array.len (local.get $b)))
      (then (return (i32.const 0))))
    (i32.eqz (call {compare} (local.get $a) (local.get $b))))"
                          (list (new Pair (first "array") (second array))
                                (new Pair (first "compare") (second compare))))))

    ;; Lexicographic comparison by Unicode scalar: -1, 0 or 1.

    (define (string-compare-helper (m Module)) (→ String)
      (template-helper! m "string-compare" ""
                        "(func {id} (param $a (ref null {array})) (param $b (ref null {array})) (result i32)
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
                        (list
                         (new Pair (first "array") (second (array-type m (Scalar "i32")))))))

    ;; Strings transfer UTF32 scalars and return their count. Bytes transfer
    ;; a little-endian u32 length followed by packed bytes and return its
    ;; address, so a leaf host import reads memory without reentering Wasm.
    ;; stage reserves four bytes per slot: count+1 safely holds either layout.

    (define (stage-helper (m Module) (bytes? Bool)) (→ String)
      (let ((type (if bytes? (TCon "Array" (list (TCon "U8" (Nil)))) (TCon "String" (Nil))))
            (stage (import! m
                            (new Import (module "snail.core.support") (symbol "snail:io/stage"))
                            (list (Scalar "i32"))
                            (Some (Scalar "i32")))))
        (template-helper! m (if bytes? "stage.bytes" "stage.text") ""
                          "(func {id} (param $value {type}) (result i32)
    (local $address i32) (local $index i32) (local $text (ref null {array})) (local $length i32)
    (local.set $text {data})
    (local.set $length {length})
    {guard}
    (local.set $address (call {stage} {capacity}))
    {header}
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (local.get $length)))
        ({store} (i32.add (i32.add (local.get $address) (i32.const {offset})) (i32.shl (local.get $index) (i32.const {shift})))
                 ({get} {array} (local.get $text) (local.get $index)))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    {result})"
                          (list
                           (new Pair
                             (first "type")
                             (second (wat->text (rep->wat (rep m type)))))
                           (new Pair (first "data") (second "(local.get $value)"))
                           (new Pair (first "length") (second "(array.len (local.get $value))"))
                           (new Pair
                             (first "array")
                             (second (array-type m (Scalar (if bytes? "i8" "i32")))))
                           (new Pair (first "stage") (second stage))
                           (new Pair (first "guard")
                                (second (if bytes?
                                            "(if (i32.eq (local.get $length) (i32.const -1)) (then (unreachable)))"
                                            "")))
                           (new Pair (first "capacity")
                                (second (if bytes?
                                            "(i32.add (local.get $length) (i32.const 1))"
                                            "(local.get $length)")))
                           (new Pair (first "header")
                                (second (if bytes?
                                            "(i32.store (local.get $address) (local.get $length))"
                                            "")))
                           (new Pair (first "store") (second (if bytes? "i32.store8" "i32.store")))
                           (new Pair (first "get") (second (if bytes? "array.get_u" "array.get")))
                           (new Pair (first "offset") (second (if bytes? "4" "0")))
                           (new Pair (first "shift") (second (if bytes? "0" "2")))
                           (new Pair (first "result")
                                (second (if bytes?
                                            "(local.get $address)"
                                            "(local.get $length)")))))))

    ;; Sends the message to the runtime one scalar at a time, then stops.

    (define (panic-helper (m Module)) (→ String)
      (let ((character (import! m
                                (new Import
                                  (module "snail.core.support")
                                  (symbol "snail:panic/character"))
                                (list (Scalar "i32"))
                                (None)))
            (raise (import! m
                            (new Import (module "snail.core.support") (symbol "snail:panic/raise"))
                            (Nil)
                            (None))))
        (template-helper! m "panic" ""
                          "(func {id} (param $message (ref null {array}))
    (local $index i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $message))))
        (call {character} (array.get {array} (local.get $message) (local.get $index)))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    (call {raise})
    (unreachable))"
                          (list
                           (new Pair (first "array") (second (array-type m (Scalar "i32"))))
                           (new Pair (first "character") (second character))
                           (new Pair (first "raise") (second raise))))))

    (define (wat->text (wat Wat)) (→ String)
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

    (define (type-groups (definitions (List Wat))) (→ (List Wat))
      (let* ((named (fold-left (lambda (table definition)
                                 (table-set table (type-definition-name definition) definition))
                               (empty-table) definitions))
             (names (list->array (list-sort string<? (map type-definition-name definitions))))
             (numbers
              (fold-left (lambda (table index) (table-set table (array-ref names index) index))
                         (empty-table)
                         (iota (array-length names)))))
        (map (lambda (component)
               (group-wat named (map (lambda (index) (array-ref names index)) component)))
             (strong-components
              (array-map (lambda (name) (type-edges named numbers name)) names)))))

    (define (type-definition-name (definition Wat)) (→ String)
      (match definition
        ((Node (Cons _ (Cons (Word name) _))) name)
        (_ (panic "internal error: not a type definition"))))

    ;; The numbers of the types a definition refers to, in the order of
    ;; their names: its fields, parameters, results and supertype.

    (define (type-edges (named (Table Wat)) (numbers (Table I64)) (name String)) (→ (List I64))
      (map (lambda (word) (table-number numbers word))
           (list-sort string<? (delete-duplicates string=?
                                                  (filter (lambda (word)
                                                            (and (not (string=? word name))
                                                                 (table-contains? numbers word)))
                                                          (wat-words
                                                           (table-ref-or-wat named name)))))))

    (define (table-number (table (Table I64)) (key String)) (→ I64)
      (match (table-ref table key)
        ((Some number) number)
        ((None) (panic "internal error: unknown type"))))

    (define (table-ref-or-wat (table (Table Wat)) (key String)) (→ Wat)
      (match (table-ref table key)
        ((Some value) value)
        ((None) (panic "internal error: unknown type"))))

    (define (wat-words (wat Wat)) (→ (List String))
      (match wat
        ((Word text) (list text))
        ((Node items) (concatenate (map wat-words items)))))

    (define (group-wat (named (Table Wat)) (group (List String))) (→ Wat)
      (match group
        ((Cons name (Nil)) (table-ref-or-wat named name))
        (_ (wat* "rec"
                 (map (lambda (name) (table-ref-or-wat named name))
                      (list-sort (lambda (a b)
                                   (let ((left (super-depth named a)) (right (super-depth named b)))
                                     (if (= left right) (string<? a b) (< left right)))) group))))))

    ;; Recursive field references may point forward, but supertypes must
    ;; precede their subtypes even inside one recursive group.
    (define (super-depth (named (Table Wat)) (name String)) (→ I64)
      (match (table-ref-or-wat named name)
        ((Node (Cons (Word "type") (Cons _ (Cons (Node (Cons (Word "sub") parts)) (Nil)))))
         (match (find (lambda (part)
                        (match part ((Word name) (table-contains? named name)) (_ #f))) parts)
           ((Some (Word parent)) (+ 1 (super-depth named parent)))
           (_ 0)))
        (_ 0)))

    ;; ---- Modules ----

    ;; The prepared input contains concrete functions,
    ;; explicit host exports and an optional program entry.

    (define (emit-module (prepared Prepared)) (→ Wat)
      (let ((m (new-module (● prepared declarations) (● prepared suspensions))))
        (for-each (lambda (definition)
                    (emit-function! m (● definition name) (● definition value)))
                  (● prepared definitions))
        (for-each (lambda (item) (emit-exposure! m item)) (● prepared exposed))
        (match (● prepared entry) ((Some name) (emit-main! m name)) (_ (unit)))
        (module-wat m)))

    (define (new-module (declarations Declarations) (suspensions Suspensions)) (→ Module)
      (new Module (declarations declarations)
           (suspensions suspensions)
           (type-ids (empty-table))
           (remaining-data-types 65536)
           (types (Nil))
           (imports (Nil))
           (globals (Nil))
           (functions (Nil)) (declared (Nil)) (exports (Nil)) (data (Nil))
           (lambdas (empty-table)) (helpers (empty-table))))

    ;; The entry's start takes the scheduler that main runs on. `main` is
    ;; it as the host calls it; `main:body` is it at its `snail-scheme`
    ;; type, for an engine that links the program to call through a
    ;; Funcref.

    (define (emit-main! (m Module) (start String)) (→ Unit)
      (match (declared-type m start)
        ((Some type)
         (push! (● m exports)
                (wat "export" (wat-string "main")
                     (wat "func" (id (exposed-function m start type)))))
         (push! (● m exports)
                (wat "export" (wat-string "main:body") (wat "func" (id (wasm-id start))))))
        ((None) (panic "internal error: the entry's start has no definition"))))

    ;; The fields in the order Wasm requires: types in their recursion
    ;; groups, then imports, globals, declared function references, exports,
    ;; code and the data segments of byte literals. Every module imports the
    ;; runtime's linear memory, where staged text goes; once linked, the two
    ;; share it.
    ;; Declarations are listed by name, so the text is the same whichever
    ;; order they were emitted in. Only the types constrain their order, and
    ;; `type-groups` settles it.

    (define (module-wat (m Module)) (→ Wat)
      (let ((declared
             (list-sort string<? (delete-duplicates string=? (● m declared)))))
        (wat* "module"
              (concatenate
               (list (type-groups (reverse (● m types)))
                     (Cons (wat "import"
                                (wat-string "snail.core.support")
                                (wat-string "memory")
                                (wat "memory" (int 0)))
                           (sorted-declarations (● m imports)))
                     (sorted-declarations (● m globals))
                     (if (null? declared)
                         (Nil)
                         (list (wat* "elem"
                                     (Cons (Word "declare")
                                           (Cons (Word "func") (map id declared))))))
                     (sorted-declarations (● m exports))
                     (map (lambda (entry) (Word (● entry second)))
                          (sort-named (● m functions)))
                     (sorted-declarations (● m data)))))))

    (define (sorted-declarations (declarations (List Wat))) (→ (List Wat))
      (map (lambda (entry) (● entry second))
           (sort-named (map (lambda (declaration)
                              (new Pair (first (declaration-id declaration)) (second declaration)))
                            declarations))))

    (define (sort-named (entries (List (Pair String A))))
      (→ (List (Pair String A)))
      (∀ (A))
      (list-sort (lambda (a b) (string<? (● a first) (● b first))) entries))

    ;; Host exposures are adapters around ordinary functions.
    (define (emit-exposure! (m Module) (item Item)) (→ Unit)
      (match item
        ((Expose name symbol _)
         (match (declared-type m name)
           ((Some type)
            (push! (● m exports)
                   (wat "export" (wat-string symbol)
                        (wat "func" (id (exposed-function m name type))))))
           ((None) (panic "internal error: an exposed function has no definition"))))
        (_ (panic "internal error: expected a host exposure"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm)
    (import
     (snail stage0 testing))
    (begin
      (define test-wasm
        (lambda () (expect (mangle "a b,c(d)") "a_b~c<d>")
                (expect (fill "(call {f} {x})"
                              (list (new Pair (first "f") (second "$g"))
                                    (new Pair (first "x") (second "1"))))
                        "(call $g 1)")
                (expect (wat->string (wat "module"
                                          (wat "func"
                                               (Word "$f")
                                               (wat "result" (Word "i32"))
                                               (wat "i32.const" (int 1)))))
                        "(module\n  (func $f (result i32)\n    (i32.const 1)))\n")
                (expect (wat->text (wat-string "é\n")) "\"\\c3\\a9\\0a\"")))))
   (else)))
