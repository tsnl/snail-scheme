;; Input stays responsive while a future waits on the server. Canceling
;; reception and starting again cannot install an older reply. There is
;; no Loaded action: update takes the result directly out of its model.
(define-library (futures application)
  (export FuturesApplication)
  (import
   (snail core base)
   (snail shell task)
   (snail shell future)
   (snail shell async)
   (snail shell dom)
   (snail shell fetch)
   (snail shell ui)
   (snail shell application)
   (snail shell page)
   (snail shell dom page)
   (snail shell fetch page)
   (snail shell wire))
  (begin

    (enum Display
      (Showing ((text String)))
      (Waiting)
      (deriving Serialize Deserialize))

    (struct Model
      ((display Display)
       (clicks I64)
       (pending (Option (Future (Result String String))))))

    (struct Save
      ((display Display)
       (clicks I64))
      (deriving Serialize Deserialize))

    (enum Msg
      (Load)
      (Cancel)
      (Click))

    (define (update (model Model) (message (Option Msg))) (→ Model) (! mut completion fetch)
      (match model
        ((Model display clicks pending)
         (match message
           ((Some (Load))
            (drop pending)
            (Model (Waiting) clicks (Some (dispatch (once load-text)))))
           ((Some (Cancel))
            (drop pending)
            (Model (Showing "canceled") clicks (None)))
           ((Some (Click)) (collect display (+ clicks 1) pending))
           ((None) (collect display clicks pending))))))

    (define (load-text) (→ (Result String String)) (! fetch tasks)
      (match (request "GET" "/api/text" (Nil) "")
        ((Ok reply) (Ok (::body reply)))
        ((Err why) (Err why))))

    (define (collect (display Display)
                     (clicks I64)
                     (pending (Option (Future (Result String String)))))
      (→ Model)
      (! mut)
      (match pending
        ((None) (Model display clicks (None)))
        ((Some future)
         (match (poll future)
           ((Pending future) (Model display clicks (Some future)))
           ((Ready (Completed (Ok text))) (Model (Showing text) clicks (None)))
           ((Ready (Completed (Err why))) (Model (Showing why) clicks (None)))
           ((Ready (Abandoned)) (Model (Showing "abandoned") clicks (None)))))))

    (define (button (id String) (label String) (message Msg)) (→ (Html Msg))
      (Element "button"
               (list (Attr "id" id) (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (define (view (model (Borrow Model))) (→ (Html Msg))
      (Element "main"
               (list (Attr "aria-busy" (match (::display model)
                                         ((Waiting) "true")
                                         (_ "false"))))
               (list (Element "h1" (Nil) (list (Text "Future requests")))
                     (Element "p"
                              (list (Attr "id" "result"))
                              (list (Text (display-text (::display model)))))
                     (Element "p"
                              (list (Attr "id" "clicks"))
                              (list (Text (show (::clicks model)))))
                     (button "load" "Load" (Load))
                     (button "cancel" "Cancel" (Cancel))
                     (button "click" "Count" (Click)))))

    (define (display-text (display Display)) (→ String)
      (match display
        ((Showing text) text)
        ((Waiting) "loading")))

    (define (window (model (Borrow Model))) (→ (List (Attribute Msg)))
      (Nil))

    (define (save (model (Borrow Model))) (→ Save)
      (Save (::display model) (::clicks model)))

    (define (restore (saved Save)) (→ Model)
      (Model (match (::display saved)
               ((Waiting) (Showing "interrupted"))
               (display display))
             (::clicks saved) (None)))

    (struct FuturesApplication
      ())

    (define-page-state Save)

    (instance (Application (! mut events storage tasks) FuturesApplication)
      (define start
        (lambda (entry)
          (run-page (lambda () (Save (Showing "idle") 0)) serialize deserialize present))))

    ;; Only Save enters the shared lifecycle. Construct the linear model inside
    ;; the repeatable host binders, then keep it owned by the reactor's loop.
    (define (present (saved Save) (checkpoint (dyn (Fn Save → Unit ! events storage tasks))))
      (→ Unit)
      (! mut events storage tasks)
      (with-page-dom
       (lambda ()
         (with-page-fetch
          (lambda ()
            (drop (run-reactor (restore saved) (Nil)
                               (ann update
                                    (dyn (Fn Model
                                             (Option Msg)
                                             → Model
                                             ! mut completion events storage dom fetch)))
                               view window save
                               (ann commit (dyn (Fn Save → Unit ! mut events storage dom fetch)))
                               (lambda (saved) (checkpoint saved)))))))))

    (define (commit (saved Save)) (→ Unit) (! mut events)
      (commit-page saved)
      (report-ready))
    ))
