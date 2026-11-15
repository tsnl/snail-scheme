;; What a page's program shares, whether it draws a scene ((snail shell
;; app)) or shows a document ((snail shell ui page)): the host's queue of
;; events, the storage of one checkpoint, and the root task the host
;; drives. Only the root task polls events and touches storage, so a trap
;; there ends the run with its last checkpoint (host/browser/runtime.mjs).
;;
;; An event is a kind and fields of I32. The kinds 11 to 13, a display
;; frame, the page hidden and a reload, are the host's own; each program
;; numbers the rest, which match its host's encoding. A display frame
;; matters only to a scene, which matches its kind itself.
(define-library (snail shell page)
  (export
   Events
   poll-event
   wait-event
   event-field
   random-seed
   canvas-width
   canvas-height
   report-boot
   report-ready
   hidden-kind
   reload-kind
   save-kind
   Storage
   load-save
   store-save
   Page
   Page-run
   make-page
   start-page
   Page-state
   define-page-state
   run-page
   commit-page
   define-page-entry)
  (import
   (snail core base)
   (only (snail core forms) Host)
   (prefix (snail runtime browser events) host-)
   (prefix (snail runtime browser storage) host-)
   (snail shell application)
   (snail shell task))
  (begin

    ;; ---- Events ----

    (define (hidden-kind) (→ I32) 12)

    (define (reload-kind) (→ I32) 13)

    (define (save-kind) (→ I32) 16)

    ;; Waiting for an event, like loading and storing a save below, starts
    ;; on the host and waits by ticket ((snail shell task)'s `through-host`).
    (effect Events
      ((poll-event (Fn → I32))
       (wait-event (Fn → Unit ! Tasks))
       (event-field (Fn I32 → I32))
       (random-seed (Fn → I32))
       (canvas-width (Fn → I32))
       (canvas-height (Fn → I32))
       (report-boot (Fn I32 → Unit))
       (report-ready (Fn → Unit))
       (checkpoint-root (Fn → Unit))
       (handover-only (Fn → I32))
       (save-after (Fn I32 → Unit)))
      (default
        ((poll-event host-poll)
         (wait-event (lambda () (through-host host-start-wait host-finish-wait)))
         (event-field host-field)
         (random-seed host-seed)
         (canvas-width host-width)
         (canvas-height host-height)
         (report-boot host-boot)
         (report-ready host-ready)
         (checkpoint-root host-checkpoint)
         (handover-only host-handover-only)
         (save-after host-save-after))))

    ;; ---- Storage ----

    ;; The root task owns this checkpoint protocol. Detached tasks
    ;; need their own storage binding; they cannot replace the loop's save.
    (effect Storage
      ((load-count (Fn → I32 ! Tasks))
       (loaded-byte (Fn I32 → U8))
       (store-save (Fn Bytes → Unit ! Tasks)))
      (default
        ((load-count (lambda () (through-host host-start-load host-finish-load)))
         (loaded-byte host-byte)
         (store-save (lambda (bytes)
                       (through-host (lambda (ticket) (host-start-store ticket bytes))
                                     host-finish-store))))))

    (define (load-save) (→ (Option Bytes)) (! Storage Tasks)
      (let ((count (load-count)))
        (if (< count 0)
            (None)
            (Some
             (vector-generate (i32->i64 count) (lambda (index) (loaded-byte (i64->i32 index))))))))

    ;; ---- The root task ----

    ;; A root may return before its children. Completion records that
    ;; return, independently of readiness and the optional checkpoint below.
    ;; Suspension or failure never sets it.

    (record Page-run
      ((completed Bool)
       (incoming (Option Any))
       (current (Option Any))))

    ;; The host owns one context per invocation. It holds recovery values,
    ;; never a scheduler or pending work. Saved handlers keep this context
    ;; attached to its generation when the presentation suspends.
    (effect Page
      ((current-page (Fn → Page-run))))

    (define (make-page (handover (Option Any))) (→ Page-run)
      (new Page-run (completed #f) (incoming handover) (current (None))))

    (define (page-done (context Page-run)) (→ I32)
      (if (● context completed) 1 0))

    ;; ---- Checkpointed pages ----

    ;; Reification is checked at a concrete type: a generic S could hide
    ;; effects in a function. Engines request this ordinary evidence rather
    ;; than weakening the compiler's Any boundary.
    (typeclass (Page-state S)
      (declare (pack-state (state S)) (→ Any))
      (declare (unpack-state (boxed Any)) (→ (Option S))))

    (define-syntax define-page-state
      (syntax-rules ()
        ((_ State)
         (instance (Page-state State)
           (define (pack-state (state State)) (→ Any) (Any state))
           (define (unpack-state (previous Any)) (→ (Option State))
             (downcast State previous))))))

    ;; The host retains these opaque saved values across replacement.
    ;; Only a completed presentation commits; boot keeps an initial recovery
    ;; point without declaring the page ready. Only the root task may
    ;; replace the checkpoint, which the host checks first.

    (define (commit-page (state S))
      (→ Unit)
      (! Mut Events Page)
      (∀ (S))
      (⊨ (Page-state S))
      (checkpoint-root)
      (set! (● (current-page) current) (Some (pack-state state))))

    (define (restore-page (cold? Bool)
                          (initialize (Fn → S ! Events))
                          (decode (Fn Bytes → S)))
      (→ (Option (Pair S I32)))
      (! Events Storage Tasks)
      (∀ (S))
      (⊨ (Page-state S))
      (match (load-save)
        ((Some bytes) (Some (new Pair (first (decode bytes)) (second 1))))
        ((None) (if cold? (Some (new Pair (first (initialize)) (second 2))) (None)))))

    (define (boot-page (context Page-run) (initialize (Fn → S ! Events)) (decode (Fn Bytes → S)))
      (→ (Option (Pair S I32)))
      (! Events Storage Tasks)
      (∀ (S))
      (⊨ (Page-state S))
      (match (● context incoming)
        ((Some previous)
         (match (unpack-state previous)
           ((Some state) (Some (new Pair (first state) (second 0))))
           ((None) (restore-page #f initialize decode))))
        ((None) (restore-page #t initialize decode))))

    ;; Engines own presentation and event reduction. This shared boundary
    ;; owns restore/refusal, the boot checkpoint and durable save encoding.

    (define (run-page (initialize (Fn → S ! Events))
                      (encode (Fn S → Bytes))
                      (decode (Fn Bytes → S))
                      (run (Fn S (Fn S → Unit ! Events Storage Tasks) → Unit ! e)))
      (→ Unit)
      (! Mut Events Storage Tasks Page e)
      (∀ (S e))
      (⊨ (Page-state S))
      (let ((context (current-page)))
        (match (boot-page context initialize decode)
          ((Some (Pair state kind))
           (commit-page state)
           (set! (● context incoming) (None))
           (report-boot kind)
           (if (= (handover-only) 1)
               (store-save (encode state))
               (begin
                 (save-after 5000)
                 (run state (lambda (state) (store-save (encode state)) (save-after 5000))))))
          ((None) (unit)))))

    (define (start-page (context Page-run) (scheduler Scheduler)
                        (work (Fn → Unit ! Mut Tasks Page e)))
      (→ I64) (! Mut Host e) (∀ (e))
      (handle Page ((current-page (lambda () context)))
        (dispatch-in scheduler
                     (lambda ()
                       (work)
                       (set! (● context completed) #t)))))

    ;; Only a published checkpoint is the page's state. If loading traps
    ;; before boot, the host can recover the incoming value separately.

    (define (page-state (context Page-run)) (→ (Option Any))
      (● context current))

    (define (page-incoming (context Page-run)) (→ (Option Any))
      (● context incoming))

    ;; The only generated browser scaffolding is an ordinary Application
    ;; call. Its selected instance determines the effect row, without an
    ;; effects list or a reset binder in the entry declaration.
    (define-syntax define-page-entry
      (syntax-rules ()
        ((_ App)
         (begin
           (define page-main
             (lambda (scheduler page)
               (start-page (ann page Page-run) (ann scheduler Scheduler)
                           (lambda () (start (ann (new Entry) (Entry App)))))))
           (expose page-main "app_main")))))

    (expose make-page "app_create")
    (expose page-done "app_done")
    (expose page-state "app_state")
    (expose page-incoming "app_incoming")

    ))
