;; Tasks: one-shot local work that runs until it waits, scheduled here in
;; Snail-Core. Each task runs under its own handler of `tasks`, whose
;; control operations hand the rest of the task back to the scheduler as
;; a step instead of resuming it. The host drives the scheduler: it calls
;; `tasks:turn` until nothing is live, and wakes the tickets of the host
;; operations that complete with `tasks:wake`. A mailbox carries messages
;; between tasks, in the order they are posted.
;;
;; The host sees the scheduler only through these exports:
;;
;; - `tasks:turn now` runs a turn, answering when the next is due;
;; - `tasks:wake ticket` readies the task waiting on a ticket, answering
;;   whether one was;
;; - `tasks:close` drops every task;
;; - `tasks:running` names the running task: after a trap, the task that
;;   trapped, which the trap ended;
;; - `tasks:live` counts the tasks that have not finished.
(define-library (snail shell task)
  (export
   tasks yield sleep await ticket
   dispatch-local dispatch-task
   through-host
   Mailbox make-mailbox mailbox-post mailbox-receive)
  (import
   (snail core base)
   (only (snail core forms) host)
   (only (snail core primitive) inherit-handlers))
  (begin

    ;; ---- The effect ----

    ;; `yield` lets every other ready task run first, `sleep` waits for a
    ;; number of milliseconds, and `await` waits until a ticket is woken. A
    ;; ticket names one wait; taking one does not suspend, so `ticket` is
    ;; an ordinary operation.
    (effect tasks
      ((ctl yield (-> Unit))
       (ctl sleep (-> I64 Unit))
       (ctl await (-> I64 Unit))
       (ticket (-> I64))))

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

    ;; ---- Steps ----

    ;; What a task does next, once it stops running. Each `next` is the
    ;; rest of the task, closed over the handlers in scope where the task
    ;; was dispatched, so it runs under them whoever calls it: a child
    ;; keeps its parent's handlers after the parent returns, and at every
    ;; resumption.
    (enum Step
      (Finished)
      (Yielded
       ((next (FnOnce Step ! host))))
      (Sleeping
       ((delay I64)
        (next (FnOnce Step ! host))))
      (Waiting
       ((ticket I64)
        (next (FnOnce Step ! host)))))

    (type Run (FnOnce Step ! host))

    ;; A task that is ready, under its id.
    (struct Task
      ((id I64)
       (next Run)))

    ;; A task waiting to be woken, by its deadline among the timers or by
    ;; its ticket among the waiters.
    (struct Pending
      ((key I64)
       (id I64)
       (next Run)))

    ;; ---- The scheduler ----

    ;; Tasks share the scheduler, so its state is the boundary between
    ;; them. A task that is not running is in exactly one place: `ready`,
    ;; `timers`, sorted by deadline, or `waiters`. A list of linear values
    ;; has no length to read, so `ready-count` counts the ready tasks and
    ;; `live` the tasks in all three. `running` is the id of the running
    ;; task, and 0 between tasks; `last-task` is the last id given out.
    ;; `now` is the current turn's clock, in milliseconds.
    ;;
    ;; Tickets are numbered from the first turn's clock, so that a ticket
    ;; a Mailbox kept across a relink, from the scheduler before this one,
    ;; names no wait of this one, unless that one took a thousand tickets a
    ;; millisecond.
    (struct Scheduler
      ((ready mut (Queue Task))
       (ready-count mut I64)
       (timers mut (List Pending))
       (waiters mut (List Pending))
       (live mut I64)
       (running mut I64)
       (last-task mut I64)
       (now mut I64)
       (last-ticket mut I64)))

    (: scheduler Scheduler)
    (define scheduler (Scheduler (empty-queue) 0 (Nil) (Nil) 0 0 0 0 0))

    ;; A linear field's content moves out by a swap that leaves an empty
    ;; placeholder, and back by a swap that must answer that placeholder:
    ;; anything else would mean a second writer.
    (: take-ready! (-> (Queue Task) ! mut))
    (define (take-ready!)
      (Scheduler-ready-replace! scheduler (empty-queue)))

    (: put-ready! (-> (Queue Task) Unit ! mut))
    (define (put-ready! queue)
      (match (Scheduler-ready-replace! scheduler queue)
        ((Queue (Nil) (Nil)) (unit))
        ((Queue front back) (panic "the ready queue changed while it was out"))))

    (: take-timers! (-> (List Pending) ! mut))
    (define (take-timers!)
      (Scheduler-timers-replace! scheduler (Nil)))

    (: put-timers! (-> (List Pending) Unit ! mut))
    (define (put-timers! timers)
      (match (Scheduler-timers-replace! scheduler timers)
        ((Nil) (unit))
        ((Cons first rest) (panic "the timers changed while they were out"))))

    (: take-waiters! (-> (List Pending) ! mut))
    (define (take-waiters!)
      (Scheduler-waiters-replace! scheduler (Nil)))

    (: put-waiters! (-> (List Pending) Unit ! mut))
    (define (put-waiters! waiters)
      (match (Scheduler-waiters-replace! scheduler waiters)
        ((Nil) (unit))
        ((Cons first rest) (panic "the waiters changed while they were out"))))

    (: add-live! (-> I64 Unit ! mut))
    (define (add-live! change)
      (Scheduler-live-set! scheduler (+ (Scheduler-live scheduler) change)))

    (: add-ready! (-> I64 Unit ! mut))
    (define (add-ready! change)
      (Scheduler-ready-count-set! scheduler (+ (Scheduler-ready-count scheduler) change)))

    (: push-ready! (-> Task Unit ! mut))
    (define (push-ready! task)
      (put-ready! (enqueue (take-ready!) task))
      (add-ready! 1))

    ;; ---- Dispatching ----

    ;; A task runs `work` under its own handler of `tasks`, until the work
    ;; finishes or waits. The implementations run in the handle's outer
    ;; context, which holds the dispatcher's handlers, and close the rest of
    ;; the task over them. A `resume` runs the rest of the work under this
    ;; handle again, so closing it cannot let a yield to `tasks` escape.
    (: start-task (All (e) (-> (FnOnce Unit ! tasks e) Step ! mut e)))
    (define (start-task work)
      (handle tasks
          ((yield (lambda (resume)
                    (Yielded (inherit-handlers (once (lambda () (resume (unit))))))))
           (sleep (lambda (delay resume)
                    (Sleeping delay (inherit-handlers (once (lambda () (resume (unit))))))))
           (await (lambda (ticket resume)
                    (Waiting ticket (inherit-handlers (once (lambda () (resume (unit))))))))
           (ticket (lambda () (next-ticket!))))
        (work)
        (Finished)))

    (: next-ticket! (-> I64 ! mut))
    (define (next-ticket!)
      (let ((ticket (+ (Scheduler-last-ticket scheduler) 1)))
        (Scheduler-last-ticket-set! scheduler ticket)
        ticket))

    ;; Dispatching charges the work's effects to the dispatcher, so it
    ;; cannot hide an unhandled operation. The work runs on a later turn,
    ;; as a task whose id `dispatch-task` answers.
    (: dispatch-local (All (e) (-> (FnOnce Unit ! tasks e) Unit ! mut e)))
    (define (dispatch-local work)
      (dispatch-task work)
      (unit))

    (: dispatch-task (All (e) (-> (FnOnce Unit ! tasks e) I64 ! mut e)))
    (define (dispatch-task work)
      (let ((id (+ (Scheduler-last-task scheduler) 1)))
        (Scheduler-last-task-set! scheduler id)
        (add-live! 1)
        (push-ready! (Task id (inherit-handlers (once (lambda () (start-task work))))))
        id))

    ;; ---- Turns ----

    ;; One turn runs the tasks that were ready when it began, so tasks that
    ;; yield to each other cannot keep the host from its events, then
    ;; readies the sleepers whose deadline has passed. It answers 0 when a
    ;; task is ready, -1 when no task is live, -2 when every task waits on a
    ;; ticket, and otherwise the milliseconds until the earliest deadline.
    (: turn (-> I64 I64 ! mut host))
    (define (turn now)
      (when (= (Scheduler-last-ticket scheduler) 0)
        (Scheduler-last-ticket-set! scheduler (* now 1000)))
      (Scheduler-now-set! scheduler now)
      (run-ready! (Scheduler-ready-count scheduler))
      (put-timers! (wake-due! now (take-timers!)))
      (outlook now))

    ;; A task leaves the queue, and the rest of the queue is back in its
    ;; field, before the task runs, so a trap in it loses that task alone,
    ;; which `running` still names: the host reports the trap and calls
    ;; `turn` again.
    (: run-ready! (-> I64 Unit ! mut host))
    (define (run-ready! count)
      (when (> count 0)
        (match (dequeue (take-ready!))
          ((None) (put-ready! (empty-queue)))
          ((Some (Pair (Task id run) rest))
           (put-ready! rest)
           (add-ready! -1)
           (add-live! -1)
           (Scheduler-running-set! scheduler id)
           (record! id (run))
           (Scheduler-running-set! scheduler 0)
           (run-ready! (- count 1))))))

    (: record! (-> I64 Step Unit ! mut))
    (define (record! id step)
      (match step
        ((Finished) (unit))
        ((Yielded next)
         (add-live! 1)
         (push-ready! (Task id next)))
        ((Sleeping delay next)
         (add-live! 1)
         (put-timers!
          (insert-timer (Pending (+ (Scheduler-now scheduler) delay) id next) (take-timers!))))
        ((Waiting ticket next)
         (add-live! 1)
         (put-waiters! (Cons (Pending ticket id next) (take-waiters!))))))

    ;; A timer goes after every timer due no later, so sleepers with one
    ;; deadline wake in the order they slept.
    (: insert-timer (-> Pending (List Pending) (List Pending)))
    (define (insert-timer timer timers)
      (match timers
        ((Nil) (Cons timer (Nil)))
        ((Cons first rest)
         (if (< (Pending-key timer) (Pending-key first))
             (Cons timer (Cons first rest))
             (Cons first (insert-timer timer rest))))))

    (: wake-due! (-> I64 (List Pending) (List Pending) ! mut))
    (define (wake-due! now timers)
      (match timers
        ((Nil) (Nil))
        ((Cons first rest)
         (if (<= (Pending-key first) now)
             (match first
               ((Pending _ id next)
                (push-ready! (Task id next))
                (wake-due! now rest)))
             (Cons first rest)))))

    (: outlook (-> I64 I64 ! mut))
    (define (outlook now)
      (cond
       ((> (Scheduler-ready-count scheduler) 0) 0)
       ((= (Scheduler-live scheduler) 0) -1)
       (else
        (match (take-timers!)
          ((Nil)
           (put-timers! (Nil))
           -2)
          ((Cons first rest)
           (let ((deadline (Pending-key first)))
             (put-timers! (Cons first rest))
             (- deadline now)))))))

    ;; ---- Waking and closing ----

    ;; Wakes the task waiting on a ticket, answering whether one was: a
    ;; stale ticket, such as one whose task trapped, or whose scheduler
    ;; closed, wakes nothing.
    (: wake! (-> I64 Bool ! mut))
    (define (wake! ticket)
      (match (without ticket (take-waiters!))
        ((Pair found rest)
         (put-waiters! rest)
         (match found
           ((Some task)
            (push-ready! task)
            #t)
           ((None) #f)))))

    (: without (-> I64 (List Pending) (Pair (Option Task) (List Pending))))
    (define (without ticket waiters)
      (match waiters
        ((Nil) (Pair (None) (Nil)))
        ((Cons first rest)
         (if (= (Pending-key first) ticket)
             (match first
               ((Pending _ id next) (Pair (Some (Task id next)) rest)))
             (match (without ticket rest)
               ((Pair found others) (Pair found (Cons first others))))))))

    ;; Closing drops every task that is not running, as a relink does with
    ;; the tasks of the program it replaces: what they hold is abandoned.
    ;; A task is its rest, a FnOnce, which runs nothing when dropped, so
    ;; dropping a queue of them discards it whole.
    (: close! (-> Unit ! mut))
    (define (close!)
      (drop (take-ready!))
      (drop (take-timers!))
      (drop (take-waiters!))
      (Scheduler-ready-count-set! scheduler 0)
      (Scheduler-live-set! scheduler 0))

    (: running (-> I64 ! mut))
    (define (running)
      (Scheduler-running scheduler))

    (: live (-> I64 ! mut))
    (define (live)
      (Scheduler-live scheduler))

    (expose turn "tasks:turn")
    (expose wake! "tasks:wake")
    (expose close! "tasks:close")
    (expose running "tasks:running")
    (expose live "tasks:live")

    ;; ---- Waiting on the host ----

    ;; A host operation that completes later: `start` begins it under a
    ;; fresh ticket and returns at once, the task waits until the host
    ;; wakes the ticket, and `finish` takes the outcome the host kept for
    ;; it. Only the task's own Wasm runs between taking the ticket and
    ;; awaiting it, so the completion cannot come first.
    (: through-host (All (A) (-> (-> I64 Unit) (-> I64 A) A ! tasks)))
    (define (through-host start finish)
      (let ((id (ticket)))
        (start id)
        (await id)
        (finish id)))

    ;; ---- Mailboxes ----

    ;; Tasks share a mailbox, so what it holds cannot be threaded through
    ;; any one of them: its cells are the boundary between them. `messages`
    ;; holds what was posted while no task waited, and `receivers` the tasks
    ;; waiting in `mailbox-receive`, each in the order it arrived; at most
    ;; one of the two queues is not empty. A message may be linear, so it
    ;; moves in and out of a cell with `ref-replace!`, and neither
    ;; operation suspends while a cell holds the empty value a swap left.
    (struct (Mailbox T)
      ((messages (Ref (Queue T)))
       (receivers (Ref (Queue (Receiver T))))))

    ;; A waiting receiver: the ticket its task waits on, and the cell a post
    ;; hands it its message in.
    (struct (Receiver T)
      ((ticket I64)
       (slot (Ref (Option T)))))

    (: make-mailbox (All (T) (-> (Mailbox T))))
    (define (make-mailbox)
      (Mailbox (ref (empty-queue)) (ref (empty-queue))))

    ;; Posting never waits, so a program may post before any task runs.
    ;; The receiver that has waited longest is handed the message and woken,
    ;; so a task that asks before that one runs cannot take it. A receiver
    ;; whose ticket wakes nothing, because its task trapped or its scheduler
    ;; closed while it waited, is dropped, and the message goes to the next.
    ;; With no receiver, the message joins the queue. A message handed to a
    ;; receiver is its: should the scheduler close before that task runs,
    ;; the message goes with it, as one it had received would.
    (: mailbox-post (All (T) (-> (Mailbox T) T Unit ! mut)))
    (define (mailbox-post mailbox message)
      (let ((receivers (Mailbox-receivers mailbox)))
        (match (dequeue (ref-get receivers))
          ((None)
           (let ((messages (Mailbox-messages mailbox)))
             (put-back! messages (enqueue (ref-replace! messages (empty-queue)) message))))
          ((Some (Pair receiver rest))
           (ref-set! receivers rest)
           (if (wake! (Receiver-ticket receiver))
               (hand! (Receiver-slot receiver) message)
               (mailbox-post mailbox message))))))

    ;; A queue goes back into the cell it was taken from, which still holds
    ;; the empty queue the swap left; matching consumes that.
    (: put-back! (All (T) (-> (Ref (Queue T)) (Queue T) Unit ! mut)))
    (define (put-back! cell queue)
      (match (ref-replace! cell queue)
        ((Queue (Nil) (Nil)) (unit))
        ((Queue front back) (panic "a mailbox changed while its messages were out"))))

    ;; A receiver's slot is handed one message, while it is empty.
    (: hand! (All (T) (-> (Ref (Option T)) T Unit ! mut)))
    (define (hand! slot message)
      (match (ref-replace! slot (Some message))
        ((None) (unit))
        ((Some held) (panic "a receiver was handed a second message"))))

    ;; Receiving takes the oldest message. With none, the swap has already
    ;; left the cell empty, and the task waits in line on a ticket until a
    ;; post hands it a message, so receivers are served in the order they
    ;; began to wait.
    (: mailbox-receive (All (T) (-> (Mailbox T) T ! mut tasks)))
    (define (mailbox-receive mailbox)
      (let ((messages (Mailbox-messages mailbox)))
        (match (dequeue (ref-replace! messages (empty-queue)))
          ((Some (Pair message rest))
           (put-back! messages rest)
           message)
          ((None) (wait-in-line mailbox)))))

    ;; Only a post wakes the ticket, and it hands the message first.
    (: wait-in-line (All (T) (-> (Mailbox T) T ! mut tasks)))
    (define (wait-in-line mailbox)
      (let ((receivers (Mailbox-receivers mailbox))
            (receiver (Receiver (ticket) (ref (None)))))
        (ref-set! receivers (enqueue (ref-get receivers) receiver))
        (await (Receiver-ticket receiver))
        (match (ref-replace! (Receiver-slot receiver) (None))
          ((Some message) message)
          ((None) (panic "a receiver woke without a message")))))))
