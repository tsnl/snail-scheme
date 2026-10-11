;; Resolve the compiler's folded Wasm datums for native lowering. This is not
;; a general WAT parser or validator: unsupported module shapes fail explicitly.
(define-library (snail-scheme wasm-resolve)
  (export resolve-wasm lower-wasm-body)
  (import (scheme base) (scheme cxr) (scheme hash-table))
  (begin

    ;; ---- Module names and canonical types ----

    (define-record-type <space>
      (make-space names count) space?
      (names space-names) (count space-count set-space-count!))

    (define-record-type <context>
      (make-context types aliases functions globals tables indices) context?
      (types context-types set-context-types!)
      (aliases context-aliases set-context-aliases!)
      (functions context-functions) (globals context-globals) (tables context-tables)
      (indices context-indices))

    (define-record-type <body>
      (make-body forms context locals name) body?
      (forms body-forms) (context body-context) (locals body-locals) (name body-name))

    (define (identifier? value)
      (and (symbol? value)
           (let ((text (symbol->string value)))
             (and (> (string-length text) 0) (char=? (string-ref text 0) #\$)))))

    (define (node-name node)
      (and (pair? (cdr node)) (identifier? (cadr node)) (cadr node)))

    (define (node-fields node)
      (if (node-name node) (cddr node) (cdr node)))

    (define (register-name! space name)
      (let ((index (space-count space)))
        (when name
          (when (hash-table-ref/default (space-names space) name #f) (error "duplicate Wasm name" name))
          (hash-table-set! (space-names space) name index))
        (set-space-count! space (+ index 1))
        index))

    (define (index-of space name)
      (if (integer? name)
          (if (<= 0 name (- (space-count space) 1)) name (error "Wasm index out of range" name))
          (let ((entry (hash-table-ref/default (space-names space) name #f)))
            (if entry entry (error "unknown Wasm name" name)))))

    (define (type-index context name)
      (let ((entry (assq name (context-aliases context))))
        (if entry (cdr entry) (error "unknown or forward Wasm type" name))))

    (define (heap-type value context self)
      (cond ((and self (eq? value self)) 'self)
            ((identifier? value) (type-index context value))
            ((memq value '(any eq i31 struct array func none nofunc)) value)
            (else (error "unsupported Wasm heap type" value))))

    (define (resolve-type value context self)
      (cond ((memq value '(i32 i64 f32 f64 i8 i16)) value)
            ((eq? value 'eqref) '(ref null eq))
            ((eq? value 'funcref) '(ref null func))
            ((eq? value 'anyref) '(ref null any))
            ((and (pair? value) (eq? (car value) 'mut) (= (length value) 2))
             (list 'mut (resolve-type (cadr value) context self)))
            ((and (pair? value) (eq? (car value) 'ref))
             (cond ((= (length value) 2) (list 'ref (heap-type (cadr value) context self)))
                   ((and (= (length value) 3) (eq? (cadr value) 'null))
                    (list 'ref 'null (heap-type (caddr value) context self)))
                   (else (error "invalid Wasm reference type" value))))
            (else (error "unsupported Wasm value type" value))))

    (define (declarations fields tag)
      (let loop ((rest fields) (found '()))
        (cond ((null? rest) (reverse found))
              ((and (pair? (car rest)) (eq? (caar rest) tag))
               (loop (cdr rest) (cons (car rest) found)))
              (else (loop (cdr rest) found)))))

    (define (declaration-types fields tag context self)
      (apply append
             (map (lambda (node)
                    (map (lambda (type) (resolve-type type context self)) (node-fields node)))
                  (declarations fields tag))))

    (define (signature fields context self)
      (let ((results (declaration-types fields 'result context self)))
        (when (> (length results) 1) (error "native multivalue Wasm signatures are unsupported"))
        (list 'func (declaration-types fields 'param context self) results)))

    (define (composite-type node context self)
      (case (car node)
        ((func) (signature (cdr node) context self))
        ((struct) (cons 'struct (declaration-types (cdr node) 'field context self)))
        ((array) (unless (= (length node) 2) (error "invalid Wasm array type" node))
         (list 'array (resolve-type (cadr node) context self)))
        (else (error "unsupported Wasm composite type" node))))

    ;; Each emitted type is a final singleton recursion group. Canonical keys
    ;; replace the group's own reference with self and earlier references with
    ;; canonical indices. Equal keys share one identity, including self cycles.
    ;; Explicit rec groups, forward references and subtyping are not generated.
    (define (intern-type! context definition)
      (let ((found (assoc definition (context-types context))))
        (if found (cdr found)
            (let ((index (length (context-types context))))
              (set-context-types! context (cons (cons definition index) (context-types context)))
              index))))

    (define (register-type! context node)
      (unless (and (= (length node) 3) (node-name node)) (error "expected a named Wasm type" node))
      (let ((name (cadr node)))
        (when (assq name (context-aliases context)) (error "duplicate Wasm type" name))
        (let ((index (intern-type! context (composite-type (caddr node) context name))))
          (set-context-aliases! context (cons (cons name index) (context-aliases context))))))

    (define (replace-self value index)
      (cond ((eq? value 'self) index)
            ((pair? value) (map (lambda (item) (replace-self item index)) value))
            (else value)))

    (define (type-declarations context)
      (map (lambda (entry) (list 'type (cdr entry) (replace-self (car entry) (cdr entry))))
           (reverse (context-types context))))

    ;; ---- Declarations and function headers ----

    (define (declaration-space context tag)
      (case tag ((func) (context-functions context)) ((global) (context-globals context))
            ((table) (context-tables context))
            (else (error "unsupported Wasm index space" tag))))

    (define (register-declaration! context node)
      (cond ((eq? (car node) 'import) (register-declaration! context (cadddr node)))
            ((memq (car node) '(func global table))
             (let ((index (register-name! (declaration-space context (car node)) (node-name node))))
               (hash-table-set! (context-indices context) node index)))))

    (define (declaration-index context node)
      (hash-table-ref (context-indices context) node))

    (define (inline-exports node index)
      (map (lambda (entry) (list 'export (cadr entry) (list (car node) index)))
           (declarations (node-fields node) 'export)))

    (define (function-forms fields)
      (if (and (pair? fields) (pair? (car fields))
               (memq (caar fields) '(type param result local export)))
          (function-forms (cdr fields)) fields))

    (define (function-locals fields)
      (let ((space (make-space (make-hash-table eq?) 0)))
        (for-each
         (lambda (node)
           (when (and (node-name node) (not (= (length (node-fields node)) 1)))
             (error "named Wasm local requires one type" node))
           (for-each (lambda (type) (register-name! space (node-name node))) (node-fields node)))
         (append (declarations fields 'param) (declarations fields 'local)))
        space))

    (define (function-signature fields context)
      (let* ((definition (signature fields context #f)) (uses (declarations fields 'type))
             (index (intern-signature! context definition)))
        (when (pair? uses)
          (unless (and (= (length uses) 1) (= index (type-index context (cadar uses))))
            (error "Wasm function type use does not match signature" fields)))
        index))

    (define (intern-signature! context definition)
      (let loop ((types (reverse (context-types context))))
        (cond ((null? types) (intern-type! context definition))
              ((equal? definition (replace-self (caar types) (cdar types))) (cdar types))
              (else (loop (cdr types))))))

    (define (resolve-function node context)
      (let* ((fields (node-fields node)) (index (declaration-index context node))
             (type (function-signature fields context)))
        (list 'func index type (declaration-types fields 'local context #f)
              (make-body (function-forms fields) context (function-locals fields) (node-name node)))))

    (define (function-names node context)
      (let ((name (node-name node)))
        (if (not name) '()
            (let ((text (symbol->string name)))
              (list (list 'function-name (declaration-index context node)
                          (substring text 1 (string-length text))))))))

    (define (resolve-global node context)
      (let* ((fields (node-fields node))
             (fields (if (and (pair? (car fields)) (eq? (caar fields) 'export)) (cdr fields) fields)))
        (list 'global (declaration-index context node) (resolve-type (car fields) context #f)
              (reverse (lower-expressions (cdr fields) context (make-space (make-hash-table eq?) 0) '() '())))))

    (define (resolve-table node context)
      (let* ((fields (node-fields node)) (minimum (car fields))
             (maximum (if (= (length fields) 3) (cadr fields) 4294967295))
             (type (resolve-type (car (reverse fields)) context #f)))
        (unless (and (<= 0 minimum maximum 4294967295) (pair? type) (eq? (cadr type) 'null))
          (error "unsupported Wasm table" node))
        (list 'table (declaration-index context node) minimum maximum type)))

    (define (resolve-declaration node context)
      (case (car node)
        ((type) '())
        ((import)
         (unless (eq? (car (cadddr node)) 'func) (error "expected a Wasm function import" node))
         (let ((function (resolve-function (cadddr node) context)))
           (list (list 'import (cadr node) (caddr node) (list 'func (cadr function) (caddr function))))))
        ((func) (append (list (resolve-function node context))
                        (inline-exports node (declaration-index context node)) (function-names node context)))
        ((global) (cons (resolve-global node context) (inline-exports node (declaration-index context node))))
        ((table) (list (resolve-table node context)))
        ((export) (let ((target (caddr node)))
                    (list (list 'export (cadr node)
                                (list (car target) (index-of (declaration-space context (car target)) (cadr target)))))))
        ((start) (list (list 'start (index-of (context-functions context) (cadr node)))))
        ((elem)
         (resolve-element node context))
        (else (error "unsupported generated Wasm declaration" node))))

    (define (resolve-element node context)
      (cond ((equal? (list (cadr node) (caddr node)) '(declare func))
             (for-each (lambda (name) (index-of (context-functions context) name)) (cdddr node)) '())
            ((and (pair? (cadr node)) (eq? (caadr node) 'table) (eq? (cadddr node) 'func))
             (list (list 'elem (index-of (context-tables context) (cadadr node))
                         (reverse (lower-expressions (list (caddr node)) context (make-space (make-hash-table eq?) 0) '() '()))
                         (map (lambda (name) (index-of (context-functions context) name)) (cddddr node)))))
            (else (error "unsupported Wasm element segment" node))))

    (define (resolve-wasm datum)
      (unless (and (pair? datum) (eq? (car datum) 'module)) (error "expected a Wasm module datum"))
      (let ((context (make-context '() '() (make-space (make-hash-table eq?) 0) (make-space (make-hash-table eq?) 0) (make-space (make-hash-table eq?) 0) (make-hash-table eq?))))
        (for-each (lambda (node) (register-type! context node)) (declarations (cdr datum) 'type))
        (for-each (lambda (node) (register-declaration! context node)) (cdr datum))
        (let ((nodes (apply append (map (lambda (node) (resolve-declaration node context)) (cdr datum)))))
          (append (type-declarations context) nodes))))

    ;; ---- Folded expressions to evaluated instruction order ----

    ;; Normalize one function at a time. Operands precede their instruction,
    ;; including effects and reads; LLVM's operand stack then holds SSA values.
    ;; A label enters scope for a control body's instructions, never its if test.
    (define (lower-wasm-body body)
      (reverse (cons '(end) (lower-expressions (body-forms body) (body-context body)
                                               (body-locals body) (list (body-name body)) '()))))

    (define (lower-expressions forms context locals labels output)
      (if (null? forms) output
          (lower-expressions (cdr forms) context locals labels
                             (lower-expression (car forms) context locals labels output))))

    (define (branch-index name labels)
      (if (integer? name)
          (if (<= 0 name (- (length labels) 1)) name (error "invalid Wasm branch depth" name))
          (let loop ((labels labels) (index 0))
            (cond ((null? labels) (error "unknown Wasm label" name))
                  ((eq? name (car labels)) index)
                  (else (loop (cdr labels) (+ index 1)))))))

    (define (control-parts node context)
      (let* ((fields (node-fields node))
             (result? (and (pair? fields) (pair? (car fields)) (eq? (caar fields) 'result))))
        (when (and result? (not (= (length (car fields)) 2)))
          (error "unsupported Wasm control result" (car fields)))
        (cons (if result? (resolve-type (cadar fields) context #f) 'void)
              (if result? (cdr fields) fields))))

    (define (lower-control node context locals labels output)
      (let* ((op (car node)) (parts (control-parts node context)) (type (car parts)) (forms (cdr parts))
             (inside (cons (node-name node) labels)))
        (if (eq? op 'if)
            (lower-if forms type context locals labels inside output)
            (cons '(end) (lower-expressions forms context locals inside (cons (list op type) output))))))

    (define (lower-if forms type context locals outside inside output)
      (unless (and (<= 2 (length forms) 3) (eq? (caadr forms) 'then))
        (error "unsupported folded Wasm if" forms))
      (let* ((output (lower-expression (car forms) context locals outside output))
             (output (lower-expressions (cdadr forms) context locals inside (cons (list 'if type) output))))
        (when (= (length forms) 3)
          (unless (eq? (caaddr forms) 'else) (error "expected Wasm else" forms))
          (set! output (lower-expressions (cdaddr forms) context locals inside (cons '(else) output))))
        (cons '(end) output)))

    (define (lower-expression value context locals labels output)
      (let ((node (if (symbol? value) (list value) value)))
        (if (memq (car node) '(block loop if)) (lower-control node context locals labels output)
            (let ((parts (operation-parts node context locals labels)))
              (cons (car parts) (lower-expressions (cdr parts) context locals labels output))))))

    (define (indexed-operation node index)
      (cons (list (car node) index) (cddr node)))

    (define (branch-table-parts args labels)
      (let loop ((args args) (targets '()))
        (if (and (pair? args) (not (pair? (car args))))
            (loop (cdr args) (cons (branch-index (car args) labels) targets))
            (if (null? targets) (error "Wasm branch table needs a default")
                (cons (cons 'br_table (cons (car targets) (reverse (cdr targets)))) args)))))

    (define (operation-parts node context locals labels)
      (let ((op (car node)) (args (cdr node)))
        (case op
          ((local.get local.set local.tee) (indexed-operation node (index-of locals (car args))))
          ((global.get global.set) (indexed-operation node (index-of (context-globals context) (car args))))
          ((call return_call ref.func) (indexed-operation node (index-of (context-functions context) (car args))))
          ((br br_if) (indexed-operation node (branch-index (car args) labels)))
          ((br_table) (branch-table-parts args labels))
          ((call_indirect return_call_indirect)
           (unless (and (pair? (cadr args)) (eq? (caadr args) 'type))
             (error "expected indirect call type use" node))
           (cons (list op (index-of (context-tables context) (car args))
                       (type-index context (cadadr args))) (cddr args)))
          ((call_ref return_call_ref struct.new struct.new_default array.new array.new_default array.get array.get_s array.get_u array.set)
           (indexed-operation node (type-index context (car args))))
          ((table.get table.set table.size table.grow) (indexed-operation node (index-of (context-tables context) (car args))))
          ((struct.get struct.get_s struct.get_u struct.set array.new_fixed)
           (cons (list op (type-index context (car args)) (cadr args)) (cddr args)))
          ((array.copy) (cons (list op (type-index context (car args)) (type-index context (cadr args))) (cddr args)))
          ((ref.test ref.cast) (cons (list op (resolve-type (car args) context #f)) (cdr args)))
          ((ref.null) (cons (list op (heap-type (car args) context #f)) (cdr args)))
          ((i32.const i64.const f64.const) (cons (list op (car args)) (cdr args)))
          ((unreachable nop drop return select ref.i31 i31.get_s i31.get_u ref.as_non_null ref.eq ref.is_null array.len)
           (cons (list op) args))
          (else (let ((entry (assq op numeric-operations)))
                  (if entry (cons (cdr entry) args) (error "unsupported generated Wasm instruction" op)))))))

    ;; ---- Numeric operation metadata ----

    ;; Entries retain the operation and operand count used by LLVM lowering.
    ;; There is no binary opcode table or text parsing on the instruction path.
    (define (numeric-family type operations count)
      (map (lambda (op) (cons (string->symbol (string-append type "." (symbol->string op)))
                              (list 'numeric type op count))) operations))

    (define numeric-operations
      (append
       (apply append
              (map (lambda (type)
                     (append (numeric-family type '(eqz clz ctz popcnt extend8_s extend16_s) 1)
                             (numeric-family type '(eq ne lt_s lt_u gt_s gt_u le_s le_u ge_s ge_u
                                                       add sub mul div_s div_u rem_s rem_u and or xor shl shr_s shr_u rotl rotr) 2)))
                   '("i32" "i64")))
       (apply append
              (map (lambda (type)
                     (append (numeric-family type '(abs neg ceil floor trunc nearest sqrt) 1)
                             (numeric-family type '(eq ne lt gt le ge add sub mul div copysign) 2)))
                   '("f32" "f64")))
       (numeric-family "i32" '(trunc_sat_f32_s trunc_sat_f32_u trunc_sat_f64_s trunc_sat_f64_u) 1)
       (numeric-family "i64" '(trunc_sat_f32_s trunc_sat_f32_u trunc_sat_f64_s trunc_sat_f64_u) 1)
       (numeric-family "i32" '(wrap_i64 trunc_f32_s trunc_f32_u trunc_f64_s trunc_f64_u reinterpret_f32) 1)
       (numeric-family "i64" '(extend_i32_s extend_i32_u trunc_f32_s trunc_f32_u trunc_f64_s trunc_f64_u reinterpret_f64 extend32_s) 1)
       (numeric-family "f32" '(convert_i32_s convert_i32_u convert_i64_s convert_i64_u demote_f64 reinterpret_i32) 1)
       (numeric-family "f64" '(convert_i32_s convert_i32_u convert_i64_s convert_i64_u promote_f32 reinterpret_i64) 1))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm-resolve)
    (import (snail-scheme test-utils))
    (begin
      (define (test-canonical-types)
        (expect
         (resolve-wasm '(module (type $a (struct (field (ref null $a))))
                                (type $b (struct (field (ref null $b))))
                                (type $c (struct (field (ref null $a))))
                                (type $d (struct (field (ref null $b))))
                                (type $bytes (array (mut i8)))
                                (type $words (array (mut i32)))))
         '((type 0 (struct (ref null 0))) (type 1 (struct (ref null 0)))
           (type 2 (array (mut i8))) (type 3 (array (mut i32)))))
        (let ((context (make-context '() '() #f #f #f (make-hash-table eq?))))
          (register-type! context '(type $f (func (param (ref $f)))))
          (expect (function-signature '((type $f) (param (ref $f))) context) 0)))

      (define (test-folded-order)
        (let* ((module (resolve-wasm
                        '(module (import "m" "f" (func $import (param i32) (result i32)))
                                 (func $f (param $x i32) (local $y i32) (result i32)
                                       (i32.add (local.get $x)
                                                (block (result i32) (local.set $x (i32.const 9))
                                                       (call $import (local.get $x))))))))
               (function (car (declarations module 'func))))
          (expect (cadr function) 1)
          (expect (lower-wasm-body (car (cddddr function)))
                  '((local.get 0) (block i32) (i32.const 9) (local.set 0) (local.get 0)
                    (call 0) (end) (numeric "i32" add 2) (end)))))

      (define (test-label-scope)
        (let* ((module (resolve-wasm
                        '(module (func $f (block $exit (result i32)
                                                 (if $exit (result i32) (br $exit (i32.const 7))
                                                     (then (block (br $exit (i32.const 8))))
                                                     (else (i32.const 9))))))))
               (function (car (declarations module 'func))))
          (expect (lower-wasm-body (car (cddddr function)))
                  '((block i32) (i32.const 7) (br 0) (if i32) (block void)
                    (i32.const 8) (br 1) (end) (else) (i32.const 9) (end) (end) (end)))))

      (define (test-resolution-errors)
        (for-each
         (lambda (datum)
           (expect (guard (failure (else #t)) (resolve-wasm datum) #f) #t))
         '((module (type $a (struct (field (ref $later)))))
           (module (type $a (array i8)) (type $a (array i8)))
           (module (func $f) (func $f))
           (module (type $f (func (param i32))) (func (type $f)))
           (module (memory 1))))
        (expect (guard (failure (else #t)) (branch-index '$absent '(#f $here)) #f) #t))

      (define (test-wasm-resolve)
        (run-test test-canonical-types)
        (run-test test-folded-order)
        (run-test test-label-scope)
        (run-test test-resolution-errors))))))
