(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell async)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell ui))

(record PendingWork
  ((future (Option (Future String)))))

(record Model
  ((text String)
   (pending (Rc PendingWork))))

(enum Msg
  (Start))

(define (update (model Model) (message (Option Msg)))
  (→ Model) (! mut host completion tasks)
  (match message
    ((Some (Start))
     (drop
      (replace! (● model pending future) (Some (dispatch (once (lambda () (yield) "finished"))))))
     (set! (● model text) "working"))
    ((None) (collect model)))
  model)

(define (collect (model Model)) (→ Unit) (! mut host)
  (match (replace! (● model pending future) (None))
    ((None) (unit))
    ((Some future)
     (match (poll future)
       ((Pending future) (drop (replace! (● model pending future) (Some future))))
       ((Ready (Completed text)) (set! (● model text) text))
       ((Ready (Abandoned)) (set! (● model text) "canceled"))))))

(define (view (model Model)) (→ (Html Msg)) (! mut host)
  (Element "p" (Nil) (list (Text (● model text)))))

(define (window (model Model)) (→ (List (Attribute Msg))) (! mut host)
  (Nil))

(define (snapshot (model Model)) (→ String) (! mut host)
  (● model text))

;; A storage-like wait owns the live model while a producer completes.
(define (checkpoint (saved String)) (→ Unit) (! tasks)
  (yield))

(define (main) (→ Unit) (! host mut output-port completion tasks)
  (match (with-memory-dom (list (Hide) (Hide))
                          (lambda ()
                            (run-reactor (new Model
                                           (text "idle")
                                           (pending (rc (new PendingWork (future (None))))))
                                         (list (Start))
                                         (lambda (model msg) (update model msg))
                                         (lambda (model) (view model))
                                         (lambda (model) (window model))
                                         (lambda (model) (snapshot model))
                                         (lambda (saved) (unit))
                                         (lambda (saved) (checkpoint saved)))))
    ((Pair model document)
     (write-line (● model text))
     (write-line (document->html document))
     (drop model)))
  (unit))
