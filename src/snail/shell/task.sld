;; Runtime-owned control operations. Dispatch transfers one-shot local work;
;; its latent effects remain requirements of the dispatching computation.
;; A mailbox carries messages between tasks, in the order they are posted,
;; and a host operation that completes later is waited for by ticket.
(define-library (snail shell task)
  (export
   tasks dispatch-local yield sleep
   through-host
   Mailbox make-mailbox mailbox-post mailbox-receive)
  (import
   (snail core base)
   (only (snail core forms) tasks)
   (only (snail core primitive) dispatch-local ticket-task await-task wake-task)
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

    ;; ---- Waiting on the host ----

    ;; A host operation that completes later: `start` begins it under a
    ;; fresh ticket and returns at once, the task waits until the host
    ;; wakes the ticket, and `finish` takes the outcome the host kept for
    ;; it. Only the task's own Wasm runs between taking the ticket and
    ;; awaiting it, so the completion cannot come first.
    (: through-host (All (A) (-> (-> I64 Unit) (-> I64 A) A ! tasks)))
    (define (through-host start finish)
      (let ((ticket (ticket-task)))
        (start ticket)
        (await-task ticket)
        (finish ticket)))

    ;; ---- Mailboxes ----

    ;; Tasks share a mailbox, so what it holds cannot be threaded through
    ;; any one of them: its two cells are the boundary between them, and
    ;; the only mutable state here. `messages` holds what was posted and
    ;; not yet received, and `receivers` the tickets of the tasks waiting
    ;; in `mailbox-receive`, each in the order it arrived. A message may be
    ;; linear, so it moves in and out of its cell with `ref-replace!`, and
    ;; neither operation suspends while the cell holds the empty queue the
    ;; swap left.
    (struct (Mailbox T)
      ((messages (Ref (Queue T)))
       (receivers (Ref (Queue I64)))))

    (: make-mailbox (All (T) (-> (Mailbox T))))
    (define (make-mailbox)
      (Mailbox (ref (empty-queue)) (ref (empty-queue))))

    ;; Posting never waits. The message joins the queue, and the receiver
    ;; that has waited longest is woken to take it.
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

    ;; A receiver whose ticket wakes nothing, because its task was
    ;; cancelled while it waited, is dropped, so the message wakes the next
    ;; one.
    (: wake-first (-> (Queue I64) (Queue I64) ! tasks))
    (define (wake-first receivers)
      (match (dequeue receivers)
        ((None) receivers)
        ((Some (Pair ticket rest)) (if (wake-task ticket) rest (wake-first rest)))))

    ;; Receiving takes the oldest message. With none, the swap has already
    ;; left the cell empty, and the task waits on a ticket until a post
    ;; wakes it and then looks again, since a receiver that was already
    ;; running may have taken the message first. Waiting is not a busy
    ;; wait: the task does not run again until a post wakes it.
    (: mailbox-receive (All (T) (-> (Mailbox T) T ! mut tasks)))
    (define (mailbox-receive mailbox)
      (let ((messages (Mailbox-messages mailbox)))
        (match (dequeue (ref-replace! messages (empty-queue)))
          ((Some (Pair message rest))
           (put-back! messages rest)
           message)
          ((None)
           (let ((receivers (Mailbox-receivers mailbox)) (ticket (ticket-task)))
             (ref-set! receivers (enqueue (ref-get receivers) ticket))
             (await-task ticket))
           (mailbox-receive mailbox)))))))
