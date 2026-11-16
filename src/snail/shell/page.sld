;; What a page's program shares, whether it draws a scene ((snail shell
;; app)) or shows a document ((snail shell ui page)): the host's queue of
;; events, the storage of one save, and `run-page`, which boots from that
;; save. A trap ends the page; it keeps its last save
;; (host/browser/runtime.mjs).
;;
;; An event is a kind and fields of I32. The kinds 11, 12 and 16, a
;; display frame, the page hidden and a save's timer, are the host's own;
;; each program numbers the rest, which match its host's encoding. A
;; display frame matters only to a scene, which matches its kind itself.
(define-library (snail shell page)
  (export
   events
   provide-events
   poll-event
   wait-event
   event-field
   random-seed
   canvas-width
   canvas-height
   report-boot
   report-ready
   hidden-kind
   save-kind
   storage
   provide-storage
   load-save
   store-save
   run-page)
  (import
   (snail core base)
   (only (snail core forms) host)
   (prefix (snail runtime browser events) host-)
   (prefix (snail runtime browser storage) host-)
   (snail shell task))
  (begin

    ;; ---- Events ----

    (define hidden-kind (→ I32) 12)

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
       (report-ready (Fn → Unit))))

    ;; The page's events, through the browser host.
    (define (provide-events (work (Fn → T ! events e))) (→ T) (! e) (∀ (T e))
      (handle events
          ((poll-event host-poll)
           (wait-event (lambda () (through-host host-start-wait host-finish-wait)))
           (event-field host-field)
           (random-seed host-seed)
           (canvas-width host-width)
           (canvas-height host-height)
           (report-boot host-boot)
           (report-ready host-ready))
        (work)))

    ;; ---- Storage ----

    ;; One save, read at boot and replaced by each store.
    (effect storage
      ((load-count (Fn → I32 ! tasks))
       (loaded-byte (Fn I32 → U8))
       (store-save (Fn Bytes → Unit ! tasks))))

    ;; The page's saved state, through the browser host.
    (define (provide-storage (work (Fn → T ! storage e))) (→ T) (! e) (∀ (T e))
      (handle storage
          ((load-count (lambda () (through-host host-start-load host-finish-load)))
           (loaded-byte host-byte)
           (store-save (lambda (bytes)
                         (through-host (lambda (ticket) (host-start-store ticket bytes))
                                       host-finish-store))))
        (work)))

    (define (load-save) (→ (Option Bytes)) (! storage tasks)
      (let ((count (load-count)))
        (if (< count 0)
            (None)
            (Some
             (array-generate (i32->i64 count) (lambda (index) (loaded-byte (i64->i32 index))))))))

    ;; ---- Running a page ----

    ;; A page's state is its save's, when it has one, and otherwise
    ;; `initialize`'s; the boot report tells the host which, 1 or 2. A save
    ;; `decode` cannot read traps before the report, and the host starts the
    ;; page again without it. `run` takes the state and a function that saves
    ;; one, which a loop calls when the page is hidden or the host's timer
    ;; asks: five seconds after the boot or the last save.

    (define (run-page (initialize (Fn → S ! events))
                      (encode (Fn S → Bytes))
                      (decode (Fn Bytes → S))
                      (run (Fn S (Fn S → Unit ! events storage tasks) → Unit ! e)))
      (→ Unit)
      (! events storage tasks e)
      (∀ (S e))
      (let ((booted (match (load-save)
                      ((Some bytes) (new Pair (first (decode bytes)) (second 1)))
                      ((None) (new Pair (first (initialize)) (second 2))))))
        (report-boot (● booted second))
        (run (● booted first) (lambda (state) (store-save (encode state))))))

    ))
