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
      (FnOnce → M ! dom tasks))

(define (update (model Model) (message Msg)) (→ (Pair Model (List (Command Msg))))
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

(define (logged (model Model) (what String)) (→ Model)
  (Model-log-set model (append (● model log) (list what))))

(define (indent) (→ Msg) (! dom)
  (match (element-by-id "text")
    ((Some node)
     (let ((took (insert-text node 0 0 "  ")))
       (select-range node 2 2)
       (focus-node node)
       (Done (string-append "indented: "
                            (if took "taken" "refused")
                            ", selection "
                            (show (● (selection-range node) first))
                            "-"
                            (show (● (selection-range node) second))
                            ", line height "
                            (show (● (measure node) line-height))))))
    ((None) (Done "no field"))))

(define (late) (→ Msg) (! dom tasks)
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

(define (ask) (→ Msg) (! dom)
  (if (confirm "Hide the field?") (Hide) (Done "kept")))

(define (missing) (→ Msg) (! dom)
  (match (element-by-id "text")
    ((Some node) (Done "still there"))
    ((None) (Done "field gone"))))

(define (view (model Model)) (→ (Html Msg))
  (Element "div"
           (Nil)
           (append (if (● model shown)
                       (list (Element "textarea"
                                      (list (Keyed "text")
                                            (Attr "id" "text")
                                            (StringProperty "value" (● model text))
                                            (On "input"
                                                (list (Value))
                                                (Allow)
                                                (lambda (event) (Typed (● event value)))))
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

(define (window (model Model)) (→ (List (Attribute Msg)))
  (list (On "online" (Nil) (Allow) (lambda (event) (Online)))
        (On "keydown"
            (list (Key))
            (Chords (list (Chord "s" control-key)))
            (lambda (event) (Save)))))

(define (began) (→ Msg)
  (Done "began"))

(define (starts-with? (prefix String) (line String)) (→ Bool)
  (and (>= (string-length line) (string-length prefix))
       (string=? (substring line 0 (string-length prefix)) prefix)))

(define (clicked (target String)) (→ Cue)
  (Fire target "click" no-event))

(define main
  (lambda ()
    (dispatch-local
     (once (lambda ()
             (let ((result
                    (with-memory-dom
                     (list (Fire "text" "input" (Event-value-set no-event "(car x)"))
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
                               (lambda (model) (unit))
                               (lambda (model) (unit)))))))
               (write-line (string-append "text: " (● (● result first) text)))
               (for-each write-line (● (● result first) log))
               (write-line (document->html (● result second)))
               (for-each write-line
                         (filter (lambda (line)
                                   (not (or (starts-with? "create" line)
                                            (starts-with? "insert " line)
                                            (starts-with? "listen" line)
                                            (starts-with? "set-attribute" line))))
                                 (document-trace (● result second))))))))
    (unit)))
