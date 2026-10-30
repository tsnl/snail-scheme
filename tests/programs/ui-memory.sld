(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell ui))

;; A list an interface keeps, run over the document in memory with a
;; script of events: typing into a field and adding what was typed, which
;; also starts a command that answers once it has yielded and wakes the
;; interface, hiding the page, which checkpoints the model, reversing the
;; list, and removing an item. The items are keyed, so reversing moves
;; their nodes instead of rewriting them, and the trace shows each change
;; the reconciler made.

(struct Item
  ((id I64)
   (text String)))

(struct Model
  ((items (List Item))
   (draft String)
   (next I64)
   (saved I64)))

(enum Msg
  (Typed ((text String)))
  (Add)
  (Reverse)
  (Remove ((id I64)))
  (Saved ((count I64))))

(: update (-> Model Msg (Pair Model (List (FnOnce Msg ! console tasks)))))
(define (update model message)
  (match message
    ((Typed text) (Pair (Model-draft-set model text) (Nil)))
    ((Add)
     (let ((items
            (append (Model-items model) (list (Item (Model-next model) (Model-draft model))))))
       (Pair (Model items "" (+ (Model-next model) 1) (Model-saved model))
             (list (once (lambda ()
                           (yield)
                           (Saved (length items))))))))
    ((Reverse) (Pair (Model-items-set model (reverse (Model-items model))) (Nil)))
    ((Remove id)
     (Pair (Model-items-set model
                            (filter (lambda (item) (not (= (Item-id item) id)))
                                    (Model-items model)))
           (Nil)))
    ((Saved count) (Pair (Model-saved-set model count) (Nil)))))

(: view (-> Model (Html Msg)))
(define (view model)
  (Element "main"
           (Nil)
           (list (Element "input"
                          (list (Attr "id" "draft")
                                (StringProperty "value" (Model-draft model))
                                (On "input"
                                    (list (Value))
                                    (Allow)
                                    (lambda (event) (Typed (Event-value event)))))
                          (Nil))
                 (Element "button"
                          (list (Attr "id" "add")
                                (On "click" (Nil) (Always) (lambda (event) (Add))))
                          (list (Text "Add")))
                 (Element "button"
                          (list (Attr "id" "reverse")
                                (On "click" (Nil) (Allow) (lambda (event) (Reverse))))
                          (list (Text "Reverse")))
                 (Element "ul" (Nil) (map item-view (Model-items model)))
                 (Text (string-append "saved " (show (Model-saved model)))))))

(: item-view (-> Item (Html Msg)))
(define (item-view item)
  (Element "li"
           (list (Keyed (show (Item-id item))))
           (list (Text (Item-text item))
                 (Element "button"
                          (list (Attr "id" (string-append "remove-" (show (Item-id item))))
                                (On "click" (Nil) (Allow) (lambda (event) (Remove (Item-id item)))))
                          (list (Text "x"))))))

(: checkpoint (-> Model Unit ! console))
(define (checkpoint model)
  (write-line (string-append "checkpoint: "
                             (string-join (map Item-text (Model-items model)) ", ")
                             "; saved "
                             (show (Model-saved model)))))

(: typed (-> String Cue))
(define (typed text)
  (Fire "draft" "input" (Event-value-set no-event text)))

(: clicked (-> String Cue))
(define (clicked target)
  (Fire target "click" no-event))

(: script (List Cue))
(define script
  (list (typed "milk")
        (clicked "add")
        (typed "eggs")
        (clicked "add")
        (typed "tea")
        (clicked "add")
        (Hide)
        (clicked "reverse")
        (clicked "remove-1")))

(dispatch-local
 (once (lambda ()
         (let ((result
                (with-memory-dom script
                                 (lambda () (run-ui (Model (Nil) "" 0 0) update view checkpoint)))))
           (write-line (string-append "saved " (show (Model-saved (Pair-first result)))))
           (write-line (document->html (Pair-second result)))
           (for-each write-line (document-trace (Pair-second result)))))))
