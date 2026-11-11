(import
 (snail core base)
 (boundary value))

;; A mismatch here is a broken test-host invariant. Guest conversions that
;; are expected to fail use dyn-cast handlers in the dedicated fixtures.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (try-convert value target)
       ((Ok checked) checked)
       ((Err _) (panic "fixture payload has the wrong type"))))))

(extern note-text "snail.test" "text" (impl (Fn String → I32)))
(extern note-bytes "snail.test" "bytes" (impl (Fn I32 Bytes → I32)))
(extern receive-managed "snail.test" "managed" (impl (Fn → (Result Payload String))))

(define checkpoint (→ (Ref Any)) (ref (type-convert (ann 42 I64) Any)))

(define (state) (→ Any) (! mut)
  (ref-get checkpoint))

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

(define (discard (handover (Option Any))) (→ Unit)
  (unit))

(define (fail) (→ Unit)
  (panic "a deliberate boundary trap"))

(expose state "state")
(expose echo "echo")
(expose value "value")
(expose binary "binary")
(expose empty "empty")
(expose discard "discard")
(expose fail "fail")

(define (managed) (→ (Result Payload String))
  (receive-managed))

(define (result-number (value (Result Payload String))) (→ I32)
  (match value
    ((Ok payload) (::number payload))
    ((Err _) -1)))

(define (result-bytes (value (Result Payload String))) (→ Bytes)
  (match value
    ((Ok payload) (::bytes payload))
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
  (lambda (value) (ref-set! checkpoint (type-convert (ann value I64) Any))
          (ref-get checkpoint)))
(expose inferred-entry "inferred")
