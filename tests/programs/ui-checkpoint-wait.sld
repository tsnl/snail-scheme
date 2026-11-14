(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell ui))

;; A checkpoint may suspend, as a storage write does. A command still
;; running finishes meanwhile, and its answer reaches the model before the
;; document closes.
(record Model
  ((text String)))

(enum Msg
  (Start)
  (Finished ((text String))))

(define (update (model Model) (message Msg)) (→ (Pair Model (List (Fn → Msg ! tasks))))
  (match message
    ((Start)
     (new Pair
       (first (new Model (text "working")))
       (second (list (lambda () (yield) (Finished "finished"))))))
    ((Finished text) (new Pair (first (new Model (text text))) (second (Nil))))))

(define (view (model Model)) (→ (Html Msg))
  (Element "p" (Nil) (list (Text (● model text)))))

(define (window (model Model)) (→ (List (Attribute Msg)))
  (Nil))

(define (checkpoint (model Model)) (→ Unit) (! tasks)
  (yield))

(define (main) (→ Unit) (! host mut output-port tasks)
  (match (with-memory-dom (list (Hide) (Hide))
                          (lambda ()
                            (run-ui (new Model (text "idle"))
                                    (list (Start))
                                    (lambda (model message) (update model message))
                                    (lambda (model) (view model))
                                    (lambda (model) (window model))
                                    (lambda (model) (unit))
                                    (lambda (model) (checkpoint model)))))
    ((Pair model document)
     (write-line (● model text))
     (write-line (document->html document))
     (unit)))
  (unit))
