;; Input stays responsive while a future waits on the server. Canceling
;; forgets the pending future, so starting again cannot install an older
;; reply; the request itself runs to completion. There is no Loaded
;; action: update takes the result directly out of its model.
(define-library (futures application)
  (export FuturesApplication)
  (import
   (snail core base)
   (only (snail core forms) host)
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

    (record Model
      ((display Display)
       (clicks I64)
       (pending (Option (Future (Result String String))))))

    (record Save
      ((display Display)
       (clicks I64))
      (deriving Serialize Deserialize))

    (enum Msg
      (Load)
      (Cancel)
      (Click))

    (define (update (model Model) (message (Option Msg)))
      (→ Model) (! mut host completion fetch tasks)
      (match message
        ((Some (Load))
         (set! (● model pending) (Some (dispatch load-text)))
         (set! (● model display) (Waiting)))
        ((Some (Cancel))
         (cancel! model)
         (set! (● model display) (Showing "canceled")))
        ((Some (Click)) (set! (● model clicks) (+ (● model clicks) 1)) (collect model))
        ((None) (collect model)))
      model)

    (define (load-text) (→ (Result String String)) (! fetch tasks)
      (match (request "GET" "/api/text" (Nil) "")
        ((Ok reply) (Ok (● reply body)))
        ((Err why) (Err why))))

    (define (collect (model Model)) (→ Unit) (! mut)
      (match (● model pending)
        ((None) (unit))
        ((Some future)
         (match (poll future)
           ((Pending) (unit))
           ((Ready result)
            (set! (● model pending) (None))
            (set! (● model display) (Showing (match result ((Ok text) text) ((Err why) why)))))))))

    (define (cancel! (model Model)) (→ Unit) (! mut)
      (set! (● model pending) (None)))

    (define (button (id String) (label String) (message Msg)) (→ (Html Msg))
      (Element "button"
               (list (Attr "id" id) (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (define (view (model Model)) (→ (Html Msg))
      (Element "main"
               (list (Attr "aria-busy" (match (● model display)
                                         ((Waiting) "true")
                                         (_ "false"))))
               (list (Element "h1" (Nil) (list (Text "Future requests")))
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

    (define (restore (saved Save)) (→ Model)
      (new Model (display (match (● saved display)
                            ((Waiting) (Showing "interrupted"))
                            (display display)))
           (clicks (● saved clicks)) (pending (None))))

    (record FuturesApplication
      ())

    (define-page-state Save)

    (instance (Application (! mut host completion events storage tasks page) FuturesApplication)
      (define (start (entry (Entry FuturesApplication)))
        (→ Unit)
        (! mut host completion events storage tasks page)

        (run-page (lambda () (new Save (display (Showing "idle")) (clicks 0)))
                  serialize
                  deserialize
                  present)))

    ;; Save is detached recovery data. Returning from the loop forgets the
    ;; pending future even if another alias of the model remains.
    (define (present (saved Save) (checkpoint (Fn Save → Unit ! events storage tasks)))
      (→ Unit)
      (! mut host events storage tasks page)
      (with-page-dom
       (lambda ()
         (with-page-fetch
          (lambda ()
            (cancel! (run-reactor (restore saved) (Nil)
                                  (lambda (model message) (update model message))
                                  (lambda (model) (view model))
                                  (lambda (model) (window model))
                                  (lambda (model) (save model))
                                  (lambda (saved) (commit saved))
                                  (lambda (saved) (checkpoint saved)))))))))

    (define (commit (saved Save)) (→ Unit) (! mut events page)
      (commit-page saved)
      (report-ready))
    ))
