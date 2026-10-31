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
   hidden-kind
   reload-kind
   storage
   load-save
   store-save
   default-reset
   app-start)
  (import
   (snail core base)
   (prefix (snail runtime browser events) host-)
   (prefix (snail runtime browser storage) host-)
   (snail shell task))
  (begin

    ;; ---- Events ----

    (: hidden-kind I32)
    (define hidden-kind 12)

    (: reload-kind I32)
    (define reload-kind 13)

    ;; Waiting for an event, like loading and storing a save below, starts
    ;; on the host and waits by ticket ((snail shell task)'s `through-host`).
    (effect events
      ((poll-event (-> I32))
       (wait-event (-> Unit ! tasks))
       (event-field (-> I32 I32))
       (random-seed (-> I32))
       (canvas-width (-> I32))
       (canvas-height (-> I32))
       (report-boot (-> I32 Unit)))
      (default
        ((poll-event host-poll)
         (wait-event (lambda () (through-host host-start-wait host-finish-wait)))
         (event-field host-field)
         (random-seed host-seed)
         (canvas-width host-width)
         (canvas-height host-height)
         (report-boot host-boot))))

    ;; ---- Storage ----

    ;; The root task owns this checkpoint protocol. Detached tasks
    ;; need their own storage binding; they cannot replace the loop's save.
    (effect storage
      ((load-count (-> I32 ! tasks))
       (loaded-byte (-> I32 U8))
       (store-save (-> Bytes Unit ! tasks)))
      (default
        ((load-count (lambda () (through-host host-start-load host-finish-load)))
         (loaded-byte host-byte)
         (store-save (lambda (bytes)
                       (through-host (lambda (ticket) (host-start-store ticket bytes))
                                     host-finish-store))))))

    (: load-save (-> (Option Bytes) ! storage tasks))
    (define (load-save)
      (let ((count (load-count)))
        (if (< count 0)
            (None)
            (Some
             (vector-generate (i32->i64 count) (lambda (index) (loaded-byte (i64->i32 index))))))))

    ;; ---- The root task ----

    ;; Instantiate the result and row on reset, not on the returned binder.
    ;; A program can replace this binder to install handlers for the run.
    (: default-reset (All (T e) (-> (-> (-> T ! e) T ! e))))
    (define (default-reset)
      (lambda (run) (run)))

    ;; The loop runs as a task, which the host drives. `app-start`
    ;; dispatches it and answers its id, which the host compares with
    ;; `tasks:running` to know a trap in the loop from a trap in another
    ;; task. The loop's answer, the state to hand over to the program that
    ;; replaces this one, or none when it could not boot, waits in
    ;; `outcome` for the host: `app_outcome` is 1 once it is there, and
    ;; `app_handover` reads it.
    (: outcome (Ref (Option (Option Any))))
    (define outcome (ref (None)))

    ;; The loop's row names `mut`, which recording its answer performs: in a
    ;; generic body, the first call fixes the row of the lambda around it.
    (: app-start (All (e) (-> (FnOnce (Option Any) ! mut tasks e) I64 ! mut e)))
    (define (app-start loop)
      (ref-set! outcome (None))
      (dispatch-task (once (lambda () (ref-set! outcome (Some (loop)))))))

    (: app-outcome (-> I32 ! mut))
    (define (app-outcome)
      (match (ref-get outcome)
        ((None) 0)
        ((Some _) 1)))

    (: app-handover (-> (Option Any) ! mut))
    (define (app-handover)
      (match (ref-get outcome)
        ((Some answer) answer)
        ((None) (panic "the application loop has not answered"))))

    (expose app-outcome "app_outcome")
    (expose app-handover "app_handover")))
