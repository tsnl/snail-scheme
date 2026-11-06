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

    (type (Command M) (FnOnce M ! tasks dom fetch))

    (typeclass (Interface Model)
      (type Message)
      (: interface-initialize (-> I32 Model))
      (: interface-update (-> Model Message (Pair Model (List (Command Message)))))
      (: interface-view (-> Model (Html Message)))
      (: interface-window (-> Model (List (Attribute Message))))
      (: interface-messages (-> Model (List Message)))
      (: interface-save (-> Model Bytes))
      (: interface-restore (-> Bytes Model)))

    (struct (InterfaceApplication Model)
      ())

    (instance (Application (! mut events storage tasks) (InterfaceApplication Model))
      (requires (Interface Model) (PageState Model) (Copy Model))
      (define (start entry)
        (run-page (lambda () (initial-interface entry)) interface-save interface-restore
                  present-interface)))

    (: initial-interface
       (All (Model) (requires (Interface Model))
            (-> (Entry (InterfaceApplication Model)) Model ! events)))
    (define (initial-interface entry)
      (interface-initialize (random-seed)))

    ;; The loop's row includes publishing and saving its model. Commands
    ;; retain their narrower public contract and run under the same handlers.
    (: widen-commands
       (All (M) (-> (List (Command M))
                    (List (FnOnce M ! mut events storage tasks dom fetch)))))
    (define (widen-commands commands)
      (match commands
        ((Cons command rest) (Cons (once (lambda () (command))) (widen-commands rest)))
        ((Nil) (Nil))))

    (: interface-save-callback
       (All (S) (-> (-> S Unit ! events storage tasks)
                    (-> S Unit ! mut events storage tasks dom fetch))))
    (define (interface-save-callback save)
      (lambda (model) (save model)))

    (: present-interface
       (All (Model) (requires (Interface Model) (PageState Model) (Copy Model))
            (-> Model (-> Model Unit ! events storage tasks) Unit ! mut events storage tasks)))
    (define (present-interface model save)
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
