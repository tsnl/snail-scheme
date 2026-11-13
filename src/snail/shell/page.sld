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
   events
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
   storage
   load-save
   store-save
   page
   PageRun
   make-page
   start-page
   PageState
   define-page-state
   run-page
   commit-page
   define-page-entry)
  (import
   (snail core base)
   (only (snail core forms) host)
   (prefix (snail runtime browser events) host-)
   (prefix (snail runtime browser storage) host-)
   (snail shell application)
   (snail shell task))
  (begin

    ;; ---- Events ----

    (define hidden-kind (→ I32) 12)

    (define reload-kind (→ I32) 13)

    (define save-kind (→ I32) 16)

    ;; Waiting for an event, like loading and storing a save below, starts
    ;; on the host and waits by ticket ((snail shell task)'s `through-host`).
    (effect events
      ((poll-event (Fn → I32))
       (wait-event (Fn → Unit ! tasks))
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
    (effect storage
      ((load-count (Fn → I32 ! tasks))
       (loaded-byte (Fn I32 → U8))
       (store-save (Fn Bytes → Unit ! tasks)))
      (default
        ((load-count (lambda () (through-host host-start-load host-finish-load)))
         (loaded-byte host-byte)
         (store-save (lambda (bytes)
                       (through-host (lambda (ticket) (host-start-store ticket bytes))
                                     host-finish-store))))))

    (define (load-save) (→ (Option Bytes)) (! storage tasks)
      (let ((count (load-count)))
        (if (< count 0)
            (None)
            (Some
             (vector-generate (i32->i64 count) (lambda (index) (loaded-byte (i64->i32 index))))))))

    ;; ---- The root task ----

    ;; A root may return before its children. Completion records that
    ;; return, independently of readiness and the optional checkpoint below.
    ;; Suspension or failure never sets it.



    (struct PageRun
      ((completed Bool)
       (incoming (Option Any))
       (current (Option Any))))

    ;; The host owns one context per invocation. It holds recovery values,
    ;; never a scheduler or pending work. Saved handlers keep this context
    ;; attached to its generation when the presentation suspends.
    (effect page
      ((current-page (Fn → PageRun))))

    (define (make-page (handover (Option Any))) (→ PageRun)
      (PageRun #f handover (None)))

    (define (page-done (context PageRun)) (→ I32)
      (if (● context completed) 1 0))

    ;; ---- Checkpointed pages ----

    ;; Reification is checked at a concrete type: a generic S could hide
    ;; effects in a function. Engines request this ordinary evidence rather
    ;; than weakening the compiler's Any boundary.
    (typeclass (PageState S)
      (: pack-state (Fn S → Any))
      (: unpack-state (Fn Any → (Option S))))

    (define-syntax define-page-state
      (syntax-rules ()
        ((_ State)
         (instance (PageState State)
           (define (pack-state (state State)) (→ Any) (type-convert state Any))
           (define (unpack-state (previous Any)) (→ (Option State))
             (match (try-convert previous State)
               ((Ok state) (Some state))
               ((Err _) (None))))))))

    ;; The host retains these opaque saved values across replacement.
    ;; Only a completed presentation commits; boot keeps an initial recovery
    ;; point without declaring the page ready. The host checks root
    ;; ownership before a caller can replace the checkpoint.





    (define (commit-page (state S))
      (→ Unit)
      (! mut events page)
      (∀ S)
      (⊨ (PageState S) (Copy S) (Drop (!) S))
      (checkpoint-root)
      (set! (● (current-page) current) (Some (pack-state state))))

    (define (restore-page (cold? Bool)
                          (initialize (Fn → S ! events))
                          (decode (Fn Bytes → S)))
      (→ (Option (Pair S I32)))
      (! events storage tasks)
      (∀ S)
      (⊨ (PageState S) (Copy S) (Drop (!) S))
      (match (load-save)
        ((Some bytes) (Some (Pair (decode bytes) 1)))
        ((None) (if cold? (Some (Pair (initialize) 2)) (None)))))

    (define (boot-page (context PageRun) (initialize (Fn → S ! events)) (decode (Fn Bytes → S)))
      (→ (Option (Pair S I32)))
      (! events storage tasks)
      (∀ S)
      (⊨ (PageState S) (Copy S) (Drop (!) S))
      (match (● context incoming)
        ((Some previous)
         (match (unpack-state previous)
           ((Some state) (Some (Pair state 0)))
           ((None) (restore-page #f initialize decode))))
        ((None) (restore-page #t initialize decode))))

    ;; Engines own presentation and event reduction. This shared boundary
    ;; owns restore/refusal, the boot checkpoint and durable save encoding.

    (define (run-page (initialize (Fn → S ! events))
                      (encode (Fn S → Bytes))
                      (decode (Fn Bytes → S))
                      (run (Fn S (Fn S → Unit ! events storage tasks) → Unit ! e)))
      (→ Unit)
      (! mut events storage tasks page e)
      (∀ S e)
      (⊨ (PageState S) (Copy S) (Drop (!) S))
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

    (define (start-page (context PageRun) (scheduler Scheduler)
                        (work (FnOnce → Unit ! mut tasks page e)))
      (→ I64) (! mut host e) (∀ e)
      (handle page ((current-page (lambda () context)))
        (dispatch-in scheduler
                     (once (lambda ()
                             (work)
                             (set! (● context completed) #t))))))

    ;; Only a published checkpoint is the page's state. If loading traps
    ;; before boot, the host can recover the incoming value separately.
    ;; Each getter transfers one credit to its host caller.

    (define (page-state (context PageRun)) (→ (Option Any))
      (● context current))

    (define (page-incoming (context PageRun)) (→ (Option Any))
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
               (start-page (ann page PageRun) (ann scheduler Scheduler)
                           (once (lambda () (start (ann (Entry) (Entry App))))))))
           (expose page-main "app_main")))))

    (expose make-page "app_create")
    (expose page-done "app_done")
    (expose page-state "app_state")
    (expose page-incoming "app_incoming")

    ))
