;; Concrete runtime datums. Recursive data stays in Lofi; Rust receives only
;; scalar characters, number fields and owned temporary IDs, never Lofi roots.
(define-library (lofi datum)
  (export Symbol string->symbol symbol->string symbol=? i64->string
          Scalar exact-scalar rational-scalar inexact-scalar scalar->f64 scalar-equivalent?
          Number exact-number rational-number inexact-number complex-number number->f64 number-equivalent?
          NumberResult not-a-number parsed-number number-error parsed-number-value number-error-text
          string->number string->number/radix string->atom identifier? datum-fail
          ReadResult read-end read-value read-error read-value-datum read-error-message
          Datum datum-null datum-boolean datum-character datum-string datum-symbol datum-number
          datum-pair datum-vector datum-bytevector datum=? datum-cons datum-car datum-cdr
          datum-set-car! datum-set-cdr! datum-number? datum-number-value datum-string-value datum-symbol-value
          datum-null? datum-pair? datum-truth? datum-eq? datum-kind
          datum-boolean-value datum-character-value datum-vector-values datum-bytevector-values
          datum-list datum-length datum-append datum-assq datum-map
          test-datum)
  (import (lofi base) (lofi bytes) (lofi integer) (lofi rational) (lofi number)
          (only (lofi primitive) i64-wrapping-add i64-wrapping-mul))

  ;; ---- Explicit scalar service ownership ----

  (begin
    (define-extern token-open "snail.library" "snail:datum/token-open" (-> I32))
    (define-extern token-character "snail.library" "snail:datum/token-character" (-> I32 Char Unit))
    (define-extern token-close "snail.library" "snail:datum/token-close" (-> I32 Unit))
    (define-extern token-parse "snail.library" "snail:datum/token-parse" (-> I32 I32))
    (define-extern token-parse-radix "snail.library" "snail:datum/token-parse-radix" (-> I32 I32 I32))
    (define-extern token-identifier "snail.library" "snail:datum/token-identifier" (-> I32 I32))
    (define-extern token-intern "snail.library" "snail:datum/token-intern" (-> I32 I32))
    (define-extern raw-number-kind "snail.library" "snail:datum/number-kind" (-> I32 I32 I32))
    (define-extern raw-number-integer "snail.library" "snail:datum/number-integer" (-> I32 I32 I64))
    (define-extern raw-number-real "snail.library" "snail:datum/number-real" (-> I32 I32 F64))
    (define-extern raw-number-radix "snail.library" "snail:datum/number-radix" (-> I32 I32 I32))
    (define-extern raw-number-scale "snail.library" "snail:datum/number-scale" (-> I32 I32 I64))
    (define-extern raw-number-text-length "snail.library" "snail:datum/number-text-length" (-> I32 I32 I32 I32))
    (define-extern raw-number-text-character "snail.library" "snail:datum/number-text-character" (-> I32 I32 I32 I32 Char))
    (define-extern error-length "snail.library" "snail:datum/error-length" (-> I32 I32))
    (define-extern error-character "snail.library" "snail:datum/error-character" (-> I32 I32 Char))
    (define-extern raw-fail "snail.library" "snail:datum/fail" (-> I32 Unit))
    (define-extern symbol-length "snail.library" "snail:datum/symbol-length" (-> I32 I64))
    (define-extern symbol-character "snail.library" "snail:datum/symbol-character" (-> I32 I32 Char))

    ;; The caller owns this ID until close or intern consumes it. These loops
    ;; invoke no user callbacks. Rust trap cleanup releases outstanding tokens.

    (def stage-text (-> String I32)
         (lambda (text)
           (begin (let lofi-migration-let-1 (token-open)) (let lofi-migration-let-2 (string-length text))
                  (let handle lofi-migration-let-1)
                  (let count lofi-migration-let-2)
                  (begin
                    (def loop
                         (lambda (index)
                           (if (= index count)
                               handle
                               (begin (token-character handle (string-ref text index))
                                      (loop (+ index (ann 1 I64)))))))
                    (loop (ann 0 I64))))))

    (def datum-fail (-> String Never)
         (lambda (message)
           (begin (raw-fail (stage-text message)) (unreachable))))

    (def identifier? (-> String Bool)
         (lambda (text)
           (begin (let handle (stage-text text))
                  (begin (let valid (token-identifier handle))
                         (begin
                           (token-close handle) (i32-eq valid (ann 1 I32)))))))

    ;; ---- Interned symbols, independent of the legacy literal domain ----

    (def Symbol (datatype () (symbol (id I32 symbol-id))))

    (def string->symbol (-> String Symbol)
         (lambda (text) (symbol (token-intern (stage-text text)))))

    (def symbol=? (-> Symbol Symbol Bool)
         (lambda (left right) (i32-eq (symbol-id left) (symbol-id right))))

    (def symbol->string (-> Symbol String)
         (lambda (value)
           (begin (let id (symbol-id value))
                  (begin (let count (symbol-length id))
                         (begin (let result (make-string count))
                                (begin
                                  (def loop
                                       (lambda (index)
                                         (if (= index count)
                                             result
                                             (begin (string-set! result index (symbol-character id (i64->i32 index)))
                                                    (loop (+ index (ann 1 I64)))))))
                                  (loop (ann 0 I64))))))))

    ;; ---- Exact lexical fields become Lofi-owned numeric values ----

    (def NumberResult (datatype () (not-a-number)
                                (parsed-number (value Number parsed-number-value))
                                (number-error (message String number-error-text))))

    (def token-exact-text (-> I32 I32 I32 String)
         (lambda (handle part term)
           (begin (let count (i32->i64 (raw-number-text-length handle part term)))
                  (begin (let text (make-string count))
                         (begin
                           (def loop
                                (lambda (at)
                                  (if (= at count)
                                      text
                                      (begin (string-set! text at (raw-number-text-character handle part term (i64->i32 at)))
                                             (loop (+ at (ann 1 I64)))))))
                           (loop (ann 0 I64)))))))

    (def token-rational (-> I32 I32 String Rational)
         (lambda (handle part numerator-text)
           (begin (let radix (i32->i64 (raw-number-radix handle part)))
                  (begin (let scale (raw-number-scale handle part))
                         (begin (let numerator (integer-from-string/radix numerator-text radix))
                                (begin (let denominator (integer-from-string/radix (token-exact-text handle part (ann 1 I32)) radix))
                                       (begin (let factor (integer-power (integer-from-i64 (ann 10 I64)) (if (< scale (ann 0 I64)) (- (ann 0 I64) scale) scale)))
                                              (if (< scale (ann 0 I64))
                                                  (make-rational numerator (integer-multiply denominator factor))
                                                  (make-rational (integer-multiply numerator factor) denominator)))))))))

    (def token-exact-scalar (-> I32 I32 I32 Scalar)
         (lambda (handle part kind)
           (begin (let text (token-exact-text handle part (ann 0 I32)))
                  (begin (let value (token-rational handle part text))
                         (if (i32-eq kind (ann 5 I32))
                             (scalar-from-rational value)
                             ;; Exact zero has no sign, so retain the lexical sign until #i has
                             ;; produced its binary64 zero. Nonzero underflow keeps its own sign.
                             (inexact-scalar (if (if (rational-zero? value) (char=? (string-ref text (ann 0 I64)) #\-) #f)
                                                 (* -1.0 0.0)
                                                 (rational->f64 value))))))))

    (def token-scalar (-> I32 I32 Scalar)
         (lambda (handle part)
           (begin (let kind (raw-number-kind handle part))
                  (if (i32-eq kind (ann 1 I32))
                      (exact-scalar (raw-number-integer handle part))
                      (if (i32-eq kind (ann 2 I32))
                          (inexact-scalar (raw-number-real handle part))
                          (token-exact-scalar handle part kind))))))

    (def token-error-text (-> I32 String)
         (lambda (handle)
           (begin (let count (i32->i64 (error-length handle)))
                  (begin (let result (make-string count))
                         (begin
                           (def loop
                                (lambda (index)
                                  (if (= index count)
                                      result
                                      (begin (string-set! result index (error-character handle (i64->i32 index)))
                                             (loop (+ index (ann 1 I64)))))))
                           (loop (ann 0 I64)))))))

    (def token-polar-result (-> I32 I32 NumberResult)
         (lambda (handle kind)
           (begin (let lofi-migration-let-3 (token-scalar handle (ann 0 I32))) (let lofi-migration-let-4 (token-scalar handle (ann 1 I32)))
                  (let radius lofi-migration-let-3)
                  (let angle lofi-migration-let-4)
                  (if (if (i32-eq kind (ann 8 I32))
                          (not (if (if (scalar-exact? radius) (scalar-zero? radius) #f)
                                   #t
                                   (if (scalar-exact? angle) (scalar-zero? angle) #f)))
                          #f)
                      (number-error "exact nonaxis polar number is not supported")
                      (parsed-number (number-polar radius angle))))))

    (def token-number-result (-> I32 I32 NumberResult)
         (lambda (handle kind)
           (if (i32-eq kind (ann 0 I32))
               (not-a-number)
               (if (i32-eq kind (ann 4 I32))
                   (number-error (token-error-text handle))
                   (if (i32-eq kind (ann 3 I32))
                       (parsed-number (number-rectangular (token-scalar handle (ann 0 I32)) (token-scalar handle (ann 1 I32))))
                       (if (if (i32-eq kind (ann 7 I32)) #t (i32-eq kind (ann 8 I32)))
                           (token-polar-result handle kind)
                           (parsed-number (number-from-scalar (token-scalar handle (ann 0 I32))))))))))

    (def string->number/radix (-> String I64 NumberResult)
         (lambda (text radix)
           (if (not (if (= radix (ann 2 I64)) #t (if (= radix (ann 8 I64)) #t (if (= radix (ann 10 I64)) #t (= radix (ann 16 I64))))))
               (number-error "string->number: radix must be 2, 8, 10 or 16")
               (begin (let handle (stage-text text))
                      (begin (let kind (token-parse-radix handle (i64->i32 radix)))
                             (begin (let result (token-number-result handle kind))
                                    (begin
                                      (token-close handle) result)))))))
    (define-overload string->number (-> String NumberResult)
      (lambda (text) (string->number/radix text (ann 10 I64))))
    (define-overload string->number (-> String I64 NumberResult) string->number/radix)

    ;; ---- Recursive datums and explicit mutable pair fields ----

    (def Datum (datatype ()
                         (datum-null) (datum-boolean (value Bool datum-boolean-value))
                         (datum-character (value Char datum-character-value))
                         (datum-string (value String datum-string-value))
                         (datum-symbol (value Symbol datum-symbol-value))
                         (datum-number (value Number datum-number-value))
                         (pair-datum (first (Ref Datum) datum-first) (rest (Ref Datum) datum-rest)
                                     (identity I64 pair-datum-identity))
                         (vector-datum (values (Vector Datum) datum-vector-values) (identity I64 vector-datum-identity))
                         (datum-bytevector (values Bytevector datum-bytevector-values))))

    ;; ---- A shared result for atom interpretation and incremental input ----

    (def ReadResult (datatype () (read-end)
                              (read-value (datum Datum read-value-datum))
                              (read-error (message String read-error-message))))

    (def token-number-datum (-> I32 I32 ReadResult)
         (lambda (handle kind)
           (begin (let result (token-number-result handle kind))
                  (begin
                    (token-close handle)
                    (match result
                      ((parsed-number number) (read-value (datum-number number)))
                      ((number-error message) (read-error message)) ((not-a-number) (unreachable)))))))
    ;; No callback runs while this ID is owned. Numeric results and invalid
    ;; identifiers close once; symbol interning consumes the same parsed text.
    ;; EOF belongs to input, so string->atom never constructs read-end.

    (def string->atom (-> String ReadResult)
         (lambda (text)
           (begin (let handle (stage-text text))
                  (begin (let kind (token-parse handle))
                         (if (i32-eq kind (ann 0 I32))
                             (if (i32-eq (token-identifier handle) (ann 1 I32))
                                 (read-value (datum-symbol (symbol (token-intern handle))))
                                 (begin (token-close handle)
                                        (read-error "invalid numeric token or identifier")))
                             (token-number-datum handle kind))))))

    ;; ---- Explicit mutable pair fields ----

    ;; These private constructors attach IDs to immutable views, not to storage.
    ;; Two views of the same Refs/array may have different IDs; datum-eq? below
    ;; still reports their shared storage. Child reads return the stored view.
    ;; Never recycling an ID lets a comparison remember it without rooting the
    ;; object. The only global state is a scalar; it retains no Lofi graph.
    (def next-datum-identity
         (ref (ann 1 I64)))

    (def fresh-datum-identity (-> I64)
         (lambda ()
           (begin (let identity (ref-get next-datum-identity))
                  (if (= identity (ann 9223372036854775807 I64))
                      (datum-fail "datum: recursive view identity exhausted")
                      (begin (ref-set! next-datum-identity (+ identity (ann 1 I64))) identity)))))

    (def datum-pair (-> (Ref Datum) (Ref Datum) Datum)
         (lambda (first rest) (pair-datum first rest (fresh-datum-identity))))

    (def datum-vector (-> (Vector Datum) Datum)
         (lambda (values) (vector-datum values (fresh-datum-identity))))

    (def datum-cons (-> Datum Datum Datum)
         (lambda (first rest) (datum-pair (ref first) (ref rest))))

    (def datum-car (-> Datum Datum)
         (lambda (pair) (ref-get (datum-first pair))))

    (def datum-cdr (-> Datum Datum)
         (lambda (pair) (ref-get (datum-rest pair))))

    (def datum-set-car! (-> Datum Datum Unit)
         (lambda (pair value) (ref-set! (datum-first pair) value)))

    (def datum-set-cdr! (-> Datum Datum Unit)
         (lambda (pair value) (ref-set! (datum-rest pair) value)))

    (def datum-kind (-> Datum I64)
         (lambda (value)
           (match value
             ((datum-null) (ann 0 I64)) ((datum-boolean value) (ann 1 I64)) ((datum-character value) (ann 2 I64))
             ((datum-string value) (ann 3 I64)) ((datum-symbol value) (ann 4 I64)) ((datum-number value) (ann 5 I64))
             ((pair-datum first rest identity) (ann 6 I64)) ((vector-datum values identity) (ann 7 I64)) ((datum-bytevector values) (ann 8 I64)))))

    (def datum-number? (-> Datum Bool)
         (lambda (value) (= (datum-kind value) (ann 5 I64))))

    (def datum-null? (-> Datum Bool)
         (lambda (value) (= (datum-kind value) (ann 0 I64))))

    (def datum-pair? (-> Datum Bool)
         (lambda (value) (= (datum-kind value) (ann 6 I64))))

    (def datum-truth? (-> Datum Bool)
         (lambda (value)
           (if (= (datum-kind value) (ann 1 I64)) (datum-boolean-value value) #t)))

    ;; ---- Atomic equivalence and mutable storage identity ----

    ;; Scalars compare by value, including the Number equivalence above.
    ;; Mutable values compare their underlying storage. A datum-pair wrapper is
    ;; a view of its two Ref fields: two wrappers sharing both fields identify
    ;; the same logical pair. Sharing just one field does not identify a pair.
    ;; datum-cons always creates fresh fields, matching ordinary cons identity.

    (def datum-eq? (-> Datum Datum Bool)
         (lambda (left right)
           (if (= (datum-kind left) (datum-kind right))
               (match left
                 ((datum-null) #t)
                 ((datum-boolean left) (if left (datum-boolean-value right) (not (datum-boolean-value right))))
                 ((datum-character left) (char=? left (datum-character-value right)))
                 ((datum-string left) (string-eq? left (datum-string-value right)))
                 ((datum-symbol left) (symbol=? left (datum-symbol-value right)))
                 ((datum-number left) (number-equivalent? left (datum-number-value right)))
                 ((pair-datum first rest identity)
                  (if (ref-eq? first (datum-first right)) (ref-eq? rest (datum-rest right)) #f))
                 ((vector-datum left identity) (vector-eq? left (datum-vector-values right)))
                 ((datum-bytevector left) (bytevector-eq? left (datum-bytevector-values right))))
               #f)))

    ;; ---- Proper list operations preserve elements and shared suffixes ----

    (def datum-list (-> (Rest Datum) Datum)
         (lambda values
           (begin
             (def loop
                  (lambda (values)
                    (if (null? values) (datum-null) (datum-cons (car values) (loop (cdr values))))))
             (loop values))))

    (def datum-length (-> Datum I64)
         (lambda (values)
           (begin
             (def loop
                  (lambda (values count)
                    (if (datum-null? values) count (loop (datum-cdr values) (+ count (ann 1 I64))))))
             (loop values (ann 0 I64)))))

    (def datum-append (-> Datum Datum Datum)
         (lambda (first rest)
           (if (datum-null? first)
               rest
               (datum-cons (datum-car first) (datum-append (datum-cdr first) rest)))))

    (def datum-assq (-> Datum Datum Datum)
         (lambda (key entries)
           (if (datum-null? entries)
               (datum-boolean #f)
               (begin (let entry (datum-car entries))
                      (if (datum-eq? key (datum-car entry)) entry (datum-assq key (datum-cdr entries)))))))

    (def datum-map (-> (-> Datum Datum) Datum Datum)
         (lambda (procedure values)
           (if (datum-null? values)
               (datum-null)
               (begin (let head (procedure (datum-car values)))
                      (datum-cons head (datum-map procedure (datum-cdr values)))))))

    ;; ---- Query-local comparison history ----

    ;; Remember ordered pairs of recursive view IDs before following children.
    ;; Reaching that comparison again closes a cycle or skips an already shared
    ;; subgraph. It does not assert a one-to-one mapping between the two graphs:
    ;; one-node and two-node cycles with the same unfolding compare equal.
    ;;
    ;; Zero is the empty key. At most half the slots are occupied, so every
    ;; probe terminates. The arrays contain only scalar IDs and are discarded
    ;; after this call. Neither comparison history nor pending work escapes.
    ;; Work is proportional to the visited comparison pairs with well-distributed
    ;; hashes, not necessarily to input nodes: coprime cycle lengths can visit
    ;; their product. Hash collisions can add linear probing work.
    (def EqualityHistory (datatype ()
                                   (equality-history (left (Ref (Vector I64)) history-left)
                                                     (right (Ref (Vector I64)) history-right)
                                                     (size (Ref I64) history-size))))

    (def make-equality-history (-> EqualityHistory)
         (lambda ()
           (equality-history (ref (make-vector (ann 32 I64) (ann 0 I64))) (ref (make-vector (ann 32 I64) (ann 0 I64))) (ref (ann 0 I64)))))
    ;; Mix complete I64 bit patterns with wrapping arithmetic and logical shifts.
    ;; Odd multiplication and xor-with-shift are each invertible. Mixing the
    ;; right ID before combining it with the left avoids diagonal cancellation.
    ;; These constants are signed spellings of 64-bit words; negative results
    ;; are expected. Exact keys, never hashes, decide membership. This is not
    ;; an adversarial collision guarantee.

    (def equality-mix-word (-> I64 I64)
         (lambda (word)
           (begin (let first (i64-wrapping-mul (i64-bitwise-xor word (i64-shift-right/logical word (ann 30 I64))) (ann -4658895280553007687 I64)))
                  (begin (let second (i64-wrapping-mul (i64-bitwise-xor first (i64-shift-right/logical first (ann 27 I64))) (ann -7723592293110705685 I64)))
                         (i64-bitwise-xor second (i64-shift-right/logical second (ann 31 I64)))))))

    (def equality-pair-hash (-> I64 I64 I64)
         (lambda (left right)
           (equality-mix-word (i64-bitwise-xor left (equality-mix-word (i64-wrapping-add right (ann -7046029254386353131 I64)))))))
    ;; Capacity starts at 32 and only doubles, through at most 2^31. Its mask
    ;; selects a nonnegative bucket even when the full hash has its high bit set.

    (def equality-bucket (-> I64 I64 I64 I64)
         (lambda (left right capacity)
           (i64-bitwise-and (equality-pair-hash left right) (- capacity (ann 1 I64)))))

    (def equality-slot (-> I64 I64 (Vector I64) (Vector I64) I64)
         (lambda (left right keys partners)
           (begin (let capacity (vector-length keys))
                  (begin
                    (def loop
                         (lambda (index)
                           (if (if (= (vector-ref keys index) (ann 0 I64))
                                   #t
                                   (if (= (vector-ref keys index) left) (= (vector-ref partners index) right) #f))
                               index
                               (loop (if (= (+ index (ann 1 I64)) capacity) (ann 0 I64) (+ index (ann 1 I64)))))))
                    (loop (equality-bucket left right capacity))))))

    (def place-equality-key! (-> I64 I64 (Vector I64) (Vector I64) Unit)
         (lambda (left right keys partners)
           (begin (let slot (equality-slot left right keys partners))
                  (begin
                    (vector-set! keys slot left) (vector-set! partners slot right)))))

    (def rehash-equality-keys! (-> (Vector I64) (Vector I64) (Vector I64) (Vector I64) Unit)
         (lambda (old-left old-right keys partners)
           (begin
             (def loop
                  (lambda (index)
                    (if (= index (vector-length old-left))
                        (unit)
                        (begin
                          (if (= (vector-ref old-left index) (ann 0 I64))
                              (unit)
                              (begin
                                (place-equality-key! (vector-ref old-left index) (vector-ref old-right index) keys partners)
                                (unit)))
                          (loop (+ index (ann 1 I64)))))))
             (loop (ann 0 I64)))))

    (def grow-equality-history! (-> EqualityHistory Unit)
         (lambda (history)
           (begin (let old-left (ref-get (history-left history)))
                  (begin (let old-right (ref-get (history-right history)))
                         (begin (let capacity (vector-length old-left))
                                (begin (let grown (if (> capacity (ann 1073741824 I64))
                                                      (datum-fail "datum=?: comparison history exhausted")
                                                      (* capacity (ann 2 I64))))
                                       (begin (let keys (make-vector grown (ann 0 I64)))
                                              (begin (let partners (make-vector grown (ann 0 I64)))
                                                     (begin
                                                       (rehash-equality-keys! old-left old-right keys partners)
                                                       (ref-set! (history-left history) keys) (ref-set! (history-right history) partners))))))))))

    (def equality-seen? (-> I64 I64 EqualityHistory Bool)
         (lambda (left right history)
           (begin
             (if (= (* (ref-get (history-size history)) (ann 2 I64)) (vector-length (ref-get (history-left history))))
                 (begin
                   (grow-equality-history! history)
                   (unit))
                 (unit))
             (begin (let keys (ref-get (history-left history)))
                    (begin (let partners (ref-get (history-right history)))
                           (begin (let slot (equality-slot left right keys partners))
                                  (if (= (vector-ref keys slot) left)
                                      #t
                                      (begin (vector-set! keys slot left) (vector-set! partners slot right)
                                             (ref-set! (history-size history) (+ (ref-get (history-size history)) (ann 1 I64))) #f))))))))

    ;; ---- Stack-safe equality of finite graphs ----

    ;; Pending continuations live in traced Lofi data. Every recursive call
    ;; below is a tail call, including descent through car and vector elements.
    ;; Scalar comparison retains the existing exactness, NaN and zero rules.
    ;; No input is mutated, no user procedure is called, and every call starts
    ;; with fresh history, so later pair/vector mutation is visible immediately.
    (def EqualityWork (datatype ()
                                (equality-done)
                                (equality-values (left Datum) (right Datum) (pending EqualityWork))
                                (equality-elements (left (Vector Datum)) (right (Vector Datum))
                                                   (index I64) (pending EqualityWork))))

    (def datum=? (-> Datum Datum Bool)
         (lambda (left right)
           (if (datum-eq? left right)
               #t
               (equality-compare left right (equality-done) (make-equality-history)))))

    (def equality-continue (-> EqualityWork EqualityHistory Bool)
         (lambda (work history)
           (match work
             ((equality-done) #t)
             ((equality-values left right pending) (equality-compare left right pending history))
             ((equality-elements left right index pending) (equality-vector left right index pending history)))))

    (def equality-pair (-> Datum Datum EqualityWork EqualityHistory Bool)
         (lambda (left right pending history)
           (if (equality-seen? (pair-datum-identity left) (pair-datum-identity right) history)
               (equality-continue pending history)
               (equality-compare (datum-car left) (datum-car right)
                                 (equality-values (datum-cdr left) (datum-cdr right) pending) history))))

    (def equality-vector (-> (Vector Datum) (Vector Datum) I64 EqualityWork EqualityHistory Bool)
         (lambda (left right index pending history)
           (if (= index (vector-length left))
               (equality-continue pending history)
               (equality-compare (vector-ref left index) (vector-ref right index)
                                 (equality-elements left right (+ index (ann 1 I64)) pending) history))))

    (def equality-vector-datum (-> Datum Datum EqualityWork EqualityHistory Bool)
         (lambda (left right pending history)
           (begin (let lofi-migration-let-5 (datum-vector-values left)) (let lofi-migration-let-6 (datum-vector-values right))
                  (let values lofi-migration-let-5)
                  (let others lofi-migration-let-6)
                  (if (= (vector-length values) (vector-length others))
                      (if (equality-seen? (vector-datum-identity left) (vector-datum-identity right) history)
                          (equality-continue pending history)
                          (equality-vector values others (ann 0 I64) pending history))
                      #f))))

    (def equality-compare (-> Datum Datum EqualityWork EqualityHistory Bool)
         (lambda (left right pending history)
           (if (datum-eq? left right)
               (equality-continue pending history)
               (if (= (datum-kind left) (datum-kind right))
                   (match left
                     ;; Atomic equivalence already failed. Only distinct mutable
                     ;; storage can still contain structurally equal values.
                     ((datum-null) #f) ((datum-boolean value) #f) ((datum-character value) #f)
                     ((datum-symbol value) #f) ((datum-number value) #f)
                     ((datum-string text)
                      (if (string=? text (datum-string-value right)) (equality-continue pending history) #f))
                     ((datum-bytevector bytes)
                      (if (datum-bytes=? bytes (datum-bytevector-values right))
                          (equality-continue pending history)
                          #f))
                     ((pair-datum first rest identity) (equality-pair left right pending history))
                     ((vector-datum values identity) (equality-vector-datum left right pending history)))
                   #f))))

    (def datum-bytes=? (-> Bytevector Bytevector Bool)
         (lambda (left right)
           (begin (let count (bytevector-length left))
                  (if (= count (bytevector-length right))
                      (begin
                        (def loop
                             (lambda (index)
                               (if (= index count)
                                   #t
                                   (if (= (bytevector-u8-ref left index) (bytevector-u8-ref right index))
                                       (loop (+ index (ann 1 I64)))
                                       #f))))
                        (loop (ann 0 I64)))
                      #f))))

    ;; ---- Tests ----

    ;; Test entry points are ordinary Lofi exports; no feature expansion is required.

    (def test-pair-identity
         (lambda ()
           (begin (let first (ref (datum-null)))
                  (begin (let rest (ref (datum-null)))
                         (begin (let pair (datum-pair first rest))
                                (begin (let alias (datum-pair first rest))
                                       (begin
                                         (datum-set-cdr! pair pair)
                                         (if (datum-eq? pair alias)
                                             (if (datum-eq? (datum-cdr alias) pair)
                                                 (if (not (datum-eq? pair (datum-pair first (ref pair))))
                                                     (if (not (datum-eq? pair (datum-pair (ref (datum-null)) rest)))
                                                         (not (datum-eq? pair (datum-cons (datum-null) pair)))
                                                         #f)
                                                     #f)
                                                 #f)
                                             #f))))))))
    (def test-list-sharing
         (lambda ()
           (begin (let a (datum-symbol (string->symbol "a")))
                  (begin (let b (datum-symbol (string->symbol "b")))
                         (begin (let entry (datum-cons a b))
                                (begin (let tail (datum-list b))
                                       (begin (let head (datum-list a))
                                              (begin (let joined (datum-append head tail))
                                                     (if (= (datum-length joined) (ann 2 I64))
                                                         (if (datum-eq? (datum-cdr joined) tail)
                                                             (if (not (datum-eq? head joined))
                                                                 (if (datum-eq? (datum-car joined) a)
                                                                     (if (datum-eq? (datum-assq a (datum-list entry)) entry)
                                                                         (if (not (datum-truth? (datum-assq b (datum-list entry))))
                                                                             (datum=? (datum-map (lambda (value) value) joined) joined)
                                                                             #f)
                                                                         #f)
                                                                     #f)
                                                                 #f)
                                                             #f)
                                                         #f)))))))))
    (def test-storage-identity
         (lambda ()
           (begin (let text (string-copy "a"))
                  (begin (let bytes (bytevector (ann 1 I64)))
                         (begin (let elements (vector (datum-null)))
                                (if (datum-eq? (datum-string text) (datum-string text))
                                    (if (not (datum-eq? (datum-string text) (datum-string (string-copy text))))
                                        (if (datum-eq? (datum-vector elements) (datum-vector elements))
                                            (if (not (datum-eq? (datum-vector elements) (datum-vector (vector-copy elements))))
                                                (if (datum-eq? (datum-bytevector bytes) (datum-bytevector bytes))
                                                    (not (datum-eq? (datum-bytevector bytes) (datum-bytevector (bytevector-copy bytes))))
                                                    #f)
                                                #f)
                                            #f)
                                        #f)
                                    #f))))))
    (def test-decimal
         (lambda (text)
           (begin (let number (parsed-number-value (string->number text)))
                  (match number
                    ((exact-number value) (string=? text (i64->string value)))
                    ((rational-number value) #f) ((inexact-number value) #f) ((complex-number real imaginary) #f)))))

    (def test-atom-number (-> String Bool)
         (lambda (text)
           (match (string->atom text)
             ((read-value value)
              (datum=? value (datum-number (parsed-number-value (string->number text)))))
             ((read-error message) #f) ((read-end) #f))))

    (def test-atom-error (-> String Bool)
         (lambda (text)
           (match (string->number text)
             ((number-error message)
              (match (string->atom text)
                ((read-error actual) (string=? message actual))
                ((read-value value) #f) ((read-end) #f)))
             ((parsed-number number) #f) ((not-a-number) #f))))

    (def test-invalid-atom (-> String Bool)
         (lambda (text)
           (match (string->atom text)
             ((read-error message)
              (string=? message "invalid numeric token or identifier"))
             ((read-value value) #f) ((read-end) #f))))

    (def test-atoms (-> Bool)
         (lambda ()
           (begin (let lofi-migration-let-7 (read-value-datum (string->atom "same")))
                  (let lofi-migration-let-8 (read-value-datum (string->atom (string-copy "same"))))
                  (let first lofi-migration-let-7)
                  (let second lofi-migration-let-8)
                  (if (datum-eq? first second)
                      (if (test-atom-number "42")
                          (if (test-atom-number "1.0")
                              (if (test-atom-number "1+2i")
                                  (if (test-atom-number "1/2")
                                      (if (test-atom-number "#e1.5")
                                          (if (test-atom-number "9223372036854775808")
                                              (if (test-atom-error "1/0")
                                                  (if (test-invalid-atom "123abc") (test-invalid-atom "") #f)
                                                  #f)
                                              #f)
                                          #f)
                                      #f)
                                  #f)
                              #f)
                          #f)
                      #f))))
    (def test-equality-leaves
         (lambda ()
           (if (datum=? (datum-string (string-copy "ab")) (datum-string (string-copy "ab")))
               (if (not (datum=? (datum-string "ab") (datum-string "ac")))
                   (if (datum=? (datum-bytevector (bytevector (ann 1 I64) (ann 2 I64))) (datum-bytevector (bytevector (ann 1 I64) (ann 2 I64))))
                       (if (not (datum=? (datum-bytevector (bytevector (ann 1 I64) (ann 2 I64))) (datum-bytevector (bytevector (ann 1 I64) (ann 3 I64)))))
                           (if (not (datum=? (datum-bytevector (bytevector (ann 1 I64) (ann 2 I64))) (datum-bytevector (bytevector (ann 1 I64)))))
                               (not (datum=? (datum-null) (datum-boolean #f)))
                               #f)
                           #f)
                       #f)
                   #f)
               #f)))
    (def test-equality-cycles
         (lambda ()
           (begin (let a (datum-character #\a))
                  (begin (let b (datum-character #\b))
                         (begin (let one (datum-cons a (datum-null)))
                                (begin (let two (datum-cons a one))
                                       (begin (let self (datum-cons a (datum-null)))
                                              (begin
                                                (datum-set-cdr! one two) (datum-set-cdr! self self)
                                                (if (datum=? one self)
                                                    (if (datum=? self two)
                                                        (if (begin (datum-set-car! two b) (not (datum=? self one)))
                                                            (if (begin (datum-set-car! two a) (datum=? self one))
                                                                (if (datum-eq? (datum-cdr one) two) (datum-eq? (datum-cdr self) self) #f)
                                                                #f)
                                                            #f)
                                                        #f)
                                                    #f)))))))))
    (def test-equality-pair-views
         (lambda ()
           (begin (let first (ref (datum-character #\a)))
                  (begin (let rest (ref (datum-null)))
                         (begin (let original (datum-pair first rest))
                                (begin (let alias (datum-pair first rest))
                                       (begin (let other (datum-cons (datum-character #\a) (datum-null)))
                                              (begin (let one-field (datum-pair first (ref (datum-character #\b))))
                                                     (begin (let other-field (datum-pair (ref (datum-character #\b)) rest))
                                                            (begin
                                                              (datum-set-cdr! original alias) (datum-set-cdr! other other)
                                                              (if (datum=? original alias)
                                                                  (if (datum-eq? original alias)
                                                                      (if (datum=? original other)
                                                                          (if (datum=? alias other)
                                                                              (if (not (datum=? original one-field))
                                                                                  (if (not (datum=? original other-field))
                                                                                      (if (datum-eq? (datum-cdr alias) alias)
                                                                                          (char=? (datum-character-value (ref-get first)) #\a)
                                                                                          #f)
                                                                                      #f)
                                                                                  #f)
                                                                              #f)
                                                                          #f)
                                                                      #f)
                                                                  #f)))))))))))
    (def test-equality-vector-cycles
         (lambda ()
           (begin (let left (vector (datum-null)))
                  (begin (let right (vector (datum-null)))
                         (begin (let x (datum-vector left))
                                (begin (let alias (datum-vector left))
                                       (begin (let y (datum-vector right))
                                              (begin (let a (datum-cons (datum-character #\a) x))
                                                     (begin (let b (datum-cons (datum-character #\a) y))
                                                            (begin
                                                              (vector-set! left (ann 0 I64) a) (vector-set! right (ann 0 I64) b)
                                                              (if (datum=? alias y)
                                                                  (if (datum-eq? alias x)
                                                                      (if (not (datum=? x (datum-vector (empty-vector))))
                                                                          (if (begin (datum-set-car! b (datum-character #\b)) (not (datum=? x y)))
                                                                              (if (datum-eq? (vector-ref left (ann 0 I64)) a) (datum-eq? (datum-cdr a) x) #f)
                                                                              #f)
                                                                          #f)
                                                                      #f)
                                                                  #f)))))))))))
    (def test-equality-pending-cdr
         (lambda ()
           (begin (let lofi-migration-let-9 (datum-cons (datum-null) (datum-character #\a)))
                  (let lofi-migration-let-10 (datum-cons (datum-null) (datum-character #\b)))
                  (let left lofi-migration-let-9)
                  (let right lofi-migration-let-10)
                  (begin
                    (datum-set-car! left left) (datum-set-car! right right)
                    (if (not (datum=? left right))
                        (begin (datum-set-cdr! right (datum-character #\a)) (datum=? left right))
                        #f)))))
    (def test-equality-pending-vector
         (lambda ()
           (begin (let left (vector (datum-null) (datum-character #\a)))
                  (begin (let right (vector (datum-null) (datum-character #\b)))
                         (begin (let x (datum-cons (datum-vector left) (datum-null)))
                                (begin (let y (datum-cons (datum-vector right) (datum-null)))
                                       (begin
                                         (vector-set! left (ann 0 I64) x) (vector-set! right (ann 0 I64) y)
                                         (if (not (datum=? x y))
                                             (begin (vector-set! right (ann 1 I64) (datum-character #\a)) (datum=? x y))
                                             #f))))))))
    (def test-ring
         (lambda (count)
           (begin (let root (datum-cons (datum-character #\a) (datum-null)))
                  (begin
                    (def loop
                         (lambda (count last)
                           (if (= count (ann 0 I64))
                               (begin (datum-set-cdr! last root) root)
                               (begin (let next (datum-cons (datum-character #\a) (datum-null)))
                                      (begin
                                        (datum-set-cdr! last next) (loop (- count (ann 1 I64)) next))))))
                    (loop (- count (ann 1 I64)) root)))))
    (def test-equality-coprime-cycles
         (lambda ()
           (begin (let lofi-migration-let-11 (test-ring (ann 17 I64))) (let lofi-migration-let-12 (test-ring (ann 19 I64)))
                  (let left lofi-migration-let-11)
                  (let right lofi-migration-let-12)
                  (if (datum=? left right)
                      (begin (datum-set-car! (datum-cdr right) (datum-character #\b))
                             (not (datum=? left right)))
                      #f))))
    (def test-deep-datum
         (lambda (count leaf)
           (begin
             (def loop
                  (lambda (count value)
                    (if (= count (ann 0 I64)) value (loop (- count (ann 1 I64)) (datum-cons value (datum-null))))))
             (loop count leaf))))
    (def test-equality-depth
         (lambda ()
           (begin (let lofi-migration-let-13 (test-deep-datum (ann 5000 I64) (datum-character #\a)))
                  (let lofi-migration-let-14 (test-deep-datum (ann 5000 I64) (datum-character #\a)))
                  (let lofi-migration-let-15 (test-deep-datum (ann 5000 I64) (datum-character #\b)))
                  (let left lofi-migration-let-13)
                  (let right lofi-migration-let-14)
                  (let different lofi-migration-let-15)
                  (if (datum=? left right)
                      (if (not (datum=? left different))
                          (datum=? (datum-vector (empty-vector)) (datum-vector (empty-vector)))
                          #f)
                      #f))))
    ;; Reference words were computed with independent unsigned-64 arithmetic.
    ;; Include changes above 32 bits, both result signs, and reversed keys.
    (def test-equality-hash-words
         (lambda ()
           (if (= (equality-pair-hash (ann 1 I64) (ann 1 I64)) (ann 6652587683579779273 I64))
               (if (= (equality-pair-hash (ann 1 I64) (ann 2 I64)) (ann -972091869234291113 I64))
                   (if (= (equality-pair-hash (ann 2 I64) (ann 1 I64)) (ann 583880340377267059 I64))
                       (if (= (equality-pair-hash (ann 9223372036854775807 I64) (ann 9223372036854775807 I64)) (ann 4218948218474539009 I64))
                           (if (= (equality-pair-hash (ann 1 I64) (ann 9223372036854775807 I64)) (ann 6459536036652829431 I64))
                               (if (= (equality-pair-hash (ann 9223372036854775807 I64) (ann 1 I64)) (ann -421409582817843346 I64))
                                   (if (= (equality-pair-hash (ann 2097153 I64) (ann 7 I64)) (ann 1992281314829590827 I64))
                                       (if (= (equality-pair-hash (ann 2147483649 I64) (ann 7 I64)) (ann -1548759241620248504 I64))
                                           (if (= (equality-pair-hash (ann 4294967297 I64) (ann 7 I64)) (ann 2205320672614223687 I64))
                                               (if (= (equality-pair-hash (ann 4398046511105 I64) (ann 7 I64)) (ann -2359351969197311418 I64))
                                                   (if (= (equality-pair-hash (ann 4611686018427387905 I64) (ann 7 I64)) (ann -5466481419058493644 I64))
                                                       (if (= (equality-pair-hash (ann 4611690416475996161 I64) (ann 7 I64)) (ann -5320575393637501446 I64))
                                                           (= (equality-pair-hash (ann 7 I64) (ann 4611690416475996161 I64)) (ann -1025925624717699660 I64))
                                                           #f)
                                                       #f)
                                                   #f)
                                               #f)
                                           #f)
                                       #f)
                                   #f)
                               #f)
                           #f)
                       #f)
                   #f)
               #f)))
    (def test-equality-history-high-bits
         (lambda ()
           (begin (let lofi-migration-let-16 (vector (ann 1 I64) (ann 2097153 I64) (ann 2147483649 I64) (ann 4294967297 I64) (ann 4398046511105 I64)
                                                     (ann 4611686018427387905 I64) (ann 4611690416475996161 I64) (ann 9223372036854775807 I64)))
                  (let lofi-migration-let-17 (make-equality-history))
                  (let ids lofi-migration-let-16)
                  (let history lofi-migration-let-17)
                  (begin
                    (def loop
                         (lambda (index)
                           (if (= index (vector-length ids))
                               (= (ref-get (history-size history)) (ann 16 I64))
                               (begin (let id (vector-ref ids index))
                                      (if (not (equality-seen? id (ann 7 I64) history))
                                          (if (not (equality-seen? (ann 7 I64) id history))
                                              (if (equality-seen? id (ann 7 I64) history)
                                                  (if (equality-seen? (ann 7 I64) id history) (loop (+ index (ann 1 I64))) #f)
                                                  #f)
                                              #f)
                                          #f)))))
                    (loop (ann 0 I64))))))
    (def test-insert-colliding-keys
         (lambda (keys history)
           (begin
             (def loop
                  (lambda (index)
                    (if (= index (vector-length keys))
                        #t
                        (if (if (not (= index (ann 32 I64))) #t (= (vector-length (ref-get (history-left history))) (ann 32 I64)))
                            (if (not (equality-seen? (vector-ref keys index) (vector-ref keys (+ index (ann 1 I64))) history))
                                (loop (+ index (ann 2 I64)))
                                #f)
                            #f))))
             (loop (ann 0 I64)))))
    (def test-find-colliding-keys
         (lambda (keys history)
           (begin
             (def loop
                  (lambda (index)
                    (if (= index (vector-length keys))
                        #t
                        (if (equality-seen? (vector-ref keys index) (vector-ref keys (+ index (ann 1 I64))) history)
                            (loop (+ index (ann 2 I64)))
                            #f))))
             (loop (ann 0 I64)))))
    (def test-equality-history-collisions
         (lambda ()
           ;; All keys start at bucket 31 modulo 32. Growth splits their homes
           ;; between 31 and 63, exercising wraparound and rehashing together.
           (begin (let lofi-migration-let-18 (vector (ann 23 I64) (ann 4611686018427387973 I64)
                                                     (ann 46 I64) (ann 4611686018427388042 I64)
                                                     (ann 65 I64) (ann 4611686018427388099 I64)
                                                     (ann 134 I64) (ann 4611686018427388306 I64)
                                                     (ann 189 I64) (ann 4611686018427388471 I64)
                                                     (ann 213 I64) (ann 4611686018427388543 I64)
                                                     (ann 247 I64) (ann 4611686018427388645 I64)
                                                     (ann 271 I64) (ann 4611686018427388717 I64)
                                                     (ann 284 I64) (ann 4611686018427388756 I64)
                                                     (ann 387 I64) (ann 4611686018427389065 I64)
                                                     (ann 474 I64) (ann 4611686018427389326 I64)
                                                     (ann 486 I64) (ann 4611686018427389362 I64)
                                                     (ann 506 I64) (ann 4611686018427389422 I64)
                                                     (ann 513 I64) (ann 4611686018427389443 I64)
                                                     (ann 529 I64) (ann 4611686018427389491 I64)
                                                     (ann 539 I64) (ann 4611686018427389521 I64)
                                                     (ann 541 I64) (ann 4611686018427389527 I64)
                                                     (ann 567 I64) (ann 4611686018427389605 I64)))
                  (let lofi-migration-let-19 (make-equality-history))
                  (let keys lofi-migration-let-18)
                  (let history lofi-migration-let-19)
                  (if (test-insert-colliding-keys keys history)
                      (if (= (vector-length (ref-get (history-left history))) (ann 64 I64))
                          (if (= (ref-get (history-size history)) (ann 18 I64))
                              (if (test-find-colliding-keys keys history)
                                  (if (= (ref-get (history-size history)) (ann 18 I64))
                                      (if (not (equality-seen? (ann 640 I64) (ann 4611686018427389824 I64) history))
                                          (not (equality-seen? (vector-ref keys (ann 0 I64)) (vector-ref keys (ann 1 I64)) (make-equality-history)))
                                          #f)
                                      #f)
                                  #f)
                              #f)
                          #f)
                      #f))))
    (def test-datum
         (lambda ()
           (if (if (test-pair-identity)
                   (if (test-list-sharing)
                       (if (test-storage-identity)
                           (if (test-atoms)
                               (if (test-equality-leaves)
                                   (if (test-equality-cycles)
                                       (if (test-equality-pair-views)
                                           (if (test-equality-vector-cycles)
                                               (if (test-equality-depth)
                                                   (if (test-equality-pending-cdr)
                                                       (if (test-equality-pending-vector)
                                                           (if (test-equality-coprime-cycles)
                                                               (if (test-equality-hash-words)
                                                                   (if (test-equality-history-high-bits)
                                                                       (if (test-equality-history-collisions)
                                                                           (if (datum-null? (datum-null))
                                                                               (if (datum-pair? (datum-list (datum-null)))
                                                                                   (if (datum-truth? (datum-null))
                                                                                       (if (not (datum-truth? (datum-boolean #f)))
                                                                                           (if (datum-eq? (datum-symbol (string->symbol "same"))
                                                                                                          (datum-symbol (string->symbol (string-copy "same"))))
                                                                                               (if (test-decimal "0")
                                                                                                   (if (test-decimal "42")
                                                                                                       (if (test-decimal "-42")
                                                                                                           (if (test-decimal "-9223372036854775808") (test-decimal "9223372036854775807") #f)
                                                                                                           #f)
                                                                                                       #f)
                                                                                                   #f)
                                                                                               #f)
                                                                                           #f)
                                                                                       #f)
                                                                                   #f)
                                                                               #f)
                                                                           #f)
                                                                       #f)
                                                                   #f)
                                                               #f)
                                                           #f)
                                                       #f)
                                                   #f)
                                               #f)
                                           #f)
                                       #f)
                                   #f)
                               #f)
                           #f)
                       #f)
                   #f)
               (ann 42 I64)
               (ann 0 I64))))))
