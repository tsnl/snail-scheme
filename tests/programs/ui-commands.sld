(import
 (only (snail core forms) host)
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
      (Fn → M ! dom tasks))

(define (update (model Model) (message Msg)) (→ (Pair Model (List (Command Msg))))
  (match message
    ((Begin) (new Pair (first model) (second (list began))))
    ((Typed text) (new Pair (first (Model-text-set model text)) (second (Nil))))
    ((Indent) (new Pair (first model) (second (list indent))))
    ((Late) (new Pair (first model) (second (list late))))
    ((Ask) (new Pair (first model) (second (list ask))))
    ((Hide) (new Pair (first (Model-shown-set model #f)) (second (list missing))))
    ((Save) (new Pair (first (logged model "saved")) (second (Nil))))
    ((Online) (new Pair (first (logged model "online")) (second (Nil))))
    ((Done what) (new Pair (first (logged model what)) (second (Nil))))))

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
            (Chords (list (new Chord (key "s") (modifiers (control-key)))))
            (lambda (event) (Save)))))

(define (began) (→ Msg)
  (Done "began"))

(define (starts-with? (prefix String) (line String)) (→ Bool)
  (and (>= (string-length line) (string-length prefix))
       (string=? (substring line 0 (string-length prefix)) prefix)))

(define (clicked (target String)) (→ Cue)
  (Fire target "click" (no-event)))

(define (main) (→ Unit) (! host mut output-port tasks)
  (dispatch-local
   (lambda ()
     (let ((result
            (with-memory-dom
             (list (Fire "text" "input" (Event-value-set (no-event) "(car x)"))
                   (clicked "indent")
                   (FireWindow "keydown"
                               (Event-modifiers-set (Event-key-set (no-event) "s")
                                                    (control-key)))
                   (clicked "late")
                   (clicked "hide")
                   (FireWindow "online" (no-event)))
             (lambda ()
               (run-ui (new Model (text "") (shown #t) (log (Nil)))
                       (list (Begin))
                       (lambda (model message) (update model message))
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
                         (document-trace (● result second)))))))
  (unit))
