;; Lower a whole program's typed instructions to linear memory. Fields become
;; aligned loads and stores, scoped locals occupy their activation, and indirect
;; calls use the program's table. The runtime traces only published references.
(define-library (snail shell compiler memory)
  (export lower-memory)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler wat))
  (begin

    (record (BuilderSlot T)
      ((value T)))

    ;; ---- Instruction vocabulary ----

    (define (string-prefix? (prefix String) (text String)) (→ Bool)
      (and (<= (string-length prefix) (string-length text))
           (let loop ((i 0))
             (or (= i (string-length prefix))
                 (and (char=? (string-ref prefix i) (string-ref text i))
                      (loop (+ i 1)))))))

    (define (word (tree Wat)) (→ String)
      (match tree ((Word text) text) (_ (panic "internal error: expected WAT word"))))

    (define (head (tree Wat)) (→ String)
      (match tree ((Node (Cons (Word text) _)) text) (_ "")))

    (define (parts (tree Wat)) (→ (List Wat))
      (match tree ((Node (Cons _ rest)) rest) (_ (Nil))))

    (define (at (items (List Wat)) (index I64)) (→ Wat)
      (match (list-drop items index)
        ((Cons item _) item)
        (_ (panic "internal error: missing WAT operand"))))

    (define (named? (tree Wat)) (→ Bool)
      (match tree
        ((Word name) (and (> (string-length name) 0) (char=? (string-ref name 0) #\$)))
        (_ #f)))

    (define (lookup (table (Table Wat)) (name String)) (→ Wat)
      (match (table-ref table name)
        ((Some value) value)
        (_ (panic (string-append "internal error: unknown physical operand " name)))))

    (define (pick (name String) (items (List Wat))) (→ (List Wat))
      (filter (lambda (item) (string=? (head item) name)) items))

    (define (c32 (value I64)) (→ Wat) (wat "i32.const" (int value)))

    (define (get-local (name String)) (→ Wat) (wat "local.get" (Word name)))

    (define (get-global (name String)) (→ Wat) (wat "global.get" (Word name)))

    (define (call (name String) (args (List Wat))) (→ Wat) (wat* "call" (Cons (Word name) args)))

    (define (unwrap-mut (type Wat)) (→ Wat)
      (if (string=? (head type) "mut") (at (parts type) 0) type))

    (define (reference? (type Wat)) (→ Bool)
      (or (string=? (head type) "ref")
          (match type
            ((Word name) (member? name (list "eqref" "anyref" "funcref" "externref")))
            (_ #f))))

    (define (physical-type (type Wat)) (→ Wat)
      (if (reference? type) (Word "i32") type))

    (define (heap-name (type Wat)) (→ String)
      (if (string=? (head type) "ref") (word (at (reverse (parts type)) 0)) (word type)))

    (define (annotation (tree Wat)) (→ Wat)
      (wat* (head tree) (map (lambda (part) (if (named? part) part (physical-type part)))
                             (parts tree))))

    ;; ---- Logical module facts ----

    (record MemoryModule
      ((types (Table Wat))
       (functions (Table Wat))
       (signatures (Table String))
       (globals (Table Wat))
       (codes (Table I64))
       (foreign (List String))
       (noncollecting (Table Bool))
       (imports (BuilderSlot (Table Wat)))))

    (define (type-body (declaration Wat)) (→ Wat)
      (let* ((body (at (parts declaration) 1)))
        (if (string=? (head body) "sub") (at (reverse (parts body)) 0) body)))

    (define (declarations (kind String) (fields (List Wat))) (→ (Table Wat))
      (fold-left (lambda (table field)
                   (let* ((value (if (string=? (head field) "import") (at (parts field) 2) field)))
                     (if (string=? (head value) kind)
                         (table-set table (word (at (parts value) 0)) value) table)))
                 (empty-table) fields))

    (define (reference-code? (module MemoryModule) (type Wat)) (→ Bool)
      (and (reference? type)
           (let* ((name (heap-name type)))
             (or (member? name (list "func" "funcref"))
                 (match (table-ref (● module types) name)
                   ((Some definition) (string=? (head (type-body definition)) "func"))
                   (_ #f))))))

    (define (declaration-type (declaration Wat)) (→ Wat)
      (unwrap-mut (at (parts declaration) 1)))

    (define (result-type (function Wat)) (→ Wat)
      (match (pick "result" (parts function))
        ((Cons result (Nil))
         (match (parts result)
           ((Cons type (Nil)) type)
           (_ (panic "internal error: physical lowering requires one result"))))
        ((Nil) (Word "void"))
        (_ (panic "internal error: multiple result annotations"))))

    (define (import-runtime (module MemoryModule)
                            (name String)
                            (params (List String))
                            (result String))
      (→ String)
      (let* ((id (string-append "$lm." name)))
        ;; A runtime service has one fixed ABI. Intern its declaration once;
        ;; reconstructing its quoted strings for every instruction overwhelms
        ;; stage 0 while leaving the emitted module exactly the same.
        (unless (table-contains? (● (● module imports) value) id)
          (set! (● (● module imports) value) (table-set (● (● module imports) value) id
                                                        (wat "import"
                                                             (wat-string "snail.core.support")
                                                             (wat-string
                                                              (string-append "snail:gc/" name))
                                                             (wat* "func" (append (Cons (Word id)
                                                                                        (map
                                                                                         (lambda (p)
                                                                                           (wat
                                                                                            "param"
                                                                                            (Word
                                                                                             p)))
                                                                                         params))
                                                                                  (if
                                                                                   (string=? result
                                                                                             "void")
                                                                                   (Nil)
                                                                                   (list
                                                                                    (wat "result"
                                                                                         (Word
                                                                                          result))))))))))
        id))

    (define (runtime-call (module MemoryModule) (name String) (args (List Wat)) (result String))
      (→ Wat)
      (call (import-runtime module name (map (lambda (_) "i32") args) result) args))

    (define (tag-id (name String))
      (→ String)
      (string-append "$lm.tag." (substring name 1 (string-length name))))

    (define (tag (name String)) (→ Wat) (get-global (tag-id name)))

    ;; ---- Calls that cannot collect ----

    ;; Collection only occurs in managed allocation or a call. Unknown imports
    ;; and indirect calls may re-enter the runtime, so they are collecting.
    ;; Propagate those facts backwards over direct calls. Recursive components
    ;; with no collecting operation need no roots, including scalar tail loops.

    (define (direct-callees (tree Wat)) (→ (List String))
      (let ((nested (concatenate (map direct-callees (parts tree)))))
        (if (member? (head tree) (list "call" "return_call"))
            (Cons (word (at (parts tree) 0)) nested) nested)))

    (define (collection-point? (local (Table Bool)) (tree Wat)) (→ Bool)
      (let ((op (head tree)))
        (or (string-prefix? "struct.new" op) (string-prefix? "array.new" op)
            (member? op (list "call_ref" "return_call_ref" "call_indirect" "return_call_indirect"))
            (and (member? op (list "call" "return_call"))
                 (not (table-contains? local (word (at (parts tree) 0)))))
            (any? (lambda (child) (collection-point? local child)) (parts tree)))))

    (define (callers-of (callers (Table (List String))) (name String)) (→ (List String))
      (match (table-ref callers name) ((Some names) names) (_ (Nil))))

    (define (reverse-calls (functions (List Wat))) (→ (Table (List String)))
      (fold-left (lambda (callers function)
                   (fold-left (lambda (callers callee)
                                (table-set callers callee
                                           (Cons (member-name function)
                                                 (callers-of callers callee))))
                              callers (direct-callees function))) (empty-table) functions))

    (define (collecting-callers (callers (Table (List String)))
                                (pending (List String))
                                (collecting (Table Bool)))
      (→ (Table Bool))
      (match pending
        ((Nil) collecting)
        ((Cons name rest)
         (if (table-contains? collecting name) (collecting-callers callers rest collecting)
             (collecting-callers callers (append (callers-of callers name) rest)
                                 (table-set collecting name #t))))))

    (define (noncollecting-functions (fields (List Wat))) (→ (Table Bool))
      (let* ((functions (pick "func" fields))
             (local (fold-left (lambda (names fn) (table-set names (member-name fn) #t))
                               (empty-table) functions))
             (seeds (map member-name (filter (lambda (fn) (collection-point? local fn)) functions)))
             (collecting (collecting-callers (reverse-calls functions) seeds (empty-table))))
        (fold-left (lambda (safe function)
                     (let ((name (member-name function)))
                       (if (table-contains? collecting name) safe (table-set safe name #t))))
                   (empty-table) functions)))

    ;; ---- Layouts ----

    ;; Eight header bytes precede every payload: type identity and array length.
    ;; Struct fields use their natural alignment, capped at eight. Packed array
    ;; elements retain their original width. The collector recognizes extents
    ;; from its own metadata, never from untrusted words in candidate memory.

    (define (width (type Wat)) (→ I64)
      (match type
        ((Word "i8") 1)
        ((Word "i16") 2)
        ((Word "i64") 8)
        ((Word "f64") 8)
        (_ 4)))

    (define (aligned (value I64) (alignment I64)) (→ I64)
      (* (quotient (+ value (- alignment 1)) alignment) alignment))

    (define (fields-of (module MemoryModule) (name String)) (→ (List Wat))
      (map (lambda (field) (unwrap-mut (at (reverse (parts field)) 0)))
           (parts (type-body (lookup (● module types) name)))))

    (define (field-offset (fields (List Wat)) (index I64)) (→ I64)
      (let loop ((fields fields) (index index) (offset 8))
        (match fields
          ((Cons type rest)
           (let* ((start (aligned offset (width type))))
             (if (= index 0) start (loop rest (- index 1) (+ start (width type))))))
          (_ offset))))

    (define (struct-size (fields (List Wat))) (→ I64) (field-offset fields (length fields)))

    (define (array-element (module MemoryModule) (name String)) (→ Wat)
      (unwrap-mut (at (parts (type-body (lookup (● module types) name))) 0)))

    (define (load-op (type Wat) (signed String)) (→ String)
      (match type
        ((Word "i8") (string-append "i32.load8_" signed))
        ((Word "i16") (string-append "i32.load16_" signed))
        (_ (string-append (word (physical-type type)) ".load"))))

    (define (store-op (type Wat)) (→ String)
      (match type
        ((Word "i8") "i32.store8")
        ((Word "i16") "i32.store16")
        (_ (string-append (word (physical-type type)) ".store"))))

    ;; ---- Function roots ----

    ;; Frame lifetime belongs to the whole function, even when a return value
    ;; is computed without collection. Temporary publication may be disabled
    ;; inside one such expression without changing the function's exit rules.
    (record MemoryFunction
      ((module MemoryModule)
       (framed? Bool)
       (temporary-roots? Bool)
       (local-types (Table Wat))
       (local-names (Table String))
       (local-roots (Table I64))
       (locals (BuilderSlot (List Wat)))
       (names (BuilderSlot I64))
       (slots (BuilderSlot I64))
       (result Wat)))

    (define (fresh-local (fn MemoryFunction) (type Wat)) (→ String)
      (let* ((name (string-append "$lm.tmp." (i64->string (● (● fn names) value)))))
        (set! (● (● fn names) value) (+ (● (● fn names) value) 1))
        (set! (● (● fn locals) value) (Cons (wat "local" (Word name) (physical-type type))
                                            (● (● fn locals) value)))
        name))

    (define (root-slot (fn MemoryFunction)) (→ I64)
      (let* ((slot (● (● fn slots) value)))
        (set! (● (● fn slots) value) (+ slot 1)) slot))

    (define (root-address (slot I64)) (→ Wat)
      (wat "i32.add" (get-local "$lm.frame") (c32 (* slot 4))))

    (define (root-result (fn MemoryFunction) (value Wat) (first I64) (end I64)) (→ Wat)
      (let* ((slot (root-slot fn)) (local (value-local (Word "i32"))))
        (wat* "block" (concatenate
                       (list (list (wat "result" (Word "i32"))
                                   (wat "local.set" (Word local) value)
                                   (wat "i32.store" (root-address slot) (get-local local)))
                             (clear-temporaries first end) (list (get-local local)))))))

    ;; A folded operation consumes its operands. Publish its result before
    ;; releasing their temporary roots; parameter/local slots precede this range
    ;; and keep their conservative function lifetime. Pending sibling operands
    ;; are outside the range too. Abrupt branches skip cleanup, conservatively.

    (define (clear-temporaries (first I64) (end I64)) (→ (List Wat))
      (cond ((= first end) (Nil))
            ((= end (+ first 1)) (list (wat "i32.store" (root-address first) (c32 0))))
            (else (list (wat "memory.fill" (root-address first) (c32 0)
                             (c32 (* 4 (- end first))))))))

    (define (consume-temporaries (value Wat) (type Wat) (first I64) (end I64)) (→ Wat)
      (if (null? (result-annotation type))
          (wat* "block" (Cons value (clear-temporaries first end)))
          (let* ((local (value-local type)))
            (wat* "block" (concatenate
                           (list (result-annotation type)
                                 (list (wat "local.set" (Word local) value))
                                 (clear-temporaries first end) (list (get-local local))))))))

    ;; These scratch values are assigned after evaluating their entire operand.
    ;; Nested expressions have finished with the same scratch before it is
    ;; overwritten. No call or allocation separates that assignment and read.

    (define (value-local (type Wat)) (→ String)
      (string-append "$lm.value." (word (physical-type type))))

    (define (scratch-locals) (→ (List Wat))
      (append (map (lambda (type) (wat "local" (Word (value-local (Word type))) (Word type)))
                   (list "i32" "i64" "f32" "f64"))
              (list (wat "local" (Word "$lm.object") (Word "i32"))
                    (wat "local" (Word "$lm.index") (Word "i32")))))

    (define (local-name (fn MemoryFunction) (name String)) (→ String)
      (match (table-ref (● fn local-names) name)
        ((Some value) value)
        (_ (panic (string-append "internal error: unknown local " name)))))

    ;; Objects do not move, so a pointer value stays valid across collection.
    ;; Keep it in a Wasm local and mirror assignments into its root cell. This
    ;; caches variable values only; mutable fields are still loaded normally.

    (define (read-local (fn MemoryFunction) (name String)) (→ Wat)
      (get-local (local-name fn name)))

    (define (write-local (fn MemoryFunction) (name String) (value Wat) (tee? Bool)) (→ Wat)
      (match (table-ref (● fn local-roots) name)
        ((Some slot)
         (let* ((store (wat "i32.store" (root-address slot)
                            (wat "local.tee" (Word (local-name fn name)) value))))
           (if tee? (wat "block" (wat "result" (Word "i32")) store (read-local fn name)) store)))
        (_ (wat (if tee? "local.tee" "local.set") (Word (local-name fn name)) value))))

    (define (leave-frame (fn MemoryFunction)) (→ Wat)
      (if (● fn framed?)
          (runtime-call (● fn module) "leave" (list (get-local "$lm.frame")) "void")
          (wat "nop")))

    ;; Original folded operands are evaluated once, left to right. Their own
    ;; root slots protect managed results while later operands allocate. New
    ;; construction temporaries need no extra slots: initialization cannot GC.

    (define (save-operands (fn MemoryFunction) (operands (List Wat)))
      (→ (Pair (List Wat) (List Wat)))
      (let loop ((operands operands) (stores (Nil)) (reads (Nil)))
        (match operands
          ((Nil) (new Pair (first (reverse stores)) (second (reverse reads))))
          ((Cons operand rest)
           (if (member? (head operand)
                        (list "i32.const" "i64.const" "f32.const" "f64.const" "ref.null"))
               (loop rest stores (Cons (lower-operation fn operand) reads))
               (if
                (and (● fn temporary-roots?) (reference? (expression-type fn operand)))
                (let* ((value (lower-expression fn operand)) (slot (- (● (● fn slots) value) 1)))
                  (loop rest (Cons (wat "drop" value) stores)
                        (Cons (wat "i32.load" (root-address slot)) reads)))
                (let* ((local (fresh-local fn (expression-type fn operand)))
                       (value (lower-expression fn operand)))
                  (loop rest (Cons (wat "local.set" (Word local) value) stores)
                        (Cons (get-local local) reads)))))))))

    ;; ---- Expression types ----

    (define (expression-type (fn MemoryFunction) (tree Wat)) (→ Wat)
      (let* ((op (head tree)) (args (parts tree)) (module (● fn module)))
        (cond
         ((member? op (list "local.get" "local.tee"))
          (lookup (● fn local-types) (word (at args 0))))
         ((string=? op "global.get")
          (declaration-type (lookup (● module globals) (word (at args 0)))))
         ((string=? op "call") (result-type (lookup (● module functions) (word (at args 0)))))
         ((string=? op "call_ref")
          (result-type (type-body (lookup (● module types) (word (at args 0))))))
         ((member? op (list "block" "loop" "if")) (result-type tree))
         ((member? op
                   (list "struct.new"
                         "frame.struct.at"
                         "struct.new_default"
                         "array.new"
                         "array.new_fixed"
                         "array.new_default" "array.new_data")) (wat "ref" (at args 0)))
         ((string=? op "struct.get")
          (at (fields-of module (word (at args 0))) (number (word (at args 1)))))
         ((member? op (list "array.get" "array.get_u" "array.get_s"))
          (let* ((type (array-element module (word (at args 0)))))
            (if (< (width type) 4) (Word "i32") type)))
         ((string=? op "ref.cast") (at args 0))
         ((string=? op "ref.as_non_null") (expression-type fn (at args 0)))
         ((string=? op "ref.null") (wat "ref" (Word "null") (at args 0)))
         ((string=? op "ref.func") (Word "funcref"))
         ((member? op (list "array.len" "array.payload" "ref.eq" "ref.is_null" "ref.test"))
          (Word "i32"))
         ((or (string-prefix? "i32." op) (string-prefix? "i64." op)
              (string-prefix? "f32." op) (string-prefix? "f64." op))
          (numeric-type op))
         (else (Word "void")))))

    (define (number (text String)) (→ I64)
      (fold-left (lambda (value c) (+ (* value 10) (- (char->integer c) 48)))
                 0 (string->list text)))

    (define (numeric-type (op String)) (→ Wat)
      (let* ((suffix (substring op 4 (string-length op))))
        (cond ((string-prefix? "store" suffix) (Word "void"))
              ((or (member? suffix (list "eq" "eqz" "ne" "lt" "le" "gt" "ge"))
                   (member? (substring suffix 0 (min 3 (string-length suffix)))
                            (list "lt_" "le_" "gt_" "ge_"))) (Word "i32"))
              (else (Word (substring op 0 3))))))

    ;; ---- Lowering ----

    (define (lower-expression (fn MemoryFunction) (tree Wat)) (→ Wat)
      (if (not (● fn temporary-roots?)) (lower-operation fn tree)
          (lower-rooted-expression fn tree)))

    ;; A subtree with no collecting call needs no temporary publications inside
    ;; it. Its final reference still gets a root: the next sibling may collect.
    ;; Persistent local assignments and function exits retain their frame rules.

    (define (lower-rooted-expression (fn MemoryFunction) (tree Wat)) (→ Wat)
      (let* ((first (● (● fn slots) value))
             (inner (if (collection-point? (● (● fn module) noncollecting) tree) fn
                        (MemoryFunction-temporary-roots?-set fn #f)))
             (value (lower-operation inner tree))
             (end (● (● fn slots) value)) (type (expression-type fn tree)))
        (cond ((reference? type) (root-result fn value first end))
              ((or (= first end)
                   (member? (head tree)
                            (list "then"
                                  "else"
                                  "br"
                                  "return"
                                  "return_call"
                                  "return_call_ref"
                                  "unreachable")))
               value)
              (else (consume-temporaries value type first end)))))

    ;; Every instruction producer, including fixed helper templates, reaches
    ;; this dispatch. Unsupported reference instructions are rejected here.

    (define (lower-operation (fn MemoryFunction) (tree Wat)) (→ Wat)
      (let* ((op (head tree)) (args (parts tree)))
        (cond
         ((string=? op "") tree)
         ((member? op (list "result" "param" "local")) (annotation tree))
         ((string=? op "local.get") (read-local fn (word (at args 0))))
         ;; A self tail loop evaluates changed scalar arguments on the operand
         ;; stack before rebinding any formal. Managed stores always carry a
         ;; value expression so write-local can also update the frame root.
         ((and (string=? op "local.set") (= (length args) 1))
          (let ((name (word (at args 0))))
            (if (reference? (lookup (● fn local-types) name))
                (panic "internal error: stack assignment to a reference")
                (wat "local.set" (Word (local-name fn name))))))
         ((member? op (list "local.set" "local.tee"))
          (write-local fn
                       (word (at args 0))
                       (lower-expression fn (at args 1))
                       (string=? op "local.tee")))
         ((string=? op "global.get") (read-global fn (word (at args 0))))
         ((string=? op "global.set")
          (write-global fn (word (at args 0)) (lower-expression fn (at args 1))))
         ((string=? op "struct.new") (new-struct fn (word (at args 0)) (list-drop args 1) (None)))
         ((string=? op "frame.struct.at")
          (new-struct fn (word (at args 0)) (list-drop args 2)
                      (Some (number (word (at args 1))))))
         ((member? op (list "struct.get" "struct.set")) (struct-access fn op args))
         ((string-prefix? "array." op) (array-operation fn op args))
         ((string-prefix? "ref." op) (reference-operation fn op args))
         ((string=? op "call") (lower-call fn args))
         ((string=? op "call_ref")
          (wat* "call_indirect" (Cons (wat "type" (at args 0))
                                      (indirect-arguments
                                       (map (lambda (arg) (lower-expression fn arg))
                                            (list-drop args 1))))))
         ((and (string=? op "return_call")
               (member? (word (at args 0)) (● (● fn module) foreign))
               (reference? (result-type (lookup (● (● fn module) functions) (word (at args 0))))))
          (return-value fn (list (wat* "call" args))))
         ((member? op (list "return_call" "return_call_ref")) (tail-call fn op args))
         ((string=? op "return") (return-value fn args))
         ((member? op (list "struct.new_default" "br_on_cast" "br_on_null" "try_table"))
          (panic (string-append "internal error: unsupported physical instruction " op)))
         (else (wat* op (map (lambda (arg) (lower-expression fn arg)) args))))))

    (define (lower-call (fn MemoryFunction) (args (List Wat))) (→ Wat)
      (let* ((module (● fn module)) (name (word (at args 0)))
             (type (result-type (lookup (● module functions) name)))
             (value (call name (map (lambda (arg) (lower-expression fn arg)) (list-drop args 1)))))
        (if (and (member? name (● module foreign)) (reference? type))
            (call "$lm.foreign-value" (list value (host-type module type))) value)))

    (define (read-global (fn MemoryFunction) (name String)) (→ Wat)
      (if (reference? (declaration-type (lookup (● (● fn module) globals) name)))
          (wat "i32.load" (get-global name)) (get-global name)))

    (define (write-global (fn MemoryFunction) (name String) (value Wat)) (→ Wat)
      (if (reference? (declaration-type (lookup (● (● fn module) globals) name)))
          (wat "i32.store" (get-global name) value) (wat "global.set" (Word name) value)))

    (define (reference-operation (fn MemoryFunction) (op String) (args (List Wat))) (→ Wat)
      (cond ((string=? op "ref.null") (c32 0))
            ((string=? op "ref.func") (code-address (● fn module) (word (at args 0))))
            ((string=? op "ref.eq")
             (wat* "i32.eq" (map (lambda (arg) (lower-expression fn arg)) args)))
            ((string=? op "ref.is_null") (wat "i32.eqz" (lower-expression fn (at args 0))))
            ((string=? op "ref.as_non_null")
             (call "$lm.nonnull" (list (lower-expression fn (at args 0)))))
            ((member? op (list "ref.cast" "ref.test")) (cast-reference fn op args))
            (else (panic (string-append "internal error: unsupported reference instruction " op)))))

    (define (cast-reference (fn MemoryFunction) (op String) (args (List Wat))) (→ Wat)
      (let* ((type (at args 0)) (name (heap-name type))
             (nullable (member? "null" (map word (parts type))))
             (value (lower-expression fn (at args 1)))
             (code? (reference-code? (● fn module) type)))
        (runtime-call (● fn module)
                      (if code? (if (string=? op "ref.test") "host-check" "code-cast")
                          (if (string=? op "ref.test") "test" "cast"))
                      (list value (tag name)
                            (c32 (if (and code? (string=? op "ref.test"))
                                     (+ 5 (if nullable 2 0)) (if nullable 1 0)))) "i32")))

    (define (code-address (module MemoryModule) (name String)) (→ Wat)
      (match (table-ref (● module codes) name)
        ((Some index) (code-cell index))
        (_ (panic (string-append "internal error: undeclared function reference " name)))))

    (define (code-cell (index I64)) (→ Wat)
      (wat "i32.add" (get-global "$lm.codes") (c32 (* index 12))))

    (define (indirect-arguments (args (List Wat))) (→ (List Wat))
      (match (reverse args)
        ((Cons code rest) (reverse (Cons (call "$lm.code-index" (list code)) rest)))
        (_ (panic "internal error: indirect call without code"))))

    (define (return-value (fn MemoryFunction) (args (List Wat))) (→ Wat)
      (let* ((body (map (lambda (arg) (lower-expression fn arg)) args)))
        (if (null? (result-annotation (● fn result)))
            (wat "return" (wat* "block" (append body (list (leave-frame fn)))))
            (let* ((value (value-local (● fn result))))
              (wat "return" (wat* "block" (append (result-annotation (● fn result))
                                                  (list (wat "local.set" (Word value)
                                                             (wat* "block"
                                                                   (append (result-annotation
                                                                            (● fn result))
                                                                           body)))
                                                        (leave-frame fn) (get-local value)))))))))

    (define (tail-call (fn MemoryFunction) (op String) (args (List Wat))) (→ Wat)
      (let* ((saved (save-operands fn (list-drop args 1))))
        (wat "return"
             (wat* "block" (concatenate (list (result-annotation (● fn result)) (● saved first)
                                              (list (leave-frame fn)
                                                    (wat* (if (string=? op "return_call")
                                                              op
                                                              "return_call_indirect")
                                                          (Cons (if (string=? op "return_call")
                                                                    (at args 0)
                                                                    (wat "type" (at args 0)))
                                                                (if (string=? op "return_call")
                                                                    (● saved second)
                                                                    (indirect-arguments
                                                                     (● saved second))))))))))))

    (define (new-struct (fn MemoryFunction)
                        (name String)
                        (operands (List Wat))
                        (storage (Option I64)))
      (→ Wat)
      (let* ((fields (fields-of (● fn module) name)) (saved (save-operands fn operands))
             (object "$lm.object"))
        (wat* "block" (concatenate (list (list (wat "result" (Word "i32"))) (● saved first)
                                         (struct-storage fn name (struct-size fields) storage)
                                         (map (lambda (index)
                                                (wat (store-op (at fields index))
                                                     (Word (string-append "offset="
                                                                          (i64->string
                                                                           (field-offset fields
                                                                                         index))))
                                                     (get-local object)
                                                     (at (● saved second) index)))
                                              (iota (length fields)))
                                         (list (get-local object)))))))

    ;; The scoped checker proves no heap object, return or suspended frame can
    ;; retain this address. The compiler reserves flat payloads in the untraced
    ;; part of the activation. Construction writes every scalar field.

    (define (struct-storage (fn MemoryFunction) (name String) (bytes I64) (storage (Option I64)))
      (→ (List Wat))
      (match storage
        ((None)
         (list (wat "local.set" (Word "$lm.object")
                    (runtime-call (● fn module)
                                  "alloc"
                                  (list (c32 bytes) (tag name) (c32 0))
                                  "i32"))))
        ((Some slot)
         (list (wat "local.set" (Word "$lm.object")
                    (wat "i32.and" (wat "i32.add" (root-address slot) (c32 7)) (c32 -8)))
               (wat "i32.store" (get-local "$lm.object") (tag name))))))

    (define (struct-access (fn MemoryFunction) (op String) (args (List Wat))) (→ Wat)
      (let* ((fields (fields-of (● fn module) (word (at args 0))))
             (index (number (word (at args 1)))) (offset (field-offset fields index))
             (receiver (at args 2)) (type (expression-type fn receiver)))
        (if (string=? op "struct.get")
            (wat (load-op (at fields index) "u")
                 (Word (string-append "offset=" (i64->string offset)))
                 (checked-address type (lower-expression fn receiver)))
            (let* ((saved (save-operands fn (list-drop args 2))))
              (wat* "block" (append (● saved first)
                                    (list (wat (store-op (at fields index))
                                               (Word (string-append "offset=" (i64->string offset)))
                                               (checked-address type (at (● saved second) 0))
                                               (at (● saved second) 1)))))))))

    (define (checked-address (type Wat) (value Wat)) (→ Wat)
      (match type
        ((Node (Cons (Word "ref") (Cons (Word _) (Nil)))) value)
        (_ (call "$lm.nonnull" (list value)))))

    ;; ---- Arrays ----

    (define (array-operation (fn MemoryFunction) (op String) (args (List Wat))) (→ Wat)
      (cond ((string=? op "array.len")
             (wat "i32.load" (Word "offset=4")
                  (call "$lm.nonnull" (list (lower-expression fn (at args 0))))))
            ((string=? op "array.payload")
             (wat "i32.add" (call "$lm.nonnull" (list (lower-expression fn (at args 0)))) (c32 8)))
            ((member? op (list "array.get" "array.get_u" "array.get_s" "array.set"))
             (array-access fn op args))
            ((string=? op "array.copy") (array-copy fn args))
            ((member? op (list "array.new" "array.new_fixed" "array.new_default" "array.new_data"))
             (new-array fn op args))
            (else (panic (string-append "internal error: unsupported array instruction " op)))))

    (define (array-address (array Wat) (index Wat) (stride I64)) (→ Wat)
      (call "$lm.index" (list array index (c32 stride))))

    (define (array-access (fn MemoryFunction) (op String) (args (List Wat))) (→ Wat)
      (let* ((element (array-element (● fn module) (word (at args 0)))))
        (if (string=? op "array.set")
            (let* ((saved (save-operands fn (list-drop args 1))))
              (wat* "block" (append (● saved first)
                                    (list (wat (store-op element)
                                               (array-address (at (● saved second) 0)
                                                              (at (● saved second) 1)
                                                              (width element))
                                               (at (● saved second) 2))))))
            (wat (load-op element (if (string=? op "array.get_s") "s" "u"))
                 (array-address (lower-expression fn (at args 1))
                                (lower-expression fn (at args 2)) (width element))))))

    (define (array-copy (fn MemoryFunction) (args (List Wat))) (→ Wat)
      (let* ((stride (width (array-element (● fn module) (word (at args 0)))))
             (saved (save-operands fn (list-drop args 2))) (values (● saved second)))
        (wat* "block" (append (● saved first)
                              (list (wat "memory.copy"
                                         (call "$lm.range"
                                               (list (at values 0)
                                                     (at values 1)
                                                     (at values 4)
                                                     (c32 stride)))
                                         (call "$lm.range"
                                               (list (at values 2)
                                                     (at values 3)
                                                     (at values 4)
                                                     (c32 stride)))
                                         (wat "i32.mul" (at values 4) (c32 stride))))))))

    (define (new-array (fn MemoryFunction) (op String) (args (List Wat))) (→ Wat)
      (let* ((name (word (at args 0))) (element (array-element (● fn module) name))
             (skip (if (member? op (list "array.new_fixed" "array.new_data")) 2 1))
             (saved (save-operands fn (list-drop args skip)))
             (values (● saved second)) (object "$lm.object")
             (count (if (string=? op "array.new_fixed") (c32 (number (word (at args 1))))
                        (at (reverse values) 0))))
        (wat* "block" (concatenate (list (list (wat "result" (Word "i32"))) (● saved first)
                                         (list (wat "local.set" (Word object)
                                                    (runtime-call (● fn module)
                                                                  "array"
                                                                  (list (tag name)
                                                                        count
                                                                        (c32 (width element)))
                                                                  "i32")))
                                         (initialize-array op args element values object count)
                                         (list (get-local object)))))))

    (define (initialize-array (op String)
                              (args (List Wat))
                              (element Wat)
                              (values (List Wat))
                              (object String)
                              (count Wat))
      (→ (List Wat))
      (cond ((string=? op "array.new_default") (Nil))
            ((string=? op "array.new_fixed")
             (map (lambda (index)
                    (wat (store-op element)
                         (Word
                          (string-append "offset=" (i64->string (+ 8 (* index (width element))))))
                         (get-local object) (at values index))) (iota (length values))))
            ((string=? op "array.new_data")
             (list (wat "memory.init" (at args 1) (wat "i32.add" (get-local object) (c32 8))
                        (at values 0) (wat "i32.mul" count (c32 (width element))))))
            (else (fill-array element (at values 0) object count))))

    (define (fill-array (element Wat) (value Wat) (object String) (count Wat)) (→ (List Wat))
      (let* ((index "$lm.index"))
        (list (wat "local.set" (Word index) (c32 0))
              (wat "block" (Word "$lm.filled")
                   (wat "loop" (Word "$lm.fill")
                        (wat "br_if" (Word "$lm.filled") (wat "i32.ge_u" (get-local index) count))
                        (wat (store-op element) (Word "offset=8")
                             (wat "i32.add"
                                  (get-local object)
                                  (wat "i32.mul" (get-local index) (c32 (width element))))
                             value)
                        (wat "local.set" (Word index) (wat "i32.add" (get-local index) (c32 1)))
                        (wat "br" (Word "$lm.fill")))))))

    ;; ---- Complete functions ----

    (define (result-annotation (type Wat)) (→ (List Wat))
      (if (string=? (head type) "")
          (if (string=? (word type) "void") (Nil) (list (wat "result" (physical-type type))))
          (list (wat "result" (physical-type type)))))

    (define (bind-function-local (fn MemoryFunction) (declaration Wat) (index I64))
      (→ MemoryFunction)
      (let* ((type (at (reverse (parts declaration)) 0))
             (number (i64->string index))
             (name (if (named? (at (parts declaration) 0)) (word (at (parts declaration) 0))
                       (string-append "$lm.local." number)))
             (slot (if (and (● fn temporary-roots?) (reference? type)) (root-slot fn) -1)))
        (new MemoryFunction
          (module (● fn module))
          (framed? (● fn framed?))
          (temporary-roots? (● fn temporary-roots?))
          (local-types (table-set (table-set (● fn local-types) name type) number type))
          (local-names (table-set (table-set (● fn local-names) name name) number name))
          (local-roots (if (< slot 0) (● fn local-roots)
                           (table-set (table-set (● fn local-roots) name slot) number slot)))
          (locals (● fn locals))
          (names (● fn names))
          (slots (● fn slots))
          (result (● fn result)))))

    (define (function-context (module MemoryModule) (function Wat) (owns-slots? Bool))
      (→ MemoryFunction)
      ;; A leaf can own storage without ever collecting. Its callers do not
      ;; need roots for that call. Its own frame still ends on every exit.
      (let* ((collects? (not (table-contains? (● module noncollecting) (member-name function))))
             (framed? (or owns-slots? collects?))
             (declarations
              (append (pick "param" (parts function)) (pick "local" (parts function)))))
        (fold-left (lambda (fn index) (bind-function-local fn (at declarations index) index))
                   (new MemoryFunction
                     (module module)
                     (framed? framed?)
                     (temporary-roots? collects?)
                     (local-types (empty-table))
                     (local-names (empty-table))
                     (local-roots (empty-table))
                     (locals (new BuilderSlot (value (Nil))))
                     (names (new BuilderSlot (value 0)))
                     (slots (new BuilderSlot (value (if framed? 1 0))))
                     (result (result-type function)))
                   (iota (length declarations)))))

    (define (parameter-root (fn MemoryFunction) (index I64)) (→ (List Wat))
      (let* ((number (i64->string index)))
        (match (table-ref (● fn local-roots) number)
          ((Some slot)
           (list (wat "i32.store" (root-address slot) (get-local (local-name fn number)))))
          (_ (Nil)))))

    (define (local-declarations (fn MemoryFunction) (function Wat)) (→ (List Wat))
      (let* ((declarations
              (append (pick "param" (parts function)) (pick "local" (parts function)))))
        (map (lambda (index)
               (let* ((old (at declarations index)))
                 (wat (head old) (Word (local-name fn (i64->string index)))
                      (physical-type (at (reverse (parts old)) 0)))))
             (iota (length declarations)))))

    (define (function-code (function Wat)) (→ (List Wat))
      (filter (lambda (part)
                (and (not (named? part))
                     (not (member? (head part) (list "param" "result" "local" "type" "export")))))
              (parts function)))

    ;; Reserve fixed object extents before temporary roots, whose cleanup must
    ;; never erase a live payload. One spare word permits eight-byte alignment
    ;; even when the root frame starts at an odd word. Frames are per invocation.

    (define (owns-slots? (tree Wat)) (→ Bool)
      (or (string=? (head tree) "frame.struct.new") (any? owns-slots? (parts tree))))

    (define (reserve-frame-objects (fn MemoryFunction) (tree Wat)) (→ Wat)
      (let* ((tree (if (string=? (head tree) "frame.struct.new")
                       (let* ((type (at (parts tree) 0))
                              (size (struct-size (fields-of (● fn module) (word type))))
                              (slot (● (● fn slots) value)))
                         (set! (● (● fn slots) value) (+ (+ slot 1) (quotient (+ size 3) 4)))
                         (wat* "frame.struct.at"
                               (Cons type (Cons (int slot) (list-drop (parts tree) 1)))))
                       tree)))
        (match tree
          ((Node items) (Node (map (lambda (child) (reserve-frame-objects fn child)) items)))
          (_ tree))))

    (define (lower-function (module MemoryModule) (function Wat)) (→ Wat)
      (let* ((owns? (owns-slots? function)) (fn (function-context module function owns?))
             (scratch-start (● (● fn slots) value))
             (function (if owns? (reserve-frame-objects fn function) function))
             (scratch-end (● (● fn slots) value))
             (body (map (lambda (tree) (lower-expression fn tree)) (function-code function)))
             (result (● fn result))
             (returned (if (null? (result-annotation result)) "" (value-local result)))
             (count (● (● fn slots) value)))
        (wat* "func" (concatenate (list (list (at (parts function) 0))
                                        (pick "export" (parts function))
                                        (pick "type" (parts function))
                                        (pick "param" (local-declarations fn function))
                                        (result-annotation result)
                                        (pick "local" (local-declarations fn function))
                                        (list (wat "local" (Word "$lm.frame") (Word "i32")))
                                        (scratch-locals)
                                        (reverse (● (● fn locals) value))
                                        (function-prologue fn
                                                           function
                                                           count
                                                           scratch-start
                                                           scratch-end)
                                        (finish-function fn body returned count))))))

    (define (function-prologue (fn MemoryFunction) (function Wat) (count I64) (start I64) (end I64))
      (→ (List Wat))
      (if (= count 0) (Nil)
          (Cons (wat "local.set" (Word "$lm.frame")
                     (runtime-call (● fn module)
                                   "enter"
                                   (list (c32 count) (c32 start) (c32 end))
                                   "i32"))
                (concatenate (map (lambda (index) (parameter-root fn index))
                                  (iota (length (pick "param" (parts function)))))))))

    ;; Leaving a frame is noncollecting. A return value, or all arguments of a
    ;; tail call, crosses to the next prologue without a collection boundary.

    (define (finish-function (fn MemoryFunction) (body (List Wat)) (returned String) (count I64))
      (→ (List Wat))
      (let* ((leave (if (= count 0) (Nil) (list (leave-frame fn)))))
        (if (string=? returned "") (append body leave)
            (concatenate (list (list (wat "local.set" (Word returned)
                                          (wat* "block"
                                                (append (result-annotation (● fn result)) body))))
                               leave (list (get-local returned)))))))

    ;; ---- Checked memory operations ----

    (define (memory-helpers) (→ (List Wat))
      (map parse-wat
           (list
            "(func $lm.foreign-value (param $p i32) (param $type i64) (result i32)
               (if (i32.eqz (call $lm.host-check (local.get $p)
                     (i32.wrap_i64 (i64.shr_u (local.get $type) (i64.const 32)))
                     (i32.wrap_i64 (local.get $type)))) (then (unreachable)))
               (local.get $p))"
            "(func $lm.nonnull (param $p i32) (result i32)
               (if (i32.eqz (local.get $p)) (then (unreachable))) (local.get $p))"
            "(func $lm.code-index (param $p i32) (result i32)
               (i32.load offset=8 (call $lm.nonnull (local.get $p))))"
            "(func $lm.index (param $p i32) (param $i i32) (param $s i32) (result i32)
               (if (i32.ge_u (local.get $i) (i32.load offset=4 (call $lm.nonnull (local.get $p)))) (then (unreachable)))
               (i32.add (i32.add (local.get $p) (i32.const 8)) (i32.mul (local.get $i) (local.get $s))))"
            "(func $lm.range (param $p i32) (param $i i32) (param $n i32) (param $s i32) (result i32) (local $len i32)
               (local.set $len (i32.load offset=4 (call $lm.nonnull (local.get $p))))
               (if (i32.gt_u (local.get $i) (local.get $len)) (then (unreachable)))
               (if (i32.gt_u (local.get $n) (i32.sub (local.get $len) (local.get $i))) (then (unreachable)))
               (i32.add (i32.add (local.get $p) (i32.const 8)) (i32.mul (local.get $i) (local.get $s))))")))

    ;; ---- Layout identities ----
    (record MemorySetup
      ((declarations (List Wat))
       (initializers (List Wat))))

    (define (words (tree Wat)) (→ (List String))
      (match tree ((Word text) (list text)) ((Node parts) (concatenate (map words parts)))))

    (define (global-i32 (name String)) (→ Wat)
      (wat "global" (Word name) (wat "mut" (Word "i32")) (c32 0)))

    (define (member-name (member Wat)) (→ String) (word (at (parts member) 0)))

    (define (layout-pointers (module MemoryModule) (name String) (layout Wat)) (→ (List Wat))
      (cond ((string=? (head layout) "struct")
             (let ((fields (fields-of module name)))
               (concatenate (map-indexed
                             (lambda (index field)
                               (if (reference? field)
                                   (list (runtime-call module "reference-field"
                                                       (list (tag name)
                                                             (c32 (field-offset fields index)))
                                                       "void"))
                                   (Nil))) fields))))
            ((and (string=? (head layout) "array") (reference? (array-element module name)))
             (list (runtime-call module "reference-array" (list (tag name)) "void")))
            (else (Nil))))

    (define (setup-layout (module MemoryModule) (member Wat) (index I64)) (→ MemorySetup)
      (let* ((name (member-name member)) (body (at (parts member) 1))
             (parents (if (string=? (head body) "sub") (filter named? (parts body)) (Nil))))
        (new MemorySetup
          (declarations (list (wat "global" (Word (tag-id name)) (Word "i32") (c32 (+ 1 index)))))
          (initializers
           (append (layout-pointers module name (type-body member))
                   (map (lambda (parent) (runtime-call module "type-parent"
                                                       (list (tag name) (tag (word parent)))
                                                       "void"))
                        parents))))))

    (define (physical-function-type (member Wat)) (→ Wat)
      (wat "type" (at (parts member) 0)
           (wat* "func" (map annotation (parts (type-body member))))))

    ;; ---- Code handles ----

    (define (declared-code (fields (List Wat))) (→ (List String))
      (list-sort string<? (delete-duplicates string=?
                                             (append (concatenate (map (lambda (element)
                                                                         (map word
                                                                              (filter named?
                                                                                      (parts
                                                                                       element))))
                                                                       (pick "elem" fields)))
                                                     (map (lambda (entry) (● entry second))
                                                          (function-exports fields))))))

    (define (function-exports (fields (List Wat))) (→ (List (Pair String String)))
      (concatenate (map (lambda (field)
                          (cond ((string=? (head field) "func")
                                 (map (lambda (export)
                                        (new Pair
                                          (first (word (at (parts export) 0)))
                                          (second (member-name field))))
                                      (pick "export" (parts field))))
                                ((and (string=? (head field) "export")
                                      (string=? (head (at (parts field) 1)) "func"))
                                 (list (new Pair
                                         (first (word (at (parts field) 0)))
                                         (second (member-name (at (parts field) 1))))))
                                (else (Nil)))) fields)))

    (define (code-numbers (names (List String))) (→ (Table I64))
      (fold-left (lambda (table index) (table-set table (list-ref names index) index))
                 (empty-table) (iota (length names))))

    (define (signature-key (function Wat)) (→ String)
      (wat->text (signature-tree function)))

    (define (signature-tree (function Wat)) (→ Wat)
      (wat* "func" (append (map (lambda (param) (wat "param" (at (reverse (parts param)) 0)))
                                (pick "param" (parts function))) (pick "result" (parts function)))))

    (define (function-type-name (module MemoryModule) (name String)) (→ String)
      (let* ((function (lookup (● module functions) name)) (key (signature-key function)))
        (match (pick "type" (parts function))
          ((Cons type _) (word (at (parts type) 0)))
          (_ (match (table-ref (● module signatures) key)
               ((Some name) name)
               (_
                (panic (string-append "internal error: function handle lacks a type: " name))))))))

    (define (signature-types (types (List Wat))) (→ (Table String))
      (fold-left (lambda (table type)
                   (if (string=? (head (type-body type)) "func")
                       (table-set table (signature-key (type-body type)) (member-name type)) table))
                 (empty-table) types))

    (define (setup-code (module MemoryModule) (names (List String))) (→ (List Wat))
      (Cons (wat "global.set" (Word "$lm.codes")
                 (runtime-call module "static-code" (list (c32 (length names))) "i32"))
            (concatenate
             (map-indexed
              (lambda (index name)
                (list (wat "i32.store" (code-cell index) (tag (function-type-name module name)))
                      (wat "i32.store" (Word "offset=8") (code-cell index) (c32 (+ index 1)))))
              names))))

    ;; Public entry points also have handles, including `main:body`, which the
    ;; host hands to the scheduler. A source function need not otherwise have
    ;; appeared as a value, so add its signature when no named type describes it.

    (define (exported-types (fields (List Wat)) (codes (List String))) (→ (List Wat))
      (let* ((functions (declarations "func" fields)))
        (● (fold-left (lambda (state index)
                        (let* ((function (lookup functions (list-ref codes index)))
                               (key (signature-key function))
                               (name (string-append "$lm.export-type." (i64->string index))))
                          (if (table-contains? (● state second) key) state
                              (new Pair
                                (first (Cons (wat "type" (Word name) (signature-tree function))
                                             (● state first)))
                                (second (table-set (● state second) key name))))))
                      (new Pair
                        (first (ann (Nil) (List Wat)))
                        (second (signature-types (pick "type" fields))))
                      (iota (length codes))) first)))

    ;; The host view keeps managed results opaque and rooted. This descriptor
    ;; returns pointer/nullability/code flags in its low word and the logical
    ;; type ID in its high word. Position -1 describes the result.

    (define (host-type (module MemoryModule) (type Wat)) (→ Wat)
      (if (not (reference? type)) (wat "i64.const" (int 0))
          (let* ((name (heap-name type))
                 (nullable (or (not (string=? (head type) "ref")) (member? "null" (words type))))
                 (flags (+ 1 (+ (if nullable 2 0) (if (reference-code? module type) 4 0))))
                 (identity (if (table-contains? (● module types) name) (tag name) (c32 0))))
            (wat "i64.or" (wat "i64.const" (int flags))
                 (wat "i64.shl" (wat "i64.extend_i32_u" identity) (wat "i64.const" (int 32)))))))

    (define (host-exports (module MemoryModule) (fields (List Wat))) (→ (List Wat))
      (map (lambda (entry)
             (describe-host-function module (lookup (● module functions) (● entry second))
                                     (Word (string-append "\"snail:abi/"
                                                          (substring (● entry first)
                                                                     1
                                                                     (string-length
                                                                      (● entry first)))))))
           (function-exports fields)))

    (define (describe-host-function (module MemoryModule) (function Wat) (exported Wat)) (→ Wat)
      (let* ((params (pick "param" (parts function))))
        (wat* "func" (concatenate
                      (list
                       (list (wat "export" exported) (wat "param" (Word "$position") (Word "i32"))
                             (wat "result" (Word "i64"))
                             (wat "if" (wat "i32.eq" (get-local "$position") (c32 -2))
                                  (wat "then"
                                       (wat "return" (wat "i64.const" (int (length params)))))))
                       (map (lambda (index)
                              (wat "if" (wat "i32.eq" (get-local "$position") (c32 index))
                                   (wat "then"
                                        (wat "return"
                                             (host-type module
                                                        (at (reverse (parts (at params index)))
                                                            0))))))
                            (iota (length params)))
                       (list (host-type module (result-type function))))))))

    ;; A public managed global holds the address of its registered root cell.
    ;; Describe its logical value for the same instance-checked host view.
    (define (host-globals (module MemoryModule) (fields (List Wat))) (→ (List Wat))
      (concatenate
       (map (lambda (entry)
              (let* ((name (word (at (parts entry) 0))) (item (at (parts entry) 1)))
                (if (string=? (head item) "global")
                    (let ((type (declaration-type (lookup (● module globals) (member-name item)))))
                      (if (reference? type)
                          (list (wat "func"
                                     (wat "export" (Word (string-append "\"snail:global/"
                                                                        (substring name
                                                                                   1
                                                                                   (string-length
                                                                                    name)))))
                                     (wat "result" (Word "i64")) (host-type module type)))
                          (Nil))) (Nil))))
            (pick "export" fields))))

    (define (foreign-exports (module MemoryModule) (fields (List Wat))) (→ (List Wat))
      (map (lambda (field)
             (let* ((from (word (at (parts field) 0))) (name (word (at (parts field) 1))))
               (describe-host-function module (at (parts field) 2)
                                       (Word (string-append "\"snail:foreign/"
                                                            (substring from
                                                                       1
                                                                       (- (string-length from) 1))
                                                            "\\00"
                                                            (substring name
                                                                       1
                                                                       (string-length name)))))))
           (filter (lambda (field)
                     (let* ((declaration (at (parts field) 2)))
                       (and (string=? (head declaration) "func")
                            (or (reference? (result-type declaration))
                                (any? (lambda (param) (reference? (at (reverse (parts param)) 0)))
                                      (pick "param" (parts declaration)))))))
                   (pick "import" fields))))

    ;; ---- Globals and imports ----

    (define (lower-import (field Wat)) (→ Wat)
      (let* ((args (parts field)) (declaration (at args 2)) (kind (head declaration)))
        (wat "import" (at args 0) (at args 1)
             (cond ((string=? kind "func")
                    (wat* "func"
                          (Cons (at (parts declaration) 0)
                                (map annotation (list-drop (parts declaration) 1)))))
                   ((string=? kind "global")
                    (wat "global" (at (parts declaration) 0)
                         (if (reference? (declaration-type declaration)) (wat "mut" (Word "i32"))
                             (at (parts declaration) 1))))
                   (else declaration)))))

    (define (lower-global (field Wat)) (→ Wat)
      (if (reference? (declaration-type field)) (global-i32 (member-name field)) field))

    (define (managed-globals (fields (List Wat))) (→ (List Wat))
      (filter (lambda (field) (reference? (declaration-type field))) (pick "global" fields)))

    (define (setup-root-cells (module MemoryModule) (fields (List Wat))) (→ (List Wat))
      (let ((globals (managed-globals fields)))
        (Cons (wat "global.set" (Word "$lm.roots")
                   (runtime-call module "roots" (list (c32 (length globals))) "i32"))
              (map-indexed (lambda (index global)
                             (wat "global.set" (Word (member-name global))
                                  (wat "i32.add" (get-global "$lm.roots") (c32 (* index 4)))))
                           globals))))

    (define (foreign-functions (fields (List Wat))) (→ (List String))
      (map (lambda (field) (member-name (at (parts field) 2)))
           (filter (lambda (field)
                     (string=? (head (at (parts field) 2)) "func"))
                   (pick "import" fields))))

    ;; Global constant constructors now allocate in the start function. Their
    ;; registered cells are in place before the first allocation can collect.

    (define (initialize-globals (module MemoryModule) (fields (List Wat))) (→ Wat)
      (lower-function module
                      (wat* "func" (Cons (Word "$lm.initialize-globals")
                                         (map (lambda (global)
                                                (wat "global.set" (Word (member-name global))
                                                     (at (reverse (parts global)) 0)))
                                              (filter (lambda (field)
                                                        (reference? (declaration-type field)))
                                                      (pick "global" fields)))))))

    ;; ---- Module assembly ----

    (define (lower-memory (tree Wat)) (→ Wat)
      (let* ((fields (parts tree))
             (codes (declared-code fields))
             (fields (append fields (reverse (exported-types fields codes))))
             (types (pick "type" fields))
             (module (new MemoryModule
                       (types (declarations "type" types))
                       (functions (declarations "func" fields))
                       (signatures (signature-types types))
                       (globals (declarations "global" fields))
                       (codes (code-numbers codes))
                       (foreign (foreign-functions fields))
                       (noncollecting (noncollecting-functions fields))
                       (imports (new BuilderSlot (value (empty-table))))))
             (setup (map-indexed (lambda (index member) (setup-layout module member index)) types))
             (functions
              (map (lambda (function) (Word (field->string (lower-function module function))))
                   (pick "func" fields)))
             (globals (initialize-globals module fields))
             (start (module-start module fields codes setup)))
        (import-runtime module "host-check" (list "i32" "i32" "i32") "i32")
        (wat* "module" (concatenate (list
                                     (map physical-function-type
                                          (filter
                                           (lambda (type) (string=? (head (type-body type)) "func"))
                                           types))
                                     (map lower-import (pick "import" fields))
                                     (sorted-imports module)
                                     (list (wat "table"
                                                (Word "$lm.code")
                                                (wat "export" (wat-string "snail:table"))
                                                (int (+ 1 (length codes)))
                                                (Word "funcref")))
                                     (concatenate (map (lambda (part) (● part declarations)) setup))
                                     (list (global-i32 "$lm.roots") (global-i32 "$lm.codes"))
                                     (map lower-global (pick "global" fields))
                                     (pick "export" fields)
                                     (if (null? codes)
                                         (Nil)
                                         (list (wat* "elem"
                                                     (append (list (c32 1) (Word "func"))
                                                             (map Word codes)))))
                                     (memory-helpers)
                                     (host-exports module fields)
                                     (host-globals module fields)
                                     (foreign-exports module fields)
                                     functions (list globals start (wat "start" (Word "$lm.start")))
                                     (pick "data" fields))))))

    (define (sorted-imports (module MemoryModule)) (→ (List Wat))
      (let* ((table (● (● module imports) value)))
        (map (lambda (key) (lookup table key)) (list-sort string<? (table-keys table)))))

    (define (module-start (module MemoryModule)
                          (fields (List Wat))
                          (codes (List String))
                          (setup (List MemorySetup)))
      (→ Wat)
      (wat* "func"
            (concatenate
             (list (list (Word "$lm.start")
                         (runtime-call module "layouts" (list (c32 (length setup))) "void"))
                   (concatenate (map (lambda (part) (● part initializers)) setup))
                   (setup-root-cells module fields) (setup-code module codes)
                   (list (call "$lm.initialize-globals" (Nil)))))))
    ))
