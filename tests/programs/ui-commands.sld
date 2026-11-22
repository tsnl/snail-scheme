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

(record Model
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
      (Fn → M))

(define (update (dom Dom) (model Model) (message Msg)) (→ (Pair Model (List (Command Msg))))
  (match message
    ((Begin) (new Pair (first model) (second (list began))))
    ((Typed text) (new Pair (first (Model-text-set model text)) (second (Nil))))
    ((Indent) (new Pair (first model) (second (list (lambda () (indent dom))))))
    ((Late) (new Pair (first model) (second (list (lambda () (late dom))))))
    ((Ask) (new Pair (first model) (second (list (lambda () (ask dom))))))
    ((Hide) (new Pair (first (Model-shown-set model #f)) (second (list (lambda () (missing dom))))))
    ((Save) (new Pair (first (logged model "saved")) (second (Nil))))
    ((Online) (new Pair (first (logged model "online")) (second (Nil))))
    ((Done what) (new Pair (first (logged model what)) (second (Nil))))))

(define (logged (model Model) (what String)) (→ Model)
  (Model-log-set model (append (● model log) (list what))))

(define (indent (dom Dom)) (→ Msg)
  (match (element-by-id dom "text")
    ((Some node)
     (let ((took (insert-text dom node 0 0 "  ")))
       (select-range dom node 2 2)
       (focus-node dom node)
       (Done (string-append "indented: "
                            (if took "taken" "refused")
                            ", selection "
                            (show (● (selection-range dom node) first))
                            "-"
                            (show (● (selection-range dom node) second))
                            ", line height "
                            (show (● (measure dom node) line-height))))))
    ((None) (Done "no field"))))

(define (late (dom Dom)) (→ Msg)
  (match (element-by-id dom "text")
    ((Some node)
     (yield)
     (yield)
     (let ((took (insert-text dom node 0 0 "late ")))
       (Done (string-append "late: "
                            (if took "taken" "refused")
                            ", value "
                            (show (string-length (string-property dom node "value")))))))
    ((None) (Done "no field"))))

(define (ask (dom Dom)) (→ Msg)
  (if (confirm dom "Hide the field?") (Hide) (Done "kept")))

(define (missing (dom Dom)) (→ Msg)
  (match (element-by-id dom "text")
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
            (Chords (list (new Chord (key "s") (modifiers control-key))))
            (lambda (event) (Save)))))

(define (began) (→ Msg)
  (Done "began"))

(define (starts-with? (prefix String) (line String)) (→ Bool)
  (and (>= (string-length line) (string-length prefix))
       (string=? (substring line 0 (string-length prefix)) prefix)))

(define (clicked (target String)) (→ Cue)
  (Fire target "click" no-event))

(define (main (out OutputPort)) (→ Unit)
  (dispatch
   (lambda ()
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
             (lambda (dom)
               (run-ui dom (new Model (text "") (shown #t) (log (Nil)))
                       (list (Begin))
                       (lambda (model message) (update dom model message))
                       view
                       window
                       (lambda (model) (unit))
                       (lambda (model) (unit)))))))
       (write-line out (string-append "text: " (● (● result first) text)))
       (for-each (lambda (text) (write-line out text)) (● (● result first) log))
       (write-line out (document->html (● result second)))
       (for-each (lambda (text) (write-line out text))
                 (filter (lambda (line)
                           (not (or (starts-with? "create" line)
                                    (starts-with? "insert " line)
                                    (starts-with? "listen" line)
                                    (starts-with? "set-attribute" line))))
                         (document-trace (● result second)))))))
  (unit))
