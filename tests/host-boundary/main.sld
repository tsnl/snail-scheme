(import
 (snail core base)
 (boundary value))

;; A mismatch here is a broken test-host invariant.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (downcast target value)
       ((Some checked) checked)
       ((None) (panic "fixture payload has the wrong type"))))))

(extern note-text "snail.test" "text" (Fn String → I32))
(extern note-bytes "snail.test" "bytes" (Fn I32 Bytes → I32))
(extern receive-managed "snail.test" "managed" (Fn → (Result Payload String)))

(struct Checkpoint
  ((value Any)))

(define (create) (→ Checkpoint) (Checkpoint (Any 42)))
(expose create "create")

(define (state (checkpoint Checkpoint)) (→ Any)
  (● checkpoint value))

(define (echo (handover (Option Any))) (→ (Option Any))
  (match handover
    ((Some state) (Some state))
    ((None) (None))))

(define (value (handover (Option Any))) (→ I64)
  (match handover
    ((Some state) (fixture-convert state I64))
    ((None) -1)))

(define (binary) (→ I32)
  (note-bytes (note-text "λ") #u8(0 255 128 1)))

(define (empty) (→ I32)
  (note-bytes 0 #u8()))

(define (updated) (→ I32) (! mut)
  (let ((bytes #u8(1 0)))
    (vector-set! bytes 1 (ann 2 U8))
    (note-bytes 9 bytes)))

(define (discard (handover (Option Any))) (→ Unit)
  (unit))

(define (fail) (→ Unit)
  (panic "a deliberate boundary trap"))

(expose state "state")
(expose echo "echo")
(expose value "value")
(expose binary "binary")
(expose empty "empty")
(expose updated "updated")
(expose discard "discard")
(expose fail "fail")

(define (managed) (→ (Result Payload String))
  (receive-managed))

(define (result-number (value (Result Payload String))) (→ I32)
  (match value
    ((Ok payload) (● payload number))
    ((Err _) -1)))

(define (result-bytes (value (Result Payload String))) (→ Bytes)
  (match value
    ((Ok payload) (● payload bytes))
    ((Err _) #u8())))

(define (inspect-bytes (bytes Bytes)) (→ I32)
  (u8->i32 (vector-ref bytes 2)))

(expose managed "managed")
(expose result-number "result-number")
(expose result-bytes "result-bytes")
(expose inspect-bytes "inspect-bytes")

;; A concrete inferred entry closes its effect row without a handwritten
;; export signature. Application scaffolding relies on the same ordinary rule.
(define inferred-entry
  (lambda (checkpoint value)
    (set! (● checkpoint value) (Any (ann value I64)))
    (state checkpoint)))
(expose inferred-entry "inferred")
