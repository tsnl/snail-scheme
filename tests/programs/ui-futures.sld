(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell async)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell ui))

(struct Model
  ((text String)
   (pending (Option (Future String)))))

(enum Msg
  (Start))

(: update (-> Model (Option Msg) Model ! mut completion))
(define (update model message)
  (match model
    ((Model text pending)
     (match message
       ((Some (Start))
        (drop pending)
        (Model "working" (Some (dispatch (once (lambda () (yield) "finished"))))))
       ((None) (collect text pending))))))

(: collect (-> String (Option (Future String)) Model ! mut))
(define (collect text pending)
  (match pending
    ((None) (Model text (None)))
    ((Some future)
     (match (poll future)
       ((Pending future) (Model text (Some future)))
       ((Ready (Completed text)) (Model text (None)))
       ((Ready (Abandoned)) (Model "canceled" (None)))))))

(: view (-> (Borrow Model) (Html Msg)))
(define (view model)
  (Element "p" (Nil) (list (Text (Model-text model)))))

(: window (-> (Borrow Model) (List (Attribute Msg))))
(define (window model)
  (Nil))

(: snapshot (-> (Borrow Model) String))
(define (snapshot model)
  (Model-text model))

;; A storage-like wait owns the live model while a producer completes.
(: checkpoint (-> String Unit ! tasks))
(define (checkpoint saved)
  (yield))

(match (with-memory-dom (list (Hide) (Hide))
                        (lambda () (run-reactor (Model "idle" (None)) (list (Start))
                                                update
                                                view
                                                window
                                                snapshot
                                                (lambda (saved) (unit))
                                                checkpoint)))
  ((Pair model document)
   (write-line (Model-text model))
   (write-line (document->html document))
   (drop model)))
