;; Concrete runtime datums. Recursive data stays in Scheme; Rust receives only
;; scalar characters, number fields and owned temporary IDs, never Scheme roots.
(define-library (snail datum)
  (export Symbol string->symbol symbol->string symbol=? i64->string
          Scalar exact-scalar inexact-scalar scalar->f64 scalar-equivalent?
          Number exact-number inexact-number complex-number number->f64 number-equivalent?
          NumberResult not-a-number parsed-number number-error parsed-number-value number-error-text
          string->number string->atom identifier? datum-fail
          ReadResult read-end read-value read-error read-value-datum read-error-message
          Datum datum-null datum-boolean datum-character datum-string datum-symbol datum-number
          datum-pair datum-vector datum-bytevector datum=? datum-cons datum-car datum-cdr
          datum-set-car! datum-set-cdr! datum-number? datum-number-value datum-string-value datum-symbol-value
          datum-null? datum-pair? datum-truth? datum-eq? datum-kind
          datum-boolean-value datum-character-value datum-vector-values datum-bytevector-values
          datum-list datum-length datum-append datum-assq datum-map)
  (import (snail strict) (snail bytes))
  (begin

    ;; ---- Explicit scalar service ownership ----

    (define-extern token-open "snail.library" "snail:datum/token-open" (-> I32))
    (define-extern token-character "snail.library" "snail:datum/token-character" (-> I32 Char Unit))
    (define-extern token-close "snail.library" "snail:datum/token-close" (-> I32 Unit))
    (define-extern token-parse "snail.library" "snail:datum/token-parse" (-> I32 I32))
    (define-extern token-identifier "snail.library" "snail:datum/token-identifier" (-> I32 I32))
    (define-extern token-intern "snail.library" "snail:datum/token-intern" (-> I32 I32))
    (define-extern raw-number-kind "snail.library" "snail:datum/number-kind" (-> I32 I32 I32))
    (define-extern raw-number-integer "snail.library" "snail:datum/number-integer" (-> I32 I32 I64))
    (define-extern raw-number-real "snail.library" "snail:datum/number-real" (-> I32 I32 F64))
    (define-extern error-length "snail.library" "snail:datum/error-length" (-> I32 I32))
    (define-extern error-character "snail.library" "snail:datum/error-character" (-> I32 I32 Char))
    (define-extern raw-fail "snail.library" "snail:datum/fail" (-> I32 Unit))
    (define-extern symbol-length "snail.library" "snail:datum/symbol-length" (-> I32 I64))
    (define-extern symbol-character "snail.library" "snail:datum/symbol-character" (-> I32 I32 Char))
    (define-extern real-equivalent "snail.library" "snail:datum/real-equivalent" (-> F64 F64 I32))

    ;; The caller owns this ID until close or intern consumes it. These loops
    ;; invoke no user callbacks. Rust trap cleanup releases outstanding tokens.
    (: stage-text (-> String I32))
    (define (stage-text text)
      (let ((handle (token-open)) (count (string-length text)))
        (let loop ((index 0))
          (if (= index count) handle
              (begin (token-character handle (string-ref text index))
                     (loop (+ index 1)))))))
    (: datum-fail (-> String Never))
    (define (datum-fail message) (raw-fail (stage-text message)) (unreachable))
    (: identifier? (-> String Bool))
    (define (identifier? text)
      (let* ((handle (stage-text text)) (valid (token-identifier handle)))
        (token-close handle) (i32-eq valid (ann 1 I32))))

    ;; ---- Interned symbols, independent of the legacy literal domain ----

    (define-data Symbol (symbol (id I32 symbol-id)))
    (: string->symbol (-> String Symbol))
    (define (string->symbol text) (symbol (token-intern (stage-text text))))
    (: symbol=? (-> Symbol Symbol Bool))
    (define (symbol=? left right) (i32-eq (symbol-id left) (symbol-id right)))
    (: symbol->string (-> Symbol String))
    (define (symbol->string value)
      (let* ((id (symbol-id value)) (count (symbol-length id))
             (result (make-string count)))
        (let loop ((index 0))
          (if (= index count) result
              (begin (string-set! result index (symbol-character id (i64->i32 index)))
                     (loop (+ index 1)))))))

    ;; Work with a nonpositive magnitude so the minimum I64 needs no positive
    ;; counterpart. Each remainder lies in [-9,0]; negating that digit is safe.
    (: decimal-digits (-> I64 I64))
    (define (decimal-digits value)
      (let loop ((value value) (count 1))
        (if (> value -10) count (loop (quotient value 10) (+ count 1)))))
    (: i64->string (-> I64 String))
    (define (i64->string value)
      (let* ((negative (< value 0)) (magnitude (if negative value (- 0 value)))
             (count (+ (decimal-digits magnitude) (if negative 1 0)))
             (text (make-string count)))
        (when negative (string-set! text 0 #\-))
        (let loop ((remaining magnitude) (index (- count 1)))
          (string-set! text index (integer->char (- 48 (remainder remaining 10))))
          (if (> remaining -10) text (loop (quotient remaining 10) (- index 1))))))

    ;; ---- Numbers preserve exactness and binary64 zero signs ----

    (define-data Scalar (exact-scalar (value I64)) (inexact-scalar (value F64)))
    (define-data Number (exact-number (value I64 exact-number-value))
      (inexact-number (value F64 inexact-number-value))
      (complex-number (real Scalar complex-real) (imaginary Scalar complex-imaginary)))
    (define-data NumberResult (not-a-number)
      (parsed-number (value Number parsed-number-value))
      (number-error (message String number-error-text)))
    (: scalar->f64 (-> Scalar F64))
    (define (scalar->f64 value)
      (match value ((exact-scalar value) (i64->f64 value)) ((inexact-scalar value) value)))
    (: number->f64 (-> Number F64))
    (define (number->f64 value)
      (match value
        ((exact-number value) (i64->f64 value)) ((inexact-number value) value)
        ((complex-number real imaginary)
         (if (= (scalar->f64 imaginary) 0.0) (scalar->f64 real)
             (datum-fail "number->f64: expected a real-valued number")))))
    (: token-scalar (-> I32 I32 Scalar))
    (define (token-scalar handle part)
      (if (i32-eq (raw-number-kind handle part) (ann 1 I32))
          (exact-scalar (raw-number-integer handle part))
          (inexact-scalar (raw-number-real handle part))))
    (: token-error-text (-> I32 String))
    (define (token-error-text handle)
      (let* ((count (i32->i64 (error-length handle))) (result (make-string count)))
        (let loop ((index 0))
          (if (= index count) result
              (begin (string-set! result index (error-character handle (i64->i32 index)))
                     (loop (+ index 1)))))))
    (: token-number-result (-> I32 I32 NumberResult))
    (define (token-number-result handle kind)
      (if (i32-eq kind (ann 0 I32)) (not-a-number)
          (if (i32-eq kind (ann 1 I32)) (parsed-number (exact-number (raw-number-integer handle (ann 0 I32))))
              (if (i32-eq kind (ann 2 I32)) (parsed-number (inexact-number (raw-number-real handle (ann 0 I32))))
                  (if (i32-eq kind (ann 3 I32))
                      (parsed-number (complex-number (token-scalar handle (ann 0 I32))
                                                     (token-scalar handle (ann 1 I32))))
                      (number-error (token-error-text handle)))))))
    (: string->number (-> String NumberResult))
    (define (string->number text)
      (let* ((handle (stage-text text)) (kind (token-parse handle))
             (result (token-number-result handle kind)))
        (token-close handle) result))

    ;; Equivalence follows the selected Chez contract: exact/inexact differ,
    ;; signed zeros differ, all NaNs are equivalent, and infinities keep sign.
    (: scalar-equivalent? (-> Scalar Scalar Bool))
    (define (scalar-equivalent? left right)
      (match left
        ((exact-scalar left) (match right ((exact-scalar right) (= left right)) ((inexact-scalar right) #f)))
        ((inexact-scalar left) (match right
                                 ((inexact-scalar right) (i32-eq (real-equivalent left right) (ann 1 I32))) ((exact-scalar right) #f)))))
    (: number-kind (-> Number I64))
    (define (number-kind value)
      (match value ((exact-number value) 0) ((inexact-number value) 1) ((complex-number real imaginary) 2)))
    (: number-equivalent? (-> Number Number Bool))
    (define (number-equivalent? left right)
      (and (= (number-kind left) (number-kind right))
           (match left
             ((exact-number left) (= left (exact-number-value right)))
             ((inexact-number left) (i32-eq (real-equivalent left (inexact-number-value right)) (ann 1 I32)))
             ((complex-number real imaginary)
              (and (scalar-equivalent? real (complex-real right))
                   (scalar-equivalent? imaginary (complex-imaginary right)))))))

    ;; ---- Recursive datums and explicit mutable pair fields ----

    (define-data Datum
      (datum-null) (datum-boolean (value Bool datum-boolean-value))
      (datum-character (value Char datum-character-value))
      (datum-string (value String datum-string-value))
      (datum-symbol (value Symbol datum-symbol-value))
      (datum-number (value Number datum-number-value))
      (pair-datum (first (Ref Datum) datum-first) (rest (Ref Datum) datum-rest)
                  (identity I64 pair-datum-identity))
      (vector-datum (values (Vector Datum) datum-vector-values) (identity I64 vector-datum-identity))
      (datum-bytevector (values Bytevector datum-bytevector-values)))

    ;; ---- A shared result for atom interpretation and incremental input ----

    (define-data ReadResult (read-end)
      (read-value (datum Datum read-value-datum))
      (read-error (message String read-error-message)))
    (: token-number-datum (-> I32 I32 ReadResult))
    (define (token-number-datum handle kind)
      (let ((result (token-number-result handle kind)))
        (token-close handle)
        (match result
          ((parsed-number number) (read-value (datum-number number)))
          ((number-error message) (read-error message)) ((not-a-number) (unreachable)))))
    ;; No callback runs while this ID is owned. Numeric results and invalid
    ;; identifiers close once; symbol interning consumes the same parsed text.
    ;; EOF belongs to input, so string->atom never constructs read-end.
    (: string->atom (-> String ReadResult))
    (define (string->atom text)
      (let* ((handle (stage-text text)) (kind (token-parse handle)))
        (if (i32-eq kind (ann 0 I32))
            (if (i32-eq (token-identifier handle) (ann 1 I32))
                (read-value (datum-symbol (symbol (token-intern handle))))
                (begin (token-close handle)
                       (read-error "invalid numeric token or identifier; rational numbers are not supported")))
            (token-number-datum handle kind))))

    ;; ---- Explicit mutable pair fields ----

    ;; These private constructors attach IDs to immutable views, not to storage.
    ;; Two views of the same Refs/array may have different IDs; datum-eq? below
    ;; still reports their shared storage. Child reads return the stored view.
    ;; Never recycling an ID lets a comparison remember it without rooting the
    ;; object. The only global state is a scalar; it retains no Scheme graph.
    (define next-datum-identity (ref 1))
    (: fresh-datum-identity (-> I64))
    (define (fresh-datum-identity)
      (let ((identity (ref-get next-datum-identity)))
        (if (= identity 9223372036854775807)
            (datum-fail "datum: recursive view identity exhausted")
            (begin (ref-set! next-datum-identity (+ identity 1)) identity))))
    (: datum-pair (-> (Ref Datum) (Ref Datum) Datum))
    (define (datum-pair first rest) (pair-datum first rest (fresh-datum-identity)))
    (: datum-vector (-> (Vector Datum) Datum))
    (define (datum-vector values) (vector-datum values (fresh-datum-identity)))
    (: datum-cons (-> Datum Datum Datum))
    (define (datum-cons first rest) (datum-pair (ref first) (ref rest)))
    (: datum-car (-> Datum Datum))
    (define (datum-car pair) (ref-get (datum-first pair)))
    (: datum-cdr (-> Datum Datum))
    (define (datum-cdr pair) (ref-get (datum-rest pair)))
    (: datum-set-car! (-> Datum Datum Unit))
    (define (datum-set-car! pair value) (ref-set! (datum-first pair) value))
    (: datum-set-cdr! (-> Datum Datum Unit))
    (define (datum-set-cdr! pair value) (ref-set! (datum-rest pair) value))
    (: datum-kind (-> Datum I64))
    (define (datum-kind value)
      (match value
        ((datum-null) 0) ((datum-boolean value) 1) ((datum-character value) 2)
        ((datum-string value) 3) ((datum-symbol value) 4) ((datum-number value) 5)
        ((pair-datum first rest identity) 6) ((vector-datum values identity) 7) ((datum-bytevector values) 8)))
    (: datum-number? (-> Datum Bool))
    (define (datum-number? value) (= (datum-kind value) 5))
    (: datum-null? (-> Datum Bool))
    (define (datum-null? value) (= (datum-kind value) 0))
    (: datum-pair? (-> Datum Bool))
    (define (datum-pair? value) (= (datum-kind value) 6))
    (: datum-truth? (-> Datum Bool))
    (define (datum-truth? value)
      (if (= (datum-kind value) 1) (datum-boolean-value value) #t))

    ;; ---- Atomic equivalence and mutable storage identity ----

    ;; Scalars compare by value, including the Number equivalence above.
    ;; Mutable values compare their underlying storage. A datum-pair wrapper is
    ;; a view of its two Ref fields: two wrappers sharing both fields identify
    ;; the same logical pair. Sharing just one field does not identify a pair.
    ;; datum-cons always creates fresh fields, matching ordinary cons identity.
    (: datum-eq? (-> Datum Datum Bool))
    (define (datum-eq? left right)
      (and (= (datum-kind left) (datum-kind right))
           (match left
             ((datum-null) #t)
             ((datum-boolean left) (if left (datum-boolean-value right) (not (datum-boolean-value right))))
             ((datum-character left) (char=? left (datum-character-value right)))
             ((datum-string left) (string-eq? left (datum-string-value right)))
             ((datum-symbol left) (symbol=? left (datum-symbol-value right)))
             ((datum-number left) (number-equivalent? left (datum-number-value right)))
             ((pair-datum first rest identity)
              (and (ref-eq? first (datum-first right)) (ref-eq? rest (datum-rest right))))
             ((vector-datum left identity) (vector-eq? left (datum-vector-values right)))
             ((datum-bytevector left) (bytevector-eq? left (datum-bytevector-values right))))))

    ;; ---- Proper list operations preserve elements and shared suffixes ----

    (: datum-list (-> (Rest Datum) Datum))
    (define (datum-list . values)
      (let loop ((values values))
        (if (null? values) (datum-null) (datum-cons (car values) (loop (cdr values))))))
    (: datum-length (-> Datum I64))
    (define (datum-length values)
      (let loop ((values values) (count 0))
        (if (datum-null? values) count (loop (datum-cdr values) (+ count 1)))))
    (: datum-append (-> Datum Datum Datum))
    (define (datum-append first rest)
      (if (datum-null? first) rest
          (datum-cons (datum-car first) (datum-append (datum-cdr first) rest))))
    (: datum-assq (-> Datum Datum Datum))
    (define (datum-assq key entries)
      (if (datum-null? entries) (datum-boolean #f)
          (let ((entry (datum-car entries)))
            (if (datum-eq? key (datum-car entry)) entry (datum-assq key (datum-cdr entries))))))
    (: datum-map (-> (-> Datum Datum) Datum Datum))
    (define (datum-map procedure values)
      (if (datum-null? values) (datum-null)
          (let ((head (procedure (datum-car values))))
            (datum-cons head (datum-map procedure (datum-cdr values))))))

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
    (define-data EqualityHistory
      (equality-history (left (Ref (Vector I64)) history-left)
                        (right (Ref (Vector I64)) history-right)
                        (size (Ref I64) history-size)))
    (: make-equality-history (-> EqualityHistory))
    (define (make-equality-history)
      (equality-history (ref (make-vector 32 0)) (ref (make-vector 32 0)) (ref 0)))
    ;; Mix complete I64 bit patterns with wrapping arithmetic and logical shifts.
    ;; Odd multiplication and xor-with-shift are each invertible. Mixing the
    ;; right ID before combining it with the left avoids diagonal cancellation.
    ;; These constants are signed spellings of 64-bit words; negative results
    ;; are expected. Exact keys, never hashes, decide membership. This is not
    ;; an adversarial collision guarantee.
    (: equality-mix-word (-> I64 I64))
    (define (equality-mix-word word)
      (let* ((first (i64-mul (i64-bitwise-xor word (i64-shift-right/logical word 30)) -4658895280553007687))
             (second (i64-mul (i64-bitwise-xor first (i64-shift-right/logical first 27)) -7723592293110705685)))
        (i64-bitwise-xor second (i64-shift-right/logical second 31))))
    (: equality-pair-hash (-> I64 I64 I64))
    (define (equality-pair-hash left right)
      (equality-mix-word (i64-bitwise-xor left (equality-mix-word (i64-add right -7046029254386353131)))))
    ;; Capacity starts at 32 and only doubles, through at most 2^31. Its mask
    ;; selects a nonnegative bucket even when the full hash has its high bit set.
    (: equality-bucket (-> I64 I64 I64 I64))
    (define (equality-bucket left right capacity)
      (i64-bitwise-and (equality-pair-hash left right) (- capacity 1)))
    (: equality-slot (-> I64 I64 (Vector I64) (Vector I64) I64))
    (define (equality-slot left right keys partners)
      (let ((capacity (vector-length keys)))
        (let loop ((index (equality-bucket left right capacity)))
          (if (or (= (vector-ref keys index) 0)
                  (and (= (vector-ref keys index) left) (= (vector-ref partners index) right)))
              index (loop (if (= (+ index 1) capacity) 0 (+ index 1)))))))
    (: place-equality-key! (-> I64 I64 (Vector I64) (Vector I64) Unit))
    (define (place-equality-key! left right keys partners)
      (let ((slot (equality-slot left right keys partners)))
        (vector-set! keys slot left) (vector-set! partners slot right)))
    (: rehash-equality-keys! (-> (Vector I64) (Vector I64) (Vector I64) (Vector I64) Unit))
    (define (rehash-equality-keys! old-left old-right keys partners)
      (let loop ((index 0))
        (if (= index (vector-length old-left)) (unit)
            (begin
              (unless (= (vector-ref old-left index) 0)
                (place-equality-key! (vector-ref old-left index) (vector-ref old-right index) keys partners))
              (loop (+ index 1))))))
    (: grow-equality-history! (-> EqualityHistory Unit))
    (define (grow-equality-history! history)
      (let* ((old-left (ref-get (history-left history))) (old-right (ref-get (history-right history)))
             (capacity (vector-length old-left))
             (grown (if (> capacity 1073741824) (datum-fail "datum=?: comparison history exhausted") (* capacity 2)))
             (keys (make-vector grown 0)) (partners (make-vector grown 0)))
        (rehash-equality-keys! old-left old-right keys partners)
        (ref-set! (history-left history) keys) (ref-set! (history-right history) partners)))
    (: equality-seen? (-> I64 I64 EqualityHistory Bool))
    (define (equality-seen? left right history)
      (when (= (* (ref-get (history-size history)) 2) (vector-length (ref-get (history-left history))))
        (grow-equality-history! history))
      (let* ((keys (ref-get (history-left history))) (partners (ref-get (history-right history)))
             (slot (equality-slot left right keys partners)))
        (if (= (vector-ref keys slot) left) #t
            (begin (vector-set! keys slot left) (vector-set! partners slot right)
                   (ref-set! (history-size history) (+ (ref-get (history-size history)) 1)) #f))))

    ;; ---- Stack-safe equality of finite graphs ----

    ;; Pending continuations live in traced Scheme data. Every recursive call
    ;; below is a tail call, including descent through car and vector elements.
    ;; Scalar comparison retains the existing exactness, NaN and zero rules.
    ;; No input is mutated, no user procedure is called, and every call starts
    ;; with fresh history, so later pair/vector mutation is visible immediately.
    (define-data EqualityWork
      (equality-done)
      (equality-values (left Datum) (right Datum) (pending EqualityWork))
      (equality-elements (left (Vector Datum)) (right (Vector Datum))
                         (index I64) (pending EqualityWork)))
    (: datum=? (-> Datum Datum Bool))
    (define (datum=? left right)
      (or (datum-eq? left right)
          (equality-compare left right (equality-done) (make-equality-history))))
    (: equality-continue (-> EqualityWork EqualityHistory Bool))
    (define (equality-continue work history)
      (match work
        ((equality-done) #t)
        ((equality-values left right pending) (equality-compare left right pending history))
        ((equality-elements left right index pending) (equality-vector left right index pending history))))
    (: equality-pair (-> Datum Datum EqualityWork EqualityHistory Bool))
    (define (equality-pair left right pending history)
      (if (equality-seen? (pair-datum-identity left) (pair-datum-identity right) history)
          (equality-continue pending history)
          (equality-compare (datum-car left) (datum-car right)
                            (equality-values (datum-cdr left) (datum-cdr right) pending) history)))
    (: equality-vector (-> (Vector Datum) (Vector Datum) I64 EqualityWork EqualityHistory Bool))
    (define (equality-vector left right index pending history)
      (if (= index (vector-length left)) (equality-continue pending history)
          (equality-compare (vector-ref left index) (vector-ref right index)
                            (equality-elements left right (+ index 1) pending) history)))
    (: equality-vector-datum (-> Datum Datum EqualityWork EqualityHistory Bool))
    (define (equality-vector-datum left right pending history)
      (let ((values (datum-vector-values left)) (others (datum-vector-values right)))
        (and (= (vector-length values) (vector-length others))
             (if (equality-seen? (vector-datum-identity left) (vector-datum-identity right) history)
                 (equality-continue pending history)
                 (equality-vector values others 0 pending history)))))
    (: equality-compare (-> Datum Datum EqualityWork EqualityHistory Bool))
    (define (equality-compare left right pending history)
      (if (datum-eq? left right) (equality-continue pending history)
          (and (= (datum-kind left) (datum-kind right))
               (match left
                 ;; Atomic equivalence already failed. Only distinct mutable
                 ;; storage can still contain structurally equal values.
                 ((datum-null) #f) ((datum-boolean value) #f) ((datum-character value) #f)
                 ((datum-symbol value) #f) ((datum-number value) #f)
                 ((datum-string text)
                  (and (string=? text (datum-string-value right)) (equality-continue pending history)))
                 ((datum-bytevector bytes)
                  (and (datum-bytes=? bytes (datum-bytevector-values right)) (equality-continue pending history)))
                 ((pair-datum first rest identity) (equality-pair left right pending history))
                 ((vector-datum values identity) (equality-vector-datum left right pending history))))))
    (: datum-bytes=? (-> Bytevector Bytevector Bool))
    (define (datum-bytes=? left right)
      (let ((count (bytevector-length left)))
        (and (= count (bytevector-length right))
             (let loop ((index 0))
               (or (= index count)
                   (and (= (bytevector-u8-ref left index) (bytevector-u8-ref right index))
                        (loop (+ index 1)))))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-datum)
    (begin
      (define (test-pair-identity)
        (let* ((first (ref (datum-null))) (rest (ref (datum-null)))
               (pair (datum-pair first rest)) (alias (datum-pair first rest)))
          (datum-set-cdr! pair pair)
          (and (datum-eq? pair alias) (datum-eq? (datum-cdr alias) pair)
               (not (datum-eq? pair (datum-pair first (ref pair))))
               (not (datum-eq? pair (datum-pair (ref (datum-null)) rest)))
               (not (datum-eq? pair (datum-cons (datum-null) pair))))))
      (define (test-list-sharing)
        (let* ((a (datum-symbol (string->symbol "a"))) (b (datum-symbol (string->symbol "b")))
               (entry (datum-cons a b)) (tail (datum-list b))
               (head (datum-list a)) (joined (datum-append head tail)))
          (and (= (datum-length joined) 2) (datum-eq? (datum-cdr joined) tail)
               (not (datum-eq? head joined)) (datum-eq? (datum-car joined) a)
               (datum-eq? (datum-assq a (datum-list entry)) entry)
               (not (datum-truth? (datum-assq b (datum-list entry))))
               (datum=? (datum-map (lambda (value) value) joined) joined))))
      (define (test-storage-identity)
        (let* ((text (string-copy "a")) (bytes (bytevector 1))
               (elements (vector (datum-null))))
          (and (datum-eq? (datum-string text) (datum-string text))
               (not (datum-eq? (datum-string text) (datum-string (string-copy text))))
               (datum-eq? (datum-vector elements) (datum-vector elements))
               (not (datum-eq? (datum-vector elements) (datum-vector (vector-copy elements))))
               (datum-eq? (datum-bytevector bytes) (datum-bytevector bytes))
               (not (datum-eq? (datum-bytevector bytes) (datum-bytevector (bytevector-copy bytes)))))))
      (define (test-decimal text)
        (let ((number (parsed-number-value (string->number text))))
          (match number
            ((exact-number value) (string=? text (i64->string value)))
            ((inexact-number value) #f) ((complex-number real imaginary) #f))))
      (: test-atom-number (-> String Bool))
      (define (test-atom-number text)
        (match (string->atom text)
          ((read-value value)
           (datum=? value (datum-number (parsed-number-value (string->number text)))))
          ((read-error message) #f) ((read-end) #f)))
      (: test-atom-error (-> String Bool))
      (define (test-atom-error text)
        (match (string->number text)
          ((number-error message)
           (match (string->atom text)
             ((read-error actual) (string=? message actual))
             ((read-value value) #f) ((read-end) #f)))
          ((parsed-number number) #f) ((not-a-number) #f)))
      (: test-invalid-atom (-> String Bool))
      (define (test-invalid-atom text)
        (match (string->atom text)
          ((read-error message)
           (string=? message "invalid numeric token or identifier; rational numbers are not supported"))
          ((read-value value) #f) ((read-end) #f)))
      (: test-atoms (-> Bool))
      (define (test-atoms)
        (let ((first (read-value-datum (string->atom "same")))
              (second (read-value-datum (string->atom (string-copy "same")))))
          (and (datum-eq? first second)
               (test-atom-number "42") (test-atom-number "1.0") (test-atom-number "1+2i")
               (test-atom-error "1/2") (test-atom-error "#e1.5")
               (test-atom-error "9223372036854775808")
               (test-invalid-atom "123abc") (test-invalid-atom ""))))
      (define (test-equality-leaves)
        (and (datum=? (datum-string (string-copy "ab")) (datum-string (string-copy "ab")))
             (not (datum=? (datum-string "ab") (datum-string "ac")))
             (datum=? (datum-bytevector (bytevector 1 2)) (datum-bytevector (bytevector 1 2)))
             (not (datum=? (datum-bytevector (bytevector 1 2)) (datum-bytevector (bytevector 1 3))))
             (not (datum=? (datum-bytevector (bytevector 1 2)) (datum-bytevector (bytevector 1))))
             (not (datum=? (datum-null) (datum-boolean #f)))))
      (define (test-equality-cycles)
        (let* ((a (datum-character #\a)) (b (datum-character #\b))
               (one (datum-cons a (datum-null))) (two (datum-cons a one))
               (self (datum-cons a (datum-null))))
          (datum-set-cdr! one two) (datum-set-cdr! self self)
          (and (datum=? one self) (datum=? self two)
               (begin (datum-set-car! two b) (not (datum=? self one)))
               (begin (datum-set-car! two a) (datum=? self one))
               (datum-eq? (datum-cdr one) two) (datum-eq? (datum-cdr self) self))))
      (define (test-equality-pair-views)
        (let* ((first (ref (datum-character #\a))) (rest (ref (datum-null)))
               (original (datum-pair first rest)) (alias (datum-pair first rest))
               (other (datum-cons (datum-character #\a) (datum-null)))
               (one-field (datum-pair first (ref (datum-character #\b))))
               (other-field (datum-pair (ref (datum-character #\b)) rest)))
          (datum-set-cdr! original alias) (datum-set-cdr! other other)
          (and (datum=? original alias) (datum-eq? original alias)
               (datum=? original other) (datum=? alias other)
               (not (datum=? original one-field)) (not (datum=? original other-field))
               (datum-eq? (datum-cdr alias) alias) (char=? (datum-character-value (ref-get first)) #\a))))
      (define (test-equality-vector-cycles)
        (let* ((left (vector (datum-null))) (right (vector (datum-null)))
               (x (datum-vector left)) (alias (datum-vector left)) (y (datum-vector right))
               (a (datum-cons (datum-character #\a) x)) (b (datum-cons (datum-character #\a) y)))
          (vector-set! left 0 a) (vector-set! right 0 b)
          (and (datum=? alias y) (datum-eq? alias x)
               (not (datum=? x (datum-vector (empty-vector))))
               (begin (datum-set-car! b (datum-character #\b)) (not (datum=? x y)))
               (datum-eq? (vector-ref left 0) a) (datum-eq? (datum-cdr a) x))))
      (define (test-equality-pending-cdr)
        (let ((left (datum-cons (datum-null) (datum-character #\a)))
              (right (datum-cons (datum-null) (datum-character #\b))))
          (datum-set-car! left left) (datum-set-car! right right)
          (and (not (datum=? left right))
               (begin (datum-set-cdr! right (datum-character #\a)) (datum=? left right)))))
      (define (test-equality-pending-vector)
        (let* ((left (vector (datum-null) (datum-character #\a)))
               (right (vector (datum-null) (datum-character #\b)))
               (x (datum-cons (datum-vector left) (datum-null)))
               (y (datum-cons (datum-vector right) (datum-null))))
          (vector-set! left 0 x) (vector-set! right 0 y)
          (and (not (datum=? x y))
               (begin (vector-set! right 1 (datum-character #\a)) (datum=? x y)))))
      (define (test-ring count)
        (let ((root (datum-cons (datum-character #\a) (datum-null))))
          (let loop ((count (- count 1)) (last root))
            (if (= count 0) (begin (datum-set-cdr! last root) root)
                (let ((next (datum-cons (datum-character #\a) (datum-null))))
                  (datum-set-cdr! last next) (loop (- count 1) next))))))
      (define (test-equality-coprime-cycles)
        (let ((left (test-ring 17)) (right (test-ring 19)))
          (and (datum=? left right)
               (begin (datum-set-car! (datum-cdr right) (datum-character #\b))
                      (not (datum=? left right))))))
      (define (test-deep-datum count leaf)
        (let loop ((count count) (value leaf))
          (if (= count 0) value
              (loop (- count 1) (datum-cons value (datum-null))))))
      (define (test-equality-depth)
        (let ((left (test-deep-datum 5000 (datum-character #\a)))
              (right (test-deep-datum 5000 (datum-character #\a)))
              (different (test-deep-datum 5000 (datum-character #\b))))
          (and (datum=? left right) (not (datum=? left different))
               (datum=? (datum-vector (empty-vector)) (datum-vector (empty-vector))))))
      ;; Reference words were computed with independent unsigned-64 arithmetic.
      ;; Include changes above 32 bits, both result signs, and reversed keys.
      (define (test-equality-hash-words)
        (and (= (equality-pair-hash 1 1) 6652587683579779273)
             (= (equality-pair-hash 1 2) -972091869234291113)
             (= (equality-pair-hash 2 1) 583880340377267059)
             (= (equality-pair-hash 9223372036854775807 9223372036854775807) 4218948218474539009)
             (= (equality-pair-hash 1 9223372036854775807) 6459536036652829431)
             (= (equality-pair-hash 9223372036854775807 1) -421409582817843346)
             (= (equality-pair-hash 2097153 7) 1992281314829590827)
             (= (equality-pair-hash 2147483649 7) -1548759241620248504)
             (= (equality-pair-hash 4294967297 7) 2205320672614223687)
             (= (equality-pair-hash 4398046511105 7) -2359351969197311418)
             (= (equality-pair-hash 4611686018427387905 7) -5466481419058493644)
             (= (equality-pair-hash 4611690416475996161 7) -5320575393637501446)
             (= (equality-pair-hash 7 4611690416475996161) -1025925624717699660)))
      (define (test-equality-history-high-bits)
        (let ((ids (vector 1 2097153 2147483649 4294967297 4398046511105
                           4611686018427387905 4611690416475996161 9223372036854775807))
              (history (make-equality-history)))
          (let loop ((index 0))
            (if (= index (vector-length ids)) (= (ref-get (history-size history)) 16)
                (let ((id (vector-ref ids index)))
                  (and (not (equality-seen? id 7 history))
                       (not (equality-seen? 7 id history))
                       (equality-seen? id 7 history) (equality-seen? 7 id history)
                       (loop (+ index 1))))))))
      (define (test-insert-colliding-keys keys history)
        (let loop ((index 0))
          (if (= index (vector-length keys)) #t
              (and (or (not (= index 32))
                       (= (vector-length (ref-get (history-left history))) 32))
                   (not (equality-seen? (vector-ref keys index) (vector-ref keys (+ index 1)) history))
                   (loop (+ index 2))))))
      (define (test-find-colliding-keys keys history)
        (let loop ((index 0))
          (if (= index (vector-length keys)) #t
              (and (equality-seen? (vector-ref keys index) (vector-ref keys (+ index 1)) history)
                   (loop (+ index 2))))))
      (define (test-equality-history-collisions)
        ;; All keys start at bucket 31 modulo 32. Growth splits their homes
        ;; between 31 and 63, exercising wraparound and rehashing together.
        (let ((keys (vector 23 4611686018427387973
                            46 4611686018427388042
                            65 4611686018427388099
                            134 4611686018427388306
                            189 4611686018427388471
                            213 4611686018427388543
                            247 4611686018427388645
                            271 4611686018427388717
                            284 4611686018427388756
                            387 4611686018427389065
                            474 4611686018427389326
                            486 4611686018427389362
                            506 4611686018427389422
                            513 4611686018427389443
                            529 4611686018427389491
                            539 4611686018427389521
                            541 4611686018427389527
                            567 4611686018427389605))
              (history (make-equality-history)))
          (and (test-insert-colliding-keys keys history)
               (= (vector-length (ref-get (history-left history))) 64)
               (= (ref-get (history-size history)) 18)
               (test-find-colliding-keys keys history)
               (= (ref-get (history-size history)) 18)
               (not (equality-seen? 640 4611686018427389824 history))
               (not (equality-seen? (vector-ref keys 0) (vector-ref keys 1) (make-equality-history))))))
      (define (test-datum)
        (if (and (test-pair-identity) (test-list-sharing) (test-storage-identity)
                 (test-atoms)
                 (test-equality-leaves) (test-equality-cycles) (test-equality-pair-views)
                 (test-equality-vector-cycles) (test-equality-depth)
                 (test-equality-pending-cdr) (test-equality-pending-vector)
                 (test-equality-coprime-cycles)
                 (test-equality-hash-words) (test-equality-history-high-bits)
                 (test-equality-history-collisions)
                 (datum-null? (datum-null)) (datum-pair? (datum-list (datum-null)))
                 (datum-truth? (datum-null)) (not (datum-truth? (datum-boolean #f)))
                 (datum-eq? (datum-symbol (string->symbol "same"))
                            (datum-symbol (string->symbol (string-copy "same"))))
                 (test-decimal "0") (test-decimal "42") (test-decimal "-42")
                 (test-decimal "-9223372036854775808") (test-decimal "9223372036854775807"))
            42 0))))))
