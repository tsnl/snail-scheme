;; Input stays responsive while a request waits on the server. Each reply
;; carries the number of the request that asked for it, and only the
;; latest request's reply is shown. Canceling moves the number on, so
;; starting again cannot install an older reply; the request itself runs
;; to completion.
(define-library (requests application)
  (export RequestsApplication)
  (import
   (snail core base)
   (only (snail core forms) host)
   (snail shell task)
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

    (record Model
      ((display Display)
       (clicks I64)
       (request I64)))

    (record Save
      ((display Display)
       (clicks I64))
      (deriving Serialize Deserialize))

    (enum Msg
      (Load)
      (Cancel)
      (Click)
      (Loaded ((request I64)
               (result (Result String String)))))

    (define (update (model Model) (message Msg))
      (→ (Pair Model (List (Fn → Msg ! fetch tasks e))))
      (∀ (e))
      (match message
        ((Load)
         (let ((request (+ (● model request) 1)))
           (new Pair
             (first (Model-request-set (Model-display-set model (Waiting)) request))
             (second (list (lambda () (Loaded request (load-text))))))))
        ((Cancel)
         (stay (Model-request-set (Model-display-set model (Showing "canceled"))
                                  (+ (● model request) 1))))
        ((Click) (stay (Model-clicks-set model (+ (● model clicks) 1))))
        ((Loaded request result)
         (stay (if (= request (● model request))
                   (Model-display-set model
                                      (Showing (match result ((Ok text) text) ((Err why) why))))
                   model)))))

    (define (stay (model Model)) (→ (Pair Model (List (Fn → Msg ! fetch tasks e)))) (∀ (e))
      (new Pair (first model) (second (Nil))))

    (define (load-text) (→ (Result String String)) (! fetch tasks)
      (match (request "GET" "/api/text" (Nil) "")
        ((Ok reply) (Ok (● reply body)))
        ((Err why) (Err why))))

    (define (button (id String) (label String) (message Msg)) (→ (Html Msg))
      (Element "button"
               (list (Attr "id" id) (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (define (view (model Model)) (→ (Html Msg))
      (Element "main"
               (list (Attr "aria-busy" (match (● model display)
                                         ((Waiting) "true")
                                         (_ "false"))))
               (list (Element "h1" (Nil) (list (Text "Requests")))
                     (Element "p"
                              (list (Attr "id" "result"))
                              (list (Text (display-text (● model display)))))
                     (Element "p"
                              (list (Attr "id" "clicks"))
                              (list (Text (show (● model clicks)))))
                     (button "load" "Load" (Load))
                     (button "cancel" "Cancel" (Cancel))
                     (button "click" "Count" (Click)))))

    (define (display-text (display Display)) (→ String)
      (match display
        ((Showing text) text)
        ((Waiting) "loading")))

    (define (window (model Model)) (→ (List (Attribute Msg)))
      (Nil))

    (define (save (model Model)) (→ Save)
      (new Save (display (● model display)) (clicks (● model clicks))))

    ;; A request still waiting when the page stopped never answers.
    (define (restore (saved Save)) (→ Model)
      (new Model (display (match (● saved display)
                            ((Waiting) (Showing "interrupted"))
                            (display display)))
           (clicks (● saved clicks)) (request 0)))

    (record RequestsApplication
      ())

    (define-page-state Save)

    (instance (Application (! mut host events storage tasks page) RequestsApplication)
      (define (start (entry (Entry RequestsApplication)))
        (→ Unit)
        (! mut host events storage tasks page)

        (run-page (lambda () (new Save (display (Showing "idle")) (clicks 0)))
                  serialize
                  deserialize
                  present)))

    ;; Save is detached recovery data: a replacement starts with no request
    ;; outstanding.
    (define (present (saved Save) (checkpoint (Fn Save → Unit ! events storage tasks)))
      (→ Unit)
      (! mut host events storage tasks page)
      (with-page-dom
       (lambda ()
         (with-page-fetch
          (lambda ()
            (run-ui (restore saved) (Nil)
                    (lambda (model message) (update model message))
                    (lambda (model) (view model))
                    (lambda (model) (window model))
                    (lambda (model) (commit (save model)))
                    (lambda (model) (checkpoint (save model))))
            (unit))))))

    (define (commit (saved Save)) (→ Unit) (! mut events page)
      (commit-page saved)
      (report-ready))))
