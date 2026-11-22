;; Cooperative tasks run on a scheduler that the host creates, passes to
;; each turn or wake, and closes. A task runs until it finishes: nothing
;; cancels one, and tasks that want to stop each other arrange it between
;; themselves, as through a mailbox.
;;
;; A task waits by suspending: `yield`, `sleep` and `await` stop it where
;; it is, however deep in its calls, and its scheduler keeps the rest of
;; it to run later. No function between the wait and the task's start says
;; so in its type, and none takes anything for it.
(define-library (snail shell task)
  (export
   yield sleep await ticket current-scheduler
   Scheduler make-scheduler dispatch-in
   dispatch through-host
   tasks-turn tasks-wake! tasks-close! tasks-running tasks-live
   Mailbox make-mailbox mailbox-post mailbox-receive mailbox-try-receive)
  (import
   (snail core base))
  (begin

    ;; ---- Waiting ----

    ;; What a task tells its scheduler when it stops to wait: for its next
    ;; turn, for a delay, or for the host's answers to tickets.
    (enum Wait
      (Yield)
      (Sleep ((delay I64)))
      (Await ((tickets (List I64)))))

    ;; The prompt every task runs under. A wait suspends to it, and the
    ;; scheduler resumes the task with nothing but the news that the wait
    ;; is over.
    (define waiting (→ (Prompt Wait Unit)) (make-prompt))

    (define (yield) (→ Unit)
      (suspend waiting (Yield)))

    (define (sleep (delay I64)) (→ Unit)
      (suspend waiting (Sleep delay)))

    (define (await (tickets (List I64))) (→ Unit)
      (suspend waiting (Await tickets)))

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
       ((next (Fn → Step ! mut))))
      (Sleeping
       ((delay I64)
        (next (Fn → Step ! mut))))
      (Waiting
       ((tickets (List I64))
        (next (Fn → Step ! mut)))))

    (type Run (Fn → Step ! mut))

    ;; A task that is ready, under its id.
    (record Runnable
      ((id I64)
       (next Run)))

    ;; A sleeping task, by its deadline.
    (record Pending
      ((key I64)
       (task Runnable)))

    ;; A task awaiting tickets, with those it still waits for.
    (record Waiter
      ((tickets (List I64))
       (task Runnable)))

    ;; ---- The scheduler ----

    ;; A stopped task is in exactly one list: the ready tasks, newest first;
    ;; the timers, by deadline; or the waiters. The running task is in
    ;; none. Tickets and task ids count from 1 in each scheduler, and the
    ;; host addresses every wake to its own scheduler.
    (record Scheduler
      ((ready (List Runnable))
       (timers (List Pending))
       (waiters (List Waiter))
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

    ;; ---- The running scheduler ----

    ;; The scheduler whose task is running, which a turn sets around each
    ;; step it runs. A task asks it for tickets and dispatches to it, so
    ;; no task is handed its scheduler.
    (record Running
      ((scheduler (Option Scheduler))))

    (define running (→ Running) (new Running (scheduler (None))))

    (define (current-scheduler) (→ Scheduler)
      (match (● running scheduler)
        ((Some scheduler) scheduler)
        ((None) (panic "no task is running"))))

    (define (ticket) (→ I64) (! mut)
      (let* ((scheduler (current-scheduler)) (ticket (+ (● scheduler last-ticket) 1)))
        (set! (● scheduler last-ticket) ticket)
        ticket))

    ;; A step, with `scheduler` the running one while it runs.
    (define (stepped (scheduler Scheduler) (run Run)) (→ Step) (! mut)
      (let ((outer (● running scheduler)))
        (set! (● running scheduler) (Some scheduler))
        (let ((step (run)))
          (set! (● running scheduler) outer)
          step)))

    ;; ---- Dispatching ----

    ;; A task from its start to its first wait, or to its end. A wait hands
    ;; over the rest of the task as the step that runs it to its next: the
    ;; `with-prompt` is around the task again whenever that step runs.
    (define (start-task (work (Fn → Unit ! mut))) (→ Step) (! mut)
      (with-prompt waiting
                   (lambda ()
                     (work)
                     (Finished))
                   (lambda (wait resume) (waited wait (lambda () (resume (unit)))))))

    (define (waited (wait Wait) (next Run)) (→ Step)
      (match wait
        ((Yield) (Yielded next))
        ((Sleep delay) (Sleeping delay next))
        ((Await tickets) (Waiting tickets next))))

    (define (dispatch (work (Fn → Unit ! mut))) (→ Unit) (! mut)
      (dispatch-in (current-scheduler) work)
      (unit))

    (define (dispatch-in (scheduler Scheduler) (work (Fn → Unit ! mut))) (→ I64) (! mut)
      (when (● scheduler closed)
        (panic "cannot dispatch to a closed scheduler"))
      (let ((id (+ (● scheduler last-task) 1)))
        (set! (● scheduler last-task) id)
        (push-ready! scheduler (new Runnable (id id) (next (lambda () (start-task work)))))
        id))

    ;; ---- Turns ----

    ;; 0 means ready work, -1 completed, -2 waiting only on tickets, and a
    ;; positive answer is the delay until the earliest timer. A turn takes
    ;; the ready list whole, so a task readied during the turn, by yielding
    ;; or by a wake, runs in the next one, and tasks that yield to each
    ;; other cannot keep the host from its events. Waking merely queues a
    ;; task: it never invokes one synchronously.
    (define (tasks-turn (scheduler Scheduler) (now I64)) (→ I64) (! mut)
      (if (● scheduler closed) -1
          (let ((batch (reverse (● scheduler ready))))
            (set! (● scheduler ready) (Nil))
            (run-batch! scheduler now batch)
            (set! (● scheduler timers) (wake-due! scheduler now (● scheduler timers)))
            (outlook scheduler now))))

    ;; Once the scheduler closes, the rest of the batch is forgotten.
    (define (run-batch! (scheduler Scheduler) (now I64) (batch (List Runnable)))
      (→ Unit) (! mut)
      (match batch
        ((Nil) (unit))
        ((Cons (Runnable id run) rest)
         (unless (● scheduler closed)
           (set! (● scheduler running) id)
           (record! scheduler now id (stepped scheduler run))
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
          ((Waiting tickets next)
           (let ((task (new Runnable (id id) (next next))))
             (if (null? tickets)
                 (push-ready! scheduler task)
                 (set! (● scheduler waiters)
                       (Cons (new Waiter (tickets tickets) (task task))
                             (● scheduler waiters)))))))))

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

    ;; A completion crosses its ticket off the waiter holding it, and a
    ;; waiter with none left is ready. A ticket no waiter holds, one woken
    ;; already or after a close, wakes nothing.
    (define (tasks-wake! (scheduler Scheduler) (ticket I64)) (→ Bool) (! mut)
      (if (● scheduler closed) #f
          (match (holding ticket (● scheduler waiters))
            ((Pair (Some waiter) others)
             (let ((left (filter (lambda (held) (not (= held ticket))) (● waiter tickets))))
               (if (null? left)
                   (begin
                     (set! (● scheduler waiters) others)
                     (push-ready! scheduler (● waiter task)))
                   (set! (● scheduler waiters) (Cons (Waiter-tickets-set waiter left) others))))
             #t)
            ((Pair (None) _) #f))))

    ;; The waiter holding `ticket`, and the others.
    (define (holding (ticket I64) (waiters (List Waiter)))
      (→ (Pair (Option Waiter) (List Waiter)))
      (match waiters
        ((Nil) (new Pair (first (None)) (second (Nil))))
        ((Cons first rest)
         (if (member? ticket (● first tickets))
             (new Pair (first (Some first)) (second rest))
             (match (holding ticket rest)
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

    (expose make-scheduler "tasks:create")
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
      (! mut)
      (∀ (A))
      (let ((id (ticket)))
        (start id)
        (await (list id))
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
      (→ T) (! mut) (∀ (T))
      (match (mailbox-try-receive mailbox)
        ((Some message) message)
        ((None)
         (let ((id (ticket)) (scheduler (current-scheduler)))
           (set! (● mailbox receivers)
                 (Cons (lambda () (tasks-wake! scheduler id) (unit)) (● mailbox receivers)))
           (await (list id)))
         (mailbox-receive mailbox))))

    (define (mailbox-try-receive (mailbox (Mailbox T)))
      (→ (Option T)) (! mut) (∀ (T))
      (match (dequeue (● mailbox messages))
        ((None) (None))
        ((Some (Pair message rest))
         (set! (● mailbox messages) rest)
         (Some message))))))
