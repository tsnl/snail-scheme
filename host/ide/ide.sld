;; The browser entry for the shared, host-independent IDE model.
(import
 (snail core base)
 (snail shell ui page)
 (snail shell page)
 (snail shell wire)
 (snail shell ide application))

(type IdeApplication (InterfaceApplication Ide))

(define-page-state Ide)

(instance (Interface Ide)
  (type Message Msg)
  (define (interface-initialize seed) initial)
  (define (interface-update model message) (update model message))
  (define (interface-view model) (view model))
  (define (interface-window model) (window model))
  (define (interface-messages model) (list (Boot) (Connect)))
  (define (interface-save model) (serialize (kept model)))
  (define (interface-restore bytes) (restored (deserialize bytes))))

(define-page-entry IdeApplication)
