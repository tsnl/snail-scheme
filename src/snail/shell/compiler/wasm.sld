;; Prepared concrete code to WasmGC. Declarations and initializer bodies are
;; fixed before emission; no source specialization or validation happens here.
;; This backend decides representations:
;; scalars are Wasm numbers, enums whose cases have no fields are i32 tags,
;; other data are GC structs (enum cases are subtypes of a tagged base), a
;; field holding a struct keeps a reference to that object,
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
   emit-control-module
   wat->string)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (only (snail shell compiler specialize)
         Declarations Binding
         control-effects)
   (only (snail shell compiler prepare)
         Prepared Callees declaration-callees yields
         holds-yield-point?))
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
    ;; other fields as trees. `memo` caches closures for global functions, singletons and
    ;; string literals; `helpers` caches imports and helper functions by key.
    ;; `declarations` is fixed metadata: it holds no source bodies, recipes
    ;; or pending work. Only the Wasm output builders change during emission.
    (struct Module
      ((declarations Declarations)
       (type-ids (Table String))
       (remaining-data-types I64)
       (types (List Wat))
       (imports (List Wat))
       (globals (List Wat))
       (functions (List (Pair String String)))
       (declared (List String))
       (exports (List Wat))
       (data (List Wat))
       (memo (Table Wat))
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

    (define (push-function! (m Module) (name String) (function Wat)) (→ Unit) (! mut)
      (push! (● m functions) (Pair name (field->string function))))

    (define (memoize! (m Module) (key String) (make (Fn → Wat ! mut))) (→ Wat) (! mut)
      (match (table-ref (● m memo) key)
        ((Some value) value)
        ((None)
         (let ((value (make)))
           (put! (● m memo) key value)
           value))))

    ;; An import declared once: the first request for `key` declares it
    ;; under `name`, and later ones find that name.

    (define (import-once! (m Module)
                          (key String)
                          (name String)
                          (declaration (Fn String → Wat ! mut)))
      (→ String)
      (! mut)
      (match (table-ref (● m helpers) key)
        ((Some found) found)
        ((None)
         (put! (● m helpers) key name)
         (push! (● m imports) (declaration name))
         name)))

    (define (program-of (m Module)) (→ Program)
      (● (● m declarations) program))

    ;; A location for code the backend writes itself.

    (define no-loc (→ Loc) (Loc "" 0 0))

    ;; ---- Names ----

    ;; Characters outside Wasm's identifier set are replaced.

    (define (mangle (text String)) (→ String)
      (vector->string (vector-map mangle-char (string->vector text))))

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
         (vector-fold (lambda (h c) (fnv-step h (char->integer c)))
                      (fnv-step hash 32)
                      (string->vector text)))
        ((Node items) (fold-left wat-hash (fnv-step hash 40) items))))

    (define (wat=? (a Wat) (b Wat)) (→ Bool)
      (match (Pair a b)
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
    ;; source use or ownership operation may precede the yield test.
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

    ;; A linear value is its payload: linearity is a fact the ownership
    ;; check proves, and nothing at run time keeps it. A FnOnce is the
    ;; closure of its function type, and a fn a reference to code alone.

    (define (rep (m Module) (type Type)) (→ Rep) (! mut)
      (match type
        ((TCon name args)
         (case name
           (("U8" "I32" "Bool" "Char" "Unit") (Scalar "i32"))
           (("I64") (Scalar "i64"))
           (("F32") (Scalar "f32"))
           (("F64") (Scalar "f64"))
           (("String") (Reference (array-type m (Scalar "i32"))))
           (("Any") (Reference (any-type m)))
           (("Rc" "WeakRc") (Reference (rc-type m (first-type args))))
           (("Funcref") (Scalar "funcref"))
           (("Vector") (Reference (sequence-type m (first-type args))))
           (("FnOnce") (rep m (first-type args)))

           (else (if (tag-enum? m name) (Scalar "i32") (Reference (data-type m type))))))
        ((TFun params result _)
         (Reference
          (closure-type m (map (lambda (param) (rep m param)) params) (rep m result))))
        (_ (panic (string-append "internal error: not a ground type: " (type-key type))))))

    (define (first-type (types (List Type))) (→ Type)
      (match types
        ((Cons type _) type)
        ((Nil) (panic "internal error: missing type argument"))))

    ;; Byte arrays are packed; a byte is an i32 everywhere else.

    (define (element-rep (m Module) (type Type)) (→ Rep) (! mut)
      (match type
        ((TCon "U8" (Nil)) (Scalar "i8"))
        (_ (rep m type))))

    (define (array-get (array String)) (→ String)
      (if (string=? array "$arr.i8") "array.get_u" "array.get"))

    (define (register-type! (m Module) (key String) (type String) (definition Wat))
      (→ String)
      (! mut)
      (put! (● m type-ids) key type)
      (push! (● m types) definition)
      type)

    (define (known-type (m Module) (key String)) (→ (Option String))
      (table-ref (● m type-ids) key))

    (define (array-type (m Module) (element Rep)) (→ String) (! mut)
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

    (define (closure-type (m Module) (params (List Rep)) (result Rep)) (→ String) (! mut)
      (let* ((signature
              (string-append (string-join (map rep-key params) ",") "->" (rep-key result)))
             (key (string-append "clo." signature)))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (let ((closure (wasm-id key)) (code (wasm-id (string-append "fn." signature))))
             (put! (● m type-ids) key closure)
             (put! (● m type-ids) (string-append "code:" closure) code)
             (put! (● m type-ids) (string-append "counted:" closure) closure)
             (owner-type m)
             (dropper-type m)
             (register-type! m (string-append "fn." signature) code
                             (wat "type" (id code)
                                  (wat* "func"
                                        (append
                                         (list (wat "param" (ref-wat closure))
                                               (wat "param" (evidence-ref m)))
                                         (append (map (lambda (param)
                                                        (wat "param"
                                                             (rep->wat param)))
                                                      params)
                                                 (list (wat "result"
                                                            (rep->wat result))))))))
             (register-type! m key closure
                             (wat "type" (id closure) (wat "sub" (id (owner-type m))
                                                           (wat* "struct"
                                                                 (closure-fields m closure))))))))))

    ;; Every closure carries, beside its code, a nullable dropper: a thunk
    ;; closure that drops the linear values it captured, which `drop-once`
    ;; runs when a FnOnce is dropped unrun (control.sld, "Droppers"). A
    ;; frame carries one too, for the locals live across its yield point,
    ;; and a `resume` one that runs its frames' (`resume-dropper-code`).
    ;; The thunk's own closure type is registered first, since every
    ;; closure type names it.

    (define (dropper-type (m Module)) (→ String) (! mut)
      (closure-type m (Nil) (Scalar "i32")))

    (define (dropper-ref) (→ Wat)
      (ref-wat "$clo.->i32"))

    (define (dropper-null) (→ Wat)
      (wat "ref.null" (id "$clo.->i32")))

    ;; Every closure subtype shares its base's code type.

    (define (code-type (m Module) (closure String)) (→ String)
      (match (known-type m (string-append "code:" closure))
        ((Some code) code)
        ((None) (panic "internal error: closure without a code type"))))

    (define (function-signature (m Module) (type Type)) (→ (Pair (List Rep) Rep)) (! mut)
      (match (fn-arrow type)
        ((TFun params result _) (Pair (map (lambda (param) (rep m param)) params) (rep m result)))
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

    ;; Every source field occupies one Wasm field. Physical mutability also
    ;; permits replacements to reuse a record whose unique ownership is proved.
    (define (case-fields (m Module) (type Type) (case Case)) (→ (List Wat)) (! mut)
      (map (lambda (type) (wat "field" (wat "mut" (rep->wat (rep m type)))))
           (case-field-types m type case)))

    ;; A linear struct leaves only by being taken apart, dropped or
    ;; replaced, so its reference has one owner, and a replacement, which
    ;; consumes the record, may write the field where it is: no other
    ;; reference could see it change. That holds of a ground type that is
    ;; linear; an unrestricted one, which a generic body checked as linear
    ;; may be specialized at, can be shared, so its replacement copies.

    (define (reused-in-place? (m Module) (type Type)) (→ Bool)
      (match type
        ((TCon name _)
         (and (not (● (data-type-of m name) enum?))
              (linear-type? (program-of m) (Nil) type)))
        (_ #f)))

    (define (type-name (type Type)) (→ String)
      (match type
        ((TCon name _) name)
        (_ (panic "internal error: not a named type"))))

    ;; A struct is one GC struct. An enum is a base struct holding the tag,
    ;; with a final subtype for each case that has fields; a field-less case
    ;; is the base struct itself. The base is registered first because a
    ;; supertype must precede its subtypes.

    (define (data-type (m Module) (type Type)) (→ String) (! mut)
      (require-type-capacity type)
      (let ((key (type-key type)))
        (match (known-type m key)
          ((Some found) found)
          ((None)
           (when (= (● m remaining-data-types) 0)
             (panic "compilation exceeds the limit of 65536 concrete aggregate types"))
           (set! (● m remaining-data-types) (- (● m remaining-data-types) 1))
           (let* ((type-id (wasm-id key)) (data (data-type-of m (type-name type)))
                  (header (data-header m type)))
             (put! (● m type-ids) key type-id)
             (unless (null? header)
               (put! (● m type-ids) (string-append "counted:" type-id) type-id))
             (if (● data enum?)
                 (begin
                   (push! (● m types)
                          (wat "type" (id type-id)
                               (wat* "sub"
                                     (append (if (null? header) (Nil) (list (id (owner-type m))))
                                             (list (wat* "struct"
                                                         (append header
                                                                 (list
                                                                  (wat "field" (Word "i32"))))))))))
                   (for-each (lambda (case) (case-type m type case) (unit))
                             (filter (lambda (case) (not (null? (● case fields)))) (● data cases))))
                 (let* ((case (struct-case m type))
                        (body (wat* "struct" (append header (case-fields m type case)))))
                   (push! (● m types) (wat "type" (id type-id)
                                           (if (null? header)
                                               body
                                               (wat "sub"
                                                    (Word "final")
                                                    (id (owner-type m))
                                                    body))))))
             type-id)))))

    (define (case-type (m Module) (type Type) (case Case)) (→ String) (! mut)
      (let* ((base (data-type m type))
             (key (string-append (type-key type) "." (short-name (● case name)))))
        (match (known-type m key)
          ((Some found) found)
          ((None)
           (let ((case-id (wasm-id key)))
             (register-type! m key case-id
                             (wat "type" (id case-id) (wat "sub" (Word "final") (id base)
                                                           (wat* "struct"
                                                                 (append (data-header m type)
                                                                         (Cons
                                                                          (wat "field" (Word "i32"))
                                                                          (case-fields m
                                                                                       type
                                                                                       case))))))))))))

    ;; A struct has one case, whose declared fields are its complete layout.
    (define (struct-case (m Module) (type Type)) (→ Case)
      (match (● (data-type-of m (type-name type)) cases)
        ((Cons case _) case)
        ((Nil) (panic "internal error: a struct has one case"))))

    ;; ---- Functions ----

    ;; `access` maps each visible local name to the instruction that reads it,
    ;; and `reps` to its representation. A closure's `self` records exact
    ;; aliases of the incoming closure, its code and its ownership layout.
    ;; Fresh function and control-frame contexts inherit none of those facts.
    ;; `exit` is where a yield leaves the code being emitted (see Control).
    (struct FnState
      ((locals (List Wat))
       (access (Table Wat))
       (reps (Table Rep))
       (names I64)))

    (struct Fn
      ((module Module)
       (state FnState)
       (self (Option Self))
       (evidence Wat)
       (exit (Option Exit))))

    (struct Self
      ((names (List String))
       (code String)
       (counted? Bool)))

    ;; Context replacements share this function's output builder while
    ;; changing only immutable control and evidence metadata.
    (define (new-fn (m Module)) (→ Fn)
      (Fn m (FnState (Nil) empty-table empty-table 0)
          (None) (wat "local.get" (Word "$ev")) (None)))

    ;; Temporaries and labels are numbered within their function, so a name
    ;; depends on nothing outside the body it appears in.

    (define (local-id (fn Fn) (prefix String)) (→ String) (! mut)
      (let ((count (+ (● (● fn state) names) 1)))
        (set! (● (● fn state) names) count)
        (wasm-id (string-append prefix "." (i64->string count)))))

    (define (bind-local! (fn Fn) (name String) (read Wat) (rep Rep)) (→ Unit) (! mut)
      (put! (● (● fn state) access) name read)
      (put! (● (● fn state) reps) name rep))

    (define (declare-local! (fn Fn) (name String) (rep Rep)) (→ String) (! mut)
      (let ((local (wasm-id name)))
        (push! (● (● fn state) locals) (wat "local" (id local) (rep->wat rep)))
        (bind-local! fn name (wat "local.get" (id local)) rep)
        local))

    ;; A temporary takes any value type, including a nullable reference.

    (define (declare-temp! (fn Fn) (type Wat)) (→ String) (! mut)
      (let ((local (local-id fn "tmp")))
        (push! (● (● fn state) locals) (wat "local" (id local) type))
        local))

    (define (local-access (fn Fn) (name String)) (→ (Option Wat))
      (table-ref (● (● fn state) access) name))

    (define (local? (fn Fn) (name String)) (→ Bool)
      (table-contains? (● (● fn state) access) name))

    (define (fn-rep (fn Fn) (type Type)) (→ Rep) (! mut)
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

    (define (bind-params! (fn Fn) (params (List String)) (reps (List Rep))) (→ Unit) (! mut)
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

    (define (emit-function! (m Module) (name String) (function Expr)) (→ Unit) (! mut)
      (match (● function term)
        ((Lambda params body )
         (let* ((fn (Fn-exit-set (new-fn m) (function-exit (● function type))))
                (signature (function-signature m (● function type)))
                (reps (● signature first)))
           (bind-params! fn params reps)
           (let ((code (emit fn body #t)))
             (push-function! m (wasm-id name)
                             (function-wat fn
                                           (wasm-id name)
                                           (Cons (evidence-param m) (param-wats params reps))
                                           (● signature second)
                                           code)))))
        (_ (panic "internal error: not a function"))))

    ;; ---- Lazy values ----

    ;; A defining module owns the cache for its lifetime. Initializers are
    ;; ordinary compiled bodies, never startup work. WasmGC values here are
    ;; not shared between threads: the guard detects reentry, not races.
    ;; Cache publication consumes the initializer's result; every read returns
    ;; its own credit. Discarding an instance does not run source finalizers.
    (define (emit-lazy-value! (m Module) (name String) (function Expr)) (→ Unit) (! mut)
      (match (● function term)
        ((Lambda (Nil) body )
         (let* ((fn (Fn-exit-set (new-fn m) (function-exit (● function type))))
                (type (● body type)) (result (rep m type))
                (state (wasm-id (string-append "%lazy.state." name)))
                (value (wasm-id (string-append "%lazy.value." name))))
           (push! (● m globals) (wat "global" (id state) (wat "mut" (Word "i32"))
                                     (wat "i32.const" (int 0))))
           (push! (● m globals) (wat "global" (id value) (wat "mut" (rep->wat result))
                                     (default-value result)))
           (let ((code (lazy-body fn name body state value)))
             (push-function! m (wasm-id name)
                             (function-wat fn
                                           (wasm-id name)
                                           (list (evidence-param m))
                                           result
                                           code)))))
        (_ (panic "internal error: a lazy initializer must take no arguments"))))

    ;; State 1 is installed before entering user code. State 2 proves the
    ;; cached reference is non-null. A fatal trap leaves state 1 in place;
    ;; there is no retry contract. Non-tail emission must publish the result.
    (define (lazy-body (fn Fn) (name String) (body Expr) (state String) (value String))
      (→ (List Wat)) (! mut)
      (let* ((m (● fn module)) (type (● body type)) (result (rep m type))
             (read (wat "global.get" (id value)))
             (code (emit fn body #f)))
        (list
         (wat "if" (wat "i32.eq" (wat "global.get" (id state)) (wat "i32.const" (int 1)))
              (wat "then" (wat "call" (id (panic-helper m))
                               (string-literal m (string-append "initialization cycle: " name)))))
         (wat "if" (wat "i32.eqz" (wat "global.get" (id state)))
              (wat "then"
                   (wat "global.set" (id state) (wat "i32.const" (int 1)))
                   (wat "global.set" (id value)
                        (wat* "block" (Cons (wat "result" (rep->wat result)) code)))
                   (wat "global.set" (id state) (wat "i32.const" (int 2)))))
         (retain-value m type read))))

    ;; ---- Expressions ----

    ;; A list of instructions that leave one value on the stack.

    (define (emit (fn Fn) (expr Expr) (tail? Bool)) (→ (List Wat)) (! mut)
      (let ((type (● expr type)))
        (match (● expr term)
          ((Lit value) (list (literal fn value type)))
          ((Var name _ _) (list (variable fn name type)))
          ((Lambda _ _ ) (list (closure fn expr (None))))
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
          ((BoxAny inner) (list (to-any (● fn module) (● inner type) (emit1 fn inner))))
          ((Downcast inner target) (list (emit-downcast fn inner target (● expr type))))

          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((Ann inner _) (emit fn inner tail?)))))

    ;; One instruction, wrapping a sequence in a block when needed.

    (define (emit1 (fn Fn) (expr Expr)) (→ Wat) (! mut)
      (emit1-tail fn expr #f))

    (define (emit1-tail (fn Fn) (expr Expr) (tail? Bool)) (→ Wat) (! mut)
      (match (emit fn expr tail?)
        ((Cons single (Nil)) single)
        (code (wat* "block" (Cons (wat "result" (rep->wat (fn-rep fn (● expr type)))) code)))))

    (define (emit-args (fn Fn) (args (List Expr))) (→ (List Wat)) (! mut)
      (map (lambda (arg) (emit1 fn arg)) args))

    (define (literal (fn Fn) (value Datum) (type Type)) (→ Wat) (! mut)
      (match value
        ((DBool true?) (wat "i32.const" (int (if true? 1 0))))
        ((DChar c) (wat "i32.const" (int (char->integer c))))
        ((DString text) (string-literal (● fn module) text))
        ((DBytes bytes) (bytes-literal (● fn module) bytes))
        ((DUnit) (wat "i32.const" (int 0)))
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

    (define (string-literal (m Module) (text String)) (→ Wat) (! mut)
      (memoize! m (string-append "string:" text)
                (lambda ()
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
    ;; a fresh mutable vector on every evaluation.

    (define (bytes-literal (m Module) (bytes Bytes)) (→ Wat) (! mut)
      (let ((text (bytes-wat-string bytes)))
        (memoize! m (string-append "bytes:" text)
                  (lambda ()
                    (let ((segment (keyed-id "bytes" text)))
                      (push! (● m data) (wat "data" (id segment) (Word text)))
                      (sequence-owned m (TCon "Vector" (list (TCon "U8" (Nil))))
                                      (wat "array.new_data"
                                           (id (array-type m (Scalar "i8")))
                                           (id segment)
                                           (wat "i32.const" (int 0))
                                           (wat "i32.const" (int (vector-length bytes))))))))))

    ;; Every byte is a two-digit escape, so the text is three characters per
    ;; byte, generated in one pass: images make literals of millions of
    ;; bytes, too many to build from a piece of text per byte.

    (define (bytes-wat-string (bytes Bytes)) (→ String)
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

    (define (hex-char (value I64)) (→ Char)
      (string-ref "0123456789abcdef" value))

    ;; A let whose value may yield tests for the yield before its body. The
    ;; control pass marks such a value with the cleanup of the frame saved
    ;; there (`with-cleanup`), emitted as its cancellation entry.

    (define (emit-let (fn Fn) (name String) (marked Expr) (body Expr) (tail? Bool))
      (→ (List Wat))
      (! mut)
      (match (cleanup-of marked)
        ((Pair value cleanup)
         (let* ((code (if (and (lambda-expr? value) (member? name (expr-references value)))
                          (closure fn value (Some name))
                          (emit-let-value fn value)))
                (local (declare-local! fn name (fn-rep fn (● value type)))))
           (Cons (wat "local.set" (id local) code)
                 (let-rest (bind-self fn name value) name value cleanup body tail?))))))

    ;; A let's value and its unevaluated cancellation code, if any.

    (define (cleanup-of (marked Expr)) (→ (Pair Expr (Option Expr)))
      (match (● marked term)
        ((App callee (Cons value (Cons cleanup (Nil))))
         (match (● callee term)
           ((Var "prim:with-cleanup" _ _) (Pair value (Some cleanup)))
           (_ (Pair marked (None)))))
        (_ (Pair marked (None)))))

    ;; ---- Variables ----

    ;; A global function or operation used as a value becomes a closure.

    (define (variable (fn Fn) (name String) (type Type)) (→ Wat) (! mut)
      (let ((m (● fn module)))
        (match (local-access fn name)
          ((Some access) access)
          ((None)
           (match (definition-of m name)
             ((Some definition)
              (cond

               ((● definition function?) (function-value m name type))
               (else (wat "call" (id (value-id m name type)) (● fn evidence)))))
             ((None)
              (match (program-value (program-of m) name)
                ((Some (Constructor case _))
                 (if (null? (● case fields))
                     (construct fn case type (Nil))
                     (function-value m name type)))
                ((Some _) (function-value m name type))
                ((None) (panic (string-append "internal error: unknown variable " name))))))))))

    ;; Signatures suffice to emit references before or after a body is
    ;; emitted. No definition body lives in the module builder.

    (define (definition-of (m Module) (name String)) (→ (Option Binding))
      (table-ref (● (● m declarations) bindings) name))

    (define (external-definition? (m Module) (name String)) (→ Bool)
      (match (definition-of m name)
        ((Some binding) (● binding external?))
        ((None) #f)))

    (define (function-id (m Module) (name String)) (→ String) (! mut)
      (match (definition-of m name)
        ((Some binding)
         (if (● binding external?)
             (let ((signature (function-signature m (● binding type))))
               (import! m (Import (name-owner name) name)
                        (Cons (evidence-rep m) (● signature first))
                        (Some (● signature second))))
             (wasm-id name)))
        ((None) (wasm-id name))))

    ;; Every importer calls the defining instance's getter, sharing its cache.
    (define (value-id (m Module) (name String) (type Type)) (→ String) (! mut)
      (if (external-definition? m name)
          (import! m (Import (name-owner name) name)
                   (list (evidence-rep m)) (Some (rep m type)))
          (wasm-id name)))

    ;; An immutable global closure whose code calls `name` with its arguments.

    (define (function-value (m Module) (name String) (type Type)) (→ Wat) (! mut)
      (memoize! m (string-append "closure:" name ":" (type-key type))
                (lambda ()
                  (match (fn-arrow type)
                    ((TFun params result _)
                     (let* ((names
                             (map (lambda (index) (string-append "argument." (i64->string index)))
                                  (iota (length params))))
                            (call (Expr (App (Expr (Var name (Nil) (Nil)) type no-loc)
                                             (map (lambda (pair)
                                                    (Expr (Var (● pair first) (Nil) (Nil))
                                                          (● pair second)
                                                          no-loc))
                                                  (zip names params)))
                                        result no-loc)))
                       (closure-value m (Expr (Lambda names call ) type no-loc) (None))))
                    (_ (panic "internal error: a function value needs a function type"))))))

    ;; ---- Closures ----

    ;; A lambda becomes a function taking its closure first. Captured
    ;; variables are copied into the closure and loaded on entry; `self` names
    ;; a recursive local function, which reads as the closure itself. Closures
    ;; without captured locals are immutable globals.

    (define (closure (fn Fn) (function Expr) (self (Option String))) (→ Wat) (! mut)
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

    (define (closure-value (m Module) (function Expr) (self (Option String))) (→ Wat) (! mut)
      (let* ((signature (function-signature m (● function type)))
             (base (closure-type m (● signature first) (● signature second)))
             (code (lambda-function! m function self (Nil) base)))
        (memoize! m (string-append "closure-value:" code)
                  (lambda ()
                    (let ((global (derived-id "closure" code)))
                      (push! (● m globals)
                             (wat "global"
                                  (id global)
                                  (ref-wat base)
                                  (wat "struct.new"
                                       (id base)
                                       (wat "i64.const" (int -1)) (code-of m (owner-noop m))
                                       (wat "ref.func" (id code))
                                       (dropper-null))))
                      (wat "global.get" (id global)))))))

    ;; Only captures with deterministic cleanup need a counted owner. Prepare
    ;; attaches a cancellation dropper only to lambdas with linear captures,
    ;; which keeps every closure that can acquire a dropper counted here.
    (define (closure-with-captures (fn Fn)
                                   (function Expr)
                                   (self (Option String))
                                   (captured (List String)))
      (→ Wat) (! mut)
      (let* ((m (● fn module)) (signature (function-signature m (● function type)))
             (base (closure-type m (● signature first) (● signature second)))
             (reps (map (lambda (name) (capture-rep fn name)) captured))
             (subtype (capture-type m base reps))
             (fields (capture-types function captured))
             (counted? (counted-captures? m fields))
             (code (lambda-function! m function self (zip captured reps) subtype)))
        (wat* "struct.new"
              (Cons (id subtype)
                    (append (list (wat "i64.const" (int (if counted? 1 -1)))
                                  (code-of m (if counted? (capture-destructor m subtype fields)
                                                 (owner-noop m)))
                                  (wat "ref.func" (id code)) (dropper-null))
                            (map (lambda (entry) (retain-value m (● entry second)
                                                               (variable fn
                                                                         (● entry first)
                                                                         unchecked)))
                                 (zip captured fields)))))))

    (define (capture-types (function Expr) (captured (List String))) (→ (List Type))
      (let ((types (expr-reference-types function)))
        (map (lambda (name) (reference-type-of types name)) captured)))

    (define (counted-captures? (m Module) (fields (List Type))) (→ Bool)
      (any? (lambda (type)
              (or (shared-type? (program-of m) type)
                  (linear-type? (program-of m) (Nil) type))) fields))

    ;; The captures extend the base struct with their fields. Closures with
    ;; one base and one list of representations share the subtype.

    (define (capture-type (m Module) (base String) (reps (List Rep))) (→ String) (! mut)
      (let ((name (wasm-id (string-append (substring base 1 (string-length base)) "+"
                                          (string-join (map rep-key reps) ",")))))
        (match (known-type m name)
          ((Some type) type)
          ((None)
           (put! (● m type-ids)
                 (string-append "capture-offset:" name)
                 (if (string=? base "$frame") "3" "4"))
           (register-type! m name name
                           (wat "type" (id name) (wat "sub" (Word "final") (id base)
                                                      (wat* "struct" (append (closure-fields m base)
                                                                             (map (lambda (r)
                                                                                    (wat "field"
                                                                                         (rep->wat
                                                                                          r)))
                                                                                  reps))))))))))

    ;; Source closures own shared captures until their last activation or
    ;; stored alias leaves. A frame transfers one environment into either
    ;; resume or cancellation code; it owns no separate cleanup closure.
    (define (closure-fields (m Module) (base String)) (→ (List Wat)) (! mut)
      (if (string=? base "$frame")
          (list (wat "field" (ref-wat (code-type m base)))
                (wat "field" (ref-wat (code-type m base)))
                (wat "field" (wat "mut" (evidence-ref m))))
          (append (owner-fields)
                  (list (wat "field" (ref-wat (code-type m base)))
                        (wat "field" (wat "mut" (dropper-ref)))))))

    (define (capture-offset (m Module) (type String)) (→ I64)
      (match (known-type m (string-append "capture-offset:" type))
        ((Some "3") 3)
        (_ 4)))

    (define (reference-type-of (types (Table Type)) (name String)) (→ Type)
      (match (table-ref types name)
        ((Some type) type)
        ((None) (panic (string-append "internal error: untyped capture " name)))))

    ;; Once the last child is released this destructor has no work left.
    ;; Tail dispatch keeps lists and chains of counted wrappers off the stack.
    (define (tail-release (call Wat)) (→ Wat)
      (match call
        ((Node (Cons (Word "call") arguments)) (wat* "return_call" arguments))
        (_ (wat "return" call))))

    (define (release-sequence (calls (List Wat))) (→ (List Wat))
      (match calls
        ((Nil) (list (wat "return" (wat "i32.const" (int 0)))))
        ((Cons last (Nil)) (list (tail-release last)))
        ((Cons first rest) (Cons (wat "drop" first) (release-sequence rest)))))

    (define (capture-destructor (m Module) (holder String) (types (List Type))) (→ String) (! mut)
      (helper! m "capture-drop" (string-append holder ":" (string-join (map type-key types) ","))
               (lambda (name)
                 (let ((read
                        (wat "ref.cast"
                             (ref-wat holder)
                             (wat "local.get" (Word "$owner"))))
                       (evidence (wat "local.get" (Word "$ev"))))
                   (wat* "func"
                         (append (list (id name) (wat "type" (Word "$owner.drop"))
                                       (wat "param"
                                            (Word "$owner")
                                            (ref-wat (owner-type m)))
                                       (evidence-param m) (wat "result" (Word "i32"))
                                       (disarm-dropper m holder read evidence))
                                 (release-sequence
                                  (capture-releases m holder types read evidence))))))))

    (define (capture-releases (m Module)
                              (holder String)
                              (types (List Type))
                              (read Wat)
                              (evidence Wat))
      (→ (List Wat)) (! mut)
      (map (lambda (field)
             (release-value m (● field second)
                            (wat "struct.get" (id holder) (int (+ (● field first) 4)) read)
                            evidence))
           (filter (lambda (field) (shared-type? (program-of m) (● field second)))
                   (zip (iota (length types)) types))))

    ;; Moving a dropper out clears its slot before any release can call user
    ;; code. Entering a closure transfers its linear captures into the call,
    ;; so the unused cancellation thunk is released without running its body.
    (define (disarm-dropper (m Module) (holder String) (value Wat) (evidence Wat)) (→ Wat) (! mut)
      (wat "drop"
           (wat "call" (id (disarm-helper m holder)) value evidence)))

    (define (disarm-helper (m Module) (holder String)) (→ String) (! mut)
      (template-helper! m "disarm" holder
                        "(func {id} (param $closure (ref null {holder})) (param $ev (ref null {evidence})) (result i32)
  (local $dropper (ref null {dropper}))
  (local.set $dropper (struct.get {holder} 3 (local.get $closure)))
  (struct.set {holder} 3 (local.get $closure) (ref.null {dropper}))
  (if (i32.eqz (ref.is_null (local.get $dropper)))
    (then (drop (call {release} (local.get $dropper) (local.get $ev)))))
  (i32.const 0))"
                        (list (Pair "holder" holder)
                              (Pair "evidence" (evidence-type m))
                              (Pair "dropper" (dropper-type m))
                              (Pair "release" (release-helper m)))))

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
      (! mut)
      (match (● function term)
        ((Lambda params body )
         (let* ((signature (function-signature m (● function type)))
                (reps (● signature first))
                (base (closure-type m reps (● signature second)))
                (counted? (counted-captures? m
                                             (capture-types function
                                                            (map (lambda (field) (● field first))
                                                                 captured))))
                (fn (Fn-exit-set (lambda-fn m self "$lambda.self" base counted?)
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
                                              (Cons (evidence-param m) (param-wats params reps))))
                                       (● signature second)
                                       (append loads
                                               (if counted?
                                                   (Cons (disarm-dropper m
                                                                         base
                                                                         (wat "local.get"
                                                                              (Word "$closure"))
                                                                         (wat "local.get"
                                                                              (Word "$ev")))
                                                         code)
                                                   code)))))
             (lambda-id m "lambda" draft 0))))
        (_ (panic "internal error: not a lambda"))))

    ;; A lambda, or a join function, is named by the hash of its own text,
    ;; written with its name as a placeholder, so identical lambdas share one
    ;; function and a name depends on nothing but the body. Two different
    ;; lambdas with one hash take the next salt, the one place a name can
    ;; still depend on the order of emission.

    (define (lambda-id (m Module) (prefix String) (draft Wat) (salt I64)) (→ String) (! mut)
      (let* ((hash (i64->string (wat-hash fnv-offset draft)))
             (name (wasm-id (string-append prefix
                                           "."
                                           hash
                                           (if (= salt 0)
                                               ""
                                               (string-append "." (i64->string salt))))))
             (key (string-append "lambda:" name)))
        (match (table-ref (● m memo) key)
          ((Some stored) (if (wat=? stored draft) name (lambda-id m prefix draft (+ salt 1))))
          ((None)
           (put! (● m memo) key draft)
           (push! (● m declared) name)
           (push-function! m name (wat-rename "$lambda.self" name draft))
           name))))

    ;; A recursive lambda reads its own name as its closure.

    (define (lambda-fn (m Module) (self (Option String)) (function-id String) (base String)
                       (counted? Bool))
      (→ Fn)
      (! mut)
      (let* ((names (match self ((Some name) (list name)) ((None) (Nil))))
             (fn (Fn-self-set (new-fn m) (Some (Self names function-id counted?)))))
        (match self
          ((Some name) (bind-local! fn name (wat "local.get" (Word "$closure")) (Reference base)))
          ((None) (unit)))
        fn))

    ;; On entry, each captured variable is copied from the closure to a local.

    (define (capture-loads (fn Fn) (captured (List (Pair String Rep))) (closure String))
      (→ (List Wat))
      (! mut)
      (map-indexed (lambda (index entry)
                     (wat "local.set"
                          (id (declare-local! fn (● entry first) (● entry second)))
                          (wat "struct.get"
                               (id closure)
                               (int (+ index (capture-offset (● fn module) closure)))
                               (wat "ref.cast"
                                    (ref-wat closure)
                                    (wat "local.get" (Word "$closure"))))))
                   captured))

    ;; ---- Code references ----

    (define (code-of (m Module) (function-id String)) (→ Wat) (! mut)
      (push! (● m declared) function-id)
      (wat "ref.func" (id function-id)))

    ;; ---- Calls ----

    (define (call-op (tail? Bool)) (→ String)
      (if tail? "return_call" "call"))

    ;; Resolved locals are immutable. A direct alias or retain keeps the same
    ;; recursive entry point; other expressions establish no such proof. Emit
    ;; the actual callee operand below, preserving its operand evaluation.
    (define (self-target (fn Fn) (callee Expr)) (→ (Option String))
      (match (● callee term)
        ((Var name _ _)
         (match (● fn self)
           ((Some self) (if (member? name (● self names)) (Some (● self code)) (None)))
           ((None) (None))))
        ((App (Expr (Var "prim:current-closure" _ _) _ _) (Nil))
         (match (● fn self)
           ((Some self) (Some (● self code)))
           ((None) (None))))
        ((App operation (Cons value (Nil)))
         (match (● operation term)
           ((Var "prim:retain" _ _) (self-target fn value))
           (_ (None))))
        (_ (None))))

    ;; The alias belongs only to this let's body. Fresh function and control
    ;; frame contexts start with no inherited proof about their caller.
    (define (bind-self (fn Fn) (name String) (value Expr)) (→ Fn)
      (match (Pair (● fn self) (self-target fn value))
        ((Pair (Some self) (Some _))
         (Fn-self-set fn (Some (Self-names-set self (Cons name (● self names))))))
        (_ fn)))

    ;; Only exact aliases qualify, not other closures with the same code.
    ;; The layout cannot acquire a cancellation dropper without linear captures.
    (define (uncounted-self? (fn Fn) (value Expr)) (→ Bool)
      (match (Pair (● fn self) (self-target fn value))
        ((Pair (Some self) (Some _)) (not (● self counted?)))
        (_ #f)))

    (define (emit-call (fn Fn) (expr Expr) (callee Expr) (args (List Expr)) (tail? Bool))
      (→ (List Wat)) (! mut)
      (match (self-target fn callee)
        ((Some function-id)
         (list (wat* (call-op tail?)
                     (Cons (id function-id)
                           (Cons (emit1 fn callee) (Cons (● fn evidence) (emit-args fn args)))))))
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
      (! mut)
      (if (local? fn name)
          (closure-call fn callee args tail?)
          (match (definition-of (● fn module) name)
            ((Some definition)
             (if (● definition function?)
                 (list (wat* (call-op tail?)
                             (Cons (id (function-id (● fn module) name))
                                   (Cons (● fn evidence) (emit-args fn args)))))
                 (closure-call fn callee args tail?)))
            ((None) (builtin-call fn expr name args)))))

    (define (builtin-call (fn Fn) (expr Expr) (name String) (args (List Expr)))
      (→ (List Wat))
      (! mut)
      (let ((m (● fn module)))
        (match (program-value (program-of m) name)
          ((Some (Constructor case _))
           (list (construct fn case (● expr type) args)))
          ((Some (Accessor case index _)) (list (field-access fn case index (first-arg args))))
          ((Some (Replacer case index _))
           (list (replace-field fn case index (first-arg args) (list-ref args 1))))
          ((Some (Setter case index _))
           (append (set-field fn case index (first-arg args) (list-ref args 1))
                   (list (wat "i32.const" (int 0)))))
          ((Some (Swapper case index _))
           (list (swap-field fn case index (first-arg args) (list-ref args 1))))
          ((Some (Primitive _)) (emit-primitive fn name args (● expr type)))
          ((Some (Operation effect _))
           (list (wat* "call"
                       (Cons (id (performer m effect name))
                             (Cons (● fn evidence) (emit-args fn args))))))
          ((Some (Foreign import scheme))
           (host-call m import (● scheme type) (emit-args fn args) (● expr loc)))
          (_ (panic (string-append "internal error: cannot call " name))))))

    (define (first-arg (args (List Expr))) (→ Expr)
      (match args
        ((Cons arg _) arg)
        ((Nil) (panic "internal error: missing argument"))))

    ;; The callee is evaluated once, into a temporary unless it is already a
    ;; variable read. Calling a FnOnce calls the closure it is; the
    ;; ownership check has proved nothing calls it again.

    (define (closure-call (fn Fn) (callee Expr) (args (List Expr)) (tail? Bool))
      (→ (List Wat))
      (! mut)
      (let* ((m (● fn module))
             (signature (function-signature m (procedure-type (● callee type))))
             (base (closure-type m (● signature first) (● signature second)))
             (value (emit1 fn callee)))
        (if (variable-read? value)
            (list (closure-call-wat m base value (Cons (● fn evidence) (emit-args fn args)) tail?))
            (let ((temp (declare-temp! fn (rep->wat (Reference base)))))
              (list (wat "local.set" (id temp) value)
                    (closure-call-wat m
                                      base
                                      (wat "local.get" (id temp))
                                      (Cons (● fn evidence) (emit-args fn args))
                                      tail?))))))

    (define (procedure-type (type Type)) (→ Type)
      (fn-arrow type))

    ;; The arguments begin with the evidence.

    (define (closure-call-wat (m Module) (base String) (read Wat) (args (List Wat)) (tail? Bool))
      (→ Wat)

      (wat* (if tail? "return_call_ref" "call_ref")
            (Cons (id (code-type m base))
                  (Cons read (append args (list (wat "struct.get" (id base) (int 2) read)))))))

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
             (match (definition-of (● fn module) name)
               ((Some _) (None))
               ((None) (program-value (program-of (● fn module)) name)))))
        (_ (None))))

    ;; Arguments become fields in source order. Nested records stay references.
    (define (construct (fn Fn) (case Case) (type Type) (args (List Expr))) (→ Wat) (! mut)
      (construct-slots fn case type (map (lambda (arg) (emit1 fn arg)) args)))

    ;; Tag enums are i32 constants; field-less cases of other enums are shared
    ;; immutable globals of the base type, so constructing them allocates
    ;; nothing. `slots` contains one value per declared field.

    (define (construct-slots (fn Fn) (case Case) (type Type) (slots (List Wat))) (→ Wat) (! mut)
      (let* ((m (● fn module)) (name (● case type)))
        (cond ((tag-enum? m name) (wat "i32.const" (int (● case tag))))
              ((not (● (data-type-of m name) enum?))
               (wat* "struct.new"
                     (Cons (id (data-type m type)) (append (data-owner m type #f) slots))))
              ((null? slots) (singleton m type case))
              (else (wat* "struct.new" (Cons (id (case-type m type case))
                                             (append (data-owner m type #f)
                                                     (Cons (wat "i32.const" (int (● case tag)))
                                                           slots))))))))

    (define (singleton (m Module) (type Type) (case Case)) (→ Wat) (! mut)
      (let ((key (string-append (type-key type) ":" (● case name))))
        (memoize! m (string-append "singleton:" key)
                  (lambda ()
                    (let ((global (keyed-id "value" key)) (base (data-type m type)))
                      (push! (● m globals)
                             (wat "global" (id global) (ref-wat base)
                                  (wat* "struct.new" (Cons (id base) (append (data-owner m type #t)
                                                                             (list (wat "i32.const"
                                                                                        (int (● case
                                                                                                tag)))))))))
                      (wat "global.get" (id global)))))))

    ;; ---- Counted owners ----

    ;; WasmGC owns storage. This header owns deterministic cleanup: positive
    ;; counts are live, zero is dead, and -1 marks an immortal code constant.
    ;; The last release marks an owner dead before entering user cleanup.
    ;; Shared mutable records own their current fields once, independently
    ;; of how many aliases the record itself has. Linear records keep their
    ;; existing single-owner representation and are consumed by Drop glue.
    (define (data-offset (m Module) (type Type)) (→ I64) (! mut)
      (let ((key (string-append "shared:" (type-key type))))
        (match (known-type m key)
          ((Some value) (if (string=? value "yes") 2 0))
          ((None)
           (let ((answer (shared-type? (program-of m) type)))
             (put! (● m type-ids) key (if answer "yes" "no"))
             (if answer 2 0))))))

    (define (data-header (m Module) (type Type)) (→ (List Wat)) (! mut)
      (if (= (data-offset m type) 0) (Nil) (begin (owner-type m) (owner-fields))))

    (define (owner-noop (m Module)) (→ String) (! mut)
      (owner-type m)
      (helper! m "owner-noop" ""
               (lambda (name)
                 (wat "func" (id name) (wat "type" (Word "$owner.drop"))
                      (wat "param" (ref-wat (owner-type m)))
                      (wat "param" (evidence-ref m))
                      (wat "result" (Word "i32")) (wat "i32.const" (int 0))))))

    (define (data-owner (m Module) (type Type) (immortal? Bool)) (→ (List Wat)) (! mut)
      (if (= (data-offset m type) 0) (Nil)
          (list (wat "i64.const" (int (if immortal? -1 1)))
                (code-of m (if immortal? (owner-noop m) (data-destructor m type))))))

    (define (data-destructor (m Module) (type Type)) (→ String) (! mut)
      (let ((data (data-type-of m (type-name type))) (holder (data-type m type)))
        (helper! m "record-drop" holder
                 (lambda (name)
                   (let ((read (wat "ref.cast"
                                    (ref-wat holder)
                                    (wat "local.get" (Word "$owner")))))
                     (wat* "func"
                           (append (list (id name) (wat "type" (Word "$owner.drop"))
                                         (wat "param"
                                              (Word "$owner")
                                              (ref-wat (owner-type m)))
                                         (evidence-param m) (wat "result" (Word "i32")))
                                   (append
                                    (concatenate
                                     (map (lambda (case)
                                            (let ((drops (release-case m type case read)))
                                              (if (or (not (● data enum?)) (null? drops)) drops
                                                  (list (wat "if"
                                                             (wat "i32.eq"
                                                                  (wat "struct.get"
                                                                       (id holder)
                                                                       (int 2)
                                                                       read)
                                                                  (wat "i32.const"
                                                                       (int (● case tag))))
                                                             (wat* "then" drops))))))
                                          (● data cases)))
                                    (list (wat "i32.const" (int 0)))))))))))

    (define (release-case (m Module) (type Type) (case Case) (record Wat)) (→ (List Wat)) (! mut)
      (let* ((enum? (● (data-type-of m (type-name type)) enum?))
             (holder (if enum? (case-type m type case) (data-type m type)))
             (read (if enum? (wat "ref.cast" (ref-wat holder) record) record))
             (offset (+ (data-offset m type) (if enum? 1 0)))
             (fields (filter (lambda (field) (shared-type? (program-of m) (● field second)))
                             (zip (iota (length (● case fields))) (case-field-types m type case)))))
        (release-sequence
         (map (lambda (field)
                (release-value m (● field second)
                               (wat "struct.get" (id holder) (int (+ offset (● field first))) read)
                               (wat "local.get" (Word "$ev")))) fields))))

    (define (owner-type (m Module)) (→ String) (! mut)
      (match (known-type m "owner")
        ((Some type) type)
        ((None)
         (put! (● m type-ids) "owner" "$owner")
         (register-type! m "owner.drop" "$owner.drop"
                         (wat "type" (Word "$owner.drop")
                              (wat "func" (wat "param" (ref-wat "$owner"))
                                   (wat "param" (evidence-ref m)) (wat "result" (Word "i32")))))
         (register-type! m "owner" "$owner"
                         (wat "type" (Word "$owner")
                              (wat "sub" (wat* "struct" (owner-fields))))))))

    (define (owner-fields) (→ (List Wat))
      (list (wat "field" (wat "mut" (Word "i64")))
            (wat "field" (ref-wat "$owner.drop"))))

    (define (retain-helper (m Module)) (→ String) (! mut)
      (owner-type m)
      (template-helper! m "retain" ""
                        "(func {id} (param $owner (ref null $owner)) (result (ref null $owner))
  (local $count i64)
  (local.set $count (struct.get $owner 0 (local.get $owner)))
  (if (i64.ne (local.get $count) (i64.const -1))
    (then
      (if (i32.or (i64.le_s (local.get $count) (i64.const 0))
                  (i64.eq (local.get $count) (i64.const 9223372036854775807))) (then unreachable))
      (struct.set $owner 0 (local.get $owner) (i64.add (local.get $count) (i64.const 1)))))
  (local.get $owner))" (Nil)))

    (define (release-helper (m Module)) (→ String) (! mut)
      (owner-type m)
      (template-helper! m "release" ""
                        "(func {id} (param $owner (ref null $owner)) (param $ev (ref null {evidence})) (result i32)
  (local $count i64)
  (local.set $count (struct.get $owner 0 (local.get $owner)))
  (if (i64.ne (local.get $count) (i64.const -1))
    (then
      (if (i64.le_s (local.get $count) (i64.const 0)) (then unreachable))
      (local.set $count (i64.sub (local.get $count) (i64.const 1)))
      (struct.set $owner 0 (local.get $owner) (local.get $count))
      (if (i64.eqz (local.get $count))
        (then (return_call_ref $owner.drop (local.get $owner) (local.get $ev)
                (struct.get $owner 1 (local.get $owner)))))))
  (i32.const 0))" (list (Pair "evidence" (evidence-type m)))))

    ;; Rc and WeakRc share a GC control cell. A weak reference contributes
    ;; no strong count. Clearing the payload makes a dead weak cell harmless
    ;; even when it remains reachable after its resource has been finalized.
    (define (rc-type (m Module) (payload Type)) (→ String) (! mut)
      (let ((key (string-append "rc." (type-key payload))))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (let ((name (wasm-id key)))
             (owner-type m)
             (put! (● m type-ids) key name)
             (put! (● m type-ids) (string-append "counted:" name) name)
             (register-type! m key name
                             (wat "type" (id name)
                                  (wat "sub" (Word "final") (id (owner-type m))
                                       (wat* "struct"
                                             (append (owner-fields)
                                                     (list (wat "field"
                                                                (wat "mut"
                                                                     (rep->wat (rep m payload))))
                                                           (wat "field"
                                                                (ref-wat (rc-finalizer-type m
                                                                                            payload))))))))))))))

    (define (rc-finalizer-type (m Module) (payload Type)) (→ String) (! mut)
      (closure-type m (list (rep m payload)) (Scalar "i32")))

    (define (rc-payload (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (wat "struct.get" (id (rc-type m (first-type (type-args type)))) (int 2) value))

    (define (type-args (type Type)) (→ (List Type))
      (match type ((TCon _ args) args) (_ (panic "internal error: expected a named type"))))

    (define (rc-destructor (m Module) (payload Type)) (→ String) (! mut)
      (let* ((holder (rc-type m payload)) (finalizer (rc-finalizer-type m payload))
             (read (wat "local.get" (Word "$cell"))))
        (helper! m "rc-drop" holder
                 (lambda (name)
                   (wat "func" (id name) (wat "type" (Word "$owner.drop"))
                        (wat "param" (Word "$owner") (ref-wat (owner-type m)))
                        (evidence-param m) (wat "result" (Word "i32"))
                        (wat "local" (Word "$cell") (ref-wat holder))
                        (wat "local" (Word "$value") (rep->wat (rep m payload)))
                        (wat "local" (Word "$finalizer") (ref-wat finalizer))
                        (wat "local.set" (Word "$cell")
                             (wat "ref.cast"
                                  (ref-wat holder)
                                  (wat "local.get" (Word "$owner"))))
                        (wat "local.set"
                             (Word "$value")
                             (wat "struct.get" (id holder) (int 2) read))
                        (wat "struct.set" (id holder) (int 2) read (default-value (rep m payload)))
                        (wat "local.set"
                             (Word "$finalizer")
                             (wat "struct.get" (id holder) (int 3) read))
                        (closure-call-wat m finalizer (wat "local.get" (Word "$finalizer"))
                                          (list (wat "local.get" (Word "$ev"))
                                                (wat "local.get" (Word "$value"))) #t))))))

    (define (new-rc (m Module) (type Type) (payload Wat) (finalizer Wat)) (→ Wat) (! mut)
      (let ((content (first-type (type-args type))))
        (wat "struct.new" (id (rc-type m content))
             (wat "i64.const" (int 1)) (code-of m (rc-destructor m content)) payload finalizer)))

    (define (counted-value? (m Module) (type Type)) (→ Bool) (! mut)
      (and (shared-type? (program-of m) type)
           (match (rep m type)
             ((Reference name)
              (match (known-type m (string-append "counted:" name)) ((Some _) #t) ((None) #f)))
             (_ #f))))

    (define (retain-value (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (if (counted-value? m type)
          (wat "ref.cast" (rep->wat (rep m type)) (wat "call" (id (retain-helper m)) value)) value))

    (define (release-value (m Module) (type Type) (value Wat) (evidence Wat)) (→ Wat) (! mut)
      (if (counted-value? m type) (wat "call" (id (release-helper m)) value evidence)
          (discard-value value)))

    (define (discard-value (value Wat)) (→ Wat)
      (wat "block" (wat "result" (Word "i32")) (wat "drop" value) (wat "i32.const" (int 0))))

    (define (upgrade-weak (fn Fn) (type Type) (value Wat)) (→ Wat) (! mut)
      (let* ((m (● fn module)) (strong (first-type (type-args type)))
             (temp (declare-temp! fn (rep->wat (rep m strong))))
             (read (wat "local.get" (id temp))))
        (wat "block" (wat "result" (rep->wat (rep m type)))
             (wat "local.set" (id temp) value)
             (wat "if" (wat "result" (rep->wat (rep m type)))
                  (wat "i64.gt_s" (wat "struct.get" (id (owner-type m)) (int 0) read)
                       (wat "i64.const" (int 0)))
                  (wat "then" (construct-slots fn (option-case m #t) type
                                               (list (retain-value m strong read))))
                  (wat "else" (construct-slots fn (option-case m #f) type (Nil)))))))

    ;; Rc automatically projects into its stable payload. Following another
    ;; ordinary field is still a separate source-level read and ownership
    ;; operation; these helpers only remove Rc control cells from the path.
    (define (record-type (type Type)) (→ Type)
      (match type ((TCon "Rc" (Cons content (Nil))) (record-type content)) (_ type)))

    (define (record-value (fn Fn) (value Expr)) (→ Wat) (! mut)
      (record-through (● fn module) (● value type) (emit1 fn value)))

    (define (record-through (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (match type
        ((TCon "Rc" (Cons content (Nil))) (record-through m content (rc-payload m type value)))
        (_ value)))

    ;; ---- Vectors ----

    ;; A vector's array has its exact, permanent length. Uncounted elements
    ;; need no wrapper; counted elements add an owner header and one fixed
    ;; array reference. Each initialized slot owns its element credit.
    ;; Strings remain separate values; conversions copy their character data.
    (define (sequence-element (type Type)) (→ Type)
      (match type
        ((TCon "String" _) (TCon "Char" (Nil)))
        ((TCon _ (Cons element (Nil))) element)
        (_ (panic "internal error: not a sequence"))))

    (define (sequence-raw-type (m Module) (type Type)) (→ String) (! mut)
      (array-type m (element-rep m (sequence-element type))))

    (define (sequence-type (m Module) (element Type)) (→ String) (! mut)
      (let ((array (array-type m (element-rep m element)))
            (key (string-append "vector." (type-key element))))
        (if (not (shared-type? (program-of m) element)) array
            (match (known-type m key)
              ((Some type) type)
              ((None)
               (let ((name (wasm-id key)))
                 (owner-type m)
                 (put! (● m type-ids) (string-append "counted:" name) name)
                 (register-type! m key name
                                 (wat "type" (id name)
                                      (wat "sub" (Word "final") (id (owner-type m))
                                           (wat* "struct" (append (owner-fields)
                                                                  (list (wat "field"
                                                                             (ref-wat
                                                                              array))))))))))))))

    (define (sequence-data (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (let ((element (sequence-element type)))
        (if (shared-type? (program-of m) element)
            (wat "struct.get" (id (sequence-type m element)) (int 2) value)
            value)))

    (define (sequence-length (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (wat "array.len" (sequence-data m type value)))

    (define (sequence-owned (m Module) (type Type) (data Wat)) (→ Wat) (! mut)
      (let ((element (sequence-element type)))
        (if (shared-type? (program-of m) element)
            (wat "struct.new" (id (sequence-type m element))
                 (wat "i64.const" (int 1)) (code-of m (sequence-destructor m element)) data)
            data)))

    (define (sequence-copied (m Module) (type Type) (data Wat)) (→ Wat) (! mut)
      (let ((element (sequence-element type)))
        (sequence-owned m type
                        (if (shared-type? (program-of m) element)
                            (wat "call" (id (array-retain-helper m element)) data) data))))

    ;; Every accessible slot is initialized, including reference elements.
    (define (array-read (m Module) (element Type) (data Wat) (index Wat)) (→ Wat) (! mut)
      (let ((array (array-type m (element-rep m element))))
        (wat (array-get array) (id array) data index)))

    ;; These loops are typed by the element, not merely its Wasm layout:
    ;; WeakRc and Rc have the same representation but different ownership.
    (define (array-retain-helper (m Module) (element Type)) (→ String) (! mut)
      (let ((array (array-type m (element-rep m element))))
        (template-helper! m "array-retain" (type-key element)
                          "(func {id} (param $array (ref null {array})) (result (ref null {array}))
  (local $index i32)
  (block $done (loop $next
    (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $array))))
    (drop (call {retain} (array.get {array} (local.get $array) (local.get $index))))
    (local.set $index (i32.add (local.get $index) (i32.const 1))) (br $next)))
  (local.get $array))"
                          (list (Pair "array" array) (Pair "retain" (retain-helper m))))))

    (define (array-release-helper (m Module) (element Type)) (→ String) (! mut)
      (let ((array (array-type m (element-rep m element))))
        (template-helper! m "array-release" (type-key element)
                          "(func {id} (param $array (ref null {array})) (param $ev (ref null {evidence})) (result i32)
  (local $index i32)
  (block $done (loop $next
    (br_if $done (i32.ge_u (local.get $index) (array.len (local.get $array))))
    (if (i32.eq (i32.add (local.get $index) (i32.const 1)) (array.len (local.get $array)))
      (then (return_call {release} (array.get {array} (local.get $array) (local.get $index)) (local.get $ev))))
    (drop (call {release} (array.get {array} (local.get $array) (local.get $index)) (local.get $ev)))
    (local.set $index (i32.add (local.get $index) (i32.const 1))) (br $next)))
  (i32.const 0))"
                          (list (Pair "array" array)
                                (Pair "evidence" (evidence-type m))
                                (Pair "release" (release-helper m))))))

    (define (sequence-destructor (m Module) (element Type)) (→ String) (! mut)
      (let ((holder (sequence-type m element)))
        (helper! m "vector-drop" (type-key element)
                 (lambda (name)
                   (let ((value (wat "ref.cast" (ref-wat holder)
                                     (wat "local.get" (Word "$owner")))))
                     (wat "func" (id name) (wat "type" (Word "$owner.drop"))
                          (wat "param" (Word "$owner") (ref-wat (owner-type m)))
                          (evidence-param m) (wat "result" (Word "i32"))
                          (wat "return_call" (id (array-release-helper m element))
                               (wat "struct.get" (id holder) (int 2) value)
                               (wat "local.get" (Word "$ev")))))))))

    (define (array-write-helper (m Module) (element Type)) (→ String) (! mut)
      (template-helper! m "array-write" (type-key element)
                        "(func {id} (param $array (ref null {array})) (param $index i32) (param $value {element}) (param $ev (ref null {evidence})) (result i32)
  (local $old {element})
  (local.set $old (array.get {array} (local.get $array) (local.get $index)))
  (array.set {array} (local.get $array) (local.get $index) (local.get $value))
  (return_call {release} (local.get $old) (local.get $ev)))"
                        (list (Pair "array" (array-type m (element-rep m element)))
                              (Pair "element" (wat->text (rep->wat (rep m element))))
                              (Pair "evidence" (evidence-type m))
                              (Pair "release" (release-helper m)))))

    ;; Copying owns all unchanged elements; the replacement argument moves
    ;; into its selected slot. The original array remains an independent owner.
    (define (array-replace-helper (m Module) (element Type)) (→ String) (! mut)
      (let ((array (array-type m (element-rep m element))))
        (template-helper! m "array-replace" (type-key element)
                          "(func {id} (param $array (ref null {array})) (param $index i64) (param $value {element}) (param $ev (ref null {evidence})) (result (ref null {array}))
  (local $result (ref null {array}))
  (local.set $result (call {retain} (call {copy} (local.get $array))))
  (drop (call {write} (local.get $result) (i32.wrap_i64 (local.get $index)) (local.get $value) (local.get $ev)))
  (local.get $result))"
                          (list (Pair "array" array)
                                (Pair "element" (wat->text (rep->wat (rep m element))))
                                (Pair "evidence" (evidence-type m))
                                (Pair "retain" (array-retain-helper m element))
                                (Pair "copy" (copy-helper m array))
                                (Pair "write" (array-write-helper m element))))))

    ;; Snapshot both ranges before writing. Incoming owners are retained,
    ;; the entire destination is installed, and only then do old elements
    ;; release. Overlap and reentrant finalizers therefore see a completed copy.
    (define (array-copy-owners-helper (m Module) (element Type)) (→ String) (! mut)
      (let ((array (array-type m (element-rep m element))))
        (template-helper! m "array-copy-owners" (type-key element)
                          "(func {id} (param $to (ref null {array})) (param $at i64) (param $from (ref null {array})) (param $start i64) (param $count i64) (param $ev (ref null {evidence})) (result i32)
  (local $incoming (ref null {array})) (local $old (ref null {array}))
  (local.set $incoming (call {slice} (local.get $from) (local.get $start) (i64.add (local.get $start) (local.get $count))))
  (local.set $old (call {slice} (local.get $to) (local.get $at) (i64.add (local.get $at) (local.get $count))))
  (drop (call {retain} (local.get $incoming)))
  (array.copy {array} {array} (local.get $to) (i32.wrap_i64 (local.get $at)) (local.get $incoming) (i32.const 0) (i32.wrap_i64 (local.get $count)))
  (return_call {release} (local.get $old) (local.get $ev)))"
                          (list (Pair "array" array) (Pair "slice" (slice-helper m array))
                                (Pair "evidence" (evidence-type m))
                                (Pair "retain" (array-retain-helper m element))
                                (Pair "release" (array-release-helper m element))))))

    ;; Validate full-width indices
    ;; before narrowing to Wasm's i32 indices, including zero-length copies.
    (define (range-helper (m Module)) (→ String) (! mut)
      (template-helper! m "range" ""
                        "(func {id} (param $length i32) (param $start i64) (param $count i64) (result i32)
  (if (i64.gt_u (local.get $start) (i64.extend_i32_u (local.get $length))) (then unreachable))
  (if (i64.gt_u (local.get $count) (i64.sub (i64.extend_i32_u (local.get $length)) (local.get $start))) (then unreachable))
  (i32.wrap_i64 (local.get $start)))" (Nil)))

    (define (size-helper (m Module)) (→ String) (! mut)
      (template-helper! m "size" ""
                        "(func {id} (param $length i64) (result i32)
  (if (i64.gt_u (local.get $length) (i64.const 2147483647)) (then unreachable))
  (i32.wrap_i64 (local.get $length)))" (Nil)))

    (define (vector-storage-bindings (m Module) (element Type))
      (→ (List (Pair String String))) (! mut)
      (list (Pair "holder" (sequence-type m element))
            (Pair "array" (array-type m (element-rep m element)))
            (Pair "data" (wat->text (sequence-data m (TCon "Vector" (list element))
                                                   (wat "local.get" (Word "$vector")))))
            (Pair "element" (wat->text (rep->wat (rep m element))))
            (Pair "read" (wat->text (array-read m element (wat "local.get" (Word "$data"))
                                                (wat "local.get" (Word "$index")))))))

    (define (vector-read-helper (m Module) (element Type)) (→ String) (! mut)
      (template-helper! m "vector-read" (type-key element)
                        "(func {id} (param $vector (ref null {holder})) (param $at i64) (result {element})
  (local $data (ref null {array})) (local $index i32)
  (local.set $data {data})
  (local.set $index (call {range} (array.len (local.get $data)) (local.get $at) (i64.const 1)))
  {read})"
                        (Cons (Pair "range" (range-helper m)) (vector-storage-bindings m element))))

    (define (vector-write-helper (m Module) (element Type)) (→ String) (! mut)
      (let ((write (if (shared-type? (program-of m) element)
                       (string-append "(return_call " (array-write-helper m element)
                                      " (local.get $data) (local.get $index) (local.get $value) (local.get $ev))")
                       "(array.set {array} (local.get $data) (local.get $index) (local.get $value)) (i32.const 0)")))
        (template-helper! m "vector-write" (type-key element)
                          (string-append
                           "(func {id} (param $vector (ref null {holder})) (param $at i64) (param $value {element}) (param $ev (ref null {evidence})) (result i32)
  (local $data (ref null {array})) (local $index i32)
  (local.set $data {data})
  (local.set $index (call {range} (array.len (local.get $data)) (local.get $at) (i64.const 1)))
  " write ")")
                          (append (list (Pair "range" (range-helper m))
                                        (Pair "evidence" (evidence-type m)))
                                  (vector-storage-bindings m element)))))

    (define (sequence-slice-helper (m Module) (type Type)) (→ String) (! mut)
      (helper! m "sequence-slice" (type-key type)
               (lambda (name)
                 (let ((value (wat "local.get" (Word "$value")))
                       (start (wat "local.get" (Word "$start")))
                       (end (wat "local.get" (Word "$end"))))
                   (wat "func" (id name) (wat "param" (Word "$value") (rep->wat (rep m type)))
                        (wat "param" (Word "$start") (Word "i64"))
                        (wat "param" (Word "$end") (Word "i64"))
                        (wat "result" (rep->wat (rep m type)))
                        (wat "drop" (wat "call" (id (range-helper m)) (sequence-length m type value)
                                         start (wat "i64.sub" end start)))
                        (sequence-copied m
                                         type
                                         (wat "call"
                                              (id (slice-helper m (sequence-raw-type m type)))
                                              (sequence-data m type value) start end)))))))

    (define (sequence-append-helper (m Module) (type Type)) (→ String) (! mut)
      (helper! m "sequence-append" (type-key type)
               (lambda (name)
                 (let ((left (wat "local.get" (Word "$left")))
                       (right (wat "local.get" (Word "$right"))))
                   (wat "func" (id name) (wat "param" (Word "$left") (rep->wat (rep m type)))
                        (wat "param" (Word "$right") (rep->wat (rep m type)))
                        (wat "result" (rep->wat (rep m type)))
                        (sequence-copied m
                                         type
                                         (wat "call"
                                              (id (append-helper m (sequence-raw-type m type)))
                                              (sequence-data m type left)
                                              (sequence-data m type right))))))))

    (define (vector-copy-helper (m Module) (element Type)) (→ String) (! mut)
      (let* ((type (TCon "Vector" (list element))) (holder (sequence-type m element)))
        (helper! m "vector-copy" (type-key element)
                 (lambda (name)
                   (let ((value (wat "local.get" (Word "$value"))))
                     (wat "func"
                          (id name)
                          (wat "param" (Word "$value") (ref-wat holder))
                          (wat "result" (ref-wat holder))
                          (wat "return_call" (id (sequence-slice-helper m type)) value
                               (wat "i64.const" (int 0))
                               (wat "i64.extend_i32_u" (sequence-length m type value)))))))))

    (define (vector-replace-helper (m Module) (element Type)) (→ String) (! mut)
      (let* ((type (TCon "Vector" (list element))) (array (sequence-raw-type m type))
             (counted? (shared-type? (program-of m) element)))
        (helper! m "vector-replace" (type-key element)
                 (lambda (name)
                   (let ((value (wat "local.get" (Word "$vector")))
                         (index (wat "local.get" (Word "$index"))))
                     (wat "func" (id name) (wat "param" (Word "$vector") (rep->wat (rep m type)))
                          (wat "param" (Word "$index") (Word "i64"))
                          (wat "param" (Word "$value") (rep->wat (rep m element)))
                          (evidence-param m) (wat "result" (rep->wat (rep m type)))
                          (wat "drop"
                               (wat "call" (id (range-helper m)) (sequence-length m type value)
                                    index (wat "i64.const" (int 1))))
                          (sequence-owned m type
                                          (wat* "call"
                                                (append (list (id (if counted?
                                                                      (array-replace-helper m
                                                                                            element)
                                                                      (set-helper m
                                                                                  array
                                                                                  (rep m element))))
                                                              (sequence-data m type value)
                                                              index
                                                              (wat "local.get" (Word "$value")))
                                                        (if counted?
                                                            (list (wat "local.get" (Word "$ev")))
                                                            (Nil)))))))))))

    (define (vector-copy-into-helper (m Module) (element Type)) (→ String) (! mut)
      (let ((copy (if (shared-type? (program-of m) element)
                      (string-append "(return_call " (array-copy-owners-helper m element)
                                     " (local.get $to-data) (local.get $at) (local.get $from-data) (local.get $start) (local.get $count) (local.get $ev))")
                      "(array.copy {array} {array} (local.get $to-data) (i32.wrap_i64 (local.get $at)) (local.get $from-data) (i32.wrap_i64 (local.get $start)) (i32.wrap_i64 (local.get $count))) (i32.const 0)")))
        (template-helper! m "vector-copy-into" (type-key element)
                          (string-append
                           "(func {id} (param $to (ref null {holder})) (param $at i64) (param $from (ref null {holder})) (param $start i64) (param $count i64) (param $ev (ref null {evidence})) (result i32)
  (local $to-data (ref null {array})) (local $from-data (ref null {array}))
  (local.set $to-data {to-data})
  (local.set $from-data {from-data})
  (drop (call {range} (array.len (local.get $to-data)) (local.get $at) (local.get $count)))
  (drop (call {range} (array.len (local.get $from-data)) (local.get $start) (local.get $count)))
  " copy ")")
                          (append (list (Pair "range" (range-helper m))
                                        (Pair "evidence" (evidence-type m))
                                        (Pair "to-data"
                                              (wat->text
                                               (sequence-data m (TCon "Vector" (list element))
                                                              (wat "local.get" (Word "$to")))))
                                        (Pair "from-data"
                                              (wat->text
                                               (sequence-data m (TCon "Vector" (list element))
                                                              (wat "local.get" (Word "$from"))))))
                                  (vector-storage-bindings m element)))))

    ;; ---- Fields ----

    ;; A projection follows one reference and reads one declared field. Enum
    ;; accessors first establish the case subtype, whose fields follow its tag.
    (define (field-access (fn Fn) (case Case) (index I64) (value Expr)) (→ Wat) (! mut)
      (let* ((m (● fn module)) (type (record-type (● value type))))
        (wat "struct.get" (id (field-holder m type case)) (int (+ index (field-offset m type)))
             (field-record fn case value))))

    (define (field-holder (m Module) (type Type) (case Case)) (→ String) (! mut)
      (if (● (data-type-of m (● case type)) enum?) (case-type m type case) (data-type m type)))

    (define (field-offset (m Module) (type Type)) (→ I64) (! mut)
      (+ (data-offset m type) (if (● (data-type-of m (type-name type)) enum?) 1 0)))

    (define (field-record (fn Fn) (case Case) (record Expr)) (→ Wat) (! mut)
      (let* ((m (● fn module)) (type (record-type (● record type))))
        (case-record m type case (record-value fn record))))

    ;; Enum reads here are introduced by ownership lowering inside a
    ;; matched clause. Its tag test already proved the nominal case, even
    ;; when two case layouts share the same structural Wasm subtype.
    (define (case-record (m Module) (type Type) (case Case) (record Wat)) (→ Wat) (! mut)
      (wat "ref.cast" (ref-wat (field-holder m type case)) record))

    ;; Wasm evaluates the receiver before the incoming value, each once.
    (define (set-field (fn Fn) (case Case) (index I64) (record Expr) (content Expr))
      (→ (List Wat)) (! mut)
      (list (wat "drop" (release-value (● fn module) (● content type)
                                       (swap-field fn case index record content)
                                       (● fn evidence)))))

    (define (swap-field (fn Fn) (case Case) (index I64) (record Expr) (content Expr))
      (→ Wat) (! mut)
      (let* ((m (● fn module)) (type (record-type (● record type))))
        (wat "call" (id (swap-helper m type case (+ index (field-offset m type))
                                     (rep m (● content type))))
             (record-value fn record) (emit1 fn content))))

    ;; Checking has resolved a place to an actual mutable field. The target
    ;; expression may itself follow any number of ordinary object references.
    (struct FieldTarget
      ((case Case)
       (index I64)
       (record Expr)))

    (define (place-field (fn Fn) (place Expr)) (→ FieldTarget) (! mut)
      (match (● place term)
        ((Ann inner _) (place-field fn inner))
        ((App callee (Cons record (Nil)))
         (match (builtin-of fn callee)
           ((Some (Accessor case index _)) (FieldTarget case index record))
           (_ (panic "internal error: a place reads a field"))))
        (_ (panic "internal error: a place reads a field"))))

    (define (place-write (fn Fn) (place Expr) (value Expr)) (→ (List Wat)) (! mut)
      (let ((target (place-field fn place)))
        (set-field fn (● target case) (● target index) (● target record) value)))

    (define (place-swap (fn Fn) (place Expr) (value Expr)) (→ Wat) (! mut)
      (let ((target (place-field fn place)))
        (swap-field fn (● target case) (● target index) (● target record) value)))

    ;; Swaps a mutable field's content for a new value and answers the old
    ;; one, which stays on the operand stack while the new one is stored.
    ;; The case check is inside the helper, after both call operands run.
    ;; The content moves without a copy, so the caller is its only owner,
    ;; and a mutable field may hold a linear value.

    (define (swap-helper (m Module) (record-type Type) (case Case) (index I64) (content Rep))
      (→ String) (! mut)
      (let ((type (rep->wat content)) (base (data-type m record-type))
            (holder (field-holder m record-type case)))
        (helper! m "swap" (string-append holder "." (i64->string index))
                 (lambda (function-id)
                   (wat "func" (id function-id)
                        (wat "param" (Word "$record") (ref-wat base))
                        (wat "param" (Word "$value") type)
                        (wat "result" type)
                        (wat "local" (Word "$case") (ref-wat holder))
                        (wat "local.set" (Word "$case")
                             (case-record m record-type case (wat "local.get" (Word "$record"))))
                        (wat "struct.get" (id holder) (int index) (wat "local.get" (Word "$case")))
                        (wat "struct.set" (id holder) (int index)
                             (wat "local.get" (Word "$case"))
                             (wat "local.get" (Word "$value"))))))))

    ;; A pure replacement consumes its record. Its established uniqueness
    ;; permits reuse; otherwise the new object shares unchanged field values.
    ;; Evaluate both operands before reading the remaining fields.
    (define (replace-field (fn Fn) (case Case) (index I64) (value Expr) (replacement Expr))
      (→ Wat) (! mut)
      (let* ((m (● fn module)) (type (● value type)) (holder (data-type m type))
             (owner (declare-temp! fn (rep->wat (Reference holder))))
             (incoming (declare-temp! fn (rep->wat (rep m (● replacement type)))))
             (record (wat "local.get" (id owner))) (content (wat "local.get" (id incoming)))
             (offset (data-offset m type)))
        (wat* "block"
              (append (list (wat "result" (ref-wat holder))
                            (wat "local.set" (id owner) (emit1 fn value))
                            (wat "local.set" (id incoming) (emit1 fn replacement)))
                      (if (reused-in-place? m type)
                          (list (wat "drop" (release-value m (● replacement type)
                                                           (wat "call"
                                                                (id (swap-helper m
                                                                                 type case
                                                                                 (+ index offset)
                                                                                 (rep m
                                                                                      (● replacement
                                                                                         type))))
                                                                record content) (● fn evidence)))
                                record)
                          (list (construct-slots fn case type
                                                 (map-indexed (lambda (i field)
                                                                (if (= i index) content
                                                                    (retain-value m
                                                                                  field
                                                                                  (wat "struct.get"
                                                                                       (id holder)
                                                                                       (int (+ i
                                                                                               offset))
                                                                                       record))))
                                                              (case-field-types m type case)))))))))

    ;; ---- Host calls ----

    ;; The runtime reads only scalars. A String or Bytes argument, which must come
    ;; last, is copied into the runtime's staging buffer just before the call,
    ;; and the host receives its scalar count or byte-record address.
    ;; A Unit result is no result.

    (define (host-call (m Module) (import Import) (type Type) (args (List Wat)) (loc Loc))
      (→ (List Wat))
      (! mut)
      (match type
        ((TFun params result _)
         (let* ((function-id (import-wat! m
                                          import
                                          (map nonnull (host-params m params loc))
                                          (if (unit-type? type)
                                              (None)
                                              (Some (nonnull (rep m result))))))
                (call (wat* "call" (Cons (id function-id) (host-args m params args)))))
           (if (unit-type? type) (list call (wat "i32.const" (int 0))) (list call))))
        (_ (panic "internal error: a host function needs a function type"))))

    (define (host-params (m Module) (params (List Type)) (loc Loc)) (→ (List Rep)) (! mut)
      (map-indexed (lambda (index param)
                     (cond ((not (buffer-type? param)) (rep m param))
                           ((= index (- (length params) 1)) (Scalar "i32"))
                           (else
                            (panic
                             "internal error: a host function's buffer is not its last argument"))))
                   params))

    (define (host-args (m Module) (params (List Type)) (args (List Wat))) (→ (List Wat)) (! mut)
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
        ((TFun _ (TCon "Unit" (Nil)) _) #t)
        (_ #f)))

    ;; A function the module imports from the host or another module.

    (define (import! (m Module) (import Import) (params (List Rep)) (result (Option Rep)))
      (→ String)
      (! mut)
      (import-wat! m import (map rep->wat params)
                   (match result ((Some r) (Some (rep->wat r))) ((None) (None)))))

    (define (import-wat! (m Module) (import Import) (params (List Wat)) (result (Option Wat)))
      (→ String)
      (! mut)
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

    ;; Each host argument is observed: the entry acquires an owner for the
    ;; source call, leaving the host's owner intact. Results transfer an owner
    ;; to the host. Its creator's :release-result export consumes that owner;
    ;; the host keeps the value and creator alive until release finishes.
    ;; Option Any crosses as a nullable Any, not as its enum wrapper.

    (define (exposed-value-type (m Module) (type Type)) (→ Wat) (! mut)
      (if (optional-any-type? type) (rep->wat (Reference (any-type m))) (nonnull (rep m type))))

    (define (option-case (m Module) (some? Bool)) (→ Case)
      (match (find (lambda (case) (= (length (● case fields)) (if some? 1 0)))
                   (● (data-type-of m "snail.core.base:Option") cases))
        ((Some case) case)
        ((None) (panic "internal error: missing Option case"))))

    (define (import-handover (fn Fn) (type Type) (value Wat)) (→ Wat) (! mut)
      (let ((m (● fn module)))
        (if (optional-any-type? type)
            (wat "if" (wat "result" (rep->wat (rep m type))) (wat "ref.is_null" value)
                 (wat "then" (construct-slots fn (option-case m #f) type (Nil)))
                 (wat "else"
                      (construct-slots fn (option-case m #t) type
                                       (list (retain-value m (TCon "Any" (Nil))
                                                           (wat "ref.as_non_null" value))))))
            (retain-value m type value))))

    (define (export-handover (fn Fn) (type Type) (value Wat)) (→ Wat) (! mut)
      (if (optional-any-type? type)
          (export-option fn type value)
          (match (fn-rep fn type)
            ((Reference _) (wat "ref.as_non_null" value))
            (_ value))))

    (define (export-option (fn Fn) (type Type) (value Wat)) (→ Wat) (! mut)
      (let* ((m (● fn module)) (temp (declare-temp! fn (rep->wat (rep m type))))
             (answer (declare-temp! fn (exposed-value-type m type)))
             (read (wat "local.get" (id temp))) (some (case-type m type (option-case m #t))))
        (wat "block" (wat "result" (exposed-value-type m type))
             (wat "local.set" (id temp) value)
             (wat "local.set" (id answer)
                  (wat "if" (wat "result" (exposed-value-type m type))
                       (wat "i32.eq"
                            (wat "struct.get"
                                 (id (data-type m type))
                                 (int (data-offset m type))
                                 read)
                            (wat "i32.const" (int (● (option-case m #f) tag))))
                       (wat "then" (wat "ref.null" (id (any-type m))))
                       (wat "else"
                            (retain-value m (TCon "Any" (Nil))
                                          (wat "struct.get"
                                               (id some)
                                               (int (+ 1 (data-offset m type)))
                                               (wat "ref.cast"
                                                    (ref-wat some)
                                                    read))))))
             (wat "drop" (release-value m type read (evidence-none m)))
             (wat "local.get" (id answer)))))

    ;; A release entry consumes its argument without the ordinary entry's
    ;; retain. Mark a host ownership record consumed before calling it, even
    ;; if disposal reenters the host or traps. A trap is terminal, not unwind.
    (define (export-result-release! (m Module) (name String) (symbol String) (type Type))
      (→ Unit) (! mut)
      (match (fn-arrow type)
        ((TFun _ result _)
         (when (counted-value? m result)
           (let ((wrapper (wasm-id (string-append "release-result." name))))
             (push-function! m wrapper
                             (wat "func" (id wrapper)
                                  (wat "param" (id "$result") (exposed-value-type m result))
                                  (wat "drop" (release-handover m result
                                                                (wat "local.get" (id "$result"))))))
             (push! (● m exports)
                    (wat "export" (wat-string (string-append symbol ":release-result"))
                         (wat "func" (id wrapper)))))))
        (_ (panic "internal error: an exposed value has a function type"))))

    (define (release-handover (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (if (optional-any-type? type)
          (wat "if" (wat "result" (Word "i32")) (wat "ref.is_null" value)
               (wat "then" (wat "i32.const" (int 0)))
               (wat "else" (release-value m (TCon "Any" (Nil)) (wat "ref.as_non_null" value)
                                          (evidence-none m))))
          (release-value m type value (evidence-none m))))

    (define (exposed-function (m Module) (name String) (type Type)) (→ String) (! mut)
      (match (fn-arrow type)
        ((TFun params result _) (handover-wrapper! m name params result))
        (_ (panic "internal error: exposed value is not a function"))))

    (define (handover-wrapper! (m Module) (name String) (params (List Type)) (result Type))
      (→ String)
      (! mut)
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
                                     (wat* "call"
                                           (Cons (id (function-id m name))
                                                 (Cons (evidence-none m) args))))))
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
                                                     value)))))))
        wrapper))

    ;; A Unit result is no result, as a foreign import's is (`import!`), so
    ;; a module that imports an exposed function of another, as one the
    ;; engine serves, finds the type it declared.

    (define (wrapper-result (m Module) (result Type)) (→ (List Wat)) (! mut)
      (if (unit-result? result) (Nil) (list (wat "result" (exposed-value-type m result)))))

    (define (unit-result? (type Type)) (→ Bool)
      (match type
        ((TCon "Unit" (Nil)) #t)
        (_ #f)))

    ;; A host entry starts with no yield in flight. In a checked program
    ;; nothing between a yield's record and its catch traps, but for a stack
    ;; overflow in the call that saves the first frame, and the task loop
    ;; goes on after a trap (host/browser/tasks.mjs's `drive`), so a record
    ;; left set would unwind the next task. A program without control
    ;; effects has no record.

    (define (entry-clears (m Module)) (→ (List Wat)) (! mut)
      (match (module-callees m)
        ((Some _) (list (wat "global.set" (id (yielding m)) (wat "ref.null" (id (yield-type m))))))
        ((None) (Nil))))

    ;; ---- Pattern matching ----

    ;; Clauses are tried in order. Each clause is a block that its failing
    ;; tests branch out of; a matching clause branches to `done` with its value.

    (define (emit-match (fn Fn) (expr Expr) (scrutinee Expr) (clauses (List Clause)) (tail? Bool))
      (→ (List Wat))
      (! mut)
      (let* ((value (declare-temp! fn (rep->wat (fn-rep fn (● scrutinee type)))))
             (done (local-id fn "match"))
             (scrutinee-code (emit1 fn scrutinee)))
        (list (wat "local.set" (id value) scrutinee-code)
              (wat* "block"
                    (Cons (id done)
                          (Cons (wat "result" (rep->wat (fn-rep fn (● expr type))))
                                (append
                                 (map (lambda (clause) (clause-block fn clause value done tail?))
                                      clauses)
                                 (list (wat "unreachable")))))))))

    ;; The pattern declares the locals its body reads.

    (define (clause-block (fn Fn) (clause Clause) (value String) (done String) (tail? Bool))
      (→ Wat)
      (! mut)
      (let* ((next (local-id fn "clause"))
             (pattern (● clause pattern))
             (tests (pattern-code fn pattern (wat "local.get" (id value)) next))
             (body (emit1-tail fn (● clause body) tail?)))
        (wat* "block" (Cons (id next) (append tests (list (wat "br" (id done) body)))))))

    (define (pattern-code (fn Fn) (pattern Pattern) (value Wat) (fail String))
      (→ (List Wat))
      (! mut)
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
      (! mut)
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
      (! mut)
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
               (fields-code fn (data-type m type) (data-offset m type) case type args value fail))
              (else
               ;; A case's own type is registered only when its fields are
               ;; read, so a field-less case never declares one.
               (let ((base (data-type m type)))
                 (Cons (wat "br_if"
                            (id fail)
                            (wat "i32.ne"
                                 (wat "struct.get" (id base) (int (data-offset m type)) value)
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
                                   (fields-code fn case-id (+ 1 (data-offset m type)) case type args
                                                (wat "local.get" (id cast)) fail))))))))))

    (define (wild? (pattern Pattern)) (→ Bool)
      (match pattern
        ((PWild _) #t)
        (_ #f)))

    ;; Patterns read each selected field once. A nested pattern follows the
    ;; reference in that field; no enclosing object layout is involved.
    (define (fields-code (fn Fn) (holder String) (offset I64) (case Case)
                         (type Type) (args (List Pattern)) (value Wat) (fail String))
      (→ (List Wat)) (! mut)
      (let ((types (case-field-types (● fn module) type case)))
        (concatenate
         (map-indexed (lambda (index arg)
                        (if (wild? arg) (Nil)
                            (slot-pattern-code fn
                                               (wat "struct.get" (id holder)
                                                    (int (+ offset index)) value)
                                               (list-ref types index) arg fail)))
                      args))))

    (define (slot-pattern-code (fn Fn) (field Wat) (type Type) (arg Pattern) (fail String))
      (→ (List Wat))
      (! mut)
      (match arg
        ((PVar _ _) (pattern-code fn arg field fail))
        (_ (let ((temp (declare-temp! fn (rep->wat (fn-rep fn type)))))
             (Cons (wat "local.set" (id temp) field)
                   (pattern-code fn arg (wat "local.get" (id temp)) fail))))))

    ;; ---- Dynamic values ----

    ;; An Any is the TypeId of its value's ground type with the value itself;
    ;; a scalar is boxed so every payload is a reference.

    (define (any-type (m Module)) (→ String) (! mut)
      (match (known-type m "any")
        ((Some type) type)
        ((None)
         (owner-type m)
         (put! (● m type-ids) "counted:$any" "$any")
         (register-type! m "any" "$any"
                         (wat "type" (Word "$any") (wat "sub" (Word "final") (id (owner-type m))
                                                        (wat* "struct" (append (owner-fields)
                                                                               (list (wat "field"
                                                                                          (Word
                                                                                           "i32"))
                                                                                     (wat "field"
                                                                                          (Word
                                                                                           "anyref")))))))))))

    (define (box-type (m Module) (r Rep)) (→ String) (! mut)
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

    ;; Any owns its payload credit. Downcast consumes one Any credit on
    ;; either branch and retains the recovered payload into Some. The type
    ;; test proves both nominal identity and representation before reading.
    ;; TypeIds omit effects; the checker rejects payloads that could erase
    ;; a function's effects or hide effectful disposal.

    (define (emit-downcast (fn Fn) (inner Expr) (target Type) (result Type)) (→ Wat) (! mut)
      (let* ((m (● fn module)) (temp (declare-temp! fn (ref-wat (any-type m))))
             (read (wat "local.get" (id temp))))
        (wat "block" (wat "result" (rep->wat (rep m result)))
             (wat "local.set" (id temp) (emit1 fn inner))
             (wat "if" (wat "result" (rep->wat (rep m result)))
                  (any-holds? fn read target)
                  (wat "then" (construct-slots fn (option-case m #t) result
                                               (list (from-any fn target read))))
                  (wat "else"
                       (wat "drop" (release-value m (● inner type) read (● fn evidence)))
                       (construct-slots fn (option-case m #f) result (Nil)))))))

    (define (to-any (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (let ((r (rep m type)) (shared? (shared-type? (program-of m) type)))
        (wat "struct.new" (id (any-type m))
             (wat "i64.const" (int (if shared? 1 -1)))
             (code-of m (if shared? (any-destructor m type) (owner-noop m)))
             (wat "i32.const" (int (any-type-id (program-of m) type)))
             (match r
               ((Scalar _) (wat "struct.new" (id (held-type m r)) value))
               ((Reference _) value)))))

    (define (from-any (fn Fn) (type Type) (value Wat)) (→ Wat) (! mut)
      (let* ((m (● fn module)) (r (fn-rep fn type))
             (owner (declare-temp! fn (ref-wat (any-type m))))
             (result (declare-temp! fn (rep->wat r)))
             (held (wat "ref.cast" (ref-wat (held-type m r))
                        (wat "struct.get" (id (any-type m)) (int 3) (wat "local.get" (id owner)))))
             (read (match r ((Scalar _) (wat "struct.get" (id (held-type m r)) (int 0) held))
                          ((Reference _) held))))
        (wat "block" (wat "result" (rep->wat r))
             (wat "local.set" (id owner) value)
             (wat "local.set" (id result) (retain-value m type read))
             (wat "drop"
                  (wat "call" (id (release-helper m)) (wat "local.get" (id owner)) (● fn evidence)))
             (wat "local.get" (id result)))))

    (define (any-destructor (m Module) (type Type)) (→ String) (! mut)
      (helper! m "any-drop" (type-key type)
               (lambda (name)
                 (wat "func" (id name) (wat "type" (Word "$owner.drop"))
                      (wat "param" (Word "$owner") (ref-wat (owner-type m)))
                      (evidence-param m) (wat "result" (Word "i32"))
                      (tail-release (release-value m type
                                                   (wat "ref.cast" (rep->wat (rep m type))
                                                        (wat "struct.get" (id (any-type m)) (int 3)
                                                             (wat "ref.cast"
                                                                  (ref-wat (any-type m))
                                                                  (wat "local.get"
                                                                       (Word "$owner")))))
                                                   (wat "local.get" (Word "$ev"))))))))

    ;; An Any holds a value of `type` when its TypeId is the type's and its
    ;; value has the type's representation, which `ref.test` checks without
    ;; trapping.

    (define (any-holds? (fn Fn) (value Wat) (type Type)) (→ Wat) (! mut)
      (let* ((m (● fn module))
             (field (lambda (index) (wat "struct.get" (id (any-type m)) (int index) value))))
        (wat "i32.and"
             (wat "i32.eq" (field 2) (wat "i32.const" (int (any-type-id (program-of m) type))))
             (wat "ref.test" (wat "ref" (id (held-type m (fn-rep fn type)))) (field 3)))))

    ;; What an Any holds for a value of representation `r`: the value, or a
    ;; box around a scalar.

    (define (held-type (m Module) (r Rep)) (→ String) (! mut)
      (match r
        ((Scalar _) (box-type m r))
        ((Reference type) type)))

    ;; ---- Funcref closures ----

    ;; A Funcref becomes a closure that holds it, whose code casts it to the
    ;; Wasm type of a function of the expected type and calls it. The cast is
    ;; the only check: the engine traps if the function's Wasm type differs,
    ;; and nothing compares Snail Scheme types, which is what makes the cast unsafe.
    ;; That type is a Snail Scheme function's, which takes the evidence first,
    ;; so the held function is one another module compiled from Snail Scheme.

    (define (funcref-closure (m Module) (type Type) (reference Wat)) (→ Wat) (! mut)
      (match type

        ((TFun _ _ _)
         (let* ((signature (function-signature m type))
                (base (closure-type m (● signature first) (● signature second)))
                (holder (funcref-holder-type m base)))
           (wat "struct.new"
                (id holder)
                (wat "i64.const" (int -1)) (code-of m (owner-noop m))
                (wat "ref.func" (id (funcref-code m signature base holder)))
                (dropper-null)
                reference)))
        (_ (panic (string-append "unsafe-cast makes a function, not a " (type->string type))))))

    (define (funcref-holder-type (m Module) (base String)) (→ String) (! mut)
      (capture-type m base (list (Scalar "funcref"))))

    ;; The code takes the closure, the evidence and the arguments, and calls
    ;; the function the closure holds with the evidence and the arguments, at
    ;; that function's own type, which takes no closure.

    (define (funcref-code (m Module)
                          (signature (Pair (List Rep) Rep))
                          (base String)
                          (holder String))
      (→ String)
      (! mut)
      (let ((params (● signature first)) (result (● signature second)))
        (helper! m "funcref" holder
                 (lambda (function-id)
                   (push! (● m declared) function-id)
                   (wat* "func"
                         (concatenate
                          (list (list (id function-id) (wat "type" (id (code-type m base)))
                                      (wat "param" (ref-wat base))
                                      (wat "param" (evidence-ref m)))
                                (map (lambda (param) (wat "param" (rep->wat param))) params)
                                (list (wat "result" (rep->wat result))
                                      (held-call m params result holder)))))))))

    ;; The held function runs under the handlers in scope where the closure
    ;; is called: the code passes on its own evidence, local 1, and the
    ;; parameters that follow it.

    (define (held-call (m Module) (params (List Rep)) (result Rep) (holder String)) (→ Wat) (! mut)
      (let ((own (funcref-type m params result))
            (held (wat "struct.get"
                       (id holder)
                       (int 4)
                       (wat "ref.cast"
                            (ref-wat holder)
                            (wat "local.get" (int 0))))))
        (wat* "call_ref"
              (append (Cons (id own)
                            (map (lambda (index) (wat "local.get" (int (+ index 1))))
                                 (iota (+ (length params) 1))))
                      (list (wat "ref.cast" (ref-wat own) held))))))

    ;; The Wasm type of the function a Funcref refers to, which takes the
    ;; evidence and no closure.

    (define (funcref-type (m Module) (params (List Rep)) (result Rep)) (→ String) (! mut)
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

    ;; ---- Effect handlers ----

    ;; Handlers are evidence passed to every function: a list of nodes, each
    ;; an effect's label, its handler and the node outside it. A `handle`
    ;; extends the list for its body; an operation walks it for its effect's
    ;; label and calls that handler's implementation with the list outside
    ;; the node, so the implementation's own operations go to the next
    ;; handler out, and a list with no such node means the host default.
    ;; Nothing is global, so a task carries its handlers on its own stack.
    ;; Parent links are immutable. A resumed computation gets fresh nodes,
    ;; so inherited contexts and other suspended work keep their ancestry.
    ;; Field 5 copies the node's payload; field 6 names a forwarding node's
    ;; performer context, which renewal must follow even when it is hidden.

    (define (evidence-type (m Module)) (→ String) (! mut)
      (match (known-type m "evidence")
        ((Some type) type)
        ((None)
         (put! (● m type-ids) "evidence" "$evidence")
         (owner-type m)
         (evidence-copy-type m)
         (push! (● m globals)
                (wat "global" (id "$evidence.none") (ref-wat "$evidence")
                     (wat "struct.new" (id "$evidence")
                          (wat "i64.const" (int -1)) (code-of m (owner-noop m))
                          (wat "i32.const" (int -1)) (wat "ref.null" (Word "any"))
                          (wat "ref.null" (id "$evidence")) (wat "ref.null" (id "$evidence.copy"))
                          (wat "ref.null" (id "$evidence")))))
         (register-type! m "evidence" "$evidence"
                         (wat "type"
                              (Word "$evidence")
                              (wat "sub"
                                   (Word "final")
                                   (Word "$owner")
                                   (wat "struct"
                                        (wat "field" (wat "mut" (Word "i64")))
                                        (wat "field" (ref-wat "$owner.drop"))
                                        (wat "field" (Word "i32"))
                                        (wat "field" (Word "anyref"))
                                        (wat "field" (ref-wat "$evidence"))
                                        (wat "field"
                                             (ref-wat "$evidence.copy"))
                                        (wat "field"
                                             (ref-wat "$evidence")))))))))

    ;; Handler nodes own their implementations and their outer context.
    ;; Calls only observe evidence; saved frames and inherited contexts
    ;; acquire an owner when they outlive that call.
    (define (retain-evidence (m Module) (value Wat)) (→ Wat) (! mut)
      (wat "ref.cast" (evidence-ref m) (wat "call" (id (retain-helper m)) value)))

    (define (evidence-destructor (m Module) (effect String)) (→ String) (! mut)
      (let ((info (program-effect (program-of m) effect)) (node (wat "local.get" (Word "$node"))))
        (helper! m "evidence-drop" effect
                 (lambda (name)
                   (wat* "func"
                         (append
                          (list (id name) (wat "type" (Word "$owner.drop"))
                                (wat "param"
                                     (Word "$owner")
                                     (ref-wat (owner-type m)))
                                (evidence-param m) (wat "result" (Word "i32"))
                                (wat "local" (Word "$node") (evidence-ref m))
                                (wat "local"
                                     (Word "$outside")
                                     (ref-wat (evidence-type m)))
                                (wat "local.set"
                                     (Word "$node")
                                     (wat "ref.cast"
                                          (evidence-ref m)
                                          (wat "local.get" (Word "$owner"))))
                                (wat "local.set"
                                     (Word "$outside")
                                     (wat "struct.get" (id (evidence-type m)) (int 4) node))
                                )
                          (append
                           (map-indexed (lambda (index operation)
                                          (wat "drop" (wat "call" (id (release-helper m))
                                                           (wat "ref.cast"
                                                                (ref-wat (owner-type m))
                                                                (handler-field m info node index))
                                                           (wat "local.get"
                                                                (Word "$outside")))))
                                        (● info operations))
                           (list
                            (wat "if"
                                 (wat "i32.eqz" (wat "ref.is_null"
                                                     (wat "struct.get"
                                                          (id (evidence-type m))
                                                          (int 6)
                                                          node)))
                                 (wat "then" (wat "drop" (wat "call" (id (release-helper m))
                                                              (wat "struct.get"
                                                                   (id (evidence-type m))
                                                                   (int 6)
                                                                   node)
                                                              (wat "local.get" (Word "$ev"))))))
                            (wat "return_call" (id (release-helper m))
                                 (wat "local.get" (Word "$outside"))
                                 (wat "local.get" (Word "$ev")))))))))))

    ;; A resumption owns its frames, but inherited closures can also retain
    ;; their evidence. Renew the captured activation graph before either call
    ;; or cancellation. The map gives every old node exactly one new identity;
    ;; map entries own both identities until all frame and continuation slots
    ;; agree. Slot replacement retains before releasing, so it cannot finalize
    ;; either a changed node (held by the map) or an unchanged node (held by
    ;; its replacement slot). Only releasing the completed map can finalize.
    (define (activation-type (m Module)) (→ String) (! mut)
      (match (known-type m "activation")
        ((Some type) type)
        ((None)
         (evidence-type m)
         (register-type! m "activation.map" "$activation.map"
                         (wat "type"
                              (Word "$activation.map")
                              (wat "struct"
                                   (wat "field" (ref-wat "$evidence"))
                                   (wat "field" (ref-wat "$evidence"))
                                   (wat "field"
                                        (ref-wat "$activation.map")))))

         (register-type! m "activation" "$activation"
                         (wat "type"
                              (Word "$activation")
                              (wat "struct"
                                   (wat "field"
                                        (wat "mut"
                                             (ref-wat "$activation.map")))
                                   ))))))

    ;; Returned nodes are observations. Each map entry owns its old and fresh
    ;; nodes; parents, forwarding origins and installed roots retain separately.
    ;; Evidence is acyclic: installation points to existing contexts, and
    ;; activation seeds the delimiter before renewing any descendant paths.
    ;; An unchanged outside context keeps its identity and active delimiter.
    (define (activation-node (m Module)) (→ String) (! mut)
      (activation-type m)
      (template-helper! m "activation-node" ""
                        "(func {id} (param $state (ref null $activation)) (param $node (ref null {evidence})) (result (ref null {evidence}))
  (local $entry (ref null $activation.map))
  (local $parent (ref null {evidence})) (local $origin (ref null {evidence}))
  (local $fresh (ref null {evidence}))
  (if (ref.is_null (local.get $node)) (then (return (local.get $node))))
  (local.set $entry (struct.get $activation 0 (local.get $state)))
  (block $absent (loop $find
    (br_if $absent (ref.is_null (local.get $entry)))
    (if (ref.eq (struct.get $activation.map 0 (local.get $entry)) (local.get $node))
      (then (return (struct.get $activation.map 1 (local.get $entry)))))
    (local.set $entry (struct.get $activation.map 2 (local.get $entry))) (br $find)))
  (local.set $parent (call {id} (local.get $state) (struct.get {evidence} 4 (local.get $node))))
  (local.set $origin (call {id} (local.get $state) (struct.get {evidence} 6 (local.get $node))))
  (if (i32.and (ref.eq (local.get $parent) (struct.get {evidence} 4 (local.get $node)))
               (ref.eq (local.get $origin) (struct.get {evidence} 6 (local.get $node))))
    (then (return (local.get $node))))
  (local.set $fresh (call_ref {copier} (local.get $node)
    (local.get $parent) (local.get $origin)
    (struct.get {evidence} 5 (local.get $node))))
  (struct.set $activation 0 (local.get $state)
    (struct.new $activation.map
      (ref.cast (ref null {evidence}) (call {retain} (local.get $node))) (local.get $fresh)
      (struct.get $activation 0 (local.get $state))))
  (local.get $fresh))"
                        (list (Pair "evidence" (evidence-type m))
                              (Pair "copier" (evidence-copy-type m))
                              (Pair "retain" (retain-helper m)))))

    ;; Handled frames contain another owned continuation. Both entries read
    ;; that same object, so updating it establishes both execution and
    ;; cancellation contexts together. Source values in captures stay intact.
    (define (activate-continuation (m Module)) (→ String) (! mut)
      (activation-type m)
      (template-helper! m "activation-frames" ""
                        "(func {id} (param $state (ref null $activation)) (param $continuation (ref null {continuation}))
  (local $old (ref null {evidence})) (local $frames (ref null {frames})) (local $frame (ref null {frame}))
  (local.set $old (struct.get {continuation} 1 (local.get $continuation)))
  (struct.set {continuation} 1 (local.get $continuation)
    (ref.cast (ref null {evidence}) (call {retain}
      (call {renew} (local.get $state) (local.get $old)))))
  (drop (call {release} (local.get $old) (struct.get {continuation} 1 (local.get $continuation))))
  (local.set $frames (struct.get {continuation} 0 (local.get $continuation)))
  (block $done (loop $next
    (br_if $done (ref.is_null (local.get $frames)))
    (local.set $frame (struct.get {frames} 0 (local.get $frames)))
    (if (ref.test (ref {handled}) (local.get $frame))
      (then (call {id} (local.get $state)
        (struct.get {handled} 3 (ref.cast (ref null {handled}) (local.get $frame))))))
    (local.set $old (struct.get {frame} 2 (local.get $frame)))
    (struct.set {frame} 2 (local.get $frame)
      (ref.cast (ref null {evidence}) (call {retain}
        (call {renew} (local.get $state) (local.get $old)))))
    (drop (call {release} (local.get $old) (struct.get {continuation} 1 (local.get $continuation))))
    (local.set $frames (struct.get {frames} 1 (local.get $frames))) (br $next))))"
                        (list (Pair "evidence" (evidence-type m))
                              (Pair "continuation" (continuation-type m))
                              (Pair "frames" (frames-type m)) (Pair "frame" (frame-type m))
                              (Pair "handled" (handled-type m)) (Pair "retain" (retain-helper m))
                              (Pair "renew" (activation-node m))
                              (Pair "release" (release-helper m)))))

    (define (release-activation (m Module)) (→ String) (! mut)
      (activation-type m)
      (template-helper! m "activation-release" ""
                        "(func {id} (param $state (ref null $activation)) (param $ev (ref null {evidence}))
  (local $entry (ref null $activation.map))
  (local.set $entry (struct.get $activation 0 (local.get $state)))
  (block $new-done (loop $new
    (br_if $new-done (ref.is_null (local.get $entry)))
    (drop (call {release} (struct.get $activation.map 0 (local.get $entry)) (local.get $ev)))
    (drop (call {release} (struct.get $activation.map 1 (local.get $entry)) (local.get $ev)))
    (local.set $entry (struct.get $activation.map 2 (local.get $entry))) (br $new))))"
                        (list (Pair "evidence" (evidence-type m))
                              (Pair "release" (release-helper m)))))

    ;; Public resumptions originate at actual handler catches, so this
    ;; delimiter is ordinary, with no forwarding origin. Nested forwarding
    ;; catches are renewed through their enclosing owned handled frames.
    (define (activate-helper (m Module)) (→ String) (! mut)
      (activation-type m)
      (template-helper! m "activation-start" ""
                        "(func {id} (param $continuation (ref null {continuation})) (param $ev (ref null {evidence}))
  (local $old (ref null {evidence})) (local $fresh (ref null {evidence})) (local $state (ref null $activation))
  (local.set $old (struct.get {continuation} 1 (local.get $continuation)))
  (local.set $fresh (call_ref {copier} (local.get $old) (local.get $ev)
    (struct.get {evidence} 6 (local.get $old))
    (struct.get {evidence} 5 (local.get $old))))
  (local.set $state (struct.new $activation
    (struct.new $activation.map (ref.cast (ref null {evidence}) (call {retain} (local.get $old)))
      (local.get $fresh) (ref.null $activation.map))))
  (call {frames} (local.get $state) (local.get $continuation))
  (call {release} (local.get $state) (local.get $ev)))"
                        (list (Pair "evidence" (evidence-type m))
                              (Pair "continuation" (continuation-type m))
                              (Pair "copier" (evidence-copy-type m))
                              (Pair "retain" (retain-helper m))
                              (Pair "frames" (activate-continuation m))
                              (Pair "release" (release-activation m)))))

    (define (evidence-copy-type (m Module)) (→ String) (! mut)
      (match (known-type m "evidence.copy")
        ((Some type) type)
        ((None)
         (register-type! m "evidence.copy" "$evidence.copy"
                         (wat "type"
                              (Word "$evidence.copy")
                              (wat "func"
                                   (wat "param" (ref-wat "$evidence"))
                                   (wat "param" (ref-wat "$evidence"))
                                   (wat "param" (ref-wat "$evidence"))
                                   (wat "result" (ref-wat "$evidence"))))))))

    ;; The copier owns a newly allocated activation. Ordinary implementations
    ;; are shared; forwarding implementations are rebuilt over their renewed
    ;; performer context. The evidence walker treats that origin as another
    ;; graph edge, including when it is hidden from the visible parent chain.
    (define (evidence-copier (m Module) (effect String) (forwarding? Bool)) (→ String) (! mut)
      (helper! m (if forwarding? "forward-copy" "evidence-copy") effect
               (lambda (name)
                 (let* ((info (program-effect (program-of m) effect))
                        (node (wat "local.get" (Word "$node")))
                        (origin (wat "local.get" (Word "$origin")))
                        (fields (map-indexed
                                 (lambda (index operation)
                                   (if forwarding?
                                       (forwarding-field m
                                                         info
                                                         operation
                                                         origin)
                                       (wat "ref.cast" (implementation-field m info operation)
                                            (wat "call" (id (retain-helper m))
                                                 (wat "ref.cast"
                                                      (ref-wat (owner-type m))
                                                      (handler-field m info node index))))))
                                 (● info operations))))
                   (push! (● m declared) name)
                   (wat "func" (id name) (wat "type" (id (evidence-copy-type m)))
                        (wat "param" (Word "$node") (evidence-ref m))
                        (wat "param" (Word "$outside") (evidence-ref m))
                        (wat "param"
                             (Word "$origin")
                             (ref-wat (evidence-type m)))
                        (wat "result" (evidence-ref m))
                        (new-evidence m effect
                                      (wat* "struct.new" (Cons (id (handler-type m effect)) fields))
                                      (wat "local.get" (Word "$outside")) forwarding? origin))))))

    (define (retain-optional-evidence (m Module) (value Wat)) (→ Wat) (! mut)
      (wat "if" (wat "result" (ref-wat (evidence-type m)))
           (wat "ref.is_null" value)
           (wat "then" (wat "ref.null" (id (evidence-type m))))
           (wat "else" (retain-evidence m value))))

    (define (new-evidence (m Module) (effect String) (handler Wat) (outside Wat)
                          (forwarding? Bool) (origin Wat)) (→ Wat) (! mut)
                          (wat "struct.new" (id (evidence-type m))
                               (wat "i64.const" (int 1)) (code-of m (evidence-destructor m effect))
                               (effect-label effect) handler (retain-evidence m outside)
                               (wat "ref.func" (id (evidence-copier m effect forwarding?)))
                               (retain-optional-evidence m origin)))

    (define (evidence-rep (m Module)) (→ Rep) (! mut)
      (Reference (evidence-type m)))

    (define (evidence-ref (m Module)) (→ Wat) (! mut)
      (rep->wat (evidence-rep m)))

    (define (evidence-param (m Module)) (→ Wat) (! mut)
      (wat "param" (Word "$ev") (evidence-ref m)))

    ;; The empty list: one node no effect's label matches, outside everything.

    (define (evidence-none (m Module)) (→ Wat) (! mut)
      (evidence-type m)
      (wat "global.get" (id "$evidence.none")))

    (define (effect-label (effect String)) (→ Wat)
      (wat "i32.const" (int (type-id effect))))

    ;; A handler is a struct of the effect's implementations, in operation order.

    (define (handler-type (m Module) (effect String)) (→ String) (! mut)
      (let ((key (string-append "handler." effect)))
        (match (known-type m key)
          ((Some type) type)
          ((None)
           (let* ((info (program-effect (program-of m) effect))
                  (fields
                   (map (lambda (operation) (wat "field" (implementation-field m info operation)))
                        (● info operations))))
             (register-type! m
                             key
                             (wasm-id key)
                             (wat "type" (id (wasm-id key)) (wat* "struct" fields))))))))

    ;; A control implementation's type depends on its handle's result, and
    ;; only its handle site calls it, so its field holds any reference.

    (define (implementation-field (m Module) (info Effect) (operation String)) (→ Wat) (! mut)
      (if (member? operation (● info control))
          (ref-wat "any")
          (rep->wat (rep m (operation-type m operation)))))

    (define (operation-type (m Module) (operation String)) (→ Type)
      (match (program-value (program-of m) operation)
        ((Some (Operation _ (Scheme _ _ _ (TFun params result _)))) (TFun params result empty-row))
        (_ (panic "internal error: not an operation"))))

    (define (operation-result (m Module) (operation String)) (→ Type)
      (match (operation-type m operation)
        ((TFun _ result _) result)
        (_ (panic "internal error: an operation is a function"))))

    ;; An operation that answers Never cannot return to its performer: its
    ;; implementation is handed no `resume`, and its yields save nothing.

    (define (answers-never? (m Module) (operation String)) (→ Bool)
      (never-type? (operation-result m operation)))

    ;; The implementations are values of the surrounding evidence; the body
    ;; runs with the new node as its evidence. A handle of a control effect
    ;; also catches the yields aimed at its node (see Control).

    (define (emit-handle (fn Fn) (expr Expr) (effect String)
                         (implementations (List (Pair String Expr))) (body Expr))
      (→ (List Wat)) (! mut)
      (emit-control-handle fn expr effect implementations body))

    ;; A new evidence node in a local: the local's name, and the instruction
    ;; that sets it to the node holding the handler.

    (define (install-handler (fn Fn) (effect String) (implementations (List (Pair String Expr))))
      (→ (Pair String Wat)) (! mut)
      (let* ((m (● fn module)) (node (local-id fn "ev"))
             (handler (wat* "struct.new" (Cons (id (handler-type m effect))
                                               (map (lambda (operation)
                                                      (emit1 fn
                                                             (handler-implementation implementations
                                                                                     operation)))
                                                    (● (program-effect (program-of m) effect)
                                                       operations))))))
        (push! (● (● fn state) locals) (wat "local" (id node) (evidence-ref m)))
        (Pair node (wat "local.set" (id node)
                        (new-evidence m effect handler (● fn evidence) #f
                                      (wat "ref.null" (id (evidence-type m))))))))

    (define (handler-implementation (implementations (List (Pair String Expr))) (operation String))
      (→ Expr)
      (match (assoc-ref implementations operation)
        ((Some implementation) implementation)
        ((None) (panic "internal error: missing implementation"))))

    ;; Each operation is one function, so its call sites are ordinary calls.
    ;; It walks the evidence for its effect's node and calls that handler's
    ;; implementation with the evidence outside it, which forwards the
    ;; effects its latent row names (see Latent effects); with no node it
    ;; uses the default. A control operation records a yield at the node
    ;; instead (see Control).

    (define (performer (m Module) (effect String) (operation String)) (→ String) (! mut)
      (helper! m "perform" operation
               (lambda (function-id)
                 (let* ((signature (function-signature m (operation-type m operation)))
                        (params (● signature first))
                        (result (● signature second))
                        (names (argument-names signature))
                        (info (program-effect (program-of m) effect)))
                   (wat* "func"
                         (concatenate
                          (list (Cons (id function-id)
                                      (Cons (evidence-param m)
                                            (map (lambda (pair)
                                                   (wat "param"
                                                        (id (● pair first))
                                                        (rep->wat (● pair second))))
                                                 (zip names params))))
                                (list (wat "result" (rep->wat result))
                                      (wat "local"
                                           (Word "$node")
                                           (ref-wat (evidence-type m))))
                                (forwarding-locals m operation result)
                                (list
                                 (wat "local.set" (Word "$node") (wat "local.get" (Word "$ev")))
                                 (wat* "loop"
                                       (Cons (Word "$walk")
                                             (handler-search m info operation names params result)))
                                 (wat "unreachable")))))))))

    ;; One step of the walk: the default past the last node, the
    ;; implementation at the effect's node, else the next node out.

    (define (handler-search (m Module)
                            (info Effect)
                            (operation String)
                            (names (List String))
                            (params (List Rep))
                            (result Rep))
      (→ (List Wat))
      (! mut)
      (let ((node (wat "local.get" (Word "$node"))) (evidence (evidence-type m)))
        (list
         (wat "if" (wat "ref.is_null" node) (wat* "then" (default-call m info operation names)))
         (wat "if"
              (wat "i32.eq"
                   (wat "struct.get" (id evidence) (int 2) node)
                   (effect-label (● info name)))
              (wat* "then" (at-handler m info operation names params result)))
         (wat "local.set" (Word "$node") (wat "struct.get" (id evidence) (int 4) node))
         (wat "br" (Word "$walk")))))

    ;; At the effect's node an ordinary operation calls the implementation
    ;; there and returns its result, under forwarding nodes when its latent
    ;; row names effects with operations; a control operation records the
    ;; yield and returns zero or null.

    (define (at-handler (m Module)
                        (info Effect)
                        (operation String)
                        (names (List String))
                        (params (List Rep))
                        (result Rep))
      (→ (List Wat))
      (! mut)
      (cond ((member? operation (● info control))
             (list (record-yield m info operation names params)
                   (wat "return" (default-value (rep m (operation-result m operation))))))
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

    (define (implementation-call (m Module)
                                 (info Effect)
                                 (operation String)
                                 (names (List String))
                                 (params (List Rep))
                                 (result Rep)
                                 (evidence Wat))
      (→ Wat)
      (! mut)
      (let* ((handler-id (handler-type m (● info name))) (base (closure-type m params result))
             (implementation
              (wat "struct.get" (id handler-id) (int (operation-index info operation))
                   (wat "ref.cast"
                        (ref-wat handler-id)
                        (wat "struct.get"
                             (id (evidence-type m))
                             (int 3)
                             (wat "local.get" (Word "$node")))))))
        (wat* "call_ref" (Cons (id (code-type m base))
                               (Cons (wat "ref.cast"
                                          (ref-wat base)
                                          (wat "call" (id (retain-helper m)) implementation))
                                     (Cons evidence
                                           (append
                                            (map (lambda (name) (wat "local.get" (id name))) names)
                                            (list (wat "struct.get"
                                                       (id base)
                                                       (int 2)
                                                       implementation)))))))))

    ;; The evidence outside a node.

    (define (node-outside (m Module) (node Wat)) (→ Wat) (! mut)
      (wat "struct.get" (id (evidence-type m)) (int 4) node))

    ;; Past the last node: the Snail Scheme default, called under the
    ;; performer's evidence, or a trap.

    (define (default-call (m Module) (info Effect) (operation String) (names (List String)))
      (→ (List Wat))
      (! mut)
      (let ((arguments (map (lambda (name) (wat "local.get" (id name))) names)))
        (match (assoc-ref (● info defaults) operation)
          ((Some function)
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
    ;; then returns zero or null for its inactive result slot. Each call that may
    ;; yield is the value of a let, as (snail shell compiler prepare)
    ;; arranges, and after that let the record is tested: while it is set,
    ;; the let saves its body as a frame on the record (see Frames) and
    ;; leaves with zero or null, a function to its caller and a handle body
    ;; to the end of its block, until the handle whose node the record
    ;; names. That handle clears the record and calls the operation's
    ;; implementation in its own context, with the recorded arguments and a
    ;; `resume` holding the frames (see Resuming); the implementation's
    ;; result is the handle's. A yield of an operation that answers Never
    ;; is never resumed, so where every effect a call may yield to is of
    ;; that kind, its test leaves without saving a frame, and no join is
    ;; built for the rest. A call whose value flows straight out needs
    ;; no test, so a tail call stays a tail call. Nothing reads a
    ;; inactive slot, since every caller tests first and leaves too. The
    ;; record is clear whenever Snail Scheme code runs outside a yield, so
    ;; none is live while the host runs between calls.

    ;; Where a yield leaves the code being emitted, with zero or null: a
    ;; function returns its inactive result to its caller; a block, the
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

    (define (function-exit (type Type)) (→ (Option Exit))
      (match (fn-arrow type)
        ((TFun _ result _) (Some (ToCaller result)))
        (_ (panic "internal error: not a function type"))))

    (define (yield-type (m Module)) (→ String) (! mut)
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
                                          (wat "mut" (ref-wat frames))))))))))

    ;; The global holding the record, null while nothing yields. A whole
    ;; program declares and exports it. A library imports it from the control
    ;; module, which a library build links first. A loading engine supplies
    ;; its own control module, so yields cross into loaded program code under
    ;; the same scheduler and evidence protocol.

    (define (yielding (m Module)) (→ String) (! mut)
      (let ((type (wat "mut" (ref-wat (yield-type m)))))
        (match (● (● m declarations) owner)
          ((Some _)
           (import-once! m "yielding" "$yielding"
                         (lambda (global)
                           (wat "import"
                                (wat-string "snail.core.control")
                                (wat-string "yielding")
                                (wat "global" (id global) type)))))
          ((None)
           (unless (table-contains? (● m helpers) "yielding")
             (put! (● m helpers) "yielding" "$yielding")
             (push! (● m globals)
                    (wat "global" (id "$yielding") type (wat "ref.null" (id "$yield"))))
             (push! (● m exports)
                    (wat "export" (wat-string "yielding") (wat "global" (id "$yielding")))))
           "$yielding"))))

    ;; The module a library build links first when its program has control
    ;; effects: it declares the record's global and exports it, and its
    ;; text never changes.

    (define (emit-control-module (program Program)) (→ Wat) (! mut)
      (let ((m (new-module (Declarations (Program-items-set program (Nil))
                                         (None) (control-effects program) empty-table))))
        (yielding m)
        (module-wat m)))

    (define (yielding? (m Module)) (→ Wat) (! mut)
      (wat "i32.eqz" (wat "ref.is_null" (wat "global.get" (id (yielding m))))))

    ;; Whether the record, which is set, names `node`.

    (define (aimed-at? (m Module) (node Wat)) (→ Wat) (! mut)
      (wat "ref.eq"
           (wat "struct.get"
                (id (yield-type m))
                (int 0)
                (wat "global.get" (id (yielding m))))
           node))

    (define (may-yield? (fn Fn) (value Expr)) (→ Bool)
      (match (module-callees (● fn module))
        ((Some callees) (not (null? (yields callees value))))
        ((None) #f)))

    ;; The rest of a let after its value. When the value may yield, a test
    ;; comes first: while the record is set, it saves the let's body as a
    ;; frame and leaves. In a join function, whose own rest the body is,
    ;; the body then runs in that frame, by a tail call as the runner would
    ;; make, so each join holds its body only up to the next yield point.
    ;; A yield that nothing can resume saves nothing, so its test only
    ;; leaves, and the body follows in the same function.

    (define (let-rest (fn Fn)
                      (name String)
                      (value Expr)
                      (cleanup (Option Expr))
                      (body Expr)
                      (tail? Bool))
      (→ (List Wat))
      (! mut)
      (cond ((not (may-yield? fn value)) (emit fn body tail?))
            ((aborts? fn value)
             (Cons (wat "if" (yielding? (● fn module))
                        (wat* "then" (append (abort-drops fn cleanup)
                                             (list (leave fn)))))
                   (emit fn body tail?)))
            ((match (● fn exit) ((Some (ToRunner)) #t) (_ #f))
             (continue-in-frame fn name value cleanup body))
            (else (let ((test (yield-test fn (frame fn name value cleanup body))))
                    (append test (emit fn body tail?))))))

    ;; No resumption will own this scope. Drop its live values before
    ;; leaving its handlers; cleanup cannot itself perform control.

    (define (abort-drops (fn Fn) (cleanup (Option Expr))) (→ (List Wat)) (! mut)
      (match cleanup
        ((Some body) (list (wat "drop" (emit1 fn body))))
        ((None) (Nil))))

    ;; Whether every effect `value` may yield to aborts: each of its control
    ;; operations answers Never, so its handler is handed no `resume`, and
    ;; nothing will run what follows the yield.

    (define (aborts? (fn Fn) (value Expr)) (→ Bool)
      (let ((m (● fn module)))
        (match (module-callees m)
          ((Some callees)
           (every? (lambda (label)
                     (every? (lambda (operation) (answers-never? m operation))
                             (● (program-effect (program-of m) label) control)))
                   (yields callees value)))
          ((None) #f))))

    (define (yield-test (fn Fn) (saved Wat)) (→ (List Wat)) (! mut)
      (let* ((m (● fn module)) (exit (leave fn)))
        (list (wat "if" (yielding? m) (wat "then" (wat "call" (id (push-helper m)) saved) exit)))))

    (define (continue-in-frame (fn Fn)
                               (name String)
                               (value Expr)
                               (cleanup (Option Expr))
                               (body Expr))
      (→ (List Wat)) (! mut)
      (let* ((m (● fn module)) (base (frame-type m))
             (temp (declare-temp! fn (ref-wat base)))
             (saved (wat "local.get" (id temp)))
             (set (wat "local.set" (id temp) (frame fn name value cleanup body)))
             (test (yield-test fn saved))
             (argument (box-value m (● value type) (variable fn name unchecked))))
        (Cons set (append test (list (wat "return_call" (id (frame-runner m)) saved argument))))))

    ;; A let's value that holds yield points of its own is a block they
    ;; leave, so that the let's own test then saves the let's body too.

    (define (emit-let-value (fn Fn) (value Expr)) (→ Wat) (! mut)
      (match (module-callees (● fn module))
        ((Some callees)
         (if (holds-yield-point? callees value)
             (let ((label (local-id fn "yield")) (type (● value type)))
               (wat* "block"
                     (Cons (id label)
                           (Cons (wat "result" (rep->wat (fn-rep fn type)))
                                 (emit (Fn-exit-set fn (Some (ToBlock label type))) value #f)))))
             (emit1 fn value)))
        ((None) (emit1 fn value))))

    (define (leave (fn Fn)) (→ Wat) (! mut)
      (match (● fn exit)
        ((Some (ToCaller result)) (wat "return" (default-value (rep (● fn module) result))))
        ((Some (ToBlock label result))
         (wat "br" (id label) (default-value (rep (● fn module) result))))
        ((Some (ToRunner)) (wat "return" (wat "ref.null" (Word "any"))))
        ((None) (panic "internal error: a yield outside any function"))))

    ;; ---- Frames ----

    ;; A frame is a closure over the rest of a function at a yield point:
    ;; the body of a let whose value yielded. Its code takes the frame and
    ;; the let's value and returns the body's, each boxed when a scalar, so
    ;; one code type serves both entries of every frame. It holds evidence
    ;; and the locals needed by execution or cleanup; that evidence reaches
    ;; the handler the yield is aimed at. Outside join functions a frame is
    ;; built only on the path that leaves, so the fast path allocates none.

    ;; The runner consumes one saved frame, detached from its continuation
    ;; before entry. Only this path or cancellation can take its owners.
    ;; Evidence stays alive through that execution, including its releases.
    (define (frame-runner (m Module)) (→ String) (! mut)
      (template-helper! m "frame-run" ""
                        "(func {id} (param $frame (ref null {frame})) (param $value anyref) (result anyref)
  (local $ev (ref null {evidence}))
  (local.set $ev (struct.get {frame} 2 (local.get $frame)))
  (local.set $value (call_ref {code} (local.get $frame) (local.get $value) (struct.get {frame} 0 (local.get $frame))))
  (drop (call {release} (local.get $ev) (local.get $ev)))
  (local.get $value))"
                        (list (Pair "frame" (frame-type m)) (Pair "evidence" (evidence-type m))
                              (Pair "code" (code-type m (frame-type m)))
                              (Pair "release" (release-helper m)))))

    (define (frame-type (m Module)) (→ String) (! mut)
      (match (known-type m "frame")
        ((Some type) type)
        ((None)
         (put! (● m type-ids) "code:$frame" "$frame.code")
         (put! (● m type-ids) "capture-offset:$frame" "3")
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

    (define (frames-type (m Module)) (→ String) (! mut)
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
    ;; its body, cancellation code, retained evidence, and one environment
    ;; shared by both entries. Cleanup-only owners must be captured too:
    ;; a Never continuation need not mention the owners it abandons.

    (define (frame (fn Fn) (name String) (value Expr) (cleanup (Option Expr)) (body Expr))
      (→ Wat) (! mut)
      (let* ((m (● fn module))
             (captured (filter (lambda (local) (and (not (string=? local name)) (local? fn local)))
                               (delete-duplicates string=?
                                                  (append (expr-references body)
                                                          (match cleanup
                                                            ((Some code) (expr-references code))
                                                            ((None) (Nil)))))))
             (entries (map (lambda (local) (Pair local (capture-rep fn local))) captured))
             (type
              (capture-type m (frame-type m) (map (lambda (record) (● record second)) entries)))
             (join
              (emit-join! (Fn-exit-set (new-fn m) (Some (ToRunner))) name value body entries type)))
        (wat* "struct.new"
              (append (list (id type) (wat "ref.func" (id join))
                            (wat "ref.func" (id (emit-cancel! m cleanup entries type)))
                            (retain-evidence m (● fn evidence)))
                      (map (lambda (local) (variable fn local unchecked)) captured)))))

    ;; A let's body as a function of its frame and its boxed value: it
    ;; loads the frame's locals and evidence and binds the value, runs the
    ;; body, which a yield leaves with null, and boxes the body's value.
    ;; The body runs to the let's end and no further, since the frames
    ;; outside it continue from there, and its tail calls are calls, since
    ;; their results are boxed. It is named by its text, as a lambda is,
    ;; so the joins of one let, which the function and the join of the
    ;; let before it both need, are one function.

    (define (emit-join! (join Fn)
                        (name String)
                        (value Expr)
                        (body Expr)
                        (entries (List (Pair String Rep)))
                        (type String))
      (→ String)
      (! mut)
      (let* ((m (● join module))
             (loads (frame-loads join entries type))
             (local (declare-local! join name (fn-rep join (● value type))))
             (argument (wat "local.set"
                            (id local)
                            (unbox-value m (● value type) (wat "local.get" (Word "$value")))))
             (result (box-value m (● body type) (emit1 join body))))
        (lambda-id m
                   "join"
                   (join-wat join (append loads (list argument result)))
                   0)))

    (define (emit-cancel! (m Module) (cleanup (Option Expr))
                          (entries (List (Pair String Rep))) (type String))
      (→ String) (! mut)
      (let* ((cancel (new-fn m))
             (code (match cleanup
                     ((Some body)
                      (let ((loads (frame-loads cancel entries type)))
                        (append loads (list (wat "drop" (emit1 cancel body))))))
                     ((None) (Nil)))))
        (lambda-id m "cancel"
                   (join-wat cancel (append code (list (wat "ref.null" (Word "any"))))) 0)))

    ;; Both entries read the same captures and the frame's current evidence,
    ;; which activation may have renewed before resume or cancellation.
    (define (frame-loads (fn Fn) (entries (List (Pair String Rep))) (type String))
      (→ (List Wat)) (! mut)
      (push! (● (● fn state) locals) (wat "local" (Word "$ev") (evidence-ref (● fn module))))
      (let ((frame (wat "ref.cast" (ref-wat type) (wat "local.get" (Word "$closure")))))
        (Cons (wat "local.set" (Word "$ev") (wat "struct.get" (id type) (int 2) frame))
              (capture-loads fn entries type))))

    (define (join-wat (join Fn) (code (List Wat))) (→ Wat) (! mut)
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

    (define (box-value (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (match (rep m type)
        ((Scalar name) (wat "struct.new" (id (box-type m (Scalar name))) value))
        ((Reference _) value)))

    (define (unbox-value (m Module) (type Type) (value Wat)) (→ Wat) (! mut)
      (match (rep m type)
        ((Scalar name)
         (let ((box (box-type m (Scalar name))))
           (wat "struct.get"
                (id box)
                (int 0)
                (wat "ref.cast" (ref-wat box) value))))
        ((Reference type-id) (wat "ref.cast" (ref-wat type-id) value))))

    ;; Saves a frame on the record, as the yield leaves it.

    (define (push-helper (m Module)) (→ String) (! mut)
      (template-helper! m "control" "push"
                        "(func {id} (param $frame (ref null {frame}))
  (local $record (ref null {yield}))
  (local.set $record (global.get {yielding}))
  (struct.set {yield} 3 (local.get $record) (struct.new {frames} (local.get $frame) (struct.get {yield} 3 (local.get $record)))))"
                        (list (Pair "frame" (frame-type m))
                              (Pair "yield" (yield-type m))
                              (Pair "yielding" (yielding m))
                              (Pair "frames" (frames-type m)))))

    ;; ---- Performing and catching ----

    ;; The yield of `operation` at the node the performer's walk is on,
    ;; with no frames yet.

    (define (record-yield (m Module)
                          (info Effect)
                          (operation String)
                          (names (List String))
                          (params (List Rep)))
      (→ Wat)
      (! mut)
      (wat "global.set" (id (yielding m))
           (wat "struct.new"
                (id (yield-type m))
                (wat "local.get" (Word "$node"))
                (wat "i32.const" (int (operation-index info operation)))
                (wat* "struct.new"
                      (Cons (id (arguments-type m operation params))
                            (map (lambda (name) (wat "local.get" (id name))) names)))
                (wat "ref.null" (id (frames-type m))))))

    (define (operation-index (info Effect) (operation String)) (→ I64)
      (match (list-index (lambda (o) (string=? o operation)) (● info operations))
        ((Some index) index)
        ((None) (panic "internal error: unknown operation"))))

    ;; An operation's arguments, as the record holds them.

    (define (arguments-type (m Module) (operation String) (params (List Rep))) (→ String) (! mut)
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
    ;; leaves by branching to its end with zero or null. There the handle
    ;; catches a yield aimed at its own node; any other yield leaves the
    ;; inactive result as the handle's value, and the record set for its caller,
    ;; with the handle saved as a frame of its own (see Resuming).

    (define (emit-control-handle (fn Fn)
                                 (expr Expr)
                                 (effect String)
                                 (implementations (List (Pair String Expr)))
                                 (body Expr))
      (→ (List Wat))
      (! mut)
      (let* ((info (program-effect (program-of (● fn module)) effect))
             (installed (install-handler fn effect implementations))
             (label (local-id fn "handle")))
        (Cons (● installed second)
              (handled-body fn expr info (● installed first) label body))))

    ;; The body's value, or the implementation's when the handle catches.

    (define (handled-body (fn Fn)
                          (expr Expr)
                          (info Effect)
                          (node String)
                          (label String)
                          (body Expr))
      (→ (List Wat))
      (! mut)
      (let* ((m (● fn module))
             (type (● expr type))
             (result (fn-rep fn type))
             (value (declare-temp! fn (rep->wat result)))
             (code (emit (Fn-exit-set (Fn-evidence-set fn (wat "local.get" (id node)))
                                      (Some (ToBlock label type)))
                         body
                         #f))
             (catch (if (null? (● info control)) (wat "nop")
                        (catch-yield m info type (wat "local.get" (id node)) value (● expr loc)))))
        (list (wat "local.set"
                   (id value)
                   (wat* "block" (Cons (id label) (Cons (wat "result" (rep->wat result)) code))))
              catch
              (wat "drop"
                   (wat "call" (id (release-helper m)) (wat "local.get" (id node)) (● fn evidence)))
              (wat "local.get" (id value)))))

    (define (catch-yield (m Module) (info Effect) (type Type) (node Wat) (value String) (loc Loc))
      (→ Wat)
      (! mut)
      (wat "if"
           (yielding? m)
           (wat "then"
                (wat "local.set"
                     (id value)
                     (wat "call" (id (catcher m info type loc)) (retain-evidence m node))))))

    ;; What a handle does with the yield that has reached it, for one
    ;; effect and handle result type; the handle site and `resume` both
    ;; end here. A yield aimed at another node leaves the handle, which
    ;; saves itself as one frame, and the handle's result stays inactive.
    ;; One aimed at `node` is caught: the record is cleared, the yield's
    ;; frames become a continuation, and the implementation of the recorded
    ;; operation runs in the context outside the node, with the recorded
    ;; arguments and a `resume` holding the continuation. Its call is a
    ;; tail call, so a handler that resumes in tail position runs in
    ;; constant stack however many times its operation is performed.

    (define (catcher (m Module) (info Effect) (type Type) (loc Loc)) (→ String) (! mut)
      (helper! m "catch" (string-append (● info name) " " (type-key type))
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
                                               (● info control))
                                          (list (wat "unreachable"))))))))

    (define (pass-on (m Module) (info Effect) (type Type) (loc Loc)) (→ Wat) (! mut)
      (let ((node (wat "local.get" (Word "$node"))))
        (wat "if"
             (wat "i32.eqz" (aimed-at? m node))
             (wat "then"
                  (enclose m (Handling info loc) type node)
                  (wat "return" (default-value (rep m type)))))))

    (define (dispatch-locals (m Module) (info Effect) (type Type)) (→ (List Wat)) (! mut)
      (append (list (wat "local" (Word "$record") (ref-wat (yield-type m)))
                    (wat "local"
                         (Word "$continuation")
                         (ref-wat (continuation-type m))))
              (map (lambda (operation)
                     (wat "local"
                          (implementation-local info operation)
                          (ref-wat (implementation-base m operation type))))
                   (● info control))))

    (define (take-continuation (m Module)) (→ (List Wat)) (! mut)
      (let ((frames
             (wat "struct.get" (id (yield-type m)) (int 3) (wat "local.get" (Word "$record")))))
        (list (wat "local.set"
                   (Word "$record")
                   (wat "global.get" (id (yielding m))))
              (wat "global.set" (id (yielding m)) (wat "ref.null" (id (yield-type m))))
              (wat "local.set" (Word "$continuation")
                   (wat "struct.new"
                        (id (continuation-type m))
                        (wat "call" (id (reverse-helper m)) frames)
                        (wat "local.get" (Word "$node")))))))

    ;; The implementation of a control operation, if the record names it,
    ;; taken from the handler at the node.

    (define (dispatch-case (m Module) (info Effect) (type Type) (operation String) (loc Loc))
      (→ Wat)
      (! mut)
      (let* ((index (operation-index info operation))
             (base (implementation-base m operation type))
             (local (implementation-local info operation))
             (node (wat "local.get" (Word "$node")))
             (outer (wat "struct.get" (id (evidence-type m)) (int 4) node))
             (arguments (recorded-arguments m operation (wat "local.get" (Word "$record")))))
        (wat "if"
             (wat "i32.eq"
                  (wat "struct.get" (id (yield-type m)) (int 1) (wat "local.get" (Word "$record")))
                  (wat "i32.const" (int index)))
             (wat "then"
                  (wat "local.set"
                       local
                       (wat "ref.cast" (ref-wat base)
                            (wat "call" (id (retain-helper m))
                                 (wat "ref.cast"
                                      (ref-wat (owner-type m))
                                      (handler-field m info node index)))))
                  (if (answers-never? m operation)
                      (wat "drop" (call-dropper m (resume-dropper m) outer))
                      (wat "nop"))
                  (closure-call-wat m
                                    base
                                    (wat "local.get" local)
                                    (Cons outer
                                          (if (answers-never? m operation)
                                              arguments
                                              (append arguments
                                                      (list
                                                       (resume-closure m
                                                                       info
                                                                       operation
                                                                       type
                                                                       loc)))))
                                    #t)))))

    (define (implementation-local (info Effect) (operation String)) (→ Wat)
      (Word (string-append "$implementation." (i64->string (operation-index info operation)))))

    ;; An implementation's closure type: the operation's arguments and
    ;; `resume` to the handle's result. An operation that answers Never has
    ;; no `resume`.

    (define (implementation-base (m Module) (operation String) (type Type)) (→ String) (! mut)
      (let ((params (● (function-signature m (operation-type m operation)) first)))
        (closure-type m
                      (if (answers-never? m operation)
                          params
                          (append params (list (Reference (resume-base m operation type)))))
                      (rep m type))))

    (define (handler-field (m Module) (info Effect) (node Wat) (index I64)) (→ Wat) (! mut)
      (let ((handler (handler-type m (● info name))))
        (wat "struct.get"
             (id handler)
             (int index)
             (wat "ref.cast"
                  (ref-wat handler)
                  (wat "struct.get" (id (evidence-type m)) (int 3) node)))))

    (define (recorded-arguments (m Module) (operation String) (record Wat)) (→ (List Wat)) (! mut)
      (let* ((params (● (function-signature m (operation-type m operation)) first))
             (type (arguments-type m operation params))
             (held (wat "ref.cast"
                        (ref-wat type)
                        (wat "struct.get" (id (yield-type m)) (int 2) record))))
        (map-indexed (lambda (index param) (wat "struct.get" (id type) (int index) held)) params)))

    ;; ---- Resuming ----

    ;; A continuation owns the frames saved inside a handle, innermost first,
    ;; and its delimiter node. Public resume/cancel renew their activation
    ;; graph under the caller's evidence before consuming those frames. A
    ;; nested handled frame uses that already renewed graph. The handler is
    ;; deep: a yield a yield aimed at the node runs the
    ;; handler again, in tail position, as the handle site would, even after
    ;; that handle has returned. A handle that any other yield leaves, at
    ;; its site or resumed, becomes one frame holding the continuation
    ;; inside it, so resuming the outer computation enters the handle again
    ;; too. Dropping `resume` detaches those frames and runs their cleanup
    ;; under the drop site's evidence before releasing the continuation.

    (define (continuation-type (m Module)) (→ String) (! mut)
      (match (known-type m "continuation")
        ((Some type) type)
        ((None)
         (let ((frames (frames-type m)))
           (register-type! m "continuation" "$continuation"
                           (wat "type" (id "$continuation")
                                (wat "struct"
                                     (wat "field" (wat "mut" (ref-wat frames)))
                                     (wat "field" (wat "mut" (evidence-ref m))))))))))

    ;; `resume`, a closure of the operation's answer to the handle's result.

    (define (resume-type (m Module) (base String)) (→ String) (! mut)
      (capture-type m base (list (Reference (continuation-type m)))))

    (define (resume-base (m Module) (operation String) (type Type)) (→ String) (! mut)
      (closure-type m (list (rep m (operation-result m operation))) (rep m type)))

    (define (resume-closure (m Module) (info Effect) (operation String) (type Type) (loc Loc))
      (→ Wat)
      (! mut)
      (let ((base (resume-base m operation type)))
        (wat "struct.new"
             (id (resume-type m base))
             (wat "i64.const" (int 1)) (code-of m (owner-noop m))
             (wat "ref.func" (id (resume-code m info operation type loc)))
             (resume-dropper m)
             (wat "local.get" (Word "$continuation")))))

    ;; A resume's dropper: a thunk closed over the continuation, whose code
    ;; rebases the continuation's handle onto the drop site's evidence,
    ;; just as resuming does. Its own handled effect stays discharged, while
    ;; other drops reach the handlers at the actual drop site. It detaches
    ;; the frames before dropping them. Dropping therefore performs no more than the
    ;; resume's own row, which the checker charged (capabilities.sld,
    ;; `trivial-rows`).

    (define (resume-dropper (m Module)) (→ Wat) (! mut)
      (wat "struct.new"
           (id (resume-dropper-type m))
           (wat "i64.const" (int 1)) (code-of m (owner-noop m))
           (wat "ref.func" (id (resume-dropper-code m)))
           (dropper-null)
           (wat "local.get" (Word "$continuation"))))

    (define (resume-dropper-type (m Module)) (→ String) (! mut)
      (capture-type m (dropper-type m) (list (Reference (continuation-type m)))))

    (define (cancel-continuation-helper (m Module)) (→ String) (! mut)
      (template-helper! m "cancel-continuation" ""
                        "(func {id} (param $continuation (ref null {continuation})) (param $ev (ref null {evidence})) (result i32)
  (local $frames (ref null {frames}))
  (local $frame (ref null {frame}))
  (local.set $frames (struct.get {continuation} 0 (local.get $continuation)))
  (struct.set {continuation} 0 (local.get $continuation) (ref.null {frames}))
  (block $done
    (loop $next
      (br_if $done (ref.is_null (local.get $frames)))
      (local.set $frame (struct.get {frames} 0 (local.get $frames)))
      (local.set $frames (struct.get {frames} 1 (local.get $frames)))
      (drop (call_ref {code} (local.get $frame) (ref.null any) (struct.get {frame} 1 (local.get $frame))))
      (drop (call {release} (struct.get {frame} 2 (local.get $frame)) (local.get $ev)))
      (br $next)))
  (return_call {release} (struct.get {continuation} 1 (local.get $continuation)) (local.get $ev)))"
                        (list (Pair "release" (release-helper m))
                              (Pair "code" (code-type m (frame-type m)))
                              (Pair "evidence" (evidence-type m))
                              (Pair "continuation" (continuation-type m))
                              (Pair "frames" (frames-type m))
                              (Pair "frame" (frame-type m)))))

    (define (resume-dropper-code (m Module)) (→ String) (! mut)
      (helper! m "drop" "resume"
               (lambda (name)
                 (push! (● m declared) name)
                 (Word (fill
                        "(func {id} (type {code}) (param $closure (ref null {base})) (param $ev (ref null {evidence})) (result i32)
  (local $continuation (ref null {continuation}))
  (local.set $continuation (struct.get {holder} 4 (ref.cast (ref null {holder}) (local.get $closure))))
  (call {activate} (local.get $continuation) (local.get $ev))
  (return_call {cancel} (local.get $continuation) (local.get $ev)))"
                        (list (Pair "id" name) (Pair "code" (code-type m (dropper-type m)))
                              (Pair "base" (dropper-type m)) (Pair "evidence" (evidence-type m))
                              (Pair "continuation" (continuation-type m))
                              (Pair "holder" (resume-dropper-type m))
                              (Pair "activate" (activate-helper m))
                              (Pair "cancel" (cancel-continuation-helper m))))))))

    ;; The code of an operation's `resume`: the handle again, run on the
    ;; boxed answer under the caller's evidence.

    (define (resume-code (m Module) (info Effect) (operation String) (type Type) (loc Loc))
      (→ String)
      (! mut)
      (helper! m "resume" (string-append operation " " (type-key type))
               (lambda (function-id)
                 (let* ((base (resume-base m operation type)) (resume (resume-type m base)))
                   (push! (● m declared) function-id)
                   (Word
                    (fill
                     "(func {id} (type {code}) (param $closure (ref null {base})) (param $ev (ref null {evidence})) (param $answer {answer}) (result {result})
  (local $continuation (ref null {continuation}))
  (local.set $continuation (struct.get {resume} 4 (ref.cast (ref null {resume}) (local.get $closure))))
  (drop (call {disarm} (local.get $closure) (local.get $ev)))
  (drop (call {release} (local.get $closure) (local.get $ev)))
  (call {activate} (local.get $continuation) (local.get $ev))
  (return_call {rehandle} (local.get $continuation) (local.get $ev) {boxed}))"
                     (list (Pair "continuation" (continuation-type m))
                           (Pair "disarm" (disarm-helper m base))
                           (Pair "release" (release-helper m)) (Pair "id" function-id)
                           (Pair "code" (code-type m base))
                           (Pair "base" base)
                           (Pair "evidence" (evidence-type m))
                           (Pair "answer"
                                 (wat->text (rep->wat (rep m (operation-result m operation)))))
                           (Pair "result" (wat->text (rep->wat (rep m type))))
                           (Pair "activate" (activate-helper m))
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

    (define (catch-helper (m Module) (catch Catch) (type Type)) (→ String) (! mut)
      (match catch
        ((Handling info loc) (catcher m info type loc))
        ((Forwarding info) (forwarder m info type))))

    (define (catch-prefix (catch Catch) (prefix String)) (→ String)
      (match catch
        ((Handling _ _) prefix)
        ((Forwarding _) (string-append "forward-" prefix))))

    (define (catch-key (catch Catch) (type Type)) (→ String)
      (let ((info (match catch ((Handling info _) info) ((Forwarding info) info))))
        (string-append (● info name) " " (type-key type))))

    ;; The handle again, for one catch and handle result type: the
    ;; continuation run on a boxed value under `$ev`, ending, if a yield
    ;; reaches it, in the handle's catch, in tail position.

    (define (rehandler (m Module) (catch Catch) (type Type)) (→ String) (! mut)
      (helper! m (catch-prefix catch "rehandle") (catch-key catch type)
               (lambda (function-id)
                 (Word
                  (fill
                   "(func {id} (param $continuation (ref null {continuation})) (param $ev (ref null {evidence})) (param $value anyref) (result {result})
  (local.set $value (call {continue} (local.get $continuation) (local.get $value)))
  (if {yielding} (then (return_call {catch} (struct.get {continuation} 1 (local.get $continuation)))))
  (drop (call {release} (struct.get {continuation} 1 (local.get $continuation)) (local.get $ev)))
  {unboxed})"
                   (list (Pair "release" (release-helper m)) (Pair "id" function-id)
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

    (define (handled-type (m Module)) (→ String) (! mut)
      (let ((name (capture-type m (frame-type m) (list (Reference (continuation-type m)))))) name))

    (define (handled-code (m Module) (catch Catch) (type Type)) (→ String) (! mut)
      (helper! m (catch-prefix catch "handled") (catch-key catch type)
               (lambda (function-id)
                 (let ((frame (frame-type m)) (continuation (continuation-type m)))
                   (push! (● m declared) function-id)
                   (Word
                    (fill
                     "(func {id} (type {code}) (param $frame (ref null {frame})) (param $value anyref) (result anyref)
  (local $continuation (ref null {continuation}))
  (local.set $continuation (struct.get {handled} 3 (ref.cast (ref null {handled}) (local.get $frame))))
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
                                                            (wat "struct.get"
                                                                 (id (evidence-type m))
                                                                 (int 4)
                                                                 (wat "struct.get"
                                                                      (id continuation)
                                                                      (int 1)
                                                                      (wat "local.get"
                                                                           (Word
                                                                            "$continuation"))))
                                                            (wat "local.get"
                                                                 (Word "$value")))))))))))))

    ;; A handled frame owns the installed node, not its outside context.
    ;; Enter its cancellation path just as `handled-code` enters its code:
    ;; under the current outside of that node. Keep that outside alive
    ;; independently while finalizers run and may rebase other continuations.
    (define (handled-cancel-code (m Module)) (→ String) (! mut)
      (helper! m "drop" "handled"
               (lambda (function-id)
                 (push! (● m declared) function-id)
                 (Word
                  (fill
                   "(func {id} (type {code}) (param $frame (ref null {frame})) (param $value anyref) (result anyref)
  (local $continuation (ref null {continuation}))
  (local $ev (ref null {evidence}))
  (local $outside (ref null {evidence}))
  (local.set $ev (struct.get {frame} 2 (local.get $frame)))
  (local.set $continuation (struct.get {handled} 3 (ref.cast (ref null {handled}) (local.get $frame))))
  (local.set $outside (ref.cast (ref null {evidence}) (call {retain}
    (struct.get {evidence} 4
      (struct.get {continuation} 1 (local.get $continuation))))))
  (drop (call {cancel} (local.get $continuation) (local.get $outside)))
  (drop (call {release} (local.get $outside) (local.get $ev)))
  (ref.null any))"
                   (list (Pair "id" function-id) (Pair "code" (code-type m (frame-type m)))
                         (Pair "frame" (frame-type m)) (Pair "evidence" (evidence-type m))
                         (Pair "continuation" (continuation-type m))
                         (Pair "handled" (handled-type m))
                         (Pair "retain" (retain-helper m)) (Pair "release" (release-helper m))
                         (Pair "cancel" (cancel-continuation-helper m))))))))

    ;; Saves the handle at `node`, which a yield is leaving, as one frame
    ;; in place of the frames saved inside its body.

    (define (enclose (m Module) (catch Catch) (type Type) (node Wat)) (→ Wat) (! mut)
      (wat "call" (id (enclose-helper m)) node (wat "ref.func" (id (handled-code m catch type)))))

    (define (enclose-helper (m Module)) (→ String) (! mut)
      (template-helper! m "control" "enclose"
                        "(func {id} (param $node (ref null {evidence})) (param $code (ref null {code}))
  (local $record (ref null {yield}))
  (local $continuation (ref null {continuation}))
  (local.set $record (global.get {yielding}))
  (local.set $continuation (struct.new {continuation} (call {reverse} (struct.get {yield} 3 (local.get $record))) (local.get $node)))
  (struct.set {yield} 3 (local.get $record)
    (struct.new {frames}
      (struct.new {handled} (local.get $code) (ref.func {cancel})
        (ref.cast (ref null {evidence}) (call {retain} (local.get $node))) (local.get $continuation))
      (ref.null {frames}))))"
                        (list (Pair "retain" (retain-helper m))
                              (Pair "evidence" (evidence-type m))
                              (Pair "code" (code-type m (frame-type m)))
                              (Pair "yield" (yield-type m))
                              (Pair "yielding" (yielding m))
                              (Pair "frames" (frames-type m))
                              (Pair "handled" (handled-type m))
                              (Pair "continuation" (continuation-type m))
                              (Pair "reverse" (reverse-helper m))
                              (Pair "cancel" (handled-cancel-code m)))))

    ;; Runs an activated continuation and takes the frames out, so that neither the continuation nor
    ;; `resume` holds them while they run. Then each frame runs in turn,
    ;; innermost first, on the value the one before produced. When a frame
    ;; yields, the frames after it are saved on the record in turn, as if
    ;; the yield were leaving them, and the loop returns with the record
    ;; set, so its caller leaves too. A handle among the frames is one
    ;; frame that runs the frames inside it itself, so a yield aimed at
    ;; that handle is caught there and never passes through this loop.

    (define (continue-helper (m Module)) (→ String) (! mut)
      (let ((frame (frame-type m)))
        (template-helper! m "control" "continue"
                          "(func {id} (param $continuation (ref null {continuation})) (param $value anyref) (result anyref)
  (local $frames (ref null {frames}))
  (local $frame (ref null {frame}))
  (local.set $frames (struct.get {continuation} 0 (local.get $continuation)))
  (struct.set {continuation} 0 (local.get $continuation) (ref.null {frames}))
  (loop $next
    (if (ref.is_null (local.get $frames)) (then (return (local.get $value))))
    (local.set $frame (struct.get {frames} 0 (local.get $frames)))
    (local.set $frames (struct.get {frames} 1 (local.get $frames)))
    (if (ref.is_null (global.get {yielding}))
      (then (local.set $value (call {run} (local.get $frame) (local.get $value))))
      (else (call {push} (local.get $frame))))
    (br $next))
  (unreachable))"
                          (list (Pair "run" (frame-runner m))
                                (Pair "continuation" (continuation-type m))
                                (Pair "evidence" (evidence-type m))
                                (Pair "frames" (frames-type m))
                                (Pair "frame" frame)
                                (Pair "code" (code-type m frame))
                                (Pair "yielding" (yielding m))
                                (Pair "push" (push-helper m))))))

    (define (reverse-helper (m Module)) (→ String) (! mut)
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
    ;; operations reach that evidence. The builtin effects, mut and host,
    ;; which no evidence carries, need no node.

    (define (forwarded-effects (m Module) (operation String)) (→ (List Effect))
      (match (program-value (program-of m) operation)
        ((Some (Operation effect scheme))
         (map (lambda (label) (program-effect (program-of m) label))
              (filter (lambda (label) (table-contains? (● (program-of m) effects) label))
                      (operation-latent effect scheme))))
        (_ (panic "internal error: not an operation"))))

    ;; The performer's locals for forwarding: the result, and a node per
    ;; forwarded effect.

    (define (forwarding-locals (m Module) (operation String) (result Rep)) (→ (List Wat)) (! mut)
      (let ((effects (forwarded-effects m operation)))
        (if (null? effects)
            (Nil)
            (Cons (wat "local" (Word "$forwarded") (rep->wat result))
                  (map (lambda (index) (wat "local" (latent-local index) (evidence-ref m)))
                       (iota (length effects)))))))

    (define (latent-local (index I64)) (→ Wat)
      (Word (string-append "$latent." (i64->string index))))

    ;; At the effect's node: a forwarding node per forwarded effect, each
    ;; over the one before and the first over the evidence outside the
    ;; node; the implementation called under the last; then the catch of
    ;; each node of a control effect, innermost first.

    (define (forwarding-call (m Module)
                             (info Effect)
                             (operation String)
                             (names (List String))
                             (params (List Rep))
                             (result Rep))
      (→ (List Wat))
      (! mut)
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
               (reverse (map-indexed (lambda (index effect)
                                       (wat "drop" (wat "call" (id (release-helper m))
                                                        (wat "local.get" (latent-local index))
                                                        (wat "local.get" (Word "$ev"))))) effects))
               (list (wat "return" (wat "local.get" (Word "$forwarded"))))))))

    (define (forwarding-catches (m Module) (effects (List Effect)) (type Type))
      (→ (List Wat))
      (! mut)
      (concatenate (map-indexed (lambda (index effect)
                                  (if (null? (● effect control))
                                      (Nil)
                                      (list (wat "if" (yielding? m)
                                                 (wat "then" (wat "local.set" (Word "$forwarded")
                                                                  (wat "call"
                                                                       (id
                                                                        (forwarder m effect type))
                                                                       (retain-evidence m
                                                                                        (wat
                                                                                         "local.get"
                                                                                         (latent-local
                                                                                          index))))))))))
                                effects)))

    ;; A forwarding node for an effect over `outside`, whose handler sends
    ;; each of the effect's operations to the performer's evidence, `$ev`.

    (define (forwarding-node (m Module) (info Effect) (outside Wat)) (→ Wat) (! mut)
      (let ((origin (wat "local.get" (Word "$ev"))))
        (new-evidence m (● info name)
                      (wat* "struct.new" (Cons (id (handler-type m (● info name)))
                                               (map (lambda (operation)
                                                      (forwarding-field m info operation origin))
                                                    (● info operations))))
                      outside #t origin)))

    (define (forwarding-field (m Module) (info Effect) (operation String) (evidence Wat))
      (→ Wat)
      (! mut)
      (if (member? operation (● info control)) (retain-evidence m evidence)
          (let ((holder (forwarding-closure m operation)))
            (wat "struct.new" (id holder)
                 (wat "i64.const" (int 1)) (code-of m (context-closure-destructor m holder))
                 (wat "ref.func" (id (forwarding-code m info operation))) (dropper-null)
                 (retain-evidence m evidence)))))

    ;; An ordinary operation's closure that holds the evidence to perform it
    ;; under.

    (define (forwarding-closure (m Module) (operation String)) (→ String) (! mut)
      (let ((signature (function-signature m (operation-type m operation))))
        (capture-type m
                      (closure-type m (● signature first) (● signature second))
                      (list (evidence-rep m)))))

    ;; Its code: the operation performed under the evidence it holds.

    (define (forwarding-code (m Module) (info Effect) (operation String)) (→ String) (! mut)
      (helper! m "forward" operation
               (lambda (function-id)
                 (let* ((signature (function-signature m (operation-type m operation)))
                        (closure (forwarding-closure m operation))
                        (call (wat* "call" (Cons (id (performer m (● info name) operation))
                                                 (Cons (held-capture closure 1)
                                                       (argument-reads signature))))))
                   (code-function m
                                  function-id
                                  signature
                                  (context-call-body m
                                                     (closure-type m
                                                                   (● signature first)
                                                                   (● signature second))
                                                     (● signature second)
                                                     call))))))

    ;; The function of a closure's code, which the module declares for
    ;; `ref.func`: the closure, the evidence and the arguments, read by
    ;; `argument-reads`, then `body`.

    (define (code-function (m Module)
                           (function-id String)
                           (signature (Pair (List Rep) Rep))
                           (body (List Wat)))
      (→ Wat)
      (! mut)
      (let ((base (closure-type m (● signature first) (● signature second))))
        (push! (● m declared) function-id)
        (wat* "func"
              (concatenate (list (list (id function-id)
                                       (wat "type" (id (code-type m base)))
                                       (wat "param"
                                            (Word "$closure")
                                            (ref-wat base))
                                       (evidence-param m))
                                 (map (lambda (pair)
                                        (wat "param"
                                             (id (● pair first))
                                             (rep->wat (● pair second))))
                                      (zip (argument-names signature) (● signature first)))
                                 (list (wat "result" (rep->wat (● signature second))))
                                 body)))))

    (define (argument-names (signature (Pair (List Rep) Rep))) (→ (List String))
      (map (lambda (index) (string-append "$argument." (i64->string index)))
           (iota (length (● signature first)))))

    (define (argument-reads (signature (Pair (List Rep) Rep))) (→ (List Wat))
      (map (lambda (name) (wat "local.get" (id name))) (argument-names signature)))

    ;; A field of the closure a code function runs, which is of the subtype
    ;; `closure`; field 0 is the code.

    (define (held-capture (closure String) (index I64)) (→ Wat)
      (wat "struct.get"
           (id closure)
           (int (+ index 3))
           (wat "ref.cast"
                (ref-wat closure)
                (wat "local.get" (Word "$closure")))))

    ;; A forwarding node's catch: a yield aimed at the node is re-aimed at
    ;; the performer's handler. Either way the yield leaves, and the node's
    ;; catch is saved as a frame (see Resuming).

    (define (forwarder (m Module) (info Effect) (type Type)) (→ String) (! mut)
      (helper! m "forward-catch" (string-append (● info name) " " (type-key type))
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
                        (default-value (rep m type)))))))

    ;; Sets the record, aimed at a forwarding node, to aim at the first node
    ;; for the node's effect in the performer's evidence, which the node's
    ;; handler holds, with the same operation, arguments and frames.

    (define (retargeter (m Module) (info Effect)) (→ String) (! mut)
      (template-helper! m "retarget" (● info name)
                        "(func {id} (param $node (ref null {evidence}))
  (local $record (ref null {yield}))
  (local $target (ref null {evidence}))
  (local.set $record (global.get {yielding}))
  (local.set $target (ref.cast (ref null {evidence}) (struct.get {handler} {index} (ref.cast (ref null {handler}) (struct.get {evidence} 3 (local.get $node))))))
  (loop $walk
    (if (ref.is_null (local.get $target)) (then (call {panic} {message}) (unreachable)))
    (if (i32.eq (struct.get {evidence} 2 (local.get $target)) {label})
      (then (global.set {yielding} (struct.new {yield} (local.get $target) (struct.get {yield} 1 (local.get $record))
                                     (struct.get {yield} 2 (local.get $record)) (struct.get {yield} 3 (local.get $record))))
            (return)))
    (local.set $target (struct.get {evidence} 4 (local.get $target)))
    (br $walk)))"
                        (list (Pair "evidence" (evidence-type m))
                              (Pair "yield" (yield-type m))
                              (Pair "yielding" (yielding m))
                              (Pair "handler" (handler-type m (● info name)))
                              (Pair "index"
                                    (i64->string (operation-index info (first-control info))))
                              (Pair "panic" (panic-helper m))
                              (Pair "message"
                                    (wat->text (string-literal m
                                                               (string-append "unhandled effect "
                                                                              (short-name
                                                                               (● info name))))))
                              (Pair "label" (wat->text (effect-label (● info name)))))))

    (define (first-control (info Effect)) (→ String)
      (match (● info control)
        ((Cons operation _) operation)
        ((Nil) (panic "internal error: not a control effect"))))

    ;; ---- Inherited handlers ----

    ;; `inherit-handlers` closes a one-shot procedure over the handlers in
    ;; scope where it is called. The FnOnce it makes is a closure holding
    ;; that evidence and the procedure, moved in; its code ignores the
    ;; evidence it is called with and tail-calls the procedure under the
    ;; evidence it holds. So whoever calls the FnOnce, the procedure's
    ;; operations reach the handlers of the place it
    ;; was closed. A `resume` closed this way resumes under them too, since
    ;; resuming rebases its handler's node onto the evidence it is called
    ;; with (see Resuming). Nothing yields through it: control.sld refuses a
    ;; procedure that may yield to a control effect.

    (define (inherited (fn Fn) (type Type) (procedure Wat)) (→ Wat) (! mut)
      (match type
        ((TCon "FnOnce" (Cons procedure-type (Nil)))
         (let* ((m (● fn module)) (signature (function-signature m procedure-type))
                (base (closure-type m (● signature first) (● signature second)))
                (holder (inherit-closure m signature))
                (saved (declare-temp! fn (ref-wat base))))
           (wat "block" (wat "result" (ref-wat holder))
                (wat "local.set" (id saved) procedure)
                (wat "struct.new" (id holder)
                     (wat "i64.const" (int 1)) (code-of m (context-closure-destructor m holder))
                     (wat "ref.func" (id (inherit-code m signature)))
                     (inherited-dropper fn base (wat "local.get" (id saved)))
                     (retain-evidence m (● fn evidence)) (wat "local.get" (id saved))))))
        (_ (panic "internal error: inherit-handlers makes a FnOnce"))))

    ;; Cleanup runs under the same saved handlers as the work. Capture the
    ;; original dropper, not its owner closure, so cleanup never retains
    ;; the managed wrapper whose resources it releases.

    (define (inherited-dropper (fn Fn) (base String) (procedure Wat)) (→ Wat) (! mut)
      (let* ((m (● fn module))
             (holder (capture-type m (dropper-type m) (list (evidence-rep m) (Reference base)))))
        (wat "struct.new" (id holder)
             (wat "i64.const" (int 1)) (code-of m (context-closure-destructor m holder))
             (wat "ref.func" (id (inherited-dropper-code m base holder))) (dropper-null)
             (retain-evidence m (● fn evidence)) procedure)))

    ;; Closures of one signature share the subtype that holds the evidence
    ;; and the procedure.

    (define (inherit-closure (m Module) (signature (Pair (List Rep) Rep))) (→ String) (! mut)
      (let ((base (closure-type m (● signature first) (● signature second))))
        (capture-type m base (list (evidence-rep m) (Reference base)))))

    (define (inherit-code (m Module) (signature (Pair (List Rep) Rep))) (→ String) (! mut)
      (let ((base (closure-type m (● signature first) (● signature second)))
            (closure (inherit-closure m signature)))
        (helper! m "inherit" (substring base 1 (string-length base))
                 (lambda (function-id)
                   (code-function m function-id signature
                                  (context-call-body m
                                                     (closure-type m
                                                                   (● signature first)
                                                                   (● signature second))
                                                     (● signature second)
                                                     (closure-call-wat m
                                                                       base
                                                                       (held-capture closure 2)
                                                                       (Cons
                                                                        (held-capture closure 1)
                                                                        (argument-reads signature))
                                                                       #f)))))))

    ;; Compiler-generated context closures own the evidence in field 4.
    ;; Their one-shot procedure, when present, transfers to either invocation
    ;; or cancellation; it is never duplicated by the wrapper's destructor.
    (define (context-closure-destructor (m Module) (holder String)) (→ String) (! mut)
      (helper! m "context-closure-drop" holder
               (lambda (name)
                 (wat "func" (id name) (wat "type" (Word "$owner.drop"))
                      (wat "param" (Word "$owner") (ref-wat (owner-type m)))
                      (evidence-param m) (wat "result" (Word "i32"))
                      (wat "return_call" (id (release-helper m))
                           (wat "struct.get" (id holder) (int 4)
                                (wat "ref.cast"
                                     (ref-wat holder)
                                     (wat "local.get" (Word "$owner"))))
                           (wat "local.get" (Word "$ev")))))))

    (define (context-call-body (m Module) (base String) (result Rep) (call Wat))
      (→ (List Wat))
      (! mut)
      (list (wat "local" (Word "$result") (rep->wat result))
            (disarm-dropper m
                            base
                            (wat "local.get" (Word "$closure"))
                            (wat "local.get" (Word "$ev")))
            (wat "local.set" (Word "$result") call)
            (wat "drop" (wat "call" (id (release-helper m)) (wat "local.get" (Word "$closure"))
                             (wat "local.get" (Word "$ev"))))
            (wat "local.get" (Word "$result"))))

    (define (inherited-dropper-code (m Module) (base String) (holder String)) (→ String) (! mut)
      (helper! m "inherit-drop" holder
               (lambda (name)
                 (code-function m name (Pair (Nil) (Scalar "i32"))
                                (list (wat "return_call" (id (drop-once-helper m base))
                                           (held-capture holder 2) (held-capture holder 1)))))))

    (define (drop-once-helper (m Module) (base String)) (→ String) (! mut)
      (template-helper! m "drop-once" base
                        "(func {id} (param $closure (ref null {base})) (param $ev (ref null {evidence})) (result i32)
  (local $dropper (ref null {dropper}))
  (local.set $dropper (struct.get {base} 3 (local.get $closure)))
  (struct.set {base} 3 (local.get $closure) (ref.null {dropper}))
  (if (i32.eqz (ref.is_null (local.get $dropper)))
    (then (drop (call {invoke} (local.get $dropper) (local.get $ev)))))
  (return_call {release} (local.get $closure) (local.get $ev)))"
                        (list (Pair "base" base) (Pair "evidence" (evidence-type m))
                              (Pair "dropper" (dropper-type m))
                              (Pair "invoke" (dropper-call-helper m))
                              (Pair "release" (release-helper m)))))

    ;; ---- Primitives ----

    ;; Primitives with a single Wasm instruction.

    (define instruction-primitives (→ (List (Pair String String)))
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

    (define (index (value Wat)) (→ Wat)
      (wat "i32.wrap_i64" value))

    (define (emit-primitive (fn Fn) (name String) (args (List Expr)) (type Type))
      (→ (List Wat))
      (! mut)
      (let ((operation (substring name 5 (string-length name))))
        (match (assoc-ref instruction-primitives operation)
          ((Some instruction) (list (wat* instruction (emit-args fn args))))
          ((None)
           (special-primitive fn
                              operation
                              args
                              (emit-args fn args)
                              (map (lambda (record) (● record type)) args)
                              type)))))

    ;; Primitive calls evaluate operands once, then operate on the stable holder.

    (define (special-primitive (fn Fn)
                               (operation String)
                               (args (List Expr))
                               (code (List Wat))
                               (types (List Type))
                               (type Type))
      (→ (List Wat))
      (! mut)
      (let* ((m (● fn module))
             (arg (lambda (n) (list-ref code n)))
             (sequence (lambda (t) (sequence-raw-type m t)))
             (data (lambda (n) (sequence-data m (list-ref types n) (arg n)))))
        (case operation
          (("rc-new") (list (new-rc m type (arg 0) (arg 1))))
          (("rc-get") (list (rc-payload m (first-type types) (arg 0))))
          (("rc-downgrade") (list (arg 0)))
          (("weak-rc-upgrade") (list (upgrade-weak fn type (arg 0))))
          (("current-closure") (list (wat "local.get" (Word "$closure"))))
          (("retain" "pattern-retain")
           (list (if (uncounted-self? fn (first-arg args)) (arg 0)
                     (retain-value m (first-type types) (arg 0)))))
          (("release" "discard")
           (list (if (uncounted-self? fn (first-arg args)) (discard-value (arg 0))
                     (release-value m (first-type types) (arg 0) (● fn evidence)))))
          (("unit") (list (wat "i32.const" (int 0))))
          (("once") (list (arg 0)))
          (("call-once") (list (wat "call" (id (call-once-helper m)) (arg 0) (● fn evidence))))
          (("inherit-handlers" "inherit-handlers-1") (list (inherited fn type (arg 0))))
          (("drop-once") (drop-once fn (first-arg args) (arg 0)))
          (("once-dropping") (list (once-dropping fn (first-arg args) (arg 0) (arg 1))))
          (("with-cleanup") (panic "internal error: cleanup marks only a let's value"))
          (("unsafe-total") (closure-call fn (first-arg args) (Nil) #f))
          (("unsafe-cast") (list (funcref-closure m type (arg 0))))

          (("panic") (list (wat* "call" (Cons (id (panic-helper m)) code)) (wat "unreachable")))
          (("bool->i32" "char->i32" "i32->char" "u8->i32") code)
          (("i32->u8") (list (wat "i32.and" (arg 0) (wat "i32.const" (int 255)))))
          (("i32->bool") (list (wat "i32.ne" (arg 0) (wat "i32.const" (int 0)))))
          (("string->vector")
           (list (sequence-owned m type (wat "call" (id (copy-helper m (sequence type))) (arg 0)))))
          (("vector->string") (list (wat "call" (id (copy-helper m (sequence type))) (arg 0))))
          (("string-length" "vector-length")
           (list (wat "i64.extend_i32_u" (sequence-length m (first-type types) (arg 0)))))
          (("string-ref")
           (list (wat "array.get" (id (sequence (first-type types))) (arg 0) (index (arg 1)))))
          (("vector-ref")
           (list (wat "call"
                      (id (vector-read-helper m (sequence-element (first-type types))))
                      (arg 0)
                      (arg 1))))
          (("set!")
           (append (place-write fn (first-arg args) (list-ref args 1))
                   (list (wat "i32.const" (int 0)))))
          (("replace!") (list (place-swap fn (first-arg args) (list-ref args 1))))
          (("vector-set!")
           (list (wat "call" (id (vector-write-helper m (sequence-element (first-type types))))
                      (arg 0) (arg 1) (arg 2) (● fn evidence))))
          (("vector")
           (list (sequence-owned m type (wat "array.new_fixed" (id (sequence type)) (int 0)))))
          (("make-string" "make-vector")
           (list (sequence-copied m type (wat "array.new" (id (sequence type)) (arg 1)
                                              (wat "call" (id (size-helper m)) (arg 0))))))
          (("string-append" "vector-append")
           (list (wat "call" (id (sequence-append-helper m type)) (arg 0) (arg 1))))
          (("substring" "subvector")
           (list (wat "call" (id (sequence-slice-helper m type)) (arg 0) (arg 1) (arg 2))))
          (("vector-set")
           (list (wat "call" (id (vector-replace-helper m (sequence-element type)))
                      (arg 0) (arg 1) (arg 2) (● fn evidence))))
          (("vector-copy")
           (list (wat "call" (id (vector-copy-helper m (sequence-element type))) (arg 0))))
          (("vector-copy!")
           (list (wat "call" (id (vector-copy-into-helper m (sequence-element (first-type types))))
                      (arg 0) (arg 1) (arg 2) (arg 3) (arg 4) (● fn evidence))))
          (("string=?") (list (wat* "call" (Cons (id (string-equal-helper m)) code))))
          (("string-compare") (list (wat* "call" (Cons (id (string-compare-helper m)) code))))
          (("vector-generate" "string-generate")
           (list (sequence-owned m type
                                 (wat* "call"
                                       (Cons
                                        (id (generate-helper m (sequence type) (list-ref types 1)))
                                        (append code (list (● fn evidence))))))))
          (else (panic (string-append "internal error: unknown primitive " operation))))))

    ;; `call-once` calls the thunk it is given, which is its own closure.

    (define (call-once-helper (m Module)) (→ String) (! mut)
      (let ((closure (closure-type m (Nil) (Scalar "i32"))))
        (template-helper! m "call-once" ""
                          "(func {id} (param $closure (ref null {closure})) (param $ev (ref null {evidence})) (result i32)
  (return_call_ref {code} (local.get $closure) (local.get $ev) (struct.get {closure} 2 (local.get $closure))))"
                          (list (Pair "closure" closure)
                                (Pair "code" (code-type m closure))
                                (Pair "evidence" (evidence-type m))))))

    ;; ---- Droppers ----

    ;; Dropping a FnOnce unrun runs the dropper its closure carries, if any,
    ;; under the dropper's caller's handlers: what it performs is within the
    ;; FnOnce's row, which the checker charged where the drop is written.

    (define (drop-once (fn Fn) (value Expr) (code Wat)) (→ (List Wat)) (! mut)
      (list
       (wat "call" (id (drop-once-helper (● fn module) (reference-type (fn-rep fn (● value type)))))
            code (● fn evidence))))

    (define (call-dropper (m Module) (dropper Wat) (evidence Wat)) (→ Wat) (! mut)
      (wat "call" (id (dropper-call-helper m)) dropper evidence))

    (define (dropper-call-helper (m Module)) (→ String) (! mut)
      (let ((base (dropper-type m)))
        (template-helper! m "invoke-dropper" ""
                          "(func {id} (param $dropper (ref null {base})) (param $ev (ref null {evidence})) (result i32)
  (drop (call_ref {code} (local.get $dropper) (local.get $ev) (struct.get {base} 2 (local.get $dropper))))
  (return_call {release} (local.get $dropper) (local.get $ev)))"
                          (list (Pair "base" base) (Pair "code" (code-type m base))
                                (Pair "evidence" (evidence-type m))
                                (Pair "release" (release-helper m))))))

    ;; `once` of a lambda with linear captures: the closure, with the
    ;; dropper of its captures stored beside its code.

    (define (once-dropping (fn Fn) (value Expr) (closure Wat) (dropper Wat)) (→ Wat) (! mut)
      (let* ((base (reference-type (fn-rep fn (● value type))))
             (temp (declare-temp! fn (ref-wat base))))
        (wat "block"
             (wat "result" (ref-wat base))
             (wat "local.set" (id temp) closure)
             (wat "struct.set" (id base) (int 3) (wat "local.get" (id temp)) dropper)
             (wat "local.get" (id temp)))))

    ;; ---- Runtime helpers ----

    ;; Helpers are fixed WAT, written once per array type and filled in from
    ;; a template. A new array needs an initial element, so empty results
    ;; come from `array.new_fixed`.

    (define (helper! (m Module) (prefix String) (key String) (make (Fn String → Wat ! mut)))
      (→ String)
      (! mut)
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
      (! mut)
      (helper! m
               prefix
               key
               (lambda (function-id)
                 (Word (fill template (Cons (Pair "id" function-id) bindings))))))

    (define (append-helper (m Module) (array String)) (→ String) (! mut)
      (template-helper! m "append" array
                        "(func {id} (param $a (ref null {array})) (param $b (ref null {array})) (result (ref null {array}))
  (local $result (ref null {array})) (local $size i32)
  (local.set $size (call {size} (i64.add (i64.extend_i32_u (array.len (local.get $a))) (i64.extend_i32_u (array.len (local.get $b))))))
  (local.set $result (array.new_default {array} (local.get $size)))
  (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
  (array.copy {array} {array} (local.get $result) (array.len (local.get $a)) (local.get $b) (i32.const 0) (array.len (local.get $b)))
  (local.get $result))" (list (Pair "array" array) (Pair "size" (size-helper m)))))

    (define (slice-helper (m Module) (array String)) (→ String) (! mut)
      (template-helper! m "slice" array
                        "(func {id} (param $a (ref null {array})) (param $start i64) (param $end i64) (result (ref null {array}))
    (local $result (ref null {array})) (local $length i32)
    (local.set $length (i32.wrap_i64 (i64.sub (local.get $end) (local.get $start))))
    (if (i32.eqz (local.get $length)) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} ({get} {array} (local.get $a) (i32.wrap_i64 (local.get $start))) (local.get $length)))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.wrap_i64 (local.get $start))
                (local.get $length))
    (local.get $result))"
                        (list (Pair "array" array) (Pair "get" (array-get array)))))

    (define (copy-helper (m Module) (array String)) (→ String) (! mut)
      (template-helper! m "copy" array
                        "(func {id} (param $a (ref null {array})) (result (ref null {array}))
    (local $result (ref null {array}))
    (if (i32.eqz (array.len (local.get $a))) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} ({get} {array} (local.get $a) (i32.const 0)) (array.len (local.get $a))))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
    (local.get $result))"
                        (list (Pair "array" array) (Pair "get" (array-get array)))))

    (define (set-helper (m Module) (array String) (element Rep)) (→ String) (! mut)
      (template-helper! m "set" array
                        "(func {id} (param $a (ref null {array})) (param $index i64) (param $value {element}) (result (ref null {array}))
    (local $result (ref null {array}))
    (local.set $result (array.new {array} (local.get $value) (array.len (local.get $a))))
    (array.copy {array} {array} (local.get $result) (i32.const 0) (local.get $a) (i32.const 0) (array.len (local.get $a)))
    (array.set {array} (local.get $result) (i32.wrap_i64 (local.get $index)) (local.get $value))
    (local.get $result))"
                        (list (Pair "array" array)
                              (Pair "element" (wat->text (rep->wat element))))))

    (define (generate-helper (m Module) (array String) (function-type Type)) (→ String) (! mut)
      (let* ((signature (function-signature m function-type))
             (base (closure-type m (● signature first) (● signature second))))
        (template-helper! m "generate" (string-append array " " base)
                          "(func {id} (param $count i64) (param $f (ref null {base})) (param $ev (ref null {evidence})) (result (ref null {array}))
    (local $result (ref null {array})) (local $length i32) (local $index i32)
    (local.set $length (call {size} (local.get $count)))
    (if (i32.eqz (local.get $length)) (then (return (array.new_fixed {array} 0))))
    (local.set $result (array.new {array} (call_ref {code} (ref.cast (ref null {base}) (call {retain} (local.get $f))) (local.get $ev) (i64.const 0) (struct.get {base} 2 (local.get $f)))
                                  (local.get $length)))
    (local.set $index (i32.const 1))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $index) (local.get $length)))
        (array.set {array} (local.get $result) (local.get $index)
                   (call_ref {code} (ref.cast (ref null {base}) (call {retain} (local.get $f))) (local.get $ev) (i64.extend_i32_u (local.get $index)) (struct.get {base} 2 (local.get $f))))
        (local.set $index (i32.add (local.get $index) (i32.const 1)))
        (br $next)))
    (local.get $result))"
                          (list (Pair "size" (size-helper m))
                                (Pair "retain" (retain-helper m))
                                (Pair "array" array)
                                (Pair "base" base)
                                (Pair "code" (code-type m base))
                                (Pair "evidence" (evidence-type m))))))

    (define (string-equal-helper (m Module)) (→ String) (! mut)
      (let* ((array (array-type m (Scalar "i32"))) (compare (string-compare-helper m)))
        (template-helper! m "string-equal" ""
                          "(func {id} (param $a (ref null {array})) (param $b (ref null {array})) (result i32)
    (i32.eqz (call {compare} (local.get $a) (local.get $b))))"
                          (list (Pair "array" array) (Pair "compare" compare)))))

    ;; Lexicographic comparison by Unicode scalar: -1, 0 or 1.

    (define (string-compare-helper (m Module)) (→ String) (! mut)
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
                        (list (Pair "array" (array-type m (Scalar "i32"))))))

    ;; Strings transfer UTF32 scalars and return their count. Bytes transfer
    ;; a little-endian u32 length followed by packed bytes and return its
    ;; address, so a leaf host import reads memory without reentering Wasm.
    ;; stage reserves four bytes per slot: count+1 safely holds either layout.

    (define (stage-helper (m Module) (bytes? Bool)) (→ String) (! mut)
      (let ((type (if bytes? (TCon "Vector" (list (TCon "U8" (Nil)))) (TCon "String" (Nil))))
            (stage (import! m
                            (Import "snail.core.support" "snail:io/stage")
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
                          (list (Pair "type" (wat->text (rep->wat (rep m type))))
                                (Pair "data"
                                      (wat->text
                                       (sequence-data m type (wat "local.get" (Word "$value")))))
                                (Pair "length"
                                      (wat->text
                                       (sequence-length m type (wat "local.get" (Word "$value")))))
                                (Pair "array" (array-type m (Scalar (if bytes? "i8" "i32"))))
                                (Pair "stage" stage)
                                (Pair "guard"
                                      (if bytes?
                                          "(if (i32.eq (local.get $length) (i32.const -1)) (then (unreachable)))"
                                          ""))
                                (Pair "capacity"
                                      (if bytes?
                                          "(i32.add (local.get $length) (i32.const 1))"
                                          "(local.get $length)"))
                                (Pair "header"
                                      (if bytes?
                                          "(i32.store (local.get $address) (local.get $length))"
                                          ""))
                                (Pair "store" (if bytes? "i32.store8" "i32.store"))
                                (Pair "get" (if bytes? "array.get_u" "array.get"))
                                (Pair "offset" (if bytes? "4" "0"))
                                (Pair "shift" (if bytes? "0" "2"))
                                (Pair "result"
                                      (if bytes?
                                          "(local.get $address)"
                                          "(local.get $length)"))))))

    ;; Sends the message to the runtime one scalar at a time, then stops.

    (define (panic-helper (m Module)) (→ String) (! mut)
      (let ((character (import! m
                                (Import "snail.core.support" "snail:panic/character")
                                (list (Scalar "i32"))
                                (None)))
            (raise (import! m (Import "snail.core.support" "snail:panic/raise") (Nil) (None))))
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
                          (list (Pair "array" (array-type m (Scalar "i32")))
                                (Pair "character" character)
                                (Pair "raise" raise)))))

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
                               empty-table definitions))
             (names (list->vector (list-sort string<? (map type-definition-name definitions))))
             (numbers
              (fold-left (lambda (table index) (table-set table (vector-ref names index) index))
                         empty-table
                         (iota (vector-length names)))))
        (map (lambda (component)
               (group-wat named (map (lambda (index) (vector-ref names index)) component)))
             (strong-components
              (vector-map (lambda (name) (type-edges named numbers name)) names)))))

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

    ;; The prepared input contains functions and initializer functions,
    ;; explicit host exports and an optional program entry. Bindings preserve
    ;; which functions initialize cached values rather than being source code.

    (define (emit-module (prepared Prepared)) (→ Wat) (! mut)
      (let ((m (new-module (● prepared declarations))))
        (for-each (lambda (item)
                    (match item
                      ((Define name value)
                       (match (definition-of m name)
                         ((Some binding)
                          (if (● binding function?) (emit-function! m name value)
                              (emit-lazy-value! m name value)))
                         ((None) (panic "internal error: an emitted definition has no binding"))))
                      (_ (panic "internal error: a prepared function must be a definition"))))
                  (● prepared definitions))
        (for-each (lambda (item) (emit-exposure! m item)) (● prepared exposed))
        (match (● prepared entry) ((Some name) (emit-main! m name)) (_ (unit)))
        (for-each (lambda (name) (export-definition! m name)) (● prepared exported))
        (module-wat m)))

    (define (new-module (declarations Declarations)) (→ Module)
      (Module declarations
              empty-table 65536 (Nil) (Nil) (Nil)
              (Nil) (Nil) (Nil) (Nil)
              empty-table empty-table))

    (define (module-callees (m Module)) (→ (Option Callees))
      (if (null? (● (● m declarations) control))
          (None)
          (Some (declaration-callees (● m declarations)))))

    (define (emit-main! (m Module) (name String)) (→ Unit) (! mut)
      (push-function! m "$main.body"
                      (wat "func" (id "$main.body") (wat "export" (wat-string "main:body"))
                           (evidence-param m) (wat "result" (Word "i32"))
                           (wat "return_call" (id (wasm-id name)) (wat "local.get" (id "$ev")))))
      (push-function! m "$main"
                      (wat "func" (id "$main") (wat "export" (wat-string "main"))
                           (wat "result" (Word "i32"))
                           (wat "return_call" (id "$main.body") (evidence-none m)))))

    (define (export-definition! (m Module) (name String)) (→ Unit) (! mut)
      (match (definition-of m name)
        ((Some definition)
         (push! (● m exports)
                (wat "export" (wat-string name)
                     (wat "func" (id (wasm-id name))))))
        ((None) (panic (string-append "internal error: nothing to export for " name)))))

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
           (sort-named (map (lambda (declaration) (Pair (declaration-id declaration) declaration))
                            declarations))))

    (define (sort-named (entries (List (Pair String A))))
      (→ (List (Pair String A)))
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (list-sort (lambda (a b) (string<? (● a first) (● b first))) entries))

    ;; Host exposures are adapters around ordinary functions. Counted
    ;; results transfer a credit with an explicit companion for its release.
    (define (emit-exposure! (m Module) (item Item)) (→ Unit) (! mut)
      (match item
        ((Expose name symbol _)
         (match (definition-of m name)
           ((Some definition)
            (unless (● definition function?)
              (panic "internal error: an exposed function is not a lambda"))
            (push! (● m exports)
                   (wat "export" (wat-string symbol)
                        (wat "func" (id (exposed-function m name (● definition type))))))
            (export-result-release! m name symbol (● definition type)))
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
                (expect (fill "(call {f} {x})" (list (Pair "f" "$g") (Pair "x" "1"))) "(call $g 1)")
                (expect (wat->string (wat "module"
                                          (wat "func"
                                               (Word "$f")
                                               (wat "result" (Word "i32"))
                                               (wat "i32.const" (int 1)))))
                        "(module\n  (func $f (result i32)\n    (i32.const 1)))\n")
                (expect (wat->text (wat-string "é\n")) "\"\\c3\\a9\\0a\"")))))
   (else)))
