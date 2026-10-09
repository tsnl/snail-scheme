;; Specialize stack instructions into immutable LLVM functions and blocks.
;; llvmlite owns LLVM syntax; this module owns Scheme's VM and runtime protocol.
(define-library (snail-scheme llvm)
  (export write-llvm-program)
  (import (scheme base) (scheme cxr) (scheme write) (snail-scheme vm)
          (prefix (snail-scheme llvmlite) ir:))
  (begin

    ;; ---- Runtime and instruction signatures ----

    (define (word number) (ir:integer ir:i32 number))
    (define (tag number) (ir:inttoptr (ir:integer ir:i64 number)))

    (define (foreign name result types)
      (let loop ((types types) (index 0) (parameters '()))
        (if (null? types) (ir:function name result (reverse parameters))
            (loop (cdr types) (+ index 1)
                  (cons (cons (car types) (ir:indexed-name "arg" index)) parameters)))))

    (define runtime-functions
      (list (cons 'enter (foreign "snail_rt_enter" ir:i32 (list ir:ptr)))
            (cons 'slot (foreign "snail_rt_slot" ir:ptr (list ir:ptr ir:i32 ir:i32)))
            (cons 'capture (foreign "snail_rt_capture_slot" ir:ptr (list ir:ptr ir:i32 ir:i32)))
            (cons 'single (foreign "snail_rt_single" ir:ptr (list ir:ptr)))
            (cons 'result (foreign "snail_rt_result" ir:ptr (list ir:ptr)))
            (cons 'push (foreign "snail_rt_push" ir:ptr (list ir:ptr)))
            (cons 'uninitialized (foreign "snail_rt_uninitialized" ir:void (list ir:ptr)))
            (cons 'close (foreign "snail_rt_close" ir:void
                                  (list ir:ptr ir:i32 ir:i32 ir:i32 ir:i32 ir:i32)))
            (cons 'call (foreign "snail_rt_call" ir:i32 (list ir:ptr ir:i32 ir:i32 ir:i32)))
            (cons 'return (foreign "snail_rt_return" ir:i32 (list ir:ptr)))
            (cons 'halt (foreign "snail_halt" ir:void (list ir:ptr)))
            (cons 'invalid (foreign "snail_invalid_pc" ir:void (list ir:ptr ir:i32)))
            (cons 'atom (foreign "snail_const_atom" ir:void (list ir:ptr ir:i32 ir:i32 ir:ptr ir:i32)))
            (cons 'pair (foreign "snail_const_pair" ir:void (list ir:ptr ir:i32 ir:i32 ir:i32)))
            (cons 'vector (foreign "snail_const_vector" ir:void (list ir:ptr ir:i32 ir:ptr ir:i32)))
            (cons 'primitive (foreign "snail_global_primitive" ir:void
                                      (list ir:ptr ir:i32 ir:ptr ir:i32)))))

    (define (runtime-function name) (cdr (assq name runtime-functions)))

    (define (vm-function name result arguments)
      (ir:function (string-append "snail_vm_" name) result
                   (cons (cons ir:ptr "vm") (map (lambda (name) (cons ir:i32 name)) arguments))))

    (define vm-functions
      (list (cons 'constant (vm-function "constant" ir:void '("index")))
            (cons 'refer-local (vm-function "refer_local" ir:void '("index")))
            (cons 'refer-free (vm-function "refer_free" ir:void '("index")))
            (cons 'refer-global (vm-function "refer_global" ir:void '("index")))
            (cons 'set-local (vm-function "set_local" ir:void '("index")))
            (cons 'set-free (vm-function "set_free" ir:void '("index")))
            (cons 'set-global (vm-function "set_global" ir:void '("index")))
            (cons 'capture-local (vm-function "capture_local" ir:void '("index")))
            (cons 'capture-free (vm-function "capture_free" ir:void '("index")))
            (cons 'push (vm-function "push" ir:void '()))
            (cons 'test (vm-function "test" ir:i32 '()))
            (cons 'close (vm-function "close" ir:void '("code" "required" "rest" "locals" "captures")))
            (cons 'call (vm-function "call" ir:i32 '("argc" "resume" "tail")))
            (cons 'return (vm-function "return" ir:i32 '()))))

    (define (instruction-function operation)
      (let ((entry (assq operation vm-functions)))
        (if entry (cdr entry) (error "unknown VM instruction" operation))))

    ;; ---- Inline instruction bodies ----

    ;; Each entry remains an automatic safepoint. After it, slot operations are
    ;; GC-free. Load a source BEFORE a call can resize its storage, then publish
    ;; the word before another instruction enters. Tagged ptr bits are never
    ;; dereferenced as Scheme objects. These tags agree with runtime/object.rs.

    (define false-value (tag 14))
    (define unspecified-value (tag 38))
    (define uninitialized-value (tag 46))

    (define (handler-entry function body done)
      (let* ((entry (ir:block function "entry"))
             (ready (ir:local function ir:i32 "ready"))
             (running (ir:local function ir:i1 "running")))
        (ir:block-body entry
                       (list (ir:call ready (runtime-function 'enter) (list (ir:parameter function 0)))
                             (ir:icmp running 'ne ready (word 0)))
                       (ir:cbr running body done))))

    (define (handler-definition function body done instructions)
      (let ((result (if (ir:type=? (ir:function-result function) ir:void) #f (word 0))))
        (ir:define-function function 'internal '(alwaysinline)
                            (append (list (handler-entry function body done)) instructions
                                    (list (ir:block-body done '() (ir:ret result)))))))

    ;; A checked service and its null test share one block. The optional leading
    ;; loads explicitly preserve source values before services can grow storage.
    ;; These services must not collect; the handler entry already ran its safepoint.
    (define (checked-pointer-block block leading call next done)
      (let* ((value (ir:instruction-result call))
             (missing (ir:local (ir:block-owner block) ir:i1
                                (string-append (ir:value-name value) "_missing"))))
        (ir:block-body block (append leading (list call (ir:icmp missing 'eq value ir:null-pointer)))
                       (ir:cbr missing done next))))

    (define (reference-handler operation kind)
      (let* ((function (instruction-function operation)) (vm (ir:parameter function 0))
             (body (ir:block function "body")) (source-ok (ir:block function "source_ok"))
             (unbound (ir:block function "unbound")) (initialized (ir:block function "initialized"))
             (destination-ok (ir:block function "destination_ok")) (done (ir:block function "done"))
             (source (ir:local function ir:ptr "source")) (value (ir:local function ir:ptr "value"))
             (missing (ir:local function ir:i1 "uninitialized"))
             (destination (ir:local function ir:ptr "destination")))
        (handler-definition
         function body done
         (list (checked-pointer-block body '()
                                      (ir:call source (runtime-function 'slot)
                                               (list vm (ir:parameter function 1) (word kind)))
                                      source-ok done)
               (ir:block-body source-ok (list (ir:load value source)
                                              (ir:icmp missing 'eq value uninitialized-value))
                              (ir:cbr missing unbound initialized))
               (ir:block-body unbound (list (ir:call #f (runtime-function 'uninitialized) (list vm)))
                              (ir:br done))
               (checked-pointer-block initialized '()
                                      (ir:call destination (runtime-function 'result) (list vm))
                                      destination-ok done)
               (ir:block-body destination-ok (list (ir:store value destination)) (ir:br done))))))

    (define (assignment-handler operation kind)
      (let* ((function (instruction-function operation)) (vm (ir:parameter function 0))
             (body (ir:block function "body")) (source-ok (ir:block function "source_ok"))
             (destination-ok (ir:block function "destination_ok")) (done (ir:block function "done"))
             (source (ir:local function ir:ptr "source")) (value (ir:local function ir:ptr "value"))
             (destination (ir:local function ir:ptr "destination")))
        (handler-definition
         function body done
         (append
          (list (checked-pointer-block body '() (ir:call source (runtime-function 'single) (list vm))
                                       source-ok done)
                (checked-pointer-block source-ok (list (ir:load value source))
                                       (ir:call destination (runtime-function 'slot)
                                                (list vm (ir:parameter function 1) (word kind)))
                                       destination-ok done))
          (unspecified-result-blocks function destination-ok
                                     (list (ir:store value destination)) done)))))

    (define (unspecified-result-blocks function start leading done)
      (let ((result (ir:local function ir:ptr "result")) (ok (ir:block function "result_ok")))
        (list (checked-pointer-block start leading
                                     (ir:call result (runtime-function 'result)
                                              (list (ir:parameter function 0))) ok done)
              (ir:block-body ok (list (ir:store unspecified-value result)) (ir:br done)))))

    (define (push-handler operation free)
      (let* ((function (instruction-function operation)) (vm (ir:parameter function 0))
             (body (ir:block function "body")) (source-ok (ir:block function "source_ok"))
             (done (ir:block function "done")) (source (ir:local function ir:ptr "source"))
             (service (runtime-function (if free 'capture 'single)))
             (args (if free (list vm (ir:parameter function 1) (word free)) (list vm))))
        (handler-definition function body done
                            (cons (checked-pointer-block body '() (ir:call source service args)
                                                         source-ok done)
                                  (push-value-blocks function source source-ok done)))))

    (define (push-value-blocks function source start done)
      (let ((value (ir:local function ir:ptr "value"))
            (destination (ir:local function ir:ptr "destination"))
            (ok (ir:block function "destination_ok")))
        (list (checked-pointer-block start (list (ir:load value source))
                                     (ir:call destination (runtime-function 'push)
                                              (list (ir:parameter function 0))) ok done)
              (ir:block-body ok (list (ir:store value destination)) (ir:br done)))))

    (define (test-handler)
      (let* ((function (instruction-function 'test)) (body (ir:block function "body"))
             (source-ok (ir:block function "source_ok")) (done (ir:block function "done"))
             (source (ir:local function ir:ptr "source")) (value (ir:local function ir:ptr "value"))
             (truth (ir:local function ir:i1 "truth")) (answer (ir:local function ir:i32 "answer")))
        (handler-definition
         function body done
         (list (checked-pointer-block body '() (ir:call source (runtime-function 'single)
                                                        (list (ir:parameter function 0))) source-ok done)
               (ir:block-body source-ok (list (ir:load value source)
                                              (ir:icmp truth 'ne value false-value)
                                              (ir:zext answer truth)) (ir:ret answer))))))

    ;; Rust owns captures and frames. Calls return labels to generated code.
    (define (transfer-handler operation)
      (let* ((function (instruction-function operation)) (body (ir:block function "body"))
             (done (ir:block function "done"))
             (result (if (eq? operation 'close) #f (ir:local function ir:i32 "next")))
             (count (case operation ((close) 6) ((call) 4) (else 1)))
             (call (ir:call result (runtime-function operation) (function-arguments function count))))
        (ir:define-function function 'internal '(alwaysinline)
                            (list (handler-entry function body done)
                                  (ir:block-body body (list call)
                                                 (if result (ir:ret result) (ir:br done)))
                                  (ir:block-body done '() (ir:ret (if result (word 4294967295) #f)))))))

    (define (function-arguments function count)
      (let loop ((index 0))
        (if (= index count) '() (cons (ir:parameter function index) (loop (+ index 1))))))

    (define (write-vm-instructions port)
      (for-each (lambda (entry)
                  (ir:write-definition (reference-handler (car entry) (cadr entry)) port))
                '((constant 3) (refer-local 0) (refer-free 1) (refer-global 2)))
      (for-each (lambda (entry)
                  (ir:write-definition (assignment-handler (car entry) (cadr entry)) port))
                '((set-local 0) (set-free 1) (set-global 2)))
      (for-each (lambda (entry) (ir:write-definition (push-handler (car entry) (cadr entry)) port))
                '((capture-local 0) (capture-free 1) (push #f)))
      (ir:write-definition (test-handler) port)
      (for-each (lambda (operation) (ir:write-definition (transfer-handler operation) port))
                '(close call return)))

    ;; ---- Module and constant data ----

    (define (write-llvm-program program port)
      (let ((constants (program-constant-data program)) (primitives (program-primitive-data program)))
        (display "; Generated by Snail-Scheme. VM state and values belong to Rust.\n" port)
        (write-count "program_abi" 1 port)
        (for-each (lambda (entry) (ir:write-definition (ir:declare (cdr entry)) port)) runtime-functions)
        (write-vm-instructions port)
        (write-data constants primitives port)
        (write-count "global_count" (length (vm-program-globals program)) port)
        (write-count "constant_count" (length (vm-program-constants program)) port)
        (write-execution program constants primitives port)))

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

    ;; Create references before bodies. Dense lowerer labels index this immutable
    ;; vector directly; sparse hand-built programs fall back to a linear lookup.

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

    (define (write-execution program constants primitives port)
      (let* ((function (ir:function "snail_program" ir:void (list (cons ir:ptr "vm"))))
             (entry (ir:block function "entry")) (dispatch (ir:block function "dispatch"))
             (invalid (ir:block function "invalid")) (done (ir:block function "done"))
             (start (ir:local function ir:i32 "start")) (pc (ir:local function ir:i32 "pc"))
             (blocks (program-blocks function program))
             (bodies (map (lambda (instruction) (instruction-body function blocks dispatch instruction))
                          (vm-program-instructions program))))
        (ir:write-definition
         (ir:define-function
          function 'external '()
          (append (list (initialization-body program constants primitives entry dispatch start)) bodies
                  (list (dispatch-body program blocks dispatch invalid done pc
                                       (cons (cons start entry) (destination-inputs program bodies))))
                  (exit-bodies function invalid done pc))) port)))

    (define (initialization-body program constants primitives entry dispatch start)
      (let* ((function (ir:block-owner entry)) (vm (ir:parameter function 0))
             (close (ir:call #f (instruction-function 'close)
                             (list vm (word (vm-program-entry program)) (word 0) (word 0)
                                   (word (vm-program-locals program)) (word 0))))
             (call (ir:call start (instruction-function 'call)
                            (list vm (word 0) (word 4294967295) (word 1)))))
        (ir:block-body entry
                       (append (constant-initializers program constants vm)
                               (map (lambda (entry) (primitive-initializer vm entry)) primitives)
                               (list close call)) (ir:br dispatch))))

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

    (define (instruction-body function blocks dispatch instruction)
      (let* ((label (instruction-label instruction)) (block (target-block blocks label))
             (operation (instruction-operation instruction))
             (result (if (memq operation '(call return))
                         (ir:local function ir:i32 (ir:indexed-name "next" label)) #f)))
        (if (eq? operation 'test) (test-body function blocks block instruction)
            (ir:block-body block
                           (list (ir:call result (instruction-function operation)
                                          (cons (ir:parameter function 0)
                                                (map word (instruction-operands instruction)))))
                           (ir:br (if result dispatch
                                      (target-block blocks (instruction-next instruction))))))))

    (define (test-body function blocks block instruction)
      (let* ((label (instruction-label instruction)) (arms (instruction-operands instruction))
             (truth (ir:local function ir:i32 (ir:indexed-name "truth" label)))
             (test (ir:local function ir:i1 (ir:indexed-name "test" label))))
        (ir:block-body block
                       (list (ir:call truth (instruction-function 'test)
                                      (list (ir:parameter function 0)))
                             (ir:icmp test 'ne truth (word 0)))
                       (ir:cbr test (target-block blocks (car arms))
                               (target-block blocks (cadr arms))))))

    (define (destination-inputs program bodies)
      (let loop ((instructions (vm-program-instructions program)) (bodies bodies) (incoming '()))
        (if (null? instructions) (reverse incoming)
            (loop (cdr instructions) (cdr bodies)
                  (if (memq (instruction-operation (car instructions)) '(call return))
                      (cons (cons (ir:instruction-result (car (ir:body-instructions (car bodies))))
                                  (ir:body-block (car bodies))) incoming) incoming)))))

    (define (dispatch-body program blocks dispatch invalid done pc incoming)
      (ir:block-body dispatch (list (ir:phi pc incoming))
                     (ir:switch pc invalid
                                (cons (cons (word 4294967295) done)
                                      (map (lambda (label)
                                             (cons (word label) (target-block blocks label)))
                                           (dispatch-targets program))))))

    (define (exit-bodies function invalid done pc)
      (let ((vm (ir:parameter function 0)))
        (list (ir:block-body invalid
                             (list (ir:call #f (runtime-function 'invalid) (list vm pc))) (ir:br done))
              (ir:block-body done (list (ir:call #f (runtime-function 'halt) (list vm))) (ir:ret #f)))))

    ;; Only procedure entries and non-tail return addresses need dynamic lookup.
    ;; A return address needs a case even when no static branch targets it.
    ;; Lowering produces dense labels. A private bitmap keeps their discovery
    ;; linear; sparse hand-built programs use the existing list membership test.
    ;; The table is fresh for every emission, and first-occurrence order is kept.
    (define (dispatch-targets program)
      (let* ((instructions (vm-program-instructions program))
             (seen (make-vector (length instructions) #f)))
        (remember-destination! seen '() (vm-program-entry program))
        (let loop ((instructions instructions) (targets (list (vm-program-entry program))))
          (if (null? instructions) (reverse targets)
              (let ((target (instruction-destination (car instructions))))
                (loop (cdr instructions)
                      (if (remember-destination! seen targets target)
                          (cons target targets) targets)))))))

    (define (remember-destination! seen targets target)
      (and target
           (if (< target (vector-length seen))
               (and (not (vector-ref seen target))
                    (begin (vector-set! seen target #t) #t))
               (not (memv target targets)))))

    (define (instruction-destination instruction)
      (let ((args (instruction-operands instruction)))
        (case (instruction-operation instruction)
          ((close) (car args))
          ((call) (if (= (caddr args) 0) (cadr args) #f))
          (else #f)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-llvm)
    (import (snail-scheme test-utils))
    (begin
      ;; Two calls share a continuation, closures repeat both destinations, and
      ;; the tail call's unused resume operand must not create a switch case.
      (define (shared-destinations scale)
        (make-vm-program 0 0
                         (list (make-instruction 0 'return '() #f #f)
                               (make-instruction scale 'call (list 0 (* 4 scale) 0) #f #f)
                               (make-instruction (* 2 scale) 'call (list 0 (* 4 scale) 0) #f #f)
                               (make-instruction (* 3 scale) 'close (list (* 4 scale) 0 0 0 0) 0 #f)
                               (make-instruction (* 4 scale) 'return '() #f #f)
                               (make-instruction (* 5 scale) 'close '(0 0 0 0 0) 0 #f)
                               (make-instruction (* 6 scale) 'call (list 0 (* 2 scale) 1) #f #f))
                         '() '() '()))

      (define (llvm-lines program)
        (let ((output (open-output-string)))
          (write-llvm-program program output)
          (let ((input (open-input-string (get-output-string output))))
            (let loop ((lines '()))
              (let ((line (read-line input)))
                (if (eof-object? line) (reverse lines) (loop (cons line lines))))))))

      (define (switch-cases lines)
        (cond ((null? lines) '())
              ((and (>= (string-length (car lines)) 8)
                    (string=? (substring (car lines) 0 8) "    i32 "))
               (cons (car lines) (switch-cases (cdr lines))))
              (else (switch-cases (cdr lines)))))

      (define (test-dispatch-destinations)
        (for-each
         (lambda (scale)
           (let* ((program (shared-destinations scale))
                  (lines (llvm-lines program)) (target (number->string (* 4 scale))))
             (expect (switch-cases lines)
                     (list "    i32 4294967295, label %done"
                           "    i32 0, label %b0"
                           (string-append "    i32 " target ", label %b" target)))
             (expect (llvm-lines program) lines)))
         '(1 1000000))
        (expect (if (member (string-append "  %pc = phi i32 [ %start, %entry ], "
                                           "[ %next0, %b0 ], [ %next1, %b1 ], [ %next2, %b2 ], "
                                           "[ %next4, %b4 ], [ %next6, %b6 ]")
                            (llvm-lines (shared-destinations 1))) #t #f)
                #t))

      (define (test-llvm)
        (run-test test-dispatch-destinations))
      ))))
