;; Cooperative tasks run on a scheduler that the host creates, passes to
;; each turn or wake, and closes. A task runs until it finishes: nothing
;; cancels one, and tasks that want to stop each other arrange it between
;; themselves, as through a mailbox.
(define-library (snail shell task)
  (export
   tasks yield sleep await ticket current-scheduler
   Scheduler make-scheduler dispatch-in start-main
   dispatch through-host
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

    ;; A mailbox's messages join the back and leave the front.
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
       (task Runnable)))

    ;; ---- The scheduler ----

    ;; A stopped task is in exactly one list: the ready tasks, newest first;
    ;; the timers, by deadline; or the waiters. The running task is in
    ;; none. Tickets and task ids count from 1 in each scheduler, and the
    ;; host addresses every wake to its own scheduler.
    (record Scheduler
      ((ready (List Runnable))
       (timers (List Pending))
       (waiters (List Pending))
       (running I64)
       (last-task I64)
       (last-ticket I64)
       (closed Bool)))

    (define (make-scheduler) (→ Scheduler)
      (new Scheduler
        (ready (Nil))
        (timers (Nil))
        (waiters (Nil))
        (running 0)
        (last-task 0)
        (last-ticket 0)
        (closed #f)))

    (define (push-ready! (scheduler Scheduler) (task Runnable)) (→ Unit) (! mut)
      (set! (● scheduler ready) (Cons task (● scheduler ready))))

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

    (define (dispatch (work (Fn → Unit ! tasks e)))
      (→ Unit) (! tasks mut host e) (∀ (e))
      (dispatch-in (current-scheduler) work)
      (unit))

    (define (dispatch-in (scheduler Scheduler) (work (Fn → Unit ! tasks e)))
      (→ I64) (! mut host e) (∀ (e))
      (when (● scheduler closed)
        (panic "cannot dispatch to a closed scheduler"))
      (let ((id (+ (● scheduler last-task) 1)))
        (set! (● scheduler last-task) id)
        (push-ready! scheduler
                     (new Runnable
                       (id id)
                       (next (inherit-handlers (lambda () (start-task scheduler work))))))
        id))

    ;; ---- Turns ----

    ;; 0 means ready work, -1 completed, -2 waiting only on tickets, and a
    ;; positive answer is the delay until the earliest timer. A turn takes
    ;; the ready list whole, so a task readied during the turn, by yielding
    ;; or by a wake, runs in the next one, and tasks that yield to each
    ;; other cannot keep the host from its events. Waking merely queues a
    ;; task: it never invokes one synchronously.
    (define (tasks-turn (scheduler Scheduler) (now I64)) (→ I64) (! mut host)
      (if (● scheduler closed) -1
          (let ((batch (reverse (● scheduler ready))))
            (set! (● scheduler ready) (Nil))
            (run-batch! scheduler now batch)
            (set! (● scheduler timers) (wake-due! scheduler now (● scheduler timers)))
            (outlook scheduler now))))

    ;; Once the scheduler closes, the rest of the batch is forgotten.
    (define (run-batch! (scheduler Scheduler) (now I64) (batch (List Runnable)))
      (→ Unit) (! mut host)
      (match batch
        ((Nil) (unit))
        ((Cons (Runnable id run) rest)
         (unless (● scheduler closed)
           (set! (● scheduler running) id)
           (record! scheduler now id (run))
           (set! (● scheduler running) 0)
           (run-batch! scheduler now rest)))))

    ;; A task that stops after its scheduler has closed is forgotten. A
    ;; sleeper's deadline counts from the turn it slept in.
    (define (record! (scheduler Scheduler) (now I64) (id I64) (step Step)) (→ Unit) (! mut)
      (unless (● scheduler closed)
        (match step
          ((Finished) (unit))
          ((Yielded next) (push-ready! scheduler (new Runnable (id id) (next next))))
          ((Sleeping delay next)
           (set! (● scheduler timers)
                 (insert-timer
                  (new Pending (key (+ now delay)) (task (new Runnable (id id) (next next))))
                  (● scheduler timers))))
          ((Waiting ticket next)
           (set! (● scheduler waiters)
                 (Cons (new Pending (key ticket) (task (new Runnable (id id) (next next))))
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
             (begin
               (push-ready! scheduler (● first task))
               (wake-due! scheduler now rest))
             (Cons first rest)))))

    (define (outlook (scheduler Scheduler) (now I64)) (→ I64)
      (match (● scheduler ready)
        ((Cons _ _) 0)
        ((Nil)
         (match (● scheduler timers)
           ((Cons first _) (- (● first key) now))
           ((Nil) (if (null? (● scheduler waiters)) -1 -2))))))

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
             (new Pair (first (Some (● first task))) (second rest))
             (match (without ticket rest)
               ((Pair found others) (new Pair (first found) (second (Cons first others)))))))))

    ;; Closing is idempotent. It forgets every stopped task, which nothing
    ;; then finishes, and a late wake sees closed.
    (define (tasks-close! (scheduler Scheduler)) (→ Unit) (! mut)
      (set! (● scheduler closed) #t)
      (set! (● scheduler ready) (Nil))
      (set! (● scheduler timers) (Nil))
      (set! (● scheduler waiters) (Nil)))

    (define (tasks-running (scheduler Scheduler)) (→ I64)
      (● scheduler running))

    ;; The stopped tasks, which a closed scheduler has none of.
    (define (tasks-live (scheduler Scheduler)) (→ I64)
      (+ (length (● scheduler ready))
         (+ (length (● scheduler timers)) (length (● scheduler waiters)))))

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

    ;; A mailbox queues messages and keeps the wakers of the tasks waiting
    ;; for one, newest first. A post wakes every waiting task, and each
    ;; takes a message for itself when it runs; one that finds none waits
    ;; again. A message is never handed to a task that may not run, as on a
    ;; closed scheduler, so none is lost. The price is fairness: a task
    ;; that asks before a woken one runs takes the message first.

    ;; A waker only queues its task, so any code may call it at any time:
    ;; another task, a sender, or code between turns. A call after its task
    ;; was woken, or once its scheduler has closed, wakes nothing.
    (type Waker (Fn → Unit ! mut))

    (record (Mailbox T)
      ((messages (Queue T))
       (receivers (List Waker))))

    (define (make-mailbox) (→ (Mailbox T)) (∀ (T))
      (new Mailbox (messages (empty-queue)) (receivers (Nil))))

    (define (mailbox-post (mailbox (Mailbox T)) (message T))
      (→ Unit) (! mut) (∀ (T))
      (let ((receivers (reverse (● mailbox receivers))))
        (set! (● mailbox messages) (enqueue (● mailbox messages) message))
        (set! (● mailbox receivers) (Nil))
        (for-each (lambda (wake) (wake)) receivers)))

    ;; Taking a ticket does not suspend, so no post comes between finding
    ;; the queue empty and waiting.
    (define (mailbox-receive (mailbox (Mailbox T)))
      (→ T) (! mut tasks) (∀ (T))
      (match (mailbox-try-receive mailbox)
        ((Some message) message)
        ((None)
         (let ((id (ticket)) (scheduler (current-scheduler)))
           (set! (● mailbox receivers)
                 (Cons (lambda () (tasks-wake! scheduler id) (unit)) (● mailbox receivers)))
           (await id))
         (mailbox-receive mailbox))))

    (define (mailbox-try-receive (mailbox (Mailbox T)))
      (→ (Option T)) (! mut) (∀ (T))
      (match (dequeue (● mailbox messages))
        ((None) (None))
        ((Some (Pair message rest))
         (set! (● mailbox messages) rest)
         (Some message))))))
