;; Futures do not run themselves. This library connects their one-shot
;; channels to the cooperative scheduler, using only ordinary library
;; functions and the task effect's one-shot control operations.
(define-library (snail shell async)
  (export dispatch await-future after)
  (import
   (snail core base)
   (snail shell future)
   (snail shell task))
  (begin

    ;; ---- Dispatching ----

    ;; Dispatch owns the producer; the caller owns its receiver. Dropping
    ;; the receiver cancels reception, not the task or its external work.
    ;; If nobody receives, the task drops its unsent result under the
    ;; result's own Drop row. Expected failures are values in T.
    (: dispatch
       (All (T e) (requires (Drop e T))
            (-> (FnOnce T ! tasks e) (Future T) ! mut completion e)))
    (define (dispatch work)
      (match (make-promise)
        ((Pair promise future)
         (schedule (make-task (once (lambda () (produce promise work)))))
         future)))

    (: produce
       (All (T e) (requires (Drop e T))
            (-> (Promise T) (FnOnce T ! tasks e) Unit ! mut completion tasks e)))
    (define (produce promise work)
      (drop (fulfill promise (work))))

    ;; ---- Waiting ----

    ;; A pending future remains owned by the suspended continuation, so
    ;; cancellation drops it. No task or host callback can run between
    ;; polling, registering the ticket and parking on it in this runtime.
    (: await-future
       (All (T d) (requires (Drop d T))
            (-> (Future T) (Completion T) ! mut tasks d)))
    (define (await-future future)
      (match (poll future)
        ((Ready result) result)
        ((Pending future)
         (let* ((id (ticket))
                (future (on-ready future (lambda () (tasks-wake! id) (unit)))))
           (await id)
           (await-future future)))))

    ;; The scheduler owns the deadline. The host only sleeps until its
    ;; next deadline or I/O completion; there is no repeated polling.
    (: after (-> I64 (Future Unit) ! mut completion))
    (define (after milliseconds)
      (dispatch (once (lambda () (sleep milliseconds)))))))
