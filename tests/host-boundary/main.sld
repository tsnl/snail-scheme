(import
 (lofi base)
 (boundary value))

(extern note-text "snail.test" "text" (-> String I32))
(extern note-bytes "snail.test" "bytes" (-> I32 Bytes I32))
(extern hold-bytes "snail.test" "hold" (-> Bytes I32))
(extern receive-managed "snail.test" "managed" (-> (Result Payload String)))

(: checkpoint (Ref Any))
(define checkpoint (ref (type-convert (ann 42 I64) Any)))

(: state (-> Any ! mut))
(define (state)
  (ref-get checkpoint))

(: echo (-> (Option Any) (Option Any)))
(define (echo handover)
  (match handover
    ((Some state) (Some state))
    ((None) (None))))

(: value (-> (Option Any) I64))
(define (value handover)
  (match handover
    ((Some state) (type-convert state I64))
    ((None) -1)))

(: binary (-> I32))
(define (binary)
  (note-bytes (note-text "λ") #u8(0 255 128 1)))

(: empty (-> I32))
(define (empty)
  (note-bytes 0 #u8()))

(: held (-> I32))
(define (held)
  (hold-bytes #u8(0 255 128 1)))

(: discard (-> (Option Any) Unit))
(define (discard handover)
  (unit))

(: fail (-> Unit))
(define (fail)
  (panic "a deliberate boundary trap"))

(expose state "state")
(expose echo "echo")
(expose value "value")
(expose binary "binary")
(expose empty "empty")
(expose held "held")
(expose discard "discard")
(expose fail "fail")

(: managed (-> (Result Payload String)))
(define (managed)
  (receive-managed))

(: result-number (-> (Result Payload String) I32))
(define (result-number value)
  (match value
    ((Ok payload) (Payload-number payload))
    ((Err _) -1)))

(: result-bytes (-> (Result Payload String) Bytes))
(define (result-bytes value)
  (match value
    ((Ok payload) (Payload-bytes payload))
    ((Err _) #u8())))

(: inspect-bytes (-> Bytes I32))
(define (inspect-bytes bytes)
  (u8->i32 (vector-ref bytes 2)))

(expose managed "managed")
(expose result-number "result-number")
(expose result-bytes "result-bytes")
(expose inspect-bytes "inspect-bytes")
