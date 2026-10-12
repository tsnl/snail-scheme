;; Effect interfaces name ordinary Wasm operations and their semantic contracts.
;; Selection happens while building a node; calls need no control-effect machine.
(define-library (snail-scheme effects)
  (export define-effect-interface make-effect-interface effect-interface? effect-name
          effect-revision effect-operations effect-contract operation-name operation-signature
          operation-behavior operation-abi operation-export make-effect-handler effect-handler?
          handler-interface handler-module handler-bindings make-platform platform? platform-name
          platform-handlers platform-modules platform-module current-platform node-platform
          filesystem-interface ports-interface environment-interface clock-interface diagnostics-interface
          build-interface effect-imports standard-effect-imports implementation-exports validate-platform)
  (import (scheme base) (scheme cxr) (scheme write))
  (begin

    ;; ---- Interface definitions ----

    ;; An operation is (name (argument-types -> result-type) behavior [native-abi]).
    ;; Omitted ABI means one borrowed vector root -> one owned result root.
    (define-record-type <effect-interface>
      (%interface name revision operations) effect-interface?
      (name effect-name) (revision effect-revision) (operations effect-operations))
    (define (operation-name operation) (car operation))
    (define (operation-signature operation) (cadr operation))
    (define (operation-behavior operation) (caddr operation))
    (define (operation-abi operation)
      (if (= (length operation) 3) '((i32) (i32)) (cadddr operation)))

    (define (unique-names? names)
      (or (null? names) (and (not (member (car names) (cdr names))) (unique-names? (cdr names)))))
    (define (every? predicate values)
      (or (null? values) (and (predicate (car values)) (every? predicate (cdr values)))))
    (define (native-type? type) (memq type '(i32 i64 f32 f64 externref funcref)))
    (define (valid-operation? operation)
      (and (list? operation) (memv (length operation) '(3 4))
           (symbol? (car operation)) (string? (caddr operation))
           (let ((signature (cadr operation)) (abi (operation-abi operation)))
             (and (list? signature) (= (length signature) 3)
                  (list? (car signature)) (eq? (cadr signature) '->)
                  (list? abi) (= (length abi) 2)
                  (every? (lambda (types) (and (list? types) (every? native-type? types))) abi)))))

    (define (make-effect-interface name revision operations)
      (unless (and (symbol? name) (integer? revision) (> revision 0)
                   (list? operations) (pair? operations) (every-operation? operations)
                   (unique-names? (map operation-name operations)))
        (error "invalid effect interface" name revision operations))
      (%interface name revision operations))
    (define (every-operation? operations)
      (or (null? operations) (and (valid-operation? (car operations)) (every-operation? (cdr operations)))))
    (define-syntax define-effect-interface
      (syntax-rules ()
        ((_ name revision operation ...)
         (define name (make-effect-interface 'name revision '(operation ...))))))
    (define (effect-contract interface)
      (list 'snail-effect 1 (effect-name interface) (effect-revision interface)
            (effect-operations interface)))
    (define (operation-export interface operation)
      (string-append (symbol->string (effect-name interface)) "/" (symbol->string (operation-name operation))))

    ;; ---- Complete handlers and platform collections ----

    (define-record-type <effect-handler>
      (%handler interface module bindings) effect-handler?
      (interface handler-interface) (module handler-module) (bindings handler-bindings))
    (define (binding? binding)
      (and (pair? binding) (symbol? (car binding)) (string? (cdr binding))))
    (define (make-effect-handler interface module bindings)
      (unless (and (effect-interface? interface) (string? module) (list? bindings)
                   (every? binding? bindings) (unique-names? (map car bindings))
                   (= (length bindings) (length (effect-operations interface)))
                   (every? (lambda (op) (assq (operation-name op) bindings)) (effect-operations interface)))
        (error "effect handler must implement the complete interface" module))
      (%handler interface module
                (map (lambda (op) (assq (operation-name op) bindings)) (effect-operations interface))))

    (define-record-type <platform>
      (%platform name handlers modules) platform?
      (name platform-name) (handlers platform-handlers) (modules platform-modules))
    (define (module-binding? binding)
      (and (pair? binding) (string? (car binding)) (string? (cdr binding))
           (not (member (car binding) '("snail.abi" "snail.library" "snail.platform" "snail.entry")))))
    (define (make-platform name handlers modules)
      (unless (and (symbol? name) (list? handlers) (pair? handlers) (every? effect-handler? handlers)
                   (list? modules) (every? module-binding? modules)
                   (unique-names? (map car modules))
                   (unique-names? (map (lambda (handler) (effect-name (handler-interface handler))) handlers)))
        (error "platform must select exactly one handler per interface" name))
      (%platform name handlers modules))

    ;; Each alias is a Wasm export of an imported function, not a forwarding body.
    ;; Binaryen checks actual implementation types while resolving these imports.
    (define (handler-declarations handler index)
      (apply append
             (map (lambda (operation binding)
                    (let* ((id (string->symbol (string-append "$effect" (number->string index)
                                                              "." (symbol->string (operation-name operation)))))
                           (abi (operation-abi operation)))
                      (list `(import ,(handler-module handler) ,(cdr binding)
                                     (func ,id (param ,@(car abi)) ,@(if (null? (cadr abi)) '() `((result ,@(cadr abi))))))
                            `(export ,(operation-export (handler-interface handler) operation) (func ,id)))))
                  (effect-operations (handler-interface handler)) (handler-bindings handler))))
    (define (platform-module platform)
      (let loop ((handlers (platform-handlers platform)) (index 0) (declarations '()))
        (if (null? handlers) (cons 'module declarations)
            (loop (cdr handlers) (+ index 1) (append declarations (handler-declarations (car handlers) index))))))
    (define (effect-imports interface)
      (map (lambda (operation)
             (list (operation-name operation) "snail.platform" (operation-export interface operation)))
           (effect-operations interface)))
    ;; Remove every private default implementation, including unselected ones.
    ;; Resolved calls and public interface aliases keep selected bodies alive.
    (define (implementation-exports platform)
      (apply append
             (map (lambda (interface)
                    (map (lambda (op) (string-append "snail:" (symbol->string (operation-name op))))
                         (effect-operations interface))) standard-interfaces)))
    (define (validate-platform platform)
      (for-each (lambda (interface)
                  (let ((handler (find-handler interface (platform-handlers platform))))
                    (when (and (not handler) (not (eq? interface build-interface)))
                      (error "platform is missing an effect interface" (effect-name interface)))
                    (when (and handler (not (equal? (effect-contract interface) (effect-contract (handler-interface handler)))))
                      (error "platform effect contract does not match" (effect-name interface)))))
                (append standard-interfaces (list build-interface))))
    (define (find-handler interface handlers)
      (cond ((null? handlers) #f)
            ((eq? (effect-name interface) (effect-name (handler-interface (car handlers)))) (car handlers))
            (else (find-handler interface (cdr handlers)))))

    ;; ---- Standard environment interfaces ----

    (define filesystem-interface
      (make-effect-interface 'filesystem 1
                             '((open-input-file ((String) -> InputPort) "Open buffered UTF-8 input; failure is fatal.")
                               (open-output-file ((String) -> OutputPort) "Create or truncate output; failure is fatal.")
                               (open-binary-input-file ((String) -> BinaryInputPort) "Open binary input; failure is fatal.")
                               (file-exists? ((String) -> Boolean) "Test existence; preserve documented filesystem errors.")
                               (delete-file ((String) -> Unspecified) "Remove a file; failure is fatal.")
                               (find-artifact ((String) -> (Or String Boolean)) "Find a named companion in this pinned generation; missing is false."))))
    (define ports-interface
      (make-effect-interface 'ports 1
                             '((close-port ((Port) -> Unspecified) "Explicit close is idempotent; string output remains readable.")
                               (port? ((Any) -> Boolean) "Recognize this node's port wrappers.")
                               (input-port? ((Any) -> Boolean) "Recognize input direction, including closed ports.")
                               (output-port? ((Any) -> Boolean) "Recognize output direction, including closed ports.")
                               (input-port-open? ((Port) -> Boolean) "Test whether input remains open.")
                               (output-port-open? ((Port) -> Boolean) "Test whether output remains open.")
                               (textual-port? ((Port) -> Boolean) "Test textual representation.")
                               (binary-port? ((Port) -> Boolean) "Test binary representation.")
                               (read (((Optional InputPort)) -> Any) "Read one datum with persistent stream lookahead; EOF is distinct.")
                               (read-char (((Optional InputPort)) -> (Or Character EOF)) "Read one Unicode scalar, or EOF.")
                               (peek-char (((Optional InputPort)) -> (Or Character EOF)) "Inspect the next scalar without consuming it.")
                               (read-line (((Optional InputPort)) -> (Or String EOF)) "Consume one line; preserve stream lookahead.")
                               (read-string ((Integer (Optional InputPort)) -> (Or String EOF)) "Read up to a scalar count; zero yields empty text.")
                               (read-bytevector ((Integer (Optional BinaryInputPort)) -> (Or Bytevector EOF)) "Read up to a byte count; zero yields empty bytes.")
                               (open-input-string ((String) -> InputPort) "Create node-owned buffered textual input.")
                               (open-output-string (() -> OutputPort) "Create node-owned textual output.")
                               (get-output-string ((OutputPort) -> String) "Copy current output, including after explicit close.")
                               (display ((Any (Optional OutputPort)) -> Unspecified) "Format display text and write it; default stdout.")
                               (write ((Any (Optional OutputPort)) -> Unspecified) "Format readable datum text; default stdout.")
                               (write-char ((Character (Optional OutputPort)) -> Unspecified) "Write one scalar.")
                               (write-string ((String (Optional OutputPort Integer Integer)) -> Unspecified) "Write the checked scalar slice.")
                               (flush-output-port (((Optional OutputPort)) -> Unspecified) "Flush promptly; closed-port errors are fatal.")
                               (newline (((Optional OutputPort)) -> Unspecified) "Write a newline; default stdout.")
                               (%current-input-port (() -> InputPort) "Return this node's current input.")
                               (%current-output-port (() -> OutputPort) "Return this node's current output.")
                               (%current-error-port (() -> OutputPort) "Return this node's current error output.")
                               (%set-current-input-port! ((InputPort) -> Unspecified) "Require an open input and replace the current root.")
                               (%set-current-output-port! ((OutputPort) -> Unspecified) "Require an open output and replace the current root.")
                               (%set-current-error-port! ((OutputPort) -> Unspecified) "Require an open output and replace the current root.")
                               (drop-resource ((ResourceKind ResourceId) -> Unspecified) "Release kind-1 ports by scalar ID; repeated cleanup is harmless." ((i32 i32) ())))))
    (define environment-interface
      (make-effect-interface 'environment 1
                             '((initialize-environment (() -> Unspecified) "Initialize the command filesystem context before Scheme runs." (() ()))
                               (command-line (() -> (List String)) "Return literal command identity followed by arguments.")
                               (exit (((Optional Any)) -> Bottom) "Terminate this command with its documented status conversion.")
                               (get-environment-variable ((String) -> (Or String Boolean)) "Return UTF-8 environment text; missing is false."))))
    (define clock-interface
      (make-effect-interface 'clock 1
                             '((current-second (() -> Real) "Report calendar seconds using the platform's clock semantics.")
                               (current-jiffy (() -> Integer) "Report monotonic ticks comparable within this node.")
                               (jiffies-per-second (() -> Integer) "Return the positive tick frequency of this handler."))))
    (define diagnostics-interface
      (make-effect-interface 'diagnostics 1
                             '((error ((String (Rest Any)) -> Bottom) "Print the existing Scheme diagnostic and terminate the command.")
                               (fail ((NativeCode) -> Bottom) "Internal failure codes preserve the language's named diagnostics.")
                               (report-error ((MemoryOffset ByteLength) -> Bottom) "Report UTF-8 bytes in the shared memory and terminate." ((i32 i32) ())))))
    (define build-interface
      (make-effect-interface 'build 1
                             '((%absolute-path ((String) -> String) "Normalize against the caller cwd without resolving symlinks.")
                               (%same-file? ((String String) -> Boolean) "Compare followed file identities; missing is false.")
                               (%process-status (((List String) String Boolean String) -> Integer) "Literal argv, cwd, stdin policy, argv0; reap and return status or 128+signal.")
                               (%publish-file ((String String) -> Unspecified) "Rename one completed candidate atomically on the same filesystem.")
                               (%copy-file ((String String) -> Unspecified) "Copy a regular file and its executable permissions.")
                               (%publish-bundle ((String String) -> Unspecified) "Publish a completed generation through one relative link.")
                               (%create-directory* ((String) -> Unspecified) "Create missing parents; accept existing directories.")
                               (%reserve-build-directory (((Or String Boolean)) -> String) "Reserve and own a private directory; false selects temporary storage.")
                               (%clean-build-directory ((String) -> Unspecified) "Remove only a directory owned by this invocation; cleanup failure warns."))))

    (define standard-interfaces
      (list filesystem-interface ports-interface environment-interface clock-interface diagnostics-interface))
    (define standard-effect-imports (apply append (map effect-imports standard-interfaces)))
    (define (default-handler interface module)
      (make-effect-handler interface module
                           (map (lambda (operation) (cons (operation-name operation)
                                                          (string-append "snail:" (symbol->string (operation-name operation)))))
                                (effect-operations interface))))
    (define node-platform
      (make-platform 'node
                     (append (map (lambda (interface) (default-handler interface "snail.library")) standard-interfaces)
                             (list (default-handler build-interface "snail.node"))) '()))
    (define current-platform (make-parameter node-platform))

    ))
