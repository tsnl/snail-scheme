;; Lower resolved IR directly into WebAssembly expressions. There is no second
;; compiler IR and no interpreter stack: parameters and temporaries are Wasm
;; locals, calls are Wasm calls, and tail positions use return_call/ref.
;;
;; Every lambda has an ordinary fixed-arity entry and a uniform closure adapter.
;; Known calls avoid argument arrays; dynamic calls and apply use the adapter.
;; Captures are GC references. Only assigned or early-captured locals need cells.
(define-library (snail-scheme wasm)
  (export write-ir-library-as-wasm)
  (import (scheme base) (scheme cxr) (scheme write) (scheme file)
          (snail-scheme trace) (snail-scheme bootstrap)
          (prefix (snail-scheme ir) ir:) (prefix (snail-scheme library) library:))
  (begin

    ;; ---- Compilation state ----

    (define-record-type <module>
      (make-module globals primitives boxed functions known foreign constants)
      module?
      (globals module-globals) (primitives module-primitives)
      (boxed module-boxed) (functions module-functions) (known module-known)
      (foreign module-foreign) (constants module-constants set-module-constants!))

    (define-record-type <function>
      (make-function module environment temporaries)
      function?
      (module function-module) (environment function-environment)
      (temporaries function-temporaries set-function-temporaries!))

    (define (identifier prefix number)
      (string->symbol (string-append "$" prefix (number->string number))))

    (define (temporary! context)
      (let ((name (identifier "t" (length (function-temporaries context)))))
        (set-function-temporaries! context (cons name (function-temporaries context)))
        name))

    (define (function-locals context)
      (map (lambda (name) `(local ,name eqref)) (reverse (function-temporaries context))))

    (define (all-lambdas items)
      (define (visit node)
        (if (ir:lambda? node) (cons node (visit (ir:lambda-body node)))
            (apply append (map visit (children node)))))
      (apply append (map visit items)))

    (define (known-lambdas items assigned)
      (define (visit node)
        (append (if (and (ir:value-binding? node)
                         (ir:lambda? (ir:value-binding-initializer node))
                         (not (memq (ir:value-binding-definition node) assigned)))
                    (list (cons (ir:value-binding-definition node)
                                (ir:value-binding-initializer node))) '())
                (if (ir:lambda? node) (visit (ir:lambda-body node))
                    (apply append (map visit (children node))))))
      (apply append (map visit items)))

    (define (prepare-module libraries foreign)
      (let* ((items (apply append (map library:library-body libraries)))
             (globals (apply append (map library-global-definitions libraries)))
             (primitives (apply append (map library-core-primitives libraries))))
        (make-module (numbered globals) (immutable-primitives primitives items)
                     (boxed-definitions items globals) (numbered (all-lambdas items))
                     (known-lambdas items (assigned-definitions items)) foreign '())))

    ;; ---- Binding and capture analysis ----
    (define (library-global-definitions library)
      (unique-identities (append (library-primitives library) (item-definitions (library:library-body library)))))
    (define (library-core-primitives library)
      (if (equal? (library:library-name library) '(snail-scheme core))
          (value-exports (library:library-exports library)) '()))

    (define (library-primitives library)
      (if (member (library:library-name library) '((snail-scheme core) (snail-scheme extensions)))
          (value-exports (library:library-exports library)) '()))
    (define (value-exports exports)
      (if (null? exports) '()
          (let ((definition (library:named-binding-definition (car exports))))
            (if (ir:value-definition? definition)
                (cons definition (value-exports (cdr exports)))
                (value-exports (cdr exports))))))

    (define (item-definitions items)
      (if (null? items) '()
          (if (ir:value-binding? (car items))
              (cons (ir:value-binding-definition (car items))
                    (item-definitions (cdr items)))
              (item-definitions (cdr items)))))

    (define (unique-identities definitions)
      (let loop ((remaining definitions) (seen '()) (result '()))
        (cond ((null? remaining) (reverse result))
              ((memq (car remaining) seen) (loop (cdr remaining) seen result))
              (else (loop (cdr remaining) (cons (car remaining) seen)
                          (cons (car remaining) result))))))

    (define (numbered values)
      (let loop ((values values) (index 0))
        (if (null? values) '()
            (cons (cons (car values) index) (loop (cdr values) (+ index 1))))))

    ;; Descend through blocks in this activation, stopping at nested procedures.
    ;; Their binding identities belong to a different activation.
    (define (local-definitions items globals)
      (define (collect node)
        (cond ((ir:lambda? node) '())
              ((ir:value-binding? node)
               (append (if (memq (ir:value-binding-definition node) globals) '()
                           (list (ir:value-binding-definition node)))
                       (collect (ir:value-binding-initializer node))))
              (else (apply append (map collect (children node))))))
      (unique-identities (apply append (map collect items))))

    (define (children node)
      (cond
       ((ir:application? node)
        (cons (ir:application-operator node) (ir:application-operands node)))
       ((ir:block? node) (ir:block-items node))
       ((ir:conditional? node)
        (append (list (ir:conditional-test node) (ir:conditional-consequent node))
                (if (ir:conditional-opt-alternate node)
                    (list (ir:conditional-opt-alternate node)) '())))
       ((ir:assignment? node) (list (ir:assignment-target node) (ir:assignment-value node)))
       ((ir:value-binding? node) (list (ir:value-binding-initializer node)))
       (else '())))

    (define (lambda-locals procedure)
      (append (ir:lambda-parameters procedure)
              (if (ir:lambda-opt-rest-parameter procedure)
                  (list (ir:lambda-opt-rest-parameter procedure)) '())
              (local-definitions (list (ir:lambda-body procedure)) '())))

    ;; Descend into child procedures because their set! can assign an outer name.
    (define (assigned-definitions items)
      (define (visit node)
        (append
         (if (ir:assignment? node)
             (list (ir:name-definition (ir:assignment-target node))) '())
         (if (ir:lambda? node) (visit (ir:lambda-body node))
             (apply append (map visit (children node))))))
      (unique-identities (apply append (map visit items))))

    ;; A closure created before a definition's initializer must retain its
    ;; location, not copy UNINITIALIZED. Otherwise immutable locals stay unboxed.
    ;; The walk tracks definitely initialized identities through evaluation order;
    ;; branches keep only identities initialized on both paths.
    (define (boxed-definitions items globals)
      (define (nested node)
        (if (ir:lambda? node)
            (append (car (initialization-sequence (list (ir:lambda-body node))
                                                  (lambda-locals node) globals
                                                  (lambda-arguments node)))
                    (nested (ir:lambda-body node)))
            (apply append (map nested (children node)))))
      (unique-identities
       (append (assigned-definitions items)
               (car (initialization-sequence items (local-definitions items globals) globals '()))
               (apply append (map nested items)))))

    (define (lambda-arguments procedure)
      (append (ir:lambda-parameters procedure)
              (if (ir:lambda-opt-rest-parameter procedure)
                  (list (ir:lambda-opt-rest-parameter procedure)) '())))

    (define (initialization-sequence nodes locals globals initialized)
      (if (null? nodes) (cons '() initialized)
          (let* ((first (initialization-state (car nodes) locals globals initialized))
                 (rest (initialization-sequence (cdr nodes) locals globals (cdr first))))
            (cons (append (car first) (car rest)) (cdr rest)))))

    (define (uninitialized-captures procedure locals globals initialized)
      (let loop ((free (free-definitions procedure (numbered globals))))
        (cond ((null? free) '())
              ((and (memq (car free) locals) (not (memq (car free) initialized)))
               (cons (car free) (loop (cdr free))))
              (else (loop (cdr free))))))

    (define (initialization-state node locals globals initialized)
      (cond ((ir:lambda? node)
             (cons (uninitialized-captures node locals globals initialized) initialized))
            ((ir:value-binding? node)
             (let ((state (initialization-state (ir:value-binding-initializer node)
                                                locals globals initialized)))
               (cons (car state) (cons (ir:value-binding-definition node) (cdr state)))))
            ((ir:conditional? node) (conditional-initialization node locals globals initialized))
            ((ir:application? node)
             (initialization-sequence (append (ir:application-operands node)
                                              (list (ir:application-operator node)))
                                      locals globals initialized))
            (else (initialization-sequence (children node) locals globals initialized))))

    (define (conditional-initialization node locals globals initialized)
      (let* ((test (initialization-state (ir:conditional-test node) locals globals initialized))
             (yes (initialization-state (ir:conditional-consequent node) locals globals (cdr test)))
             (no (if (ir:conditional-opt-alternate node)
                     (initialization-state (ir:conditional-opt-alternate node) locals globals (cdr test))
                     (cons '() (cdr test)))))
        (cons (append (car test) (car yes) (car no))
              (let loop ((identities (cdr yes)))
                (cond ((null? identities) '())
                      ((memq (car identities) (cdr no))
                       (cons (car identities) (loop (cdr identities))))
                      (else (loop (cdr identities))))))))

    (define (free-definitions procedure globals)
      (define (visit node bound)
        (cond
         ((ir:name? node)
          (let ((definition (ir:name-definition node)))
            (if (or (memq definition bound) (assq definition globals)) '()
                (list definition))))
         ((ir:lambda? node)
          (visit (ir:lambda-body node) (append (lambda-locals node) bound)))
         (else (apply append (map (lambda (child) (visit child bound)) (children node))))))
      (unique-identities (visit procedure '())))

    (define (initialized-definitions items)
      (define (visit node)
        (append (if (ir:value-binding? node) (list (ir:value-binding-definition node)) '())
                (if (ir:lambda? node) (visit (ir:lambda-body node))
                    (apply append (map visit (children node))))))
      (apply append (map visit items)))

    (define (immutable-primitives primitives items)
      (let ((written (append (initialized-definitions items) (assigned-definitions items))))
        (let loop ((remaining primitives))
          (cond ((null? remaining) '())
                ((memq (car remaining) written) (loop (cdr remaining)))
                (else (cons (car remaining) (loop (cdr remaining))))))))


    ;; ---- References and literals ----

    (define (binding-place definition context)
      (or (assq definition (function-environment context))
          (let ((global (assq definition (module-globals (function-module context)))))
            (and global (cons definition `(global ,(identifier "g" (cdr global))))))
          (error "unresolved storage" (ir:value-definition-name definition))))

    (define (read-place place)
      (case (cadr place)
        ((local) `(local.get ,(caddr place)))
        ((global) `(global.get ,(caddr place)))
        ((capture) `(array.get $vector (ref.cast (ref $vector) (local.get $env))
                               (i32.const ,(caddr place))))))

    (define (boxed-place? place context)
      (and (not (eq? (cadr place) 'global))
           (memq (car place) (module-boxed (function-module context)))))

    (define (read-binding definition context)
      (let* ((place (binding-place definition context)) (value (read-place place)))
        `(call $defined ,(if (boxed-place? place context)
                             `(struct.get $cell 0 (ref.cast (ref $cell) ,value)) value))))

    (define (store-binding definition value context)
      (let ((place (binding-place definition context)))
        `(block (result eqref)
                ,(if (boxed-place? place context)
                     `(struct.set $cell 0 (ref.cast (ref $cell) ,(read-place place)) ,value)
                     `(,(if (eq? (cadr place) 'global) 'global.set 'local.set)
                       ,(caddr place) ,value))
                (global.get $unspecified))))

    (define (constant! datum module)
      (let ((found (assoc datum (module-constants module))))
        (if found (cdr found)
            (let ((name (identifier "constant" (length (module-constants module)))))
              (set-module-constants! module (cons (cons datum name) (module-constants module)))
              name))))

    (define (literal-value datum module)
      (cond ((eq? datum #f) '(global.get $false))
            ((eq? datum #t) '(global.get $true))
            ((null? datum) '(global.get $nil))
            ((char? datum) `(struct.new $atom (i32.const ,(+ 256 (char->integer datum)))))
            ((exact-integer? datum) (integer-literal datum))
            ((number? datum) `(struct.new $float (f64.const ,(float-token datum))))
            (else `(global.get ,(constant! datum module)))))

    (define (integer-literal datum)
      (if (or (< datum -9223372036854775808) (> datum 9223372036854775807))
          (error "integer literal outside supported signed 64-bit range" datum))
      `(call $pack_integer (i64.const ,datum)))

    (define (float-token number)
      (let ((text (number->string number)))
        (cond ((equal? text "+nan.0") 'nan)
              ((equal? text "+inf.0") 'inf) ((equal? text "-inf.0") '-inf)
              (else number))))

    (define (text-expression text)
      `(array.new_fixed $text ,(string-length text)
                        ,@(map (lambda (character) `(i32.const ,(char->integer character)))
                               (string->list text))))

    (define (constant-expression datum)
      (cond ((pair? datum) `(struct.new $pair ,(constant-expression (car datum))
                                        ,(constant-expression (cdr datum))))
            ((vector? datum) `(array.new_fixed $vector ,(vector-length datum)
                                               ,@(map constant-expression (vector->list datum))))
            ((bytevector? datum) `(struct.new $bytevector ,(bytevector-expression datum)))
            ((string? datum) `(struct.new $text_object (i32.const 0) ,(text-expression datum)))
            ((symbol? datum) `(call $intern ,(text-expression (symbol->string datum))))
            (else (literal-value datum #f))))

    (define (bytevector-expression datum)
      (let loop ((index (- (bytevector-length datum) 1)) (bytes '()))
        (if (< index 0) `(array.new_fixed $bytes ,(bytevector-length datum) ,@bytes)
            (loop (- index 1) (cons `(i32.const ,(bytevector-u8-ref datum index)) bytes)))))

    ;; ---- Structured expressions ----

    (define (single node context)
      `(call $single ,(expression node context #f)))

    (define (expression node context tail?)
      (cond ((ir:literal? node) (literal-value (ir:literal-value node) (function-module context)))
            ((ir:name? node) (read-binding (ir:name-definition node) context))
            ((ir:lambda? node) (closure-expression node context))
            ((ir:application? node) (application-expression node context tail?))
            ((ir:block? node) (sequence-expression (ir:block-items node) context tail?))
            ((ir:conditional? node) (conditional-expression node context tail?))
            ((ir:value-binding? node)
             (store-binding (ir:value-binding-definition node)
                            (single (ir:value-binding-initializer node) context) context))
            ((ir:assignment? node)
             (store-binding (ir:name-definition (ir:assignment-target node))
                            (single (ir:assignment-value node) context) context))
            (else (error "unknown IR expression" node))))

    (define (sequence-expression items context tail?)
      (cond ((null? items) '(global.get $unspecified))
            ((null? (cdr items)) (expression (car items) context tail?))
            (else `(block (result eqref) (drop ,(expression (car items) context #f))
                          ,(sequence-expression (cdr items) context tail?)))))

    (define (conditional-expression node context tail?)
      `(if (result eqref) (call $truthy ,(single (ir:conditional-test node) context))
           (then ,(expression (ir:conditional-consequent node) context tail?))
           (else ,(if (ir:conditional-opt-alternate node)
                      (expression (ir:conditional-opt-alternate node) context tail?)
                      '(global.get $unspecified)))))

    (define (closure-expression node context)
      (let* ((module (function-module context))
             (index (cdr (assq node (module-functions module))))
             (free (free-definitions node (module-globals module))))
        `(struct.new $closure (ref.func ,(identifier "adapter" index))
                     (array.new_fixed $vector ,(length free)
                                      ,@(map (lambda (definition)
                                               (read-place (binding-place definition context))) free)))))

    ;; ---- Calls ----

    (define direct-primitives
      '((+ 2 add) (- 2 subtract) (* 2 multiply) (/ 2 divide)
        (= 2 numeric_equal) (< 2 less) (<= 2 less_equal) (> 2 greater) (>= 2 greater_equal)
        (eq? 2 eq) (eqv? 2 eqv) (cons 2 cons) (car 1 car) (cdr 1 cdr)
        (procedure? 1 is_procedure) (number? 1 is_number) (exact-integer? 1 is_integer_value)
        (null? 1 is_null) (pair? 1 is_pair)))

    (define (direct-primitive node module)
      (let ((operator (ir:application-operator node)))
        (and (ir:name? operator)
             (memq (ir:name-definition operator) (module-primitives module))
             (let ((entry (assq (ir:value-definition-name (ir:name-definition operator))
                                direct-primitives)))
               (and entry (= (cadr entry) (length (ir:application-operands node)))
                    (string->symbol (string-append "$" (symbol->string (caddr entry)))))))))

    (define (known-procedure node module)
      (let ((operator (ir:application-operator node)))
        (cond ((ir:lambda? operator) operator)
              ((ir:name? operator)
               (let ((entry (assq (ir:name-definition operator) (module-known module))))
                 (and entry (cdr entry))))
              (else #f))))

    (define (application-expression node context tail?)
      (let* ((primitive (direct-primitive node (function-module context)))
             (operands (ir:application-operands node)))
        (if primitive
            `(,(if tail? 'return_call 'call) ,primitive
              ,@(map (lambda (operand) (single operand context)) operands))
            (procedure-call node context tail?))))

    ;; Bind operands before the operator, retaining the established evaluation
    ;; order even though a direct call puts its closure environment first.
    (define (procedure-call node context tail?)
      (let* ((operands (ir:application-operands node))
             (arguments (map (lambda (node) (temporary! context)) operands))
             (operator (temporary! context))
             (procedure (known-procedure node (function-module context))))
        `(block (result eqref)
                ,@(map (lambda (name operand) `(local.set ,name ,(single operand context)))
                       arguments operands)
                (local.set ,operator ,(single (ir:application-operator node) context))
                ,(call-expression procedure operator arguments context tail?))))

    (define (call-expression procedure operator arguments context tail?)
      (if (and procedure (not (ir:lambda-opt-rest-parameter procedure))
               (= (length arguments) (length (ir:lambda-parameters procedure))))
          `(,(if tail? 'return_call 'call)
            ,(identifier "function" (cdr (assq procedure (module-functions (function-module context)))))
            (struct.get $closure 1 (ref.cast (ref $closure) (local.get ,operator)))
            ,@(map (lambda (name) `(local.get ,name)) arguments))
          `(,(if tail? 'return_call 'call) $apply (local.get ,operator)
            (array.new_fixed $vector ,(length arguments)
                             ,@(map (lambda (name) `(local.get ,name)) arguments)))))

    ;; ---- Procedure definitions ----

    (define (procedure-environment procedure module)
      (append (map (lambda (entry) (list (car entry) 'local (identifier "v" (cdr entry))))
                   (numbered (lambda-locals procedure)))
              (map (lambda (entry) (list (car entry) 'capture (cdr entry)))
                   (numbered (free-definitions procedure (module-globals module))))))

    (define (box-local definition context)
      (let* ((place (binding-place definition context)) (name (caddr place)))
        `(local.set ,name (struct.new $cell ,(read-place place)))))

    (define (initialize-locals locals parameters context)
      (apply append
             (map (lambda (definition)
                    (append (if (memq definition parameters) '()
                                `((local.set ,(caddr (binding-place definition context))
                                             (global.get $uninitialized))))
                            (if (memq definition (module-boxed (function-module context)))
                                (list (box-local definition context)) '()))) locals)))

    (define (procedure-function entry module)
      (let* ((procedure (car entry)) (parameters (lambda-arguments procedure))
             (locals (lambda-locals procedure))
             (context (make-function module (procedure-environment procedure module) '()))
             (body (expression (ir:lambda-body procedure) context #t)))
        `(func ,(identifier "function" (cdr entry)) (param $env eqref)
               ,@(map (lambda (definition) `(param ,(caddr (binding-place definition context)) eqref)) parameters)
               (result eqref)
               ,@(map (lambda (definition) `(local ,(caddr (binding-place definition context)) eqref))
                      (list-tail locals (length parameters)))
               ,@(function-locals context)
               ,@(initialize-locals locals parameters context) ,body)))

    (define (procedure-adapter entry)
      (let* ((procedure (car entry)) (count (length (ir:lambda-parameters procedure)))
             (rest? (ir:lambda-opt-rest-parameter procedure)))
        `(func ,(identifier "adapter" (cdr entry)) (type $call)
               (param $env eqref) (param $arguments (ref $vector)) (result eqref)
               (call $arity (local.get $arguments) (i32.const ,count) (i32.const ,(if rest? 1 0)))
               (return_call ,(identifier "function" (cdr entry)) (local.get $env)
                            ,@(map (lambda (entry) `(array.get $vector (local.get $arguments)
                                                               (i32.const ,(cdr entry))))
                                   (numbered (ir:lambda-parameters procedure)))
                            ,@(if rest? `((call $rest (local.get $arguments) (i32.const ,count))) '())))))

    ;; ---- Library entries ----

    (define (library-function entry module)
      (let* ((items (library:library-body (car entry)))
             (locals (local-definitions items (map car (module-globals module))))
             (environment (map (lambda (entry) (list (car entry) 'local (identifier "v" (cdr entry))))
                               (numbered locals)))
             (context (make-function module environment '()))
             (body (sequence-expression items context #f)))
        `(func ,(identifier "library" (cdr entry)) (result eqref)
               ,@(map (lambda (entry) `(local ,(caddr entry) eqref)) environment)
               ,@(function-locals context) ,@(initialize-locals locals '() context) ,body)))

    (define (primitive-function entry)
      (let ((name (if (< (cdr entry) (length bootstrap-primitive-names))
                      (string->symbol (string-append "$builtin:" (symbol->string (car entry))))
                      (identifier "foreign" (- (cdr entry) (length bootstrap-primitive-names))))))
        `(func ,(identifier "primitive" (cdr entry)) (type $call)
               (param $env eqref) (param $arguments (ref $vector)) (result eqref)
               (return_call ,name (local.get $arguments)))))

    (define (global-initializer slot)
      `(global.set ,(identifier "g" (car slot))
                   (struct.new $closure (ref.func ,(identifier "primitive" (cdr slot)))
                               (array.new_fixed $vector 0))))

    (define (module-entry libraries module)
      `(func (export "snail_main") (result eqref)
             ,@(map (lambda (entry) `(global.set ,(cdr entry) ,(constant-expression (car entry))))
                    (reverse (module-constants module)))
             ,@(map global-initializer (library-primitive-slots libraries module))
             ,@(map (lambda (entry) `(drop (call ,(identifier "library" (cdr entry)))))
                    (reverse (cdr (reverse libraries))))
             (call ,(identifier "library" (cdr (car (reverse libraries)))))))

    ;; A host borrows an argument-vector root and owns the returned result root.
    ;; These handles are only for same-instance embedding, never actor messages.
    (define (library-export binding module)
      `(func (export ,(string-append "scheme:" (symbol->string (library:named-binding-name binding))))
             (param $arguments i32) (result i32)
             (call $awi_root
                   (call $apply
                         ,(read-binding (library:named-binding-definition binding)
                                        (make-function module '() '()))
                         (ref.cast (ref $vector) (call $awi_get (local.get $arguments)))))))

    (define (library-exports root module)
      (let loop ((bindings (library:library-exports root)))
        (cond ((null? bindings) '())
              ((ir:value-definition? (library:named-binding-definition (car bindings)))
               (cons (library-export (car bindings) module) (loop (cdr bindings))))
              (else (loop (cdr bindings))))))

    (define (primitive-slot definition library module)
      (let* ((foreign? (equal? (library:library-name library) '(snail-scheme extensions)))
             (names (if foreign? (map car (module-foreign module)) bootstrap-primitive-names))
             (index (cdr (assq (ir:value-definition-name definition) (numbered names)))))
        (cons (cdr (assq definition (module-globals module)))
              (+ index (if foreign? (length bootstrap-primitive-names) 0)))))

    (define (library-primitive-slots libraries module)
      (apply append
             (map (lambda (entry)
                    (map (lambda (definition) (primitive-slot definition (car entry) module))
                         (library-primitives (car entry)))) libraries)))

    ;; ---- Rust services through AWI ----

    ;; Each service has its own Wasm import. Rust borrows the argument root and
    ;; returns a separately owned root; resolve its value before releasing roots.
    (define rust-primitives
      '(string->number number->string char-ci=? char-alphabetic? char-numeric? char-whitespace?
                       error open-input-file open-output-file close-port read-char read-string
                       open-output-string get-output-string display write newline
                       %current-input-port %current-output-port %current-error-port
                       %set-current-input-port! %set-current-output-port! %set-current-error-port!
                       command-line exit current-jiffy jiffies-per-second string-contains
                       collect-garbage gc-statistics %trace-begin %trace-end))

    (define (module-services module)
      (append (map (lambda (name) (cons name "snail.rust")) rust-primitives)
              (module-foreign module)))

    (define (module-primitive-names module)
      (append bootstrap-primitive-names (map car (module-foreign module))))

    (define (rust-import entry)
      `(import ,(cdar entry) ,(string-append "snail:" (symbol->string (caar entry)))
               (func ,(identifier "rust" (cdr entry)) (param i32) (result i32))))

    (define (service-function-name entry)
      (if (< (cdr entry) (length rust-primitives))
          (string->symbol (string-append "$builtin:" (symbol->string (caar entry))))
          (identifier "foreign" (- (cdr entry) (length rust-primitives)))))

    (define (rust-wrapper entry)
      `(func ,(service-function-name entry)
             (param $arguments (ref $vector)) (result eqref)
             (local $root i32) (local $result eqref)
             (local.set $root (call $awi_root (local.get $arguments)))
             (local.set $result (call $awi_take (call ,(identifier "rust" (cdr entry)) (local.get $root))))
             (call $awi_release (local.get $root))
             (local.get $result)))

    ;; ---- Serialization ----

    (define (copy-file path port)
      (call-with-input-file path
        (lambda (input)
          (let loop ((character (read-char input)))
            (if (not (eof-object? character))
                (begin (display character port) (loop (read-char input))))))))

    ;; Scheme's writer escapes numeric-looking symbols such as -inf. WAT uses
    ;; those tokens literally; only WAT string operands need Scheme quoting.
    (define (write-wasm-expression expression port)
      (cond ((pair? expression)
             (display "(" port)
             (write-wasm-expression (car expression) port)
             (for-each (lambda (item) (display " " port) (write-wasm-expression item port))
                       (cdr expression))
             (display ")" port))
            ((symbol? expression) (display (symbol->string expression) port))
            (else (write expression port))))

    (define (write-definition definition port)
      (write-wasm-expression definition port)
      (newline port))

    (define-traced (write-ir-library-as-wasm root runtime-path awi-path port . foreign)
      (let* ((libraries (numbered (library:library-dependency-order root)))
             (module (prepare-module (map car libraries) (if (null? foreign) '() (car foreign))))
             (procedures (map (lambda (entry) (procedure-function entry module)) (module-functions module)))
             (entries (map (lambda (entry) (library-function entry module)) libraries)))
        (display "(module\n" port)
        (write-definition '(import "snail.rust" "snail:fail" (func $rust_fail (param i32) (result i32))) port)
        (write-definition '(import "snail.host" "register-finalizer"
                                   (func $host_register_finalizer (param eqref i32 i32))) port)
        (for-each (lambda (entry) (write-definition (rust-import entry) port))
                  (numbered (module-services module)))
        (copy-file runtime-path port)
        (copy-file awi-path port)
        (for-each (lambda (definition) (write-definition definition port))
                  (module-definitions libraries module procedures entries))
        (display ")\n" port)))

    (define (module-definitions libraries module procedures entries)
      (append (map (lambda (entry) `(global ,(identifier "g" (cdr entry)) (mut eqref) (ref.null eq)))
                   (module-globals module))
              (map (lambda (entry) `(global ,(cdr entry) (mut eqref) (ref.null eq))) (module-constants module))
              (list `(elem declare func ,@(map (lambda (entry) (identifier "adapter" (cdr entry)))
                                               (module-functions module))
                           ,@(map (lambda (entry) (identifier "primitive" (cdr entry)))
                                  (numbered (module-primitive-names module)))))
              (map rust-wrapper (numbered (module-services module)))
              (map primitive-function (numbered (module-primitive-names module)))
              (map procedure-adapter (module-functions module)) procedures entries
              (list (module-entry libraries module))
              (library-exports (car (car (reverse libraries))) module)))
    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm)
    (import (snail-scheme test-utils))
    (begin
      (define (test-procedure parameters items result)
        (ir:make-lambda parameters #f (ir:make-block (append items (list result)) #f) #f))

      (define (test-binding-cells)
        (let* ((x (ir:make-value-definition 'x #f)) (reference (ir:make-name x #f))
               (capture (test-procedure '() '() reference))
               (immutable (test-procedure (list x) '() capture))
               (assigned (test-procedure (list x)
                                         (list (ir:make-assignment reference (ir:make-literal 1 #f) #f)) capture)))
          (expect (boxed-definitions (list immutable) '()) '())
          (expect (boxed-definitions (list assigned) '()) (list x))))

      (define (test-recursive-capture)
        (let* ((f (ir:make-value-definition 'f #f))
               (self (test-procedure '() '() (ir:make-name f #f)))
               (parent (test-procedure '() (list (ir:make-value-binding f self #f))
                                       (ir:make-name f #f))))
          (expect (boxed-definitions (list parent) '()) (list f))
          (expect (free-definitions self '()) (list f))
          (expect (free-definitions parent '()) '())))

      (define (test-primitive-rebinding)
        (let* ((plus (ir:make-value-definition '+ #f))
               (reference (ir:make-name plus #f))
               (assigned (ir:make-assignment reference reference #f)))
          (expect (immutable-primitives (list plus) '()) (list plus))
          (expect (immutable-primitives (list plus) (list assigned)) '())))

      (define (test-wasm)
        (run-test test-binding-cells)
        (run-test test-recursive-capture)
        (run-test test-primitive-rebinding))))))
