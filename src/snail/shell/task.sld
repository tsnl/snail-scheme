;; Runtime-owned control operations. Dispatch transfers one-shot local work;
;; its latent effects remain requirements of the dispatching computation.
;; A mailbox carries messages between tasks, in the order they are posted.
(define-library (snail shell task)
  (export
   tasks dispatch-local yield sleep
   Mailbox make-mailbox mailbox-post mailbox-receive)
  (import
   (snail core base)
   (only (snail core forms) tasks)
   (only (snail core primitive) dispatch-local park-task unpark-task current-task)
   (rename (only (snail core primitive) yield-task sleep-task)
           (yield-task yield)
           (sleep-task sleep)))
  (begin

    ;; ---- Queues ----

    ;; Items leave from the front and join at the back, which becomes the
    ;; front, reversed, when the front runs out. Both operations take the
    ;; queue apart with `match`, so items only move, and a queue may hold
    ;; linear values.
    (struct (Queue T)
      ((front (List T))
       (back (List T))))

    (: empty-queue (All (T) (-> (Queue T))))
    (define (empty-queue)
      (Queue (Nil) (Nil)))

    (: enqueue (All (T) (-> (Queue T) T (Queue T))))
    (define (enqueue queue item)
      (match queue
        ((Queue front back) (Queue front (Cons item back)))))

    (: dequeue (All (T) (-> (Queue T) (Option (Pair T (Queue T))))))
    (define (dequeue queue)
      (match queue
        ((Queue (Cons item rest) back) (Some (Pair item (Queue rest back))))
        ((Queue (Nil) (Nil)) (None))
        ((Queue (Nil) back) (dequeue (Queue (reverse back) (Nil))))))

    ;; ---- Mailboxes ----

    ;; Tasks share a mailbox, so what it holds cannot be threaded through
    ;; any one of them: its two cells are the boundary between them, and
    ;; the only mutable state here. `messages` holds what was posted and
    ;; not yet received, and `receivers` the ids of the tasks parked in
    ;; `mailbox-receive`, each in the order it arrived. A message may be
    ;; linear, so it moves in and out of its cell with `ref-replace!`, and
    ;; neither operation suspends while the cell holds the empty queue the
    ;; swap left.
    (struct (Mailbox T)
      ((messages (Ref (Queue T)))
       (receivers (Ref (Queue I64)))))

    (: make-mailbox (All (T) (-> (Mailbox T) ! mut)))
    (define (make-mailbox)
      (Mailbox (ref (empty-queue)) (ref (empty-queue))))

    ;; Posting never waits. The message joins the queue, and the receiver
    ;; parked longest is woken to take it.
    (: mailbox-post (All (T) (-> (Mailbox T) T Unit ! mut tasks)))
    (define (mailbox-post mailbox message)
      (let ((messages (Mailbox-messages mailbox))
            (receivers (Mailbox-receivers mailbox)))
        (put-back! messages (enqueue (ref-replace! messages (empty-queue)) message))
        (ref-set! receivers (wake-first (ref-get receivers)))))

    ;; A queue goes back into the cell it was taken from, which still holds
    ;; the empty queue the swap left; matching consumes that. Anything else
    ;; would mean a second writer.
    (: put-back! (All (T) (-> (Ref (Queue T)) (Queue T) Unit ! mut)))
    (define (put-back! cell queue)
      (match (ref-replace! cell queue)
        ((Queue (Nil) (Nil)) (unit))
        ((Queue front back) (panic "a mailbox changed while its messages were out"))))

    ;; A receiver that is no longer parked, because its task was cancelled
    ;; while it waited, is dropped, so the message wakes the next one.
    (: wake-first (-> (Queue I64) (Queue I64) ! tasks))
    (define (wake-first receivers)
      (match (dequeue receivers)
        ((None) receivers)
        ((Some (Pair task rest)) (if (unpark-task task) rest (wake-first rest)))))

    ;; Receiving takes the oldest message. With none, the swap has already
    ;; left the cell empty, and the task parks until a post wakes it and
    ;; then looks again, since a receiver that was already running may have
    ;; taken the message first. Parking is not a busy wait: the task does
    ;; not run again until a post wakes it.
    (: mailbox-receive (All (T) (-> (Mailbox T) T ! mut tasks)))
    (define (mailbox-receive mailbox)
      (let ((messages (Mailbox-messages mailbox)))
        (match (dequeue (ref-replace! messages (empty-queue)))
          ((Some (Pair message rest))
           (put-back! messages rest)
           message)
          ((None)
           (let ((receivers (Mailbox-receivers mailbox)))
             (ref-set! receivers (enqueue (ref-get receivers) (current-task))))
           (park-task)
           (mailbox-receive mailbox)))))))
