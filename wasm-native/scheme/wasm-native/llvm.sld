(define-library (wasm-native llvm)
  (export wasm->llvm wasm->llvm-file current-native-imports current-native-gc-stress)
  (import (scheme base) (scheme char) (scheme cxr)
          (scheme file) (scheme write)
          (wasm-native wasm-resolve) (wasm-native llvmlite))
  (begin

    ;; ---- LLVM operands and native types ----

    (define (prefix? prefix string)
      (and (<= (string-length prefix) (string-length string))
           (string=? prefix (substring string 0 (string-length prefix)))))

    (define (symbol-name prefix name)
      (if (integer? name) (list "@" (llvm-name prefix name))
          (list "@" (llvm-quoted (string-append prefix name)))))

    (define (value-type type)
      (cond ((and (pair? type) (eq? (car type) 'ref)) "ref")
            ((memq type '(i8 i16 i32)) "i32")
            ((eq? type 'i64) "i64")
            ((eq? type 'f32) "float")
            ((eq? type 'f64) "double")
            (else (error "unsupported native Wasm value type" type))))

    (define (storage-type type)
      (if (memq type '(i8 i16)) (symbol->string type) (value-type type)))

    (define (storage-size type)
      (cond ((string=? type "i8") 1)
            ((string=? type "i16") 2)
            ((member type '("i32" "float")) 4)
            ((member type '("i64" "double" "ref")) 8)
            (else (error "unsupported native storage type" type))))

    (define (field-type type)
      (if (and (pair? type) (eq? (car type) 'mut)) (cadr type) type))

    (define (zero type)
      (if (member type '("double" "float")) "0.0" 0))

    ;; Operand types retain reference identity even though the machine ABI is i64.
    (define (llvm-type type) (if (string=? type "ref") "i64" type))
    (define (reference-value? value) (string=? (car value) "ref"))
    (define (typed value) (list (llvm-type (car value)) " " (cdr value)))
    (define (constant type word) (cons type word))

    ;; The datum backend receives Scheme f64 values, not encoded bit words.
    ;; LLVM accepts round-tripping decimal doubles; its hex spelling carries
    ;; nonfinite values. Preserve a decimal point even in exponent-only output.
    (define (float-constant value)
      (case value
        ((inf) (llvm-hex 9218868437227405312))
        ((nan) (llvm-hex 9221120237041090560))
        ((-inf) (llvm-hex -4503599627370496))
        (else
         (if (symbol? value) (nan-payload-constant (symbol->string value))
             (begin
               (unless (number? value) (error "unsupported Wasm float literal" value))
               (float-spelling (number->string value)))))))

    (define (nan-payload-word text maximum positive negative)
      (let* ((negative? (prefix? "-nan:0x" text)) (start (if negative? 7 6)))
        (unless (or negative? (prefix? "nan:0x" text)) (error "unsupported Wasm float literal" text))
        (let ((payload (string->number (substring text start (string-length text)) 16)))
          (unless (and payload (<= 1 payload maximum)) (error "invalid Wasm NaN payload" text))
          (+ payload (if negative? negative positive)))))

    (define (nan-payload-constant text)
      (llvm-hex (nan-payload-word text 4503599627370495 9218868437227405312 -4503599627370496)))

    (define (emit-f32-constant value)
      ;; Numeric literals round once to f32. NaN literals carry exact payload
      ;; bits and cannot pass through a floating conversion that may quiet them.
      (if (not (symbol? value)) (cast "fptrunc" (constant "double" (float-constant value)) "float")
          (cast "bitcast"
                (constant "i32" (case value
                                  ((inf) 2139095040) ((-inf) -8388608) ((nan) 2143289344)
                                  (else (nan-payload-word (symbol->string value) 8388607 2139095040 -8388608))))
                "float")))

    (define (float-spelling text)
      (let loop ((index 0))
        (cond ((= index (string-length text)) (string-append text ".0"))
              ((char=? (string-ref text index) #\.) text)
              ((memv (string-ref text index) '(#\e #\E))
               (string-append (substring text 0 index) ".0" (substring text index (string-length text))))
              (else (loop (+ index 1))))))

    ;; ---- Declarations ----

    ;; One pass records resolved numeric declarations. Folded function bodies
    ;; normalize to an instruction sequence only when that function is emitted.
    ;; Heap headers encode a canonical type identity and its abstract category:
    ;; function = 0, struct = 2, array = 3. Odd references are immediate i31s.

    (define-record-type <module>
      (make-module types functions globals constants output)
      module?
      (types module-types) (functions module-functions)
      (globals module-globals) (constants module-constants) (output module-output))

    (define-record-type <function>
      (make-function name params result locals body import type attributes)
      function?
      (name function-name) (params function-params) (result function-result)
      (locals function-locals) (body function-body) (import function-import)
      (type function-wasm-type) (attributes function-attributes set-function-attributes!))

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
                       (and (not import) (car (cddddr node))) import type "")))

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
        ((global) (vector-set! (module-globals (current-module)) (cadr node) node))
        ;; Names are optional optimization hints, never semantic requirements.
        ((function-name)
         (when (< (cadr node) (vector-length (module-functions (current-module))))
           (set-function-attributes! (function-info (cadr node)) (function-attributes-for-name (caddr node)))))))

    (define (function-attributes-for-name name)
      (if (prefix? "cold." name) "cold " ""))

    (define (function-type index) (function-wasm-type (function-info index)))

    ;; ---- Native function state ----

    ;; Locals and structured joins use entry-block slots. LLVM promotes them to
    ;; SSA; this keeps Wasm branch values explicit without a second CFG pass.
    ;; A false live flag means control cannot fall through. The operand
    ;; stack holds already-produced SSA values, never deferred reads or calls.

    (define-record-type <emitter>
      (make-emitter locals targets serial live? port slots stack result roots local-roots)
      emitter?
      (locals emitter-locals set-emitter-locals!)
      (targets emitter-targets set-emitter-targets!)
      (serial emitter-serial set-emitter-serial!)
      (live? emitter-live? set-emitter-live!) (port emitter-port)
      (slots emitter-slots set-emitter-slots!)
      (stack emitter-stack set-emitter-stack!) (result emitter-result set-emitter-result!)
      (roots emitter-roots set-emitter-roots!)
      (local-roots emitter-local-roots set-emitter-local-roots!))

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
                            (cons (list "  " name " = alloca " (llvm-type type) ", align 8\n")
                                  (emitter-slots emitter)))
        (constant type name)))

    (define (store value pointer)
      (line "store " (typed value) ", ptr " (cdr pointer) ", align 1"))

    (define (load pointer)
      (instruction (car pointer) "load " (llvm-type (car pointer)) ", ptr " (cdr pointer) ", align 1"))

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
      (if (string=? (llvm-type type) (llvm-type (car value))) (constant type (cdr value))
          (instruction type opcode " " (typed value) " to " (llvm-type type))))

    (define (call-native name result arguments)
      (let ((call (list "call " (llvm-type result) " @" name "(" (llvm-join (map typed arguments) ", ") ")")))
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

    ;; Reference locals live directly in the frame. At synchronous safepoints
    ;; only operand temporaries need copies. Nonmoving objects need no reload.
    ;; The active count excludes stale temporary slots left by earlier loops.
    (define (publish-roots arguments)
      (let* ((emitter (current-emitter)) (offset (emitter-local-roots emitter))
             (values (filter reference-value? (append (emitter-stack emitter) arguments)))
             (count (+ offset (length values))))
        (set-emitter-roots! emitter (max (emitter-roots emitter) count))
        (for-each (lambda (value index) (store value (root-slot (+ index 3))))
                  values (iota (length values) offset))
        (store (constant "i64" count) (root-slot 2))))

    (define (local-storage type)
      (if (not (string=? type "ref")) (slot type)
          (let* ((emitter (current-emitter)) (index (emitter-local-roots emitter)))
            (set-emitter-local-roots! emitter (+ index 1))
            (constant type (cdr (root-slot (+ index 3)))))))

    (define (root-slot index)
      (constant "i64" (cdr (instruction "ptr" "getelementptr i64, ptr %roots, i64 " index))))

    (define (leave-roots) (line "call void @native_roots_leave(ptr %roots)"))

    (define (return-value value . tail?)
      (unless (and (pair? tail?) (car tail?)) (leave-roots))
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
        (let* ((instruction (take-instruction! code)) (op (car instruction)))
          (case op
            ((end else) op)
            ((block loop if) (emit-control op (cadr instruction) code) (loop))
            (else (when (alive?) (push-value! (emit-operation instruction))) (loop))))))

    (define (take-instruction! code)
      (let ((remaining (vector-ref code 0)))
        (when (null? remaining) (error "missing Wasm function ending"))
        (vector-set! code 0 (cdr remaining))
        (car remaining)))

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

    ;; Integration tests collect immediately before tail unlinking and after
    ;; the callee publishes its parameters. Production collection is allocation-driven.
    (define current-native-gc-stress (make-parameter #f))
    (define (stress-safepoint arguments)
      (when (current-native-gc-stress)
        (publish-roots arguments)
        (call-native "native_gc_collect" "void" '())))

    (define (emit-call name arguments result tail?)
      ;; tailcc guarantees tail lowering even when argument counts differ.
      ;; LLVM 22 x86-64 mishandles musttail with growing stack arguments; the
      ;; executable ABI regression covers tailcc + tail across that boundary.
      ;; No collection can occur between unlinking and the callee publishing.
      (when tail? (stress-safepoint arguments))
      (if tail? (leave-roots) (publish-roots arguments))
      (let* ((code (list (if tail? "tail " "") "call tailcc " (llvm-type result) " " name
                         "(" (llvm-join (map typed arguments) ", ") ")"))
             (value (if (string=? result "void") (begin (line code) #f)
                        (instruction result code))))
        (when tail? (return-value value #t))
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
             (reference (load (constant "ref" (cdr (table-slot table index))))))
        (trap-unless (truth (reference-test reference (list 'ref type))))
        (emit-call (cdr (function-pointer reference)) arguments
                   (result-type (type-definition type)) tail?)))

    (define (reference-test reference type)
      (let* ((nullable? (eq? (cadr type) 'null))
             (heap (if nullable? (caddr type) (cadr type)))
             (exact? (and (pair? heap) (eq? (car heap) 'exact)))
             (heap (if exact? (cadr heap) heap))
             (tag (if (integer? heap) (type-id heap)
                      (case heap ((any eq) -1) ((i31) -2) ((struct) -3) ((array) -4)
                            ((func) -5) ((none nofunc) -6)
                            (else (error "unsupported native reference test" type))))))
        (if (= tag -2) (i31-test reference nullable?)
            (call-native "native_ref_test" "i32"
                         (list reference (constant "i64" tag)
                               (constant "i32" (if nullable? 1 0))
                               (constant "i32" (if exact? 1 0)))))))

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
      ;; The wrapping i32 shift discards input bit 31. Zero extension makes
      ;; each payload one canonical odd word; heap references remain full i64s.
      (let* ((shifted (instruction "i32" "shl " (typed value) ", 1"))
             (tagged (instruction "i32" "or " (typed shifted) ", 1")))
        (cast "zext" tagged "ref")))

    (define (emit-i31-get reference signed?)
      (let ((tagged (cast "trunc" (nonnull reference) "i32")))
        (instruction "i32" (if signed? "ashr " "lshr ") (typed tagged) ", 1")))

    ;; ---- Structs and arrays ----

    ;; Zero-filled native allocations contain uncompressed references. The
    ;; emitted type layouts identify reference fields precisely for tracing.
    ;; Struct fields occupy eight-byte slots. Arrays use their declared storage
    ;; width; only reference arrays have eight-byte GC edges to trace.
    ;; Interior pointers stay recognizable across allocating operands and calls.

    (define (allocate-struct name values)
      (let* ((reference (call-native "native_alloc" "ref"
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
      (call-native "native_array_new" "ref"
                   (list (constant "i64" (type-id name)) length (value-word initial)
                         (constant "i32" (storage-size (storage-type (array-type name)))))))

    (define (emit-array-new name default?)
      (let* ((type (value-type (array-type name))) (length (pop-value!))
             (initial (if default? (constant type (zero type)) (pop-value!))))
        (new-array name length initial)))

    ;; Array headers contain kind and u64 length, then tightly packed elements.
    ;; Validated Wasm establishes the array kind and storage width. These checks
    ;; and accesses do not collect; every operand has already been evaluated.
    (define (array-length reference)
      (nonnull reference)
      (let ((tag (instruction "i64" "and " (typed reference) ", 1")))
        (trap-unless (instruction "i1" "icmp eq " (typed tag) ", 0")))
      (let* ((pointer (cast "inttoptr" reference "ptr"))
             (length (instruction "ptr" "getelementptr i64, " (typed pointer) ", i64 1")))
        (load (constant "i64" (cdr length)))))

    (define (array-slot reference index type)
      (let* ((length (array-length reference)) (index (cast "zext" index "i64")))
        (trap-unless (instruction "i1" "icmp ult " (typed index) ", " (cdr length)))
        (let* ((pointer (cast "inttoptr" reference "ptr"))
               (payload (instruction "ptr" "getelementptr i8, " (typed pointer) ", i64 16"))
               (address (instruction "ptr" "getelementptr " (llvm-type type) ", " (typed payload) ", " (typed index))))
          (constant type (cdr address)))))

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

    (define (emit-array-copy name)
      ;; Wasm validation requires compatible element storage types. Reference
      ;; subtyping changes the allowed values, never the eight-byte stride.
      (call-native "native_array_copy" "void"
                   (append (pop-values! 5)
                           (list (constant "i32" (storage-size (storage-type (array-type name))))))))

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
              ((prefix? "trunc_sat_" name)
               ;; LLVM's saturating intrinsic preserves Wasm's NaN -> 0 and
               ;; range clamps; ordinary fptosi/fptoui would produce poison.
               (call-native (list "llvm.fpto" (substring name (- (string-length name) 1))
                                  "i.sat." base "." (if (string=? (car value) "float") "f32" "f64"))
                            target values))
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
          ((table.get) (load (constant "ref" (cdr (table-slot table (car values))))))
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
        ;; Publish before operands are popped: constructors retain their fields
        ;; across allocation, including an array's erased initial machine word.
        (when (memq op '(struct.new struct.new_default array.new array.new_default array.new_fixed table.grow))
          (publish-roots '()))
        (case op
          ((local.get) (load (local-slot (car args))))
          ((numeric) (emit-numeric (car args) (cadr args) (pop-values! (caddr args))))
          ((i32.const) (constant "i32" (car args)))
          ((local.set local.tee) (emit-local-set (car args) (eq? op 'local.tee)))
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
          ((ref.null) (constant "ref" 0))
          ((ref.func) (constant "ref" (list "ptrtoint (ptr " (symbol-name "ref." (car args)) " to i64)")))
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
          ((array.len) (cast "trunc" (array-length (pop-value!)) "i32"))
          ((array.copy) (emit-array-copy (car args)))
          ((table.get table.set table.size table.grow)
           (emit-table op (car args)))
          ((i64.const) (constant "i64" (car args)))
          ((f32.const) (emit-f32-constant (car args)))
          ((f64.const) (constant "double" (float-constant (car args))))
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
           (let* ((type (value-type local)) (pointer (local-storage type)))
             (vector-set! (emitter-locals (current-emitter)) index pointer)
             (store (constant type (if (< index (length params)) (llvm-name "%arg" index) (zero type))) pointer)))
         locals (iota (length locals) 0))))

    (define (emit-definition name params body . attributes)
      (let ((emitter (make-emitter '#() '() 0 #t
                                   (open-output-string) '() '() "void" 0 0)))
        (parameterize ((current-emitter emitter)) (body))
        (output "define " name "(" (llvm-join (map typed params) ", ") ") " attributes "{\nentry:")
        (for-each (lambda (line) (write-llvm line (module-output (current-module))))
                  (reverse (emitter-slots emitter)))
        (output "  %roots = alloca { ptr, i64, i64, [" (max (emitter-roots emitter) (emitter-local-roots emitter)) " x i64] }, align 8")
        (output "  call void @native_roots_enter(ptr %roots, i64 " (emitter-roots emitter) ")")
        (display (get-output-string (emitter-port emitter)) (module-output (current-module)))
        (close-output-port (emitter-port emitter))
        (output "}\n")))

    ;; Each binding is ((module name) C-symbol (parameters) (results)). The
    ;; build driver supplies provider declarations, never inferred call types.
    (define current-native-imports (make-parameter '()))

    (define (import-name function)
      (let* ((import (function-import function))
             (entry (assoc import (current-native-imports)))
             (signature (type-definition (function-wasm-type function))))
        (unless entry (error "native import has no provider declaration" import))
        (unless (equal? (cdr signature) (cddr entry))
          (error "native provider signature does not match Wasm import" import (cdr signature) (cddr entry)))
        (llvm-quoted (cadr entry))))

    (define (emit-function function)
      (let ((params (parameter-values function)) (result (function-result function)))
        (emit-definition
         (list "internal tailcc " (llvm-type result) " " (symbol-name "f." (function-name function)))
         params
         (lambda ()
           (if (function-import function)
               (begin (publish-roots params)
                      (return-value (call-native (import-name function) result params)))
               (begin
                 (initialize-locals function)
                 (stress-safepoint '())
                 (set-emitter-result! (current-emitter) result)
                 (let ((exit (make-target "return" result))
                       (code (vector (lower-wasm-body (function-body function)))))
                   (set-emitter-targets! (current-emitter) (list exit))
                   (unless (and (eq? (emit-stream code) 'end) (null? (vector-ref code 0)))
                     (error "invalid Wasm function ending"))
                   (close-control exit)
                   (let ((value (join-target exit))) (when (alive?) (return-value value)))))))
         (function-attributes function))))

    (define (emit-export node)
      (case (caaddr node)
        ((global)
         (let ((pointer (global-slot (cadr (caddr node)))))
           (emit-definition (list (llvm-type (car pointer)) " " (symbol-name "wasm-global." (cadr node)))
                            '() (lambda () (return-value (load pointer))))))
        ((func)
         (let* ((function (function-info (cadr (caddr node)))) (params (parameter-values function))
                (result (function-result function)))
           (emit-definition
            (list (llvm-type result) " " (symbol-name "wasm." (cadr node))) params
            (lambda () (return-value (emit-call (symbol-name "f." (function-name function))
                                                params result #f))))))
        (else (error "unsupported native Wasm export kind" (caaddr node)))))

    (define (emit-import-declaration function)
      (output "declare " (llvm-type (function-result function)) " @" (import-name function)
              "(" (llvm-join (map (lambda (type) (llvm-type (value-type type))) (function-params function)) ", ") ")"))

    ;; ---- Module initialization ----

    ;; Immutable bindings retain their initial object graphs for the module's
    ;; lifetime. The objects themselves keep their declared field mutability;
    ;; each mutable static reference slot is a permanent, explicit GC root.
    ;; A plan is committed only if every operation is a supported constant.
    (define (mutable-type? type) (and (pair? type) (eq? (car type) 'mut)))
    (define (static-global index) (vector-ref (module-constants (current-module)) index))

    (define (constant-cast opcode value type)
      (if (string=? (llvm-type type) (llvm-type (car value))) (constant type (cdr value))
          (constant type (list opcode " (" (typed value) " to " (llvm-type type) ")"))))

    (define (static-word type value)
      (case type
        ((f64) (constant-cast "bitcast" value "i64"))
        ;; Only default f32 initializers reach the static planner today.
        ((f32) (unless (equal? (cdr value) "0.0") (error "unsupported static f32" value))
         (constant "i64" 0))
        ((i8 i16 i32)
         (constant "i64" (modulo (cdr value) (case type ((i8) 256) ((i16) 65536) (else 4294967296)))))
        (else value)))

    (define (static-element type value)
      (if (memq type '(i8 i16))
          (constant (storage-type type) (modulo (cdr value) (if (eq? type 'i8) 256 65536)))
          value))

    (define (static-object type fields length plan)
      (let* ((name (list "@object." (vector-ref plan 0) "." (vector-ref plan 2)))
             (definition (type-definition type))
             (types (if length (make-list length (array-type type)) (map field-type (cdr definition))))
             (words (append (list (constant "i64" (type-id type)))
                            (if length (list (constant "i64" length)) '())
                            (map (if length static-element static-word) types fields)))
             (mutable? (if length (mutable-type? (cadr definition))
                           (pair? (filter mutable-type? (cdr definition))))))
        (vector-set! plan 1 (cons (list name words mutable?) (vector-ref plan 1)))
        (vector-set! plan 2 (+ 1 (vector-ref plan 2)))
        (constant "ref" (list "ptrtoint (ptr " name " to i64)"))))

    (define (take-constants stack count)
      (let loop ((stack stack) (left count) (values '()))
        (cond ((= left 0) (cons values stack))
              ((null? stack) (error "missing Wasm constant operand"))
              (else (loop (cdr stack) (- left 1) (cons (car stack) values))))))

    (define (static-struct node stack plan)
      (let* ((type (cadr node)) (fields (cdr (type-definition type)))
             (default? (eq? (car node) 'struct.new_default))
             (values (if default?
                         (cons (map (lambda (field)
                                      (let ((type (value-type (field-type field)))) (constant type (zero type)))) fields) stack)
                         (take-constants stack (length fields)))))
        (cons (static-object type (car values) #f plan) (cdr values))))

    (define (static-array node stack plan)
      (let* ((type (cadr node)) (op (car node))
             (length (if (eq? op 'array.new_fixed) (caddr node) (cdar stack)))
             (rest (if (eq? op 'array.new_fixed) stack (cdr stack))))
        (and (integer? length) (<= 0 length 65536)
             (let* ((element (value-type (array-type type)))
                    (values (case op
                              ((array.new_fixed) (take-constants rest length))
                              ((array.new) (cons (make-list length (car rest)) (cdr rest)))
                              (else (cons (make-list length (constant element (zero element))) rest)))))
               (cons (static-object type (car values) length plan) (cdr values))))))

    (define (static-operation node stack plan)
      (case (car node)
        ((i32.const) (cons (constant "i32" (cadr node)) stack))
        ((i64.const) (cons (constant "i64" (cadr node)) stack))
        ((f64.const) (cons (constant "double" (float-constant (cadr node))) stack))
        ((ref.null) (cons (constant "ref" 0) stack))
        ((ref.func) (cons (constant "ref" (list "ptrtoint (ptr " (symbol-name "ref." (cadr node)) " to i64)")) stack))
        ((ref.i31) (and (integer? (cdar stack))
                        (cons (constant "ref" (+ 1 (* 2 (modulo (cdar stack) 2147483648)))) (cdr stack))))
        ((global.get)
         (let ((prior (static-global (cadr node))))
           (and prior (not (mutable-type? (caddr (global-info (cadr node))))) (cons (car prior) stack))))
        ((struct.new struct.new_default) (static-struct node stack plan))
        ((array.new array.new_fixed array.new_default) (static-array node stack plan))
        (else #f)))

    (define (plan-global! node)
      (let ((plan (vector (cadr node) '() 0)))
        (let loop ((instructions (cadddr node)) (stack '()))
          (if (null? instructions)
              (when (and (= (length stack) 1)
                         (or (null? (vector-ref plan 1)) (not (mutable-type? (caddr node)))))
                (vector-set! (module-constants (current-module)) (cadr node)
                             (cons (car stack) (reverse (vector-ref plan 1)))))
              (let ((next (static-operation (car instructions) stack plan)))
                (when next (loop (cdr instructions) next)))))))

    (define (declare-static-object object)
      (let ((words (cadr object)))
        (output (car object) " = internal " (if (caddr object) "global " "constant ")
                "{ " (llvm-join (map (lambda (word) (llvm-type (car word))) words) ", ") " } { "
                (llvm-join (map typed words) ", ") " }, align 8")))

    (define (declare-global node)
      (let ((pointer (global-slot (cadr node))) (plan (static-global (cadr node))))
        (if plan
            (begin (for-each declare-static-object (cdr plan))
                   (output (cdr pointer) " = internal " (if (mutable-type? (caddr node)) "global " "constant ")
                           (typed (car plan))))
            (output (cdr pointer) " = internal global " (llvm-type (car pointer)) " " (zero (car pointer))))))

    (define (declare-function-reference function)
      (output (symbol-name "ref." (function-name function))
              " = internal constant { i64, ptr } { i64 "
              (type-id (function-type (function-name function)))
              ", ptr " (symbol-name "f." (function-name function)) " }, align 8"))

    (define (emit-declaration node)
      (case (car node)
        ((global) (declare-global node))
        ((func) (declare-function-reference (function-info (cadr node))))
        ((import) (let ((function (function-info (cadr (cadddr node)))))
                    (emit-import-declaration function) (declare-function-reference function)))
        ((table) (output (symbol-name "table." (cadr node)) " = internal global { ptr, i32, i32 } zeroinitializer"))))

    ;; ---- Precise heap layouts and permanent roots ----

    (define (reference-offsets fields start)
      (let loop ((fields fields) (offset start) (result '()))
        (if (null? fields) (reverse result)
            (loop (cdr fields) (+ offset 1)
                  (if (string=? (value-type (field-type (car fields))) "ref")
                      (cons offset result) result)))))

    (define (gc-layout index)
      (let* ((type (type-definition index)) (array? (eq? (car type) 'array))
             (offsets (if (eq? (car type) 'struct) (reference-offsets (cdr type) 1) '()))
             (kind (if array? (if (pair? (reference-offsets (cdr type) 2)) 2 0) 1)))
        (output "@gc.fields." index " = private constant [" (length offsets) " x i32] ["
                (llvm-join (map (lambda (offset) (list "i32 " offset)) offsets) ", ") "]")
        (list "{ i32, i32, ptr } { i32 " kind ", i32 " (length offsets)
              ", ptr @gc.fields." index " }")))

    (define (static-root-slots object)
      ;; Struct slots and reference-array elements are all eight bytes. Packed
      ;; numeric arrays contain no references, so their narrower fields add no roots.
      (if (not (caddr object)) '()
          (let loop ((words (cadr object)) (offset 0) (roots '()))
            (if (null? words) roots
                (loop (cdr words) (+ offset 1)
                      (if (reference-value? (car words))
                          (cons (list "ptr getelementptr (i64, ptr " (car object) ", i64 " offset ")") roots)
                          roots))))))

    (define (global-root-slots node)
      (let ((plan (static-global (cadr node))) (slot (global-slot (cadr node))))
        (append (if (and (reference-value? slot) (or (not plan) (mutable-type? (caddr node))))
                    (list (list "ptr " (cdr slot))) '())
                (if plan (apply append (map static-root-slots (cdr plan))) '()))))

    (define (declare-gc-array name type values)
      (output "@native_gc_" name "_count = constant i64 " (length values))
      (output "@native_gc_" name " = constant [" (length values) " x " type "] ["
              (llvm-join values ", ") "]"))

    (define (declare-gc-layouts declarations)
      (declare-gc-array "parents" "i64"
                        (map (lambda (node)
                               (list "i64 " (if (and (pair? (cdddr node)) (car (cddddr node)))
                                                (type-id (car (cddddr node))) 0)))
                             (filter (lambda (node) (eq? (car node) 'type)) declarations)))
      (declare-gc-array "layouts" "{ i32, i32, ptr }"
                        (map gc-layout (iota (vector-length (module-types (current-module))) 0)))
      (declare-gc-array "globals" "ptr"
                        (apply append (map global-root-slots
                                           (filter (lambda (node) (eq? (car node) 'global)) declarations))))
      (declare-gc-array "tables" "ptr"
                        (map (lambda (node) (list "ptr " (symbol-name "table." (cadr node))))
                             (filter (lambda (node) (eq? (car node) 'table)) declarations))))

    (define (initialize-table node)
      (call-native "native_table_init" "void"
                   (list (constant "ptr" (symbol-name "table." (cadr node)))
                         (constant "i32" (caddr node)) (constant "i32" (cadddr node)))))

    (define (initialize-element node)
      (let ((table (cadr node)) (offset (emit-constant-expression (caddr node)))
            (functions (cadddr node)))
        (call-native "native_table_check" "void"
                     (list (constant "ptr" (symbol-name "table." table)) offset
                           (constant "i32" (length functions))))
        (for-each
         (lambda (name index)
           (let ((address (instruction "i32" "add " (typed offset) ", " index)))
             (store (constant "i64" (list "ptrtoint (ptr " (symbol-name "ref." name) " to i64)"))
                    (constant "i64" (cdr (table-slot table address))))))
         functions (iota (length functions) 0))))

    (define (initialize-declaration node)
      (case (car node)
        ((global) (unless (static-global (cadr node))
                    (store (emit-constant-expression (cadddr node)) (global-slot (cadr node)))))
        ((table) (initialize-table node))
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
      '("declare void @native_gc_collect()"
        "declare void @native_roots_enter(ptr, i64)"
        "declare void @native_roots_leave(ptr)"
        "declare void @native_trap() noreturn cold"
        "declare i64 @native_alloc(i64)"
        "declare i32 @native_ref_test(i64, i64, i32, i32)"
        "declare i64 @native_array_new(i64, i32, i64, i32)"
        "declare void @native_array_copy(i64, i32, i64, i32, i32, i32)"
        "declare void @native_table_init(ptr, i32, i32)"
        "declare void @native_table_check(ptr, i32, i32)"
        "declare ptr @native_table_slot(ptr, i32)"
        "declare i32 @native_table_size(ptr)"
        "declare i32 @native_table_grow(ptr, i64, i32)"))

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
                                         "(" (cdr source) ")")
                                 (output "declare " type " @llvm.fpto" sign "i.sat." type "." (car source)
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

    (define (emit-module declarations port)
      (let ((module (make-module (make-vector (declaration-count declarations 'type))
                                 (make-vector (+ (declaration-count declarations 'func)
                                                 (declaration-count declarations 'import)))
                                 (make-vector (declaration-count declarations 'global))
                                 (make-vector (declaration-count declarations 'global) #f) port)))
        (parameterize ((current-module module))
          (for-each record-declaration! declarations)
          (for-each (lambda (node) (when (eq? (car node) 'global) (plan-global! node))) declarations)
          (output "; WasmGC -> LLVM. Generated by the wasm-native library.\n"
                  "target triple = \"x86_64-unknown-linux-gnu\"\n")
          (for-each output native-declarations)
          (declare-numeric-helpers)
          (for-each emit-declaration declarations)
          (declare-gc-layouts declarations)
          (for-each (lambda (node)
                      (case (car node)
                        ((func) (emit-function (function-info (cadr node))))
                        ((import) (emit-function (function-info (cadr (cadddr node)))))
                        ((export) (emit-export node)))) declarations)
          (emit-initializer declarations))))

    (define (wasm->llvm datum port)
      (emit-module (resolve-wasm datum) port))

    (define (wasm->llvm-file datum output)
      (call-with-output-file output (lambda (port) (wasm->llvm datum port)))))

  ;; ---- Tests ----

  ;; Executable ABI, trap, GC and folded control-flow tests are integration tests.
  (cond-expand
   (snail-tests
    (export test-llvm)
    (import (wasm-native test-utils))
    (begin
      (define (test-llvm-floats)
        (expect (float-spelling "1e-300") "1.0e-300")
        (expect (float-spelling "-0.0") "-0.0")
        (expect (float-spelling "9223372036854775808") "9223372036854775808.0")
        (expect (float-spelling "1.25e20") "1.25e20"))

      (define (test-llvm-rejections)
        (for-each
         (lambda (datum)
           (expect (guard (error (else #t))
                     (wasm->llvm datum (open-output-string)) #f) #t))
         '((module (memory 1))
           (module (table 0 funcref) (export "table" (table 0)))
           (module (type $many (func (result i32 i64))))
           (module (import "unknown" "thing" (func)))
           (module (import "snail.rust" "snail:fail" (func)))
           (module (import "wasi_snapshot_preview1" "args_get" (func (param i32 i32) (result i32)))))))

      (define (test-llvm)
        (run-test test-llvm-floats)
        (run-test test-llvm-rejections))))))
