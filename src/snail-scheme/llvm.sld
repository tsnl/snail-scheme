(define-library (snail-scheme llvm)
  (export wat->llvm wat-file->llvm-file)
  (import (scheme base) (scheme case-lambda) (scheme char) (scheme cxr)
          (scheme file) (scheme inexact) (scheme write)
          (only (scheme bytevector) bytevector-ieee-double-set! bytevector-u64-ref endianness
                bytevector-ieee-single-set! bytevector-ieee-single-ref)
          (srfi 69) (snail-scheme wat))
  (begin

    ;; ---- Text and native types ----

    (define (text . pieces)
      (let ((port (open-output-string)))
        (for-each (lambda (piece) (display piece port)) pieces)
        (get-output-string port)))

    (define (join pieces separator)
      (if (null? pieces) ""
          (let loop ((rest (cdr pieces)) (result (car pieces)))
            (if (null? rest) result
                (loop (cdr rest) (string-append result separator (car rest)))))))

    (define (prefix? prefix string)
      (and (<= (string-length prefix) (string-length string))
           (string=? prefix (substring string 0 (string-length prefix)))))

    (define (hex number width)
      (let ((digits (string-upcase (number->string number 16))))
        (string-append (make-string (max 0 (- width (string-length digits))) #\0) digits)))

    (define (quoted name)
      (text "\"" (apply string-append
                        (map (lambda (char)
                               (if (and (char<=? #\space char #\~)
                                        (not (memv char '(#\\ #\"))))
                                   (string char) (text "\\" (hex (char->integer char) 2))))
                             (string->list (wat-text name)))) "\""))

    (define (symbol-name prefix name)
      (text "@" (quoted (text prefix (wat-text name)))))

    (define (value-type type)
      (cond ((and (pair? type) (eq? (car type) 'ref)) "i64")
            ((memq type '(i8 i16 i32)) "i32")
            ((eq? type 'i64) "i64")
            ((eq? type 'f32) "float")
            ((eq? type 'f64) "double")
            ((memq type '(eqref anyref i31ref structref arrayref funcref
                                nullref nullfuncref)) "i64")
            (else (error "unsupported native Wasm value type" type))))

    (define (storage-type type)
      (if (memq type '(i8 i16)) (symbol->string type) (value-type type)))

    (define (field-type field)
      (let ((type (car (reverse (cdr field)))))
        (if (and (pair? type) (eq? (car type) 'mut)) (cadr type) type)))

    (define (zero type)
      (if (member type '("double" "float")) "0.0" "0"))

    (define (typed value) (text (car value) " " (cdr value)))
    (define (constant type word) (cons type (text word)))

    (define (float-bits number)
      (let ((bytes (make-bytevector 8)))
        (bytevector-ieee-double-set! bytes 0 (inexact number) (endianness little))
        (bytevector-u64-ref bytes 0 (endianness little))))

    (define (round-single number)
      (let ((bytes (make-bytevector 4)))
        (bytevector-ieee-single-set! bytes 0 (inexact number) (endianness little))
        (bytevector-ieee-single-ref bytes 0 (endianness little))))

    (define (float-magnitude-bits body single?)
      (cond ((string=? body "inf") (* 2047 (expt 2 52)))
            ((prefix? "nan:0x" body)
             (+ (* 2047 (expt 2 52)) (* (if single? (expt 2 29) 1)
                                        (string->number (substring body 6) 16))))
            (else (let ((number (wat-number body)))
                    (float-bits (if single? (round-single number) number))))))

    (define (float-constant atom single?)
      ;; LLVM writes both widths in double notation. Keep the sign bit separate
      ;; so negative zero and signed NaN payloads survive the Scheme reader.
      (let* ((string (wat-text atom)) (negative? (prefix? "-" string))
             (body (if negative? (substring string 1) string)))
        (text "0x" (hex (+ (if negative? (expt 2 63) 0)
                           (float-magnitude-bits body single?)) 16))))

    ;; ---- Declarations ----

    ;; One pass records the validated module's declarations. Function bodies
    ;; stay folded WAT, with no Scheme IR and no extra expression language.
    ;; Heap headers encode a canonical type identity and its abstract category:
    ;; function = 0, struct = 2, array = 3. Odd references are immediate i31s.

    (define-record-type <module>
      (make-module types signatures functions globals declarations output)
      module?
      (types module-types) (signatures module-signatures) (functions module-functions)
      (globals module-globals)
      (declarations module-declarations) (output module-output))

    (define-record-type <function>
      (make-function name params result locals body import type)
      function?
      (name function-name) (params function-params) (result function-result)
      (locals function-locals) (body function-body) (import function-import)
      (type function-wasm-type))

    (define current-module (make-parameter #f))

    (define (lookup table name)
      (hash-table-ref table name (lambda () (error "unknown Wasm declaration" name))))

    (define (type-info name) (lookup (module-types (current-module)) name))
    (define (function-info name) (lookup (module-functions (current-module)) name))
    (define (global-info name) (lookup (module-globals (current-module)) name))
    (define (type-id name) (car (type-info name)))
    (define (type-definition name) (cdr (type-info name)))

    (define (flatten-declarations declarations)
      (apply append
             (map (lambda (node) (if (eq? (car node) 'rec) (cdr node) (list node)))
                  declarations)))

    (define (signature-parts node tag)
      (apply append (map (lambda (item) (if (eq? (car item) tag) (cdr item) '())) node)))

    (define (local-declarations node index)
      (if (wat-name? (cadr node)) (list (cons (cadr node) (caddr node)))
          (map (lambda (type index) (cons (string->symbol (number->string index)) type))
               (cdr node) (iota (length (cdr node)) index))))

    (define (named-locals declarations tag start)
      (let loop ((nodes (filter (lambda (node) (eq? (car node) tag)) declarations))
                 (index start) (result '()))
        (if (null? nodes) (reverse result)
            (let ((locals (local-declarations (car nodes) index)))
              (loop (cdr nodes) (+ index (length locals))
                    (append (reverse locals) result))))))

    (define (iota count start)
      (let loop ((index 0) (result '()))
        (if (= index count) (reverse result)
            (loop (+ index 1) (cons (+ start index) result)))))

    (define (result-type nodes)
      (let ((results (signature-parts nodes 'result)))
        (case (length results)
          ((0) "void") ((1) (value-type (car results)))
          (else (error "native multivalue Wasm signatures are unsupported" results)))))

    (define (parse-function node import)
      (let* ((parts (cddr node)) (params (named-locals parts 'param 0)))
        (make-function
         (cadr node) params (result-type parts)
         (named-locals parts 'local (length params))
         (filter (lambda (item) (not (memq (car item) '(param result local type)))) parts)
         import (let ((types (signature-parts parts 'type)))
                  (if (pair? types) (car types)
                      (list (map cdr params) (signature-parts parts 'result)))))))

    (define (filter predicate items)
      (let loop ((rest items) (kept '()))
        (cond ((null? rest) (reverse kept))
              ((predicate (car rest)) (loop (cdr rest) (cons (car rest) kept)))
              (else (loop (cdr rest) kept)))))

    (define (record-type! node)
      (let* ((table (module-types (current-module)))
             (definition (caddr node))
             (category (case (car definition) ((func) 0) ((struct) 2) ((array) 3)
                             (else (error "unsupported native Wasm heap type" definition)))))
        (hash-table-set! table (cadr node)
                         (cons (+ (* 4 (+ 1 (hash-table-size table))) category) definition))
        (when (eq? (car definition) 'func)
          (result-type (cdr definition))
          (hash-table-set! (module-signatures (current-module))
                           (list (signature-parts (cdr definition) 'param)
                                 (signature-parts (cdr definition) 'result)) (cadr node)))))

    (define (record-function! node import)
      (hash-table-set! (module-functions (current-module)) (cadr node)
                       (parse-function node import)))

    (define (record-declaration! node)
      (case (car node)
        ((type) (record-type! node))
        ((func) (record-function! node #f))
        ((import)
         (unless (eq? (car (cadddr node)) 'func) (error "native nonfunction import" node))
         (record-function! (cadddr node) (list (cadr node) (caddr node))))
        ((global) (hash-table-set! (module-globals (current-module)) (cadr node) node))
        ((table memory data elem export start) #f)
        (else (error "unsupported native Wasm declaration" (car node)))))

    (define (function-type name)
      (let ((type (function-wasm-type (function-info name))))
        ;; Binaryen omits an explicit (type ...) on nonrecursive signatures.
        ;; Index their original Wasm shapes before erasing references to i64.
        (if (symbol? type) type (lookup (module-signatures (current-module)) type))))

    ;; ---- Native function state ----

    ;; Locals and structured joins use entry-block slots. LLVM promotes them to
    ;; SSA; this keeps Wasm branch values explicit without a second CFG pass.
    ;; A false current block means control cannot fall through. Every operand
    ;; preserves left-to-right evaluation, including an operand which branches.

    (define-record-type <emitter>
      (make-emitter locals targets serial block port slots)
      emitter?
      (locals emitter-locals)
      (targets emitter-targets set-emitter-targets!)
      (serial emitter-serial set-emitter-serial!)
      (block emitter-block set-emitter-block!) (port emitter-port)
      (slots emitter-slots set-emitter-slots!))

    (define current-emitter (make-parameter #f))
    (define abort-expression (make-parameter #f))

    (define (fresh prefix)
      (let* ((emitter (current-emitter)) (number (+ 1 (emitter-serial emitter))))
        (set-emitter-serial! emitter number)
        (text prefix number)))

    (define (alive?) (emitter-block (current-emitter)))

    (define (line . pieces)
      (unless (alive?) (error "LLVM emission after terminator" pieces))
      (display (text "  " (apply text pieces) "\n") (emitter-port (current-emitter))))

    (define (instruction type . pieces)
      (let ((name (fresh "%v")))
        (apply line name " = " pieces)
        (constant type name)))

    (define (finish . pieces)
      (apply line pieces)
      (set-emitter-block! (current-emitter) #f))

    (define (label name)
      (display (text name ":\n") (emitter-port (current-emitter)))
      (set-emitter-block! (current-emitter) name))

    (define (slot type)
      (let* ((name (fresh "%slot")) (emitter (current-emitter)))
        (set-emitter-slots! emitter
                            (cons (text "  " name " = alloca " type ", align 8\n")
                                  (emitter-slots emitter)))
        (constant type name)))

    (define (store value pointer)
      (line "store " (typed value) ", ptr " (cdr pointer) ", align 1"))

    (define (load pointer)
      (instruction (car pointer) "load " (car pointer) ", ptr " (cdr pointer) ", align 1"))

    (define (operand node)
      (let ((value (emit-expression node)))
        (if (alive?) value ((abort-expression) #f))))

    (define (operands nodes)
      (if (null? nodes) '()
          (let ((first (operand (car nodes)))) (cons first (operands (cdr nodes))))))

    (define (emit-sequence nodes)
      (let loop ((nodes nodes) (value #f))
        (if (or (null? nodes) (not (alive?))) value
            (loop (cdr nodes) (emit-expression (car nodes))))))

    (define (truth value)
      (instruction "i1" "icmp ne " (typed value) ", 0"))

    (define (boolean value)
      (instruction "i32" "zext " (typed value) " to i32"))

    (define (cast opcode value type)
      (if (string=? type (car value)) value
          (instruction type opcode " " (typed value) " to " type)))

    (define (call-native name result arguments)
      (let ((call (text "call " result " @" name "(" (join (map typed arguments) ", ") ")")))
        (if (string=? result "void") (begin (line call) #f)
            (instruction result call))))

    (define (trap-unless condition)
      (let ((yes (fresh "ok")) (no (fresh "trap")))
        (finish "br " (typed condition) ", label %" yes ", label %" no)
        (label no)
        (line "call void @native_trap()")
        (finish "unreachable")
        (label yes)))

    (define (nonnull value)
      (trap-unless (instruction "i1" "icmp ne " (typed value) ", 0"))
      value)

    (define (return-value value)
      (if value (finish "ret " (typed value)) (finish "ret void")))

    ;; ---- Structured control flow ----

    ;; Targets contain (Wasm name, LLVM label, optional result slot, reached?).
    ;; Loop backedges have no result; block exits and if joins carry one value.

    (define (target name)
      (or (let loop ((targets (emitter-targets (current-emitter))))
            (and (pair? targets)
                 (if (equal? (vector-ref (car targets) 0) name) (car targets)
                     (loop (cdr targets)))))
          (error "unknown Wasm branch target" name)))

    (define (record-edge! destination value)
      (let ((slot (vector-ref destination 2)))
        (when slot
          (unless value (error "missing Wasm branch value" destination))
          (store value slot))
        (vector-set! destination 3 #t)))

    (define (jump destination value)
      (record-edge! destination value)
      (finish "br label %" (vector-ref destination 1)))

    (define (join-target destination)
      (if (vector-ref destination 3)
          (begin (label (vector-ref destination 1))
                 (and (vector-ref destination 2) (load (vector-ref destination 2))))
          #f))

    (define (control-parts nodes)
      (let* ((named? (and (pair? nodes) (wat-name? (car nodes))))
             (name (and named? (car nodes)))
             (nodes (if named? (cdr nodes) nodes))
             (result? (and (pair? nodes) (eq? (caar nodes) 'result))))
        (list name (if result? (result-type (list (car nodes))) "void")
              (if result? (cdr nodes) nodes))))

    (define (emit-block nodes loop?)
      (let* ((parts (control-parts nodes)) (result (cadr parts))
             (exit (vector (car parts) (fresh "block")
                           (and (not (string=? result "void")) (slot result)) #f))
             (entry (if loop? (vector (car parts) (fresh "loop") #f #f) exit))
             (emitter (current-emitter)) (old (emitter-targets emitter)))
        (when loop? (jump entry #f) (label (vector-ref entry 1)))
        (set-emitter-targets! emitter (cons entry old))
        (let ((value (emit-sequence (caddr parts))))
          (when (alive?) (jump exit value)))
        (set-emitter-targets! emitter old)
        (join-target exit)))

    (define (emit-if nodes)
      (let* ((parts (control-parts nodes)) (result (cadr parts)) (body (caddr parts))
             (condition (truth (operand (car body))))
             (yes (fresh "then")) (no (fresh "else"))
             (exit (vector #f (fresh "join")
                           (and (not (string=? result "void")) (slot result)) #f)))
        (finish "br " (typed condition) ", label %" yes ", label %" no)
        (label yes)
        (let ((value (emit-sequence (cdadr body)))) (when (alive?) (jump exit value)))
        (label no)
        (let ((value (and (pair? (cddr body)) (emit-sequence (cdaddr body)))))
          (when (alive?) (jump exit value)))
        (join-target exit)))

    (define (emit-branch nodes conditional?)
      (let* ((destination (target (car nodes))) (values (operands (cdr nodes)))
             (value (and (> (length values) (if conditional? 1 0)) (car values))))
        (if (not conditional?) (begin (jump destination value) #f)
            (let ((fallthrough (fresh "next")) (condition (truth (car (reverse values)))))
              (record-edge! destination value)
              (finish "br " (typed condition) ", label %" (vector-ref destination 1)
                      ", label %" fallthrough)
              (label fallthrough)
              value))))

    (define (emit-branch-table nodes)
      (let* ((names (filter wat-name? nodes))
             (values (operands (filter pair? nodes)))
             (value (and (= (length values) 2) (car values)))
             (index (car (reverse values))) (destinations (map target names))
             (default (car (reverse destinations))))
        (for-each (lambda (destination) (record-edge! destination value)) destinations)
        (line "switch " (typed index) ", label %" (vector-ref default 1) " [")
        (for-each (lambda (destination number)
                    (line "i32 " number ", label %" (vector-ref destination 1)))
                  (reverse (cdr (reverse destinations))) (iota (- (length destinations) 1) 0))
        (finish "]")
        #f))

    ;; ---- Calls and references ----

    (define (emit-call name arguments result tail?)
      ;; tailcc guarantees tail lowering even when argument counts differ.
      ;; LLVM 22 x86-64 mishandles musttail with growing stack arguments; the
      ;; executable ABI regression covers tailcc + tail across that boundary.
      (let* ((code (text (if tail? "tail " "") "call tailcc " result " " name
                         "(" (join (map typed arguments) ", ") ")"))
             (value (if (string=? result "void") (begin (line code) #f)
                        (instruction result code))))
        (when tail? (return-value value))
        value))

    (define (emit-direct-call nodes tail?)
      (let ((function (function-info (car nodes))))
        (emit-call (symbol-name "f." (car nodes)) (operands (cdr nodes))
                   (function-result function) tail?)))

    (define (field-pointer reference index type)
      (let* ((pointer (cast "inttoptr" (nonnull reference) "ptr"))
             (address (instruction "ptr" "getelementptr i64, ptr " (cdr pointer) ", i64 " index)))
        (constant type (cdr address))))

    (define (function-pointer reference)
      (load (field-pointer reference 1 "ptr")))

    (define (emit-reference-call nodes tail?)
      (let* ((type (type-definition (car nodes))) (values (operands (cdr nodes)))
             (reference (car (reverse values)))
             (arguments (reverse (cdr (reverse values)))))
        (emit-call (cdr (function-pointer reference)) arguments (result-type (cdr type)) tail?)))

    (define (table-slot name index)
      (call-native "native_table_slot" "ptr"
                   (list (constant "ptr" (symbol-name "table." name)) index)))

    (define (emit-indirect-call nodes tail?)
      (let* ((table (car nodes)) (type (cadadr nodes))
             (values (operands (cddr nodes))) (index (car (reverse values)))
             (reference (load (constant "i64" (cdr (table-slot table index)))))
             (tag (load (field-pointer reference 0 "i64"))))
        (trap-unless (instruction "i1" "icmp eq " (typed tag) ", " (type-id type)))
        (emit-call (cdr (function-pointer reference)) (reverse (cdr (reverse values)))
                   (result-type (cdr (type-definition type))) tail?)))

    (define (reference-test reference type)
      (let* ((nullable? (and (pair? type) (eq? (cadr type) 'null)))
             (heap (if (pair? type) (car (reverse type)) type))
             (tag (if (wat-name? heap) (type-id heap)
                      (case heap ((any eq) -1) ((i31) -2) ((struct) -3) ((array) -4)
                            ((func) -5) ((none nofunc) -6)
                            (else (error "unsupported native reference test" type))))))
        (if (= tag -2) (i31-test reference nullable?)
            (call-native "native_ref_test" "i32"
                         (list reference (constant "i64" tag) (constant "i32" (if nullable? 1 0)))))))

    (define (i31-test reference nullable?)
      (let* ((tag (instruction "i64" "and " (typed reference) ", 1"))
             (test (instruction "i1" "icmp ne " (typed tag) ", 0")))
        (boolean (if nullable?
                     (let ((null? (instruction "i1" "icmp eq " (typed reference) ", 0")))
                       (instruction "i1" "or " (typed test) ", " (cdr null?))) test))))

    (define (emit-ref-cast nodes)
      (let* ((reference (operand (cadr nodes)))
             (test (reference-test reference (car nodes))))
        (trap-unless (truth test))
        reference))

    (define (emit-i31 node)
      (let* ((value (operand node))
             (shifted (instruction "i32" "shl " (typed value) ", 1"))
             (signed (instruction "i32" "ashr " (typed shifted) ", 1"))
             (wide (cast "sext" signed "i64"))
             (tagged (instruction "i64" "shl " (typed wide) ", 1")))
        (instruction "i64" "or " (typed tagged) ", 1")))

    (define (emit-i31-get node signed?)
      (let* ((reference (nonnull (operand node)))
             (word (instruction "i64" "ashr " (typed reference) ", 1"))
             (payload (cast "trunc" word "i31")))
        ;; The width also tells LLVM the signed range guaranteed by Wasm.
        (cast (if signed? "sext" "zext") payload "i32")))

    ;; ---- Structs and arrays ----

    ;; Scanned, zero-filled BDWGC allocations contain uncompressed references.
    ;; Every field occupies eight bytes, including packed numeric fields.
    ;; Interior pointers stay recognizable across allocating operands and calls.

    (define (allocate-struct name values)
      (let* ((reference (call-native "native_alloc" "i64"
                                     (list (constant "i64" (+ 8 (* 8 (length values)))))))
             (fields (cdr (type-definition name))))
        (store (constant "i64" (type-id name)) (field-pointer reference 0 "i64"))
        (for-each (lambda (field value index)
                    (let ((type (storage-type (field-type field))))
                      (store (cast "trunc" value type) (field-pointer reference index type))))
                  fields values (iota (length fields) 1))
        reference))

    (define (emit-struct-new nodes default?)
      (let ((fields (cdr (type-definition (car nodes)))))
        (allocate-struct (car nodes)
                         (if default? (map (lambda (field)
                                             (let ((type (value-type (field-type field))))
                                               (constant type (zero type)))) fields)
                             (operands (cdr nodes))))))

    (define (emit-struct-get nodes signed?)
      (let* ((index (wat-number (cadr nodes)))
             (type (field-type (list-ref (cdr (type-definition (car nodes))) index)))
             (pointer (field-pointer (operand (caddr nodes)) (+ index 1) (storage-type type))))
        (cast (if signed? "sext" "zext") (load pointer) (value-type type))))

    (define (emit-struct-set nodes)
      (let* ((index (wat-number (cadr nodes)))
             (type (storage-type (field-type (list-ref (cdr (type-definition (car nodes))) index))))
             (reference (operand (caddr nodes))) (value (operand (cadddr nodes))))
        (store (cast "trunc" value type) (field-pointer reference (+ index 1) type))
        #f))

    (define (array-type name)
      (let ((type (cadr (type-definition name))))
        (if (and (pair? type) (eq? (car type) 'mut)) (cadr type) type)))

    (define (value-word value)
      (cond ((member (car value) '("double" "float"))
             (cast "zext" (cast "bitcast" value (if (string=? (car value) "double") "i64" "i32")) "i64"))
            (else (cast "zext" value "i64"))))

    (define (new-array name length initial)
      (call-native "native_array_new" "i64"
                   (list (constant "i64" (type-id name)) length (value-word initial))))

    (define (emit-array-new nodes default?)
      (let* ((type (value-type (array-type (car nodes))))
             (values (operands (cdr nodes)))
             (initial (if default? (constant type (zero type)) (car values)))
             (length (car (reverse values))))
        (new-array (car nodes) length initial)))

    (define (array-slot reference index type)
      (constant type (cdr (call-native "native_array_slot" "ptr" (list reference index)))))

    (define (emit-array-fixed nodes)
      (let* ((name (car nodes)) (length (wat-number (cadr nodes)))
             (type (storage-type (array-type name))) (values (operands (cddr nodes)))
             (reference (new-array name (constant "i32" length) (constant "i64" 0))))
        (for-each (lambda (value index)
                    (store (cast "trunc" value type)
                           (array-slot reference (constant "i32" index) type)))
                  values (iota length 0))
        reference))

    (define (emit-array-get nodes signed?)
      (let* ((type (array-type (car nodes))) (values (operands (cdr nodes)))
             (value (load (array-slot (car values) (cadr values) (storage-type type)))))
        (cast (if signed? "sext" "zext") value (value-type type))))

    (define (emit-array-set nodes)
      (let* ((type (storage-type (array-type (car nodes)))) (values (operands (cdr nodes))))
        (store (cast "trunc" (caddr values) type) (array-slot (car values) (cadr values) type))
        #f))

    ;; ---- Linear memory ----

    ;; Rust addresses remain wasm32 offsets into a distinct, unscanned memory.
    ;; Offset addition uses i64, so a large static offset cannot wrap around a
    ;; bounds check. All loads and stores permit byte alignment as Wasm does.

    (define (memory-address address offset size)
      (let* ((wide (cast "zext" address "i64"))
             (index (instruction "i64" "add " (typed wide) ", " offset)))
        (call-native "native_memory_address" "ptr" (list index (constant "i64" size)))))

    (define (memory-offset nodes)
      (let ((offsets (filter (lambda (item) (and (symbol? item) (prefix? "offset=" (wat-text item)))) nodes)))
        (if (null? offsets) 0 (string->number (substring (wat-text (car offsets)) 7)))))

    (define (memory-instruction op nodes store?)
      (let* ((opcode (symbol->string op)) (base (substring opcode 0 3))
             (type (value-type (string->symbol base)))
             (suffix (substring opcode (if store? 9 8)))
             (size (cond ((prefix? "8" suffix) 1) ((prefix? "16" suffix) 2)
                         ((prefix? "32" suffix) 4) ((string=? base "i64") 8)
                         ((string=? base "f64") 8) (else 4)))
             (narrow (if (member base '("f32" "f64")) type (text "i" (* size 8))))
             (values (operands (filter pair? nodes)))
             (address (memory-address (car values) (memory-offset nodes) size))
             (pointer (constant narrow (cdr address))))
        (if store? (begin (store (cast "trunc" (cadr values) narrow) pointer) #f)
            (cast (if (memv #\s (string->list suffix)) "sext" "zext") (load pointer) type))))

    ;; ---- Numeric operations ----

    (define integer-operations
      '((add . "add") (sub . "sub") (mul . "mul") (and . "and") (or . "or") (xor . "xor")
        (shl . "shl") (shr_s . "ashr") (shr_u . "lshr")
        (eq . "eq") (ne . "ne") (lt_s . "slt") (lt_u . "ult")
        (le_s . "sle") (le_u . "ule") (gt_s . "sgt") (gt_u . "ugt")
        (ge_s . "sge") (ge_u . "uge")))

    (define float-operations
      '((add . "fadd") (sub . "fsub") (mul . "fmul") (div . "fdiv")
        (eq . "oeq") (ne . "une") (lt . "olt") (le . "ole") (gt . "ogt") (ge . "oge")))

    (define (numeric-binary op values float?)
      (let* ((left (car values)) (right (cadr values))
             (mapping (assq op (if float? float-operations integer-operations)))
             (compare? (memq op '(eq ne lt le gt ge lt_s lt_u le_s le_u gt_s gt_u ge_s ge_u)))
             (shift? (memq op '(shl shr_s shr_u)))
             (right (if shift? (instruction (car right) "and " (typed right) ", "
                                            (if (string=? (car right) "i64") 63 31)) right))
             (value (instruction (if compare? "i1" (car left))
                                 (if compare? (if float? "fcmp " "icmp ") "")
                                 (cdr mapping) " " (typed left) ", " (cdr right))))
        (if compare? (boolean value) value)))

    (define (emit-division op values)
      (let* ((left (car values)) (right (cadr values)) (type (car left))
             (signed? (memq op '(div_s rem_s))))
        (if signed?
            (call-native (text "native_" type "_" op) type values)
            (begin (trap-unless (instruction "i1" "icmp ne " (typed right) ", 0"))
                   (instruction type (if (eq? op 'div_u) "udiv " "urem ")
                                (typed left) ", " (cdr right))))))

    (define (numeric-intrinsic name values)
      (let* ((type (car (car values)))
             (suffix (cond ((string=? type "double") "f64")
                           ((string=? type "float") "f32") (else type))))
        (call-native (text "llvm." name "." suffix) type values)))

    (define (emit-numeric op nodes)
      (let* ((name (symbol->string op)) (base (substring name 0 3))
             (operation (string->symbol (substring name 4)))
             (float? (char=? (string-ref base 0) #\f))
             (values (operands nodes)))
        (cond ((assq operation (if float? float-operations integer-operations))
               (numeric-binary operation values float?))
              ((memq operation '(div_s div_u rem_s rem_u)) (emit-division operation values))
              ((eq? operation 'eqz) (boolean (instruction "i1" "icmp eq " (typed (car values)) ", 0")))
              ((memq operation '(clz ctz popcnt))
               (numeric-intrinsic (case operation ((clz) "ctlz") ((ctz) "cttz") (else "ctpop"))
                                  (if (eq? operation 'popcnt) values
                                      (append values (list (constant "i1" "false"))))))
              ((memq operation '(rotl rotr))
               (numeric-intrinsic (if (eq? operation 'rotl) "fshl" "fshr")
                                  (list (car values) (car values) (cadr values))))
              ((eq? operation 'neg) (instruction (car (car values)) "fneg " (typed (car values))))
              ((memq operation '(abs sqrt ceil floor trunc nearest))
               (numeric-intrinsic (case operation ((abs) "fabs") ((nearest) "roundeven")
                                        (else (symbol->string operation))) values))
              ((eq? operation 'copysign) (numeric-intrinsic "copysign" values))
              (else (emit-conversion base operation values)))))

    (define (emit-conversion base operation values)
      (let* ((value (car values)) (target (value-type (string->symbol base)))
             (name (symbol->string operation)))
        (cond ((eq? operation 'wrap_i64) (cast "trunc" value target))
              ((memq operation '(extend_i32_s extend_i32_u))
               (cast (if (eq? operation 'extend_i32_s) "sext" "zext") value target))
              ((prefix? "reinterpret_" name) (cast "bitcast" value target))
              ((prefix? "convert_" name)
               (cast (if (char=? (string-ref name (- (string-length name) 1)) #\s) "sitofp" "uitofp") value target))
              ((memq operation '(trunc_f32_s trunc_f32_u trunc_f64_s trunc_f64_u))
               (call-native (text "native_" base "_" name) target values))
              ((memq operation '(extend8_s extend16_s extend32_s))
               (cast "sext" (cast "trunc" value
                                  (case operation ((extend8_s) "i8") ((extend16_s) "i16") (else "i32"))) target))
              ((eq? operation 'promote_f32) (cast "fpext" value target))
              ((eq? operation 'demote_f64) (cast "fptrunc" value target))
              (else (error "unsupported native Wasm numeric operation" base operation)))))

    ;; ---- Instruction dispatch ----

    (define (local-slot name) (lookup (emitter-locals (current-emitter)) name))

    (define (global-slot name)
      (let* ((node (global-info name)) (type (caddr node))
             (type (if (and (pair? type) (eq? (car type) 'mut)) (cadr type) type)))
        (constant (value-type type) (symbol-name "g." name))))

    (define (emit-local-set nodes tee?)
      (let ((value (operand (cadr nodes))))
        (store value (local-slot (car nodes)))
        (and tee? value)))

    (define (emit-select nodes)
      (let* ((values (operands (filter (lambda (node) (not (eq? (car node) 'result))) nodes)))
             (condition (truth (caddr values))))
        (instruction (caar values) "select " (typed condition) ", "
                     (typed (car values)) ", " (typed (cadr values)))))

    (define (emit-table op nodes)
      (let* ((pointer (constant "ptr" (symbol-name "table." (car nodes))))
             (values (operands (cdr nodes))))
        (case op
          ((table.get) (load (constant "i64" (cdr (table-slot (car nodes) (car values))))))
          ((table.set) (store (cadr values) (constant "i64" (cdr (table-slot (car nodes) (car values))))) #f)
          ((table.size) (call-native "native_table_size" "i32" (list pointer)))
          ((table.grow) (call-native "native_table_grow" "i32" (cons pointer values)))
          (else (error "unsupported native table operation" op)))))

    (define (emit-expression node)
      (call-with-current-continuation
       (lambda (abort)
         (parameterize ((abort-expression abort))
           (emit-operation (car node) (cdr node))))))

    ;; Exhaustive dispatch stays together so the supported Wasm subset is visible.
    (define (emit-operation op nodes)
      (case op
        ((block) (emit-block nodes #f)) ((loop) (emit-block nodes #t))
        ((if) (emit-if nodes)) ((br) (emit-branch nodes #f))
        ((br_if) (emit-branch nodes #t)) ((br_table) (emit-branch-table nodes))
        ((unreachable) (line "call void @native_trap()") (finish "unreachable") #f)
        ((nop) #f) ((drop) (operand (car nodes)) #f)
        ((return) (return-value (and (pair? nodes) (operand (car nodes)))) #f)
        ((select) (emit-select nodes))
        ((local.get) (load (local-slot (car nodes))))
        ((local.set) (emit-local-set nodes #f)) ((local.tee) (emit-local-set nodes #t))
        ((global.get) (load (global-slot (car nodes))))
        ((global.set) (store (operand (cadr nodes)) (global-slot (car nodes))) #f)
        ((call) (emit-direct-call nodes #f)) ((return_call) (emit-direct-call nodes #t))
        ((call_ref) (emit-reference-call nodes #f)) ((return_call_ref) (emit-reference-call nodes #t))
        ((call_indirect) (emit-indirect-call nodes #f))
        ((return_call_indirect) (emit-indirect-call nodes #t))
        ((ref.null) (constant "i64" 0))
        ((ref.func) (constant "i64" (text "ptrtoint (ptr " (symbol-name "ref." (car nodes)) " to i64)")))
        ((ref.i31) (emit-i31 (car nodes)))
        ((i31.get_s) (emit-i31-get (car nodes) #t)) ((i31.get_u) (emit-i31-get (car nodes) #f))
        ((ref.as_non_null) (nonnull (operand (car nodes))))
        ((ref.eq) (let ((values (operands nodes)))
                    (boolean (instruction "i1" "icmp eq " (typed (car values)) ", " (cdadr values)))))
        ((ref.is_null) (boolean (instruction "i1" "icmp eq " (typed (operand (car nodes))) ", 0")))
        ((ref.test) (reference-test (operand (cadr nodes)) (car nodes)))
        ((ref.cast) (emit-ref-cast nodes))
        ((struct.new) (emit-struct-new nodes #f)) ((struct.new_default) (emit-struct-new nodes #t))
        ((struct.get struct.get_u) (emit-struct-get nodes #f)) ((struct.get_s) (emit-struct-get nodes #t))
        ((struct.set) (emit-struct-set nodes))
        ((array.new) (emit-array-new nodes #f)) ((array.new_default) (emit-array-new nodes #t))
        ((array.new_fixed) (emit-array-fixed nodes))
        ((array.get array.get_u) (emit-array-get nodes #f)) ((array.get_s) (emit-array-get nodes #t))
        ((array.set) (emit-array-set nodes))
        ((array.len) (call-native "native_array_length" "i32" (operands nodes)))
        ((array.copy) (call-native "native_array_copy" "void" (operands (cddr nodes))))
        ((table.get table.set table.size table.grow) (emit-table op nodes))
        ((memory.size) (call-native "native_memory_pages" "i32" '()))
        ((memory.grow) (call-native "native_memory_grow" "i32" (operands nodes)))
        ((memory.copy) (call-native "native_memory_copy" "void" (operands nodes)))
        ((memory.fill) (call-native "native_memory_fill" "void" (operands nodes)))
        ((i32.const) (constant "i32" (wat-number (car nodes))))
        ((i64.const) (constant "i64" (wat-number (car nodes))))
        ((f64.const) (constant "double" (float-constant (car nodes) #f)))
        ((f32.const) (constant "float" (float-constant (car nodes) #t)))
        (else
         (let ((name (symbol->string op)))
           (cond ((and (> (string-length name) 7) (string=? (substring name 3 8) ".load"))
                  (memory-instruction op nodes #f))
                 ((and (> (string-length name) 8) (string=? (substring name 3 9) ".store"))
                  (memory-instruction op nodes #t))
                 ((or (prefix? "i32." name) (prefix? "i64." name)
                      (prefix? "f32." name) (prefix? "f64." name)) (emit-numeric op nodes))
                 (else (error "unsupported native Wasm instruction" op)))))))

    ;; ---- Function definitions and host boundary ----

    (define (output . pieces)
      (display (apply text pieces) (module-output (current-module)))
      (newline (module-output (current-module))))

    (define (parameter-values function)
      (map (lambda (param index) (constant (value-type (cdr param)) (text "%arg" index)))
           (function-params function) (iota (length (function-params function)) 0)))

    (define (initialize-locals function)
      (let* ((params (function-params function))
             (locals (append params (function-locals function))))
        (for-each
         (lambda (local index)
           (let* ((type (value-type (cdr local))) (pointer (slot type)))
             (hash-table-set! (emitter-locals (current-emitter)) (car local) pointer)
             (store (constant type (if (< index (length params)) (text "%arg" index) (zero type))) pointer)))
         locals (iota (length locals) 0))))

    (define (emit-definition name params body)
      (let ((emitter (make-emitter (make-hash-table) '() 0 "entry"
                                   (open-output-string) '())))
        (parameterize ((current-emitter emitter)) (body))
        (output "define " name "(" (join (map typed params) ", ") ") {\nentry:")
        (for-each (lambda (line) (display line (module-output (current-module))))
                  (reverse (emitter-slots emitter)))
        (display (get-output-string (emitter-port emitter)) (module-output (current-module)))
        (output "}\n")))

    (define (host-import import)
      (cond ((string=? (car import) "wasi_snapshot_preview1")
             (let ((entry (assoc (cadr import) wasi-imports)))
               (and entry (cons (text "wasi_" (car entry)) (cdr entry)))))
            ((equal? import '("snail.host" "register-finalizer"))
             '("native_register_finalizer" "void" "i64" "i32" "i32"))
            ((equal? import '("snail.host" "unregister-finalizer"))
             '("native_unregister_finalizer" "void" "i64"))
            (else #f)))

    (define (import-name function)
      (let* ((import (function-import function)) (entry (host-import import))
             (signature (cons (function-result function)
                              (map (lambda (param) (value-type (cdr param)))
                                   (function-params function)))))
        (unless entry (error "unsupported native host import" import))
        (unless (equal? signature (cdr entry)) (error "native host import type mismatch" import))
        (car entry)))

    (define wasi-imports
      '(("args_sizes_get" "i32" "i32" "i32") ("args_get" "i32" "i32" "i32")
        ("environ_sizes_get" "i32" "i32" "i32") ("environ_get" "i32" "i32" "i32")
        ("clock_time_get" "i32" "i32" "i64" "i32") ("proc_exit" "void" "i32")
        ("fd_close" "i32" "i32") ("fd_prestat_get" "i32" "i32" "i32")
        ("fd_prestat_dir_name" "i32" "i32" "i32" "i32")
        ("fd_fdstat_get" "i32" "i32" "i32") ("fd_filestat_get" "i32" "i32" "i32")
        ("fd_seek" "i32" "i32" "i64" "i32" "i32")
        ("fd_write" "i32" "i32" "i32" "i32" "i32") ("fd_read" "i32" "i32" "i32" "i32" "i32")
        ("path_open" "i32" "i32" "i32" "i32" "i32" "i32" "i64" "i64" "i32" "i32")
        ("path_create_directory" "i32" "i32" "i32" "i32")
        ("path_filestat_get" "i32" "i32" "i32" "i32" "i32" "i32")))

    (define (emit-function function)
      (let ((params (parameter-values function)) (result (function-result function)))
        (emit-definition
         (text "internal tailcc " result " " (symbol-name "f." (function-name function)))
         params
         (lambda ()
           (if (function-import function)
               (return-value (call-native (import-name function) result params))
               (begin (initialize-locals function)
                      (let ((value (emit-sequence (function-body function))))
                        (when (alive?) (return-value value)))))))))

    (define (emit-export node)
      (case (caaddr node)
        ((global)
         (let ((pointer (global-slot (cadr (caddr node)))))
           (emit-definition (text (car pointer) " " (symbol-name "wasm-global." (cadr node)))
                            '() (lambda () (return-value (load pointer))))))
        ((func)
         (let* ((function (function-info (cadr (caddr node)))) (params (parameter-values function))
                (result (function-result function)))
           (emit-definition
            (text result " " (symbol-name "wasm." (cadr node))) params
            (lambda () (return-value (emit-call (symbol-name "f." (function-name function))
                                                params result #f))))))))

    (define (emit-import-declaration function)
      (output "declare " (function-result function) " @" (import-name function)
              "(" (join (map (lambda (param) (value-type (cdr param))) (function-params function)) ", ") ")"))

    ;; ---- Module initialization ----

    (define (immutable-struct? node)
      (and (not (and (pair? (caddr node)) (eq? (caaddr node) 'mut)))
           (eq? (car (cadddr node)) 'struct.new)
           (null? (filter (lambda (field) (and (pair? (cadr field))
                                               (eq? (caadr field) 'mut)))
                          (cdr (type-definition (cadr (cadddr node))))))
           (let ((values (cddr (cadddr node))))
             (= (length values)
                (length (filter (lambda (value) (memq (car value) '(i32.const i64.const f32.const f64.const))) values))))))

    (define (static-field node)
      (case (car node)
        ((f64.const) (text "i64 bitcast (double " (float-constant (cadr node) #f) " to i64)"))
        ((f32.const) (text "i64 zext (i32 bitcast (float " (float-constant (cadr node) #t)
                           " to i32) to i64)"))
        (else (text "i64 " (wat-number (cadr node))))))

    (define (declare-global node)
      (let ((pointer (global-slot (cadr node))))
        (if (immutable-struct? node)
            (let* ((init (cadddr node)) (object (symbol-name "object." (cadr node)))
                   (fields (cons (text "i64 " (type-id (cadr init))) (map static-field (cddr init)))))
              (output object " = internal constant { " (join (map (lambda (field) "i64") fields) ", ")
                      " } { " (join fields ", ") " }, align 8")
              (output (cdr pointer) " = internal constant i64 ptrtoint (ptr " object " to i64)"))
            (output (cdr pointer) " = internal global " (car pointer) " " (zero (car pointer))))))

    (define (declare-function-reference function)
      (output (symbol-name "ref." (function-name function))
              " = internal constant { i64, ptr } { i64 "
              (type-id (function-type (function-name function)))
              ", ptr " (symbol-name "f." (function-name function)) " }, align 8"))

    (define (declare-data node)
      (let ((data (car (reverse node))))
        (unless (string? data) (error "unsupported native data segment" node))
        (output (symbol-name "data." (cadr node)) " = private constant ["
                (string-length data) " x i8] c" (quoted data))))

    (define (emit-declaration node)
      (case (car node)
        ((global) (declare-global node))
        ((func) (declare-function-reference (function-info (cadr node))))
        ((import) (let ((function (function-info (cadr (cadddr node)))))
                    (emit-import-declaration function) (declare-function-reference function)))
        ((table) (output (symbol-name "table." (cadr node)) " = internal global { ptr, i32, i32 } zeroinitializer"))
        ((data) (declare-data node))))

    (define (initialize-table node)
      (let* ((parts (cddr node)) (type (car (reverse parts)))
             (minimum (wat-number (car parts)))
             (maximum (if (= (length parts) 3) (wat-number (cadr parts)) 4294967295)))
        (unless (and (<= 2 (length parts) 3)
                     (or (symbol? type) (and (pair? type) (eq? (car type) 'ref)
                                             (eq? (cadr type) 'null))))
          (error "native requires nullable table32 without an initializer" node))
        (value-type type)
        (call-native "native_table_init" "void"
                     (list (constant "ptr" (symbol-name "table." (cadr node)))
                           (constant "i32" minimum) (constant "i32" maximum)))))

    (define (initialize-data node)
      (unless (and (= (length node) 4) (pair? (caddr node)))
        (error "native passive data segments are unsupported" (cadr node)))
      (let* ((data (cadddr node)) (length (string-length data))
             (address (memory-address (operand (caddr node)) 0 length)))
        (call-native "llvm.memcpy.p0.p0.i64" "void"
                     (list address (constant "ptr" (symbol-name "data." (cadr node)))
                           (constant "i64" length) (constant "i1" "false")))))

    (define (initialize-element node)
      (unless (and (> (length node) 3) (pair? (caddr node)))
        (error "native passive or declarative elements are unsupported" node))
      (let* ((parts (cddr node)) (explicit? (and (pair? (car parts)) (eq? (caar parts) 'table)))
             (table (if explicit? (cadar parts)
                        (cadar (filter (lambda (item) (eq? (car item) 'table))
                                       (module-declarations (current-module))))))
             (parts (if explicit? (cdr parts) parts))
             (offset (wat-number (cadar parts))) (functions (cdr parts)))
        (unless (eq? (caar parts) 'i32.const)
          (error "native element offsets must be constant" node))
        (unless (eq? (car functions) 'func) (error "unsupported native element segment" node))
        (for-each
         (lambda (name index)
           (store (constant "i64" (text "ptrtoint (ptr " (symbol-name "ref." name) " to i64)"))
                  (constant "i64" (cdr (table-slot table (constant "i32" index))))))
         (cdr functions) (iota (length (cdr functions)) offset))))

    (define (initialize-declaration node)
      (case (car node)
        ((memory)
         (unless (and (<= 3 (length node) 4) (wat-name? (cadr node)))
           (error "native requires one unshared wasm32 memory" node))
         (call-native "native_memory_init" "void"
                      (list (constant "i32" (wat-number (caddr node)))
                            (constant "i32" (if (= 4 (length node)) (wat-number (cadddr node)) 65536)))))
        ((global) (unless (immutable-struct? node)
                    (store (operand (cadddr node)) (global-slot (cadr node)))))
        ((table) (initialize-table node))
        ((data) (initialize-data node))
        ((elem) (initialize-element node))))

    (define (emit-initializer declarations)
      (emit-definition
       "void @native_module_init" '()
       (lambda ()
         (for-each initialize-declaration declarations)
         (for-each (lambda (node) (when (eq? (car node) 'start)
                                    (emit-direct-call (cdr node) #f))) declarations)
         (return-value #f))))

    (define native-declarations
      '("declare void @native_trap() noreturn cold"
        "declare i64 @native_alloc(i64)"
        "declare i32 @native_ref_test(i64, i64, i32)"
        "declare i64 @native_array_new(i64, i32, i64)"
        "declare ptr @native_array_slot(i64, i32)"
        "declare i32 @native_array_length(i64)"
        "declare void @native_array_copy(i64, i32, i64, i32, i32)"
        "declare void @native_memory_init(i32, i32)"
        "declare ptr @native_memory_address(i64, i64)"
        "declare i32 @native_memory_pages()"
        "declare i32 @native_memory_grow(i32)"
        "declare void @native_memory_copy(i32, i32, i32)"
        "declare void @native_memory_fill(i32, i32, i32)"
        "declare void @native_table_init(ptr, i32, i32)"
        "declare ptr @native_table_slot(ptr, i32)"
        "declare i32 @native_table_size(ptr)"
        "declare i32 @native_table_grow(ptr, i64, i32)"
        "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)"))

    (define (declare-numeric-helpers)
      (for-each
       (lambda (type)
         (for-each (lambda (op) (output "declare " type " @native_" type "_" op
                                        "(" type ", " type ")")) '(div_s rem_s))
         (for-each (lambda (op) (output "declare " type " @llvm." op "." type
                                        "(" type ", i1)")) '(ctlz cttz))
         (output "declare " type " @llvm.ctpop." type "(" type ")")
         (for-each (lambda (op) (output "declare " type " @llvm." op "." type
                                        "(" type ", " type ", " type ")")) '(fshl fshr))
         (for-each (lambda (source)
                     (for-each (lambda (sign)
                                 (output "declare " type " @native_" type "_trunc_" (car source) "_" sign
                                         "(" (cdr source) ")")) '(s u)))
                   '((f32 . "float") (f64 . "double")))) '("i32" "i64"))
      (for-each
       (lambda (type)
         (for-each (lambda (op) (output "declare " (cdr type) " @llvm." op "." (car type)
                                        "(" (cdr type) ")")) '(fabs sqrt ceil floor trunc roundeven))
         (output "declare " (cdr type) " @llvm.copysign." (car type)
                 "(" (cdr type) ", " (cdr type) ")"))
       '((f32 . "float") (f64 . "double"))))

    (define (wat->llvm node port)
      (unless (and (pair? node) (eq? (car node) 'module)) (error "expected a Wasm module"))
      (let* ((declarations (flatten-declarations (cdr node)))
             (module (make-module (make-hash-table) (make-hash-table)
                                  (make-hash-table) (make-hash-table)
                                  declarations port)))
        (parameterize ((current-module module))
          (for-each record-declaration! declarations)
          (when (> (length (filter (lambda (node) (eq? (car node) 'memory)) declarations)) 1)
            (error "native multiple memories are unsupported"))
          (output "; WasmGC -> LLVM. Generated by the Chibi-hosted Scheme compiler.\n"
                  "target triple = \"x86_64-unknown-linux-gnu\"\n")
          (for-each output native-declarations)
          (declare-numeric-helpers)
          (for-each emit-declaration declarations)
          (for-each (lambda (node)
                      (case (car node)
                        ((func) (emit-function (function-info (cadr node))))
                        ((import) (emit-function (function-info (cadr (cadddr node)))))
                        ((export) (emit-export node)))) declarations)
          (emit-initializer declarations))))

    (define (wat-file->llvm-file input output)
      (let ((module (call-with-input-file input read-wat)))
        (call-with-output-file output (lambda (port) (wat->llvm module port))))))

  ;; ---- Tests ----

  ;; Executable ABI, trap, and GC tests belong in tests/native-semantics.wat.
  ;; These host tests cover source decoding choices and rejected module shapes.
  (cond-expand
   (snail-tests
    (export test-llvm)
    (import (snail-scheme test-utils))
    (begin
      (define (test-llvm-floats)
        (expect (float-constant (string->symbol "-0") #f) "0x8000000000000000")
        (expect (float-constant (string->symbol "0.1") #t) "0x3FB99999A0000000")
        (expect (float-constant (string->symbol "-nan:0x8000000000000") #f) "0xFFF8000000000000"))

      (define (test-llvm-rejections)
        (for-each
         (lambda (wat)
           (expect (guard (error (else #t))
                     (wat->llvm (read-wat (open-input-string wat)) (open-output-string)) #f) #t))
         '("(module (memory $m i64 1))"
           "(module (memory $a 1) (memory $b 1))"
           "(module (type $f (func (result i32 i64))) (func $f (result i32 i64)))"
           "(module (type $f (func)) (import \"unknown\" \"thing\" (func $f)))"
           "(module (type $f (func)) (import \"wasi_snapshot_preview1\" \"args_get\" (func $f)))"
           "(module (type $f (func)) (import \"wasi_snapshot_preview1\" \"unknown\" (func $f)))"
           "(module (type $s (sub (struct))))")))

      (define (test-llvm)
        (run-test test-llvm-floats)
        (run-test test-llvm-rejections))))))
