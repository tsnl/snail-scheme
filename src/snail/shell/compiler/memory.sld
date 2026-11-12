;; Physical lowering of the backend's typed, folded instructions. Prepared
;; source and allocation choices are unchanged. References become linear-memory
;; addresses; function references become indices in the runtime's shared table.
(define-library (snail shell compiler memory)
  (export lower-memory)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler wat))
  (begin

    ;; ---- Instruction vocabulary ----

    (: string-prefix? (impl (Fn String String -> Bool)))
    (define (string-prefix? prefix text)
      (and (<= (string-length prefix) (string-length text))
           (string=? prefix (substring text 0 (string-length prefix)))))

    (: word (impl (Fn Wat -> String)))
    (define (word tree)
      (match tree ((Word text) text) (_ (panic "internal error: expected WAT word"))))

    (: head (impl (Fn Wat -> String)))
    (define (head tree)
      (match tree ((Node (Cons (Word text) _)) text) (_ "")))

    (: parts (impl (Fn Wat -> (List Wat))))
    (define (parts tree)
      (match tree ((Node (Cons _ rest)) rest) (_ (Nil))))

    (: at (impl (Fn (List Wat) I64 -> Wat)))
    (define (at items index)
      (match (list-drop items index)
        ((Cons item _) item)
        (_ (panic "internal error: missing WAT operand"))))

    (: named? (impl (Fn Wat -> Bool)))
    (define (named? tree)
      (match tree
        ((Word name) (and (> (string-length name) 0) (char=? (string-ref name 0) #\$)))
        (_ #f)))

    (: lookup (impl (Fn (Table Wat) String -> Wat)))
    (define (lookup table name)
      (match (table-ref table name)
        ((Some value) value)
        (_ (panic (string-append "internal error: unknown physical operand " name)))))

    (: pick (impl (Fn String (List Wat) -> (List Wat))))
    (define (pick name items)
      (filter (lambda (item) (string=? (head item) name)) items))

    (: c32 (impl (Fn I64 -> Wat)))
    (define (c32 value) (wat "i32.const" (int value)))

    (: get-local (impl (Fn String -> Wat)))
    (define (get-local name) (wat "local.get" (Word name)))

    (: get-global (impl (Fn String -> Wat)))
    (define (get-global name) (wat "global.get" (Word name)))

    (: call (impl (Fn String (List Wat) -> Wat)))
    (define (call name args) (wat* "call" (Cons (Word name) args)))

    (: unwrap-mut (impl (Fn Wat -> Wat)))
    (define (unwrap-mut type)
      (if (string=? (head type) "mut") (at (parts type) 0) type))

    (: reference? (impl (Fn Wat -> Bool)))
    (define (reference? type)
      (or (string=? (head type) "ref")
          (match type
            ((Word name) (member? name (list "eqref" "anyref" "funcref" "externref")))
            (_ #f))))

    (: physical-type (impl (Fn Wat -> Wat)))
    (define (physical-type type)
      (if (reference? type) (Word "i32") type))

    (: heap-name (impl (Fn Wat -> String)))
    (define (heap-name type)
      (if (string=? (head type) "ref") (word (at (reverse (parts type)) 0)) (word type)))

    (: annotation (impl (Fn Wat -> Wat)))
    (define (annotation tree)
      (wat* (head tree) (map (lambda (part) (if (named? part) part (physical-type part)))
                             (parts tree))))

    ;; ---- Logical module facts ----

    (struct MemoryModule
      ((types (Table Wat))
       (functions (Table Wat))
       (signatures (Table String))
       (globals (Table Wat))
       (codes (Table I64))
       (code-start I64)
       (dependencies (List String))
       (foreign (List String))
       (noncollecting (Table Bool))
       (imports (Ref (Table Wat)))))

    (: type-body (impl (Fn Wat -> Wat)))
    (define (type-body declaration)
      (let* ((body (at (parts declaration) 1)))
        (if (string=? (head body) "sub") (at (reverse (parts body)) 0) body)))

    (: type-definitions (impl (Fn (List Wat) -> (List Wat))))
    (define (type-definitions fields)
      (concatenate (map (lambda (field)
                          (cond ((string=? (head field) "type") (list field))
                                ((string=? (head field) "rec") (parts field))
                                (else (Nil)))) fields)))

    (: declarations (impl (Fn String (List Wat) -> (Table Wat))))
    (define (declarations kind fields)
      (fold-left (lambda (table field)
                   (let* ((value (if (string=? (head field) "import") (at (parts field) 2) field)))
                     (if (string=? (head value) kind)
                         (table-set table (word (at (parts value) 0)) value) table)))
                 empty-table fields))

    (: reference-code? (impl (Fn MemoryModule Wat -> Bool)))
    (define (reference-code? module type)
      (and (reference? type)
           (let* ((name (heap-name type)))
             (or (member? name (list "func" "funcref"))
                 (match (table-ref (::types module) name)
                   ((Some definition) (string=? (head (type-body definition)) "func"))
                   (_ #f))))))

    (: managed? (impl (Fn MemoryModule Wat -> Bool)))
    (define (managed? module type)
      (reference? type))

    (: declaration-type (impl (Fn Wat -> Wat)))
    (define (declaration-type declaration)
      (unwrap-mut (at (parts declaration) 1)))

    (: result-type (impl (Fn Wat -> Wat)))
    (define (result-type function)
      (match (pick "result" (parts function))
        ((Cons result (Nil))
         (match (parts result)
           ((Cons type (Nil)) type)
           (_ (panic "internal error: physical lowering requires one result"))))
        ((Nil) (Word "void"))
        (_ (panic "internal error: multiple result annotations"))))

    (: import-runtime (impl (Fn MemoryModule String (List String) String -> String ! mut)))
    (define (import-runtime module name params result)
      (let* ((id (string-append "$lm." name)))
        ;; A runtime service has one fixed ABI. Intern its declaration once;
        ;; reconstructing its quoted strings for every instruction overwhelms
        ;; stage 0 while leaving the emitted module exactly the same.
        (unless (table-contains? (ref-get (::imports module)) id)
          (ref-set! (::imports module)
                    (table-set (ref-get (::imports module)) id
                               (wat "import" (wat-string "snail.core.support")
                                    (wat-string (string-append "snail:gc/" name))
                                    (wat* "func" (append (Cons (Word id)
                                                               (map
                                                                (lambda (p) (wat "param" (Word p)))
                                                                params))
                                                         (if (string=? result "void") (Nil)
                                                             (list
                                                              (wat "result" (Word result))))))))))
        id))

    (: runtime-call (impl (Fn MemoryModule String (List Wat) String -> Wat ! mut)))
    (define (runtime-call module name args result)
      (let* ((imported (import-runtime module name (map (lambda (_) "i32") args) result)))
        (call (if (member? name (list "alloc" "array" "code-new" "module"))
                  (string-append "$lm.allocate." name) imported) args)))

    (: tag-id (impl (Fn String -> String)))
    (define (tag-id name) (string-append "$lm.tag." (substring name 1 (string-length name))))

    (: tag (impl (Fn String -> Wat)))
    (define (tag name) (get-global (tag-id name)))

    ;; ---- Calls that cannot collect ----

    ;; Collection only occurs in managed allocation or a call. Unknown imports
    ;; and indirect calls may re-enter the runtime, so they are collecting.
    ;; Propagate those facts backwards over direct calls. Recursive components
    ;; with no collecting operation need no roots, including scalar tail loops.
    (: direct-callees (impl (Fn Wat -> (List String))))
    (define (direct-callees tree)
      (let ((nested (concatenate (map direct-callees (parts tree)))))
        (if (member? (head tree) (list "call" "return_call"))
            (Cons (word (at (parts tree) 0)) nested) nested)))

    (: collection-point? (impl (Fn (Table Bool) Wat -> Bool)))
    (define (collection-point? local tree)
      (let ((op (head tree)))
        (or (string-prefix? "struct.new" op) (string-prefix? "array.new" op)
            (member? op (list "call_ref" "return_call_ref" "call_indirect" "return_call_indirect"))
            (and (member? op (list "call" "return_call"))
                 (not (table-contains? local (word (at (parts tree) 0)))))
            (any? (lambda (child) (collection-point? local child)) (parts tree)))))

    (: callers-of (impl (Fn (Table (List String)) String -> (List String))))
    (define (callers-of callers name)
      (match (table-ref callers name) ((Some names) names) (_ (Nil))))

    (: reverse-calls (impl (Fn (List Wat) -> (Table (List String)))))
    (define (reverse-calls functions)
      (fold-left (lambda (callers function)
                   (fold-left (lambda (callers callee)
                                (table-set callers callee
                                           (Cons (member-name function)
                                                 (callers-of callers callee))))
                              callers (direct-callees function))) empty-table functions))

    (: collecting-callers
       (impl (Fn (Table (List String)) (List String) (Table Bool) -> (Table Bool))))
    (define (collecting-callers callers pending collecting)
      (match pending
        ((Nil) collecting)
        ((Cons name rest)
         (if (table-contains? collecting name) (collecting-callers callers rest collecting)
             (collecting-callers callers (append (callers-of callers name) rest)
                                 (table-set collecting name #t))))))

    (: noncollecting-functions (impl (Fn (List Wat) -> (Table Bool))))
    (define (noncollecting-functions fields)
      (let* ((functions (pick "func" fields))
             (local (fold-left (lambda (names fn) (table-set names (member-name fn) #t))
                               empty-table functions))
             (seeds (map member-name (filter (lambda (fn) (collection-point? local fn)) functions)))
             (collecting (collecting-callers (reverse-calls functions) seeds empty-table)))
        (fold-left (lambda (safe function)
                     (let ((name (member-name function)))
                       (if (table-contains? collecting name) safe (table-set safe name #t))))
                   empty-table functions)))

    ;; ---- Layouts ----

    ;; Eight header bytes precede every payload: type identity and array length.
    ;; Struct fields use their natural alignment, capped at eight. Packed array
    ;; elements retain their original width. The collector recognizes extents
    ;; from its own metadata, never from untrusted words in candidate memory.
    (: width (impl (Fn Wat -> I64)))
    (define (width type)
      (match type
        ((Word "i8") 1)
        ((Word "i16") 2)
        ((Word "i64") 8)
        ((Word "f64") 8)
        (_ 4)))

    (: aligned (impl (Fn I64 I64 -> I64)))
    (define (aligned value alignment)
      (* (quotient (+ value (- alignment 1)) alignment) alignment))

    (: fields-of (impl (Fn MemoryModule String -> (List Wat))))
    (define (fields-of module name)
      (map (lambda (field) (unwrap-mut (at (reverse (parts field)) 0)))
           (parts (type-body (lookup (::types module) name)))))

    (: field-offset (impl (Fn (List Wat) I64 -> I64)))
    (define (field-offset fields index)
      (let loop ((fields fields) (index index) (offset 8))
        (match fields
          ((Cons type rest)
           (let* ((start (aligned offset (width type))))
             (if (= index 0) start (loop rest (- index 1) (+ start (width type))))))
          (_ offset))))

    (: struct-size (impl (Fn (List Wat) -> I64)))
    (define (struct-size fields) (field-offset fields (length fields)))

    (: array-element (impl (Fn MemoryModule String -> Wat)))
    (define (array-element module name)
      (unwrap-mut (at (parts (type-body (lookup (::types module) name))) 0)))

    (: load-op (impl (Fn Wat String -> String)))
    (define (load-op type signed)
      (match type
        ((Word "i8") (string-append "i32.load8_" signed))
        ((Word "i16") (string-append "i32.load16_" signed))
        (_ (string-append (word (physical-type type)) ".load"))))

    (: store-op (impl (Fn Wat -> String)))
    (define (store-op type)
      (match type
        ((Word "i8") "i32.store8")
        ((Word "i16") "i32.store16")
        (_ (string-append (word (physical-type type)) ".store"))))

    ;; ---- Function roots ----

    ;; Frame lifetime belongs to the whole function, even when a return value
    ;; is computed without collection. Temporary publication may be disabled
    ;; inside one such expression without changing the function's exit rules.
    (struct MemoryFunction
      ((module MemoryModule)
       (framed? Bool)
       (temporary-roots? Bool)
       (local-types (Table Wat))
       (local-names (Table String))
       (local-roots (Table I64))
       (locals (Ref (List Wat)))
       (names (Ref I64))
       (slots (Ref I64))
       (result Wat)))

    (: fresh-local (impl (Fn MemoryFunction Wat -> String ! mut)))
    (define (fresh-local fn type)
      (let* ((name (string-append "$lm.tmp." (i64->string (ref-get (::names fn))))))
        (ref-set! (::names fn) (+ (ref-get (::names fn)) 1))
        (ref-set! (::locals fn) (Cons (wat "local" (Word name) (physical-type type))
                                      (ref-get (::locals fn))))
        name))

    (: root-slot (impl (Fn MemoryFunction -> I64 ! mut)))
    (define (root-slot fn)
      (let* ((slot (ref-get (::slots fn))))
        (ref-set! (::slots fn) (+ slot 1)) slot))

    (: root-address (impl (Fn I64 -> Wat)))
    (define (root-address slot)
      (wat "i32.add" (get-local "$lm.frame") (c32 (* slot 4))))

    (: root-result (impl (Fn MemoryFunction Wat I64 I64 -> Wat ! mut)))
    (define (root-result fn value first end)
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
    (: clear-temporaries (impl (Fn I64 I64 -> (List Wat))))
    (define (clear-temporaries first end)
      (if (= first end) (Nil)
          (list (wat "memory.fill" (root-address first) (c32 0) (c32 (* 4 (- end first)))))))

    (: consume-temporaries (impl (Fn Wat Wat I64 I64 -> Wat)))
    (define (consume-temporaries value type first end)
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
    (: value-local (impl (Fn Wat -> String)))
    (define (value-local type)
      (string-append "$lm.value." (word (physical-type type))))

    (: scratch-locals (impl (Fn -> (List Wat))))
    (define (scratch-locals)
      (append (map (lambda (type) (wat "local" (Word (value-local (Word type))) (Word type)))
                   (list "i32" "i64" "f32" "f64"))
              (list (wat "local" (Word "$lm.object") (Word "i32"))
                    (wat "local" (Word "$lm.index") (Word "i32")))))

    (: local-name (impl (Fn MemoryFunction String -> String)))
    (define (local-name fn name)
      (match (table-ref (::local-names fn) name)
        ((Some value) value)
        (_ (panic (string-append "internal error: unknown local " name)))))

    ;; Objects do not move, so a pointer value stays valid across collection.
    ;; Keep it in a Wasm local and mirror assignments into its root cell. This
    ;; caches variable values only; mutable fields are still loaded normally.
    (: read-local (impl (Fn MemoryFunction String -> Wat)))
    (define (read-local fn name)
      (get-local (local-name fn name)))

    (: write-local (impl (Fn MemoryFunction String Wat Bool -> Wat)))
    (define (write-local fn name value tee?)
      (match (table-ref (::local-roots fn) name)
        ((Some slot)
         (let* ((store (wat "i32.store" (root-address slot)
                            (wat "local.tee" (Word (local-name fn name)) value))))
           (if tee? (wat "block" (wat "result" (Word "i32")) store (read-local fn name)) store)))
        (_ (wat (if tee? "local.tee" "local.set") (Word (local-name fn name)) value))))

    (: leave-frame (impl (Fn MemoryFunction -> Wat ! mut)))
    (define (leave-frame fn)
      (if (::framed? fn)
          (runtime-call (::module fn) "leave" (list (get-local "$lm.frame")) "void")
          (wat "nop")))

    ;; Original folded operands are evaluated once, left to right. Their own
    ;; root slots protect managed results while later operands allocate. New
    ;; construction temporaries need no extra slots: initialization cannot GC.
    (: save-operands (impl (Fn MemoryFunction (List Wat) -> (Pair (List Wat) (List Wat)) ! mut)))
    (define (save-operands fn operands)
      (let loop ((operands operands) (stores (Nil)) (reads (Nil)))
        (match operands
          ((Nil) (Pair (reverse stores) (reverse reads)))
          ((Cons operand rest)
           (if (member? (head operand)
                        (list "i32.const" "i64.const" "f32.const" "f64.const" "ref.null"))
               (loop rest stores (Cons (lower-operation fn operand) reads))
               (if
                (and (::temporary-roots? fn) (managed? (::module fn) (expression-type fn operand)))
                (let* ((value (lower-expression fn operand)) (slot (- (ref-get (::slots fn)) 1)))
                  (loop rest (Cons (wat "drop" value) stores)
                        (Cons (wat "i32.load" (root-address slot)) reads)))
                (let* ((local (fresh-local fn (expression-type fn operand)))
                       (value (lower-expression fn operand)))
                  (loop rest (Cons (wat "local.set" (Word local) value) stores)
                        (Cons (get-local local) reads)))))))))

    ;; ---- Expression types ----

    (: expression-type (impl (Fn MemoryFunction Wat -> Wat)))
    (define (expression-type fn tree)
      (let* ((op (head tree)) (args (parts tree)) (module (::module fn)))
        (cond
         ((member? op (list "local.get" "local.tee"))
          (lookup (::local-types fn) (word (at args 0))))
         ((string=? op "global.get")
          (declaration-type (lookup (::globals module) (word (at args 0)))))
         ((string=? op "call") (result-type (lookup (::functions module) (word (at args 0)))))
         ((string=? op "call_ref")
          (result-type (type-body (lookup (::types module) (word (at args 0))))))
         ((member? op (list "block" "loop" "if")) (result-type tree))
         ((member? op (list "struct.new" "struct.new_default" "array.new" "array.new_fixed"
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
         ((member? op (list "array.len" "ref.eq" "ref.is_null" "ref.test")) (Word "i32"))
         ((or (string-prefix? "i32." op) (string-prefix? "i64." op)
              (string-prefix? "f32." op) (string-prefix? "f64." op))
          (numeric-type op))
         (else (Word "void")))))

    (: number (impl (Fn String -> I64)))
    (define (number text)
      (fold-left (lambda (value c) (+ (* value 10) (- (char->integer c) 48)))
                 0 (string->list text)))

    (: numeric-type (impl (Fn String -> Wat)))
    (define (numeric-type op)
      (let* ((suffix (substring op 4 (string-length op))))
        (cond ((string-prefix? "store" suffix) (Word "void"))
              ((or (member? suffix (list "eq" "eqz" "ne" "lt" "le" "gt" "ge"))
                   (member? (substring suffix 0 (min 3 (string-length suffix)))
                            (list "lt_" "le_" "gt_" "ge_"))) (Word "i32"))
              (else (Word (substring op 0 3))))))

    ;; ---- Lowering ----

    (: lower-expression (impl (Fn MemoryFunction Wat -> Wat ! mut)))
    (define (lower-expression fn tree)
      (if (not (::temporary-roots? fn)) (lower-operation fn tree)
          (lower-rooted-expression fn tree)))

    ;; A subtree with no collecting call needs no temporary publications inside
    ;; it. Its final reference still gets a root: the next sibling may collect.
    ;; Persistent local assignments and function exits retain their frame rules.
    (: lower-rooted-expression (impl (Fn MemoryFunction Wat -> Wat ! mut)))
    (define (lower-rooted-expression fn tree)
      (let* ((first (ref-get (::slots fn)))
             (inner (if (collection-point? (::noncollecting (::module fn)) tree) fn
                        (MemoryFunction-temporary-roots?-set fn #f)))
             (value (lower-operation inner tree))
             (end (ref-get (::slots fn))) (type (expression-type fn tree)))
        (cond ((managed? (::module fn) type) (root-result fn value first end))
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
    (: lower-operation (impl (Fn MemoryFunction Wat -> Wat ! mut)))
    (define (lower-operation fn tree)
      (let* ((op (head tree)) (args (parts tree)))
        (cond
         ((string=? op "") tree)
         ((member? op (list "result" "param" "local")) (annotation tree))
         ((string=? op "local.get") (read-local fn (word (at args 0))))
         ((member? op (list "local.set" "local.tee"))
          (write-local fn
                       (word (at args 0))
                       (lower-expression fn (at args 1))
                       (string=? op "local.tee")))
         ((string=? op "global.get") (read-global fn (word (at args 0))))
         ((string=? op "global.set")
          (write-global fn (word (at args 0)) (lower-expression fn (at args 1))))
         ((string=? op "struct.new") (new-struct fn (word (at args 0)) (list-drop args 1)))
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
               (member? (word (at args 0)) (::foreign (::module fn)))
               (reference? (result-type (lookup (::functions (::module fn)) (word (at args 0))))))
          (return-value fn (list (wat* "call" args))))
         ((member? op (list "return_call" "return_call_ref")) (tail-call fn op args))
         ((string=? op "return") (return-value fn args))
         ((member? op (list "struct.new_default" "br_on_cast" "br_on_null" "try_table"))
          (panic (string-append "internal error: unsupported physical instruction " op)))
         (else (wat* op (map (lambda (arg) (lower-expression fn arg)) args))))))

    (: lower-call (impl (Fn MemoryFunction (List Wat) -> Wat ! mut)))
    (define (lower-call fn args)
      (let* ((module (::module fn)) (name (word (at args 0)))
             (type (result-type (lookup (::functions module) name)))
             (value (call name (map (lambda (arg) (lower-expression fn arg)) (list-drop args 1)))))
        (if (and (member? name (::foreign module)) (reference? type))
            (call "$lm.foreign-value" (list value (host-type module type))) value)))

    (: read-global (impl (Fn MemoryFunction String -> Wat)))
    (define (read-global fn name)
      (if (managed? (::module fn) (declaration-type (lookup (::globals (::module fn)) name)))
          (wat "i32.load" (get-global name)) (get-global name)))

    (: write-global (impl (Fn MemoryFunction String Wat -> Wat)))
    (define (write-global fn name value)
      (if (managed? (::module fn) (declaration-type (lookup (::globals (::module fn)) name)))
          (wat "i32.store" (get-global name) value) (wat "global.set" (Word name) value)))

    (: reference-operation (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (reference-operation fn op args)
      (cond ((string=? op "ref.null") (c32 0))
            ((string=? op "ref.func") (code-address (::module fn) (word (at args 0))))
            ((string=? op "ref.eq")
             (wat* "i32.eq" (map (lambda (arg) (lower-expression fn arg)) args)))
            ((string=? op "ref.is_null") (wat "i32.eqz" (lower-expression fn (at args 0))))
            ((string=? op "ref.as_non_null")
             (call "$lm.nonnull" (list (lower-expression fn (at args 0)))))
            ((member? op (list "ref.cast" "ref.test")) (cast-reference fn op args))
            (else (panic (string-append "internal error: unsupported reference instruction " op)))))

    (: cast-reference (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (cast-reference fn op args)
      (let* ((type (at args 0)) (name (heap-name type))
             (nullable (member? "null" (map word (parts type))))
             (value (lower-expression fn (at args 1)))
             (code? (reference-code? (::module fn) type)))
        (runtime-call (::module fn)
                      (if code? (if (string=? op "ref.test") "host-check" "code-cast")
                          (if (string=? op "ref.test") "test" "cast"))
                      (list value (tag name)
                            (c32 (if (and code? (string=? op "ref.test"))
                                     (+ 5 (if nullable 2 0)) (if nullable 1 0)))) "i32")))

    (: code-address (impl (Fn MemoryModule String -> Wat)))
    (define (code-address module name)
      (match (table-ref (::codes module) name)
        ((Some index) (wat "i32.load" (code-cell module index)))
        (_ (panic (string-append "internal error: undeclared function reference " name)))))

    (: code-cell (impl (Fn MemoryModule I64 -> Wat)))
    (define (code-cell module index)
      (wat "i32.add" (get-global "$lm.roots") (c32 (+ 8 (* 4 (+ (::code-start module) index))))))

    (: indirect-arguments (impl (Fn (List Wat) -> (List Wat))))
    (define (indirect-arguments args)
      (match (reverse args)
        ((Cons code rest) (reverse (Cons (call "$lm.code-index" (list code)) rest)))
        (_ (panic "internal error: indirect call without code"))))

    (: return-value (impl (Fn MemoryFunction (List Wat) -> Wat ! mut)))
    (define (return-value fn args)
      (let* ((body (map (lambda (arg) (lower-expression fn arg)) args)))
        (if (null? (result-annotation (::result fn)))
            (wat "return" (wat* "block" (append body (list (leave-frame fn)))))
            (let* ((value (value-local (::result fn))))
              (wat "return" (wat* "block" (append (result-annotation (::result fn))
                                                  (list (wat "local.set" (Word value)
                                                             (wat* "block"
                                                                   (append (result-annotation
                                                                            (::result fn))
                                                                           body)))
                                                        (leave-frame fn) (get-local value)))))))))

    (: tail-call (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (tail-call fn op args)
      (let* ((saved (save-operands fn (list-drop args 1))))
        (wat "return"
             (wat* "block" (concatenate (list (result-annotation (::result fn)) (::first saved)
                                              (list (leave-frame fn)
                                                    (wat* (if (string=? op "return_call")
                                                              op
                                                              "return_call_indirect")
                                                          (Cons (if (string=? op "return_call")
                                                                    (at args 0)
                                                                    (wat "type" (at args 0)))
                                                                (if (string=? op "return_call")
                                                                    (::second saved)
                                                                    (indirect-arguments
                                                                     (::second saved))))))))))))

    (: new-struct (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (new-struct fn name operands)
      (let* ((fields (fields-of (::module fn) name)) (saved (save-operands fn operands))
             (object "$lm.object"))
        (wat* "block" (concatenate (list (list (wat "result" (Word "i32"))) (::first saved)
                                         (list (wat "local.set" (Word object)
                                                    (runtime-call (::module fn) "alloc"
                                                                  (list (c32 (struct-size fields))
                                                                        (tag name)
                                                                        (c32 0))
                                                                  "i32")))
                                         (map (lambda (index)
                                                (wat (store-op (at fields index))
                                                     (Word (string-append "offset="
                                                                          (i64->string
                                                                           (field-offset fields
                                                                                         index))))
                                                     (get-local object)
                                                     (at (::second saved) index)))
                                              (iota (length fields)))
                                         (list (get-local object)))))))

    (: struct-access (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (struct-access fn op args)
      (let* ((fields (fields-of (::module fn) (word (at args 0))))
             (index (number (word (at args 1)))) (offset (field-offset fields index)))
        (if (string=? op "struct.get")
            (wat (load-op (at fields index) "u")
                 (Word (string-append "offset=" (i64->string offset)))
                 (call "$lm.nonnull" (list (lower-expression fn (at args 2)))))
            (let* ((saved (save-operands fn (list-drop args 2))))
              (wat* "block" (append (::first saved)
                                    (list (wat (store-op (at fields index))
                                               (Word (string-append "offset=" (i64->string offset)))
                                               (call "$lm.nonnull" (list (at (::second saved) 0)))
                                               (at (::second saved) 1)))))))))

    ;; ---- Arrays ----

    (: array-operation (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (array-operation fn op args)
      (cond ((string=? op "array.len")
             (wat "i32.load" (Word "offset=4")
                  (call "$lm.nonnull" (list (lower-expression fn (at args 0))))))
            ((member? op (list "array.get" "array.get_u" "array.get_s" "array.set"))
             (array-access fn op args))
            ((string=? op "array.copy") (array-copy fn args))
            ((member? op (list "array.new" "array.new_fixed" "array.new_default" "array.new_data"))
             (new-array fn op args))
            (else (panic (string-append "internal error: unsupported array instruction " op)))))

    (: array-address (impl (Fn Wat Wat I64 -> Wat)))
    (define (array-address array index stride)
      (call "$lm.index" (list array index (c32 stride))))

    (: array-access (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (array-access fn op args)
      (let* ((element (array-element (::module fn) (word (at args 0)))))
        (if (string=? op "array.set")
            (let* ((saved (save-operands fn (list-drop args 1))))
              (wat* "block" (append (::first saved)
                                    (list (wat (store-op element)
                                               (array-address (at (::second saved) 0)
                                                              (at (::second saved) 1)
                                                              (width element))
                                               (at (::second saved) 2))))))
            (wat (load-op element (if (string=? op "array.get_s") "s" "u"))
                 (array-address (lower-expression fn (at args 1))
                                (lower-expression fn (at args 2)) (width element))))))

    (: array-copy (impl (Fn MemoryFunction (List Wat) -> Wat ! mut)))
    (define (array-copy fn args)
      (let* ((stride (width (array-element (::module fn) (word (at args 0)))))
             (saved (save-operands fn (list-drop args 2))) (values (::second saved)))
        (wat* "block" (append (::first saved)
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

    (: new-array (impl (Fn MemoryFunction String (List Wat) -> Wat ! mut)))
    (define (new-array fn op args)
      (let* ((name (word (at args 0))) (element (array-element (::module fn) name))
             (skip (if (member? op (list "array.new_fixed" "array.new_data")) 2 1))
             (saved (save-operands fn (list-drop args skip)))
             (values (::second saved)) (object "$lm.object")
             (count (if (string=? op "array.new_fixed") (c32 (number (word (at args 1))))
                        (at (reverse values) 0))))
        (wat* "block" (concatenate (list (list (wat "result" (Word "i32"))) (::first saved)
                                         (list (wat "local.set" (Word object)
                                                    (runtime-call (::module fn)
                                                                  "array"
                                                                  (list (tag name)
                                                                        count
                                                                        (c32 (width element)))
                                                                  "i32")))
                                         (initialize-array op args element values object count)
                                         (list (get-local object)))))))

    (: initialize-array
       (impl (Fn String (List Wat) Wat (List Wat) String Wat -> (List Wat))))
    (define (initialize-array op args element values object count)
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

    (: fill-array (impl (Fn Wat Wat String Wat -> (List Wat))))
    (define (fill-array element value object count)
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

    (: result-annotation (impl (Fn Wat -> (List Wat))))
    (define (result-annotation type)
      (if (string=? (head type) "")
          (if (string=? (word type) "void") (Nil) (list (wat "result" (physical-type type))))
          (list (wat "result" (physical-type type)))))

    (: bind-function-local (impl (Fn MemoryFunction Wat I64 -> MemoryFunction ! mut)))
    (define (bind-function-local fn declaration index)
      (let* ((type (at (reverse (parts declaration)) 0))
             (number (i64->string index))
             (name (if (named? (at (parts declaration) 0)) (word (at (parts declaration) 0))
                       (string-append "$lm.local." number)))
             (slot (if (and (::framed? fn) (managed? (::module fn) type)) (root-slot fn) -1)))
        (MemoryFunction (::module fn)
                        (::framed? fn)
                        (::temporary-roots? fn)
                        (table-set (table-set (::local-types fn) name type) number type)
                        (table-set (table-set (::local-names fn) name name) number name)
                        (if (< slot 0) (::local-roots fn)
                            (table-set (table-set (::local-roots fn) name slot) number slot))
                        (::locals fn) (::names fn) (::slots fn) (::result fn))))

    (: function-context (impl (Fn MemoryModule Wat -> MemoryFunction ! mut)))
    (define (function-context module function)
      ;; A collecting function also roots its module owner: even a function
      ;; with only scalar parameters can be executing retired module code.
      (let* ((framed? (not (table-contains? (::noncollecting module) (member-name function))))
             (declarations
              (append (pick "param" (parts function)) (pick "local" (parts function)))))
        (fold-left (lambda (fn index) (bind-function-local fn (at declarations index) index))
                   (MemoryFunction module
                                   framed?
                                   framed?
                                   empty-table
                                   empty-table
                                   empty-table
                                   (ref (Nil))
                                   (ref 0)
                                   (ref (if framed? 1 0))
                                   (result-type function)) (iota (length declarations)))))

    (: parameter-root (impl (Fn MemoryFunction I64 -> (List Wat))))
    (define (parameter-root fn index)
      (let* ((number (i64->string index)))
        (match (table-ref (::local-roots fn) number)
          ((Some slot)
           (list (wat "i32.store" (root-address slot) (get-local (local-name fn number)))))
          (_ (Nil)))))

    (: local-declarations (impl (Fn MemoryFunction Wat -> (List Wat))))
    (define (local-declarations fn function)
      (let* ((declarations
              (append (pick "param" (parts function)) (pick "local" (parts function)))))
        (map (lambda (index)
               (let* ((old (at declarations index)))
                 (wat (head old) (Word (local-name fn (i64->string index)))
                      (physical-type (at (reverse (parts old)) 0)))))
             (iota (length declarations)))))

    (: function-code (impl (Fn Wat -> (List Wat))))
    (define (function-code function)
      (filter (lambda (part)
                (and (not (named? part))
                     (not (member? (head part) (list "param" "result" "local" "type" "export")))))
              (parts function)))

    (: lower-function (impl (Fn MemoryModule Wat -> Wat ! mut)))
    (define (lower-function module function)
      (let* ((fn (function-context module function))
             (body (map (lambda (tree) (lower-expression fn tree)) (function-code function)))
             (result (::result fn))
             (returned (if (null? (result-annotation result)) "" (value-local result)))
             (count (ref-get (::slots fn))))
        (wat* "func" (concatenate (list (list (at (parts function) 0))
                                        (pick "export" (parts function))
                                        (pick "type" (parts function))
                                        (pick "param" (local-declarations fn function))
                                        (result-annotation result)
                                        (pick "local" (local-declarations fn function))
                                        (list (wat "local" (Word "$lm.frame") (Word "i32")))
                                        (scratch-locals)
                                        (reverse (ref-get (::locals fn)))
                                        (function-prologue fn function count)
                                        (finish-function fn body returned count))))))

    (: function-prologue (impl (Fn MemoryFunction Wat I64 -> (List Wat) ! mut)))
    (define (function-prologue fn function count)
      (if (= count 0) (Nil)
          (Cons (wat "local.set" (Word "$lm.frame")
                     (runtime-call (::module fn) "enter" (list (c32 count)) "i32"))
                (Cons (wat "i32.store" (root-address 0) (get-global "$lm.roots"))
                      (concatenate (map (lambda (index) (parameter-root fn index))
                                        (iota (length (pick "param" (parts function))))))))))

    ;; Leaving a frame is noncollecting. A return value, or all arguments of a
    ;; tail call, crosses to the next prologue without a collection boundary.
    (: finish-function (impl (Fn MemoryFunction (List Wat) String I64 -> (List Wat) ! mut)))
    (define (finish-function fn body returned count)
      (let* ((leave (if (= count 0) (Nil) (list (leave-frame fn)))))
        (if (string=? returned "") (append body leave)
            (concatenate (list (list (wat "local.set" (Word returned)
                                          (wat* "block"
                                                (append (result-annotation (::result fn)) body))))
                               leave (list (get-local returned)))))))

    ;; ---- Checked memory operations ----

    (: memory-helpers (impl (Fn -> (List Wat))))
    (define (memory-helpers)
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

    ;; ---- Shared recursion groups ----

    (struct MemorySetup
      ((declarations (List Wat))
       (initializers (List Wat))
       (data (List Wat))))

    (: words (impl (Fn Wat -> (List String))))
    (define (words tree)
      (match tree ((Word text) (list text)) ((Node items) (concatenate (map words items)))))

    (: replace-words (impl (Fn (Table String) Wat -> Wat)))
    (define (replace-words names tree)
      (match tree
        ((Word text)
         (match (table-ref names text) ((Some replacement) (Word replacement)) (_ tree)))
        ((Node items) (Node (map (lambda (item) (replace-words names item)) items)))))

    (: numbered-names (impl (Fn String (List String) (Table String) -> (Table String))))
    (define (numbered-names prefix names table)
      (fold-left (lambda (table index)
                   (table-set table
                              (list-ref names index)
                              (string-append prefix (i64->string index))))
                 table (iota (length names))))

    (: global-i32 (impl (Fn String -> Wat)))
    (define (global-i32 name)
      (wat "global" (Word name) (wat "mut" (Word "i32")) (c32 0)))

    (: group-members (impl (Fn Wat -> (List Wat))))
    (define (group-members group)
      (if (string=? (head group) "rec") (parts group) (list group)))

    (: member-name (impl (Fn Wat -> String)))
    (define (member-name member) (word (at (parts member) 0)))

    (: group-dependencies (impl (Fn MemoryModule Wat (List String) -> (List String))))
    (define (group-dependencies module group members)
      (backend-sort string<?
                    (delete-duplicates string=?
                                       (filter (lambda (name)
                                                 (and (table-contains? (::types module) name)
                                                      (not (member? name members))))
                                               (words group)))))

    (: setup-group (impl (Fn MemoryModule Wat I64 -> MemorySetup ! mut)))
    (define (setup-group module group index)
      (let* ((members (group-members group)) (names (map member-name members))
             (dependencies (group-dependencies module group names))
             (renaming (numbered-names "$dependency." dependencies
                                       (numbered-names "$member." names empty-table)))
             (text (wat->text (replace-words renaming group)))
             (bytes (length (concatenate (map (lambda (c) (utf-8-bytes (char->integer c)))
                                              (string->list text)))))
             (segment (string-append "$lm.types." (i64->string index))))
        (MemorySetup (map (lambda (name) (global-i32 (tag-id name))) names)
                     (concatenate (list (list (wat "memory.init" (Word segment)
                                                   (runtime-call module
                                                                 "type-key"
                                                                 (list (c32 bytes))
                                                                 "i32")
                                                   (c32 0)
                                                   (c32 bytes)))
                                        (map (lambda (name)
                                               (runtime-call module
                                                             "type-dependency"
                                                             (list (tag name))
                                                             "void"))
                                             dependencies)
                                        (list (wat "local.set" (Word "$lm.group")
                                                   (runtime-call module
                                                                 "type-group"
                                                                 (list (c32 (length names)))
                                                                 "i32")))
                                        (map (lambda (offset)
                                               (wat "global.set"
                                                    (Word (tag-id (list-ref names offset)))
                                                    (wat "i32.add"
                                                         (get-local "$lm.group")
                                                         (c32 offset))))
                                             (iota (length names)))
                                        (concatenate
                                         (map (lambda (member) (setup-parent module member))
                                              members))))
                     (list (wat "data" (Word segment) (wat-string text))))))

    (: setup-parent (impl (Fn MemoryModule Wat -> (List Wat) ! mut)))
    (define (setup-parent module member)
      (let* ((body (at (parts member) 1)))
        (if (string=? (head body) "sub")
            (map (lambda (parent)
                   (runtime-call module
                                 "type-parent"
                                 (list (tag (member-name member)) (tag (word parent)))
                                 "void"))
                 (filter named? (parts body))) (Nil))))

    (: physical-function-type (impl (Fn Wat -> Wat)))
    (define (physical-function-type member)
      (wat "type" (at (parts member) 0)
           (wat* "func" (map annotation (parts (type-body member))))))

    ;; ---- Code handles ----

    (: declared-code (impl (Fn (List Wat) -> (List String))))
    (define (declared-code fields)
      (backend-sort string<? (delete-duplicates string=?
                                                (append (concatenate (map (lambda (element)
                                                                            (map word
                                                                                 (filter named?
                                                                                         (parts
                                                                                          element))))
                                                                          (pick "elem" fields)))
                                                        (map (lambda (entry) (::second entry))
                                                             (function-exports fields))))))

    (: function-exports (impl (Fn (List Wat) -> (List (Pair String String)))))
    (define (function-exports fields)
      (concatenate (map (lambda (field)
                          (cond ((string=? (head field) "func")
                                 (map (lambda (export)
                                        (Pair (word (at (parts export) 0)) (member-name field)))
                                      (pick "export" (parts field))))
                                ((and (string=? (head field) "export")
                                      (string=? (head (at (parts field) 1)) "func"))
                                 (list (Pair (word (at (parts field) 0))
                                             (member-name (at (parts field) 1)))))
                                (else (Nil)))) fields)))

    (: code-numbers (impl (Fn (List String) -> (Table I64))))
    (define (code-numbers names)
      (fold-left (lambda (table index) (table-set table (list-ref names index) index))
                 empty-table (iota (length names))))

    (: signature-key (impl (Fn Wat -> String)))
    (define (signature-key function)
      (wat->text (signature-tree function)))

    (: signature-tree (impl (Fn Wat -> Wat)))
    (define (signature-tree function)
      (wat* "func" (append (map (lambda (param) (wat "param" (at (reverse (parts param)) 0)))
                                (pick "param" (parts function))) (pick "result" (parts function)))))

    (: function-type-name (impl (Fn MemoryModule String -> String)))
    (define (function-type-name module name)
      (let* ((function (lookup (::functions module) name)) (key (signature-key function)))
        (match (pick "type" (parts function))
          ((Cons type _) (word (at (parts type) 0)))
          (_ (match (table-ref (::signatures module) key)
               ((Some name) name)
               (_
                (panic (string-append "internal error: function handle lacks a type: " name))))))))

    (: signature-types (impl (Fn (List Wat) -> (Table String))))
    (define (signature-types types)
      (fold-left (lambda (table type)
                   (if (string=? (head (type-body type)) "func")
                       (table-set table (signature-key (type-body type)) (member-name type)) table))
                 empty-table types))

    (: setup-code (impl (Fn MemoryModule (List String) -> (List Wat) ! mut)))
    (define (setup-code module names)
      (map (lambda (index)
             (let* ((name (list-ref names index)))
               (wat "i32.store" (code-cell module index)
                    (runtime-call module "code-new"
                                  (list
                                   (call "$lm.install-code" (list (wat "ref.func" (Word name))))
                                   (tag (function-type-name module name)) (get-global "$lm.roots"))
                                  "i32"))))
           (iota (length names))))

    ;; Public entry points also have handles, including `main:body`, which the
    ;; host hands to the scheduler. A source function need not otherwise have
    ;; appeared as a value, so add its signature when no named type describes it.
    (: exported-types (impl (Fn (List Wat) (List String) -> (List Wat))))
    (define (exported-types fields codes)
      (let* ((functions (declarations "func" fields)))
        (::first
         (fold-left (lambda (state index)
                      (let* ((function (lookup functions (list-ref codes index)))
                             (key (signature-key function))
                             (name (string-append "$lm.export-type." (i64->string index))))
                        (if (table-contains? (::second state) key) state
                            (Pair (Cons (wat "type" (Word name) (signature-tree function))
                                        (::first state))
                                  (table-set (::second state) key name)))))
                    (Pair (ann (Nil) (List Wat)) (signature-types (type-definitions fields)))
                    (iota (length codes))))))

    (: handle-exports (impl (Fn MemoryModule (List Wat) -> (List Wat))))
    (define (handle-exports module fields)
      (map (lambda (entry)
             (let* ((quoted (::first entry))
                    (name (substring quoted 1 (- (string-length quoted) 1)))
                    (exported (Word (string-append "\"snail:code/" name "\""))))
               (wat "func" (wat "export" exported) (wat "result" (Word "i32"))
                    (code-address module (::second entry))))) (function-exports fields)))

    ;; The host view keeps managed results opaque and rooted. This descriptor
    ;; returns pointer/nullability/code flags in its low word and the logical
    ;; type ID in its high word. Position -1 describes the result.
    (: host-type (impl (Fn MemoryModule Wat -> Wat)))
    (define (host-type module type)
      (if (not (reference? type)) (wat "i64.const" (int 0))
          (let* ((name (heap-name type))
                 (nullable (or (not (string=? (head type) "ref")) (member? "null" (words type))))
                 (flags (+ 1 (+ (if nullable 2 0) (if (reference-code? module type) 4 0))))
                 (identity (if (table-contains? (::types module) name) (tag name) (c32 0))))
            (wat "i64.or" (wat "i64.const" (int flags))
                 (wat "i64.shl" (wat "i64.extend_i32_u" identity) (wat "i64.const" (int 32)))))))

    (: host-exports (impl (Fn MemoryModule (List Wat) -> (List Wat))))
    (define (host-exports module fields)
      (map (lambda (entry)
             (describe-host-function module (lookup (::functions module) (::second entry))
                                     (Word (string-append "\"snail:abi/"
                                                          (substring (::first entry)
                                                                     1
                                                                     (string-length
                                                                      (::first entry)))))))
           (function-exports fields)))

    (: describe-host-function (impl (Fn MemoryModule Wat Wat -> Wat)))
    (define (describe-host-function module function exported)
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

    (: foreign-exports (impl (Fn MemoryModule (List Wat) -> (List Wat))))
    (define (foreign-exports module fields)
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
                       (and (string=? (head declaration) "func") (not (source-import? field))
                            (or (reference? (result-type declaration))
                                (any? (lambda (param) (reference? (at (reverse (parts param)) 0)))
                                      (pick "param" (parts declaration)))))))
                   (pick "import" fields))))

    ;; ---- Globals and imports ----

    (: lower-import (impl (Fn Wat -> Wat)))
    (define (lower-import field)
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

    (: lower-global (impl (Fn Wat -> Wat)))
    (define (lower-global field)
      (if (reference? (declaration-type field)) (global-i32 (member-name field)) field))

    (: managed-globals (impl (Fn MemoryModule (List Wat) -> (List Wat))))
    (define (managed-globals module fields)
      (filter (lambda (field) (managed? module (declaration-type field))) (pick "global" fields)))

    (: setup-root-cells (impl (Fn MemoryModule (List Wat) -> (List Wat) ! mut)))
    (define (setup-root-cells module fields)
      (let* ((globals (managed-globals module fields)))
        (Cons (wat "global.set" (Word "$lm.roots")
                   (runtime-call module
                                 "module"
                                 (list (c32 (+ (+ (length globals) (table-count (::codes module)))
                                               (length (::dependencies module))))) "i32"))
              (append (map (lambda (index)
                             (wat "global.set" (Word (member-name (at globals index)))
                                  (wat "i32.add" (get-global "$lm.roots") (c32 (+ 8 (* index 4))))))
                           (iota (length globals)))
                      (map (lambda (index)
                             (wat "i32.store"
                                  (code-cell module (+ (table-count (::codes module)) index))
                                  (get-global
                                   (string-append "$lm.dependency." (i64->string index)))))
                           (iota (length (::dependencies module))))))))

    (: module-dependencies (impl (Fn (List Wat) -> (List String))))
    (define (module-dependencies fields)
      (backend-sort string<?
                    (delete-duplicates string=?
                                       (map (lambda (field) (word (at (parts field) 0)))
                                            (filter source-import? (pick "import" fields))))))

    ;; Source functions receive evidence; foreign scalar services do not.
    ;; Only source libraries own managed globals. Host namespaces may otherwise
    ;; have any spelling, including browser services such as snail.page.
    (: source-import? (impl (Fn Wat -> Bool)))
    (define (source-import? field)
      (let* ((declaration (at (parts field) 2)))
        (or (string=? (head declaration) "global")
            (and (string=? (head declaration) "func")
                 (match (pick "param" (parts declaration))
                   ((Cons param _)
                    (let* ((type (at (reverse (parts param)) 0)))
                      (and (reference? type) (string=? (heap-name type) "$evidence"))))
                   (_ #f))))))

    (: dependency-imports (impl (Fn MemoryModule -> (List Wat))))
    (define (dependency-imports module)
      (map (lambda (index)
             (wat "import"
                  (Word (list-ref (::dependencies module) index))
                  (wat-string "snail:gc/module-roots")
                  (wat "global"
                       (Word (string-append "$lm.dependency." (i64->string index)))
                       (wat "mut" (Word "i32")))))
           (iota (length (::dependencies module)))))

    (: foreign-functions (impl (Fn (List Wat) -> (List String))))
    (define (foreign-functions fields)
      (map (lambda (field) (member-name (at (parts field) 2)))
           (filter (lambda (field)
                     (and (string=? (head (at (parts field) 2)) "func")
                          (not (source-import? field))))
                   (pick "import" fields))))

    ;; Global constant constructors now allocate in the start function. Their
    ;; registered cells are in place before the first allocation can collect.
    (: initialize-globals (impl (Fn MemoryModule (List Wat) -> Wat ! mut)))
    (define (initialize-globals module fields)
      (lower-function module
                      (wat* "func" (Cons (Word "$lm.initialize-globals")
                                         (map (lambda (global)
                                                (wat "global.set" (Word (member-name global))
                                                     (at (reverse (parts global)) 0)))
                                              (filter (lambda (field)
                                                        (reference? (declaration-type field)))
                                                      (pick "global" fields)))))))

    ;; ---- Logical linking contracts ----

    ;; Wasm can check the numeric ABI, but erasing references loses its layout
    ;; checks. Intern the complete logical signature using the same type IDs as
    ;; casts. Imports compare these contracts before the module becomes live.
    (struct MemoryContract
      ((contract-name String)
       (symbol Wat)
       (provider (Option Wat))
       (shape Wat)))

    (: contract-shape (impl (Fn Wat -> Wat)))
    (define (contract-shape declaration)
      (if (string=? (head declaration) "func") (signature-tree declaration)
          (wat "global" (at (parts declaration) 1))))

    (: exported-contracts (impl (Fn (List Wat) -> (List MemoryContract))))
    (define (exported-contracts fields)
      (let* ((functions (declarations "func" fields)) (globals (declarations "global" fields)))
        (append
         (map (lambda (entry)
                (MemoryContract "" (Word (::first entry)) (None)
                                (signature-tree (lookup functions (::second entry)))))
              (function-exports fields))
         (map (lambda (field)
                (MemoryContract "" (at (parts field) 0) (None)
                                (contract-shape
                                 (lookup globals (member-name (at (parts field) 1))))))
              (filter (lambda (field) (string=? (head (at (parts field) 1)) "global"))
                      (pick "export" fields))))))

    (: module-contracts (impl (Fn (List Wat) -> (List MemoryContract))))
    (define (module-contracts fields)
      (let* ((contracts
              (append (exported-contracts fields)
                      (map (lambda (field)
                             (MemoryContract "" (at (parts field) 1) (Some (at (parts field) 0))
                                             (contract-shape (at (parts field) 2))))
                           (filter source-import? (pick "import" fields))))))
        (map (lambda (entry)
               (MemoryContract-contract-name-set (::first entry)
                                                 (string-append "$lm.contract."
                                                                (i64->string (::second entry)))))
             (zip contracts (iota (length contracts))))))

    (: contract-type (impl (Fn MemoryContract -> Wat)))
    (define (contract-type contract)
      (wat "type" (Word (::contract-name contract)) (wat "contract" (::shape contract))))

    (: contract-symbol (impl (Fn MemoryContract -> Wat)))
    (define (contract-symbol contract)
      (let* ((quoted (word (::symbol contract))))
        (Word (string-append "\"snail:signature/" (substring quoted 1 (string-length quoted))))))

    (: contract-declaration (impl (Fn MemoryContract -> Wat)))
    (define (contract-declaration contract)
      (match (::provider contract)
        ((Some provider)
         (wat "import" provider (contract-symbol contract)
              (wat "func" (Word (::contract-name contract)) (wat "result" (Word "i32")))))
        ((None)
         (wat "func" (wat "export" (contract-symbol contract)) (wat "result" (Word "i32"))
              (tag (::contract-name contract))))))

    (: imported-contract? (impl (Fn MemoryContract -> Bool)))
    (define (imported-contract? contract)
      (match (::provider contract) ((Some _) #t) (_ #f)))

    (: check-contracts (impl (Fn MemoryModule (List MemoryContract) -> (List Wat) ! mut)))
    (define (check-contracts module contracts)
      (map (lambda (contract)
             (wat "if"
                  (wat "i32.ne"
                       (tag (::contract-name contract))
                       (call (::contract-name contract) (Nil)))
                  (wat "then" (runtime-call module "abi-failed" (Nil) "void") (wat "unreachable"))))
           (filter imported-contract? contracts)))

    ;; ---- Module assembly ----

    (: lower-memory (impl (Fn Wat -> Wat ! mut)))
    (define (lower-memory tree)
      (let* ((fields (parts tree))
             (codes (declared-code fields))
             (fields (append fields (reverse (exported-types fields codes))))
             (contracts (module-contracts fields))
             (fields (append fields (map contract-type contracts)))
             (types (type-definitions fields))
             (module (MemoryModule (declarations "type" types)
                                   (declarations "func" fields)
                                   (signature-types types)
                                   (declarations "global" fields) (code-numbers codes)
                                   (length
                                    (filter (lambda (global) (reference? (declaration-type global)))
                                            (pick "global" fields)))
                                   (module-dependencies fields)
                                   (foreign-functions fields)
                                   (noncollecting-functions fields)
                                   (ref empty-table)))
             (groups (filter (lambda (field) (member? (head field) (list "type" "rec"))) fields))
             (setup (map (lambda (index) (setup-group module (at groups index) index))
                         (iota (length groups))))
             (functions
              (map (lambda (function) (Word (field->string (lower-function module function))))
                   (pick "func" fields)))
             (globals (initialize-globals module fields))
             (start (module-start module fields codes setup contracts))
             (allocation (allocation-helpers module)))
        (wat* "module" (concatenate (list
                                     (map physical-function-type
                                          (filter
                                           (lambda (type) (string=? (head (type-body type)) "func"))
                                           types))
                                     (map lower-import (pick "import" fields))
                                     (dependency-imports module)
                                     (map contract-declaration
                                          (filter imported-contract? contracts))
                                     (list (wat "import"
                                                (wat-string "snail.core.support")
                                                (wat-string "__indirect_function_table")
                                                (wat "table"
                                                     (Word "$lm.code")
                                                     (int 0)
                                                     (Word "funcref"))))
                                     (sorted-imports module)
                                     (concatenate (map (lambda (part) (::declarations part)) setup))
                                     (list (global-i32 "$lm.roots"))
                                     (map lower-global (pick "global" fields))
                                     (pick "export" fields)
                                     (list (wat "export"
                                                (wat-string "snail:gc/module-roots")
                                                (wat "global" (Word "$lm.roots"))))
                                     (if (null? codes)
                                         (Nil)
                                         (list (wat* "elem"
                                                     (append (list (Word "declare") (Word "func"))
                                                             (map Word codes)))))
                                     (memory-helpers)
                                     allocation
                                     (handle-exports module fields)
                                     (host-exports module fields)
                                     (foreign-exports module fields)
                                     (map contract-declaration
                                          (filter
                                           (lambda (contract) (not (imported-contract? contract)))
                                           contracts))
                                     functions (list globals start (wat "start" (Word "$lm.start")))
                                     (pick "data" fields)
                                     (concatenate (map (lambda (part) (::data part)) setup)))))))

    (: sorted-imports (impl (Fn MemoryModule -> (List Wat) ! mut)))
    (define (sorted-imports module)
      (let* ((table (ref-get (::imports module))))
        (map (lambda (key) (lookup table key)) (backend-sort string<? (table-keys table)))))

    (: module-start
       (impl (Fn MemoryModule
                 (List Wat)
                 (List String)
                 (List MemorySetup)
                 (List MemoryContract)
                 ->
                 Wat
                 ! mut)))
    (define (module-start module fields codes setup contracts)
      (wat* "func"
            (concatenate
             (list (list (Word "$lm.start") (wat "local" (Word "$lm.group") (Word "i32")))
                   (concatenate (map (lambda (part) (::initializers part)) setup))
                   (check-contracts module contracts)
                   (setup-root-cells module fields) (setup-code module codes)
                   (list (call "$lm.initialize-globals" (Nil)))))))

    ;; Collection may discover dead code handles. Clear their Wasm table slots
    ;; before reusing indices, so retired modules can release engine resources.
    ;; These helpers do not allocate managed objects while a result is in flight.
    (: allocation-helpers (impl (Fn MemoryModule -> (List Wat) ! mut)))
    (define (allocation-helpers module)
      (import-runtime module "host-check" (list "i32" "i32" "i32") "i32")
      (import-runtime module "dead-code" (Nil) "i32")
      (import-runtime module "recycle-code" (list "i32") "void")
      (import-runtime module "free-code" (Nil) "i32")
      (append
       (map allocation-wrapper
            (filter (lambda (name)
                      (table-contains? (ref-get (::imports module)) (string-append "$lm." name)))
                    (list "alloc" "array" "code-new" "module")))
       (map parse-wat
            (list
             "(func $lm.flush-code (local $index i32)
                (block $done (loop $next
                  (local.set $index (call $lm.dead-code))
                  (br_if $done (i32.eqz (local.get $index)))
                  (table.set $lm.code (local.get $index) (ref.null func))
                  (call $lm.recycle-code (local.get $index)) (br $next))))"
             "(func $lm.install-code (param $code funcref) (result i32) (local $index i32)
                (local.set $index (call $lm.free-code))
                (if (i32.eqz (local.get $index))
                  (then (local.set $index (table.grow $lm.code (local.get $code) (i32.const 1)))
                        (if (i32.eq (local.get $index) (i32.const -1)) (then (unreachable))))
                  (else (table.set $lm.code (local.get $index) (local.get $code))))
                (local.get $index))"))))

    (: allocation-wrapper (impl (Fn String -> Wat)))
    (define (allocation-wrapper name)
      (let* ((count (if (string=? name "module") 1 3)))
        (wat* "func" (concatenate
                      (list (list (Word (string-append "$lm.allocate." name)))
                            (map (lambda (_) (wat "param" (Word "i32"))) (iota count))
                            (list (wat "result" (Word "i32"))
                                  (wat "local" (Word "$value") (Word "i32"))
                                  (wat "local.set" (Word "$value") (call (string-append "$lm." name)
                                                                         (map (lambda (index)
                                                                                (wat "local.get"
                                                                                     (int index)))
                                                                              (iota count))))
                                  (call "$lm.flush-code" (Nil)) (get-local "$value")))))))
    ))
