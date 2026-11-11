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

    (type (Command M) (dyn (FnOnce → M ! tasks dom fetch)))

    (typeclass (Interface Model)
      (type Message)
      (: interface-initialize (impl (Fn I32 → Model)))
      (: interface-update (impl (Fn Model Message → (Pair Model (List (Command Message))))))
      (: interface-view (impl (Fn Model → (Html Message))))
      (: interface-window (impl (Fn Model → (List (Attribute Message)))))
      (: interface-messages (impl (Fn Model → (List Message))))
      (: interface-save (impl (Fn Model → Bytes)))
      (: interface-restore (impl (Fn Bytes → Model))))

    (struct (InterfaceApplication Model)
      ())

    (instance (Application (! mut events storage tasks) (InterfaceApplication Model))
      (⊨ (Interface Model) (PageState Model) (Copy Model))
      (define start
        (lambda (entry)
          (run-page (lambda () (initial-interface entry)) interface-save interface-restore
                    present-interface))))

    (define (initial-interface (entry (Entry (InterfaceApplication Model))))
      (→ Model)
      (! events)
      (∀ Model)
      (⊨ (Interface Model))
      (interface-initialize (random-seed)))

    ;; The loop's row includes publishing and saving its model. Commands
    ;; retain their narrower public contract and run under the same handlers.

    (define (widen-commands (commands (List (Command M))))
      (→ (List (dyn (FnOnce → M ! mut events storage tasks dom fetch))))
      (∀ M)
      (match commands
        ((Cons command rest) (Cons (once (lambda () (command))) (widen-commands rest)))
        ((Nil) (Nil))))

    (define (interface-save-callback (save (dyn (Fn S → Unit ! events storage tasks))))
      (→ (dyn (Fn S → Unit ! mut events storage tasks dom fetch)))
      (∀ S)
      (lambda (model) (save model)))

    (define (present-interface (model Model) (save (dyn (Fn Model → Unit ! events storage tasks))))
      (→ Unit)
      (! mut events storage tasks)
      (∀ Model)
      (⊨ (Interface Model) (PageState Model) (Copy Model))
      (with-page-dom
       (lambda ()
         (with-page-fetch
          (lambda ()
            (run-ui model (interface-messages model)
                    (lambda (model message)
                      (match (interface-update model message)
                        ((Pair next commands) (Pair next (widen-commands commands)))))
                    interface-view interface-window
                    (lambda (model) (commit-page model) (report-ready))
                    (interface-save-callback save))
            (unit))))))

    ))
