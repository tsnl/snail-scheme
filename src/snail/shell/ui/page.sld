;; A document engine over the shared page lifecycle. Interface describes
;; pure model transitions and commands; its Application adapter installs
;; the browser's document and fetch bindings and runs the ordinary UI loop.
(define-library (snail shell ui page)
  (export
   Command
   PageState
   define-page-state
   Interface
   InterfaceApplication
   interface-initialize
   interface-update
   interface-view
   interface-window
   interface-messages
   interface-save
   interface-restore)
  (import
   (snail core base)
   (only (snail core forms) host)
   (snail shell application)
   (snail shell task)
   (snail shell page)
   (snail shell dom)
   (snail shell dom page)
   (snail shell fetch)
   (snail shell fetch page)
   (snail shell ui))
  (begin

    ;; ---- Interfaces ----

    (type (Command M) (Fn → M ! tasks dom fetch))

    (typeclass (Interface Model)
      (type Message)
      (declare (interface-initialize (seed I32)) (→ Model))
      (declare (interface-update (model Model) (message Message))
        (→ (Pair Model (List (Command Message)))))
      (declare (interface-view (value Model)) (→ (Html Message)))
      (declare (interface-window (value Model)) (→ (List (Attribute Message))))
      (declare (interface-messages (value Model)) (→ (List Message)))
      (declare (interface-save (value Model)) (→ Bytes))
      (declare (interface-restore (bytes Bytes)) (→ Model)))

    (record (InterfaceApplication Model)
      ())

    (instance (Application (! mut host events storage tasks page) (InterfaceApplication Model))
      (⊨ (Interface Model) (PageState Model))
      (define (start (entry (Entry (InterfaceApplication Model))))
        (→ Unit)
        (! mut host events storage tasks page)

        (run-page (lambda () (initial-interface entry)) interface-save interface-restore
                  present-interface)))

    (define (initial-interface (entry (Entry (InterfaceApplication Model))))
      (→ Model)
      (! events)
      (∀ (Model))
      (⊨ (Interface Model))
      (interface-initialize (random-seed)))

    ;; The loop's row includes publishing and saving its model. Commands
    ;; retain their narrower public contract and run under the same handlers.

    (define (widen-commands (commands (List (Command M))))
      (→ (List (Fn → M ! mut host page events storage tasks dom fetch)))
      (∀ (M))
      (match commands
        ((Cons command rest) (Cons (lambda () (command)) (widen-commands rest)))
        ((Nil) (Nil))))

    (define (interface-save-callback (save (Fn S → Unit ! events storage tasks)))
      (→ (Fn S → Unit ! mut host page events storage tasks dom fetch))
      (∀ (S))
      (lambda (model) (save model)))

    (define (present-interface (model Model) (save (Fn Model → Unit ! events storage tasks)))
      (→ Unit)
      (! mut host events storage tasks page)
      (∀ (Model))
      (⊨ (Interface Model) (PageState Model))
      (with-page-dom
       (lambda ()
         (with-page-fetch
          (lambda ()
            (run-ui model (interface-messages model)
                    (lambda (model message)
                      (match (interface-update model message)
                        ((Pair next commands)
                         (new Pair (first next) (second (widen-commands commands))))))
                    interface-view interface-window
                    (lambda (model) (commit-page model) (report-ready))
                    (interface-save-callback save))
            (unit))))))

    ))
