;; Elaborate the Scheme calling convention into ordinary MIR memory operations.
;; The downward-growing stack holds arguments, locals, and three-word frames.
;; No MIR operation knows about Scheme: representation changes are foreign calls.
(define-library (snail-scheme machine)
  (export create-machine machine-definitions machine-instruction
          machine-apply-code machine-return-code machine-stop-code machine-consume-code)
  (import (scheme base) (scheme cxr) (prefix (snail-scheme mir) mir:))
  (begin

    ;; ---- Runtime and register protocol ----

    ;; ABI 3 fields are four bytes each. Stack depth d addresses end[-d].
    ;; Only depths 1..s are roots. Saved depths and code addresses are fixnums.
    ;; VM and state pointers may alias; a reserve invalidates stack pointers.
    (define registers
      '(a c s f count end capacity globals constants argc entry locals frames max-frames stopped))
    (define (integer value) (mir:literal 'i32 value))
    (define (word value) (mir:literal 'word value))
    (define (register-type name)
      (cond ((memq name '(end globals constants)) 'ptr)
            ((memq name '(a c)) 'word) (else 'i32)))
    (define (register-address name)
      (let loop ((names registers) (index 0))
        (cond ((null? names) (error "unknown machine register" name))
              ((eq? name (car names)) (mir:offset mir:state (integer (* 4 index))))
              (else (loop (cdr names) (+ index 1))))))
    (define (read-register name) (mir:load (register-type name) (register-address name)))
    (define (write-register name value) (mir:store value (register-address name)))
    (define (single-result result)
      (mir:sequence (list (write-register 'a result) (write-register 'count (integer 1)))))
    (define (stack-slot depth)
      (mir:offset (read-register 'end) (mir:binop 'mul depth (integer -4))))
    (define (local-slot index)
      (stack-slot (mir:binop 'add (read-register 'f) (integer (+ index 1)))))

    (define runtime-functions
      (list (cons 'reserve (mir:foreign "snail_rt_reserve" '(ptr i32) 'void 'state))
            (cons 'box (mir:foreign "snail_rt_box" '(ptr i32) 'void 'boundary))
            (cons 'cell (mir:foreign "snail_rt_cell" '(ptr word) 'ptr 'state))
            (cons 'free (mir:foreign "snail_rt_free" '(ptr i32) 'ptr 'state))
            (cons 'uninitialized (mir:foreign "snail_rt_uninitialized" '(ptr) 'void 'state))
            (cons 'value-error (mir:foreign "snail_rt_value_error" '(ptr) 'void 'state))
            (cons 'close (mir:foreign "snail_rt_close" '(ptr i32 i32 i32 i32 i32) 'void 'boundary))
            (cons 'prepare (mir:foreign "snail_rt_prepare_apply" '(ptr i32) 'i32 'boundary))
            (cons 'numeric (mir:foreign "snail_rt_numeric" '(ptr i32) 'void 'boundary))
            (cons 'receive (mir:foreign "snail_rt_receive" '(ptr) 'void 'state))
            (cons 'capture (mir:foreign "snail_rt_capture" '(ptr) 'void 'boundary))
            (cons 'restore (mir:foreign "snail_rt_restore" '(ptr i32) 'void 'state))))
    (define move-function
      (mir:foreign "llvm.memmove.p0.p0.i32" '(ptr ptr i32 i1) 'void 'state))
    (define fixnum-predicate (mir:foreign "snail_value_is_fixnum" '(word) 'i32 'pure))
    (define fixnum-extractor (mir:foreign "snail_value_to_i32" '(word) 'i32 'pure))
    (define fixnum-constructor (mir:foreign "snail_value_from_i32" '(i32) 'word 'pure))
    (define boolean-constructor (mir:foreign "snail_value_from_boolean" '(i32) 'word 'pure))
    (define predicate-functions
      (list (cons 'procedure-predicate (mir:foreign "snail_value_is_procedure" '(word) 'i32 'read))
            (cons 'number-predicate (mir:foreign "snail_value_is_number" '(word) 'i32 'read))
            (cons 'integer-predicate (mir:foreign "snail_value_is_exact_integer" '(word) 'i32 'read))))
    (define (runtime-call name arguments)
      (mir:call-direct (cdr (assq name runtime-functions)) (cons mir:vm arguments)))
    (define (pack-integer value) (mir:call-direct fixnum-constructor (list value)))
    (define (unpack-integer value) (mir:call-direct fixnum-extractor (list value)))
    (define (raise-error name)
      (mir:sequence (list (runtime-call name '()) mir:finish)))
    (define (while-running next)
      (mir:conditional (mir:compare 'eq (read-register 'stopped) (integer 0)) next mir:finish))
    (define (checked-service name arguments next)
      (mir:sequence (list (runtime-call name arguments) (while-running next))))
    (define (single-value next)
      (mir:conditional (mir:compare 'eq (read-register 'count) (integer 1))
                       next (raise-error 'value-error)))
    (define (nonnull pointer next)
      (mir:conditional (mir:compare 'ne pointer (mir:literal 'ptr 0)) next mir:finish))

    ;; ---- Slots and objects ----

    (define (binding-slot kind index)
      (case kind
        ((local) (local-slot index))
        ((free) (runtime-call 'free (list (integer index))))
        (else (mir:offset (read-register kind) (integer (* 4 index))))))
    (define (read-value pointer next)
      (mir:let* ((item (mir:load 'word pointer)))
                (mir:conditional (mir:compare 'eq item (word 44))
                                 (raise-error 'uninitialized)
                                 (mir:sequence (list (single-result item) next)))))
    (define (reference kind index next)
      (mir:let* ((slot (binding-slot kind index)))
                (nonnull slot (read-value slot next))))
    (define (indirect next)
      (single-value
       (mir:let* ((slot (runtime-call 'cell (list (read-register 'a)))))
                 (nonnull slot (read-value slot next)))))
    (define (store-binding pointer item next)
      (nonnull pointer (mir:sequence (list (mir:store item pointer)
                                           (single-result (word 36)) next))))
    (define (assignment kind index boxed? next)
      (single-value
       (mir:let* ((item (read-register 'a)) (slot (binding-slot kind index)))
                 (nonnull slot
                          (if boxed?
                              (mir:let* ((cell (runtime-call 'cell (list (mir:load 'word slot)))))
                                        (store-binding cell item next))
                              (store-binding slot item next))))))

    ;; ---- Stack construction ----

    (define (reserve depth next)
      (mir:sequence
       (list (mir:conditional (mir:compare 'ule depth (read-register 'capacity))
                              (mir:sequence '())
                              (checked-service 'reserve (list depth) (mir:sequence '())))
             next)))
    (define (argument next)
      (single-value
       (mir:let* ((top (mir:binop 'add (read-register 's) (integer 1))))
                 (reserve top (mir:sequence (list (mir:store (read-register 'a) (stack-slot top))
                                                  (write-register 's top) next))))))
    (define (increment-frame-count)
      (mir:let* ((count (mir:binop 'add (read-register 'frames) (integer 1)))
                 (maximum (read-register 'max-frames)))
                (mir:sequence
                 (list (write-register 'frames count)
                       (write-register 'max-frames
                                       (mir:conditional (mir:compare 'ugt count maximum) count maximum))))))
    (define (frame resume next)
      (mir:let* ((top (mir:binop 'add (read-register 's) (integer 3))))
                (reserve top
                         (mir:sequence
                          (list (mir:store (read-register 'c) (stack-slot (mir:binop 'sub top (integer 2))))
                                (mir:store (pack-integer (read-register 'f))
                                           (stack-slot (mir:binop 'sub top (integer 1))))
                                (mir:store (pack-integer (mir:code-reference resume)) (stack-slot top))
                                (write-register 's top) (increment-frame-count) next)))))
    (define (shift argc next)
      (mir:let* ((top (mir:binop 'add (read-register 'f) (integer argc))))
                (mir:sequence
                 (list (mir:call-direct move-function
                                        (list (stack-slot top) (stack-slot (read-register 's))
                                              (integer (* 4 argc)) (mir:literal 'i1 0)))
                       (write-register 's top) next))))

    ;; ---- Numeric operations ----

    ;; Both operands remain stack roots until fallback returns. Decoded signed31
    ;; sums/differences fit signed32; the biased unsigned check guards re-tagging.
    (define (numeric-result result top next)
      (mir:sequence (list (single-result result)
                          (write-register 's (mir:binop 'sub top (integer 2))) next)))
    (define (fixnum-arithmetic operation left right top fallback next)
      (mir:let* ((x (unpack-integer left)) (y (unpack-integer right))
                 (number (mir:binop (if (eq? operation 'add) 'add 'sub) x y)))
                (mir:conditional
                 (mir:compare 'ule (mir:binop 'add number (integer 1073741824)) (integer 2147483647))
                 (numeric-result (pack-integer number) top next) fallback)))
    (define (fixnum-comparison operation left right top next)
      (let ((predicate (cdr (assq operation '((numeric-equal . eq) (less . slt) (less-equal . sle)
                                              (greater . sgt) (greater-equal . sge))))))
        (mir:let* ((x (unpack-integer left)) (y (unpack-integer right)))
                  (numeric-result
                   (mir:call-direct boolean-constructor
                                    (list (mir:cast 'i32 'zext (mir:compare predicate x y)))) top next))))
    (define (numeric operation global next)
      (mir:sequence (list (numeric-step operation global) next)))

    (define (numeric-step operation global)
      (let* ((done (mir:sequence '()))
             (fallback (checked-service 'numeric (list (integer global)) done)))
        (mir:let* ((top (read-register 's))
                   (left (mir:load 'word (stack-slot (mir:binop 'sub top (integer 1)))))
                   (right (mir:load 'word (stack-slot top)))
                   (left-fixnum (mir:call-direct fixnum-predicate (list left)))
                   (right-fixnum (mir:call-direct fixnum-predicate (list right))))
                  (mir:conditional
                   (mir:compare 'ne (mir:binop 'and left-fixnum right-fixnum) (integer 0))
                   (if (memq operation '(add subtract))
                       (fixnum-arithmetic operation left right top fallback done)
                       (fixnum-comparison operation left right top done)) fallback))))

    (define (predicate operation next)
      (mir:let* ((top (read-register 's)) (item (mir:load 'word (stack-slot top)))
                 (answer (mir:call-direct (cdr (assq operation predicate-functions)) (list item))))
                (mir:sequence
                 (list (single-result (mir:call-direct boolean-constructor (list answer)))
                       (write-register 's (mir:binop 'sub top (integer 1))) next))))

    ;; ---- Scheme transfers ----

    (define-record-type <machine>
      (make-machine apply-code return-code stop-code consume-code pad-code)
      machine?
      (apply-code machine-apply-code) (return-code machine-return-code)
      (stop-code machine-stop-code) (consume-code machine-consume-code)
      (pad-code machine-pad-code))
    (define (create-machine)
      (make-machine (mir:make-code 'apply) (mir:make-code 'return) (mir:make-code 'stop)
                    (mir:make-code 'consume) (mir:make-code 'pad-locals)))
    (define (transfer code) (mir:tail-call (mir:code-reference code)))
    (define (apply-procedure machine argc)
      (mir:sequence (list (write-register 'argc argc) (transfer (machine-apply-code machine)))))
    (define (scheme-entry machine)
      (mir:let* ((top (mir:binop 'add (read-register 'f) (read-register 'locals))))
                (reserve top (pad-locals machine))))
    (define (pad-locals machine)
      (mir:let* ((top (mir:binop 'add (read-register 'f) (read-register 'locals)))
                 (depth (read-register 's)))
                (mir:conditional
                 (mir:compare 'ult depth top)
                 (mir:let* ((next (mir:binop 'add depth (integer 1))))
                           (mir:sequence (list (mir:store (word 44) (stack-slot next))
                                               (write-register 's next) (transfer (machine-pad-code machine)))))
                 (mir:sequence (list (write-register 's top) (single-result (word 36))
                                     (mir:tail-call (read-register 'entry)))))))
    (define (apply-action machine action)
      (define (choose choices)
        (if (null? choices) mir:finish
            (mir:conditional (mir:compare 'eq action (integer (caar choices)))
                             (cdar choices) (choose (cdr choices)))))
      (choose (list (cons 0 (scheme-entry machine))
                    (cons 1 (transfer (machine-return-code machine)))
                    (cons 2 (transfer (machine-apply-code machine)))
                    (cons 3 (produce-values machine)) (cons 4 (capture-continuation machine))
                    (cons 5 (checked-service 'restore (list (read-register 'argc))
                                             (transfer (machine-return-code machine)))))))
    (define (apply-body machine)
      (single-value
       (mir:sequence
        (list (write-register 'f (mir:binop 'sub (read-register 's) (read-register 'argc)))
              (write-register 'c (read-register 'a))
              (mir:let* ((action (runtime-call 'prepare (list (read-register 'argc)))))
                        (apply-action machine action))))))

    ;; Load every saved value before publishing the shorter stack. Signed decode
    ;; preserves -1 (stop) and -2 (values receiver) as well as ordinary addresses.
    (define (return-body)
      (mir:let* ((base (read-register 'f))
                 (closure (mir:load 'word (stack-slot (mir:binop 'sub base (integer 2)))))
                 (frame (unpack-integer (mir:load 'word (stack-slot (mir:binop 'sub base (integer 1))))))
                 (resume (unpack-integer (mir:load 'word (stack-slot base)))))
                (mir:sequence
                 (list (write-register 'c closure) (write-register 'f frame)
                       (write-register 's (mir:binop 'sub base (integer 3)))
                       (write-register 'frames (mir:binop 'sub (read-register 'frames) (integer 1)))
                       (mir:tail-call resume)))))

    ;; The consumer remains below the producer frame, so a snapshot retains it.
    (define (produce-values machine)
      (mir:sequence
       (list (single-result (mir:load 'word (local-slot 0)))
             (frame (machine-consume-code machine) (apply-procedure machine (integer 0))))))
    (define (consume-values machine)
      (checked-service 'receive '() (transfer (machine-apply-code machine))))

    ;; Capture excludes its argument, but that slot roots the procedure during GC.
    ;; Reload the slot address after capture; the service may resize storage.
    (define (capture-continuation machine)
      (mir:let* ((procedure (mir:load 'word (local-slot 0))))
                (checked-service
                 'capture '()
                 (mir:sequence (list (mir:store (read-register 'a) (local-slot 0))
                                     (single-result procedure) (apply-procedure machine (integer 1)))))))

    (define (machine-definitions machine)
      (list (mir:make-definition (machine-apply-code machine) (apply-body machine))
            (mir:make-definition (machine-return-code machine) (return-body))
            (mir:make-definition (machine-stop-code machine) mir:finish)
            (mir:make-definition (machine-consume-code machine) (consume-values machine))
            (mir:make-definition (machine-pad-code machine) (pad-locals machine))))

    ;; ---- Elaboration interface ----

    ;; These cases are construction helpers, not operations retained in MIR.
    ;; Common next expressions remain shared objects rather than copied trees.
    (define (machine-instruction machine operation operands next)
      (case operation
        ((constant) (reference 'constants (car operands) next))
        ((refer-local) (reference 'local (car operands) next))
        ((refer-free) (reference 'free (car operands) next))
        ((refer-global) (reference 'globals (car operands) next))
        ((init-local) (assignment 'local (car operands) #f next))
        ((set-local) (assignment 'local (car operands) #t next))
        ((set-free) (assignment 'free (car operands) #t next))
        ((set-global) (assignment 'globals (car operands) #f next))
        ((indirect) (indirect next))
        ((box) (checked-service 'box (map integer operands) next))
        ((argument) (argument next))
        ((frame) (frame (car operands) next))
        ((shift) (shift (car operands) next))
        ((reserve) (reserve (integer (car operands)) next))
        ((close) (checked-service 'close (cons (mir:code-reference (car operands))
                                               (map integer (cdr operands))) next))
        ((test) (single-value (mir:conditional (mir:compare 'ne (read-register 'a) (word 20))
                                               (car operands) (cadr operands))))
        ((add subtract numeric-equal less less-equal greater greater-equal)
         (numeric operation (car operands) next))
        ((procedure-predicate number-predicate integer-predicate) (predicate operation next))
        ((apply) (apply-procedure machine (integer (car operands))))
        ((return) (transfer (machine-return-code machine)))
        (else (error "unknown machine elaboration operation" operation))))))
