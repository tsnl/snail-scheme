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
;; - `tasks:start-main body` runs a program's body, its `main:body`
;;   export, as the first task, so the program's statements may yield;
;; - `tasks:turn now` runs a turn, answering when the next is due;
;; - `tasks:wake ticket` readies the task waiting on a ticket, answering
;;   whether one was;
;; - `tasks:close` drops every task;
;; - `tasks:running` names the running task: after a trap, the task that
;;   trapped, which the trap ended;
;; - `tasks:live` counts the tasks that have not finished.
;;
;; An engine written in Snail-Core ((snail shell engine)) runs tasks of
;; its own beside the program's, and turns this scheduler, its own, by the
;; same functions, which it imports as `tasks-turn`, `tasks-wake!`,
;; `tasks-close!`, `tasks-running` and `tasks-live`.
(define-library (snail shell task)
  (export
   tasks yield sleep await ticket
   dispatch-local dispatch-task
   through-host
   tasks-turn tasks-wake! tasks-close! tasks-running tasks-live
   Mailbox make-mailbox mailbox-post mailbox-receive mailbox-try-receive)
  (import
   (snail core base)
   (only (snail core forms) host Funcref)
   (only (snail core primitive) inherit-handlers unsafe-cast)
   (snail shell slot))
  (begin

    ;; ---- The effect ----

    ;; `yield` lets every other ready task run first, `sleep` waits for a
    ;; number of milliseconds, and `await` waits until a ticket is woken. A
    ;; ticket names one wait; taking one does not suspend, so `ticket` is
    ;; an ordinary operation. A program's body runs as its first task,
    ;; under this handler, so it may perform these (`around-main`).
    (effect tasks
      ((ctl yield (dyn (Fn → Unit)))
       (ctl sleep (dyn (Fn I64 → Unit)))
       (ctl await (dyn (Fn I64 → Unit)))
       (ticket (dyn (Fn → I64))))
      (around-main))

    ;; ---- Queues ----

    ;; Items leave from the front and join at the back, which becomes the
    ;; front, reversed, when the front runs out. Both operations take the
    ;; queue apart with `match`, so items only move, and a queue may hold
    ;; linear values.
    (struct (Queue T)
      ((front (List T))
       (back (List T))))

    (define (empty-queue) (→ (Queue T)) (∀ T)
      (Queue (Nil) (Nil)))

    (define (enqueue (queue (Queue T)) (item T)) (→ (Queue T)) (∀ T)
      (match queue
        ((Queue front back) (Queue front (Cons item back)))))

    (define (dequeue (queue (Queue T))) (→ (Option (Pair T (Queue T)))) (∀ T)
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
       ((next (dyn (FnOnce → Step ! host)))))
      (Sleeping
       ((delay I64)
        (next (dyn (FnOnce → Step ! host)))))
      (Waiting
       ((ticket I64)
        (next (dyn (FnOnce → Step ! host))))))

    (type Run (dyn (FnOnce → Step ! host)))

    ;; A task that is ready, under its id.
    (struct Runnable
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
    ;; them. A task that is not running is in exactly one place: the
    ;; `ready` queue, the `timers`, sorted by deadline, or the `waiters`.
    ;; Each is a slot of the runtime's, since a task is linear and a cell
    ;; holds no linear value, taken out and put back around each change
    ;; while no task runs; the counters are a value in one cell. A list of
    ;; linear values has no length to read, so `ready-count` counts the
    ;; ready tasks and `live` the tasks in all three. `running` is the id of the running
    ;; task, and 0 between tasks; `last-task` is the last id given out.
    ;; `now` is the current turn's clock, in milliseconds.
    ;;
    ;; Tickets are numbered from the first turn's clock, so that a ticket
    ;; a Mailbox kept across a relink, from the scheduler before this one,
    ;; names no wait of this one, unless that one took a thousand tickets a
    ;; millisecond.
    (struct Scheduler
      ((ready-count I64)
       (live I64)
       (running I64)
       (last-task I64)
       (now I64)
       (last-ticket I64)))

    ;; The counters are a value in one cell, whose slots are its fields;
    ;; each operation writes the one field it changes.

    (define scheduler (→ (Ref Scheduler)) (ref (Scheduler 0 0 0 0 0 0)))

    ;; The queues of tasks rest in the runtime's slots. A queue is taken
    ;; out, changed and put back while no task runs, so a second taker,
    ;; such as a host callback reentering `wake`, traps in the slot.

    (define ready (→ (UnsafeSlot (Queue Runnable))) (unsafe-slot (empty-queue)))

    (define timers (→ (UnsafeSlot (List Pending))) (unsafe-slot (Nil)))

    (define waiters (→ (UnsafeSlot (List Pending))) (unsafe-slot (Nil)))

    (define (take-ready!) (→ (Queue Runnable)) (! mut)
      (take! ready))

    (define (put-ready! (queue (Queue Runnable))) (→ Unit) (! mut)
      (put! ready queue))

    (define (take-timers!) (→ (List Pending)) (! mut)
      (take! timers))

    (define (put-timers! (pending (List Pending))) (→ Unit) (! mut)
      (put! timers pending))

    (define (take-waiters!) (→ (List Pending)) (! mut)
      (take! waiters))

    (define (put-waiters! (pending (List Pending))) (→ Unit) (! mut)
      (put! waiters pending))

    (define (add-live! (change I64)) (→ Unit) (! mut)
      (set! (::live (ref-get scheduler)) (+ (::live (ref-get scheduler)) change)))

    (define (add-ready! (change I64)) (→ Unit) (! mut)
      (set! (::ready-count (ref-get scheduler)) (+ (::ready-count (ref-get scheduler)) change)))

    (define (push-ready! (task Runnable)) (→ Unit) (! mut)
      (put-ready! (enqueue (take-ready!) task))
      (add-ready! 1))

    ;; ---- Dispatching ----

    ;; A task runs `work` under its own handler of `tasks`, until the work
    ;; finishes or waits. The implementations run in the handle's outer
    ;; context, which holds the dispatcher's handlers, and close the rest of
    ;; the task over them. A `resume` runs the rest of the work under this
    ;; handle again, so closing it cannot let a yield to `tasks` escape.

    (define (start-task (work (dyn (FnOnce → Unit ! tasks e)))) (→ Step) (! mut e) (∀ e)
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

    (define (next-ticket!) (→ I64) (! mut)
      (let ((ticket (+ (::last-ticket (ref-get scheduler)) 1)))
        (set! (::last-ticket (ref-get scheduler)) ticket)
        ticket))

    ;; Dispatching charges the work's effects to the dispatcher, so it
    ;; cannot hide an unhandled operation. The work runs on a later turn,
    ;; as a task whose id `dispatch-task` answers.

    (define (dispatch-local (work (dyn (FnOnce → Unit ! tasks e)))) (→ Unit) (! mut e) (∀ e)
      (dispatch-task work)
      (unit))

    (define (dispatch-task (work (dyn (FnOnce → Unit ! tasks e)))) (→ I64) (! mut e) (∀ e)
      (let ((id (+ (::last-task (ref-get scheduler)) 1)))
        (set! (::last-task (ref-get scheduler)) id)
        (add-live! 1)
        (push-ready! (Runnable id (inherit-handlers (once (lambda () (start-task work))))))
        id))

    ;; ---- Turns ----

    ;; One turn runs the tasks that were ready when it began, so tasks that
    ;; yield to each other cannot keep the host from its events, then
    ;; readies the sleepers whose deadline has passed. It answers 0 when a
    ;; task is ready, -1 when no task is live, -2 when every task waits on a
    ;; ticket, and otherwise the milliseconds until the earliest deadline.

    (define (tasks-turn (now I64)) (→ I64) (! mut host)
      (when (= (::last-ticket (ref-get scheduler)) 0)
        (set! (::last-ticket (ref-get scheduler)) (* now 1000)))
      (set! (::now (ref-get scheduler)) now)
      (run-ready! (::ready-count (ref-get scheduler)))
      (put-timers! (wake-due! now (take-timers!)))
      (outlook now))

    ;; A task leaves the queue, and the rest of the queue is back in its
    ;; field, before the task runs, so a trap in it loses that task alone,
    ;; which `running` still names: the host reports the trap and calls
    ;; `turn` again.

    (define (run-ready! (count I64)) (→ Unit) (! mut host)
      (when (> count 0)
        (match (dequeue (take-ready!))
          ((None) (put-ready! (empty-queue)))
          ((Some (Pair (Runnable id run) rest))
           (put-ready! rest)
           (add-ready! -1)
           (add-live! -1)
           (set! (::running (ref-get scheduler)) id)
           (record! id (run))
           (set! (::running (ref-get scheduler)) 0)
           (run-ready! (- count 1))))))

    (define (record! (id I64) (step Step)) (→ Unit) (! mut)
      (match step
        ((Finished) (unit))
        ((Yielded next)
         (add-live! 1)
         (push-ready! (Runnable id next)))
        ((Sleeping delay next)
         (add-live! 1)
         (put-timers!
          (insert-timer (Pending (+ (::now (ref-get scheduler)) delay) id next) (take-timers!))))
        ((Waiting ticket next)
         (add-live! 1)
         (put-waiters! (Cons (Pending ticket id next) (take-waiters!))))))

    ;; A timer goes after every timer due no later, so sleepers with one
    ;; deadline wake in the order they slept.

    (define (insert-timer (timer Pending) (timers (List Pending))) (→ (List Pending))
      (match timers
        ((Nil) (Cons timer (Nil)))
        ((Cons first rest)
         (if (< (::key timer) (::key first))
             (Cons timer (Cons first rest))
             (Cons first (insert-timer timer rest))))))

    (define (wake-due! (now I64) (timers (List Pending))) (→ (List Pending)) (! mut)
      (match timers
        ((Nil) (Nil))
        ((Cons first rest)
         (if (<= (::key first) now)
             (match first
               ((Pending _ id next)
                (push-ready! (Runnable id next))
                (wake-due! now rest)))
             (Cons first rest)))))

    (define (outlook (now I64)) (→ I64) (! mut)
      (cond
       ((> (::ready-count (ref-get scheduler)) 0) 0)
       ((= (::live (ref-get scheduler)) 0) -1)
       (else
        (match (take-timers!)
          ((Nil)
           (put-timers! (Nil))
           -2)
          ((Cons first rest)
           (let ((deadline (::key first)))
             (put-timers! (Cons first rest))
             (- deadline now)))))))

    ;; ---- Waking and closing ----

    ;; Wakes the task waiting on a ticket, answering whether one was: a
    ;; stale ticket, such as one whose task trapped, or whose scheduler
    ;; closed, wakes nothing.

    (define (tasks-wake! (ticket I64)) (→ Bool) (! mut)
      (match (without ticket (take-waiters!))
        ((Pair found rest)
         (put-waiters! rest)
         (match found
           ((Some task)
            (push-ready! task)
            #t)
           ((None) #f)))))

    (define (without (ticket I64) (waiters (List Pending)))
      (→ (Pair (Option Runnable) (List Pending)))
      (match waiters
        ((Nil) (Pair (None) (Nil)))
        ((Cons first rest)
         (if (= (::key first) ticket)
             (match first
               ((Pending _ id next) (Pair (Some (Runnable id next)) rest)))
             (match (without ticket rest)
               ((Pair found others) (Pair found (Cons first others))))))))

    ;; Closing drops every task that is not running, as a relink does with
    ;; the tasks of the program it replaces. A task is its rest, a FnOnce;
    ;; dropping one unrun drops the linear values its frames hold, which
    ;; performs what their drops perform, within the task's row, `host`.
    ;; Detach every queue before any drop runs: a promise's drop may wake
    ;; another task. Drain again if cleanup dispatched more work.

    (define (tasks-close!) (→ Unit) (! mut host)
      (let ((queued (take-ready!)) (sleeping (take-timers!)) (waiting (take-waiters!)))
        (put-ready! (empty-queue))
        (put-timers! (Nil))
        (put-waiters! (Nil))
        (set! (::ready-count (ref-get scheduler)) 0)
        (set! (::live (ref-get scheduler)) 0)
        (drop queued)
        (drop sleeping)
        (drop waiting))
      (when (> (::live (ref-get scheduler)) 0) (tasks-close!)))

    (define (tasks-running) (→ I64) (! mut)
      (::running (ref-get scheduler)))

    (define (tasks-live) (→ I64) (! mut)
      (::live (ref-get scheduler)))

    ;; The program's body, its `main:body` export, which takes the evidence
    ;; and answers its status, run as the first task: the host, or the
    ;; engine, calls this in place of the body, once the program's
    ;; definitions are initialized, so the statements run under this
    ;; scheduler's handler of `tasks` and may yield.

    (define (start-main (body Funcref)) (→ Unit) (! mut host)
      (dispatch-local (once (lambda ()
                              ((ann (unsafe-cast body) (dyn (Fn → I32 ! tasks host))))
                              (unit)))))

    (expose start-main "tasks:start-main")
    (expose tasks-turn "tasks:turn")
    (expose tasks-wake! "tasks:wake")
    (expose tasks-close! "tasks:close")
    (expose tasks-running "tasks:running")
    (expose tasks-live "tasks:live")

    ;; ---- Waiting on the host ----

    ;; A host operation that completes later: `start` begins it under a
    ;; fresh ticket and returns at once, the task waits until the host
    ;; wakes the ticket, and `finish` takes the outcome the host kept for
    ;; it. Only the task's own Wasm runs between taking the ticket and
    ;; awaiting it, so the completion cannot come first.

    (define (through-host (start (dyn (Fn I64 → Unit))) (finish (dyn (Fn I64 → A))))
      (→ A)
      (! tasks)
      (∀ A)
      (let ((id (ticket)))
        (start id)
        (await id)
        (finish id)))

    ;; ---- Mailboxes ----

    ;; Tasks share a mailbox, so what it holds cannot be threaded through
    ;; any one of them: its cells are the boundary between them. `messages`
    ;; holds what was posted while no task waited, and `receivers` the tasks
    ;; waiting in `mailbox-receive`, each in the order it arrived; at most
    ;; one of the two queues is not empty. A message may be linear, so the
    ;; queues rest in the runtime's slots, taken out and put back around
    ;; each change, and no operation suspends while one is out.
    (struct (Mailbox T)
      ((messages (UnsafeSlot (Queue T)))
       (receivers (UnsafeSlot (Queue (Receiver T))))))

    ;; A waiting receiver: the ticket its task waits on, and the slot a post
    ;; hands it its message in.
    (struct (Receiver T)
      ((ticket I64)
       (slot (UnsafeSlot T))))

    (define (make-mailbox) (→ (Mailbox T)) (∀ T)
      (Mailbox (unsafe-slot (empty-queue)) (unsafe-slot (empty-queue))))

    ;; Posting never waits, so a program may post before any task runs.
    ;; The receiver that has waited longest is handed the message and woken,
    ;; so a task that asks before that one runs cannot take it. A receiver
    ;; whose ticket wakes nothing, because its task trapped or its scheduler
    ;; closed while it waited, is dropped, and the message goes to the next.
    ;; With no receiver, the message joins the queue. A message handed to a
    ;; receiver is its: should the scheduler close before that task runs,
    ;; the message goes with it, as one it had received would.

    (define (mailbox-post (mailbox (Mailbox T)) (message T)) (→ Unit) (! mut) (∀ T)
      (let ((receivers (::receivers mailbox)))
        (match (dequeue (take! receivers))
          ((None)
           (put! receivers (empty-queue))
           (let ((messages (::messages mailbox)))
             (put! messages (enqueue (take! messages) message))))
          ((Some (Pair receiver rest))
           (put! receivers rest)
           (if (tasks-wake! (::ticket receiver))
               (put! (::slot receiver) message)
               (mailbox-post mailbox message))))))

    ;; Receiving takes the oldest message. With none, the swap has already
    ;; left the cell empty, and the task waits in line on a ticket until a
    ;; post hands it a message, so receivers are served in the order they
    ;; began to wait.

    (define (mailbox-receive (mailbox (Mailbox T))) (→ T) (! mut tasks) (∀ T)
      (let ((messages (::messages mailbox)))
        (match (dequeue (take! messages))
          ((Some (Pair message rest))
           (put! messages rest)
           message)
          ((None)
           (put! messages (empty-queue))
           (wait-in-line mailbox)))))

    ;; Receiving without waiting: the oldest message, or none.

    (define (mailbox-try-receive (mailbox (Mailbox T))) (→ (Option T)) (! mut) (∀ T)
      (let ((messages (::messages mailbox)))
        (match (dequeue (take! messages))
          ((Some (Pair message rest))
           (put! messages rest)
           (Some message))
          ((None)
           (put! messages (empty-queue))
           (None)))))

    ;; Only a post wakes the ticket, and it hands the message first, so the
    ;; slot is full when the receiver takes it; an empty one traps there.

    (define (wait-in-line (mailbox (Mailbox T))) (→ T) (! mut tasks) (∀ T)
      (let ((receivers (::receivers mailbox))
            (receiver (Receiver (ticket) (empty-slot))))
        (put! receivers (enqueue (take! receivers) receiver))
        (await (::ticket receiver))
        (take! (::slot receiver))))))
