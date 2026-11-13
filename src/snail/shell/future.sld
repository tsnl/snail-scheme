;; A one-shot channel. Its linear endpoints share an Rc-owned state; no
;; borrowed or unowned slot can hide a buffered linear value. Every transition
;; publishes its new state before invoking or dropping a callback.
(define-library (snail shell future)
  (export
   Promise Future Completion Completed Abandoned Poll Pending Ready
   completion completed make-promise fulfill poll on-ready)
  (import
   (snail core base)
   (only (snail core forms) host)
   (only (snail core primitive) inherit-handlers))
  (begin

    ;; ---- The channel ----

    (enum (Completion T)
      (Completed ((value T)))
      (Abandoned))

    (enum (Poll T)
      (Pending ((future (Future T))))
      (Ready ((result (Completion T)))))

    ;; One registration is invoked or dropped once. Its inherited handlers
    ;; outlive registration and bound both invocation and capture cleanup.
    (type Waker (FnOnce → Unit ! host))
    (enum (State T)
      (Unresolved ((waker (Option Waker))))
      (Resolved ((result (Completion T))))
      (Unobserved))

    (struct (Channel T)
      ((state (State T))))

    (enum (Promise T)
      (Sender ((channel (Rc (Channel T))))))

    (enum (Future T)
      (Receiver ((channel (Rc (Channel T))))))

    (effect completion
      ((completed (Fn → Unit)))
      (default ((completed (lambda () (unit))))))

    ;; Each endpoint owns one shared credit. Either may release the last
    ;; one, so both carry T's disposal bound, including operations that
    ;; normally transfer T without dropping it. No state provenance is hidden
    ;; in a convention about which endpoint happens to be released first.
    (define (make-promise) (→ (Pair (Promise T) (Future T))) (∀ T d) (⊨ (Drop d T))
      (let ((channel (rc (Channel (Unresolved (None))))))
        (Pair (Sender channel) (Receiver channel))))

    ;; ---- Sending ----

    (define (fulfill (promise (Promise T)) (value T))
      (→ (Result Unit T)) (! mut host completion d) (∀ T d) (⊨ (Drop d T))
      (match promise
        ((Sender channel)
         (match (replace! (● channel state) (Unobserved))
           ((Unresolved waker)
            (drop (replace! (● channel state) (Resolved (Completed value))))
            (sent waker))
           ((Unobserved) (Err value))
           ((Resolved result)
            (drop result)
            (drop value)
            (panic "a promise was fulfilled twice"))))))

    ;; This tail call releases the sender's local channel owner before a
    ;; waker can reenter. The state already owns the published result.
    (define (sent (waker (Option Waker))) (→ (Result Unit T)) (! host completion) (∀ T)
      (notify waker)
      (Ok (unit)))

    (define (notify (waker (Option Waker))) (→ Unit) (! host completion)
      (match waker
        ((Some wake) (wake))
        ((None) (unit)))
      (completed))

    (instance (Drop (! mut host completion d) (Promise T))
      (⊨ (Drop d T))
      (define drop (lambda (promise)
                     (match promise
                       ((Sender channel)
                        (match (replace! (● channel state) (Unobserved))
                          ((Unresolved waker)
                           (drop (replace! (● channel state) (Resolved (Abandoned))))
                           (notify waker))
                          ((Unobserved) (unit))
                          ((Resolved result)
                           (drop result)
                           (panic "a consumed promise was dropped"))))))))

    ;; ---- Receiving ----

    (define (poll (future (Future T)))
      (→ (Poll T)) (! mut host d) (∀ T d) (⊨ (Drop d T))
      (match future
        ((Receiver channel)
         (match (replace! (● channel state) (Unobserved))
           ((Unresolved waker)
            (drop (replace! (● channel state) (Unresolved waker)))
            (Pending (Receiver channel)))
           ((Resolved result) (Ready result))
           ((Unobserved) (panic "a consumed future was polled"))))))

    ;; Registration owns its callback and handlers. No suspension is allowed:
    ;; a ready result calls it immediately, and a pending result calls it
    ;; after publication. Replacing a registration drops its previous callback
    ;; only after the new callback is installed.
    (define (on-ready (future (Future T)) (wake (FnOnce → Unit ! d)))
      (→ (Future T)) (! mut host d) (∀ T d) (⊨ (Drop d T))
      (register future (inherit-handlers wake)))

    (define (register (future (Future T)) (wake Waker))
      (→ (Future T)) (! mut host d) (∀ T d) (⊨ (Drop d T))
      (match future
        ((Receiver channel)
         (match (replace! (● channel state) (Unobserved))
           ((Unresolved previous)
            (drop (replace! (● channel state) (Unresolved (Some wake))))
            (drop previous))
           ((Resolved result)
            (drop (replace! (● channel state) (Resolved result)))
            (wake))
           ((Unobserved) (drop wake) (panic "a consumed future was observed")))
         (Receiver channel))))

    ;; Detach buffered content before disposing it. The Rc payload then holds
    ;; Unobserved, so releasing either endpoint cannot finalize that content
    ;; a second time, even if its cleanup calls another channel operation.
    (instance (Drop (! mut host d) (Future T))
      (⊨ (Drop d T))
      (define drop (lambda (future)
                     (match future
                       ((Receiver channel) (drop (replace! (● channel state) (Unobserved))))))))))
