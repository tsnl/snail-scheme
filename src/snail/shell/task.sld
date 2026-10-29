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
    ;; front, reversed, when the front runs out.
    (struct (Queue T)
      ((front (List T))
       (back (List T))))

    (: empty-queue (All (T) (-> (Queue T))))
    (define (empty-queue)
      (Queue (Nil) (Nil)))

    (: enqueue (All (T) (requires (Copy T)) (-> (Queue T) T (Queue T))))
    (define (enqueue queue item)
      (Queue-back-set queue (Cons item (Queue-back queue))))

    (: dequeue (All (T) (requires (Copy T)) (-> (Queue T) (Option (Pair T (Queue T))))))
    (define (dequeue queue)
      (match (Queue-front queue)
        ((Cons item rest) (Some (Pair item (Queue rest (Queue-back queue)))))
        ((Nil) (match (Queue-back queue)
                 ((Nil) (None))
                 ((Cons _ _) (dequeue (Queue (reverse (Queue-back queue)) (Nil))))))))

    ;; ---- Mailboxes ----

    ;; What a mailbox holds: the messages posted and not yet received, and
    ;; the ids of the tasks parked in `mailbox-receive`, each in the order
    ;; it arrived.
    (struct (Pending T)
      ((messages (Queue T))
       (receivers (Queue I64))))

    ;; Tasks share a mailbox, so what it holds cannot be threaded through
    ;; any one of them: this Ref is the boundary between them, and the
    ;; only mutable state here. Neither operation suspends between reading
    ;; it and writing it back.
    (struct (Mailbox T)
      ((pending (Ref (Pending T)))))

    (: make-mailbox (All (T) (requires (Copy T)) (-> (Mailbox T) ! mut)))
    (define (make-mailbox)
      (Mailbox (ref (Pending (empty-queue) (empty-queue)))))

    ;; Posting never waits. The message joins the queue, and the receiver
    ;; parked longest is woken to take it.
    (: mailbox-post (All (T) (requires (Copy T)) (-> (Mailbox T) T Unit ! mut tasks)))
    (define (mailbox-post mailbox message)
      (let* ((pending (ref-get (Mailbox-pending mailbox)))
             (receivers (wake-first (Pending-receivers pending))))
        (ref-set! (Mailbox-pending mailbox)
                  (Pending (enqueue (Pending-messages pending) message) receivers))))

    ;; A receiver that is no longer parked, because its task was cancelled
    ;; while it waited, is dropped, so the message wakes the next one.
    (: wake-first (-> (Queue I64) (Queue I64) ! tasks))
    (define (wake-first receivers)
      (match (dequeue receivers)
        ((None) receivers)
        ((Some (Pair task rest)) (if (unpark-task task) rest (wake-first rest)))))

    ;; Receiving takes the oldest message. With none, the task parks until
    ;; a post wakes it and then looks again, since a receiver that was
    ;; already running may have taken the message first. Parking is not a
    ;; busy wait: the task does not run again until a post wakes it.
    (: mailbox-receive (All (T) (requires (Copy T)) (-> (Mailbox T) T ! mut tasks)))
    (define (mailbox-receive mailbox)
      (let ((pending (ref-get (Mailbox-pending mailbox))))
        (match (dequeue (Pending-messages pending))
          ((Some (Pair message rest))
           (ref-set! (Mailbox-pending mailbox) (Pending-messages-set pending rest))
           message)
          ((None)
           (ref-set! (Mailbox-pending mailbox)
                     (Pending-receivers-set pending
                                            (enqueue (Pending-receivers pending) (current-task))))
           (park-task)
           (mailbox-receive mailbox)))))))
