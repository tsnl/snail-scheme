;; Evaluate closed values before control and lifetime lowering. Functions
;; remain code; reading a constant forces its initializer and copies its
;; object graph. No compiler-owned mutable object becomes a runtime global.
(define-library (snail shell compiler constants)
  (export fold-constants constant-declarations)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler specialize)
   (snail shell compiler constant-scalars))
  (begin

    ;; ---- Values and evaluation ----

    ;; Objects have identities independent of structural equality. The heap
    ;; belongs to this evaluation, and updates replace one entry in it.
    (struct Known
      ((type Type)
       (value Constant)))

    (enum Constant
      (Scalar ((datum Datum)))
      (RealValue ((value F64)))
      (Global ((name String)))
      (Object ((id String))))

    (enum ObjectValue
      (RecordValue ((constructor String) (fields (List Known))))
      (ArrayValue ((items (List Known))))
      (ClosureValue ((expression Expr) (environment (Table Known)) (self (Option String)))))

    (struct Evaluation
      ((state State)
       (bodies (Table Expr))
       (values (Table Known))
       (forcing (List String))
       (heap (Table ObjectValue))
       (next I64)))

    (define-syntax evaluating
      (syntax-rules ()
        ((_ ev () body ...) (begin body ...))
        ((_ ev ((name (f arg ...)) step ...) body ...)
         (match (f ev arg ...)
           ((Pair name ev) (evaluating ev (step ...) body ...))))))

    (define (program (ev Evaluation)) (→ Program)
      (specialization-program (● ev state)))

    (define (allocate (ev Evaluation) (type Type) (value ObjectValue))
      (→ (Pair Known Evaluation))
      (let ((id (i64->string (● ev next))))
        (Pair (Known type (Object id))
              (Evaluation-next-set
               (Evaluation-heap-set ev (table-set (● ev heap) id value)) (+ (● ev next) 1)))))

    (define (object-value (ev Evaluation) (value Known) (loc Loc)) (→ ObjectValue) (! compile)
      (match (● value value)
        ((Object id)
         (match (table-ref (● ev heap) id)
           ((Some object) object)
           ((None) (panic "internal error: missing constant object"))))
        (_ (compile-error loc "constant evaluation expected an object"))))

    (define (body-of (ev Evaluation) (name String)) (→ (Pair Expr Evaluation))
      (match (table-ref (● ev bodies) name)
        ((Some body) (Pair body ev))
        ((None)
         (match (constant-body (● ev state) name)
           ((Pair body state)
            (Pair body (Evaluation-bodies-set (Evaluation-state-set ev state)
                                              (table-set (● ev bodies) name body))))))))

    ;; Only actually evaluated references force a value. Ordinary recursion
    ;; enters function bodies without putting their names on this stack.
    (define (force-value (ev Evaluation) (name String) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (table-ref (● ev values) name)
        ((Some value) (Pair value ev))
        ((None)
         (when (member? name (● ev forcing))
           (compile-error loc (string-append "constant initialization cycle: "
                                             (string-join (reverse (Cons name (● ev forcing)))
                                                          " → "))))
         (evaluating ev ((body (body-of name)))
                     (let ((outer (● ev forcing)))
                       (let ((ev (Evaluation-forcing-set ev (Cons name outer))))
                         (evaluating ev ((value (evaluate empty-table body)))
                                     (Pair value
                                           (Evaluation-values-set (Evaluation-forcing-set ev outer)
                                                                  (table-set (● ev values)
                                                                             name
                                                                             value))))))))))

    (define (reference (ev Evaluation) (env (Table Known)) (expr Expr) (name String))
      (→ (Pair Known Evaluation)) (! compile)
      (match (table-ref env name)
        ((Some value) (Pair value ev))
        ((None)
         (if (constant-binding? (● ev state) name)
             (evaluating ev ((value (force-value name (● expr loc))))
                         (copy-value ev value))
             (Pair (Known (● expr type) (Global name)) ev)))))

    (define (evaluate (ev Evaluation) (env (Table Known)) (expr Expr))
      (→ (Pair Known Evaluation)) (! compile)
      (match (● expr term)
        ((Lit datum) (literal-value ev (● expr type) datum (● expr loc)))
        ((Var name _ _) (reference ev env expr name))
        ((Lambda _ _ _) (make-closure ev env expr (None)))
        ((App callee args)
         (evaluating ev ((callee (evaluate env callee)) (args (evaluate-all env args)))
                     (invoke ev callee args (● expr type) (● expr loc))))
        ((Let name value body)
         (evaluating ev ((value (evaluate-binding env name value)))
                     (evaluate ev (table-set env name value) body)))
        ((If test yes no)
         (evaluating ev ((test (evaluate env test)))
                     (evaluate ev env (if (boolean-value test (● expr loc)) yes no))))
        ((Seq first rest)
         (evaluating ev ((ignored (evaluate env first))) (evaluate ev env rest)))
        ((Match value clauses)
         (evaluating ev ((value (evaluate env value)))
                     (evaluate-match ev env value clauses (● expr loc))))
        ((Ann inner _) (evaluate ev env inner))
        (_ (compile-error (● expr loc)
                          "this operation cannot be evaluated in a compile-time value"))))

    (define (evaluate-binding (ev Evaluation) (env (Table Known)) (name String) (value Expr))
      (→ (Pair Known Evaluation)) (! compile)
      (if (lambda-expr? value) (make-closure ev env value (Some name)) (evaluate ev env value)))

    (define (make-closure (ev Evaluation) (env (Table Known)) (expr Expr) (self (Option String)))
      (→ (Pair Known Evaluation))
      (allocate ev (● expr type)
                (ClosureValue expr
                              (fold-left (lambda (captures name)
                                           (match (table-ref env name)
                                             ((Some value) (table-set captures name value))
                                             ((None) captures)))
                                         empty-table (expr-references expr))
                              self)))

    (define (evaluate-all (ev Evaluation) (env (Table Known)) (exprs (List Expr)))
      (→ (Pair (List Known) Evaluation)) (! compile)
      (match exprs
        ((Nil) (Pair (Nil) ev))
        ((Cons first rest)
         (evaluating ev ((first (evaluate env first)) (rest (evaluate-all env rest)))
                     (Pair (Cons first rest) ev)))))

    (define (invoke (ev Evaluation) (callee Known) (args (List Known)) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (● callee value)
        ((Global name) (invoke-global ev name args type loc))
        ((Object _)
         (match (object-value ev callee loc)
           ((ClosureValue (Expr (Lambda params body _) _ _) env self)
            (let ((env (match self ((Some name) (table-set env name callee)) ((None) env))))
              (evaluate ev (fold-left (lambda (env pair)
                                        (table-set env (● pair first) (● pair second)))
                                      env (zip params args)) body)))
           (_ (compile-error loc "constant evaluation expected a function"))))
        (_ (compile-error loc "constant evaluation expected a function"))))

    (define (invoke-global (ev Evaluation) (name String) (args (List Known)) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (program-value (program ev) name)
        ((Some (Constructor _ _)) (allocate ev type (RecordValue name args)))
        ((Some (Accessor _ index _))
         (Pair (list-ref (record-fields ev (car-value args loc) loc) index) ev))
        ((Some (Replacer _ index _))
         (match (object-value ev (car-value args loc) loc)
           ((RecordValue name fields)
            (allocate ev type (RecordValue name (replace-at fields index (list-ref args 1)))))
           (_ (compile-error loc "constant replacement expected a record"))))
        ((Some (Primitive _)) (primitive-value ev name args type loc))
        ((Some (Foreign _ _))
         (compile-error loc "a compile-time value cannot call a foreign function"))
        ((Some (Operation _ _)) (compile-error loc "a compile-time value cannot perform an effect"))
        (_ (evaluating ev ((body (body-of name)))
                       (match (● body term)
                         ((Lambda params body _)
                          (evaluate ev (fold-left (lambda (env pair)
                                                    (table-set env (● pair first) (● pair second)))
                                                  empty-table (zip params args)) body))
                         (_ (evaluating ev ((function (evaluate empty-table body)))
                                        (invoke ev function args type loc))))))))

    (define (car-value (values (List Known)) (loc Loc)) (→ Known) (! compile)
      (match values ((Cons value _) value) ((Nil) (compile-error loc "missing constant operand"))))

    (define (record-fields (ev Evaluation) (value Known) (loc Loc)) (→ (List Known)) (! compile)
      (match (object-value ev value loc)
        ((RecordValue _ fields) fields)
        (_ (compile-error loc "constant evaluation expected a record"))))

    (define (replace-at (values (List Known)) (index I64) (value Known)) (→ (List Known))
      (map-indexed (lambda (i previous) (if (= i index) value previous)) values))

    ;; ---- Patterns ----

    (define (evaluate-match (ev Evaluation) (env (Table Known)) (value Known)
                            (clauses (List Clause)) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match clauses
        ((Nil) (compile-error loc "non-exhaustive match during constant evaluation"))
        ((Cons clause rest)
         (match (match-value ev env (● clause pattern) value loc)
           ((Some inner) (evaluate ev inner (● clause body)))
           ((None) (evaluate-match ev env value rest loc))))))

    (define (match-value (ev Evaluation)
                         (env (Table Known))
                         (pattern Pattern)
                         (value Known)
                         (loc Loc))
      (→ (Option (Table Known))) (! compile)
      (match pattern
        ((PWild _) (Some env))
        ((PVar name _) (Some (table-set env name value)))
        ((PLit datum _)
         (match (● value value)
           ((Scalar actual) (if (datum=? datum actual) (Some env) (None)))
           (_ (None))))
        ((PCon name args _)
         (match (object-value ev value loc)
           ((RecordValue actual fields)
            (if (string=? name actual) (match-fields ev (Some env) args fields loc) (None)))
           (_ (None))))))

    (define (match-fields (ev Evaluation) (env (Option (Table Known)))
                          (patterns (List Pattern)) (values (List Known)) (loc Loc))
      (→ (Option (Table Known))) (! compile)
      (fold-left (lambda (env pair)
                   (match env
                     ((Some inner) (match-value ev inner (● pair first) (● pair second) loc))
                     ((None) (None))))
                 env (zip patterns values)))

    ;; ---- Fresh constant graphs ----

    ;; Copy through an identity map, preserving internal aliases. Placeholders
    ;; are installed before children, so copying itself also handles cycles.
    (struct Copying
      ((evaluation Evaluation)
       (objects (Table String))))

    (define (copy-value (ev Evaluation) (value Known)) (→ (Pair Known Evaluation))
      (match (copy-known (Copying ev empty-table) value)
        ((Pair value copying) (Pair value (● copying evaluation)))))

    (define (copy-known (copying Copying) (value Known)) (→ (Pair Known Copying))
      (match (● value value)
        ((Object old)
         (match (table-ref (● copying objects) old)
           ((Some fresh) (Pair (Known (● value type) (Object fresh)) copying))
           ((None) (copy-object copying value old))))
        (_ (Pair value copying))))

    (define (copy-object (copying Copying) (value Known) (old String)) (→ (Pair Known Copying))
      (let* ((ev (● copying evaluation)) (fresh (i64->string (● ev next)))
             (copying (Copying (Evaluation-next-set ev (+ (● ev next) 1))
                               (table-set (● copying objects) old fresh))))
        (match (table-ref (● ev heap) old)
          ((Some object)
           (match (copy-object-value copying object)
             ((Pair object copying)
              (let ((ev (● copying evaluation)))
                (Pair (Known (● value type) (Object fresh))
                      (Copying-evaluation-set copying
                                              (Evaluation-heap-set ev
                                                                   (table-set (● ev heap)
                                                                              fresh
                                                                              object))))))))
          ((None) (panic "internal error: missing constant object")))))

    (define (copy-object-value (copying Copying) (object ObjectValue))
      (→ (Pair ObjectValue Copying))
      (match object
        ((RecordValue name fields)
         (match (copy-values copying fields)
           ((Pair fields copying) (Pair (RecordValue name fields) copying))))
        ((ArrayValue items)
         (match (copy-values copying items)
           ((Pair items copying) (Pair (ArrayValue items) copying))))
        ((ClosureValue expr env self)
         (let ((names (table-keys env)))
           (match (copy-values copying (map (lambda (name) (table-ref-or env name)) names))
             ((Pair values copying)
              (Pair (ClosureValue expr (fold-left (lambda (env pair)
                                                    (table-set env (● pair first) (● pair second)))
                                                  empty-table (zip names values)) self)
                    copying)))))))

    (define (table-ref-or (table (Table Known)) (name String)) (→ Known)
      (match (table-ref table name)
        ((Some value) value)
        ((None) (panic "internal error: missing constant binding"))))

    (define (copy-values (copying Copying) (values (List Known))) (→ (Pair (List Known) Copying))
      (match values
        ((Nil) (Pair (Nil) copying))
        ((Cons first rest)
         (match (copy-known copying first)
           ((Pair first copying)
            (match (copy-values copying rest)
              ((Pair rest copying) (Pair (Cons first rest) copying))))))))

    ;; ---- Floating-point values ----

    (define (literal-value (ev Evaluation) (type Type) (datum Datum) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match datum
        ((DFloat text)
         (match (read-real text)
           ((Some value) (real-result ev type value))
           ((None) (compile-error loc "invalid floating-point constant"))))
        (_ (scalar ev type datum))))

    (define (real-value (value Known) (loc Loc)) (→ F64) (! compile)
      (match (● value value)
        ((RealValue value) value)
        ((Scalar (DInt value)) (integer-real value))
        (_ (compile-error loc "constant evaluation expected a floating-point number"))))

    (define (real-result (ev Evaluation) (type Type) (value F64)) (→ (Pair Known Evaluation))
      (Pair
       (Known type (RealValue (if (string=? (type-key type) "F32") (round-single value) value)))
       ev))

    (define (real-operation (ev Evaluation)
                            (operation String)
                            (args (List Known))
                            (type Type)
                            (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let* ((op (substring operation 4 (string-length operation)))
             (a (real-value (list-ref args 0) loc))
             (b (if (= (length args) 2) (real-value (list-ref args 1) loc) 0.0)))
        (case op
          (("eq") (scalar ev type (DBool (= a b))))
          (("lt") (scalar ev type (DBool (< a b))))
          (("le") (scalar ev type (DBool (<= a b))))
          (("gt") (scalar ev type (DBool (> a b))))
          (("ge") (scalar ev type (DBool (>= a b))))
          (else (real-result ev type
                             (case op
                               (("add") (+ a b))
                               (("sub") (- a b))
                               (("mul") (* a b))
                               (("div") (/ a b))
                               (("negate") (bits-real (i64-xor (real-bits a) -9223372036854775808)))
                               (("abs") (bits-real (i64-and (real-bits a) 9223372036854775807)))
                               (("min") (real-minmax a b #t))
                               (("max") (real-minmax a b #f))
                               (("sqrt") (if (< a 0.0) (bits-real 9221120237041090560) (sqrt a)))
                               (("floor" "ceiling" "truncate" "round") (real-round op a))
                               (else (compile-error loc
                                                    (string-append "unknown float primitive: "
                                                                   operation)))))))))

    (define (real-minmax (a F64) (b F64) (minimum? Bool)) (→ F64)
      (cond ((or (not (= a a)) (not (= b b))) (bits-real 9221120237041090560))
            ((and (= a 0.0) (= b 0.0))
             (bits-real (if minimum? (i64-or (real-bits a) (real-bits b))
                            (i64-and (real-bits a) (real-bits b)))))
            ((if minimum? (< a b) (> a b)) a)
            (else b)))

    (define (real-round (operation String) (value F64)) (→ F64)
      (let ((exponent (i64-and (i64-shift-right/logical (real-bits value) 52) 2047)))
        (if (= exponent 2047) value
            (let ((result (case operation
                            (("floor") (floor value))
                            (("ceiling") (ceiling value))
                            (("truncate") (truncate value))
                            (else (round value)))))
              (if (= result 0.0)
                  (bits-real (i64-and (real-bits value) -9223372036854775808))
                  result)))))

    (define (truncate-real (ev Evaluation) (type Type) (value F64) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let* ((value (real-round "truncate" value)) (small? (string=? (type-key type) "I32"))
             (limit (if small? 2147483648.0 9223372036854775808.0)))
        (unless (and (>= value (- 0.0 limit)) (< value limit))
          (compile-error loc "floating-point conversion overflow during constant evaluation"))
        (scalar ev type (DInt (real-integer value)))))

    ;; Hex literals preserve the target bits across bootstrap hosts and avoid
    ;; depending on the host's decimal printer, including negative zero.
    (define (real-datum (type Type) (value F64)) (→ Datum)
      (if (string=? (type-key type) "F32")
          (DFloat (real-hex (i32->i64 (single-bits value)) 23 8 127))
          (DFloat (real-hex (real-bits value) 52 11 1023))))

    (define (hex-digits (value I64) (digits I64)) (→ String)
      (string-generate digits
                       (lambda (index)
                         (string-ref "0123456789abcdef"
                                     (i64-and
                                      (i64-shift-right/logical value (* 4 (- (- digits 1) index)))
                                      15)))))

    (define (real-hex (bits I64) (fraction-bits I64) (exponent-bits I64) (bias I64)) (→ String)
      (let* ((sign (if (< bits 0) "-" ""))
             (maximum (- (i64-shift-left 1 exponent-bits) 1))
             (exponent (i64-and (i64-shift-right/logical bits fraction-bits) maximum))
             (fraction (i64-and bits (- (i64-shift-left 1 fraction-bits) 1)))
             (digits (quotient (+ fraction-bits 3) 4)))
        (if (= exponent maximum)
            (string-append sign
                           (if (= fraction 0)
                               "inf"
                               (string-append "nan:0x" (hex-digits fraction digits))))
            (string-append sign (if (= exponent 0) "0x0." "0x1.")
                           (hex-digits (i64-shift-left fraction (- (* digits 4) fraction-bits))
                                       digits)
                           "p" (i64->string (- (if (= exponent 0) 1 exponent) bias))))))

    ;; ---- Primitive evaluation ----

    (define (boolean-value (value Known) (loc Loc)) (→ Bool) (! compile)
      (match (● value value)
        ((Scalar (DBool value)) value)
        (_ (compile-error loc "constant evaluation expected a Boolean"))))

    (define (integer-value (value Known) (loc Loc)) (→ I64) (! compile)
      (match (● value value)
        ((Scalar (DInt value)) value)
        ((Scalar (DChar value)) (char->integer value))
        ((Scalar (DBool value)) (if value 1 0))
        (_ (compile-error loc "constant evaluation expected an integer"))))

    (define (text-value (value Known) (loc Loc)) (→ String) (! compile)
      (match (● value value)
        ((Scalar (DString value)) value)
        (_ (compile-error loc "constant evaluation expected a string"))))

    (define (array-values (ev Evaluation) (value Known) (loc Loc)) (→ (List Known)) (! compile)
      (match (● value value)
        ((Scalar (DString text))
         (map (lambda (char) (Known (TCon "Char" (Nil)) (Scalar (DChar char))))
              (string->list text)))
        ((Scalar (DBytes bytes))
         (map (lambda (byte) (Known (TCon "U8" (Nil)) (Scalar (DInt (i32->i64 (u8->i32 byte))))))
              (vector->list bytes)))
        (_ (match (object-value ev value loc)
             ((ArrayValue items) items)
             (_ (compile-error loc "constant evaluation expected an array"))))))

    (define (scalar (ev Evaluation) (type Type) (datum Datum)) (→ (Pair Known Evaluation))
      (Pair (Known type (Scalar datum)) ev))

    (define (sequence-value (ev Evaluation) (type Type) (items (List Known)) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (if (string=? (type-key type) "String")
          (scalar ev type (DString (list->string (map (lambda (value)
                                                        (integer->char (integer-value value loc)))
                                                      items))))
          (allocate ev type (ArrayValue items))))

    (define (primitive-value (ev Evaluation)
                             (name String)
                             (args (List Known))
                             (type Type)
                             (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((op (substring name 5 (string-length name)))
            (arg (lambda (index) (list-ref args index)))
            (integer (lambda (index) (integer-value (list-ref args index) loc))))
        (cond
         ((and (or (string-prefix? "i64-" op) (string-prefix? "i32-" op))
               (not (char=? (string-ref op 4) #\>)))
          (scalar ev type (integer-operation op args loc)))
         ((and (or (string-prefix? "f64-" op) (string-prefix? "f32-" op))
               (not (char=? (string-ref op 4) #\>)))
          (real-operation ev op args type loc))
         (else
          (case op
            (("i32->f64" "i64->f64" "i32->f32" "i64->f32")
             (real-result ev type (integer-real (integer 0))))
            (("f32->f64" "f64->f32") (real-result ev type (real-value (arg 0) loc)))
            (("f32->i32" "f32->i64" "f64->i32" "f64->i64")
             (truncate-real ev type (real-value (arg 0) loc) loc))
            (("f64->bits") (scalar ev type (DInt (real-bits (real-value (arg 0) loc)))))
            (("f32->bits")
             (scalar ev type (DInt (i32->i64 (single-bits (real-value (arg 0) loc))))))
            (("bits->f64") (real-result ev type (bits-real (integer 0))))
            (("bits->f32") (real-result ev type (bits-single (i64->i32 (integer 0)))))
            (("unit" "discard") (scalar ev type (DUnit)))
            (("panic")
             (compile-error loc (string-append "constant panic: " (text-value (arg 0) loc))))
            (("bool->i32" "char->i32" "u8->i32" "i32->i64") (scalar ev type (DInt (integer 0))))
            (("i64->i32") (scalar ev type (DInt (i32->i64 (i64->i32 (integer 0))))))
            (("i32->u8") (scalar ev type (DInt (i64-and (integer 0) 255))))
            (("i32->bool") (scalar ev type (DBool (not (= (integer 0) 0)))))
            (("i32->char")
             (let ((value (integer 0)))
               (when (or (< value 0) (> value 1114111) (and (>= value 55296) (< value 57344)))
                 (compile-error loc "invalid Unicode scalar in a compile-time value"))
               (scalar ev type (DChar (integer->char value)))))
            (("string-length" "array-length" "vector-length")
             (scalar ev type (DInt (length (array-values ev (arg 0) loc)))))
            (("string-ref" "array-ref" "vector-ref")
             (let ((items (array-values ev (arg 0) loc)) (index (integer 1)))
               (check-range index 1 (length items) loc)
               (Pair (list-ref items index) ev)))
            (("string-append" "vector-append")
             (sequence-value ev type (append (array-values ev (arg 0) loc)
                                             (array-values ev (arg 1) loc)) loc))
            (("substring" "subvector")
             (let ((items (array-values ev (arg 0) loc)) (start (integer 1)) (end (integer 2)))
               (check-range start (- end start) (length items) loc)
               (sequence-value ev type (take (list-drop items start) (- end start)) loc)))
            (("make-string" "make-vector" "make-array")
             (when (< (integer 0) 0)
               (compile-error loc "negative array length in a compile-time value"))
             (sequence-value ev type (map (lambda (index) (arg 1)) (iota (integer 0))) loc))
            (("string->vector" "vector->string" "array->vector" "vector->array")
             (sequence-value ev type (array-values ev (arg 0) loc) loc))
            (("vector-set")
             (let ((items (array-values ev (arg 0) loc)))
               (check-range (integer 1) 1 (length items) loc)
               (sequence-value ev type (replace-at items (integer 1) (arg 2)) loc)))
            (("vector-generate" "string-generate")
             (when (< (integer 0) 0)
               (compile-error loc "negative array length in a compile-time value"))
             (evaluating ev ((items (generate-values (arg 1) 0 (integer 0) type loc)))
                         (sequence-value ev type items loc)))
            (("string=?") (scalar ev type (DBool (string=? (text-value (arg 0) loc)
                                                           (text-value (arg 1) loc)))))
            (("string-compare")
             (let ((left (text-value (arg 0) loc)) (right (text-value (arg 1) loc)))
               (scalar ev
                       type
                       (DInt
                        (cond ((string=? left right) 0) ((string<? left right) -1) (else 1))))))
            ;; Total wrappers may use private, newly allocated scratch. Its
            ;; writes stay inside this interpreter's heap, never a host heap.
            (("unsafe-total") (invoke ev (arg 0) (Nil) type loc))
            (("array-set!") (array-write ev (arg 0) (integer 1) (arg 2) type loc))
            (("array-copy!" "vector-copy!")
             (array-copy ev (arg 0) (integer 1) (arg 2) (integer 3) (integer 4) type loc))
            (else (compile-error loc
                                 (string-append
                                  "primitive is not available during constant evaluation: "
                                  op))))))))

    (define (string-prefix? (prefix String) (text String)) (→ Bool)
      (and (<= (string-length prefix) (string-length text))
           (string=? prefix (substring text 0 (string-length prefix)))))

    (define (check-range (start I64) (count I64) (size I64) (loc Loc)) (→ Unit) (! compile)
      (when (or (< start 0) (< count 0) (> start size) (> count (- size start)))
        (compile-error loc "array index out of bounds during constant evaluation")))

    (define (generate-values (ev Evaluation) (function Known) (index I64) (size I64)
                             (type Type) (loc Loc))
      (→ (Pair (List Known) Evaluation)) (! compile)
      (if (= index size) (Pair (Nil) ev)
          (let ((element (match type
                           ((TCon "String" _) (TCon "Char" (Nil)))
                           ((TCon _ (Cons element _)) element)
                           (_ (panic "internal error: array type")))))
            (evaluating ev
                        ((value
                          (invoke function (list (Known (TCon "I64" (Nil)) (Scalar (DInt index))))
                                  element loc))
                         (rest (generate-values function (+ index 1) size type loc)))
                        (Pair (Cons value rest) ev)))))

    (define (array-write (ev Evaluation)
                         (array Known)
                         (index I64)
                         (value Known)
                         (type Type)
                         (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((items (array-values ev array loc)))
        (check-range index 1 (length items) loc)
        (match (● array value)
          ((Object id)
           (scalar (Evaluation-heap-set ev (table-set (● ev heap) id
                                                      (ArrayValue (replace-at items index value))))
                   type
                   (DUnit)))
          (_ (compile-error loc
                            "a literal string or byte sequence is not mutable compiler scratch")))))

    (define (array-copy (ev Evaluation) (destination Known) (at I64) (source Known) (from I64)
                        (count I64) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((target (array-values ev destination loc)) (source (array-values ev source loc)))
        (check-range at count (length target) loc)
        (check-range from count (length source) loc)
        (match (● destination value)
          ((Object id)
           (scalar (Evaluation-heap-set ev (table-set (● ev heap) id
                                                      (ArrayValue (map-indexed (lambda (index old)
                                                                                 (if
                                                                                  (and (>= index at)
                                                                                       (<
                                                                                        (- index at)
                                                                                        count))
                                                                                  (list-ref source
                                                                                            (+ from
                                                                                               (-
                                                                                                index
                                                                                                at)))
                                                                                  old))
                                                                               target))))
                   type (DUnit)))
          (_ (compile-error loc "constant copy destination must be an allocated array")))))

    ;; Keep target integer semantics on both the unbounded Chez host and
    ;; Wasm. Intermediate host overflow is reduced to its low 64 bits.
    (define (word64 (value I64)) (→ I64)
      (let ((low (i64-and value 9223372036854775807)))
        (if (= (i64-and (i64-shift-right/logical value 63) 1) 0) low
            (- (- low 9223372036854775807) 1))))

    (define (logical-right (value I64) (amount I64) (bits I64)) (→ I64)
      (if (= amount 0) value
          (i64-and (i64-shift-right/logical value amount)
                   (word64 (- (i64-shift-left 1 (- bits amount)) 1)))))

    (define (signed-right (value I64) (amount I64) (bits I64)) (→ I64)
      (if (or (= amount 0) (>= value 0)) (logical-right value amount bits)
          (i64-or (logical-right value amount bits)
                  (word64 (i64-shift-left -1 (- bits amount))))))

    (define (integer-operation (operation String) (args (List Known)) (loc Loc))
      (→ Datum)
      (! compile)
      (let* ((bits (if (string-prefix? "i32" operation) 32 64))
             (op (substring operation 4 (string-length operation)))
             (a (integer-value (list-ref args 0) loc))
             (b (integer-value (list-ref args 1) loc))
             (amount (i64-and b (- bits 1)))
             (wrap (lambda (value) (if (= bits 32) (i32->i64 (i64->i32 value)) (word64 value)))))
        (case op
          (("eq") (DBool (= a b)))
          (("lt") (DBool (< a b)))
          (("le") (DBool (<= a b)))
          (("gt") (DBool (> a b)))
          (("ge") (DBool (>= a b)))
          (else
           (DInt (wrap
                  (case op
                    (("add") (+ a b))
                    (("sub") (- a b))
                    (("mul") (* a b))
                    (("and") (i64-and a b))
                    (("or") (i64-or a b))
                    (("xor") (i64-xor a b))
                    (("shift-left") (i64-shift-left a amount))
                    (("shift-right/logical") (logical-right a amount bits))
                    (("shift-right") (signed-right a amount bits))
                    (("quotient" "remainder")
                     (when (= b 0)
                       (compile-error loc "division by zero during constant evaluation"))
                     (when (and (string=? op "quotient") (= b -1)
                                (= a (if (= bits 32) -2147483648 -9223372036854775808)))
                       (compile-error loc "integer division overflow during constant evaluation"))
                     (if (string=? op "quotient") (quotient a b)
                         (if (= b -1) 0 (remainder a b))))
                    (else (compile-error loc
                                         (string-append "unknown integer primitive: "
                                                        operation))))))))))

    ;; ---- Reification ----

    ;; A factory allocates its graph once per call. Each object's children
    ;; are named before the object, so repeated fields share one local.
    (struct Reifying
      ((evaluation Evaluation)
       (done (Table Expr))
       (active (List String))
       (bindings (List (Pair String Expr)))))

    (define (reify (ev Evaluation) (value Known) (loc Loc)) (→ Expr) (! compile)
      (match (reify-value (Reifying ev empty-table (Nil) (Nil)) value loc)
        ((Pair result reifying)
         (fold-left (lambda (body binding)
                      (Expr (Let (● binding first) (● binding second) body) (● body type) loc))
                    result (● reifying bindings)))))

    (define (reify-value (r Reifying) (value Known) (loc Loc)) (→ (Pair Expr Reifying)) (! compile)
      (match (● value value)
        ((Scalar datum) (Pair (Expr (Lit datum) (● value type) loc) r))
        ((RealValue number)
         (Pair (Expr (Lit (real-datum (● value type) number)) (● value type) loc) r))
        ((Global name) (Pair (Expr (Var name (Nil) (Nil)) (● value type) loc) r))
        ((Object id)
         (match (table-ref (● r done) id)
           ((Some result) (Pair result r))
           ((None) (reify-object r id value loc))))))

    (define (reify-object (r Reifying) (id String) (value Known) (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (when (member? id (● r active))
        (compile-error loc "a compile-time object graph cannot contain a mutable cycle"))
      (let* ((name (string-append "%constant." id))
             (read (Expr (Var name (Nil) (Nil)) (● value type) loc))
             (outer (● r active))
             (r (Reifying-active-set r (Cons id outer))))
        (match (reify-object-value r
                                   name
                                   (● value type)
                                   (object-value (● r evaluation) value loc)
                                   loc)
          ((Pair expression r)
           (Pair read (Reifying-bindings-set
                       (Reifying-done-set (Reifying-active-set r outer)
                                          (table-set (● r done) id read))
                       (Cons (Pair name expression) (● r bindings))))))))

    (define (reify-object-value (r Reifying)
                                (name String)
                                (type Type)
                                (object ObjectValue)
                                (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (match object
        ((RecordValue constructor fields)
         (match (reify-values r fields loc)
           ((Pair fields r) (Pair (constant-call constructor fields type loc) r))))
        ((ArrayValue items)
         (match (reify-values r items loc)
           ((Pair items r) (Pair (constant-call "prim:constant-array" items type loc) r))))
        ((ClosureValue expr env self)
         (let ((names (table-keys env)))
           (match (reify-values r (map (lambda (name) (table-ref-or env name)) names) loc)
             ((Pair values r)
              (let ((bindings (zip names values)))
                (Pair (substitute-locals
                       (match self
                         ((Some old)
                          (Cons (Pair old (Expr (Var name (Nil) (Nil)) type loc)) bindings))
                         ((None) bindings)) expr) r))))))))

    (define (reify-values (r Reifying) (values (List Known)) (loc Loc))
      (→ (Pair (List Expr) Reifying)) (! compile)
      (match values
        ((Nil) (Pair (Nil) r))
        ((Cons first rest)
         (match (reify-value r first loc)
           ((Pair first r)
            (match (reify-values r rest loc)
              ((Pair rest r) (Pair (Cons first rest) r))))))))

    (define (constant-call (name String) (args (List Expr)) (type Type) (loc Loc)) (→ Expr)
      (Expr (App (Expr (Var name (Nil) (Nil))
                       (TFun (map (lambda (arg) (● arg type)) args) type empty-row) loc) args)
            type
            loc))

    (define (substitute-locals (bindings (List (Pair String Expr))) (expr Expr)) (→ Expr)
      (match (● expr term)
        ((Var name _ _)
         (match (assoc-ref bindings name) ((Some value) value) ((None) expr)))
        (_ (map-expression (lambda (child) (substitute-locals bindings child)) expr))))

    ;; One structural walk used by both capture substitution and the final
    ;; rewrite of value references. Names are already resolved and unique.
    (define (map-expression (visit (Fn Expr → Expr)) (expr Expr)) (→ Expr)
      (Expr (match (● expr term)
              ((Lambda params body captures?) (Lambda params (visit body) captures?))
              ((App callee args) (App (visit callee) (map visit args)))
              ((If test yes no) (If (visit test) (visit yes) (visit no)))
              ((Let name value body) (Let name (visit value) (visit body)))
              ((Seq first rest) (Seq (visit first) (visit rest)))
              ((Match value clauses)
               (Match (visit value)
                      (map (lambda (clause) (Clause (● clause pattern) (visit (● clause body))))
                           clauses)))
              ((Ann value type) (Ann (visit value) type))
              ((Convert value type) (Convert (visit value) type))
              ((TypeTest value type) (TypeTest (visit value) type))
              ((Handle effect implementations body)
               (Handle effect
                       (map (lambda (entry) (Pair (● entry first) (visit (● entry second))))
                            implementations)
                       (visit body)))
              (term term))
            (● expr type) (● expr loc)))

    ;; ---- Preparation ----

    (define (fold-constants (state State) (items (List Item)))
      (→ (Pair (List Item) State))
      (! compile)
      (let ((ev (Evaluation state empty-table empty-table (Nil) empty-table 0)))
        (match (constant-items ev items)
          ((Pair items ev)
           (Pair (map (lambda (item) (rewrite-item (● ev state) item)) items) (● ev state))))))

    (define (constant-items (ev Evaluation) (items (List Item)))
      (→ (Pair (List Item) Evaluation)) (! compile)
      (match items
        ((Nil) (Pair (Nil) ev))
        ((Cons first rest)
         (evaluating ev ((first (constant-item first)) (rest (constant-items rest)))
                     (Pair (Cons first rest) ev)))))

    (define (constant-item (ev Evaluation) (item Item)) (→ (Pair Item Evaluation)) (! compile)
      (match item
        ((Define name value)
         (if (constant-binding? (● ev state) name)
             (evaluating ev ((known (force-value name (● value loc))))
                         (Pair (Define name (Expr (Lambda (Nil) (reify ev known (● value loc)) #f)
                                                  (TFun (Nil) (● value type) empty-row)
                                                  (● value loc)))
                               ev))
             (Pair item ev)))
        (_ (Pair item ev))))

    (define (rewrite-item (state State) (item Item)) (→ Item)
      (match item
        ((Define name value) (Define name (rewrite-references state value)))
        (_ item)))

    (define (rewrite-references (state State) (expr Expr)) (→ Expr)
      (match (● expr term)
        ((Var name _ _)
         (if (constant-binding? state name)
             (constant-call name (Nil) (● expr type) (● expr loc))
             expr))
        (_ (map-expression (lambda (child) (rewrite-references state child)) expr))))

    (define (constant-declarations (declarations Declarations)) (→ Declarations)
      (Declarations (● declarations program) (● declarations owner) (● declarations control)
                    (fold-left (lambda (bindings name)
                                 (match (table-ref (● declarations bindings) name)
                                   ((Some binding)
                                    (table-set bindings name
                                               (if (● binding function?) binding
                                                   (Binding (TFun (Nil) (● binding type) empty-row)
                                                            #t
                                                            (● binding external?)))))
                                   ((None) bindings)))
                               empty-table (table-keys (● declarations bindings)))))

    ))
