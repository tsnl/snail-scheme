(import
 (only (snail core forms) host)
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

(record Item
  ((id I64)
   (text String)))

(record Model
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

(define (update (model Model) (message Msg))
  (→ (Pair Model (List (Fn → Msg ! output-port tasks))))
  (match message
    ((Typed text) (new Pair (first (Model-draft-set model text)) (second (Nil))))
    ((Add)
     (let ((items
            (append (● model items) (list (new Item (id (● model next)) (text (● model draft)))))))
       (new Pair
         (first
          (new Model (items items) (draft "") (next (+ (● model next) 1)) (saved (● model saved))))
         (second (list (lambda ()
                         (yield)
                         (Saved (length items))))))))
    ((Reverse) (new Pair (first (Model-items-set model (reverse (● model items)))) (second (Nil))))
    ((Remove id)
     (new Pair (first (Model-items-set model
                                       (filter (lambda (item) (not (= (● item id) id)))
                                               (● model items))))
          (second (Nil))))
    ((Saved count) (new Pair (first (Model-saved-set model count)) (second (Nil))))))

(define (view (model Model)) (→ (Html Msg))
  (Element "main"
           (Nil)
           (list (Element "input"
                          (list (Attr "id" "draft")
                                (StringProperty "value" (● model draft))
                                (On "input"
                                    (list (Value))
                                    (Allow)
                                    (lambda (event) (Typed (● event value)))))
                          (Nil))
                 (Element "button"
                          (list (Attr "id" "add")
                                (On "click" (Nil) (Always) (lambda (event) (Add))))
                          (list (Text "Add")))
                 (Element "button"
                          (list (Attr "id" "reverse")
                                (On "click" (Nil) (Allow) (lambda (event) (Reverse))))
                          (list (Text "Reverse")))
                 (Element "ul" (Nil) (map item-view (● model items)))
                 (Text (string-append "saved " (show (● model saved)))))))

(define (item-view (item Item)) (→ (Html Msg))
  (Element "li"
           (list (Keyed (show (● item id))))
           (list (Text (● item text))
                 (Element "button"
                          (list (Attr "id" (string-append "remove-" (show (● item id))))
                                (On "click" (Nil) (Allow) (lambda (event) (Remove (● item id)))))
                          (list (Text "x"))))))

(define (checkpoint (model Model)) (→ Unit) (! output-port)
  (write-line (string-append "checkpoint: "
                             (string-join (map (lambda (record) (● record text)) (● model items))
                                          ", ")
                             "; saved "
                             (show (● model saved)))))

(define (typed (text String)) (→ Cue)
  (Fire "draft" "input" (Event-value-set (no-event) text)))

(define (clicked (target String)) (→ Cue)
  (Fire target "click" (no-event)))

(define (script) (→ (List Cue))
  (list (typed "milk")
        (clicked "add")
        (typed "eggs")
        (clicked "add")
        (typed "tea")
        (clicked "add")
        (Hide)
        (clicked "reverse")
        (clicked "remove-1")))

(define (main) (→ Unit) (! host mut output-port tasks)
  (dispatch
   (lambda ()
     (let ((result
            (with-memory-dom (script)
                             (lambda ()
                               (run-ui (new Model (items (Nil)) (draft "") (next 0) (saved 0))
                                       (Nil)
                                       (lambda (model message) (update model message))
                                       view
                                       (lambda (model) (Nil))
                                       (lambda (model) (unit))
                                       checkpoint)))))
       (write-line (string-append "saved " (show (● (● result first) saved))))
       (write-line (document->html (● result second)))
       (for-each write-line (document-trace (● result second))))))
  (unit))
