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

    (: update (-> Model (Option Msg) Model ! mut completion fetch))
    (define (update model message)
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

    (: load-text (-> (Result String String) ! fetch tasks))
    (define (load-text)
      (match (request "GET" "/api/text" (Nil) "")
        ((Ok reply) (Ok (Reply-body reply)))
        ((Err why) (Err why))))

    (: collect (-> Display I64 (Option (Future (Result String String))) Model ! mut))
    (define (collect display clicks pending)
      (match pending
        ((None) (Model display clicks (None)))
        ((Some future)
         (match (poll future)
           ((Pending future) (Model display clicks (Some future)))
           ((Ready (Completed (Ok text))) (Model (Showing text) clicks (None)))
           ((Ready (Completed (Err why))) (Model (Showing why) clicks (None)))
           ((Ready (Abandoned)) (Model (Showing "abandoned") clicks (None)))))))

    (: button (-> String String Msg (Html Msg)))
    (define (button id label message)
      (Element "button"
               (list (Attr "id" id) (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (: view (-> (Borrow Model) (Html Msg)))
    (define (view model)
      (Element "main"
               (list (Attr "aria-busy" (match (Model-display model)
                                         ((Waiting) "true")
                                         (_ "false"))))
               (list (Element "h1" (Nil) (list (Text "Future requests")))
                     (Element "p"
                              (list (Attr "id" "result"))
                              (list (Text (display-text (Model-display model)))))
                     (Element "p"
                              (list (Attr "id" "clicks"))
                              (list (Text (show (Model-clicks model)))))
                     (button "load" "Load" (Load))
                     (button "cancel" "Cancel" (Cancel))
                     (button "click" "Count" (Click)))))

    (: display-text (-> Display String))
    (define (display-text display)
      (match display
        ((Showing text) text)
        ((Waiting) "loading")))

    (: window (-> (Borrow Model) (List (Attribute Msg))))
    (define (window model)
      (Nil))

    (: save (-> (Borrow Model) Save))
    (define (save model)
      (Save (Model-display model) (Model-clicks model)))

    (: restore (-> Save Model))
    (define (restore saved)
      (Model (match (Save-display saved)
               ((Waiting) (Showing "interrupted"))
               (display display))
             (Save-clicks saved) (None)))

    (struct FuturesApplication
      ())

    (define-page-state Save)

    (instance (Application (! mut events storage tasks) FuturesApplication)
      (define (start entry)
        (run-page (lambda () (Save (Showing "idle") 0)) serialize deserialize present)))

    ;; Only Save enters the shared lifecycle. Construct the linear model inside
    ;; the repeatable host binders, then keep it owned by the reactor's loop.
    (: present (-> Save (-> Save Unit ! events storage tasks) Unit ! mut events storage tasks))
    (define (present saved checkpoint)
      (with-page-dom
       (lambda ()
         (with-page-fetch
          (lambda ()
            (drop (run-reactor (restore saved) (Nil)
                               (ann update
                                    (-> Model
                                        (Option Msg)
                                        Model
                                        ! mut completion events storage dom fetch))
                               view window save
                               (ann commit (-> Save Unit ! mut events storage dom fetch))
                               (lambda (saved) (checkpoint saved)))))))))

    (: commit (-> Save Unit ! mut events))
    (define (commit saved)
      (commit-page saved)
      (report-ready))
    ))
