;; Cooperative tasks run on a scheduler that the host creates, passes to
;; each turn or wake, and closes. A task runs until it finishes: nothing
;; cancels one, and tasks that want to stop each other arrange it between
;; themselves, as through a mailbox.
(define-library (snail shell task)
  (export
   tasks yield sleep await ticket current-scheduler
   Scheduler make-scheduler dispatch-in start-main
   dispatch-local dispatch-task through-host
   tasks-turn tasks-wake! tasks-close! tasks-running tasks-live
   Mailbox make-mailbox mailbox-post mailbox-receive mailbox-try-receive)
  (import
   (snail core base)
   (only (snail core forms) host Funcref)
   (only (snail core primitive) inherit-handlers unsafe-cast))
  (begin

    ;; ---- The effect ----

    ;; Every handler supplies its scheduler as well as its waiting protocol.
    (effect tasks
      ((ctl yield (Fn → Unit))
       (ctl sleep (Fn I64 → Unit))
       (ctl await (Fn I64 → Unit))
       (ticket (Fn → I64))
       (current-scheduler (Fn → Scheduler)))
      (around-main))

    ;; ---- Queues ----

    ;; Items join the back and leave the front.
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
       ((next (Fn → Step ! host))))
      (Sleeping
       ((delay I64)
        (next (Fn → Step ! host))))
      (Waiting
       ((ticket I64)
        (next (Fn → Step ! host)))))

    (type Run (Fn → Step ! host))

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

    ;; A stopped task belongs to exactly one queue. The counters bound each
    ;; turn to its initial ready work and let the host detect an idle or
    ;; completed scheduler.
    (record Scheduler
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
      (new Scheduler
        (ready (empty-queue))
        (timers (Nil))
        (waiters (Nil))
        (ready-count 0)
        (live 0)
        (running 0)
        (last-task 0)
        (now 0)
        (last-ticket 0)
        (closed #f)))

    (define (add-live! (scheduler Scheduler) (change I64)) (→ Unit) (! mut)
      (set! (● scheduler live) (+ (● scheduler live) change)))

    (define (push-ready! (scheduler Scheduler) (task Runnable)) (→ Unit) (! mut)
      (set! (● scheduler ready) (enqueue (● scheduler ready) task))
      (set! (● scheduler ready-count) (+ (● scheduler ready-count) 1)))

    ;; ---- Dispatching ----

    ;; The handler holds the scheduler, for the tickets it allocates.
    ;; Inherited handlers keep the dispatcher's other effects.
    (define (start-task (scheduler Scheduler) (work (Fn → Unit ! tasks e)))
      (→ Step) (! mut host e) (∀ (e))
      (handle tasks
          ((yield (lambda (resume)
                    (Yielded (inherit-handlers (lambda () (resume (unit)))))))
           (sleep (lambda (delay resume)
                    (Sleeping delay (inherit-handlers (lambda () (resume (unit)))))))
           (await (lambda (ticket resume)
                    (Waiting ticket (inherit-handlers (lambda () (resume (unit)))))))
           (ticket (lambda () (next-ticket! scheduler)))
           (current-scheduler (lambda () scheduler)))
        (work)
        (Finished)))

    (define (next-ticket! (scheduler Scheduler)) (→ I64) (! mut)
      (let ((ticket (+ (● scheduler last-ticket) 1)))
        (set! (● scheduler last-ticket) ticket)
        ticket))

    (define (dispatch-local (work (Fn → Unit ! tasks e)))
      (→ Unit) (! tasks mut host e) (∀ (e))
      (dispatch-task work)
      (unit))

    (define (dispatch-task (work (Fn → Unit ! tasks e)))
      (→ I64) (! tasks mut host e) (∀ (e))
      (dispatch-in (current-scheduler) work))

    (define (dispatch-in (scheduler Scheduler) (work (Fn → Unit ! tasks e)))
      (→ I64) (! mut host e) (∀ (e))
      (when (● scheduler closed)
        (panic "cannot dispatch to a closed scheduler"))
      (let ((id (+ (● scheduler last-task) 1)))
        (set! (● scheduler last-task) id)
        (add-live! scheduler 1)
        (push-ready! scheduler
                     (new Runnable
                       (id id)
                       (next (inherit-handlers (lambda () (start-task scheduler work))))))
        id))

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
            (set! (● scheduler timers) (wake-due! scheduler now (● scheduler timers)))
            (outlook scheduler now))))

    (define (run-ready! (scheduler Scheduler) (count I64)) (→ Unit) (! mut host)
      (when (> count 0)
        (match (dequeue (● scheduler ready))
          ((None) (unit))
          ((Some (Pair (Runnable id run) rest))
           (set! (● scheduler ready) rest)
           (set! (● scheduler ready-count) (- (● scheduler ready-count) 1))
           (add-live! scheduler -1)
           (set! (● scheduler running) id)
           (record! scheduler id (run))
           (set! (● scheduler running) 0)
           (run-ready! scheduler (- count 1))))))

    ;; A task that stops after its scheduler has closed is forgotten.
    (define (record! (scheduler Scheduler) (id I64) (step Step)) (→ Unit) (! mut)
      (unless (● scheduler closed)
        (match step
          ((Finished) (unit))
          ((Yielded next)
           (add-live! scheduler 1)
           (push-ready! scheduler (new Runnable (id id) (next next))))
          ((Sleeping delay next)
           (add-live! scheduler 1)
           (set! (● scheduler timers)
                 (insert-timer
                  (new Pending (key (+ (● scheduler now) delay)) (id id) (next next))
                  (● scheduler timers))))
          ((Waiting ticket next)
           (add-live! scheduler 1)
           (set! (● scheduler waiters)
                 (Cons (new Pending (key ticket) (id id) (next next))
                       (● scheduler waiters)))))))

    (define (insert-timer (timer Pending) (timers (List Pending))) (→ (List Pending))
      (match timers
        ((Nil) (Cons timer (Nil)))
        ((Cons first rest)
         (if (< (● timer key) (● first key))
             (Cons timer (Cons first rest))
             (Cons first (insert-timer timer rest))))))

    (define (wake-due! (scheduler Scheduler) (now I64) (timers (List Pending)))
      (→ (List Pending)) (! mut)
      (match timers
        ((Nil) (Nil))
        ((Cons first rest)
         (if (<= (● first key) now)
             (match first
               ((Pending _ id next)
                (push-ready! scheduler (new Runnable (id id) (next next)))
                (wake-due! scheduler now rest)))
             (Cons first rest)))))

    (define (outlook (scheduler Scheduler) (now I64)) (→ I64)
      (cond ((> (● scheduler ready-count) 0) 0)
            ((= (● scheduler live) 0) -1)
            (else
             (match (● scheduler timers)
               ((Nil) -2)
               ((Cons first _) (- (● first key) now))))))

    ;; ---- Waking and closing ----

    (define (tasks-wake! (scheduler Scheduler) (ticket I64)) (→ Bool) (! mut)
      (if (● scheduler closed) #f
          (match (without ticket (● scheduler waiters))
            ((Pair found rest)
             (set! (● scheduler waiters) rest)
             (match found
               ((Some task) (push-ready! scheduler task) #t)
               ((None) #f))))))

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

    ;; Closing is idempotent. It forgets every stopped task, which nothing
    ;; then finishes, and a late wake sees closed.
    (define (tasks-close! (scheduler Scheduler)) (→ Unit) (! mut)
      (set! (● scheduler closed) #t)
      (set! (● scheduler ready) (empty-queue))
      (set! (● scheduler timers) (Nil))
      (set! (● scheduler waiters) (Nil))
      (set! (● scheduler ready-count) 0)
      (set! (● scheduler live) 0))

    (define (tasks-running (scheduler Scheduler)) (→ I64)
      (● scheduler running))

    (define (tasks-live (scheduler Scheduler)) (→ I64)
      (● scheduler live))

    (define (start-main (scheduler Scheduler) (body Funcref)) (→ Unit) (! mut host)
      (dispatch-in scheduler
                   (lambda ()
                     ((ann (unsafe-cast body) (Fn → I32 ! tasks host)))
                     (unit)))
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

    ;; Each queued receiver has a delivery cell and names the scheduler on
    ;; which it awaits. Nothing suspends while a queue is updated or a
    ;; delivery is installed.
    (record (Mailbox T)
      ((messages (Queue T))
       (receivers (Queue (Receiver T)))))

    (record (Delivery T)
      ((message (Option T))))

    (record (Receiver T)
      ((scheduler Scheduler)
       (ticket I64)
       (delivery (Delivery T))))

    (define (make-mailbox) (→ (Mailbox T)) (∀ (T))
      (new Mailbox (messages (empty-queue)) (receivers (empty-queue))))

    (define (mailbox-post (mailbox (Mailbox T)) (message T))
      (→ Unit) (! mut) (∀ (T))
      (match (dequeue (● mailbox receivers))
        ((None) (set! (● mailbox messages) (enqueue (● mailbox messages) message)))
        ((Some (Pair receiver rest))
         (set! (● mailbox receivers) rest)
         (if (tasks-wake! (● receiver scheduler) (● receiver ticket))
             (set! (● receiver delivery message) (Some message))
             (mailbox-post mailbox message)))))

    ;; Waking above only queues work. The delivery is installed before the
    ;; sender can suspend, so the receiver never observes an empty delivery.
    ;; A stale receiver is removed and the message tries the next receiver.
    (define (mailbox-receive (mailbox (Mailbox T)))
      (→ T) (! mut tasks) (∀ (T))
      (match (mailbox-try-receive mailbox)
        ((Some message) message)
        ((None) (wait-in-line mailbox))))

    (define (mailbox-try-receive (mailbox (Mailbox T)))
      (→ (Option T)) (! mut) (∀ (T))
      (match (dequeue (● mailbox messages))
        ((None) (None))
        ((Some (Pair message rest))
         (set! (● mailbox messages) rest)
         (Some message))))

    (define (wait-in-line (mailbox (Mailbox T)))
      (→ T) (! mut tasks) (∀ (T))
      (let* ((delivery (new Delivery (message (None))))
             (id (ticket)))
        (set! (● mailbox receivers)
              (enqueue (● mailbox receivers)
                       (new Receiver
                         (scheduler (current-scheduler))
                         (ticket id)
                         (delivery delivery))))
        (await id)
        (match (● delivery message)
          ((Some message) message)
          ((None) (panic "a receiver woke without its message")))))))
