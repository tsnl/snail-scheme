;; Futures do not run themselves. This library connects their one-shot
;; channels to the cooperative scheduler, using only ordinary library
;; functions and the task effect's one-shot control operations.
(define-library (snail shell async)
  (export dispatch await-future after)
  (import
   (snail core base)
   (only (snail core forms) host)
   (snail shell future)
   (snail shell task))
  (begin

    ;; ---- Dispatching ----

    ;; Dispatch owns the producer; the caller owns its receiver. Dropping
    ;; the receiver cancels reception, not the task or its external work.
    ;; If nobody receives, the task drops its unsent result under the
    ;; result's own Drop row. Expected failures are values in T.

    (define (dispatch (work (FnOnce → T ! tasks e)))
      (→ (Future T))
      (! mut host completion tasks e)
      (∀ T e)
      (⊨ (Drop e T))
      (match (make-promise)
        ((Pair promise future)
         (dispatch-task (once (lambda () (produce promise work))))
         future)))

    (define (produce (promise (Promise T)) (work (FnOnce → T ! tasks e)))
      (→ Unit)
      (! mut host completion tasks e)
      (∀ T e)
      (⊨ (Drop e T))
      (drop (fulfill promise (work))))

    ;; ---- Waiting ----

    ;; A pending future remains owned by the suspended continuation, so
    ;; cancellation drops it. No task or host callback can run between
    ;; polling, registering the ticket and parking on it in this runtime.

    (define (await-future (future (Future T)))
      (→ (Completion T))
      (! mut host tasks d)
      (∀ T d)
      (⊨ (Drop d T))
      (match (poll future)
        ((Ready result) result)
        ((Pending future)
         (let* ((id (ticket)) (scheduler (current-scheduler))
                (future (on-ready future (once (lambda () (wake-task! scheduler id) (unit))))))
           (await id)
           (await-future future)))))

    ;; The scheduler owns the deadline. The host only sleeps until its
    ;; next deadline or I/O completion; there is no repeated polling.

    (define (after (milliseconds I64)) (→ (Future Unit)) (! mut host completion tasks)
      (dispatch (once (lambda () (sleep milliseconds)))))))
