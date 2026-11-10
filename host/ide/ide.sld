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

(type Save (Option Recovery))

(define-page-state Save)

(instance (Application (! mut events storage tasks) IdeApplication)
  (define (start entry)
    (run-page (lambda () (None)) encode (lambda (bytes) (Some (deserialize bytes))) present)))

;; A replacement receives recovery data, never the old session's futures or
;; event connection. Reconnect and restore buffers under the new scheduler.
(: present (-> Save (-> Save Unit ! events storage tasks) Unit ! mut events storage tasks))
(define (present saved checkpoint)
  (with-page-dom
   (lambda ()
     (with-page-fetch
      (lambda ()
        (drop
         (run-reactor (begin-session (match saved ((Some saved) (restored saved)) ((None) initial)))
                      (list (Boot) (Connect))
                      (ann update-session
                           (-> Session
                               (Option Msg)
                               Session
                               ! mut completion events storage dom fetch))
                      session-view session-window snapshot
                      (ann commit (-> Save Unit ! mut events storage dom fetch))
                      (lambda (saved) (checkpoint saved)))))))))

(: snapshot (-> (Borrow Session) Save))
(define (snapshot session)
  (Some (session-snapshot session)))

(: encode (-> Save Bytes))
(define (encode saved)
  (serialize (match saved ((Some saved) saved) ((None) (kept initial)))))

(: commit (-> Save Unit ! mut events))
(define (commit saved)
  (commit-page saved)
  (report-ready))

(define-page-entry IdeApplication)
