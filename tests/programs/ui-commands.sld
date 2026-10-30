(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell ui))

;; Commands reaching the view's nodes by id, over the document in memory.
;; Indenting inserts two spaces at the start of the field, as typing would,
;; so the field's input event brings the model's text up to date, then
;; selects after them, focuses the field and measures it. A late edit finds
;; the field, waits, and inserts after the view has removed the field, so
;; its insertion does nothing and its trace line says so; once the field is
;; gone, looking it up finds nothing.

(struct Model
  ((text String)
   (shown Bool)
   (log (List String))))

(enum Msg
  (Typed ((text String)))
  (Indent)
  (Late)
  (Hide)
  (Done ((what String))))

(type (Command M)
      (FnOnce M ! dom tasks))

(: update (-> Model Msg (Pair Model (List (Command Msg)))))
(define (update model message)
  (match message
    ((Typed text) (Pair (Model-text-set model text) (Nil)))
    ((Indent) (Pair model (list (once indent))))
    ((Late) (Pair model (list (once late))))
    ((Hide) (Pair (Model-shown-set model #f) (list (once missing))))
    ((Done what) (Pair (Model-log-set model (append (Model-log model) (list what))) (Nil)))))

(: indent (-> Msg ! dom))
(define (indent)
  (match (element-by-id "text")
    ((Some node)
     (insert-text node 0 0 "  ")
     (select-range node 2 2)
     (focus-node node)
     (Done (string-append "indented, line height " (show (Measure-line-height (measure node))))))
    ((None) (Done "no field"))))

(: late (-> Msg ! dom tasks))
(define (late)
  (match (element-by-id "text")
    ((Some node)
     (yield)
     (yield)
     (insert-text node 0 0 "late ")
     (Done (string-append "late, value " (show (string-length (string-property node "value"))))))
    ((None) (Done "no field"))))

(: missing (-> Msg ! dom))
(define (missing)
  (match (element-by-id "text")
    ((Some node) (Done "still there"))
    ((None) (Done "field gone"))))

(: view (-> Model (Html Msg)))
(define (view model)
  (Element "div"
           (Nil)
           (append (if (Model-shown model)
                       (list (Element "textarea"
                                      (list (Keyed "text")
                                            (Attr "id" "text")
                                            (StringProperty "value" (Model-text model))
                                            (On "input"
                                                (list (Value))
                                                (Allow)
                                                (lambda (event) (Typed (Event-value event)))))
                                      (Nil)))
                       (Nil))
                   (list (Element "button"
                                  (list (Attr "id" "indent")
                                        (On "click" (Nil) (Allow) (lambda (event) (Indent))))
                                  (Nil))
                         (Element "button"
                                  (list (Attr "id" "late")
                                        (On "click" (Nil) (Allow) (lambda (event) (Late))))
                                  (Nil))
                         (Element "button"
                                  (list (Attr "id" "hide")
                                        (On "click" (Nil) (Allow) (lambda (event) (Hide))))
                                  (Nil))))))

(: starts-with? (-> String String Bool))
(define (starts-with? prefix line)
  (and (>= (string-length line) (string-length prefix))
       (string=? (substring line 0 (string-length prefix)) prefix)))

(: clicked (-> String Cue))
(define (clicked target)
  (Fire target "click" no-event))

(dispatch-local
 (once (lambda ()
         (let ((result
                (with-memory-dom (list (Fire "text" "input" (Event-value-set no-event "(car x)"))
                                       (clicked "indent")
                                       (clicked "late")
                                       (clicked "hide"))
                                 (lambda ()
                                   (run-ui (Model "" #t (Nil))
                                           update
                                           view
                                           (lambda (model) (unit)))))))
           (write-line (string-append "text: " (Model-text (Pair-first result))))
           (for-each write-line (Model-log (Pair-first result)))
           (write-line (document->html (Pair-second result)))
           (for-each write-line
                     (filter (lambda (line)
                               (not (or (starts-with? "create" line)
                                        (starts-with? "insert " line)
                                        (starts-with? "listen" line)
                                        (starts-with? "set-attribute" line))))
                             (document-trace (Pair-second result))))))))
