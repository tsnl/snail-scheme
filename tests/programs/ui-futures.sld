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

(record Model
  ((text String)
   (pending (Option (Future String)))))

(enum Msg
  (Start))

(define (update (model Model) (message (Option Msg)))
  (→ Model) (! mut host completion tasks)
  (match message
    ((Some (Start))
     (set! (● model pending) (Some (dispatch (lambda () (yield) "finished"))))
     (set! (● model text) "working"))
    ((None) (collect model)))
  model)

(define (collect (model Model)) (→ Unit) (! mut)
  (match (● model pending)
    ((None) (unit))
    ((Some future)
     (match (poll future)
       ((Pending) (unit))
       ((Ready text)
        (set! (● model pending) (None))
        (set! (● model text) text))))))

(define (view (model Model)) (→ (Html Msg))
  (Element "p" (Nil) (list (Text (● model text)))))

(define (window (model Model)) (→ (List (Attribute Msg)))
  (Nil))

(define (snapshot (model Model)) (→ String)
  (● model text))

;; A storage-like wait suspends the loop while a producer completes.
(define (checkpoint (saved String)) (→ Unit) (! tasks)
  (yield))

(define (main) (→ Unit) (! host mut output-port tasks)
  (match (with-memory-dom (list (Hide) (Hide))
                          (lambda ()
                            (run-reactor (new Model
                                           (text "idle")
                                           (pending (None)))
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
     (unit)))
  (unit))
