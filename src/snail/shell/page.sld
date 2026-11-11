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
   start-page
   PageState
   define-page-state
   run-page
   commit-page
   define-page-entry)
  (import
   (snail core base)
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
      ((poll-event (dyn (Fn → I32)))
       (wait-event (dyn (Fn → Unit ! tasks)))
       (event-field (dyn (Fn I32 → I32)))
       (random-seed (dyn (Fn → I32)))
       (canvas-width (dyn (Fn → I32)))
       (canvas-height (dyn (Fn → I32)))
       (report-boot (dyn (Fn I32 → Unit)))
       (report-ready (dyn (Fn → Unit)))
       (checkpoint-root (dyn (Fn → Unit)))
       (handover-only (dyn (Fn → I32)))
       (save-after (dyn (Fn I32 → Unit))))
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
      ((load-count (dyn (Fn → I32 ! tasks)))
       (loaded-byte (dyn (Fn I32 → U8)))
       (store-save (dyn (Fn Bytes → Unit ! tasks))))
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

    (define completed (→ (Ref Bool)) (ref #f))

    (define (page-done) (→ I32) (! mut)
      (if (ref-get completed) 1 0))

    ;; ---- Checkpointed pages ----

    ;; Reification is checked at a concrete type: a generic S could hide
    ;; effects in a function. Engines request this ordinary evidence rather
    ;; than weakening the compiler's Any boundary.
    (typeclass (PageState S)
      (: pack-state (impl (Fn S → Any)))
      (: unpack-state (impl (Fn Any → (Option S)))))

    (define-syntax define-page-state
      (syntax-rules ()
        ((_ State)
         (instance (PageState State)
           (define (pack-state (state State)) (→ Any) (type-convert state Any))
           (define (unpack-state (previous Any)) (→ (Option State))
             (match (try-convert previous State)
               ((Ok state) (Some state))
               ((Err _) (None))))))))

    ;; The host retains these opaque immutable values across replacement.
    ;; Only a completed presentation commits; boot keeps an initial recovery
    ;; point without declaring the page ready. The host checks root
    ;; ownership before a caller can replace the checkpoint.

    (define incoming (→ (Ref (Option Any))) (ref (None)))

    (define current (→ (Ref (Option Any))) (ref (None)))

    (define (commit-page (state S)) (→ Unit) (! mut events) (∀ S) (⊨ (PageState S) (Copy S))
      (checkpoint-root)
      (ref-set! current (Some (pack-state state))))

    (define (restore-page (cold? Bool)
                          (initialize (dyn (Fn → S ! events)))
                          (decode (dyn (Fn Bytes → S))))
      (→ (Option (Pair S I32)))
      (! events storage tasks)
      (∀ S)
      (⊨ (PageState S) (Copy S))
      (match (load-save)
        ((Some bytes) (Some (Pair (decode bytes) 1)))
        ((None) (if cold? (Some (Pair (initialize) 2)) (None)))))

    (define (boot-page (initialize (dyn (Fn → S ! events))) (decode (dyn (Fn Bytes → S))))
      (→ (Option (Pair S I32)))
      (! mut events storage tasks)
      (∀ S)
      (⊨ (PageState S) (Copy S))
      (match (ref-get incoming)
        ((Some previous)
         (match (unpack-state previous)
           ((Some state) (Some (Pair state 0)))
           ((None) (restore-page #f initialize decode))))
        ((None) (restore-page #t initialize decode))))

    ;; Engines own presentation and event reduction. This shared boundary
    ;; owns restore/refusal, the boot checkpoint and durable save encoding.

    (define (run-page (initialize (dyn (Fn → S ! events)))
                      (encode (dyn (Fn S → Bytes)))
                      (decode (dyn (Fn Bytes → S)))
                      (run (dyn (Fn S (dyn (Fn S → Unit ! events storage tasks)) → Unit ! e))))
      (→ Unit)
      (! mut events storage tasks e)
      (∀ S e)
      (⊨ (PageState S) (Copy S))
      (match (boot-page initialize decode)
        ((Some (Pair state kind))
         (commit-page state)
         (ref-set! incoming (None))
         (report-boot kind)
         (if (= (handover-only) 1)
             (store-save (encode state))
             (begin
               (save-after 5000)
               (run state (lambda (state) (store-save (encode state)) (save-after 5000))))))
        ((None) (unit))))

    (define (start-page (handover (Option Any)) (work (dyn (FnOnce → Unit ! mut tasks e))))
      (→ I64)
      (! mut e)
      (∀ e)
      (ref-set! incoming handover)
      (ref-set! current (None))
      (ref-set! completed #f)
      (dispatch-task (once (lambda () (work) (ref-set! completed #t)))))

    ;; Both normal return and failure hand over this same checkpoint. An
    ;; unadopted incoming value is never mistaken for the root's own state.

    (define (page-state) (→ (Option Any)) (! mut)
      (ref-get current))

    ;; The only generated browser scaffolding is an ordinary Application
    ;; call. Its selected instance determines the effect row, without an
    ;; effects list or a reset binder in the entry declaration.
    (define-syntax define-page-entry
      (syntax-rules ()
        ((_ App)
         (begin
           (define page-main
             (lambda (handover)
               (start-page (ann handover (Option Any))
                           (once (lambda () (start (ann (Entry) (Entry App))))))))
           (expose page-main "app_main")))))

    (expose page-done "app_done")
    (expose page-state "app_state")))
