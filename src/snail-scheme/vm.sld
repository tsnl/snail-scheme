;; The stack VM is a compilation representation, independent of LLVM and Rust.
;; Labels identify instructions. Ordinary instructions have a known successor;
;; calls and returns transfer through the explicit Scheme continuation stack.
;; Frame saves closure/frame/resume before arguments are evaluated. Argument
;; pushes a value; apply enters a procedure. A tail call shifts its arguments
;; over the current locals, retaining the caller's three-word return record.
;; Box creates an assigned binding's cell; indirect reads that cell. Immutable
;; locals and free variables hold values directly, including closure captures.
(define-library (snail-scheme vm)
  (export
   make-vm-program vm-program? vm-program-entry vm-program-locals
   vm-program-instructions vm-program-constants vm-program-globals vm-program-primitives
   make-instruction instruction? instruction-label instruction-operation
   instruction-operands instruction-next instruction-loc
   make-constant constant? constant-kind constant-data
   write-vm-program)
  (import (scheme base) (scheme write))
  (begin
    (define-record-type <vm-program>
      (make-vm-program entry locals instructions constants globals primitives)
      vm-program?
      (entry vm-program-entry)
      (locals vm-program-locals)
      (instructions vm-program-instructions)
      (constants vm-program-constants)
      (globals vm-program-globals)
      (primitives vm-program-primitives))

    (define-record-type <instruction>
      (make-instruction label operation operands next loc)
      instruction?
      (label instruction-label)
      (operation instruction-operation)
      (operands instruction-operands)
      (next instruction-next)
      (loc instruction-loc))

    ;; Pair/vector payloads refer to earlier constant indices. Other payloads are
    ;; Scheme scalar values or bytevectors. Each literal is built once at startup.
    (define-record-type <constant>
      (make-constant kind data)
      constant?
      (kind constant-kind)
      (data constant-data))

    (define (write-vm-program program port)
      (write `(stack-vm
               (entry ,(vm-program-entry program) (locals ,(vm-program-locals program)))
               (globals ,@(vm-program-globals program))
               (primitives ,@(vm-program-primitives program))
               (constants ,@(map (lambda (item)
                                   (list (constant-kind item) (constant-data item)))
                                 (vm-program-constants program)))) port)
      (newline port)
      (for-each
       (lambda (instruction)
         (write (list (instruction-label instruction)
                      (instruction-operation instruction)
                      (instruction-operands instruction)
                      (instruction-next instruction)) port)
         (newline port))
       (vm-program-instructions program)))))
