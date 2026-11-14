;; A one-shot channel: a promise is fulfilled once, and its future is ready
;; from then on. Every transition publishes its new state before invoking a
;; callback. A promise that is never fulfilled leaves its future pending.
(define-library (snail shell future)
  (export
   Promise Future Poll Pending Ready
   completion completed make-promise fulfill poll on-ready)
  (import
   (snail core base)
   (only (snail core forms) host)
   (only (snail core primitive) inherit-handlers))
  (begin

    ;; ---- The channel ----

    (enum (Poll T)
      (Pending)
      (Ready ((value T))))

    ;; Any number of tasks may wait on one future, so a pending one keeps
    ;; every waker, newest first. Each runs under the handlers in scope
    ;; where it was registered.
    (type Waker (Fn → Unit ! host))
    (enum (State T)
      (Unresolved ((wakers (List Waker))))
      (Resolved ((value T))))

    (record (Channel T)
      ((state (State T))))

    (enum (Promise T)
      (Sender ((channel (Channel T)))))

    (enum (Future T)
      (Receiver ((channel (Channel T)))))

    (effect completion
      ((completed (Fn → Unit)))
      (default ((completed (lambda () (unit))))))

    (define (make-promise) (→ (Pair (Promise T) (Future T))) (∀ (T))
      (let ((channel (new Channel (state (Unresolved (Nil))))))
        (new Pair (first (Sender channel)) (second (Receiver channel)))))

    ;; ---- Sending ----

    (define (fulfill (promise (Promise T)) (value T))
      (→ Unit) (! mut host completion) (∀ (T))
      (match promise
        ((Sender channel)
         (match (● channel state)
           ((Unresolved wakers)
            (set! (● channel state) (Resolved value))
            (for-each (lambda (wake) (wake)) (reverse wakers))
            (completed))
           ((Resolved _) (panic "a promise was fulfilled twice"))))))

    ;; ---- Receiving ----

    (define (poll (future (Future T))) (→ (Poll T)) (∀ (T))
      (match future
        ((Receiver channel)
         (match (● channel state)
           ((Unresolved _) (Pending))
           ((Resolved value) (Ready value))))))

    ;; No suspension is allowed: a ready future calls `wake` at once, and a
    ;; pending one when it is fulfilled, after the wakers registered before.
    (define (on-ready (future (Future T)) (wake (Fn → Unit ! d)))
      (→ Unit) (! mut host d) (∀ (T d))
      (let ((waker (inherit-handlers wake)))
        (match future
          ((Receiver channel)
           (match (● channel state)
             ((Unresolved wakers) (set! (● channel state) (Unresolved (Cons waker wakers))))
             ((Resolved _) (waker)))))))))
