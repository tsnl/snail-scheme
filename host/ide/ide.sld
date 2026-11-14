;; The browser entry for the shared, host-independent IDE model.
(import
 (snail core base)
 (only (snail core forms) host)
 (snail shell application)
 (snail shell task)
 (snail shell dom)
 (snail shell dom page)
 (snail shell fetch)
 (snail shell fetch page)
 (snail shell ui)
 (snail shell page)
 (snail shell wire)
 (snail shell ide application))

(record IdeApplication
  ())

(type Save (Option TabbedRecovery))

(define-page-state Save)

(instance (Application (! mut host events storage tasks page) IdeApplication)
  (define (start (entry (Entry IdeApplication)))
    (→ Unit)
    (! mut host events storage tasks page)

    (run-page (lambda () (None)) encode (lambda (bytes) (Some (read-recovery bytes))) present)))

;; A replacement receives recovery data, never the old run's commands or
;; event connection. Reconnect and restore buffers under the new scheduler.
(define (present (saved Save) (checkpoint (Fn Save → Unit ! events storage tasks)))
  (→ Unit)
  (! mut host events storage tasks page)
  (with-page-dom
   (lambda ()
     (with-page-fetch
      (lambda ()
        (run-ui (match saved ((Some saved) (restored saved)) ((None) (initial)))
                (list (Boot) (Connect))
                (lambda (model message) (ui-update model message))
                (lambda (model) (view model))
                (lambda (model) (window model))
                (lambda (model) (commit (Some (kept model))))
                (lambda (model) (checkpoint (Some (kept model)))))
        (unit))))))

(define (encode (saved Save)) (→ Bytes)
  (serialize (match saved ((Some saved) saved) ((None) (kept (initial))))))

(define (commit (saved Save)) (→ Unit) (! mut events page)
  (commit-page saved)
  (report-ready))

(define-page-entry IdeApplication)
