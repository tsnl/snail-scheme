;; Cooperative tasks have an explicit scheduler owner. The host creates it,
;; passes it to each turn or wake, closes it, then releases its returned
;; ownership credit. Saved tasks hold only a weak link back to the scheduler.
(define-library (snail shell task)
  (export
   tasks yield sleep await ticket current-scheduler
   Scheduler WeakScheduler make-scheduler dispatch-in start-main
   dispatch-local dispatch-task through-host wake-task!
   tasks-turn tasks-wake! tasks-close! tasks-running tasks-live
   Mailbox make-mailbox mailbox-post mailbox-receive mailbox-try-receive)
  (import
   (snail core base)
   (only (snail core forms) host Funcref)
   (only (snail core primitive) inherit-handlers unsafe-cast))
  (begin

    ;; ---- The effect ----

    ;; Every handler supplies its scheduler context as well as its waiting
    ;; protocol. The weak context never owns queued work or saved handlers.
    (effect tasks
      ((ctl yield (Fn → Unit))
       (ctl sleep (Fn I64 → Unit))
       (ctl await (Fn I64 → Unit))
       (ticket (Fn → I64))
       (current-scheduler (Fn → WeakScheduler)))
      (around-main))

    ;; ---- Queues ----

    ;; Destructuring transfers each item exactly once, including linear work.
    (record (Queue T)
      ((front (List T))
       (back (List T))))

    (define (empty-queue) (→ (Queue T)) (∀ (T))
      (new Queue (front (Nil)) (back (Nil))))

    (define (enqueue (queue (Queue T)) (item T)) (→ (Queue T)) (∀ (T))
      (match queue
        ((Queue front back) (new Queue (front front) (back (Cons item back))))))

    (define (dequeue (queue (Queue T))) (→ (Option (Pair T (Queue T)))) (∀ (T))
      (match queue
        ((Queue (Cons item rest) back)
         (Some (new Pair (first item) (second (new Queue (front rest) (back back))))))
        ((Queue (Nil) (Nil)) (None))
        ((Queue (Nil) back) (dequeue (new Queue (front (reverse back)) (back (Nil)))))))

    ;; ---- Steps ----

    (enum Step
      (Finished)
      (Yielded
       ((next (FnOnce → Step ! host))))
      (Sleeping
       ((delay I64)
        (next (FnOnce → Step ! host))))
      (Waiting
       ((ticket I64)
        (next (FnOnce → Step ! host)))))

    (type Run (FnOnce → Step ! host))

    ;; A task that is ready, under its id.
    (record Runnable
      ((id I64)
       (next Run)))

    ;; A task waiting to be woken, by its deadline among the timers or by
    ;; its ticket among the waiters.
    (record Pending
      ((key I64)
       (id I64)
       (next Run)))

    ;; ---- The scheduler ----

    (type Scheduler (Rc SchedulerState))
    (type WeakScheduler (WeakRc SchedulerState))

    ;; A stopped task belongs to exactly one queue. Replace a queue with an
    ;; empty one before processing it; no task or callback runs while moved
    ;; work is being installed. The counters bound each turn to its initial
    ;; ready work and let the host detect an idle or completed scheduler.
    (record SchedulerState
      ((ready (Queue Runnable))
       (timers (List Pending))
       (waiters (List Pending))
       (ready-count I64)
       (live I64)
       (running I64)
       (last-task I64)
       (now I64)
       (last-ticket I64)
       (closed Bool)))

    (define (make-scheduler) (→ Scheduler)
      (rc (new SchedulerState
            (ready (empty-queue))
            (timers (Nil))
            (waiters (Nil))
            (ready-count 0)
            (live 0)
            (running 0)
            (last-task 0)
            (now 0)
            (last-ticket 0)
            (closed #f))))

    (define (take-ready! (scheduler Scheduler)) (→ (Queue Runnable)) (! mut host)
      (replace! (● scheduler ready) (empty-queue)))

    (define (put-ready! (scheduler Scheduler) (queue (Queue Runnable))) (→ Unit) (! mut host)
      (drop (replace! (● scheduler ready) queue)))

    (define (take-timers! (scheduler Scheduler)) (→ (List Pending)) (! mut host)
      (replace! (● scheduler timers) (Nil)))

    (define (put-timers! (scheduler Scheduler) (pending (List Pending))) (→ Unit) (! mut host)
      (drop (replace! (● scheduler timers) pending)))

    (define (take-waiters! (scheduler Scheduler)) (→ (List Pending)) (! mut host)
      (replace! (● scheduler waiters) (Nil)))

    (define (put-waiters! (scheduler Scheduler) (pending (List Pending))) (→ Unit) (! mut host)
      (drop (replace! (● scheduler waiters) pending)))

    (define (add-live! (scheduler Scheduler) (change I64)) (→ Unit) (! mut host)
      (set! (● scheduler live) (+ (● scheduler live) change)))

    (define (push-ready! (scheduler Scheduler) (task Runnable)) (→ Unit) (! mut host)
      (put-ready! scheduler (enqueue (take-ready! scheduler) task))
      (set! (● scheduler ready-count) (+ (● scheduler ready-count) 1)))

    ;; ---- Dispatching ----

    ;; The handler captures a weak reference. Capturing its owner would make
    ;; a cycle: scheduler -> saved task -> handler -> scheduler. Each ordinary
    ;; operation upgrades only while it changes the scheduler, never across
    ;; a suspension. Inherited handlers keep the dispatcher's other effects.
    (define (start-task (scheduler WeakScheduler) (work (FnOnce → Unit ! tasks e)))
      (→ Step) (! mut host e) (∀ (e))
      (handle tasks
          ((yield (lambda (resume)
                    (Yielded (inherit-handlers (once (lambda () (resume (unit))))))))
           (sleep (lambda (delay resume)
                    (Sleeping delay (inherit-handlers (once (lambda () (resume (unit))))))))
           (await (lambda (ticket resume)
                    (Waiting ticket (inherit-handlers (once (lambda () (resume (unit))))))))
           (ticket (lambda () (next-ticket! (scheduler-owner scheduler))))
           (current-scheduler (lambda () scheduler)))
        (work)
        (Finished)))

    (define (scheduler-owner (scheduler WeakScheduler)) (→ Scheduler) (! mut host)
      (match (weak-rc-upgrade scheduler)
        ((Some owner) owner)
        ((None) (panic "the task's scheduler has closed"))))

    (define (next-ticket! (scheduler Scheduler)) (→ I64) (! mut host)
      (let ((ticket (+ (● scheduler last-ticket) 1)))
        (set! (● scheduler last-ticket) ticket)
        ticket))

    (define (dispatch-local (work (FnOnce → Unit ! tasks e)))
      (→ Unit) (! tasks mut host e) (∀ (e))
      (dispatch-task work)
      (unit))

    (define (dispatch-task (work (FnOnce → Unit ! tasks e)))
      (→ I64) (! tasks mut host e) (∀ (e))
      (dispatch-in (scheduler-owner (current-scheduler)) work))

    ;; Startup already owns the scheduler. Downgrade it before constructing
    ;; the saved closure, so its environment cannot retain the strong owner.
    (define (dispatch-in (scheduler Scheduler) (work (FnOnce → Unit ! tasks e)))
      (→ I64) (! mut host e) (∀ (e))
      (if (● scheduler closed)
          (begin (drop work) (panic "cannot dispatch to a closed scheduler"))
          (let ((id (+ (● scheduler last-task) 1)) (weak (rc-downgrade scheduler)))
            (set! (● scheduler last-task) id)
            (add-live! scheduler 1)
            (push-ready! scheduler
                         (new Runnable
                           (id id)
                           (next (inherit-handlers (once (lambda () (start-task weak work)))))))
            id)))

    ;; ---- Turns ----

    ;; 0 means ready work, -1 completed, -2 waiting only on tickets, and a
    ;; positive answer is the delay until the earliest timer. Waking merely
    ;; queues a task: it never invokes one synchronously.
    (define (tasks-turn (scheduler Scheduler) (now I64)) (→ I64) (! mut host)
      (if (● scheduler closed) -1
          (begin
            (when (= (● scheduler last-ticket) 0)
              (set! (● scheduler last-ticket) (* now 1000)))
            (set! (● scheduler now) now)
            (run-ready! scheduler (● scheduler ready-count))
            (put-timers! scheduler (wake-due! scheduler now (take-timers! scheduler)))
            (outlook scheduler now))))

    (define (run-ready! (scheduler Scheduler) (count I64)) (→ Unit) (! mut host)
      (when (> count 0)
        (match (dequeue (take-ready! scheduler))
          ((None) (unit))
          ((Some (Pair (Runnable id run) rest))
           (put-ready! scheduler rest)
           (set! (● scheduler ready-count) (- (● scheduler ready-count) 1))
           (add-live! scheduler -1)
           (set! (● scheduler running) id)
           (record! scheduler id (run))
           (set! (● scheduler running) 0)
           (run-ready! scheduler (- count 1))))))

    (define (record! (scheduler Scheduler) (id I64) (step Step)) (→ Unit) (! mut host)
      (if (● scheduler closed) (drop step)
          (match step
            ((Finished) (unit))
            ((Yielded next)
             (add-live! scheduler 1)
             (push-ready! scheduler (new Runnable (id id) (next next))))
            ((Sleeping delay next)
             (add-live! scheduler 1)
             (put-timers! scheduler
                          (insert-timer
                           (new Pending (key (+ (● scheduler now) delay)) (id id) (next next))
                           (take-timers! scheduler))))
            ((Waiting ticket next)
             (add-live! scheduler 1)
             (put-waiters! scheduler
                           (Cons (new Pending (key ticket) (id id) (next next))
                                 (take-waiters! scheduler)))))))

    (define (insert-timer (timer Pending) (timers (List Pending))) (→ (List Pending))
      (match timers
        ((Nil) (Cons timer (Nil)))
        ((Cons first rest)
         (if (< (● timer key) (● first key))
             (Cons timer (Cons first rest))
             (Cons first (insert-timer timer rest))))))

    (define (wake-due! (scheduler Scheduler) (now I64) (timers (List Pending)))
      (→ (List Pending)) (! mut host)
      (match timers
        ((Nil) (Nil))
        ((Cons first rest)
         (if (<= (● first key) now)
             (match first
               ((Pending _ id next)
                (push-ready! scheduler (new Runnable (id id) (next next)))
                (wake-due! scheduler now rest)))
             (Cons first rest)))))

    (define (outlook (scheduler Scheduler) (now I64)) (→ I64) (! mut host)
      (cond ((> (● scheduler ready-count) 0) 0)
            ((= (● scheduler live) 0) -1)
            (else
             (match (take-timers! scheduler)
               ((Nil) -2)
               ((Cons first rest)
                (let ((deadline (● first key)))
                  (put-timers! scheduler (Cons first rest))
                  (- deadline now)))))))

    ;; ---- Waking and closing ----

    (define (tasks-wake! (scheduler Scheduler) (ticket I64)) (→ Bool) (! mut host)
      (if (● scheduler closed) #f
          (match (without ticket (take-waiters! scheduler))
            ((Pair found rest)
             (put-waiters! scheduler rest)
             (match found
               ((Some task) (push-ready! scheduler task) #t)
               ((None) #f))))))

    (define (wake-task! (scheduler WeakScheduler) (ticket I64)) (→ Bool) (! mut host)
      (match (weak-rc-upgrade scheduler)
        ((Some owner) (tasks-wake! owner ticket))
        ((None) #f)))

    (define (without (ticket I64) (waiters (List Pending)))
      (→ (Pair (Option Runnable) (List Pending)))
      (match waiters
        ((Nil) (new Pair (first (None)) (second (Nil))))
        ((Cons first rest)
         (if (= (● first key) ticket)
             (match first
               ((Pending _ id next)
                (new Pair (first (Some (new Runnable (id id) (next next)))) (second rest))))
             (match (without ticket rest)
               ((Pair found others) (new Pair (first found) (second (Cons first others)))))))))

    ;; Closing is idempotent. Publish closed and detach every queue before
    ;; disposal can call a waker or user cleanup. A late wake sees closed;
    ;; cleanup cannot add work. The host releases its owner only afterwards.
    (define (tasks-close! (scheduler Scheduler)) (→ Unit) (! mut host)
      (set! (● scheduler closed) #t)
      (let ((queued (take-ready! scheduler))
            (sleeping (take-timers! scheduler))
            (waiting (take-waiters! scheduler)))
        (set! (● scheduler ready-count) 0)
        (set! (● scheduler live) 0)
        (drop queued)
        (drop sleeping)
        (drop waiting)))

    (define (tasks-running (scheduler Scheduler)) (→ I64) (! mut host)
      (● scheduler running))

    (define (tasks-live (scheduler Scheduler)) (→ I64) (! mut host)
      (● scheduler live))

    (define (start-main (scheduler Scheduler) (body Funcref)) (→ Unit) (! mut host)
      (dispatch-in scheduler
                   (once (lambda ()
                           ((ann (unsafe-cast body) (Fn → I32 ! tasks host)))
                           (unit))))
      (unit))

    (expose make-scheduler "tasks:create")
    (expose start-main "tasks:start-main")
    (expose tasks-turn "tasks:turn")
    (expose tasks-wake! "tasks:wake")
    (expose tasks-close! "tasks:close")
    (expose tasks-running "tasks:running")
    (expose tasks-live "tasks:live")

    ;; ---- Waiting on the host ----

    ;; No suspension occurs between allocating a ticket and starting its
    ;; operation. Completion is delivered between turns, after await parks.
    (define (through-host (start (Fn I64 → Unit)) (finish (Fn I64 → A)))
      (→ A)
      (! tasks)
      (∀ (A))
      (let ((id (ticket)))
        (start id)
        (await id)
        (finish id)))

    ;; ---- Mailboxes ----

    ;; Only Rc may share linear messages. Each queued receiver owns a
    ;; delivery cell and identifies the scheduler on which it awaits. There
    ;; is no suspension while moving a queue or installing a delivery.
    (type (Mailbox T) (Rc (MailboxState T)))
    (record (MailboxState T)
      ((messages (Queue T))
       (receivers (Queue (Receiver T)))))

    (record (Delivery T)
      ((message (Option T))))

    (record (Receiver T)
      ((scheduler WeakScheduler)
       (ticket I64)
       (delivery (Rc (Delivery T)))))

    (define (make-mailbox) (→ (Mailbox T)) (∀ (T d)) (⊨ (Drop d T))
      (rc (new MailboxState (messages (empty-queue)) (receivers (empty-queue)))))

    (define (mailbox-post (mailbox (Mailbox T)) (message T))
      (→ Unit) (! mut host d) (∀ (T d)) (⊨ (Drop d T))
      (match (dequeue (replace! (● mailbox receivers) (empty-queue)))
        ((None)
         (drop (replace! (● mailbox messages)
                         (enqueue (replace! (● mailbox messages) (empty-queue)) message))))
        ((Some (Pair receiver rest))
         (drop (replace! (● mailbox receivers) rest))
         (if (wake-task! (● receiver scheduler) (● receiver ticket))
             (drop (replace! (● (● receiver delivery) message) (Some message)))
             (mailbox-post mailbox message)))))

    ;; Waking above only queues work. The delivery is installed before the
    ;; sender can suspend, so the receiver never observes an empty delivery.
    ;; A stale receiver is removed and the message tries the next receiver.
    (define (mailbox-receive (mailbox (Mailbox T)))
      (→ T) (! mut tasks d) (∀ (T d)) (⊨ (Drop d T))
      (match (mailbox-try-receive mailbox)
        ((Some message) message)
        ((None) (wait-in-line mailbox))))

    (define (mailbox-try-receive (mailbox (Mailbox T)))
      (→ (Option T)) (! mut d) (∀ (T d)) (⊨ (Drop d T))
      (match (dequeue (replace! (● mailbox messages) (empty-queue)))
        ((None) (None))
        ((Some (Pair message rest))
         (drop (replace! (● mailbox messages) rest))
         (Some message))))

    (define (wait-in-line (mailbox (Mailbox T)))
      (→ T) (! mut tasks d) (∀ (T d)) (⊨ (Drop d T))
      (let* ((delivery (rc (new Delivery (message (None)))))
             (id (ticket))
             (receiver
              (new Receiver (scheduler (current-scheduler)) (ticket id) (delivery delivery))))
        (drop (replace! (● mailbox receivers)
                        (enqueue (replace! (● mailbox receivers) (empty-queue)) receiver)))
        (await id)
        (match (replace! (● delivery message) (None))
          ((Some message) message)
          ((None) (panic "a receiver woke without its message")))))))
