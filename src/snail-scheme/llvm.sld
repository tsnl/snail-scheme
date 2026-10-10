(define-library (snail-scheme llvm)
  (export wasm->llvm wasm-file->llvm-file)
  (import (scheme base) (scheme char) (scheme cxr)
          (scheme file) (scheme write)
          (snail-scheme wasm-binary) (snail-scheme llvmlite))
  (begin

    ;; ---- LLVM operands and native types ----

    (define (prefix? prefix string)
      (and (<= (string-length prefix) (string-length string))
           (string=? prefix (substring string 0 (string-length prefix)))))

    (define (symbol-name prefix name)
      (if (integer? name) (list "@" (llvm-name prefix name))
          (list "@" (llvm-quoted (string-append prefix name)))))

    (define (value-type type)
      (cond ((and (pair? type) (eq? (car type) 'ref)) "i64")
            ((memq type '(i8 i16 i32)) "i32")
            ((eq? type 'i64) "i64")
            ((eq? type 'f32) "float")
            ((eq? type 'f64) "double")
            (else (error "unsupported native Wasm value type" type))))

    (define (storage-type type)
      (if (memq type '(i8 i16)) (symbol->string type) (value-type type)))

    (define (field-type type)
      (if (and (pair? type) (eq? (car type) 'mut)) (cadr type) type))

    (define (zero type)
      (if (member type '("double" "float")) "0.0" "0"))

    (define (typed value) (list (car value) " " (cdr value)))
    (define (constant type word) (cons type word))

    (define (float-constant bits single?)
      ;; LLVM spells float constants using the equivalent double's bits. Integer
      ;; conversion preserves NaN payloads and signed zero without a host float.
      (llvm-hex (if single? (single->double-bits bits) bits)))

    (define (single->double-bits bits)
      (let* ((sign (* (quotient bits 2147483648) (expt 2 63)))
             (exponent (modulo (quotient bits 8388608) 256))
             (fraction (modulo bits 8388608)))
        (+ sign
           (cond ((= exponent 255) (+ (* 2047 (expt 2 52)) (* fraction (expt 2 29))))
                 ((> exponent 0) (+ (* (+ exponent 896) (expt 2 52)) (* fraction (expt 2 29))))
                 ((= fraction 0) 0)
                 (else (let loop ((mantissa fraction) (exponent 897))
                         (if (>= mantissa 8388608)
                             (+ (* exponent (expt 2 52)) (* (- mantissa 8388608) (expt 2 29)))
                             (loop (* mantissa 2) (- exponent 1)))))))))

    ;; ---- Declarations ----

    ;; One pass records the validated module's numeric declarations. Function
    ;; bodies stay in the input bytevector until their direct lowering below.
    ;; Heap headers encode a canonical type identity and its abstract category:
    ;; function = 0, struct = 2, array = 3. Odd references are immediate i31s.

    (define-record-type <module>
      (make-module types functions globals output)
      module?
      (types module-types) (functions module-functions)
      (globals module-globals) (output module-output))

    (define-record-type <function>
      (make-function name params result locals body import type)
      function?
      (name function-name) (params function-params) (result function-result)
      (locals function-locals) (body function-body) (import function-import)
      (type function-wasm-type))

    (define current-module (make-parameter #f))

    (define (type-info index) (vector-ref (module-types (current-module)) index))
    (define (function-info index) (vector-ref (module-functions (current-module)) index))
    (define (global-info index) (vector-ref (module-globals (current-module)) index))
    (define (type-id index) (car (type-info index)))
    (define (type-definition index) (cdr (type-info index)))

    (define (parse-function node import)
      (let* ((type (caddr node)) (signature (type-definition type)))
        (make-function (cadr node) (cadr signature) (result-type signature)
                       (if import '() (cadddr node))
                       (and (not import) (car (cddddr node))) import type)))

    (define (iota count start)
      (let loop ((index 0) (result '()))
        (if (= index count) (reverse result)
            (loop (+ index 1) (cons (+ start index) result)))))

    (define (result-type signature)
      (let ((results (caddr signature)))
        (case (length results)
          ((0) "void") ((1) (value-type (car results)))
          (else (error "native multivalue Wasm signatures are unsupported" results)))))

    (define (filter predicate items)
      (let loop ((rest items) (kept '()))
        (cond ((null? rest) (reverse kept))
              ((predicate (car rest)) (loop (cdr rest) (cons (car rest) kept)))
              (else (loop (cdr rest) kept)))))

    (define (record-type! node)
      (let* ((index (cadr node)) (definition (caddr node))
             (category (case (car definition) ((func) 0) ((struct) 2) ((array) 3)
                             (else (error "unsupported native Wasm heap type" definition)))))
        (vector-set! (module-types (current-module)) index
                     (cons (+ (* 4 (+ index 1)) category) definition))
        (when (eq? (car definition) 'func) (result-type definition))))

    (define (record-function! node import)
      (vector-set! (module-functions (current-module)) (cadr node) (parse-function node import)))

    (define (record-declaration! node)
      (case (car node)
        ((type) (record-type! node))
        ((func) (record-function! node #f))
        ((import) (record-function! (cadddr node) (list (cadr node) (caddr node))))
        ((global) (vector-set! (module-globals (current-module)) (cadr node) node))))

    (define (function-type index) (function-wasm-type (function-info index)))

    ;; ---- Native function state ----

    ;; Locals and structured joins use entry-block slots. LLVM promotes them to
    ;; SSA; this keeps Wasm branch values explicit without a second CFG pass.
    ;; A false live flag means control cannot fall through. The operand
    ;; stack holds already-produced SSA values, never deferred reads or calls.

    (define-record-type <emitter>
      (make-emitter locals targets serial live? port slots stack result)
      emitter?
      (locals emitter-locals set-emitter-locals!)
      (targets emitter-targets set-emitter-targets!)
      (serial emitter-serial set-emitter-serial!)
      (live? emitter-live? set-emitter-live!) (port emitter-port)
      (slots emitter-slots set-emitter-slots!)
      (stack emitter-stack set-emitter-stack!) (result emitter-result set-emitter-result!))

    (define current-emitter (make-parameter #f))

    (define (fresh prefix)
      (let* ((emitter (current-emitter)) (number (+ 1 (emitter-serial emitter))))
        (set-emitter-serial! emitter number)
        (llvm-name prefix number)))

    (define (alive?) (emitter-live? (current-emitter)))

    (define (line . pieces)
      (unless (alive?) (error "LLVM emission after terminator" pieces))
      (let ((port (emitter-port (current-emitter))))
        (display "  " port)
        (write-llvm pieces port)
        (newline port)))

    (define (instruction type . pieces)
      (let ((name (fresh "%v")))
        (apply line name " = " pieces)
        (constant type name)))

    (define (finish . pieces)
      (apply line pieces)
      (set-emitter-live! (current-emitter) #f))

    (define (label name)
      (write-llvm (list name ":\n") (emitter-port (current-emitter)))
      (set-emitter-live! (current-emitter) #t))

    (define (slot type)
      (let* ((name (fresh "%slot")) (emitter (current-emitter)))
        (set-emitter-slots! emitter
                            (cons (list "  " name " = alloca " type ", align 8\n")
                                  (emitter-slots emitter)))
        (constant type name)))

    (define (store value pointer)
      (line "store " (typed value) ", ptr " (cdr pointer) ", align 1"))

    (define (load pointer)
      (instruction (car pointer) "load " (car pointer) ", ptr " (cdr pointer) ", align 1"))

    (define (push-value! value)
      (when (and value (alive?))
        (let ((emitter (current-emitter)))
          (set-emitter-stack! emitter (cons value (emitter-stack emitter))))))

    (define (pop-values! count)
      (let ((emitter (current-emitter)))
        (let loop ((left count) (stack (emitter-stack emitter)) (values '()))
          (if (= left 0) (begin (set-emitter-stack! emitter stack) values)
              (if (null? stack) (error "missing Wasm operand")
                  (loop (- left 1) (cdr stack) (cons (car stack) values)))))))

    (define (pop-value!) (car (pop-values! 1)))

    (define (branch-value destination)
      (and (target-slot destination) (car (emitter-stack (current-emitter)))))

    (define (emit-constant-expression instructions)
      (for-each (lambda (instruction) (push-value! (emit-operation instruction))) instructions)
      (pop-value!))

    (define (truth value)
      (instruction "i1" "icmp ne " (typed value) ", 0"))

    (define (boolean value)
      (instruction "i32" "zext " (typed value) " to i32"))

    (define (cast opcode value type)
      (if (string=? type (car value)) value
          (instruction type opcode " " (typed value) " to " type)))

    (define (call-native name result arguments)
      (let ((call (list "call " result " @" name "(" (llvm-join (map typed arguments) ", ") ")")))
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

    ;; Branch depths index lexical targets. A target holds its label, optional
    ;; result slot and whether a live edge reaches it. Private result slots let
    ;; br_if and br_table write their result before selecting an edge.

    (define-record-type <target>
      (new-target label slot reached?) target?
      (label target-label) (slot target-slot) (reached? target-reached? set-target-reached!))

    (define (target depth) (list-ref (emitter-targets (current-emitter)) depth))

    (define (make-target prefix result)
      (new-target (fresh prefix) (and (not (string=? result "void")) (slot result)) #f))

    (define (record-edge! destination value)
      (let ((slot (target-slot destination)))
        (when slot
          (unless value (error "missing Wasm branch value" destination))
          (store value slot))
        (set-target-reached! destination #t)))

    (define (jump destination value)
      (record-edge! destination value)
      (finish "br label %" (target-label destination)))

    (define (join-target destination)
      (if (target-reached? destination)
          (begin (label (target-label destination))
                 (and (target-slot destination) (load (target-slot destination))))
          #f))

    (define (block-result type)
      (cond ((eq? type 'void) "void")
            ((integer? type)
             (let ((signature (type-definition type)))
               (unless (null? (cadr signature))
                 (error "native block parameters are unsupported" type))
               (result-type signature)))
            (else (value-type type))))

    (define (emit-stream code)
      (let loop ()
        (let* ((instruction (read-wasm-instruction code)) (op (car instruction)))
          (case op
            ((end else) op)
            ((block loop if) (emit-control op (cadr instruction) code) (loop))
            (else (when (alive?) (push-value! (emit-operation instruction))) (loop))))))

    (define (close-control destination)
      (when (alive?) (jump destination (branch-value destination))))

    (define (emit-if-body condition code exit prefix live?)
      (let ((yes (fresh "then")) (no (fresh "else")))
        (when live?
          (finish "br " (typed (truth condition)) ", label %" yes ", label %" no)
          (label yes))
        (let ((ending (emit-stream code)))
          (close-control exit)
          (set-emitter-stack! (current-emitter) prefix)
          (when live? (label no))
          (when (eq? ending 'else)
            (unless (eq? (emit-stream code) 'end) (error "unexpected Wasm else")))
          (close-control exit))))

    (define (emit-control op type code)
      (let* ((emitter (current-emitter)) (live? (alive?))
             (condition (and live? (eq? op 'if) (pop-value!)))
             (prefix (emitter-stack emitter)) (old (emitter-targets emitter))
             (exit (make-target "block" (block-result type)))
             (entry (if (eq? op 'loop) (make-target "loop" "void") exit)))
        (set-emitter-targets! emitter (cons entry old))
        (if (eq? op 'if) (emit-if-body condition code exit prefix live?)
            (begin
              (when (and live? (eq? op 'loop)) (jump entry #f) (label (target-label entry)))
              (unless (eq? (emit-stream code) 'end) (error "unexpected Wasm else"))
              (close-control exit)))
        (set-emitter-targets! emitter old)
        (set-emitter-stack! emitter prefix)
        (push-value! (join-target exit))))

    (define (emit-branch depth conditional?)
      (let* ((destination (target depth)) (condition (and conditional? (truth (pop-value!))))
             (value (branch-value destination)))
        (if (not conditional?) (jump destination value)
            (let ((fallthrough (fresh "next")))
              (record-edge! destination value)
              (finish "br " (typed condition) ", label %" (target-label destination)
                      ", label %" fallthrough)
              (label fallthrough))))
      #f)

    (define (emit-branch-table depths)
      (let* ((index (pop-value!)) (destinations (map target depths))
             (default (car destinations)) (value (branch-value default)))
        (for-each (lambda (destination) (record-edge! destination value)) destinations)
        (line "switch " (typed index) ", label %" (target-label default) " [")
        (for-each (lambda (destination number)
                    (line "i32 " number ", label %" (target-label destination)))
                  (cdr destinations) (iota (- (length destinations) 1) 0))
        (finish "]")
        #f))

    ;; ---- Calls and references ----

    (define (emit-call name arguments result tail?)
      ;; tailcc guarantees tail lowering even when argument counts differ.
      ;; LLVM 22 x86-64 mishandles musttail with growing stack arguments; the
      ;; executable ABI regression covers tailcc + tail across that boundary.
      (let* ((code (list (if tail? "tail " "") "call tailcc " result " " name
                         "(" (llvm-join (map typed arguments) ", ") ")"))
             (value (if (string=? result "void") (begin (line code) #f)
                        (instruction result code))))
        (when tail? (return-value value))
        value))

    (define (emit-direct-call index arguments tail?)
      (let ((function (function-info index)))
        (emit-call (symbol-name "f." index) arguments
                   (function-result function) tail?)))

    (define (field-pointer reference index type)
      (let* ((pointer (cast "inttoptr" (nonnull reference) "ptr"))
             (address (instruction "ptr" "getelementptr i64, ptr " (cdr pointer) ", i64 " index)))
        (constant type (cdr address))))

    (define (function-pointer reference)
      (load (field-pointer reference 1 "ptr")))

    (define (emit-reference-call type tail?)
      (let* ((reference (pop-value!)) (arguments (call-arguments type))
             (type (type-definition type)))
        (emit-call (cdr (function-pointer reference)) arguments (result-type type) tail?)))

    (define (table-slot name index)
      (call-native "native_table_slot" "ptr"
                   (list (constant "ptr" (symbol-name "table." name)) index)))

    (define (emit-indirect-call table type tail?)
      (let* ((index (pop-value!)) (arguments (call-arguments type))
             (reference (load (constant "i64" (cdr (table-slot table index)))))
             (tag (load (field-pointer reference 0 "i64"))))
        (trap-unless (instruction "i1" "icmp eq " (typed tag) ", " (type-id type)))
        (emit-call (cdr (function-pointer reference)) arguments
                   (result-type (type-definition type)) tail?)))

    (define (reference-test reference type)
      (let* ((nullable? (eq? (cadr type) 'null))
             (heap (if nullable? (caddr type) (cadr type)))
             (tag (if (integer? heap) (type-id heap)
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

    (define (emit-ref-cast reference type)
      (trap-unless (truth (reference-test reference type)))
      reference)

    (define (emit-i31 value)
      (let* ((shifted (instruction "i32" "shl " (typed value) ", 1"))
             (signed (instruction "i32" "ashr " (typed shifted) ", 1"))
             (wide (cast "sext" signed "i64"))
             (tagged (instruction "i64" "shl " (typed wide) ", 1")))
        (instruction "i64" "or " (typed tagged) ", 1")))

    (define (emit-i31-get node signed?)
      (let* ((reference (nonnull node))
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

    (define (emit-struct-new type default?)
      (let ((fields (cdr (type-definition type))))
        (allocate-struct type
                         (if default? (map (lambda (field)
                                             (let ((type (value-type (field-type field))))
                                               (constant type (zero type)))) fields)
                             (pop-values! (length fields))))))

    (define (emit-struct-get type index signed?)
      (let* ((type (field-type (list-ref (cdr (type-definition type)) index)))
             (pointer (field-pointer (pop-value!) (+ index 1) (storage-type type))))
        (cast (if signed? "sext" "zext") (load pointer) (value-type type))))

    (define (emit-struct-set type index)
      (let* ((type (storage-type (field-type (list-ref (cdr (type-definition type)) index))))
             (value (pop-value!)) (reference (pop-value!)))
        (store (cast "trunc" value type) (field-pointer reference (+ index 1) type))
        #f))

    (define (array-type name)
      (field-type (cadr (type-definition name))))

    (define (value-word value)
      (cond ((member (car value) '("double" "float"))
             (cast "zext" (cast "bitcast" value (if (string=? (car value) "double") "i64" "i32")) "i64"))
            (else (cast "zext" value "i64"))))

    (define (new-array name length initial)
      (call-native "native_array_new" "i64"
                   (list (constant "i64" (type-id name)) length (value-word initial))))

    (define (emit-array-new name default?)
      (let* ((type (value-type (array-type name))) (length (pop-value!))
             (initial (if default? (constant type (zero type)) (pop-value!))))
        (new-array name length initial)))

    (define (array-slot reference index type)
      (constant type (cdr (call-native "native_array_slot" "ptr" (list reference index)))))

    (define (emit-array-fixed name length)
      (let* ((type (storage-type (array-type name))) (values (pop-values! length))
             (reference (new-array name (constant "i32" length) (constant "i64" 0))))
        (for-each (lambda (value index)
                    (store (cast "trunc" value type)
                           (array-slot reference (constant "i32" index) type)))
                  values (iota length 0))
        reference))

    (define (emit-array-get name signed?)
      (let* ((type (array-type name)) (index (pop-value!)) (reference (pop-value!))
             (value (load (array-slot reference index (storage-type type)))))
        (cast (if signed? "sext" "zext") value (value-type type))))

    (define (emit-array-set name)
      (let* ((type (storage-type (array-type name)))
             (value (pop-value!)) (index (pop-value!)) (reference (pop-value!)))
        (store (cast "trunc" value type) (array-slot reference index type))
        #f))

    ;; ---- Linear memory ----

    ;; Rust addresses remain wasm32 offsets into a distinct, unscanned memory.
    ;; Offset addition uses i64, so a large static offset cannot wrap around a
    ;; bounds check. All loads and stores permit byte alignment as Wasm does.

    (define (memory-address address offset size)
      (let* ((wide (cast "zext" address "i64"))
             (index (instruction "i64" "add " (typed wide) ", " offset)))
        (call-native "native_memory_address" "ptr" (list index (constant "i64" size)))))

    (define (memory-instruction descriptor offset)
      (let* ((type (car descriptor)) (narrow (cadr descriptor)) (size (caddr descriptor))
             (signed? (cadddr descriptor)) (store? (car (cddddr descriptor)))
             (values (pop-values! (if store? 2 1)))
             (address (memory-address (car values) offset size))
             (pointer (constant narrow (cdr address))))
        (if store? (begin (store (cast "trunc" (cadr values) narrow) pointer) #f)
            (cast (if signed? "sext" "zext") (load pointer) type))))

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

    (define (numeric-binary op opcode values float?)
      (let* ((left (car values)) (right (cadr values))
             (compare? (memq op '(eq ne lt le gt ge lt_s lt_u le_s le_u gt_s gt_u ge_s ge_u)))
             (shift? (memq op '(shl shr_s shr_u)))
             (right (if shift? (instruction (car right) "and " (typed right) ", "
                                            (if (string=? (car right) "i64") 63 31)) right))
             (value (instruction (if compare? "i1" (car left))
                                 (if compare? (if float? "fcmp " "icmp ") "")
                                 opcode " " (typed left) ", " (cdr right))))
        (if compare? (boolean value) value)))

    (define (emit-division op values)
      (let* ((left (car values)) (right (cadr values)) (type (car left))
             (signed? (memq op '(div_s rem_s))))
        (if signed?
            (call-native (list "native_" type "_" op) type values)
            (begin (trap-unless (instruction "i1" "icmp ne " (typed right) ", 0"))
                   (instruction type (if (eq? op 'div_u) "udiv " "urem ")
                                (typed left) ", " (cdr right))))))

    (define (numeric-intrinsic name values)
      (let* ((type (car (car values)))
             (suffix (cond ((string=? type "double") "f64")
                           ((string=? type "float") "f32") (else type))))
        (call-native (list "llvm." name "." suffix) type values)))

    (define (emit-numeric base operation values)
      (let* ((float? (char=? (string-ref base 0) #\f))
             (mapping (assq operation (if float? float-operations integer-operations))))
        (cond (mapping (numeric-binary operation (cdr mapping) values float?))
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
               (call-native (list "native_" base "_" name) target values))
              ((memq operation '(extend8_s extend16_s extend32_s))
               (cast "sext" (cast "trunc" value
                                  (case operation ((extend8_s) "i8") ((extend16_s) "i16") (else "i32"))) target))
              ((eq? operation 'promote_f32) (cast "fpext" value target))
              ((eq? operation 'demote_f64) (cast "fptrunc" value target))
              (else (error "unsupported native Wasm numeric operation" base operation)))))

    ;; ---- Instruction dispatch ----

    (define (local-slot index) (vector-ref (emitter-locals (current-emitter)) index))

    (define (global-slot name)
      (let* ((node (global-info name)) (type (caddr node))
             (type (if (and (pair? type) (eq? (car type) 'mut)) (cadr type) type)))
        (constant (value-type type) (symbol-name "g." name))))

    (define (emit-local-set index tee?)
      (let ((value (pop-value!)))
        (store value (local-slot index))
        (and tee? value)))

    (define (emit-select values)
      (let ((condition (truth (caddr values))))
        (instruction (caar values) "select " (typed condition) ", "
                     (typed (car values)) ", " (typed (cadr values)))))

    (define (emit-table op table)
      (let* ((pointer (constant "ptr" (symbol-name "table." table)))
             (values (pop-values! (case op ((table.get) 1) ((table.size) 0) (else 2)))))
        (case op
          ((table.get) (load (constant "i64" (cdr (table-slot table (car values))))))
          ((table.set) (store (cadr values) (constant "i64" (cdr (table-slot table (car values))))) #f)
          ((table.size) (call-native "native_table_size" "i32" (list pointer)))
          ((table.grow) (call-native "native_table_grow" "i32" (cons pointer values)))
          (else (error "unsupported native table operation" op)))))

    (define (call-arguments index)
      (pop-values! (length (cadr (type-definition index)))))

    ;; Operands are popped in Wasm order and passed to representation operations.
    ;; Control instructions are handled by emit-stream even in dead code; other
    ;; instructions are decoded but not evaluated while no block is reachable.
    ;; Common operations lead the case: Chibi searches its arms linearly.
    (define (emit-operation node)
      (let ((op (car node)) (args (cdr node)))
        (case op
          ((local.get) (load (local-slot (car args))))
          ((numeric) (emit-numeric (car args) (cadr args) (pop-values! (caddr args))))
          ((i32.const) (constant "i32" (car args)))
          ((local.set local.tee) (emit-local-set (car args) (eq? op 'local.tee)))
          ((memory) (memory-instruction (car args) (cadr args)))
          ((global.get) (load (global-slot (car args))))
          ((br) (emit-branch (car args) #f))
          ((br_if) (emit-branch (car args) #t))
          ((br_table) (emit-branch-table args))
          ((unreachable) (line "call void @native_trap()") (finish "unreachable") #f)
          ((nop) #f)
          ((drop) (pop-value!) #f)
          ((return) (return-value (and (not (string=? (emitter-result (current-emitter)) "void"))
                                       (pop-value!))) #f)
          ((select) (emit-select (pop-values! 3)))
          ((global.set) (store (pop-value!) (global-slot (car args))) #f)
          ((call return_call)
           (emit-direct-call (car args) (call-arguments (function-type (car args)))
                             (eq? op 'return_call)))
          ((call_ref return_call_ref)
           (emit-reference-call (car args) (eq? op 'return_call_ref)))
          ((call_indirect return_call_indirect)
           (emit-indirect-call (car args) (cadr args) (eq? op 'return_call_indirect)))
          ((ref.null) (constant "i64" 0))
          ((ref.func) (constant "i64" (list "ptrtoint (ptr " (symbol-name "ref." (car args)) " to i64)")))
          ((ref.i31) (emit-i31 (pop-value!)))
          ((i31.get_s i31.get_u) (emit-i31-get (pop-value!) (eq? op 'i31.get_s)))
          ((ref.as_non_null) (nonnull (pop-value!)))
          ((ref.eq) (let ((values (pop-values! 2)))
                      (boolean (instruction "i1" "icmp eq " (typed (car values)) ", " (cdadr values)))))
          ((ref.is_null) (boolean (instruction "i1" "icmp eq " (typed (pop-value!)) ", 0")))
          ((ref.test) (reference-test (pop-value!) (car args)))
          ((ref.cast) (emit-ref-cast (pop-value!) (car args)))
          ((struct.new struct.new_default) (emit-struct-new (car args) (eq? op 'struct.new_default)))
          ((struct.get struct.get_s struct.get_u)
           (emit-struct-get (car args) (cadr args) (eq? op 'struct.get_s)))
          ((struct.set) (emit-struct-set (car args) (cadr args)))
          ((array.new array.new_default)
           (emit-array-new (car args) (eq? op 'array.new_default)))
          ((array.new_fixed) (emit-array-fixed (car args) (cadr args)))
          ((array.get array.get_s array.get_u)
           (emit-array-get (car args) (eq? op 'array.get_s)))
          ((array.set) (emit-array-set (car args)))
          ((array.len) (call-native "native_array_length" "i32" (pop-values! 1)))
          ((array.copy) (call-native "native_array_copy" "void" (pop-values! 5)))
          ((table.get table.set table.size table.grow)
           (emit-table op (car args)))
          ((memory.size) (call-native "native_memory_pages" "i32" '()))
          ((memory.grow) (call-native "native_memory_grow" "i32" (pop-values! 1)))
          ((memory.copy) (call-native "native_memory_copy" "void" (pop-values! 3)))
          ((memory.fill) (call-native "native_memory_fill" "void" (pop-values! 3)))
          ((i64.const) (constant "i64" (car args)))
          ((f64.const) (constant "double" (float-constant (car args) #f)))
          ((f32.const) (constant "float" (float-constant (car args) #t)))
          (else (error "unsupported native Wasm instruction" op)))))

    ;; ---- Function definitions and host boundary ----

    (define (output . pieces)
      (write-llvm pieces (module-output (current-module)))
      (newline (module-output (current-module))))

    (define (parameter-values function)
      (map (lambda (param index) (constant (value-type param) (llvm-name "%arg" index)))
           (function-params function) (iota (length (function-params function)) 0)))

    (define (initialize-locals function)
      (let* ((params (function-params function))
             (locals (append params (function-locals function))))
        (set-emitter-locals! (current-emitter) (make-vector (length locals)))
        (for-each
         (lambda (local index)
           (let* ((type (value-type local)) (pointer (slot type)))
             (vector-set! (emitter-locals (current-emitter)) index pointer)
             (store (constant type (if (< index (length params)) (llvm-name "%arg" index) (zero type))) pointer)))
         locals (iota (length locals) 0))))

    (define (emit-definition name params body)
      (let ((emitter (make-emitter '#() '() 0 #t
                                   (open-output-string) '() '() "void")))
        (parameterize ((current-emitter emitter)) (body))
        (output "define " name "(" (llvm-join (map typed params) ", ") ") {\nentry:")
        (for-each (lambda (line) (write-llvm line (module-output (current-module))))
                  (reverse (emitter-slots emitter)))
        (display (get-output-string (emitter-port emitter)) (module-output (current-module)))
        (close-output-port (emitter-port emitter))
        (output "}\n")))

    (define (host-import import)
      (cond ((string=? (car import) "wasi_snapshot_preview1")
             (let ((entry (assoc (cadr import) wasi-imports)))
               (and entry (cons (list "wasi_" (car entry)) (cdr entry)))))
            ((equal? import '("snail.host" "register-finalizer"))
             '("native_register_finalizer" "void" "i64" "i32" "i32"))
            ((equal? import '("snail.host" "unregister-finalizer"))
             '("native_unregister_finalizer" "void" "i64"))
            (else #f)))

    (define (import-name function)
      (let* ((import (function-import function)) (entry (host-import import))
             (signature (cons (function-result function)
                              (map value-type (function-params function)))))
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
         (list "internal tailcc " result " " (symbol-name "f." (function-name function)))
         params
         (lambda ()
           (if (function-import function)
               (return-value (call-native (import-name function) result params))
               (begin
                 (initialize-locals function)
                 (set-emitter-result! (current-emitter) result)
                 (let ((exit (make-target "return" result))
                       (code (wasm-code-copy (function-body function))))
                   (set-emitter-targets! (current-emitter) (list exit))
                   (unless (and (eq? (emit-stream code) 'end) (wasm-code-end? code))
                     (error "invalid Wasm function ending"))
                   (close-control exit)
                   (let ((value (join-target exit))) (when (alive?) (return-value value))))))))))

    (define (emit-export node)
      (case (caaddr node)
        ((global)
         (let ((pointer (global-slot (cadr (caddr node)))))
           (emit-definition (list (car pointer) " " (symbol-name "wasm-global." (cadr node)))
                            '() (lambda () (return-value (load pointer))))))
        ((func)
         (let* ((function (function-info (cadr (caddr node)))) (params (parameter-values function))
                (result (function-result function)))
           (emit-definition
            (list result " " (symbol-name "wasm." (cadr node))) params
            (lambda () (return-value (emit-call (symbol-name "f." (function-name function))
                                                params result #f))))))))

    (define (emit-import-declaration function)
      (output "declare " (function-result function) " @" (import-name function)
              "(" (llvm-join (map value-type (function-params function)) ", ") ")"))

    ;; ---- Module initialization ----

    (define (immutable-struct? node)
      (let* ((init (reverse (cadddr node))) (last (car init)))
        (and (not (and (pair? (caddr node)) (eq? (caaddr node) 'mut)))
             (eq? (car last) 'struct.new)
             (null? (filter (lambda (field) (and (pair? field) (eq? (car field) 'mut)))
                            (cdr (type-definition (cadr last)))))
             (= (length (cdr init))
                (length (filter (lambda (value) (memq (car value) '(i32.const i64.const f32.const f64.const)))
                                (cdr init)))))))

    (define (static-field node)
      (case (car node)
        ((f64.const) (list "i64 bitcast (double " (float-constant (cadr node) #f) " to i64)"))
        ((f32.const) (list "i64 zext (i32 bitcast (float " (float-constant (cadr node) #t) " to i32) to i64)"))
        (else (list "i64 " (cadr node)))))

    (define (declare-global node)
      (let ((pointer (global-slot (cadr node))))
        (if (immutable-struct? node)
            (let* ((init (reverse (cadddr node))) (object (symbol-name "object." (cadr node)))
                   (fields (cons (list "i64 " (type-id (cadar init))) (map static-field (reverse (cdr init))))))
              (output object " = internal constant { " (llvm-join (map (lambda (field) "i64") fields) ", ")
                      " } { " (llvm-join fields ", ") " }, align 8")
              (output (cdr pointer) " = internal constant i64 ptrtoint (ptr " object " to i64)"))
            (output (cdr pointer) " = internal global " (car pointer) " " (zero (car pointer))))))

    (define (declare-function-reference function)
      (output (symbol-name "ref." (function-name function))
              " = internal constant { i64, ptr } { i64 "
              (type-id (function-type (function-name function)))
              ", ptr " (symbol-name "f." (function-name function)) " }, align 8"))

    (define (declare-data node)
      (let ((data (cadddr node)))
        (output (symbol-name "data." (cadr node)) " = private constant ["
                (bytevector-length data) " x i8] c" (llvm-quoted data))))

    (define (emit-declaration node)
      (case (car node)
        ((global) (declare-global node))
        ((func) (declare-function-reference (function-info (cadr node))))
        ((import) (let ((function (function-info (cadr (cadddr node)))))
                    (emit-import-declaration function) (declare-function-reference function)))
        ((table) (output (symbol-name "table." (cadr node)) " = internal global { ptr, i32, i32 } zeroinitializer"))
        ((data) (declare-data node))))

    (define (initialize-table node)
      (call-native "native_table_init" "void"
                   (list (constant "ptr" (symbol-name "table." (cadr node)))
                         (constant "i32" (caddr node)) (constant "i32" (cadddr node)))))

    (define (initialize-data node)
      (let* ((data (cadddr node)) (length (bytevector-length data))
             (address (memory-address (emit-constant-expression (caddr node)) 0 length)))
        (call-native "llvm.memcpy.p0.p0.i64" "void"
                     (list address (constant "ptr" (symbol-name "data." (cadr node)))
                           (constant "i64" length) (constant "i1" "false")))))

    (define (initialize-element node)
      (let ((table (cadr node)) (offset (emit-constant-expression (caddr node)))
            (functions (cadddr node)))
        (for-each
         (lambda (name index)
           (let ((address (instruction "i32" "add " (typed offset) ", " index)))
             (store (constant "i64" (list "ptrtoint (ptr " (symbol-name "ref." name) " to i64)"))
                    (constant "i64" (cdr (table-slot table address))))))
         functions (iota (length functions) 0))))

    (define (initialize-declaration node)
      (case (car node)
        ((memory)
         (call-native "native_memory_init" "void"
                      (list (constant "i32" (caddr node))
                            (constant "i32" (cadddr node)))))
        ((global) (unless (immutable-struct? node)
                    (store (emit-constant-expression (cadddr node)) (global-slot (cadr node)))))
        ((table) (initialize-table node))
        ((data) (initialize-data node))
        ((elem) (initialize-element node))))

    (define (emit-initializer declarations)
      (emit-definition
       "void @native_module_init" '()
       (lambda ()
         (for-each initialize-declaration declarations)
         (for-each (lambda (node) (when (eq? (car node) 'start)
                                    (emit-direct-call (cadr node) '() #f))) declarations)
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

    (define (declaration-count declarations tag)
      (length (filter (lambda (node) (eq? (car node) tag)) declarations)))

    (define (wasm->llvm declarations port)
      (let ((module (make-module (make-vector (declaration-count declarations 'type))
                                 (make-vector (+ (declaration-count declarations 'func)
                                                 (declaration-count declarations 'import)))
                                 (make-vector (declaration-count declarations 'global))
                                 port)))
        (parameterize ((current-module module))
          (for-each record-declaration! declarations)
          (when (> (declaration-count declarations 'memory) 1)
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

    (define (wasm-file->llvm-file input output)
      (let ((module (read-wasm-file input)))
        (call-with-output-file output (lambda (port) (wasm->llvm module port))))))

  ;; ---- Tests ----

  ;; Executable ABI, trap, GC and binary control-flow tests are integration tests.
  (cond-expand
   (snail-tests
    (export test-llvm)
    (import (snail-scheme test-utils))
    (begin
      (define (test-llvm-floats)
        (expect (single->double-bits (expt 2 31)) (expt 2 63))
        (expect (single->double-bits 1) (* 874 (expt 2 52)))
        (expect (single->double-bits 1065353216) (* 1023 (expt 2 52)))
        (expect (single->double-bits 2143289344) (+ (* 2047 (expt 2 52)) (expt 2 51))))

      (define (test-llvm-rejections)
        (for-each
         (lambda (declarations)
           (expect (guard (error (else #t))
                     (wasm->llvm declarations (open-output-string)) #f) #t))
         '(((memory 0 1 1) (memory 1 1 1))
           ((type 0 (func () (i32 i64))))
           ((type 0 (func () ())) (import "unknown" "thing" (func 0 0)))
           ((type 0 (func () ())) (import "wasi_snapshot_preview1" "args_get" (func 0 0)))
           ((type 0 (func () ())) (import "wasi_snapshot_preview1" "unknown" (func 0 0))))))

      (define (test-llvm)
        (run-test test-llvm-floats)
        (run-test test-llvm-rejections))))))
