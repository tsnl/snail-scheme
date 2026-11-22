;; A document engine over the shared page lifecycle. An InterfaceHandler
;; describes pure model transitions and commands; `run-interface` installs
;; the browser's document and fetch bindings and runs the ordinary UI loop.
(define-library (snail shell ui page)
  (export
   Command
   InterfaceHandler
   run-interface)
  (import
   (snail core base)
   (only (snail core forms) host)
   (snail shell task)
   (snail shell page)
   (snail shell dom)
   (snail shell dom page)
   (snail shell fetch)
   (snail shell fetch page)
   (snail shell ui))
  (begin

    ;; ---- Interfaces ----

    (type (Command M) (Fn → M ! tasks mut))

    ;; An interface is a handler, in the style of winit's: a record of
    ;; pure model transitions and views, and the commands an update
    ;; starts, which a script hands to `run-interface` as its last
    ;; statement.

    (record (InterfaceHandler Model Message)
      ((initialize (Fn I32 → Model))
       (update (Fn Model Message → (Pair Model (List (Command Message)))))
       (view (Fn Model → (Html Message)))
       (window (Fn Model → (List (Attribute Message))))
       (messages (Fn Model → (List Message)))
       (save (Fn Model → Bytes))
       (restore (Fn Bytes → Model))))

    ;; The page's model, from its save or `initialize` with a seed, then
    ;; the interface's loop over the page's document and fetch.

    (define (run-interface (events Events) (storage Storage) (interface (InterfaceHandler Model Message)))
      (→ Unit)
      (! mut host tasks)
      (∀ (Model Message))
      (run-page events storage (lambda () ((● interface initialize) (random-seed events)))
                (● interface save)
                (● interface restore)
                (lambda (model save) (present-interface events storage interface model save))))

    ;; The loop's row includes saving its model. Commands keep their
    ;; narrower contract and fit the loop as they are. The update's pair is
    ;; rebuilt because a record's type never widens; its commands widen as
    ;; they move into the new one.

    (define (present-interface (events Events) (storage Storage) (interface (InterfaceHandler Model Message))
                               (model Model)
                               (save (Fn Model → Unit ! mut tasks)))
      (→ Unit)
      (! mut host tasks)
      (∀ (Model Message))
      (with-page-dom events
       (lambda ()
         (with-page-fetch
          (lambda ()
            (run-ui dom model ((● interface messages) model)
                    (lambda (model message)
                      (match ((● interface update) model message)
                        ((Pair next commands) (new Pair (first next) (second commands)))))
                    (● interface view) (● interface window)
                    (lambda (model) (report-ready events))
                    save)
            (unit))))))

    ))
