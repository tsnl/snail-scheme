;; Typed request/response actors. A host chooses direct immutable references
;; or the same derived binary codecs used by (lofi wire).
(define-library (lofi actor)
  (export
   Actor
   Mailbox
   actors
   spawn
   request
   receive
   reply
   define-actor)
  (import
   (lofi base)
   (lofi wire)
   (only (lofi primitive) share-value shared-value))
  (begin

    ;; ---- Protocols ----

    ;; The phantom arguments participate in the structural TypeId. Spawning
    ;; checks this witness, including the engine's representation check.
    (struct (Protocol Q R)
      ())

    (enum (Actor Q R)
      (Endpoint
       ((id I32))))

    (enum (Mailbox Q R)
      (Inbox))

    (define-syntax define-actor
      (syntax-rules ()
        ((_ Q R body) (define-actor Q R () body))
        ((_ Q R (platform ...) body)
         (begin
           (: actor-accept (-> Any Bool))
           (define (actor-accept witness)
             (share-value (ann (Protocol) (Protocol Q R)))
             (type-test witness (Protocol Q R)))
           (: actor-main (-> Unit ! actors platform ...))
           (define (actor-main) (body (ann (Inbox) (Mailbox Q R))))
           (expose actor-accept "actor_accept")
           (expose actor-main "actor_main")))))

    ;; ---- Host operations ----

    ;; These raw operations are the trusted foreign boundary. Application
    ;; code uses the typed functions below; arbitrary foreign imports can
    ;; bypass their guarantees, just as unsafe-cast can bypass a function type.
    (effect actors
      ((name-character (-> Char Unit))
       (spawn-actor (-> Any I32))
       (local-actor? (-> I32 Bool))
       (request-value (-> I32 Any Any))
       (request-bytes (-> I32 Bytes I32))
       (response-byte (-> I32 U8))
       (receive-message (-> I32))
       (message-value (-> Any))
       (message-byte (-> I32 U8))
       (local-reply? (-> Bool))
       (reply-value (-> Any Unit))
       (reply-bytes (-> Bytes Unit)))
      (host "snail.actor"
            ((name-character "character")
             (spawn-actor "spawn")
             (local-actor? "local")
             (request-value "request")
             (request-bytes "request-bytes")
             (response-byte "response-byte")
             (receive-message "receive")
             (message-value "value")
             (message-byte "request-byte")
             (local-reply? "reply-local")
             (reply-value "reply")
             (reply-bytes "reply-bytes"))))

    ;; ---- Typed operations ----

    (: spawn (All (Q R) (-> String (Actor Q R) ! actors)))
    (define (spawn name)
      (let loop ((index 0))
        (when (< index (string-length name))
          (name-character (string-ref name index))
          (loop (+ index 1))))
      (spawn-protocol (Protocol)))

    (: spawn-protocol (All (Q R) (-> (Protocol Q R) (Actor Q R) ! actors)))
    (define (spawn-protocol protocol)
      (Endpoint (spawn-actor (share-value protocol))))

    (: request (All (Q R) (requires (Serialize Q) (Deserialize R))
                    (-> (Actor Q R) Q R ! actors)))
    (define (request actor value)
      (let ((shared (share-value value)) (id (Endpoint-id actor)))
        (if (local-actor? id)
            (shared-value (request-value id shared))
            (let ((size (request-bytes id (serialize value))))
              (deserialize (vector-generate (i32->i64 size) (lambda (index) (response-byte (i64->i32 index)))))))))

    ;; A mailbox is bound to the current actor by its imports. It handles one
    ;; request at a time; receive before reply and duplicate reply both fail.
    (: receive (All (Q R) (requires (Deserialize Q))
                    (-> (Mailbox Q R) Q ! actors)))
    (define (receive mailbox)
      (let ((size (receive-message)))
        (if (= size -1)
            (shared-value (message-value))
            (deserialize (vector-generate (i32->i64 size) (lambda (index) (message-byte (i64->i32 index))))))))

    (: reply (All (Q R) (requires (Serialize R))
                  (-> (Mailbox Q R) R Unit ! actors)))
    (define (reply mailbox value)
      (let ((shared (share-value value)))
        (if (local-reply?) (reply-value shared) (reply-bytes (serialize value)))))))
