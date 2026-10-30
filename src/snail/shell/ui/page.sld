;; A document interface hosted in a page, as `define-application` hosts a
;; scene. An interface is its model and message types and five functions:
;;
;;   init    : seed -> Model
;;   update  : Model Msg -> (Pair Model (List (Command Msg)))
;;   view    : Model -> (Html Msg)
;;   save    : Model -> Save
;;   restore : Save -> Model
;;
;; `define-ui` runs `run-ui` as the page's root task, over the page's
;; document (host/browser/ui.mjs). It boots as an application does: from
;; the model a reloading program hands over, when it is still of the
;; model's type, else from the stored save, else from `init`. It stores
;; the save when the page is hidden and when a reload closes the
;; document, and the model it closed with is what it hands over. After a
;; trap, the host reads back the model of the last checkpoint, or the one
;; it booted with.
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
   (snail shell ui))
  (begin

    ;; ---- Interfaces ----

    ;; What an interface's commands may do: wait on tasks, and reach the
    ;; page's document by element id.
    (type (Command M)
          (FnOnce M ! tasks dom))

    ;; The cell is the model last checkpointed or booted. Commands share a
    ;; row with the checkpoint, which names storage, so each is wrapped in
    ;; one that may.
    (define-syntax define-ui
      (syntax-rules (init: update: view: save: restore:)
        ((_ Model
            Msg
            (init: initialize)
            (update: step)
            (view: render)
            (save: save-model)
            (restore: restore-model))
         (begin
           (define current (ref (ann (None) (Option Model))))

           ;; A live migration must refuse an absent or incompatible save;
           ;; only a cold start may begin from `init`.
           (: ui-restore (-> Bool (Option (Pair Model I32)) ! events storage tasks))
           (define (ui-restore cold?)
             (match (load-save)
               ((Some bytes) (Some (Pair (restore-model (deserialize bytes)) 1)))
               ((None) (if cold?
                           (Some (Pair ((ann initialize (-> I32 Model)) (random-seed)) 2))
                           (None)))))

           (: ui-boot (-> (Option Any) (Option (Pair Model I32)) ! events storage tasks))
           (define (ui-boot handover)
             (match handover
               ((Some model) (if (type-test model Model)
                                 (Some (Pair (ann (type-convert model Model) Model) 0))
                                 (ui-restore #f)))
               ((None) (ui-restore #t))))

           (: ui-update (-> Model Msg (Pair Model (List (FnOnce Msg ! mut storage tasks dom)))))
           (define (ui-update model message)
             (match ((ann step (-> Model Msg (Pair Model (List (Command Msg)))))
                     model
                     message)
               ((Pair next commands) (Pair next (ui-widened commands)))))

           (: ui-widened (-> (List (Command Msg)) (List (FnOnce Msg ! mut storage tasks dom))))
           (define (ui-widened commands)
             (match commands
               ((Cons command rest) (Cons (once (lambda () (command))) (ui-widened rest)))
               ((Nil) (Nil))))

           (: ui-checkpoint (-> Model Unit ! mut storage tasks))
           (define (ui-checkpoint model)
             (ref-set! current (Some model))
             (store-save (serialize (save-model model))))

           (: ui-main (-> (Option Any) I64 ! mut events storage))
           (define (ui-main handover)
             (app-start
              (once (lambda ()
                      (match (ui-boot handover)
                        ((Some boot)
                         (ref-set! current (Some (Pair-first boot)))
                         (report-boot (Pair-second boot))
                         (Some (type-convert (with-page-dom
                                              (lambda ()
                                                (run-ui (Pair-first boot)
                                                        ui-update
                                                        (ann render (-> Model (Html Msg)))
                                                        ui-checkpoint)))
                                             Any)))
                        ((None) (None)))))))

           (: ui-state (-> Any ! mut))
           (define (ui-state)
             (match (ref-get current)
               ((Some model) (type-convert model Any))
               ((None) (panic "the interface has no model yet"))))

           (expose ui-main "app_main")
           (expose ui-state "app_state")))))))
