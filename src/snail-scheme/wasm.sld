;; Lower resolved IR directly into WebAssembly expressions. There is no second
;; compiler IR and no interpreter stack: parameters and temporaries are Wasm
;; locals, calls are Wasm calls, and tail positions use return_call/ref.
;;
;; Every lambda has an ordinary fixed-arity entry and a uniform closure adapter.
;; Known fixed workers avoid argument arrays; primitive adapters keep checked vectors.
;; Captures are GC references. Only assigned or early-captured locals need cells.
(define-library (snail-scheme wasm)
  (export ir-library->wasm write-wasm)
  (import (scheme base) (scheme cxr) (scheme write) (snail-scheme identity-map)
          (snail-scheme chromium-trace) (snail-scheme bootstrap)
          (snail-scheme types) (snail-scheme type-analysis) (snail-scheme partial-eval)
          (snail-scheme wasm-i32) (snail-scheme wasm-literals) (snail-scheme wasm-runtime) (snail-scheme wasm-awi)
          (prefix (snail-scheme ir) ir:) (prefix (snail-scheme library) library:))
  (begin

    ;; ---- Compilation state ----

    (define-record-type <module>
      (make-module globals primitives boxed functions known foreign constants analysis folds specialized result-guards)
      module?
      (globals module-globals) (primitives module-primitives)
      (boxed module-boxed) (functions module-functions) (known module-known)
      (foreign module-foreign) (constants module-constants)
      (analysis module-analysis) (folds module-folds)
      (specialized module-specialized) (result-guards module-result-guards))

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

    (define prepare-module
      (chromium-trace "prepare-module"
                      (lambda (libraries foreign)
                        (let* ((items (apply append (map library:library-body libraries)))
                               (globals (apply append (map library-global-definitions libraries)))
                               (primitives (immutable-primitives
                                            (apply append (map library-core-primitives libraries)) items))
                               (functions (numbered (all-lambdas items)))
                               (known (known-lambdas items (assigned-definitions items)))
                               (analysis ((chromium-trace "analyze-types" analyze-types) items primitives)))
                          (make-module (numbered globals) primitives
                                       (boxed-definitions items globals) functions known foreign (make-literal-pool) analysis
                                       (index-folds ((chromium-trace "partial-evaluate" partial-evaluate) items primitives analysis))
                                       (specialized-functions functions known globals primitives analysis)
                                       (numbered (unique-identities (map car (analysis-guards analysis)))))))))

    ;; Keep the first alist entry for each node, including false/null constants.
    ;; This map is queried only; source traversal still determines emission order.
    (define (index-folds folds)
      (let loop ((entries (reverse folds)) (index empty-identity-map))
        (if (null? entries) index
            (loop (cdr entries) (identity-map-set index (caar entries) (car entries))))))

    (define (specialized-functions functions known globals primitives analysis)
      (if (null? functions) '()
          (let* ((entry (car functions)) (binding (procedure-binding (car entry) known globals))
                 (code (specialize-i32 (car entry) (cdr entry) binding primitives analysis)))
            (append (if code (list (cons (car entry) code)) '())
                    (specialized-functions (cdr functions) known globals primitives analysis)))))

    (define (procedure-binding procedure known globals)
      (cond ((null? known) #f)
            ((and (eq? procedure (cdar known)) (memq (caar known) globals)) (caar known))
            (else (procedure-binding procedure (cdr known) globals))))

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
       ((ir:annotation? node) (list (ir:annotation-expression node)))
       ((ir:instantiation? node) (list (ir:instantiation-expression node)))
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

    (define (literal-value datum module)
      (literal-reference datum (module-constants module)))

    (define (integer-literal datum)
      (if (or (< datum -9223372036854775808) (> datum 9223372036854775807))
          (error "integer literal outside supported signed 64-bit range" datum))
      `(call $pack_integer (i64.const ,datum)))

    ;; Generated function datums use tokens shared by Scheme and WAT. Scheme's
    ;; writer quotes the symbol -inf, so spell that value with a Wasm operation.
    ;; These expressions run in function bodies, never constant initializers.
    (define (float-expression number)
      (let ((text (number->string number)))
        (cond ((equal? text "+nan.0") '(f64.const nan))
              ((equal? text "+inf.0") '(f64.const inf))
              ((equal? text "-inf.0") '(f64.neg (f64.const inf)))
              (else `(f64.const ,number)))))

    (define (text-expression text)
      `(array.new_fixed $text ,(string-length text)
                        ,@(map (lambda (character) `(i32.const ,(char->integer character)))
                               (string->list text))))

    ;; ---- Structured expressions ----

    (define (single node context)
      (let ((value (expression node context #f)))
        (if (and (type-optimizations-enabled)
                 (fact-single? (analysis-fact (module-analysis (function-module context)) node)))
            value `(call $single ,value))))

    ;; #f denotes an ordinary expression; a list denotes tail position and its
    ;; pending source assertions, innermost first. Keep these checks in the
    ;; emitter until a procedure call actually needs to transfer them.
    (define (expression node context checks)
      (let ((guard (analysis-guard (module-analysis (function-module context)) node)))
        (cond (checks (raw-expression node context (if guard (cons node checks) checks)))
              (guard (guard-value (raw-expression node context #f) guard context))
              (else (raw-expression node context #f)))))

    (define (raw-expression node context checks)
      (cond ((identity-map-ref (module-folds (function-module context)) node #f)
             => (lambda (entry) (finish-expression (literal-value (cdr entry) (function-module context)) checks context)))
            ((ir:block? node) (sequence-expression (ir:block-items node) context checks))
            ((ir:conditional? node) (conditional-expression node context checks))
            ((ir:annotation? node) (expression (ir:annotation-expression node) context checks))
            ((ir:instantiation? node) (expression (ir:instantiation-expression node) context checks))
            ((ir:application? node) (application-expression node context checks))
            (else (finish-expression (leaf-expression node context) checks context))))

    (define (finish-expression value checks context)
      (if (or (not checks) (null? checks)) value
          (finish-expression
           (guard-value value (analysis-guard (module-analysis (function-module context)) (car checks)) context)
           (cdr checks) context)))

    (define (call-checks checks)
      (if checks '(local.get $checks) '(ref.null $result_context)))

    (define (leaf-expression node context)
      (cond ((ir:literal? node) (literal-value (ir:literal-value node) (function-module context)))
            ((ir:name? node) (read-binding (ir:name-definition node) context))
            ((ir:lambda? node) (closure-expression node context))
            ((ir:type-declaration? node) '(global.get $unspecified))
            ((ir:record-schema? node) '(global.get $unspecified))
            ((ir:value-binding? node)
             (store-binding (ir:value-binding-definition node)
                            (single (ir:value-binding-initializer node) context) context))
            ((ir:assignment? node)
             (store-binding (ir:name-definition (ir:assignment-target node))
                            (single (ir:assignment-value node) context) context))
            (else (error "unknown IR expression" node))))

    (define (sequence-expression items context checks)
      (cond ((null? items) (finish-expression '(global.get $unspecified) checks context))
            ((null? (cdr items)) (expression (car items) context checks))
            (else
             (let* ((first (expression (car items) context #f))
                    (rest (sequence-expression (cdr items) context checks)))
               `(block (result eqref) (drop ,first) ,rest)))))

    (define (conditional-expression node context checks)
      (let* ((test (single (ir:conditional-test node) context))
             (yes (expression (ir:conditional-consequent node) context checks))
             (no (if (ir:conditional-opt-alternate node)
                     (expression (ir:conditional-opt-alternate node) context checks)
                     (finish-expression '(global.get $unspecified) checks context))))
        `(if (result eqref) (call $truthy ,test) (then ,yes) (else ,no))))

    (define (closure-expression node context)
      (let* ((module (function-module context))
             (index (cdr (assq node (module-functions module))))
             (free (free-definitions node (module-globals module))))
        `(struct.new $closure (ref.func ,(identifier "adapter" index))
                     (array.new_fixed $vector ,(length free)
                                      ,@(map (lambda (definition)
                                               (read-place (binding-place definition context))) free)))))

    ;; ---- Enforced type boundaries ----

    (define (result-guard-name node module)
      (identifier "result_guard" (cdr (assq node (module-result-guards module)))))

    ;; A static site is the identity, not an unordered type union. Its recipe
    ;; reads nominal descriptors only when executed, after the result arrives.
    (define (result-guard-function entry module)
      (let* ((context (make-function module '() '()))
             (guard (analysis-guard (module-analysis module) (car entry)))
             (body (guard-value '(local.get $value) guard context)))
        `(func ,(identifier "check_result" (cdr entry)) (type $result_guard_fn)
               (param $value eqref) (result eqref) ,@(function-locals context) ,body)))

    (define (result-guard-global entry)
      `(global ,(identifier "result_guard" (cdr entry)) (ref $result_guard)
               (struct.new $result_guard (ref.func ,(identifier "check_result" (cdr entry))))))

    ;; Checked entries enforce domains before boxing, including unknown callers
    ;; through closure adapters. Direct calls bypass them only with proved domains.
    ;; Expression guards also normalize counts. Types never prove initialization.
    (define (guard-value value type context)
      (let ((temporary (temporary! context)))
        `(block (result eqref) (local.set ,temporary (call $single ,value))
                (if (i32.eqz ,(type-test type `(local.get ,temporary) context))
                    (then (call $fail (i32.const 8))))
                (local.get ,temporary))))

    (define (parameter-guards procedure context)
      (let ((signature (analysis-signature (module-analysis (function-module context)) procedure)))
        (if (not signature) '()
            (map (lambda (definition type)
                   (let ((name (caddr (binding-place definition context))))
                     `(local.set ,name ,(guard-value `(local.get ,name) type context))))
                 (ir:lambda-parameters procedure) (type-arguments (type-erasure signature))))))

    (define (union-test members value context)
      (if (null? members) '(i32.const 0)
          `(i32.or ,(type-test (car members) value context) ,(union-test (cdr members) value context))))

    (define (type-test type value context)
      (cond ((union-type? type) (union-test (cdr type) value context))
            ((nominal-type? type)
             `(if (result i32) (ref.test (ref $record) ,value)
                  (then (ref.eq (struct.get $record 0 (ref.cast (ref $record) ,value))
                                ,(read-binding (cadr type) context))) (else (i32.const 0))))
            ((memq type '(Any ?)) '(i32.const 1))
            ((eq? type 'Never) '(i32.const 0))
            ((eq? type 'ExactInteger) `(call $is_integer ,value))
            ((eq? type 'i32)
             `(if (result i32) (ref.test (ref i31) ,value) (then (i32.const 1))
                  (else (if (result i32) (ref.test (ref $integer) ,value)
                            (then (i64.le_u (i64.add (struct.get $integer 0 (ref.cast (ref $integer) ,value))
                                                     (i64.const 2147483648)) (i64.const 4294967295)))
                            (else (i32.const 0))))))
            ((memq type '(False True Null Unspecified))
             `(ref.eq ,value (global.get ,(case type ((False) '$false) ((True) '$true)
                                                ((Null) '$nil) (else '$unspecified)))))
            ((memq type '(String Symbol))
             `(call $truthy (call $is_text_kind ,value (i32.const ,(if (eq? type 'String) 0 1)))))
            ((eq? type 'Boolean) `(call $truthy (call $is_boolean ,value)))
            ((eq? type 'Number) `(call $truthy (call $is_number ,value)))
            ((eq? type 'Char) `(call $truthy (call $is_character ,value)))
            (else `(ref.test (ref ,(case type
                                     ((InexactReal) '$float) ((Pair) '$pair) ((Vector) '$vector)
                                     ((Bytevector) '$bytevector) ((Procedure) '$closure) ((Record) '$record)
                                     (else (error "no runtime type test" type)))) ,value))))

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

    (define (application-expression node context checks)
      (let* ((primitive (typed-primitive node (function-module context)))
             (operands (ir:application-operands node)))
        (if primitive
            (finish-expression `(call ,primitive ,@(map (lambda (operand) (single operand context)) operands)) checks context)
            (procedure-call node context checks))))

    ;; Select a check-free category path only from facts at this exact operand.
    ;; Integer representation tests and arithmetic overflow remain in the helper.
    (define (typed-primitive node module)
      (let ((primitive (direct-primitive node module)))
        (cond ((not (type-optimizations-enabled)) primitive)
              ((and (memq primitive '($add $subtract $numeric_equal $less $less_equal $greater $greater_equal))
                    (integer-operands? (ir:application-operands node) (module-analysis module)))
               (let ((name (symbol->string primitive)))
                 (string->symbol (string-append "$integer_" (substring name 1 (string-length name))))))
              (else (or (typed-object-primitive node module) primitive)))))

    (define (typed-object-primitive node module)
      (let ((operator (ir:application-operator node)) (operands (ir:application-operands node)))
        (and (ir:name? operator) (memq (ir:name-definition operator) (module-primitives module))
             (case (ir:value-definition-name (ir:name-definition operator))
               ((string-length)
                (and (= (length operands) 1)
                     (type-subtype? (fact-type (analysis-fact (module-analysis module) (car operands))) 'String)
                     '$known_string_length))
               ((%record-ref) (and (proved-record-access? operands module) '$known_record_ref))
               (else #f)))))

    (define (proved-record-access? operands module)
      (and (= (length operands) 3) (ir:name? (car operands))
           (type-subtype? (fact-type (analysis-fact (module-analysis module) (caddr operands)))
                          (list 'record (ir:name-definition (car operands))))))

    (define (integer-operands? operands analysis)
      (or (null? operands)
          (and (type-subtype? (fact-type (analysis-fact analysis (car operands))) 'ExactInteger)
               (integer-operands? (cdr operands) analysis))))

    ;; Bind operands before the operator, retaining the established evaluation
    ;; order even though a direct call puts its closure environment first.
    (define (procedure-call node context checks)
      (let* ((operands (ir:application-operands node))
             (arguments (map (lambda (node) (temporary! context)) operands))
             (operator (temporary! context))
             (procedure (known-procedure node (function-module context)))
             (arguments-code (map (lambda (name operand) `(local.set ,name ,(single operand context)))
                                  arguments operands))
             (operator-code (single (ir:application-operator node) context)))
        `(block (result eqref) ,@arguments-code
                (local.set ,operator ,operator-code)
                ,@(call-guards node arguments context)
                ,(call-expression procedure operator arguments context checks node))))

    (define (call-guards node arguments context)
      (let* ((analysis (module-analysis (function-module context)))
             (guards (analysis-call-guards analysis node)))
        (if (null? guards) '()
            (apply append
                   (map (lambda (name operand type)
                          (if (or (not type) (and (type-optimizations-enabled)
                                                  (type-subtype? (fact-type (analysis-fact analysis operand)) type))) '()
                                                  (list `(local.set ,name ,(guard-value `(local.get ,name) type context)))))
                        arguments (ir:application-operands node) guards)))))

    (define (call-expression procedure operator arguments context checks node)
      (let ((call (procedure-invocation procedure operator arguments context checks node)))
        (cond ((not checks) call)
              ((null? checks) (cons 'return_call (cdr call)))
              (else (guarded-tail-call call checks (function-module context))))))

    (define (procedure-invocation procedure operator arguments context checks node)
      (if (and procedure (not (ir:lambda-opt-rest-parameter procedure))
               (= (length arguments) (length (ir:lambda-parameters procedure))))
          `(call
            ,(call-worker procedure node (function-module context))
            (struct.get $closure 1 (ref.cast (ref $closure) (local.get ,operator)))
            ,@(map (lambda (name) `(local.get ,name)) arguments) ,(call-checks checks))
          (adapter-invocation node operator arguments context checks)))

    ;; Core bindings are initialized before Scheme code runs. The primitive
    ;; list excludes source initializers and assignments of those definitions,
    ;; including imported aliases; their immutable closure code stays known.
    ;; Keep the actual operator, argument vector, and result-check context.
    (define (known-primitive-adapter node module)
      (let ((operator (ir:application-operator node)))
        (and (ir:name? operator)
             (memq (ir:name-definition operator) (module-primitives module))
             (let loop ((names bootstrap-primitive-names) (index 0))
               (cond ((null? names) #f)
                     ((eq? (car names) (ir:value-definition-name (ir:name-definition operator)))
                      (identifier "primitive" index))
                     (else (loop (cdr names) (+ index 1))))))))

    (define (adapter-invocation node operator arguments context checks)
      (let ((adapter (known-primitive-adapter node (function-module context))))
        `(call ,(or adapter '$apply)
               ,(if adapter `(struct.get $closure 1 (ref.cast (ref $closure) (local.get ,operator)))
                    `(local.get ,operator))
               (array.new_fixed $vector ,(length arguments)
                                ,@(map (lambda (name) `(local.get ,name)) arguments)) ,(call-checks checks))))

    ;; The first guarded transfer owns one suspended frame. Its shared context
    ;; sees guards added by deeper tail calls; only this owner drains the list.
    ;; Ordinary subcalls receive null, and no state escapes into Scheme values.
    (define (guarded-tail-call call checks module)
      (let ((register (defer-result-checks checks module)))
        `(block (result eqref)
                (if (ref.is_null (local.get $checks))
                    (then (local.set $checks (struct.new $result_context (ref.null $result_checks)))
                          ,@register
                          (return_call $finish_result ,call
                                       (struct.get $result_context 0 (ref.as_non_null (local.get $checks))))))
                ,@register
                (return_call ,@(cdr call)))))

    (define (defer-result-checks checks module)
      (map (lambda (node)
             `(struct.set $result_context 0 (ref.as_non_null (local.get $checks))
                          (call $defer_result_check
                                (struct.get $result_context 0 (ref.as_non_null (local.get $checks)))
                                (global.get ,(result-guard-name node module)))))
           (reverse checks)))

    (define (call-worker procedure node module)
      (let ((signature (type-erasure (analysis-signature (module-analysis module) procedure)))
            (index (cdr (assq procedure (module-functions module)))))
        (identifier (if (and signature (not (proved-arguments? node signature module)))
                        "checked" "function") index)))

    (define (proved-arguments? node signature module)
      (and (type-optimizations-enabled)
           (let loop ((operands (ir:application-operands node)) (types (type-arguments signature)))
             (or (null? operands)
                 (and (or (memq (car types) '(? Any))
                          (type-subtype? (fact-type (analysis-fact (module-analysis module) (car operands)))
                                         (car types)))
                      (loop (cdr operands) (cdr types)))))))

    ;; ---- Procedure definitions ----

    (define generate-procedure-functions
      (chromium-trace "generate-procedure-functions"
                      (lambda (module)
                        (map (lambda (entry) (procedure-function entry module)) (module-functions module)))))

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
      (if (assq (car entry) (module-specialized module)) (i32-bridge entry module)
          (ordinary-procedure-function entry module)))

    (define (i32-bridge entry module)
      (let* ((procedure (car entry)) (context (make-function module (procedure-environment procedure module) '()))
             (names (map (lambda (definition) (caddr (binding-place definition context)))
                         (ir:lambda-parameters procedure))))
        `(func ,(identifier "function" (cdr entry)) (param $env eqref)
               ,@(map (lambda (name) `(param ,name eqref)) names)
               (param $checks (ref null $result_context)) (result eqref)
               (call $pack_integer (i64.extend_i32_s
                                    (call ,(identifier "i32_" (cdr entry))
                                          ,@(map (lambda (name) `(i32.wrap_i64
                                                                  (call $known_integer_value (local.get ,name)))) names)))))))

    (define (ordinary-procedure-function entry module)
      (let* ((procedure (car entry)) (parameters (lambda-arguments procedure))
             (locals (lambda-locals procedure))
             (context (make-function module (procedure-environment procedure module) '()))
             (body (expression (ir:lambda-body procedure) context '())))
        `(func ,(identifier "function" (cdr entry)) (param $env eqref)
               ,@(map (lambda (definition) `(param ,(caddr (binding-place definition context)) eqref)) parameters)
               (param $checks (ref null $result_context))
               (result eqref)
               ,@(map (lambda (definition) `(local ,(caddr (binding-place definition context)) eqref))
                      (list-tail locals (length parameters)))
               ,@(function-locals context)
               ,@(initialize-locals locals parameters context) ,body)))

    (define (procedure-checked-entry entry module)
      (let* ((procedure (car entry)) (context (make-function module (procedure-environment procedure module) '()))
             (names (map (lambda (definition) (caddr (binding-place definition context)))
                         (ir:lambda-parameters procedure)))
             (guards (parameter-guards procedure context)))
        `(func ,(identifier "checked" (cdr entry)) (param $env eqref)
               ,@(map (lambda (name) `(param ,name eqref)) names)
               (param $checks (ref null $result_context)) (result eqref)
               ,@(function-locals context) ,@guards
               (return_call ,(identifier "function" (cdr entry)) (local.get $env)
                            ,@(map (lambda (name) `(local.get ,name)) names) (local.get $checks)))))

    (define (procedure-adapter entry module)
      (let* ((procedure (car entry)) (count (length (ir:lambda-parameters procedure)))
             (rest? (ir:lambda-opt-rest-parameter procedure)))
        `(func ,(identifier "adapter" (cdr entry)) (type $call)
               (param $env eqref) (param $arguments (ref $vector))
               (param $checks (ref null $result_context)) (result eqref)
               (call $arity (local.get $arguments) (i32.const ,count) (i32.const ,(if rest? 1 0)))
               (return_call ,(identifier (if (analysis-signature (module-analysis module) procedure)
                                             "checked" "function") (cdr entry)) (local.get $env)
                                             ,@(map (lambda (entry) `(array.get $vector (local.get $arguments)
                                                                                (i32.const ,(cdr entry))))
                                                    (numbered (ir:lambda-parameters procedure)))
                                             ,@(if rest? `((call $rest (local.get $arguments) (i32.const ,count))) '())
                                             (local.get $checks)))))

    ;; ---- Library entries ----

    (define generate-library-functions
      (chromium-trace "generate-library-functions"
                      (lambda (libraries module)
                        (map (lambda (entry) (library-function entry module)) libraries))))

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
               (param $env eqref) (param $arguments (ref $vector))
               (param $checks (ref null $result_context)) (result eqref)
               ,(if (memq (car entry) '(apply call-with-values))
                    `(return_call ,name (local.get $arguments) (local.get $checks))
                    `(return_call ,name (local.get $arguments))))))

    (define (global-initializer slot)
      `(global.set ,(identifier "g" (car slot))
                   (struct.new $closure (ref.func ,(identifier "primitive" (cdr slot)))
                               (array.new_fixed $vector 0))))

    (define (module-entry libraries module)
      `(func $program (export "snail_main") (result eqref)
             ,@(map global-initializer (library-primitive-slots libraries module))
             ,@(map (lambda (entry) `(drop (call ,(identifier "library" (cdr entry)))))
                    (reverse (cdr (reverse libraries))))
             (call ,(identifier "library" (cdr (car (reverse libraries)))))))

    ;; A CLI entry is selected explicitly by the build. A script adapter ignores
    ;; the final expression's value; defining a helper named main has no effect.
    ;; Initialization and the handler run once inside this one platform call.
    (define (cli-entry root module name)
      (let ((definition (and name (find-definition name (item-definitions (library:library-body root))))))
        (if (and name (not definition)) (error "CLI handler is not defined" name))
        `(func (export "snail:main") (param $arguments i32) (result i32)
               (local $args (ref $vector))
               (local.set $args (ref.cast (ref $vector) (call $awi_get (local.get $arguments))))
               (call $arity (local.get $args) (i32.const 0) (i32.const 0))
               (drop (call $program))
               (call $awi_root ,(if definition
                                    `(call $apply ,(read-binding definition (make-function module '() '()))
                                           (local.get $args) (ref.null $result_context))
                                    '(ref.i31 (i32.const 0)))))))

    (define (find-definition name definitions)
      (cond ((null? definitions) #f)
            ((eq? name (ir:value-definition-name (car definitions))) (car definitions))
            (else (find-definition name (cdr definitions)))))

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
      '(%eqv-hash %equal-hash %string-hash %string-ci-hash
                  acos asin atan cos exp finite? infinite? log nan? sin sqrt tan
                  string->number number->string char-ci=? char-alphabetic? char-numeric? char-whitespace?
                  error open-input-file open-output-file open-binary-input-file file-exists? close-port
                  read-char read-string read-bytevector bytevector-copy bytevector-append utf8->string string->utf8
                  open-output-string get-output-string display write newline
                  %current-input-port %current-output-port %current-error-port
                  %set-current-input-port! %set-current-output-port! %set-current-error-port!
                  command-line exit get-environment-variable find-artifact current-jiffy jiffies-per-second string-contains))

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

    ;; Function datums are acyclic, contain generated identifiers, and quote
    ;; only fixed export names. Let the host traverse each complete definition:
    ;; Chibi's write-simple is native and avoids write's per-number temporary
    ;; strings and graph tables; Snail's writer traverses the datum in Rust.
    ;; Import names are the only user-supplied strings at this boundary. WAT's
    ;; byte escapes differ from Scheme's, so format just those leaves here.
    (define (write-wat-string text port)
      (display "\"" port)
      (let ((bytes (string->utf8 text)))
        (let loop ((index 0))
          (if (< index (bytevector-length bytes))
              (begin (write-wat-byte (bytevector-u8-ref bytes index) port)
                     (loop (+ index 1))))))
      (display "\"" port))

    (define (write-wat-byte byte port)
      (if (and (<= 32 byte 126) (not (memv byte '(34 92))))
          (display (integer->char byte) port)
          (begin (display "\\" port)
                 (if (< byte 16) (display "0" port))
                 (display (number->string byte 16) port))))

    (define (write-import definition port)
      (display "(import " port)
      (write-wat-string (cadr definition) port) (display " " port)
      (write-wat-string (caddr definition) port) (display " " port)
      (write-simple (cadddr definition) port) (display ")" port))

    (define (write-definition definition port)
      (cond ((eq? (car definition) 'import) (write-import definition port))
            ((negative-infinity? definition) (write-with-infinity definition port))
            (else (write-simple definition port)))
      (newline port))

    ;; Scheme quotes the WAT token -inf as a symbol. Only definitions containing
    ;; that exceptional leaf need a Scheme walk; the ordinary path stays native.
    (define (negative-infinity? datum)
      (cond ((pair? datum) (or (negative-infinity? (car datum)) (negative-infinity? (cdr datum))))
            ((symbol? datum) (eq? datum (string->symbol "-inf")))
            (else #f)))

    (define (write-with-infinity datum port)
      (cond ((pair? datum)
             (display "(" port)
             (write-with-infinity (car datum) port)
             (for-each (lambda (item) (display " " port) (write-with-infinity item port)) (cdr datum))
             (display ")" port))
            ((eq? datum (string->symbol "-inf")) (display "-inf" port))
            (else (write-simple datum port))))

    (define write-wasm
      (chromium-trace "write-wasm" (lambda (datum port)
                                     (display "(module\n" port)
                                     (for-each (lambda (definition) (write-definition definition port)) (cdr datum))
                                     (display ")\n" port))))

    ;; Both backends receive these same datums. Runtime definitions are quoted
    ;; data, shared without mutation; no backend has to read or reparse WAT.
    (define ir-library->wasm
      (chromium-trace "ir-library->wasm" (lambda (root . options)
                                           (let* ((libraries (numbered (library:library-dependency-order root)))
                                                  (module (prepare-module (map car libraries) (if (null? options) '() (car options))))
                                                  (procedures (generate-procedure-functions module))
                                                  (entries (generate-library-functions libraries module))
                                                  (program (module-entry libraries module)))
                                             (cons 'module
                                                   (append '((import "snail.rust" "snail:fail" (func $rust_fail (param i32) (result i32)))
                                                             (import "snail.host" "register-finalizer"
                                                                     (func $host_register_finalizer (param eqref i32 i32)))
                                                             (import "snail.host" "hash-identity" (func $host_hash_identity (param eqref) (result i32))))
                                                           (map rust-import (numbered (module-services module)))
                                                           runtime-definitions awi-definitions
                                                           (module-definitions libraries module procedures entries program)
                                                           (if (and (pair? options) (pair? (cdr options)))
                                                               (list (cli-entry root module (cadr options))) '())))))))

    (define (module-definitions libraries module procedures entries program)
      (append (map (lambda (entry) `(global ,(identifier "g" (cdr entry)) (mut eqref) (ref.null eq)))
                   (module-globals module))
              (literal-declarations (module-constants module))
              (map result-guard-global (module-result-guards module))
              (list `(elem declare func ,@(map (lambda (entry) (identifier "adapter" (cdr entry)))
                                               (module-functions module))
                           ,@(map (lambda (entry) (identifier "primitive" (cdr entry)))
                                  (numbered (module-primitive-names module)))
                           ,@(map (lambda (entry) (identifier "check_result" (cdr entry)))
                                  (module-result-guards module))))
              (map (lambda (entry) (result-guard-function entry module)) (module-result-guards module))
              (map rust-wrapper (numbered (module-services module)))
              (map primitive-function (numbered (module-primitive-names module)))
              (map (lambda (entry) (procedure-adapter entry module)) (module-functions module))
              (typed-entries (module-functions module) module) procedures entries
              (map cdr (module-specialized module))
              (list program)))

    (define (typed-entries entries module)
      (if (null? entries) '()
          (append (if (analysis-signature (module-analysis module) (caar entries))
                      (list (procedure-checked-entry (car entries) module)) '())
                  (typed-entries (cdr entries) module))))
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

      ;; Emission allocates identities. Host quasiquote evaluation order must
      ;; never determine the numbering of source literals or temporaries.
      (define (emitted-literal-references node values)
        (let* ((pool (make-literal-pool))
               (module (make-module '() '() '() '() '() '() pool
                                    (analyze-types '() '()) (index-folds '()) '() '()))
               (context (make-function module '() '())))
          (expression node context #f)
          (map (lambda (value) (literal-reference value pool)) values)))

      (define (test-emission-order)
        (define (literal text) (ir:make-literal text #f))
        (let ((a (string #\a)) (b (string #\b)) (c (string #\c)))
          (expect (emitted-literal-references (ir:make-block (list (literal a) (literal b)) #f) (list a b))
                  '((global.get $literal0) (global.get $literal1)))
          (expect (emitted-literal-references (ir:make-conditional (literal a) (literal b) (literal c) #f) (list a b c))
                  '((global.get $literal0) (global.get $literal1) (global.get $literal2)))
          (expect (emitted-literal-references (ir:make-application (literal c) (list (literal a) (literal b)) #f) (list a b c))
                  '((global.get $literal0) (global.get $literal1) (global.get $literal2)))))

      (define (test-wat-leaves)
        (let ((port (open-output-string)))
          (write-import `(import ,(string #\" #\\ #\newline #\λ (integer->char 0)) "f"
                                 (func $f (param i32))) port)
          (expect (get-output-string port)
                  "(import \"\\22\\5c\\0a\\ce\\bb\\00\" \"f\" (func $f (param i32)))"))
        (expect (float-expression (string->number "-inf.0")) '(f64.neg (f64.const inf)))
        (expect (float-expression (string->number "+inf.0")) '(f64.const inf))
        (expect (float-expression (string->number "+nan.0")) '(f64.const nan)))

      (define (test-fold-index)
        (let* ((first (ir:make-literal 1 #f)) (second (ir:make-literal 1 #f))
               (folds (list (cons first #f) (cons second '()) (cons first 42)))
               (index (index-folds folds)))
          (expect (identity-map-ref index first #f) (car folds))
          (expect (identity-map-ref index second #f) (cadr folds))
          (expect (identity-map-ref index (ir:make-literal 1 #f) #f) #f)
          (expect (map cdr folds) '(#f () 42))))

      (define (test-wasm)
        (run-test test-binding-cells)
        (run-test test-recursive-capture)
        (run-test test-primitive-rebinding)
        (run-test test-fold-index)
        (run-test test-emission-order)
        (run-test test-wat-leaves))))))
