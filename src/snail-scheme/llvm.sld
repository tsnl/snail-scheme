;; Specialize Dybvig's stack operations into immutable LLVM functions and blocks.
;; Scheme owns ordinary control flow; Rust owns objects and allocation boundaries.
(define-library (snail-scheme llvm)
  (export write-vm-program-as-llvm)
  (import (snail-scheme trace) (scheme base) (scheme cxr) (scheme write) (snail-scheme vm)
          (prefix (snail-scheme llvmlite) ir:))
  (begin

    ;; ---- Runtime and register protocol ----

    ;; ABI 3 is strictly 32-bit. These repr(C) fields are four bytes each.
    ;; Stack depths count from the high address: depth d is stack_end[-d].
    ;; Only the active suffix 1..s is scanned. Saved frame depths and code labels
    ;; are fixnums, so every active word remains a valid precisely traced Value.
    ;; A stack resize invalidates slot pointers; register-field pointers are stable.
    (define registers '(a c s f count end capacity globals constants argc entry locals frames max-frames stopped))
    (define pointer-registers '(end globals constants))
    (define stop-code 4294967295)
    (define consume-code 4294967294)
    (define apply-code 4294967293)
    (define return-code 4294967292)
    (define (word number) (ir:integer ir:i32 number))
    (define (boolean value) (ir:integer ir:i1 (if value 1 0)))
    (define (value function type name) (ir:local function type name))
    (define (register-type name) (if (memq name pointer-registers) ir:ptr ir:i32))
    (define (address function name) (value function ir:ptr (string-append "r_" (symbol->string name))))

    (define (register-addresses function state)
      (let loop ((names registers) (index 0))
        (if (null? names) '()
            (cons (ir:gep (address function (car names)) ir:i8 state (list (word (* 4 index))))
                  (loop (cdr names) (+ index 1))))))

    (define (read-register function name local)
      (ir:load (value function (register-type name) local) (address function name)))
    (define (write-register function name source) (ir:store source (address function name)))
    (define (single-result function result)
      (list (write-register function 'a result) (write-register function 'count (word 1))))

    (define (foreign name result types)
      (let loop ((types types) (index 0) (parameters '()))
        (if (null? types) (ir:function name result (reverse parameters))
            (loop (cdr types) (+ index 1)
                  (cons (cons (car types) (ir:indexed-name "arg" index)) parameters)))))

    (define runtime-functions
      (list (cons 'state (foreign "snail_rt_state" ir:ptr (list ir:ptr)))
            (cons 'reserve (foreign "snail_rt_reserve" ir:void (list ir:ptr ir:i32)))
            (cons 'box (foreign "snail_rt_box" ir:void (list ir:ptr ir:i32)))
            (cons 'cell (foreign "snail_rt_cell" ir:ptr (list ir:ptr ir:i32)))
            (cons 'free (foreign "snail_rt_free" ir:ptr (list ir:ptr ir:i32)))
            (cons 'uninitialized (foreign "snail_rt_uninitialized" ir:void (list ir:ptr)))
            (cons 'value-error (foreign "snail_rt_value_error" ir:void (list ir:ptr)))
            (cons 'close (foreign "snail_rt_close" ir:void
                                  (list ir:ptr ir:i32 ir:i32 ir:i32 ir:i32 ir:i32)))
            (cons 'prepare (foreign "snail_rt_prepare_apply" ir:i32 (list ir:ptr ir:i32)))
            (cons 'numeric (foreign "snail_rt_numeric" ir:void (list ir:ptr ir:i32)))
            (cons 'receive (foreign "snail_rt_receive" ir:void (list ir:ptr)))
            (cons 'capture (foreign "snail_rt_capture" ir:void (list ir:ptr)))
            (cons 'restore (foreign "snail_rt_restore" ir:void (list ir:ptr ir:i32)))
            (cons 'move (foreign "llvm.memmove.p0.p0.i32" ir:void (list ir:ptr ir:ptr ir:i32 ir:i1)))
            (cons 'halt (foreign "snail_halt" ir:void (list ir:ptr)))
            (cons 'invalid (foreign "snail_invalid_pc" ir:void (list ir:ptr ir:i32)))
            (cons 'atom (foreign "snail_const_atom" ir:void (list ir:ptr ir:i32 ir:i32 ir:ptr ir:i32)))
            (cons 'pair (foreign "snail_const_pair" ir:void (list ir:ptr ir:i32 ir:i32 ir:i32)))
            (cons 'vector (foreign "snail_const_vector" ir:void (list ir:ptr ir:i32 ir:ptr ir:i32)))
            (cons 'primitive (foreign "snail_global_primitive" ir:void (list ir:ptr ir:i32 ir:ptr ir:i32)))))
    (define (runtime-function name) (cdr (assq name runtime-functions)))

    (define (vm-function name result arguments)
      (ir:function (string-append "snail_vm_" name) result
                   (append (list (cons ir:ptr "vm") (cons ir:ptr "state"))
                           (map (lambda (name) (cons ir:i32 name)) arguments))))
    (define vm-functions
      (map (lambda (spec) (cons (car spec) (vm-function (symbol->string (car spec))
                                                        (if (eq? (car spec) 'test) ir:i32 ir:i1)
                                                        (cdr spec))))
           (append '((constant "index") (refer-local "index") (refer-free "index") (refer-global "index")
                     (init-local "index") (set-local "index") (set-free "index") (set-global "index")
                     (indirect) (box "index") (argument) (frame "resume") (shift "argc") (test)
                     (reserve "depth") (close "code" "required" "rest" "locals" "captures"))
                   (map (lambda (entry) (list (cdr entry) "global")) binary-numeric-primitives))))
    (define (instruction-function operation)
      (let ((entry (assq operation vm-functions)))
        (if entry (cdr entry) (error "unknown VM instruction" operation))))

    ;; ---- Inline instruction bodies ----

    ;; Successful pure instructions have no Rust call or stopped-state poll.
    ;; Checked helpers return success directly; inlining connects their error
    ;; branches to the program exit without an extra check on every instruction.
    (define (handler-definition function entry-instructions terminator bodies)
      (ir:define-function function 'internal '(alwaysinline)
                          (cons (ir:block-body (ir:block function "entry")
                                               (append (register-addresses function (ir:parameter function 1))
                                                       entry-instructions) terminator) bodies)))
    (define (handler-exit function name success)
      (ir:block-body (ir:block function name) '() (ir:ret (boolean success))))
    (define (service-error function block service)
      (ir:block-body block (list (ir:call #f (runtime-function service) (list (ir:parameter function 0))))
                     (ir:ret (if (ir:type=? (ir:function-result function) ir:i32) (word 2) (boolean #f)))))

    (define (single-check function)
      (list (read-register function 'count "count")
            (ir:icmp (value function ir:i1 "single") 'eq (value function ir:i32 "count") (word 1))))
    (define (stopped-result function leading)
      (append leading (list (read-register function 'stopped "stopped")
                            (ir:icmp (value function ir:i1 "running") 'eq
                                     (value function ir:i32 "stopped") (word 0)))))

    (define (stack-address function pointer end depth)
      (let ((negative (value function ir:i32 (string-append (ir:value-name pointer) "_negative"))))
        (list (ir:binop negative 'sub (word 0) depth)
              (ir:gep pointer ir:i32 end (list negative)))))

    (define (local-address function pointer index)
      (let ((frame (value function ir:i32 "frame")) (end (value function ir:ptr "end"))
            (offset (value function ir:i32 "offset")) (depth (value function ir:i32 "depth")))
        (append (list (read-register function 'f "frame") (read-register function 'end "end")
                      (ir:binop offset 'add frame index) (ir:binop depth 'add offset (word 1)))
                (stack-address function pointer end depth))))

    (define (slot-address function kind pointer)
      (let ((index (ir:parameter function 2)))
        (case kind
          ((local) (local-address function pointer index))
          ((free) (list (ir:call pointer (runtime-function 'free) (list (ir:parameter function 0) index))))
          (else (list (read-register function kind "array")
                      (ir:gep pointer ir:i32 (value function ir:ptr "array") (list index)))))))

    (define (reference-handler operation kind)
      (let* ((function (instruction-function operation)) (source (value function ir:ptr "source"))
             (loaded (ir:block function "loaded")) (valid (ir:block function "valid"))
             (unbound (ir:block function "unbound")) (failed (ir:block function "failed")))
        (handler-definition
         function (append (slot-address function kind source)
                          (list (ir:icmp (value function ir:i1 "missing") 'eq source ir:null-pointer)))
         (ir:cbr (value function ir:i1 "missing") failed loaded)
         (list (ir:block-body loaded (list (ir:load (value function ir:i32 "item") source)
                                           (ir:icmp (value function ir:i1 "uninitialized") 'eq
                                                    (value function ir:i32 "item") (word 44)))
                              (ir:cbr (value function ir:i1 "uninitialized") unbound valid))
               (ir:block-body valid (single-result function (value function ir:i32 "item")) (ir:ret (boolean #t)))
               (service-error function unbound 'uninitialized) (handler-exit function "failed" #f)))))

    (define (indirect-handler)
      (let* ((function (instruction-function 'indirect)) (cell (ir:block function "cell"))
             (loaded (ir:block function "loaded")) (valid (ir:block function "valid"))
             (failed (ir:block function "failed")) (unbound (ir:block function "unbound"))
             (source (value function ir:ptr "source")))
        (handler-definition
         function (single-check function) (ir:cbr (value function ir:i1 "single") cell (ir:block function "value_error"))
         (list (ir:block-body cell
                              (list (read-register function 'a "cell_value")
                                    (ir:call source (runtime-function 'cell)
                                             (list (ir:parameter function 0) (value function ir:i32 "cell_value")))
                                    (ir:icmp (value function ir:i1 "missing") 'eq source ir:null-pointer))
                              (ir:cbr (value function ir:i1 "missing") failed loaded))
               (ir:block-body loaded (list (ir:load (value function ir:i32 "item") source)
                                           (ir:icmp (value function ir:i1 "uninitialized") 'eq
                                                    (value function ir:i32 "item") (word 44)))
                              (ir:cbr (value function ir:i1 "uninitialized") unbound valid))
               (ir:block-body valid (single-result function (value function ir:i32 "item")) (ir:ret (boolean #t)))
               (service-error function unbound 'uninitialized)
               (service-error function (ir:block function "value_error") 'value-error)
               (handler-exit function "failed" #f)))))

    (define (assignment-handler operation kind boxed?)
      (let* ((function (instruction-function operation)) (locate (ir:block function "locate"))
             (located (ir:block function "located")) (store (ir:block function "store"))
             (source (value function ir:i32 "item")) (slot (value function ir:ptr "slot"))
             (destination (if boxed? (value function ir:ptr "destination") slot))
             (failed (ir:block function "failed")))
        (handler-definition
         function (single-check function) (ir:cbr (value function ir:i1 "single") locate (ir:block function "value_error"))
         (append
          (list (ir:block-body locate (append (list (read-register function 'a "item"))
                                              (slot-address function kind slot)
                                              (list (ir:icmp (value function ir:i1 "missing") 'eq slot ir:null-pointer)))
                               (ir:cbr (value function ir:i1 "missing") failed (if boxed? located store))))
          (if boxed?
              (list (ir:block-body located
                                   (list (ir:load (value function ir:i32 "cell_word") slot)
                                         (ir:call destination (runtime-function 'cell)
                                                  (list (ir:parameter function 0) (value function ir:i32 "cell_word")))
                                         (ir:icmp (value function ir:i1 "missing_cell") 'eq destination ir:null-pointer))
                                   (ir:cbr (value function ir:i1 "missing_cell") failed store))) '())
          (list (ir:block-body store (cons (ir:store source destination) (single-result function (word 36))) (ir:ret (boolean #t)))
                (service-error function (ir:block function "value_error") 'value-error)
                (handler-exit function "failed" #f))))))

    (define (reserve-handler)
      (let* ((function (instruction-function 'reserve)) (grow (ir:block function "grow"))
             (done (ir:block function "done")))
        (handler-definition
         function (list (read-register function 'capacity "capacity")
                        (ir:icmp (value function ir:i1 "fits") 'ule (ir:parameter function 2) (value function ir:i32 "capacity")))
         (ir:cbr (value function ir:i1 "fits") done grow)
         (list (ir:block-body grow
                              (stopped-result function (list (ir:call #f (runtime-function 'reserve)
                                                                      (list (ir:parameter function 0) (ir:parameter function 2)))))
                              (ir:ret (value function ir:i1 "running")))
               (handler-exit function "done" #t)))))

    (define (reserve-call function depth)
      (ir:call (value function ir:i1 "reserved") (instruction-function 'reserve)
               (list (ir:parameter function 0) (ir:parameter function 1) depth)))

    (define (argument-handler)
      (let* ((function (instruction-function 'argument)) (reserve (ir:block function "reserve"))
             (push (ir:block function "push")) (failed (ir:block function "failed"))
             (top (value function ir:i32 "top")) (slot (value function ir:ptr "slot")))
        (handler-definition
         function (single-check function) (ir:cbr (value function ir:i1 "single") reserve (ir:block function "value_error"))
         (list (ir:block-body reserve
                              (list (read-register function 's "s") (ir:binop top 'add (value function ir:i32 "s") (word 1))
                                    (reserve-call function top))
                              (ir:cbr (value function ir:i1 "reserved") push failed))
               (ir:block-body push
                              (append (list (read-register function 'end "end") (read-register function 'a "item"))
                                      (stack-address function slot (value function ir:ptr "end") top)
                                      (list (ir:store (value function ir:i32 "item") slot) (write-register function 's top)))
                              (ir:ret (boolean #t)))
               (service-error function (ir:block function "value_error") 'value-error)
               (handler-exit function "failed" #f)))))

    (define (tag-word function source name)
      (let ((shifted (value function ir:i32 (string-append name "_shifted"))))
        (list (ir:binop shifted 'shl source (word 1))
              (ir:binop (value function ir:i32 name) 'or shifted (word 1)))))

    (define (frame-handler)
      (let* ((function (instruction-function 'frame)) (push (ir:block function "push"))
             (top (value function ir:i32 "top")) (end (value function ir:ptr "end")))
        (handler-definition
         function (list (read-register function 's "s") (ir:binop top 'add (value function ir:i32 "s") (word 3))
                        (reserve-call function top))
         (ir:cbr (value function ir:i1 "reserved") push (ir:block function "failed"))
         (list (ir:block-body push (frame-stores function top end) (ir:ret (boolean #t)))
               (handler-exit function "failed" #f)))))

    (define (frame-stores function top end)
      (append
       (list (read-register function 'end "end") (read-register function 'f "f") (read-register function 'c "c")
             (ir:binop (value function ir:i32 "closure_depth") 'sub top (word 2))
             (ir:binop (value function ir:i32 "frame_depth") 'sub top (word 1)))
       (tag-word function (value function ir:i32 "f") "saved_f")
       (tag-word function (ir:parameter function 2) "saved_pc")
       (stack-address function (value function ir:ptr "closure_slot") end (value function ir:i32 "closure_depth"))
       (stack-address function (value function ir:ptr "frame_slot") end (value function ir:i32 "frame_depth"))
       (stack-address function (value function ir:ptr "resume_slot") end top)
       (list (ir:store (value function ir:i32 "c") (value function ir:ptr "closure_slot"))
             (ir:store (value function ir:i32 "saved_f") (value function ir:ptr "frame_slot"))
             (ir:store (value function ir:i32 "saved_pc") (value function ir:ptr "resume_slot"))
             (write-register function 's top))
       (increment-frame-count function)))

    (define (increment-frame-count function)
      (list (read-register function 'frames "frames") (read-register function 'max-frames "maximum")
            (ir:binop (value function ir:i32 "new_frames") 'add (value function ir:i32 "frames") (word 1))
            (ir:icmp (value function ir:i1 "higher") 'ugt (value function ir:i32 "new_frames") (value function ir:i32 "maximum"))
            (ir:select (value function ir:i32 "new_maximum") (value function ir:i1 "higher")
                       (value function ir:i32 "new_frames") (value function ir:i32 "maximum"))
            (write-register function 'frames (value function ir:i32 "new_frames"))
            (write-register function 'max-frames (value function ir:i32 "new_maximum"))))

    (define (shift-handler)
      (let* ((function (instruction-function 'shift)) (argc (ir:parameter function 2))
             (top (value function ir:i32 "top")) (end (value function ir:ptr "end")))
        (handler-definition
         function
         (append (list (read-register function 's "s") (read-register function 'f "f") (read-register function 'end "end")
                       (ir:binop top 'add (value function ir:i32 "f") argc)
                       (ir:binop (value function ir:i32 "bytes") 'mul argc (word 4)))
                 (stack-address function (value function ir:ptr "source") end (value function ir:i32 "s"))
                 (stack-address function (value function ir:ptr "destination") end top)
                 (list (ir:call #f (runtime-function 'move)
                                (list (value function ir:ptr "destination") (value function ir:ptr "source")
                                      (value function ir:i32 "bytes") (boolean #f)))
                       (write-register function 's top)))
         (ir:ret (boolean #t)) '())))

    (define (test-handler)
      (let* ((function (instruction-function 'test)) (test (ir:block function "test")))
        (handler-definition
         function (single-check function) (ir:cbr (value function ir:i1 "single") test (ir:block function "value_error"))
         (list (ir:block-body test
                              (list (read-register function 'a "item")
                                    (ir:icmp (value function ir:i1 "truth") 'ne (value function ir:i32 "item") (word 20))
                                    (ir:zext (value function ir:i32 "answer") (value function ir:i1 "truth")))
                              (ir:ret (value function ir:i32 "answer")))
               (service-error function (ir:block function "value_error") 'value-error)))))

    (define (object-handler operation count)
      (let ((function (instruction-function operation)))
        (handler-definition
         function (stopped-result function
                                  (list (ir:call #f (runtime-function operation)
                                                 (cons (ir:parameter function 0)
                                                       (let loop ((index 0))
                                                         (if (= index count) '()
                                                             (cons (ir:parameter function (+ index 2)) (loop (+ index 1)))))))))
         (ir:ret (value function ir:i1 "running")) '())))

    ;; ---- Binary numeric instructions ----

    ;; Operands are published at stack depths s-1 and s. The fast path neither
    ;; allocates nor changes f/c; fallback keeps those roots until Rust returns.
    (define (numeric-operands function)
      (append
       (list (read-register function 's "top") (read-register function 'end "end")
             (ir:binop (value function ir:i32 "left_depth") 'sub (value function ir:i32 "top") (word 1)))
       (stack-address function (value function ir:ptr "left_slot") (value function ir:ptr "end") (value function ir:i32 "left_depth"))
       (stack-address function (value function ir:ptr "right_slot") (value function ir:ptr "end") (value function ir:i32 "top"))
       (list (ir:load (value function ir:i32 "left") (value function ir:ptr "left_slot"))
             (ir:load (value function ir:i32 "right") (value function ir:ptr "right_slot")))))

    (define (fixnum-check function)
      (list (ir:binop (value function ir:i32 "tags") 'and (value function ir:i32 "left") (value function ir:i32 "right"))
            (ir:binop (value function ir:i32 "tag") 'and (value function ir:i32 "tags") (word 1))
            (ir:icmp (value function ir:i1 "fixnums") 'eq (value function ir:i32 "tag") (word 1))))

    ;; Decoded signed31 operands add/subtract exactly in signed32. Biasing the
    ;; result maps the signed31 range to 0..2^31-1 for one unsigned bounds check.
    (define (fixnum-arithmetic function operation)
      (list (ir:binop (value function ir:i32 "x") 'ashr (value function ir:i32 "left") (word 1))
            (ir:binop (value function ir:i32 "y") 'ashr (value function ir:i32 "right") (word 1))
            (ir:binop (value function ir:i32 "number") (if (eq? operation 'add) 'add 'sub)
                      (value function ir:i32 "x") (value function ir:i32 "y"))
            (ir:binop (value function ir:i32 "biased") 'add (value function ir:i32 "number") (word 1073741824))
            (ir:icmp (value function ir:i1 "fits") 'ule (value function ir:i32 "biased") (word 2147483647))
            (ir:binop (value function ir:i32 "shifted") 'shl (value function ir:i32 "number") (word 1))
            (ir:binop (value function ir:i32 "answer") 'or (value function ir:i32 "shifted") (word 1))))

    ;; Tagging preserves signed order, so comparisons need no decoding.
    (define (fixnum-comparison function operation)
      (let ((predicate (cdr (assq operation '((numeric-equal . eq) (less . slt) (less-equal . sle)
                                              (greater . sgt) (greater-equal . sge))))))
        (list (ir:icmp (value function ir:i1 "comparison") predicate
                       (value function ir:i32 "left") (value function ir:i32 "right"))
              (ir:select (value function ir:i32 "answer") (value function ir:i1 "comparison") (word 84) (word 20)))))

    (define (numeric-fallback function)
      (ir:block-body
       (ir:block function "fallback")
       (stopped-result function (list (ir:call #f (runtime-function 'numeric)
                                               (list (ir:parameter function 0) (ir:parameter function 2)))))
       (ir:ret (value function ir:i1 "running"))))

    (define (numeric-handler operation)
      (let* ((function (instruction-function operation)) (arithmetic? (memq operation '(add subtract)))
             (calculate (ir:block function "calculate")) (done (ir:block function "done"))
             (fallback (ir:block function "fallback")))
        (handler-definition
         function (append (numeric-operands function) (fixnum-check function))
         (ir:cbr (value function ir:i1 "fixnums") calculate fallback)
         (list (ir:block-body calculate
                              (if arithmetic? (fixnum-arithmetic function operation) (fixnum-comparison function operation))
                              (if arithmetic? (ir:cbr (value function ir:i1 "fits") done fallback) (ir:br done)))
               (ir:block-body done
                              (append (single-result function (value function ir:i32 "answer"))
                                      (list (ir:binop (value function ir:i32 "remaining") 'sub (value function ir:i32 "top") (word 2))
                                            (write-register function 's (value function ir:i32 "remaining"))))
                              (ir:ret (boolean #t)))
               (numeric-fallback function)))))

    (define (write-vm-instructions port)
      (for-each (lambda (entry) (ir:write-definition (reference-handler (car entry) (cadr entry)) port))
                '((constant constants) (refer-local local) (refer-free free) (refer-global globals)))
      (for-each (lambda (entry) (ir:write-definition (assignment-handler (car entry) (cadr entry) (caddr entry)) port))
                '((init-local local #f) (set-local local #t) (set-free free #t) (set-global globals #f)))
      (for-each (lambda (definition) (ir:write-definition definition port))
                (list (indirect-handler) (reserve-handler) (argument-handler) (frame-handler)
                      (shift-handler) (test-handler) (object-handler 'box 1) (object-handler 'close 5)))
      (for-each (lambda (entry)
                  (ir:write-definition
                   (cond-expand
                    (snail-rust-numeric (ir:declare (instruction-function (cdr entry))))
                    (else (numeric-handler (cdr entry)))) port))
                binary-numeric-primitives))

    ;; ---- Module and constant data ----

    (define-traced (write-vm-program-as-llvm program port)
      (validate-code-addresses program)
      (let ((constants (program-constant-data program)) (primitives (program-primitive-data program)))
        (display "; Generated Scheme stack operations with the Rust object runtime.\n" port)
        (write-count "program_abi" 3 port)
        (for-each (lambda (entry) (ir:write-definition (ir:declare (cdr entry)) port)) runtime-functions)
        (write-vm-instructions port)
        (write-data constants primitives port)
        (write-count "global_count" (length (vm-program-globals program)) port)
        (write-count "constant_count" (length (vm-program-constants program)) port)
        (write-execution program constants primitives port)))

    (define (validate-code-addresses program)
      (define (check label)
        (if (not (and (exact-integer? label) (<= 0 label 1073741823)))
            (error "VM instruction address exceeds nonnegative fixnum range" label)))
      (check (vm-program-entry program))
      (for-each (lambda (instruction)
                  (check (instruction-label instruction))
                  (let ((destination (instruction-destination instruction)))
                    (if destination (check destination))))
                (vm-program-instructions program)))

    (define (write-count name count port)
      (let* ((function (ir:function (string-append "snail_" name) ir:i32 '()))
             (entry (ir:block function "entry")))
        (ir:write-definition
         (ir:define-function function 'external '()
                             (list (ir:block-body entry '() (ir:ret (word count)))))
         port)))

    (define (program-constant-data program)
      (let loop ((constants (vm-program-constants program)) (index 0) (data '()))
        (if (null? constants) (list->vector (reverse data))
            (loop (cdr constants) (+ index 1) (cons (constant-global (car constants) index) data)))))

    (define (constant-global constant index)
      (let ((name (ir:indexed-name "c" index)) (data (constant-data constant)))
        (case (constant-kind constant)
          ((pair) #f)
          ((vector) (ir:global-array name ir:i32 (map word data) 4))
          (else (ir:global-bytes name (constant-bytes constant))))))

    (define (program-primitive-data program)
      (map (lambda (primitive)
             (cons (car primitive)
                   (ir:global-bytes (ir:indexed-name "p" (car primitive))
                                    (ir:utf8-bytes (symbol->string (cdr primitive))))))
           (vm-program-primitives program)))

    (define (write-data constants primitives port)
      (for-each (lambda (data) (if data (ir:write-definition data port))) (vector->list constants))
      (for-each (lambda (entry) (ir:write-definition (cdr entry) port)) primitives))

    (define (constant-bytes constant)
      (let ((data (constant-data constant)))
        (case (constant-kind constant)
          ((string) (ir:utf8-bytes data))
          ((symbol) (ir:utf8-bytes (symbol->string data)))
          ((integer float character)
           (ir:utf8-bytes (number->string (if (char? data) (char->integer data) data))))
          ((boolean) (list (if data 49 48)))
          ((bytevector) (bytevector-bytes data))
          ((nil unspecified) '())
          (else (error "constant has no byte representation" (constant-kind constant))))))

    (define (bytevector-bytes bytes)
      (let loop ((index 0))
        (if (= index (bytevector-length bytes)) '()
            (cons (bytevector-u8-ref bytes index) (loop (+ index 1))))))

    (define (atom-kind kind)
      (case kind
        ((string) 0) ((symbol) 1) ((integer) 2) ((float) 3) ((character) 4)
        ((boolean) 5) ((nil) 6) ((bytevector) 7) ((unspecified) 8)
        (else (error "unknown constant kind" kind))))

    ;; ---- Program control flow ----

    ;; One generated function owns every Scheme transfer. Calls, returns and
    ;; special procedures jump among these blocks; native recursion is never used.
    ;; Rust prepares objects/arguments, but frame construction, tail shifting and
    ;; restoring the caller are the operations below, visible in emitted LLVM.
    (define (program-blocks function program)
      (list->vector
       (map (lambda (instruction)
              (let ((label (instruction-label instruction)))
                (cons label (ir:block function (ir:indexed-name "b" label)))))
            (vm-program-instructions program))))

    (define (target-block blocks label)
      (if (and (< label (vector-length blocks)) (= (car (vector-ref blocks label)) label))
          (cdr (vector-ref blocks label))
          (let loop ((index 0))
            (cond ((= index (vector-length blocks)) (error "missing VM destination" label))
                  ((= (car (vector-ref blocks index)) label) (cdr (vector-ref blocks index)))
                  (else (loop (+ index 1)))))))

    (define (program-state function) (value function ir:ptr "state"))
    (define (program-call function operation operands result)
      (ir:call result (instruction-function operation)
               (append (list (ir:parameter function 0) (program-state function)) operands)))

    (define (write-execution program constants primitives port)
      (let* ((function (ir:function "snail_program" ir:void (list (cons ir:ptr "vm"))))
             (blocks (program-blocks function program)))
        (ir:write-definition
         (ir:define-function
          function 'external '()
          (append (list (initialization-body function program constants primitives))
                  (map (lambda (instruction) (instruction-body function blocks instruction))
                       (vm-program-instructions program))
                  (application-bodies function) (return-bodies function)
                  (special-application-bodies function)
                  (list (dispatch-body function program blocks)) (exit-bodies function))) port)))

    (define (initialization-body function program constants primitives)
      (let ((vm (ir:parameter function 0)) (ready (value function ir:i1 "initialized")))
        (ir:block-body
         (ir:block function "entry")
         (append (list (ir:call (program-state function) (runtime-function 'state) (list vm)))
                 (register-addresses function (program-state function))
                 (constant-initializers program constants vm)
                 (map (lambda (entry) (primitive-initializer vm entry)) primitives)
                 (list (program-call function 'close
                                     (list (word (vm-program-entry program)) (word 0) (word 0)
                                           (word (vm-program-locals program)) (word 0)) ready)
                       (write-register function 'argc (word 0))))
         (ir:cbr ready (ir:block function "dispatch") (ir:block function "done")))))

    (define (constant-initializers program constants vm)
      (let loop ((remaining (vm-program-constants program)) (index 0))
        (if (null? remaining) '()
            (cons (constant-initializer (car remaining) (vector-ref constants index) index vm)
                  (loop (cdr remaining) (+ index 1))))))

    (define (constant-initializer constant global index vm)
      (let ((data (constant-data constant)))
        (case (constant-kind constant)
          ((pair) (ir:call #f (runtime-function 'pair)
                           (list vm (word index) (word (car data)) (word (cadr data)))))
          ((vector) (ir:call #f (runtime-function 'vector)
                             (list vm (word index) global (word (length data)))))
          (else (ir:call #f (runtime-function 'atom)
                         (list vm (word index) (word (atom-kind (constant-kind constant)))
                               global (word (ir:global-length global))))))))

    (define (primitive-initializer vm entry)
      (ir:call #f (runtime-function 'primitive)
               (list vm (word (car entry)) (cdr entry) (word (ir:global-length (cdr entry))))))

    (define (instruction-body function blocks instruction)
      (let* ((label (instruction-label instruction)) (block (target-block blocks label))
             (operation (instruction-operation instruction)) (operands (instruction-operands instruction))
             (result (value function (if (eq? operation 'test) ir:i32 ir:i1) (ir:indexed-name "result" label))))
        (case operation
          ((apply) (ir:block-body block (list (write-register function 'argc (word (car operands)))) (ir:br (ir:block function "dispatch"))))
          ((return) (ir:block-body block '() (ir:br (ir:block function "dispatch"))))
          ((test) (ir:block-body block (list (program-call function operation '() result))
                                 (ir:switch result (ir:block function "done")
                                            (list (cons (word 0) (target-block blocks (cadr operands)))
                                                  (cons (word 1) (target-block blocks (car operands)))))))
          (else (ir:block-body block (list (program-call function operation (map word operands) result))
                               (ir:cbr result (target-block blocks (instruction-next instruction)) (ir:block function "done")))))))

    ;; The three-word return record is already beneath the arguments. Ordinary
    ;; apply changes registers only; prepare may pack a rest list or call Rust.
    ;; Every source remains published before a potentially collecting service.
    (define (application-bodies function)
      (let ((apply (ir:block function "apply")) (prepare (ir:block function "prepare")))
        (append
         (list (ir:block-body apply (single-check function)
                              (ir:cbr (value function ir:i1 "single") prepare (ir:block function "value_error")))
               (ir:block-body prepare
                              (list (read-register function 's "apply_s") (read-register function 'argc "apply_argc")
                                    (read-register function 'a "apply_procedure")
                                    (ir:binop (value function ir:i32 "apply_f") 'sub
                                              (value function ir:i32 "apply_s") (value function ir:i32 "apply_argc"))
                                    (write-register function 'f (value function ir:i32 "apply_f"))
                                    (write-register function 'c (value function ir:i32 "apply_procedure"))
                                    (ir:call (value function ir:i32 "action") (runtime-function 'prepare)
                                             (list (ir:parameter function 0) (value function ir:i32 "apply_argc"))))
                              (ir:switch (value function ir:i32 "action") (ir:block function "done")
                                         (map (lambda (entry) (cons (word (car entry)) (ir:block function (cdr entry))))
                                              '((0 . "scheme") (1 . "return") (2 . "reapply")
                                                (3 . "produce") (4 . "capture") (5 . "restore"))))))
         (cons (ir:block-body (ir:block function "reapply") '() (ir:br (ir:block function "dispatch")))
               (scheme-entry-bodies function)))))

    (define (scheme-entry-bodies function)
      (let ((scheme (ir:block function "scheme")) (pad (ir:block function "pad"))
            (write (ir:block function "pad_write")) (ready (ir:block function "scheme_ready")))
        (list
         (ir:block-body scheme
                        (list (read-register function 'f "scheme_f") (read-register function 'locals "scheme_locals")
                              (read-register function 's "scheme_s")
                              (ir:binop (value function ir:i32 "scheme_top") 'add
                                        (value function ir:i32 "scheme_f") (value function ir:i32 "scheme_locals"))
                              (program-call function 'reserve (list (value function ir:i32 "scheme_top")) (value function ir:i1 "scheme_reserved")))
                        (ir:cbr (value function ir:i1 "scheme_reserved") pad (ir:block function "done")))
         (ir:block-body pad
                        (list (ir:phi (value function ir:i32 "pad_depth")
                                      (list (cons (value function ir:i32 "scheme_s") scheme)
                                            (cons (value function ir:i32 "pad_next") write)))
                              (ir:icmp (value function ir:i1 "pad_more") 'ult
                                       (value function ir:i32 "pad_depth") (value function ir:i32 "scheme_top")))
                        (ir:cbr (value function ir:i1 "pad_more") write ready))
         (ir:block-body write
                        (append (list (ir:binop (value function ir:i32 "pad_next") 'add (value function ir:i32 "pad_depth") (word 1))
                                      (read-register function 'end "pad_end"))
                                (stack-address function (value function ir:ptr "pad_slot") (value function ir:ptr "pad_end") (value function ir:i32 "pad_next"))
                                (list (ir:store (word 44) (value function ir:ptr "pad_slot")))) (ir:br pad))
         (ir:block-body ready
                        (append (list (write-register function 's (value function ir:i32 "scheme_top"))
                                      (read-register function 'entry "scheme_entry"))
                                (single-result function (word 36))) (ir:br (ir:block function "dispatch"))))))

    ;; Saved pc -1 denotes STOP and -2 denotes the values receiver. Arithmetic
    ;; shift restores those signed sentinel bits as well as nonnegative labels.
    (define (return-bodies function)
      (let ((return (ir:block function "return")) (resume (ir:block function "resume")))
        (list
         (ir:block-body return (return-loads function) (ir:br resume))
         (ir:block-body resume
                        (list (write-register function 'c (value function ir:i32 "return_c"))
                              (write-register function 'f (value function ir:i32 "return_f"))
                              (write-register function 's (value function ir:i32 "return_s"))
                              (write-register function 'frames (value function ir:i32 "return_frames")))
                        (ir:br (ir:block function "dispatch"))))))

    (define (return-loads function)
      (append
       (list (read-register function 'f "return_base") (read-register function 'end "return_end")
             (read-register function 'frames "return_old_frames")
             (ir:binop (value function ir:i32 "return_closure_depth") 'sub (value function ir:i32 "return_base") (word 2))
             (ir:binop (value function ir:i32 "return_frame_depth") 'sub (value function ir:i32 "return_base") (word 1))
             (ir:binop (value function ir:i32 "return_s") 'sub (value function ir:i32 "return_base") (word 3)))
       (stack-address function (value function ir:ptr "return_closure_slot") (value function ir:ptr "return_end") (value function ir:i32 "return_closure_depth"))
       (stack-address function (value function ir:ptr "return_frame_slot") (value function ir:ptr "return_end") (value function ir:i32 "return_frame_depth"))
       (stack-address function (value function ir:ptr "return_resume_slot") (value function ir:ptr "return_end") (value function ir:i32 "return_base"))
       (list (ir:load (value function ir:i32 "return_c") (value function ir:ptr "return_closure_slot"))
             (ir:load (value function ir:i32 "return_tagged_f") (value function ir:ptr "return_frame_slot"))
             (ir:load (value function ir:i32 "return_tagged_pc") (value function ir:ptr "return_resume_slot"))
             (ir:binop (value function ir:i32 "return_f") 'lshr (value function ir:i32 "return_tagged_f") (word 1))
             (ir:binop (value function ir:i32 "return_pc") 'ashr (value function ir:i32 "return_tagged_pc") (word 1))
             (ir:binop (value function ir:i32 "return_frames") 'sub (value function ir:i32 "return_old_frames") (word 1)))))

    (define (activation-slot function prefix index)
      (let ((frame (value function ir:i32 (string-append prefix "_f")))
            (end (value function ir:ptr (string-append prefix "_end")))
            (depth (value function ir:i32 (string-append prefix "_depth")))
            (slot (value function ir:ptr (string-append prefix "_slot"))))
        (append (list (read-register function 'f (ir:value-name frame)) (read-register function 'end (ir:value-name end))
                      (ir:binop depth 'add frame (word (+ index 1))))
                (stack-address function slot end depth))))

    (define (running-check function prefix leading)
      (let ((stopped (value function ir:i32 (string-append prefix "_stopped")))
            (running (value function ir:i1 (string-append prefix "_running"))))
        (append leading (list (read-register function 'stopped (ir:value-name stopped))
                              (ir:icmp running 'eq stopped (word 0))))))

    (define (special-application-bodies function)
      (append (producer-bodies function) (capture-bodies function)
              (list (ir:block-body (ir:block function "consume")
                                   (running-check function "consume"
                                                  (list (ir:call #f (runtime-function 'receive) (list (ir:parameter function 0)))))
                                   (ir:cbr (value function ir:i1 "consume_running") (ir:block function "dispatch") (ir:block function "done")))
                    (ir:block-body (ir:block function "restore")
                                   (running-check function "restore"
                                                  (list (read-register function 'argc "restore_argc")
                                                        (ir:call #f (runtime-function 'restore)
                                                                 (list (ir:parameter function 0) (value function ir:i32 "restore_argc")))))
                                   (ir:cbr (value function ir:i1 "restore_running") (ir:block function "return") (ir:block function "done"))))))

    ;; Keep cwv's two arguments below the producer's return record. A snapshot
    ;; therefore retains the consumer without any separate Rust continuation frame.
    (define (producer-bodies function)
      (list
       (ir:block-body (ir:block function "produce")
                      (append (activation-slot function "producer" 0)
                              (list (ir:load (value function ir:i32 "producer_value") (value function ir:ptr "producer_slot")))
                              (single-result function (value function ir:i32 "producer_value"))
                              (list (program-call function 'frame (list (word consume-code)) (value function ir:i1 "producer_frame"))
                                    (write-register function 'argc (word 0))))
                      (ir:cbr (value function ir:i1 "producer_frame") (ir:block function "dispatch") (ir:block function "done")))))

    ;; Capture excludes call/cc's argument but includes its return record.
    ;; The procedure stays rooted in that argument until capture finishes.
    (define (capture-bodies function)
      (list
       (ir:block-body (ir:block function "capture")
                      (running-check function "capture"
                                     (append (activation-slot function "capture_procedure" 0)
                                             (list (ir:load (value function ir:i32 "capture_procedure_value") (value function ir:ptr "capture_procedure_slot"))
                                                   (ir:call #f (runtime-function 'capture) (list (ir:parameter function 0))))))
                      (ir:cbr (value function ir:i1 "capture_running") (ir:block function "captured") (ir:block function "done")))
       (ir:block-body (ir:block function "captured")
                      (append (activation-slot function "captured_argument" 0)
                              (list (read-register function 'a "captured_continuation")
                                    (ir:store (value function ir:i32 "captured_continuation") (value function ir:ptr "captured_argument_slot"))
                                    (write-register function 'argc (word 1)))
                              (single-result function (value function ir:i32 "capture_procedure_value")))
                      (ir:br (ir:block function "dispatch")))))

    ;; All dynamic transitions pass this one loop header, including the internal
    ;; apply/return protocol. Its reducible CFG maps directly to structured WASM.
    (define (dispatch-body function program blocks)
      (ir:block-body
       (ir:block function "dispatch")
       (list (ir:phi (value function ir:i32 "pc") (dispatch-inputs function program blocks)))
       (ir:switch (value function ir:i32 "pc") (ir:block function "invalid")
                  (append (list (cons (word stop-code) (ir:block function "done"))
                                (cons (word consume-code) (ir:block function "consume"))
                                (cons (word apply-code) (ir:block function "apply"))
                                (cons (word return-code) (ir:block function "return")))
                          (map (lambda (label) (cons (word label) (target-block blocks label))) (dispatch-targets program))))))

    (define (dispatch-inputs function program blocks)
      (append (map (lambda (name) (cons (word apply-code) (ir:block function name)))
                   '("entry" "reapply" "produce" "captured" "consume"))
              (list (cons (value function ir:i32 "scheme_entry") (ir:block function "scheme_ready"))
                    (cons (value function ir:i32 "return_pc") (ir:block function "resume")))
              (let loop ((instructions (vm-program-instructions program)))
                (if (null? instructions) '()
                    (let ((instruction (car instructions)))
                      (if (memq (instruction-operation instruction) '(apply return))
                          (cons (cons (word (if (eq? (instruction-operation instruction) 'apply) apply-code return-code))
                                      (target-block blocks (instruction-label instruction)))
                                (loop (cdr instructions)))
                          (loop (cdr instructions))))))))

    (define (exit-bodies function)
      (let ((vm (ir:parameter function 0)) (done (ir:block function "done")))
        (list (ir:block-body (ir:block function "invalid")
                             (list (ir:call #f (runtime-function 'invalid) (list vm (value function ir:i32 "pc")))) (ir:br done))
              (ir:block-body (ir:block function "value_error") (list (ir:call #f (runtime-function 'value-error) (list vm))) (ir:br done))
              (ir:block-body done (list (ir:call #f (runtime-function 'halt) (list vm))) (ir:ret #f)))))

    ;; Only procedure entries and explicit frame resume addresses need dispatch.
    (define (dispatch-targets program)
      (let* ((instructions (vm-program-instructions program)) (seen (make-vector (length instructions) #f)))
        (remember-destination! seen '() (vm-program-entry program))
        (let loop ((instructions instructions) (targets (list (vm-program-entry program))))
          (if (null? instructions) (reverse targets)
              (let ((target (instruction-destination (car instructions))))
                (loop (cdr instructions) (if (remember-destination! seen targets target) (cons target targets) targets)))))))

    (define (remember-destination! seen targets target)
      (and target
           (if (< target (vector-length seen))
               (and (not (vector-ref seen target)) (begin (vector-set! seen target #t) #t))
               (not (memv target targets)))))

    (define (instruction-destination instruction)
      (case (instruction-operation instruction)
        ((close frame) (car (instruction-operands instruction)))
        (else #f))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-llvm)
    (import (snail-scheme test-utils))
    (begin
      (define (shared-destinations scale)
        (make-vm-program 0 0
                         (list (make-instruction 0 'return '() #f #f)
                               (make-instruction scale 'frame (list (* 4 scale)) 0 #f)
                               (make-instruction (* 2 scale) 'frame (list (* 4 scale)) 0 #f)
                               (make-instruction (* 3 scale) 'close (list (* 4 scale) 0 0 0 0) 0 #f)
                               (make-instruction (* 4 scale) 'return '() #f #f)
                               (make-instruction (* 5 scale) 'close '(0 0 0 0 0) 0 #f)
                               (make-instruction (* 6 scale) 'apply '(0) #f #f))
                         '() '() '()))
      (define (test-dispatch-destinations)
        (for-each (lambda (scale) (expect (dispatch-targets (shared-destinations scale)) (list 0 (* 4 scale)))) '(1 1000000)))
      (define (test-llvm) (run-test test-dispatch-destinations))))))
