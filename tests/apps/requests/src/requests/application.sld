;; Input stays responsive while a request waits on the server. Each reply
;; carries the number of the request that asked for it, and only the
;; latest request's reply is shown. Canceling moves the number on, so
;; starting again cannot install an older reply; the request itself runs
;; to completion.
(define-library (requests application)
  (export run-requests)
  (import
   (snail core base)
   (snail shell task)
   (snail shell dom)
   (snail shell fetch)
   (snail shell ui)
   (snail shell page)
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

    (define (update (fetch Fetch) (model Model) (message Msg))
      (→ (Pair Model (List (Fn → Msg))))
      (match message
        ((Load)
         (let ((request (+ (● model request) 1)))
           (new Pair
             (first (Model-request-set (Model-display-set model (Waiting)) request))
             (second (list (lambda () (Loaded request (load-text fetch))))))))
        ((Cancel)
         (stay (Model-request-set (Model-display-set model (Showing "canceled"))
                                  (+ (● model request) 1))))
        ((Click) (stay (Model-clicks-set model (+ (● model clicks) 1))))
        ((Loaded request result)
         (stay (if (= request (● model request))
                   (Model-display-set model
                                      (Showing (match result ((Ok text) text) ((Err why) why))))
                   model)))))

    (define (stay (model Model)) (→ (Pair Model (List (Fn → Msg))))
      (new Pair (first model) (second (Nil))))

    (define (load-text (fetch Fetch)) (→ (Result String String))
      (match (request fetch "GET" "/api/text" (Nil) "")
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

    ;; The page runs over the save itself, so a page started again has no
    ;; request outstanding.
    (define (run-requests (dom Dom) (fetch Fetch) (events Events) (storage PageStorage))
      (→ Unit)
      (run-page events storage (lambda () (new Save (display (Showing "idle")) (clicks 0)))
                serialize
                deserialize
                (lambda (saved checkpoint)
                  (present dom fetch events storage saved checkpoint))))

    (define (present
             (dom Dom)
             (fetch Fetch)
             (events Events)
             (storage PageStorage)
             (saved Save)
             (checkpoint (Fn Save → Unit)))
      (→ Unit)
      (run-ui dom (restore saved) (Nil)
              (lambda (model message) (update fetch model message))
              (lambda (model) (view model))
              (lambda (model) (window model))
              (lambda (model) (report-ready events))
              (lambda (model) (checkpoint (save model))))
      (unit))))
