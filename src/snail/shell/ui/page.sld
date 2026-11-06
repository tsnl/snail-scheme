;; A document interface over the shared page lifecycle. Its view and
;; update own presentation; the page owns restoration, saving and handover.
(define-library (snail shell ui page)
  (export
   Command
   define-ui)
  (import
   (snail core base)
   (snail shell task)
   (snail shell wire)
   (snail shell page)
   (snail shell dom)
   (snail shell dom page)
   (snail shell fetch)
   (snail shell fetch page)
   (snail shell ui))
  (begin

    ;; ---- Interfaces ----

    ;; What an interface's commands may do: wait on tasks, reach the page's
    ;; document by element id, and ask the server.
    (type (Command M)
          (FnOnce M ! tasks dom fetch))

    (define-syntax define-ui
      (syntax-rules (init: update: view: window: start: save: restore:)
        ((_ Model
            Msg
            (init: initialize)
            (update: step)
            (view: render)
            (window: listening)
            (start: starting)
            (save: save-model)
            (restore: restore-model))
         (begin
           (define-page-state Model)

           (: ui-initialize (-> Model ! events))
           (define (ui-initialize)
             ((ann initialize (-> I32 Model)) (random-seed)))

           (: ui-save-bytes (-> Model Bytes))
           (define (ui-save-bytes model)
             (serialize (save-model model)))

           (: ui-restore-bytes (-> Bytes Model))
           (define (ui-restore-bytes bytes)
             (restore-model (deserialize bytes)))

           (: ui-update
              (-> Model Msg (Pair Model (List (FnOnce Msg ! mut events storage tasks dom fetch)))))
           (define (ui-update model message)
             (match ((ann step (-> Model Msg (Pair Model (List (Command Msg))))) model message)
               ((Pair next commands) (Pair next (ui-widened commands)))))

           (: ui-widened
              (-> (List (Command Msg)) (List (FnOnce Msg ! mut events storage tasks dom fetch))))
           (define (ui-widened commands)
             (match commands
               ((Cons command rest) (Cons (once (lambda () (command))) (ui-widened rest)))
               ((Nil) (Nil))))

           (: ui-save-callback
              (-> (-> Model Unit ! events storage tasks)
                  (-> Model Unit ! mut events storage tasks dom fetch)))
           (define (ui-save-callback save)
             (lambda (model) (save model)))

           (: ui-present
              (-> Model (-> Model Unit ! events storage tasks) Unit ! mut events storage tasks))
           (define (ui-present model save)
             (with-page-dom
              (lambda ()
                (with-page-fetch
                 (lambda ()
                   (run-ui model (ann starting (List Msg)) ui-update
                           (ann render (-> Model (Html Msg)))
                           (ann listening (-> Model (List (Attribute Msg))))
                           (lambda (model) (commit-page model) (report-ready))
                           (ui-save-callback save))
                   (unit))))))

           (: ui-main (-> (Option Any) I64 ! mut events storage))
           (define (ui-main handover)
             (start-page handover
                         (once (lambda ()
                                 (run-page ui-initialize ui-save-bytes ui-restore-bytes
                                           ui-present)))))

           (expose ui-main "app_main")))))))
