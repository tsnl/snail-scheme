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

    ;; The task fulfills the future's promise with the work's result.
    ;; Expected failures are values in T.

    (define (dispatch (work (Fn → T ! tasks e)))
      (→ (Future T))
      (! mut host completion tasks e)
      (∀ (T e))
      (match (make-promise)
        ((Pair promise future)
         (dispatch-task (lambda () (produce promise work)))
         future)))

    (define (produce (promise (Promise T)) (work (Fn → T ! tasks e)))
      (→ Unit)
      (! mut host completion tasks e)
      (∀ (T e))
      (fulfill promise (work)))

    ;; ---- Waiting ----

    ;; No task or host callback can run between polling, registering the
    ;; ticket and parking on it in this runtime.

    (define (await-future (future (Future T)))
      (→ T)
      (! mut host tasks)
      (∀ (T))
      (match (poll future)
        ((Ready value) value)
        ((Pending)
         (let ((id (ticket)) (scheduler (current-scheduler)))
           (on-ready future (lambda () (tasks-wake! scheduler id) (unit)))
           (await id)
           (await-future future)))))

    ;; The scheduler owns the deadline. The host only sleeps until its
    ;; next deadline or I/O completion; there is no repeated polling.

    (define (after (milliseconds I64)) (→ (Future Unit)) (! mut host completion tasks)
      (dispatch (lambda () (sleep milliseconds))))))
