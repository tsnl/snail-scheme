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
      ((ctl yield (-> Unit))
       (ctl sleep (-> I64 Unit))
       (ctl await (-> I64 Unit))
       (ticket (-> I64)))
      (around-main))

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
    (: scheduler (Ref Scheduler))
    (define scheduler (ref (Scheduler 0 0 0 0 0 0)))

    ;; The queues of tasks rest in the runtime's slots. A queue is taken
    ;; out, changed and put back while no task runs, so a second taker,
    ;; such as a host callback reentering `wake`, traps in the slot.
    (: ready (UnsafeSlot (Queue Task)))
    (define ready (unsafe-slot (empty-queue)))

    (: timers (UnsafeSlot (List Pending)))
    (define timers (unsafe-slot (Nil)))

    (: waiters (UnsafeSlot (List Pending)))
    (define waiters (unsafe-slot (Nil)))

    (: take-ready! (-> (Queue Task) ! mut))
    (define (take-ready!)
      (take! ready))

    (: put-ready! (-> (Queue Task) Unit ! mut))
    (define (put-ready! queue)
      (put! ready queue))

    (: take-timers! (-> (List Pending) ! mut))
    (define (take-timers!)
      (take! timers))

    (: put-timers! (-> (List Pending) Unit ! mut))
    (define (put-timers! pending)
      (put! timers pending))

    (: take-waiters! (-> (List Pending) ! mut))
    (define (take-waiters!)
      (take! waiters))

    (: put-waiters! (-> (List Pending) Unit ! mut))
    (define (put-waiters! pending)
      (put! waiters pending))

    (: add-live! (-> I64 Unit ! mut))
    (define (add-live! change)
      (set! (::live (ref-get scheduler)) (+ (::live (ref-get scheduler)) change)))

    (: add-ready! (-> I64 Unit ! mut))
    (define (add-ready! change)
      (set! (::ready-count (ref-get scheduler)) (+ (::ready-count (ref-get scheduler)) change)))

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
      (let ((ticket (+ (::last-ticket (ref-get scheduler)) 1)))
        (set! (::last-ticket (ref-get scheduler)) ticket)
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
      (let ((id (+ (::last-task (ref-get scheduler)) 1)))
        (set! (::last-task (ref-get scheduler)) id)
        (add-live! 1)
        (push-ready! (Task id (inherit-handlers (once (lambda () (start-task work))))))
        id))

    ;; ---- Turns ----

    ;; One turn runs the tasks that were ready when it began, so tasks that
    ;; yield to each other cannot keep the host from its events, then
    ;; readies the sleepers whose deadline has passed. It answers 0 when a
    ;; task is ready, -1 when no task is live, -2 when every task waits on a
    ;; ticket, and otherwise the milliseconds until the earliest deadline.
    (: tasks-turn (-> I64 I64 ! mut host))
    (define (tasks-turn now)
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
    (: run-ready! (-> I64 Unit ! mut host))
    (define (run-ready! count)
      (when (> count 0)
        (match (dequeue (take-ready!))
          ((None) (put-ready! (empty-queue)))
          ((Some (Pair (Task id run) rest))
           (put-ready! rest)
           (add-ready! -1)
           (add-live! -1)
           (set! (::running (ref-get scheduler)) id)
           (record! id (run))
           (set! (::running (ref-get scheduler)) 0)
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
          (insert-timer (Pending (+ (::now (ref-get scheduler)) delay) id next) (take-timers!))))
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
       ((> (::ready-count (ref-get scheduler)) 0) 0)
       ((= (::live (ref-get scheduler)) 0) -1)
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
    (: tasks-wake! (-> I64 Bool ! mut))
    (define (tasks-wake! ticket)
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
    ;; the tasks of the program it replaces. A task is its rest, a FnOnce;
    ;; dropping one unrun drops the linear values its frames hold, which
    ;; performs what their drops perform, within the task's row, `host`.
    (: tasks-close! (-> Unit ! mut host))
    (define (tasks-close!)
      (drop (take-ready!))
      (put-ready! (empty-queue))
      (drop (take-timers!))
      (put-timers! (Nil))
      (drop (take-waiters!))
      (put-waiters! (Nil))
      (set! (::ready-count (ref-get scheduler)) 0)
      (set! (::live (ref-get scheduler)) 0))

    (: tasks-running (-> I64 ! mut))
    (define (tasks-running)
      (::running (ref-get scheduler)))

    (: tasks-live (-> I64 ! mut))
    (define (tasks-live)
      (::live (ref-get scheduler)))

    ;; The program's body, its `main:body` export, which takes the evidence
    ;; and answers its status, run as the first task: the host, or the
    ;; engine, calls this in place of the body, once the program's
    ;; definitions are initialized, so the statements run under this
    ;; scheduler's handler of `tasks` and may yield.
    (: start-main (-> Funcref Unit ! mut host))
    (define (start-main body)
      (dispatch-local (once (lambda ()
                              ((ann (unsafe-cast body) (-> I32 ! tasks host)))
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

    (: make-mailbox (All (T) (-> (Mailbox T))))
    (define (make-mailbox)
      (Mailbox (unsafe-slot (empty-queue)) (unsafe-slot (empty-queue))))

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
        (match (dequeue (take! receivers))
          ((None)
           (put! receivers (empty-queue))
           (let ((messages (Mailbox-messages mailbox)))
             (put! messages (enqueue (take! messages) message))))
          ((Some (Pair receiver rest))
           (put! receivers rest)
           (if (tasks-wake! (Receiver-ticket receiver))
               (put! (Receiver-slot receiver) message)
               (mailbox-post mailbox message))))))

    ;; Receiving takes the oldest message. With none, the swap has already
    ;; left the cell empty, and the task waits in line on a ticket until a
    ;; post hands it a message, so receivers are served in the order they
    ;; began to wait.
    (: mailbox-receive (All (T) (-> (Mailbox T) T ! mut tasks)))
    (define (mailbox-receive mailbox)
      (let ((messages (Mailbox-messages mailbox)))
        (match (dequeue (take! messages))
          ((Some (Pair message rest))
           (put! messages rest)
           message)
          ((None)
           (put! messages (empty-queue))
           (wait-in-line mailbox)))))

    ;; Receiving without waiting: the oldest message, or none.
    (: mailbox-try-receive (All (T) (-> (Mailbox T) (Option T) ! mut)))
    (define (mailbox-try-receive mailbox)
      (let ((messages (Mailbox-messages mailbox)))
        (match (dequeue (take! messages))
          ((Some (Pair message rest))
           (put! messages rest)
           (Some message))
          ((None)
           (put! messages (empty-queue))
           (None)))))

    ;; Only a post wakes the ticket, and it hands the message first, so the
    ;; slot is full when the receiver takes it; an empty one traps there.
    (: wait-in-line (All (T) (-> (Mailbox T) T ! mut tasks)))
    (define (wait-in-line mailbox)
      (let ((receivers (Mailbox-receivers mailbox))
            (receiver (Receiver (ticket) (empty-slot))))
        (put! receivers (enqueue (take! receivers) receiver))
        (await (Receiver-ticket receiver))
        (take! (Receiver-slot receiver))))))
