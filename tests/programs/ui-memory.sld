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
            (append (::items model) (list (Item (::next model) (::draft model))))))
       (Pair (Model items "" (+ (::next model) 1) (::saved model))
             (list (once (lambda ()
                           (yield)
                           (Saved (length items))))))))
    ((Reverse) (Pair (Model-items-set model (reverse (::items model))) (Nil)))
    ((Remove id)
     (Pair (Model-items-set model
                            (filter (lambda (item) (not (= (::id item) id)))
                                    (::items model)))
           (Nil)))
    ((Saved count) (Pair (Model-saved-set model count) (Nil)))))

(: view (-> Model (Html Msg)))
(define (view model)
  (Element "main"
           (Nil)
           (list (Element "input"
                          (list (Attr "id" "draft")
                                (StringProperty "value" (::draft model))
                                (On "input"
                                    (list (Value))
                                    (Allow)
                                    (lambda (event) (Typed (::value event)))))
                          (Nil))
                 (Element "button"
                          (list (Attr "id" "add")
                                (On "click" (Nil) (Always) (lambda (event) (Add))))
                          (list (Text "Add")))
                 (Element "button"
                          (list (Attr "id" "reverse")
                                (On "click" (Nil) (Allow) (lambda (event) (Reverse))))
                          (list (Text "Reverse")))
                 (Element "ul" (Nil) (map item-view (::items model)))
                 (Text (string-append "saved " (show (::saved model)))))))

(: item-view (-> Item (Html Msg)))
(define (item-view item)
  (Element "li"
           (list (Keyed (show (::id item))))
           (list (Text (::text item))
                 (Element "button"
                          (list (Attr "id" (string-append "remove-" (show (::id item))))
                                (On "click" (Nil) (Allow) (lambda (event) (Remove (::id item)))))
                          (list (Text "x"))))))

(: checkpoint (-> Model Unit ! console))
(define (checkpoint model)
  (write-line (string-append "checkpoint: "
                             (string-join (map ::text (::items model)) ", ")
                             "; saved "
                             (show (::saved model)))))

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
                                 (lambda ()
                                   (run-ui (Model (Nil) "" 0 0)
                                           (Nil)
                                           update
                                           view
                                           (lambda (model) (Nil))
                                           (lambda (model) (unit))
                                           checkpoint)))))
           (write-line (string-append "saved " (show (::saved (::first result)))))
           (write-line (document->html (::second result)))
           (for-each write-line (document-trace (::second result)))))))
