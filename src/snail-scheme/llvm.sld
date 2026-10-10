;; Emit structured MIR through llvmlite. Scheme object and stack semantics live
;; in machine.sld; this module only owns module data and the bounded dispatcher.
(define-library (snail-scheme llvm)
  (export write-mir-library-as-llvm)
  (import (scheme base) (scheme cxr) (scheme write) (snail-scheme trace)
          (prefix (snail-scheme mir) mir:) (snail-scheme mir-llvm)
          (prefix (snail-scheme library) library:)
          (prefix (snail-scheme llvmlite) ir:))
  (begin

    ;; ---- Module interface ----

    (define (word number) (ir:integer ir:i32 number))
    (define (value function type name) (ir:local function type name))
    (define (foreign name result types)
      (ir:function name result
                   (map (lambda (type index) (cons type (ir:indexed-name "arg" index)))
                        types (indices (length types)))))
    (define (indices count)
      (let loop ((index 0))
        (if (= index count) '() (cons index (loop (+ index 1))))))
    (define runtime-functions
      (list (cons 'state (foreign "snail_rt_state" ir:ptr (list ir:ptr)))
            (cons 'close (foreign "snail_rt_close" ir:void (list ir:ptr ir:i32 ir:i32 ir:i32 ir:i32 ir:i32)))
            (cons 'halt (foreign "snail_halt" ir:void (list ir:ptr)))
            (cons 'invalid (foreign "snail_invalid_pc" ir:void (list ir:ptr ir:i32)))
            (cons 'atom (foreign "snail_const_atom" ir:void (list ir:ptr ir:i32 ir:i32 ir:ptr ir:i32)))
            (cons 'pair (foreign "snail_const_pair" ir:void (list ir:ptr ir:i32 ir:i32 ir:i32)))
            (cons 'vector (foreign "snail_const_vector" ir:void (list ir:ptr ir:i32 ir:ptr ir:i32)))
            (cons 'primitive (foreign "snail_global_primitive" ir:void (list ir:ptr ir:i32 ir:ptr ir:i32)))))
    (define (runtime-function name) (cdr (assq name runtime-functions)))

    (define-traced (write-mir-library-as-llvm root port)
      (write-body-as-llvm (library->body root) port))

    ;; Libraries retain their own code/data until this final executable boundary.
    ;; Elaboration already assigned shared constant/global slots and ordered entries.
    (define (library->body root)
      (let ((bodies (map library:library-body (library:library-dependency-order root))))
        (mir:make-body (mir:body-entry (car bodies)) (apply + (map mir:body-locals bodies))
                       (apply append (map mir:body-definitions bodies))
                       (apply append (map mir:body-constants bodies))
                       (apply append (map mir:body-globals bodies))
                       (apply append (map mir:body-primitives bodies)))))

    (define (write-body-as-llvm body port)
      (let ((constants (body-constant-data body)) (primitives (body-primitive-data body)))
        (display "; Structured MIR with explicit Rust ABI calls.\n" port)
        (write-count "program_abi" 3 port)
        (write-declarations body port)
        (for-each (lambda (metadata) (ir:write-definition metadata port)) memory-metadata)
        (write-data constants primitives port)
        (write-count "global_count" (length (mir:body-globals body)) port)
        (write-count "constant_count" (length (mir:body-constants body)) port)
        (write-execution body constants primitives port)))

    (define (write-declarations body port)
      (let ((seen '()))
        (for-each (lambda (function)
                    (if (not (member (ir:function-name function) seen))
                        (begin (set! seen (cons (ir:function-name function) seen))
                               (ir:write-definition (ir:declare function) port))))
                  (append (map cdr runtime-functions)
                          (map foreign-function (mir:body-foreign-descriptors body))))))

    ;; ---- Constants and globals ----

    (define (write-count name count port)
      (let* ((function (ir:function (string-append "snail_" name) ir:i32 '()))
             (entry (ir:block function "entry")))
        (ir:write-definition
         (ir:define-function function 'external '()
                             (list (ir:block-body entry '() (ir:ret (word count)))))
         port)))

    (define (body-constant-data body)
      (let loop ((constants (mir:body-constants body)) (index 0) (data '()))
        (if (null? constants) (list->vector (reverse data))
            (loop (cdr constants) (+ index 1) (cons (constant-global (car constants) index) data)))))

    (define (constant-global constant index)
      (let ((name (ir:indexed-name "c" index)) (data (mir:constant-data constant)))
        (case (mir:constant-kind constant)
          ((pair) #f)
          ((vector) (ir:global-array name ir:i32 (map word data) 4))
          (else (ir:global-bytes name (constant-bytes constant))))))

    (define (body-primitive-data body)
      (map (lambda (primitive)
             (cons (car primitive)
                   (ir:global-bytes (ir:indexed-name "p" (car primitive))
                                    (ir:utf8-bytes (symbol->string (cdr primitive))))))
           (mir:body-primitives body)))

    (define (write-data constants primitives port)
      (for-each (lambda (data) (if data (ir:write-definition data port))) (vector->list constants))
      (for-each (lambda (entry) (ir:write-definition (cdr entry) port)) primitives))

    (define (constant-bytes constant)
      (let ((data (mir:constant-data constant)))
        (case (mir:constant-kind constant)
          ((string) (ir:utf8-bytes data))
          ((symbol) (ir:utf8-bytes (symbol->string data)))
          ((integer float character)
           (ir:utf8-bytes (number->string (if (char? data) (char->integer data) data))))
          ((boolean) (list (if data 49 48)))
          ((bytevector) (bytevector-bytes data))
          ((nil unspecified) '())
          (else (error "constant has no byte representation" (mir:constant-kind constant))))))

    (define (bytevector-bytes bytes)
      (let loop ((index 0))
        (if (= index (bytevector-length bytes)) '()
            (cons (bytevector-u8-ref bytes index) (loop (+ index 1))))))

    (define (atom-kind kind)
      (case kind
        ((string) 0) ((symbol) 1) ((integer) 2) ((float) 3) ((character) 4)
        ((boolean) 5) ((nil) 6) ((bytevector) 7) ((unspecified) 8)
        (else (error "unknown constant kind" kind))))

    (define (constant-initializers body constants vm)
      (let loop ((remaining (mir:body-constants body)) (index 0))
        (if (null? remaining) '()
            (cons (constant-initializer (car remaining) (vector-ref constants index) index vm)
                  (loop (cdr remaining) (+ index 1))))))

    (define (constant-initializer constant global index vm)
      (let ((data (mir:constant-data constant)))
        (case (mir:constant-kind constant)
          ((pair) (ir:call #f (runtime-function 'pair)
                           (list vm (word index) (word (car data)) (word (cadr data)))))
          ((vector) (ir:call #f (runtime-function 'vector)
                             (list vm (word index) global (word (length data)))))
          (else (ir:call #f (runtime-function 'atom)
                         (list vm (word index) (word (atom-kind (mir:constant-kind constant)))
                               global (word (ir:global-length global))))))))

    (define (primitive-initializer vm entry)
      (ir:call #f (runtime-function 'primitive)
               (list vm (word (car entry)) (cdr entry) (word (ir:global-length (cdr entry))))))


    ;; ---- Code identities and the dispatcher ----

    ;; STOP and CONSUME are saved as signed fixnums in the runtime's root frame.
    ;; All other code addresses are assigned here, never stored as HIR/MIR labels.
    (define (code-addresses body)
      (map (lambda (definition index)
             (let ((code (mir:definition-code definition)))
               (cons code (cond ((eq? (mir:code-name code) 'stop) 4294967295)
                                ((eq? (mir:code-name code) 'consume) 4294967294)
                                (else index)))))
           (mir:body-definitions body) (indices (length (mir:body-definitions body)))))
    (define (named-code body name)
      (let loop ((definitions (mir:body-definitions body)))
        (let ((code (mir:definition-code (car definitions))))
          (if (equal? (mir:code-name code) name) code (loop (cdr definitions))))))
    (define (code-blocks function body)
      (map (lambda (definition index)
             (cons (mir:definition-code definition) (ir:block function (string-append "code" (number->string index)))))
           (mir:body-definitions body) (indices (length (mir:body-definitions body)))))

    (define (write-execution body constants primitives port)
      (let* ((function (ir:function "snail_program" ir:void (list (cons ir:ptr "vm"))))
             (addresses (code-addresses body)) (blocks (code-blocks function body))
             (entry (initialization-body function body constants primitives addresses)))
        (ir:write-function-start (ir:define-function function 'external '() (list entry)) port)
        (ir:write-function-block function entry port)
        (let ((incoming (write-code-bodies function body addresses blocks port)))
          (ir:write-function-block function (dispatcher-body function body addresses blocks incoming) port))
        (for-each (lambda (block) (ir:write-function-block function block port)) (exit-bodies function))
        (ir:write-function-end port)))

    ;; Retain only phi edges. Keeping every emitted LLVM block until the end made
    ;; compiler-sized inputs spend nearly all emission time rescanning live IR in GC.
    (define (write-code-bodies function body addresses blocks port)
      (let ((incoming '()))
        (for-each
         (lambda (definition)
           (let ((emission (emit-mir-body function (cdr (assq (mir:definition-code definition) blocks))
                                          (mir:definition-body definition) (ir:parameter function 0)
                                          (value function ir:ptr "state") addresses
                                          (ir:block function "dispatch") (ir:block function "done"))))
             (for-each (lambda (block) (ir:write-function-block function block port)) (emission-blocks emission))
             (set! incoming (cons (emission-incoming emission) incoming))))
         (mir:body-definitions body))
        (apply append (reverse incoming))))

    (define (initialization-body function body constants primitives addresses)
      (let ((vm (ir:parameter function 0)) (state (value function ir:ptr "state")))
        (ir:block-body
         (ir:block function "entry")
         (append (list (ir:call state (runtime-function 'state) (list vm)))
                 (constant-initializers body constants vm)
                 (map (lambda (entry) (primitive-initializer vm entry)) primitives)
                 (list (ir:call #f (runtime-function 'close)
                                (list vm (word (cdr (assq (mir:body-entry body) addresses)))
                                      (word 0) (word 0) (word (mir:body-locals body)) (word 0)))
                       (ir:gep (value function ir:ptr "argc") ir:i8 state (list (word 36)))
                       (ir:store (word 0) (value function ir:ptr "argc"))))
         (ir:br (ir:block function "dispatch")))))

    (define (dispatcher-body function body addresses blocks incoming)
      (let ((pc (value function ir:i32 "pc")))
        (ir:block-body
         (ir:block function "dispatch")
         (list (ir:phi pc (cons (cons (word (cdr (assq (named-code body 'apply) addresses)))
                                      (ir:block function "entry"))
                                incoming)))
         (ir:switch pc (ir:block function "invalid")
                    (map (lambda (entry) (cons (word (cdr (assq (car entry) addresses))) (cdr entry))) blocks)))))

    (define (exit-bodies function)
      (let ((vm (ir:parameter function 0)) (done (ir:block function "done")))
        (list (ir:block-body (ir:block function "invalid")
                             (list (ir:call #f (runtime-function 'invalid) (list vm (value function ir:i32 "pc"))))
                             (ir:br done))
              (ir:block-body done (list (ir:call #f (runtime-function 'halt) (list vm))) (ir:ret #f)))))
    )
  )
