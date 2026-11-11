;; A one-shot result channel, independent of the work that produces it.
;; The two linear endpoints share one private slot. Only the promise may
;; fill it; only the future may take its result. Every transition restores
;; the slot before calling a waker or user handler, so reentry observes a
;; complete state. There is no suspension and no scheduler in this library.
(define-library (snail shell future)
  (export
   Promise Future
   Completion Completed Abandoned
   Poll Pending Ready
   completion completed
   make-promise fulfill poll on-ready)
  (import
   (snail core base)
   (snail shell slot))
  (begin

    ;; ---- Results and endpoints ----

    ;; Application errors belong in T, commonly a Result. Abandoned means
    ;; the producer was dropped without supplying a result.
    (enum (Completion T)
      (Completed ((value T)))
      (Abandoned))

    (enum (Poll T)
      (Pending ((future (Future T))))
      (Ready ((result (Completion T)))))

    (enum (State T)
      (Unresolved ((waker (Option (dyn (Fn -> Unit ! mut))))))
      (Resolved ((result (Completion T))))
      (Unobserved))

    ;; Constructors and slots stay private: exporting an endpoint's type
    ;; never lets a client manufacture a second endpoint for its slot.
    (enum (Promise T)
      (Sender ((slot (UnsafeSlot (State T))))))

    (enum (Future T)
      (Receiver ((slot (UnsafeSlot (State T))))))

    ;; A reactor may request another update after any completion. This is
    ;; a notification, never an application-specific completion message.
    (effect completion
      ((completed (dyn (Fn -> Unit))))
      (default ((completed (lambda () (unit))))))

    (: make-promise (All (T) (impl (Fn -> (Pair (Promise T) (Future T))))))
    (define (make-promise)
      (let ((slot (unsafe-slot (Unresolved (None)))))
        (Pair (Sender slot) (Receiver slot))))

    ;; ---- Sending ----

    ;; A canceled receiver returns the unsent value to its producer.
    ;; Synchronization and one-shot ownership do not make publication pure:
    ;; it changes what another endpoint's next poll observes.
    (: fulfill (All (T) (impl (Fn (Promise T) T -> (Result Unit T) ! mut completion))))
    (define (fulfill promise value)
      (match promise
        ((Sender slot)
         (match (take! slot)
           ((Unresolved waker)
            (put! slot (Resolved (Completed value)))
            (notify waker)
            (Ok (unit)))
           ((Unobserved)
            (put! slot (Unobserved))
            (Err value))
           ((Resolved result) (panic "a promise was fulfilled twice"))))))

    (: notify (impl (Fn (Option (dyn (Fn -> Unit ! mut))) -> Unit ! mut completion)))
    (define (notify waker)
      (match waker
        ((Some wake) (wake))
        ((None) (unit)))
      (completed))

    ;; Dropping a promise closes the sender, including when a suspended
    ;; task is canceled. An already canceled receiver needs no notification.
    (instance (Drop (! mut completion) (Promise T))
      (define (drop promise)
        (match promise
          ((Sender slot)
           (match (take! slot)
             ((Unresolved waker)
              (put! slot (Resolved (Abandoned)))
              (notify waker))
             ((Unobserved) (put! slot (Unobserved)))
             ((Resolved result) (panic "a consumed promise was dropped")))))))

    ;; ---- Receiving ----

    ;; Pending returns ownership of the endpoint. Ready transfers the
    ;; result exactly once and consumes the endpoint. Neither runs work.
    (: poll (All (T) (impl (Fn (Future T) -> (Poll T) ! mut))))
    (define (poll future)
      (match future
        ((Receiver slot)
         (match (take! slot)
           ((Unresolved waker)
            (put! slot (Unresolved waker))
            (Pending (Receiver slot)))
           ((Resolved result)
            (put! slot (Unobserved))
            (Ready result))
           ((Unobserved) (panic "a consumed future was polled"))))))

    ;; Replace the one waiting observer. A scheduler uses this to register
    ;; its ticket before suspending; registration and suspension must have
    ;; no intervening yield. A ready result calls the observer immediately.
    (: on-ready (All (T) (impl (Fn (Future T) (dyn (Fn -> Unit ! mut)) -> (Future T) ! mut))))
    (define (on-ready future wake)
      (match future
        ((Receiver slot)
         (match (take! slot)
           ((Unresolved _)
            (put! slot (Unresolved (Some wake))))
           ((Resolved result)
            (put! slot (Resolved result))
            (wake))
           ((Unobserved) (panic "a consumed future was observed")))
         (Receiver slot))))

    ;; The receiver owns cleanup of a buffered result. Publish cancellation
    ;; before dropping it: its drop may call arbitrary ordinary handlers.
    (instance (Drop (! mut e) (Future T))
      (requires (Drop e T))
      (define (drop future)
        (match future
          ((Receiver slot)
           (let ((state (take! slot)))
             (put! slot (Unobserved))
             (match state
               ((Resolved result) (drop result))
               ((Unresolved _) (unit))
               ((Unobserved) (panic "a consumed future was dropped"))))))))))
