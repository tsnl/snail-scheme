;; A document engine over the shared page lifecycle. Interface describes
;; pure model transitions and commands; its Application adapter installs
;; the browser's document and fetch bindings and runs the ordinary UI loop.
(define-library (snail shell ui page)
  (export
   Command
   Page-state
   define-page-state
   Interface
   Interface-application
   interface-initialize
   interface-update
   interface-view
   interface-window
   interface-messages
   interface-save
   interface-restore)
  (import
   (snail core base)
   (only (snail core forms) Host)
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

    (type (Command M) (Fn → M ! Tasks Dom Fetch))

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

    (record (Interface-application Model)
      ())

    (instance (Application (! Mut Host Events Storage Tasks Page) (Interface-application Model))
      (⊨ (Interface Model) (Page-state Model))
      (define (start (entry (Entry (Interface-application Model))))
        (→ Unit)
        (! Mut Host Events Storage Tasks Page)

        (run-page (lambda () (initial-interface entry)) interface-save interface-restore
                  present-interface)))

    (define (initial-interface (entry (Entry (Interface-application Model))))
      (→ Model)
      (! Events)
      (∀ (Model))
      (⊨ (Interface Model))
      (interface-initialize (random-seed)))

    ;; The loop's row includes publishing and saving its model. Commands and
    ;; the save keep their narrower contracts and fit the loop as they are.
    ;; The update's pair is rebuilt because a record's type never widens;
    ;; its commands widen as they move into the new one.

    (define (present-interface (model Model) (save (Fn Model → Unit ! Events Storage Tasks)))
      (→ Unit)
      (! Mut Host Events Storage Tasks Page)
      (∀ (Model))
      (⊨ (Interface Model) (Page-state Model))
      (with-page-dom
       (lambda ()
         (with-page-fetch
          (lambda ()
            (run-ui model (interface-messages model)
                    (lambda (model message)
                      (match (interface-update model message)
                        ((Pair next commands) (new Pair (first next) (second commands)))))
                    interface-view interface-window
                    (lambda (model) (commit-page model) (report-ready))
                    save)
            (unit))))))

    ))
