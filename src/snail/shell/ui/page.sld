;; A document engine over the shared page lifecycle. An InterfaceHandler
;; describes pure model transitions and commands; `run-interface` makes
;; the page's document and fetch, runs the ordinary UI loop over them, and
;; hands them to each command.
(define-library (snail shell ui page)
  (export
   Command
   InterfaceHandler
   run-interface)
  (import
   (snail core base)
   (snail shell task)
   (snail shell page)
   (snail shell dom)
   (snail shell fetch)
   (snail shell ui))
  (begin

    ;; ---- Interfaces ----

    ;; What an update starts: it acts on the page's document and fetch,
    ;; which the loop gives it, and answers a message.
    (type (Command M) (Fn Dom Fetch → M))

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

    (define (run-interface
             (dom Dom)
             (fetch Fetch)
             (events Events)
             (storage PageStorage)
             (interface (InterfaceHandler Model Message)))
      (→ Unit)
      (∀ (Model Message))
      (run-page events storage (lambda () ((● interface initialize) (random-seed events)))
                (● interface save)
                (● interface restore)
                (lambda (model save)
                  (present-interface dom fetch events storage interface model save))))

    ;; The loop runs a command as a thunk, so each of the update's commands
    ;; is handed the document and fetch here, where the loop has them.

    (define (present-interface
             (dom Dom)
             (fetch Fetch)
             (events Events)
             (storage PageStorage)
             (interface (InterfaceHandler Model Message))
             (model Model)
             (save (Fn Model → Unit)))
      (→ Unit)
      (∀ (Model Message))
      (run-ui dom
              model
              ((● interface messages) model)
              (lambda (model message)
                (match ((● interface update) model message)
                  ((Pair next commands)
                   (new Pair
                     (first next)
                     (second (map (lambda (command) (lambda () (command dom fetch)))
                                  commands))))))
              (● interface view)
              (● interface window)
              (lambda (model) (report-ready events))
              save)
      (unit))

    ))
