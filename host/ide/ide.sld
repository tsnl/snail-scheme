;; The browser entry for the shared, host-independent IDE model.
(import
 (snail core base)
 (snail shell application)
 (snail shell task)
 (snail shell future)
 (snail shell dom)
 (snail shell dom page)
 (snail shell fetch)
 (snail shell fetch page)
 (snail shell ui)
 (snail shell page)
 (snail shell wire)
 (snail shell ide application))

(struct IdeApplication
  ())

(type Save (Option TabbedRecovery))

(define-page-state Save)

(instance (Application (! mut events storage tasks) IdeApplication)
  (define start
    (lambda (entry)
      (run-page (lambda () (None)) encode (lambda (bytes) (Some (read-recovery bytes))) present))))

;; A replacement receives recovery data, never the old session's futures or
;; event connection. Reconnect and restore buffers under the new scheduler.
(define (present (saved Save) (checkpoint (Fn Save → Unit ! events storage tasks)))
  (→ Unit)
  (! mut events storage tasks)
  (with-page-dom
   (lambda ()
     (with-page-fetch
      (lambda ()
        (drop
         (run-reactor (begin-session (match saved ((Some saved) (restored saved)) ((None) initial)))
                      (list (Boot) (Connect))
                      (ann update-session
                           (Fn Session (Option Msg) → Session ! mut completion events storage dom fetch))
                      session-view session-window snapshot
                      (ann commit (Fn Save → Unit ! mut events storage dom fetch))
                      (lambda (saved) (checkpoint saved)))))))))

(define (snapshot (session (Borrow Session))) (→ Save)
  (Some (session-snapshot session)))

(define (encode (saved Save)) (→ Bytes)
  (serialize (match saved ((Some saved) saved) ((None) (kept initial)))))

(define (commit (saved Save)) (→ Unit) (! mut events)
  (commit-page saved)
  (report-ready))

(define-page-entry IdeApplication)
