(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell ui))

;; Commands reaching the view's nodes by id, over the document in memory.
;; The interface starts with a message whose command answers at once.
;; Indenting inserts two spaces at the start of the field, as typing would,
;; so the field's input event brings the model's text up to date, then
;; selects after them, reads the selection back, focuses the field and
;; measures it. A late edit finds
;; the field, waits, and inserts after the view has removed the field, so
;; its insertion does nothing, its trace line says so, and it answers that
;; the field did not take it; once the field is gone, looking it up finds
;; nothing. Hiding asks first. The window hears Control-S, and no other
;; key, and the page going back online.

(struct Model
  ((text String)
   (shown Bool)
   (log (List String))))

(enum Msg
  (Begin)
  (Typed ((text String)))
  (Indent)
  (Late)
  (Ask)
  (Hide)
  (Save)
  (Online)
  (Done ((what String))))

(type (Command M)
      (FnOnce M ! dom tasks))

(: update (-> Model Msg (Pair Model (List (Command Msg)))))
(define (update model message)
  (match message
    ((Begin) (Pair model (list (once began))))
    ((Typed text) (Pair (Model-text-set model text) (Nil)))
    ((Indent) (Pair model (list (once indent))))
    ((Late) (Pair model (list (once late))))
    ((Ask) (Pair model (list (once ask))))
    ((Hide) (Pair (Model-shown-set model #f) (list (once missing))))
    ((Save) (Pair (logged model "saved") (Nil)))
    ((Online) (Pair (logged model "online") (Nil)))
    ((Done what) (Pair (logged model what) (Nil)))))

(: logged (-> Model String Model))
(define (logged model what)
  (Model-log-set model (append (Model-log model) (list what))))

(: indent (-> Msg ! dom))
(define (indent)
  (match (element-by-id "text")
    ((Some node)
     (let ((took (insert-text node 0 0 "  ")))
       (select-range node 2 2)
       (focus-node node)
       (Done (string-append "indented: "
                            (if took "taken" "refused")
                            ", selection "
                            (show (Pair-first (selection-range node)))
                            "-"
                            (show (Pair-second (selection-range node)))
                            ", line height "
                            (show (Measure-line-height (measure node)))))))
    ((None) (Done "no field"))))

(: late (-> Msg ! dom tasks))
(define (late)
  (match (element-by-id "text")
    ((Some node)
     (yield)
     (yield)
     (let ((took (insert-text node 0 0 "late ")))
       (Done (string-append "late: "
                            (if took "taken" "refused")
                            ", value "
                            (show (string-length (string-property node "value")))))))
    ((None) (Done "no field"))))

(: ask (-> Msg ! dom))
(define (ask)
  (if (confirm "Hide the field?") (Hide) (Done "kept")))

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
                                        (On "click" (Nil) (Allow) (lambda (event) (Ask))))
                                  (Nil))))))

(: window (-> Model (List (Attribute Msg))))
(define (window model)
  (list (On "online" (Nil) (Allow) (lambda (event) (Online)))
        (On "keydown"
            (list (Key))
            (Chords (list (Chord "s" control-key)))
            (lambda (event) (Save)))))

(: began (-> Msg))
(define (began)
  (Done "began"))

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
                                       (FireWindow "keydown"
                                                   (Event-modifiers-set (Event-key-set no-event "s")
                                                                        control-key))
                                       (clicked "late")
                                       (clicked "hide")
                                       (FireWindow "online" no-event))
                                 (lambda ()
                                   (run-ui (Model "" #t (Nil))
                                           (list (Begin))
                                           update
                                           view
                                           window
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
