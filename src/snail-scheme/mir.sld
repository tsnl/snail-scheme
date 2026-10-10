;; Structured machine instructions. An instruction object is also its SSA value.
;; Regions order instructions; if owns two regions. Other than memory access,
;; every computation is an ordinary call with an explicit ABI and tail flag.
(define-library (snail-scheme mir)
  (export make-body body-entry body-locals body-definitions
          body-constants body-globals body-primitives
          make-code code? code-name make-definition definition-code definition-body
          make-constant constant-kind constant-data
          foreign foreign? foreign-name foreign-arguments foreign-result foreign-effect foreign-convention
          expression? expression-type expression-operation expression-operands
          region? region-instructions literal vm state let* sequence conditional
          load store offset binop compare cast call-direct call-indirect
          foreign-address code-reference tail-call finish
          expression-children body-foreign-descriptors write-mir-library)
  (import (except (scheme base) let*) (scheme cxr) (scheme write) (prefix (snail-scheme library) library:))
  (begin

    ;; ---- Library bodies and foreign interfaces ----

    ;; Code and data belong to a library. Numeric slots are assigned across the
    ;; dependency graph during elaboration; LLVM alone flattens these bodies.
    (define-record-type <body>
      (make-body entry locals definitions constants globals primitives) body?
      (entry body-entry) (locals body-locals) (definitions body-definitions)
      (constants body-constants) (globals body-globals) (primitives body-primitives))
    (define-record-type <code> (make-code name) code? (name code-name))
    (define-record-type <definition>
      (make-definition code body) definition? (code definition-code) (body definition-body))
    (define-record-type <constant>
      (make-constant kind data) constant? (kind constant-kind) (data constant-data))
    (define-record-type <foreign>
      (make-foreign name arguments result effect convention) foreign?
      (name foreign-name) (arguments foreign-arguments) (result foreign-result)
      (effect foreign-effect) (convention foreign-convention))
    (define (foreign name arguments result effect . convention)
      (make-foreign name arguments result effect (if (null? convention) 'c (car convention))))

    ;; ---- Instructions and operands ----

    (define-record-type <instruction>
      (instruction type operation operands) expression?
      (type instruction-type) (operation expression-operation) (operands expression-operands))
    (define-record-type <region>
      (make-region instructions type) region?
      (instructions region-instructions) (type region-type))
    (define (sequence instructions)
      (make-region instructions
                   (if (null? instructions) 'void
                       (expression-type (car (reverse instructions))))))
    (define (expression-type value)
      (if (region? value) (region-type value) (instruction-type value)))
    (define (literal type value) (instruction type 'literal (list value)))
    (define vm (instruction 'ptr 'input '(vm)))
    (define state (instruction 'ptr 'input '(state)))
    (define (foreign-address descriptor) (instruction 'ptr 'foreign-address (list descriptor)))
    (define (code-reference code) (instruction 'i32 'code-reference (list code)))
    (define (conditional test yes no)
      (instruction (if (terminates? yes) (expression-type no) (expression-type yes))
                   'if (list test yes no)))
    ;; Optional memory regions assert disjoint live storage, not pointer lifetime.
    ;; Omitted regions remain conservative; calls retain their ordinary effects.
    (define (load type address . region) (instruction type 'load (cons address region)))
    (define (store value address . region)
      (instruction 'void 'store (cons value (cons address region))))
    (define (call-direct callee arguments . tail)
      (instruction (if (and (pair? tail) (car tail)) 'never
                       (if (code? callee) 'void (foreign-result callee)))
                   'call-direct (cons callee (cons (and (pair? tail) (car tail)) arguments))))
    (define (call-indirect descriptor pointer arguments . tail)
      (instruction (if (and (pair? tail) (car tail)) 'never (foreign-result descriptor)) 'call-indirect
                   (cons descriptor (cons (and (pair? tail) (car tail)) (cons pointer arguments)))))

    ;; ---- Construction shorthand ----

    ;; Scheme lexical bindings name the producer itself. There is no MIR local,
    ;; copy, or bind instruction. Regions anchor producers before their consumers.
    (define-syntax let*
      (syntax-rules ()
        ((_ () body) body)
        ((_ ((name initializer) rest ...) body)
         (let ((name initializer)) (sequence (list name (let* (rest ...) body)))))))
    (define (leaf name result arguments)
      (call-direct (foreign name (map expression-type arguments) result 'pure) arguments))
    (define (binop operation left right)
      (leaf (string-append "snail_i32_" (symbol->string operation))
            (expression-type left) (list left right)))
    (define (integer-bits value)
      (if (eq? (expression-type value) 'ptr) (cast 'i32 'ptrtoint value) value))
    (define (compare predicate left right)
      (leaf (string-append "snail_i32_" (symbol->string predicate)) 'i32
            (list (integer-bits left) (integer-bits right))))
    (define (offset pointer bytes) (leaf "snail_pointer_offset" 'ptr (list pointer bytes)))
    (define (cast type operation value)
      (cond ((eq? type (expression-type value)) value)
            ((and (eq? operation 'zext) (eq? (expression-type value) 'i1))
             (conditional value (literal type 1) (literal type 0)))
            (else (leaf (case operation
                          ((ptrtoint) "snail_pointer_to_i32")
                          ((inttoptr) "snail_i32_to_pointer")
                          (else "snail_i32_identity")) type (list value)))))
    (define (tail-call target)
      (if (eq? (expression-operation target) 'code-reference)
          (call-direct (car (expression-operands target)) '() #t)
          (call-indirect (foreign "scheme" '() 'void 'control 'scheme) target '() #t)))
    (define finish (call-direct (foreign "snail_halt" '(ptr) 'void 'state) (list vm) #t))
    ;; 'never describes a terminating instruction, not a machine value. Cache it
    ;; in each container: recursively inspecting shared tails is exponential.
    (define (terminates? node) (eq? (expression-type node) 'never))

    ;; ---- Inspection ----

    (define (expression-children node)
      (if (region? node) (region-instructions node)
          (let loop ((items (expression-operands node)))
            (cond ((null? items) '())
                  ((or (expression? (car items)) (region? (car items)))
                   (cons (car items) (loop (cdr items))))
                  (else (loop (cdr items)))))))
    (define (body-foreign-descriptors program)
      (let ((seen '()) (descriptors '()))
        (define (visit node)
          (if (not (memq node seen))
              (begin
                (set! seen (cons node seen))
                (if (expression? node)
                    (for-each (lambda (item)
                                (if (and (foreign? item) (eq? (foreign-convention item) 'c)
                                         (not (assoc (foreign-name item) descriptors)))
                                    (set! descriptors (cons (cons (foreign-name item) item) descriptors))))
                              (expression-operands node)))
                (for-each visit (expression-children node)))))
        ;; Bodies share operands such as vm, but their instruction graphs are
        ;; independent. Keep the identity scan local to avoid a quadratic walk
        ;; through every previously visited body in the program.
        (for-each (lambda (definition)
                    (set! seen '())
                    (visit (definition-body definition)))
                  (body-definitions program))
        (map cdr (reverse descriptors))))

    ;; Every instruction is printed once; operands refer to its stable dump index.
    ;; These are SSA value identities, not branch labels or mutable registers.
    (define (definition-datum definition codes)
      (let ((seen '()) (instructions '()) (next 0))
        (define (visit item)
          (cond ((code? item) (list 'code (cdr (assq item codes))))
                ((foreign? item) (list 'foreign (foreign-name item)))
                ((not (or (expression? item) (region? item))) item)
                ((assq item seen) => cdr)
                (else
                 (let ((args (map visit (if (region? item) (region-instructions item)
                                            (expression-operands item)))))
                   (let ((index next))
                     (set! next (+ next 1))
                     (set! seen (cons (cons item index) seen))
                     (set! instructions
                           (cons (cons index (cons (if (region? item) 'region (expression-operation item))
                                                   (cons (expression-type item) args))) instructions))
                     index)))))
        (let ((body (visit (definition-body definition))))
          (list 'code (cdr (assq (definition-code definition) codes))
                (code-name (definition-code definition)) (reverse instructions) body))))
    (define (numbered-codes definitions)
      (let loop ((definitions definitions) (index 0))
        (if (null? definitions) '()
            (cons (cons (definition-code (car definitions)) index)
                  (loop (cdr definitions) (+ index 1))))))
    (define (write-library-body library codes port)
      (let ((body (library:library-body library)))
        (write (list 'library (library:library-name library)
                     (list 'entry (cdr (assq (body-entry body) codes)))
                     (list 'locals (body-locals body)) (cons 'globals (body-globals body))) port)
        (newline port)
        (for-each (lambda (definition)
                    (write (definition-datum definition codes) port) (newline port))
                  (body-definitions body))))
    (define (write-mir-library root port)
      (let ((libraries (library:library-dependency-order root)))
        (let ((codes (numbered-codes
                      (apply append (map (lambda (library)
                                           (body-definitions (library:library-body library))) libraries)))))
          (for-each (lambda (library) (write-library-body library codes port)) libraries)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-mir)
    (import (snail-scheme test-utils))
    (begin
      (define (test-producer-identity)
        (let ((x (literal 'i32 2)))
          (let ((sum (binop 'add x x)))
            (expect (eq? (caddr (expression-operands sum))
                         (cadddr (expression-operands sum))) #t))))
      (define (test-regions)
        (let ((tree (let* ((x (literal 'i32 2))) (binop 'add x x))))
          (expect (region? tree) #t)
          (expect (expression-operation (cadr (region-instructions tree))) 'call-direct)))
      (define (test-mir)
        (run-test test-producer-identity)
        (run-test test-regions))))))
