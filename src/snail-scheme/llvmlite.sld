;; A small, immutable LLVM IR vocabulary, inspired by llvmlite.ir.
;; References exist before definitions, so branches and phi backedges need no
;; mutable builder. Local identity is (function object, name); the same name in
;; a different function is rejected. LLVM verifies definitions and dominance.
;; Constructors never mutate input lists; callers must also treat them as values.
(define-library (snail-scheme llvmlite)
  (export
   void ptr i1 i8 i32 i64 int-type array-type type=? value-type
   local integer null-pointer inttoptr indexed-name function function-name parameter function-result function-address
   block block-name block-owner block-body body-block body-instructions instruction-result
   value-name
   global-bytes global-array global-length utf8-bytes
   call call-indirect load store gep cast select icmp zext binop phi br cbr ret switch
   declare define-function module write-module write-definition
   write-function-start write-function-block write-function-end)
  (import (scheme base) (scheme cxr) (scheme write))
  (begin

    ;; ---- Types and typed operands ----

    (define-record-type <type>
      (make-type kind data) type? (kind type-kind) (data type-data))

    (define (require condition message . objects)
      (if (not condition) (apply error (string-append "llvmlite: " message) objects)))

    (define (int-type bits)
      (require (and (exact-integer? bits) (> bits 0)) "invalid integer width" bits)
      (make-type 'integer bits))

    (define (array-type element count)
      (require (and (type? element) (not (eq? (type-kind element) 'void))
                    (exact-integer? count) (>= count 0)) "invalid array type")
      (make-type 'array (cons element count)))

    (define void (make-type 'void #f))
    (define ptr (make-type 'pointer #f))
    (define i1 (int-type 1))
    (define i8 (int-type 8))
    (define i32 (int-type 32))
    (define i64 (int-type 64))

    (define (type=? left right)
      (and (type? left) (type? right) (eq? (type-kind left) (type-kind right))
           (if (eq? (type-kind left) 'array)
               (and (= (cdr (type-data left)) (cdr (type-data right)))
                    (type=? (car (type-data left)) (car (type-data right))))
               (equal? (type-data left) (type-data right)))))

    (define-record-type <value>
      (make-value type kind data owner) value?
      (type operand-type) (kind value-kind) (data value-data) (owner value-owner))

    (define (value-type value)
      (cond ((value? value) (operand-type value))
            ((global? value) ptr)
            (else (error "llvmlite: expected a typed operand" value))))

    (define (value-name value)
      (require (and (value? value) (eq? (value-kind value) 'local)) "expected a named local")
      (value-data value))

    (define (local owner type name)
      (require (and (function? owner) (type? type) (not (type=? type void)))
               "invalid local value")
      (make-value type 'local (checked-name name) owner))

    (define (integer type number)
      (require (and (type? type) (eq? (type-kind type) 'integer) (exact-integer? number))
               "invalid integer constant" number)
      (make-value type 'integer number #f))

    (define null-pointer (make-value ptr 'null #f #f))

    (define (inttoptr value)
      (require (and (value? value) (eq? (value-kind value) 'integer))
               "inttoptr constant requires an integer constant")
      (make-value ptr 'inttoptr value #f))

    ;; ---- Function and block references ----

    ;; Parameters are (type . name) specifications. References carry their
    ;; function scope; no mutable name registry or module-global counter exists.

    (define-record-type <function>
      (make-function name result parameters) function?
      (name function-name) (result function-result) (parameters function-parameters))

    (define (function name result parameters)
      (require (type? result) "invalid function result type")
      (for-each (lambda (parameter)
                  (require (and (type? (car parameter)) (not (type=? (car parameter) void)))
                           "invalid parameter type")
                  (checked-name (cdr parameter))) parameters)
      (make-function (checked-name name) result parameters))

    (define (parameter function index)
      (let ((specification (list-ref (function-parameters function) index)))
        (local function (car specification) (cdr specification))))

    (define (function-address function)
      (require (function? function) "function address requires a function reference")
      (make-value ptr 'function function #f))

    (define-record-type <block>
      (make-block owner name) block? (owner block-owner) (name block-name))

    (define (block owner name)
      (require (function? owner) "block requires a function")
      (make-block owner (checked-name name)))

    ;; Numbered names keep their decimal suffix as data. In particular, naming
    ;; every VM block does not require opening a temporary string output port.
    (define-record-type <indexed-name>
      (make-indexed-name prefix index) indexed-name?
      (prefix name-prefix) (index name-index))

    (define (indexed-name prefix index)
      (require (and (string? prefix) (> (string-length prefix) 0) (bare-name? prefix)
                    (exact-integer? index) (>= index 0)) "invalid indexed name")
      (make-indexed-name prefix index))

    (define (checked-name name)
      (require (or (indexed-name? name) (and (string? name) (> (string-length name) 0)))
               "expected a nonempty name")
      name)

    ;; ---- Instructions ----

    ;; Results are previously created local objects. Void instructions have #f
    ;; as their result. Operands hold objects, never snippets of LLVM text.

    (define-record-type <instruction>
      (instruction result operation operands) instruction?
      (result instruction-result) (operation instruction-operation)
      (operands instruction-operands))

    (define (require-type value type)
      (require (type=? (value-type value) type) "operand type mismatch" value type))

    (define (require-result value type)
      (require (and (value? value) (eq? (value-kind value) 'local)) "expected a local result")
      (require-type value type))

    (define (call result callee arguments)
      (require (function? callee) "call requires a function reference")
      (check-call result callee arguments)
      (instruction result 'call (cons callee arguments)))

    (define (call-indirect result signature pointer arguments)
      (require (function? signature) "indirect call requires an explicit signature")
      (require-type pointer ptr)
      (check-call result signature arguments)
      (instruction result 'call-indirect (cons signature (cons pointer arguments))))

    (define (check-call result callee arguments)
      (let ((parameters (function-parameters callee)))
        (require (= (length arguments) (length parameters)) "call arity mismatch")
        (for-each (lambda (argument parameter) (require-type argument (car parameter)))
                  arguments parameters))
      (if result (require-result result (function-result callee))))

    (define (load result address)
      (require-result result (value-type result))
      (require-type address ptr)
      (instruction result 'load (list address)))

    (define (store value address)
      (value-type value)
      (require-type address ptr)
      (instruction #f 'store (list value address)))

    (define (gep result element-type address indices)
      (require-result result ptr)
      (require-type address ptr)
      (require (and (type? element-type) (not (type=? element-type void)) (pair? indices))
               "getelementptr requires an element type and indices")
      (for-each (lambda (index)
                  (require (eq? (type-kind (value-type index)) 'integer)
                           "getelementptr requires integer indices")) indices)
      (instruction result 'gep (cons element-type (cons address indices))))

    (define (cast result operation value)
      (require-result result (value-type result))
      (require (case operation
                 ((ptrtoint) (and (type=? (value-type value) ptr)
                                  (eq? (type-kind (value-type result)) 'integer)))
                 ((inttoptr) (and (type=? (value-type result) ptr)
                                  (eq? (type-kind (value-type value)) 'integer)))
                 (else #f)) "invalid pointer/integer cast" operation)
      (instruction result operation (list value)))

    (define (select result condition left right)
      (require-result result (value-type left))
      (require-type condition i1)
      (require-type right (value-type left))
      (require (memq (type-kind (value-type left)) '(integer pointer)) "invalid select type")
      (instruction result 'select (list condition left right)))

    (define (icmp result predicate left right)
      (require-result result i1)
      (require-type right (value-type left))
      (require (memq predicate '(eq ne ugt uge ult ule sgt sge slt sle))
               "unknown integer comparison" predicate)
      (require (memq (type-kind (value-type left)) '(integer pointer)) "invalid comparison type")
      (instruction result 'icmp (list predicate left right)))

    (define (zext result value)
      (require-result result (value-type result))
      (require (and (eq? (type-kind (value-type result)) 'integer)
                    (eq? (type-kind (value-type value)) 'integer)
                    (> (type-data (value-type result)) (type-data (value-type value))))
               "zext requires a wider integer result")
      (instruction result 'zext (list value)))

    (define (binop result operation left right)
      (require-result result (value-type left))
      (require-type right (value-type left))
      (require (eq? (type-kind (value-type left)) 'integer) "expected integer operands")
      (require (memq operation '(add sub mul and or xor shl lshr ashr sdiv udiv srem urem))
               "unknown integer operation" operation)
      (instruction result operation (list left right)))

    (define (phi result incoming)
      (require-result result (value-type result))
      (require (pair? incoming) "phi requires incoming edges")
      (for-each (lambda (edge)
                  (require-type (car edge) (value-type result))
                  (require (block? (cdr edge)) "phi requires predecessor blocks")) incoming)
      (instruction result 'phi incoming))

    (define (br destination)
      (require (block? destination) "branch requires a block")
      (instruction #f 'br (list destination)))

    (define (cbr condition consequent alternate)
      (require-type condition i1)
      (require (and (block? consequent) (block? alternate)) "branch requires blocks")
      (instruction #f 'cbr (list condition consequent alternate)))

    (define (ret value)
      (if value (value-type value))
      (instruction #f 'ret (list value)))

    (define (switch value default cases)
      (require (eq? (type-kind (value-type value)) 'integer) "switch requires an integer")
      (require (block? default) "switch requires a default block")
      (for-each (lambda (entry)
                  (require-type (car entry) (value-type value))
                  (require (and (eq? (value-kind (car entry)) 'integer) (block? (cdr entry)))
                           "switch requires integer constants and blocks")) cases)
      (instruction #f 'switch (list value default cases)))

    ;; ---- Immutable definitions ----

    ;; Local references are checked by scope in linear time. Names identify
    ;; locals within that scope; LLVM checks duplicate/absent definitions, phi
    ;; predecessor agreement, and dominance when the emitted module is verified.

    (define-record-type <body>
      (make-body block instructions terminator) body?
      (block body-block) (instructions body-instructions) (terminator body-terminator))

    (define (terminator? value)
      (and (instruction? value) (memq (instruction-operation value) '(br cbr ret switch))))

    (define (block-body block instructions terminator)
      (require (block? block) "definition requires a block")
      (require (terminator? terminator) "block requires one terminator")
      (check-instruction-order instructions #f)
      (for-each (lambda (item) (check-instruction-scope (block-owner block) item))
                (cons terminator instructions))
      (check-return (block-owner block) terminator)
      (make-body block instructions terminator))

    (define (check-instruction-order instructions ordinary?)
      (if (pair? instructions)
          (let* ((item (car instructions))
                 (phi? (and (instruction? item) (eq? (instruction-operation item) 'phi))))
            (require (and (instruction? item) (not (terminator? item)))
                     "terminator inside instruction list")
            (require (not (and ordinary? phi?)) "phi must precede ordinary instructions")
            (check-instruction-order (cdr instructions) (or ordinary? (not phi?))))))

    (define (check-instruction-scope owner item)
      (check-reference-scope owner (instruction-result item))
      (check-reference-scope owner (instruction-operands item)))

    (define (check-reference-scope owner value)
      (cond ((and (value? value) (value-owner value))
             (require (eq? owner (value-owner value)) "value belongs to another function"))
            ((block? value)
             (require (eq? owner (block-owner value)) "block belongs to another function"))
            ((pair? value)
             (check-reference-scope owner (car value))
             (check-reference-scope owner (cdr value)))))

    (define (check-return owner terminator)
      (if (eq? (instruction-operation terminator) 'ret)
          (let ((value (car (instruction-operands terminator))))
            (require (type=? (function-result owner) (if value (value-type value) void))
                     "return type mismatch"))))

    (define-record-type <definition>
      (make-definition function linkage attributes bodies) definition?
      (function definition-function) (linkage definition-linkage)
      (attributes definition-attributes) (bodies definition-bodies))

    (define (declare function)
      (require (function? function) "declaration requires a function")
      (make-definition function 'external '() #f))

    (define (define-function function linkage attributes bodies)
      (require (and (function? function) (pair? bodies)) "function requires a body")
      (require (memq linkage '(external internal private)) "unsupported function linkage")
      (for-each (lambda (attribute)
                  (require (memq attribute '(alwaysinline noinline nounwind cold))
                           "unsupported function attribute" attribute)) attributes)
      (for-each (lambda (body)
                  (require (and (body? body) (eq? (block-owner (body-block body)) function))
                           "body belongs to another function")) bodies)
      (make-definition function linkage attributes bodies))

    (define-record-type <global>
      (make-global name type kind elements alignment) global?
      (name global-name) (type global-type) (kind global-kind)
      (elements global-elements) (alignment global-alignment))

    (define (global-bytes name bytes)
      (for-each (lambda (byte)
                  (require (and (exact-integer? byte) (<= 0 byte 255)) "invalid byte" byte)) bytes)
      (make-global (checked-name name) (array-type i8 (length bytes)) 'bytes bytes 1))

    (define (global-array name element values alignment)
      (require (and (exact-integer? alignment) (> alignment 0)) "invalid global alignment")
      (for-each (lambda (value)
                  (require-type value element)
                  (require (and (value? value) (eq? (value-kind value) 'integer))
                           "global array requires integer constants")) values)
      (make-global (checked-name name) (array-type element (length values)) 'array values alignment))

    (define (global-length global) (length (global-elements global)))

    (define-record-type <module>
      (module definitions) module? (definitions module-definitions))

    ;; ---- Serialization ----

    ;; Only this section spells LLVM syntax. Output goes directly to a port;
    ;; no complete-module string concatenation or mutable naming state is used.

    (define (write-module module port)
      (for-each (lambda (item) (write-definition item port)) (module-definitions module)))

    (define (write-definition definition port)
      (cond ((global? definition) (write-global definition port))
            ((definition? definition) (write-function definition port))
            (else (error "llvmlite: expected a top-level definition" definition))))

    (define (text port . pieces)
      ;; Pieces are scalar tokens. A shared-structure writer would allocate a
      ;; traversal table even for each integer label on the Chibi host.
      (for-each (lambda (piece)
                  (if (or (string? piece) (char? piece)) (display piece port)
                      (write-simple piece port))) pieces))

    (define (separated writer items port)
      (if (pair? items)
          (begin (writer (car items) port)
                 (for-each (lambda (item) (display ", " port) (writer item port)) (cdr items)))))

    (define (write-type type port)
      (case (type-kind type)
        ((void) (display "void" port))
        ((pointer) (display "ptr" port))
        ((integer) (text port "i" (type-data type)))
        ((array) (text port "[" (cdr (type-data type)) " x ")
         (write-type (car (type-data type)) port) (display "]" port))))

    (define (bare-name? name)
      (define (letter? c)
        (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (memv c '(#\$ #\. #\_ #\-))))
      (and (letter? (string-ref name 0))
           (let loop ((index 1))
             (or (= index (string-length name))
                 (let ((c (string-ref name index)))
                   (and (or (letter? c) (char<=? #\0 c #\9)) (loop (+ index 1))))))))

    (define (write-name prefix name port)
      (display prefix port)
      (cond ((indexed-name? name) (text port (name-prefix name) (name-index name)))
            ((bare-name? name) (display name port))
            (else (display "\"" port) (write-escaped-bytes (utf8-bytes name) port)
                  (display "\"" port))))

    (define (write-value value port)
      (if (global? value) (write-name "@" (global-name value) port)
          (case (value-kind value)
            ((local) (write-name "%" (value-data value) port))
            ((integer) (write-simple (value-data value) port))
            ((null) (display "null" port))
            ((function) (write-name "@" (function-name (value-data value)) port))
            ((inttoptr) (display "inttoptr (" port) (write-typed (value-data value) port)
             (display " to ptr)" port)))))

    (define (write-typed value port)
      (write-type (value-type value) port) (display " " port) (write-value value port))

    (define (write-label block port)
      (display "label " port) (write-name "%" (block-name block) port))

    ;; Incremental serialization releases completed regions without mutating IR.
    ;; The checked definition supplies the header; each later block checks its owner.
    (define (write-function definition port)
      (write-function-start definition port)
      (if (definition-bodies definition)
          (begin
            (for-each (lambda (body) (write-function-block (definition-function definition) body port))
                      (definition-bodies definition))
            (write-function-end port))))
    (define (write-function-start definition port)
      (let ((bodies (definition-bodies definition)))
        (text port (if bodies "define " "declare "))
        (if (not (eq? (definition-linkage definition) 'external))
            (text port (definition-linkage definition) " "))
        (write-function-signature (definition-function definition) (if bodies #t #f) port)
        (for-each (lambda (attribute) (text port " " attribute)) (definition-attributes definition))
        (display (if bodies " {\n" "\n") port)))
    (define (write-function-block function body port)
      (require (and (body? body) (eq? (block-owner (body-block body)) function))
               "body belongs to another function")
      (write-body body port))
    (define (write-function-end port) (display "}\n" port))

    (define (write-function-signature function names? port)
      (write-type (function-result function) port) (display " " port)
      (write-name "@" (function-name function) port) (display "(" port)
      (separated (lambda (parameter port)
                   (write-type (car parameter) port)
                   (if names? (begin (display " " port) (write-name "%" (cdr parameter) port))))
                 (function-parameters function) port)
      (display ")" port))

    (define (write-body body port)
      (write-name "" (block-name (body-block body)) port) (display ":\n" port)
      (for-each (lambda (item) (write-instruction item port)) (body-instructions body))
      (write-instruction (body-terminator body) port))

    (define (write-instruction item port)
      (display "  " port)
      (if (instruction-result item)
          (begin (write-value (instruction-result item) port) (display " = " port)))
      (write-operation item port)
      (newline port))

    (define (write-operation item port)
      (let ((args (instruction-operands item)) (result (instruction-result item)))
        (case (instruction-operation item)
          ((call) (write-call (car args) (cdr args) port))
          ((call-indirect) (write-indirect-call (car args) (cadr args) (cddr args) port))
          ((load) (display "load " port) (write-type (value-type result) port)
           (display ", " port) (write-typed (car args) port))
          ((store) (display "store " port) (separated write-typed args port))
          ((gep) (display "getelementptr " port) (write-type (car args) port)
           (display ", " port) (separated write-typed (cdr args) port))
          ((select) (display "select " port) (separated write-typed args port))
          ((icmp) (text port "icmp " (car args) " ") (write-typed (cadr args) port)
           (display ", " port) (write-value (caddr args) port))
          ((zext ptrtoint inttoptr) (text port (instruction-operation item) " ")
           (write-typed (car args) port)
           (display " to " port) (write-type (value-type result) port))
          ((phi) (display "phi " port) (write-type (value-type result) port)
           (display " " port) (separated write-incoming args port))
          ((br) (display "br " port) (write-label (car args) port))
          ((cbr) (display "br " port) (write-typed (car args) port)
           (display ", " port) (separated write-label (cdr args) port))
          ((ret) (display "ret " port)
           (if (car args) (write-typed (car args) port) (display "void" port)))
          ((switch) (write-switch args port))
          (else (text port (instruction-operation item) " ")
                (write-typed (car args) port) (display ", " port)
                (write-value (cadr args) port)))))

    (define (write-call callee arguments port)
      (display "call " port) (write-type (function-result callee) port) (display " " port)
      (write-name "@" (function-name callee) port) (display "(" port)
      (separated write-typed arguments port) (display ")" port))

    (define (write-indirect-call signature pointer arguments port)
      (display "call " port) (write-type (function-result signature) port) (display " " port)
      (write-value pointer port) (display "(" port)
      (separated write-typed arguments port) (display ")" port))

    (define (write-incoming edge port)
      (display "[ " port) (write-value (car edge) port) (display ", " port)
      (write-name "%" (block-name (cdr edge)) port) (display " ]" port))

    (define (write-switch args port)
      (display "switch " port) (write-typed (car args) port) (display ", " port)
      (write-label (cadr args) port) (display " [\n" port)
      (for-each (lambda (entry)
                  (display "    " port) (write-typed (car entry) port) (display ", " port)
                  (write-label (cdr entry) port) (newline port)) (caddr args))
      (display "  ]" port))

    (define (write-global global port)
      (write-name "@" (global-name global) port) (display " = private constant " port)
      (write-type (global-type global) port) (display " " port)
      (if (eq? (global-kind global) 'bytes)
          (begin (display "c\"" port) (write-escaped-bytes (global-elements global) port)
                 (display "\"" port))
          (begin (display "[" port) (separated write-typed (global-elements global) port)
                 (display "]" port)))
      (text port ", align " (global-alignment global) "\n"))

    (define (write-escaped-bytes bytes port)
      (for-each (lambda (byte)
                  (display "\\" port)
                  (display (string-ref "0123456789ABCDEF" (quotient byte 16)) port)
                  (display (string-ref "0123456789ABCDEF" (modulo byte 16)) port)) bytes))

    ;; Unicode encoding is shared by constant data and quoted LLVM identifiers.
    (define (utf8-bytes text)
      (apply append (map (lambda (character) (encode-codepoint (char->integer character)))
                         (string->list text))))

    (define (encode-codepoint code)
      (cond ((< code 128) (list code))
            ((< code 2048) (list (+ 192 (quotient code 64)) (+ 128 (modulo code 64))))
            ((< code 65536)
             (list (+ 224 (quotient code 4096)) (+ 128 (modulo (quotient code 64) 64))
                   (+ 128 (modulo code 64))))
            (else
             (list (+ 240 (quotient code 262144)) (+ 128 (modulo (quotient code 4096) 64))
                   (+ 128 (modulo (quotient code 64) 64)) (+ 128 (modulo code 64)))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-llvmlite)
    (import (snail-scheme test-utils))
    (begin
      (define (raises? thunk)
        (guard (exception ((error-object? exception) #t)) (thunk) #f))

      (define (module-text module)
        (let ((port (open-output-string))) (write-module module port) (get-output-string port)))

      (define (word value) (integer i32 value))

      (define (test-module)
        (let* ((function (function "answer" i32 '())) (entry (block function "entry")))
          (module (list (global-bytes "bytes" '(0 255))
                        (define-function function 'external '()
                          (list (block-body entry '() (ret (word 42)))))))))

      (define (test-immutable-construction)
        (let* ((module (test-module)) (first (module-text module)))
          (expect (module-text (test-module)) first)
          (expect (module-text module) first))
        (expect (type=? (array-type (int-type 8) 4) (array-type i8 4)) #t)
        (expect (type=? i32 i64) #f)
        (expect (utf8-bytes "λ😀") '(206 187 240 159 152 128)))

      (define (test-global-bytes)
        (expect (module-text (module (list (global-bytes "bytes" '(0 34 92 255)))))
                "@bytes = private constant [4 x i8] c\"\\00\\22\\5C\\FF\", align 1\n")
        (expect (module-text (module (list (global-bytes "empty" '()))))
                "@empty = private constant [0 x i8] c\"\", align 1\n"))

      (define (test-indexed-names)
        (let ((name (indexed-name "g" 12)))
          (expect (module-text (module (list (global-bytes name '(42)))))
                  (module-text (module (list (global-bytes "g12" '(42)))))))
        (for-each (lambda (arguments)
                    (expect (raises? (lambda () (apply indexed-name arguments))) #t))
                  '(("" 1) ("1b" 2) ("bad name" 0) ("b" -1) ("b" 1.0))))

      (define (test-pointer-instructions)
        (let* ((function (function "slot" ptr (list (cons ptr "base") (cons i32 "index"))))
               (entry (block function "entry")) (address (local function ptr "address"))
               (bits (local function i32 "bits")) (restored (local function ptr "restored"))
               (chosen (local function ptr "chosen"))
               (instructions (list (gep address i32 (parameter function 0) (list (parameter function 1)))
                                   (cast bits 'ptrtoint address) (cast restored 'inttoptr bits)
                                   (select chosen (integer i1 1) restored (inttoptr (word 7))))))
          (expect (module-text (module (list (define-function function 'external '()
                                               (list (block-body entry instructions (ret chosen)))))))
                  (string-append "define ptr @slot(ptr %base, i32 %index) {\nentry:\n"
                                 "  %address = getelementptr i32, ptr %base, i32 %index\n"
                                 "  %bits = ptrtoint ptr %address to i32\n"
                                 "  %restored = inttoptr i32 %bits to ptr\n"
                                 "  %chosen = select i1 1, ptr %restored, ptr inttoptr (i32 7 to ptr)\n"
                                 "  ret ptr %chosen\n}\n"))))

      (define (test-invalid-pointer-instructions)
        (let* ((function (function "f" ptr '())) (address (local function ptr "address"))
               (value (local function i32 "value")) (array (local function (array-type i32 2) "array")))
          (for-each (lambda (thunk) (expect (raises? thunk) #t))
                    (list (lambda () (gep value i32 address (list (word -1))))
                          (lambda () (gep address void address (list (word 0))))
                          (lambda () (gep address i32 value (list (word 0))))
                          (lambda () (gep address i32 address '()))
                          (lambda () (gep address i32 address (list null-pointer)))
                          (lambda () (cast address 'bitcast address))
                          (lambda () (cast address 'ptrtoint address))
                          (lambda () (cast value 'ptrtoint value))
                          (lambda () (cast value 'inttoptr value))
                          (lambda () (cast address 'inttoptr address))
                          (lambda () (select address (word 1) address null-pointer))
                          (lambda () (select address (integer i1 1) value value))
                          (lambda () (select address (integer i1 1) address value))
                          (lambda () (select array (integer i1 1) array array))))))

      (define (test-pointer-reference-scopes)
        (let* ((first (function "f" ptr '())) (second (function "g" ptr '()))
               (entry (block first "entry")) (address (local first ptr "address"))
               (value (local first i32 "value")) (foreign (local second ptr "address"))
               (index (local second i32 "index")) (condition (local second i1 "condition")))
          (for-each (lambda (item)
                      (expect (raises? (lambda () (block-body entry (list item) (ret address)))) #t))
                    (list (gep address i32 foreign (list (word -1)))
                          (gep address i32 null-pointer (list index))
                          (cast value 'ptrtoint foreign) (cast address 'inttoptr index)
                          (select address condition null-pointer null-pointer)
                          (select address (integer i1 1) foreign null-pointer)
                          (select address (integer i1 1) null-pointer foreign)))))

      (define (test-invalid-instructions)
        (let* ((function (function "f" i32 '())) (entry (block function "entry"))
               (value (local function i32 "value")) (condition (local function i1 "test"))
               (call-instruction (call value function '())) (phi-instruction (phi value (list (cons (word 0) entry)))))
          (for-each (lambda (thunk) (expect (raises? thunk) #t))
                    (list (lambda () (cbr value entry entry))
                          (lambda () (call value function (list (word 1))))
                          (lambda () (icmp condition 'eq (word 1) null-pointer))
                          (lambda () (block-body entry (list call-instruction phi-instruction) (ret value)))
                          (lambda () (block-body entry (list (ret value)) (ret value)))
                          (lambda () (block-body entry '() call-instruction))
                          (lambda () (block-body entry '() (ret #f)))
                          (lambda () (global-bytes "bytes" '(256)))
                          (lambda () (global-bytes "" '(1)))))))

      (define (test-reference-scopes)
        (let* ((first (function "f" i32 '())) (second (function "g" i32 '()))
               (entry (block first "entry")) (foreign (block second "entry"))
               (value (local second i32 "value")))
          (expect (raises? (lambda () (block-body entry '() (br foreign)))) #t)
          (expect (raises? (lambda () (block-body entry '() (ret value)))) #t)
          (expect (raises? (lambda ()
                             (define-function second 'external '()
                               (list (block-body entry '() (ret (word 1))))))) #t)))

      (define (test-indirect-calls)
        (let* ((callee (function "callee" i32 (list (cons i32 "x"))))
               (caller (function "caller" i32 (list (cons ptr "target"))))
               (value (local caller i32 "answer")) (entry (block caller "entry"))
               (invoke (call-indirect value callee (parameter caller 0) (list (word 7)))))
          (expect (module-text (module (list (define-function caller 'external '()
                                               (list (block-body entry (list invoke) (ret value)))))))
                  "define i32 @caller(ptr %target) {\nentry:\n  %answer = call i32 %target(i32 7)\n  ret i32 %answer\n}\n")
          (expect (raises? (lambda () (call-indirect value callee (word 0) (list (word 7))))) #t)
          (expect (raises? (lambda () (call-indirect value callee (function-address callee) '()))) #t)
          (expect (value-type (function-address callee)) ptr)))

      (define (test-streamed-serialization)
        (let* ((function (function "choose" i32 (list (cons i1 "test"))))
               (entry (block function "entry")) (other (block function "other"))
               (join (block function "join")) (answer (local function i32 "answer"))
               (bodies (list (block-body entry '() (cbr (parameter function 0) join other))
                             (block-body other '() (br join))
                             (block-body join (list (phi answer (list (cons (word 1) entry)
                                                                      (cons (word 2) other))))
                                         (ret answer))))
               (expected (string-append "define private i32 @choose(i1 %test) nounwind {\n"
                                        "entry:\n  br i1 %test, label %join, label %other\n"
                                        "other:\n  br label %join\njoin:\n"
                                        "  %answer = phi i32 [ 1, %entry ], [ 2, %other ]\n"
                                        "  ret i32 %answer\n}\n"))
               (port (open-output-string)))
          (expect (module-text (module (list (define-function function 'private '(nounwind) bodies)))) expected)
          (write-function-start (define-function function 'private '(nounwind) (list (car bodies))) port)
          (for-each (lambda (body) (write-function-block function body port)) bodies)
          (write-function-end port)
          (expect (get-output-string port) expected)
          (let ((declaration (open-output-string)))
            (write-function-start (declare function) declaration)
            (expect (get-output-string declaration) "declare i32 @choose(i1)\n"))))

      (define (test-streamed-block-ownership)
        (let* ((first (function "same" i32 '())) (second (function "same" i32 '()))
               (foreign (block-body (block second "entry") '() (ret (word 1))))
               (port (open-output-string)))
          (expect (raises? (lambda () (write-function-block first foreign port))) #t)
          (expect (get-output-string port) "")))

      (define (test-llvmlite)
        (run-test test-immutable-construction)
        (run-test test-global-bytes)
        (run-test test-indexed-names)
        (run-test test-pointer-instructions)
        (run-test test-invalid-pointer-instructions)
        (run-test test-pointer-reference-scopes)
        (run-test test-invalid-instructions)
        (run-test test-reference-scopes)
        (run-test test-indirect-calls)
        (run-test test-streamed-serialization)
        (run-test test-streamed-block-ownership))
      ))))
