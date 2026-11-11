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

(define (update (model Model) (message (Option Msg))) (→ Model) (! mut completion)
  (match model
    ((Model text pending)
     (match message
       ((Some (Start))
        (drop pending)
        (Model "working" (Some (dispatch (once (lambda () (yield) "finished"))))))
       ((None) (collect text pending))))))

(define (collect (text String) (pending (Option (Future String)))) (→ Model) (! mut)
  (match pending
    ((None) (Model text (None)))
    ((Some future)
     (match (poll future)
       ((Pending future) (Model text (Some future)))
       ((Ready (Completed text)) (Model text (None)))
       ((Ready (Abandoned)) (Model "canceled" (None)))))))

(define (view (model (Borrow Model))) (→ (Html Msg))
  (Element "p" (Nil) (list (Text (● model text)))))

(define (window (model (Borrow Model))) (→ (List (Attribute Msg)))
  (Nil))

(define (snapshot (model (Borrow Model))) (→ String)
  (● model text))

;; A storage-like wait owns the live model while a producer completes.
(define (checkpoint (saved String)) (→ Unit) (! tasks)
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
   (write-line (● model text))
   (write-line (document->html document))
   (drop model)))
