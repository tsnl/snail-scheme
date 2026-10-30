;; A document in memory for the `dom` effect, so an interface runs, and is
;; tested, without a page. `with-memory-dom` handles the effect around its
;; work and answers the work's value with the document it left: its tree,
;; which `document->html` prints, and the trace of every operation, one
;; line each. Its events are a script, delivered in turn as the work
;; waits for them: firing a listener on the element with an `id` or on
;; the window, or hiding the page. The input events of inserted text and
;; then a `wake` are delivered before the script goes on, in the order a
;; page would queue them, and once the script is done and nothing waits,
;; the document is closed.
;; As a page delivers only between the tasks it runs, each delivery waits
;; until every other ready task has run, so it finds the document as they
;; left it.
;;
;; The document is strict where a page would forgive: a node the
;; reconciler uses after it was removed, a listener dropped after its node
;; was, a node inserted into itself, or a key fired at a listener that
;; does not hear it, is a panic, so the tests of an interface catch what a
;; page would hide. What a command may do after the view removed its node
;; (focus, properties, selection, inserting text and measuring) does
;; nothing then, as on a page, and its trace line ends "(removed)". Inserting text delivers the field's `input` event, as
;; typing would. The person always agrees to what `confirm` asks.
(define-library (snail shell dom memory)
  (export
   Document
   Cue
   Fire
   FireWindow
   Hide
   document-trace
   document->html
   with-memory-dom)
  (import
   (snail core base)
   (snail core table)
   (snail shell datum)
   (snail shell write)
   (only (snail shell task) tasks yield)
   (snail shell dom))
  (begin

    ;; ---- Documents ----

    ;; A node: an element's tag, or "#text"; its text, when it is a text
    ;; node; its attributes and properties in the order first set; its
    ;; children; its parent, -1 when it is detached; the listeners on it;
    ;; and whether its handle is still live.
    (struct Entry
      ((tag String)
       (text String)
       (attributes (List (Pair String String)))
       (properties (List (Pair String Property)))
       (children (List I32))
       (parent I32)
       (listeners (List Hearing))
       (live Bool)))

    ;; A listener: its id, its event, and its prevention, which says which
    ;; keys it hears.
    (struct Hearing
      ((id I32)
       (event String)
       (prevent Prevent)))

    (enum Property
      (Text ((value String)))
      (Number ((value F64)))
      (Flag ((value Bool))))

    ;; Every node made, by handle; the node each listener is on, by its id;
    ;; the next handle and listener id; and the trace's lines, newest
    ;; first. Handle 0 is the root, and -1 the window, which holds only
    ;; listeners.
    (struct Document
      ((entries (Table Entry))
       (owners (Table I32))
       (next I32)
       (next-listener I32)
       (lines (List String))))

    (: empty-document Document)
    (define empty-document
      (Document (table-set (table-set empty-table "0" (new-entry "#root" ""))
                           "-1"
                           (new-entry "#window" ""))
                empty-table
                1
                1
                (Nil)))

    (: new-entry (-> String String Entry))
    (define (new-entry tag text)
      (Entry tag text (Nil) (Nil) (Nil) -1 (Nil) #t))

    ;; The trace, a line per operation, oldest first.
    (: document-trace (-> Document (List String)))
    (define (document-trace document)
      (reverse (Document-lines document)))

    (: entry (-> Document I32 Entry))
    (define (entry document handle)
      (match (table-ref (Document-entries document) (show handle))
        ((Some found)
         (if (Entry-live found)
             found
             (panic (string-append "the node " (show handle) " was removed"))))
        ((None) (panic (string-append "no node has the handle " (show handle))))))

    (: put (-> Document I32 Entry Document))
    (define (put document handle changed)
      (Document-entries-set document
                            (table-set (Document-entries document) (show handle) changed)))

    (: traced (-> Document (List String) Document))
    (define (traced document words)
      (Document-lines-set document (Cons (string-join words " ") (Document-lines document))))

    (: quoted (-> String String))
    (define (quoted text)
      (datum->string (StringDatum text)))

    ;; ---- Operations ----

    (: created (-> Document String String (Pair Node Document)))
    (define (created document tag text)
      (let ((made (made document tag text)))
        (Pair (Pair-first made)
              (traced (Pair-second made)
                      (if (string=? tag "#text")
                          (list "create-text" (show (Node-handle (Pair-first made))) (quoted text))
                          (list "create-element" (show (Node-handle (Pair-first made))) tag))))))

    (: made (-> Document String String (Pair Node Document)))
    (define (made document tag text)
      (let ((handle (Document-next document)))
        (Pair (Node handle)
              (Document-next-set (put document handle (new-entry tag text)) (+ handle 1)))))

    (: attribute-set (-> Document Node String String Document))
    (define (attribute-set document node name value)
      (let* ((handle (Node-handle node)) (changed (entry document handle)))
        (traced (put document
                     handle
                     (Entry-attributes-set changed
                                           (assigned (Entry-attributes changed)
                                                     name
                                                     (if (string=? value "") (None) (Some value)))))
                (list "set-attribute" (show handle) name (quoted value)))))

    ;; `pairs` with `name` given `value`, in place when it is there and last
    ;; when it is new, or without it.
    (: assigned
       (All (V)
            (requires (Copy V))
            (-> (List (Pair String V)) String (Option V) (List (Pair String V)))))
    (define (assigned pairs name value)
      (let ((others (filter (lambda (pair) (not (string=? (Pair-first pair) name))) pairs)))
        (match value
          ((None) others)
          ((Some value)
           (if (any? (lambda (pair) (string=? (Pair-first pair) name)) pairs)
               (map (lambda (pair) (if (string=? (Pair-first pair) name) (Pair name value) pair))
                    pairs)
               (append pairs (list (Pair name value))))))))

    ;; An element's text replaces its children, whose handles are freed,
    ;; with one text node of its own.
    (: text-set (-> Document Node String Document))
    (define (text-set document node text)
      (let ((handle (Node-handle node)))
        (traced (if (string=? (Entry-tag (entry document handle)) "#text")
                    (put document handle (Entry-text-set (entry document handle) text))
                    (element-text-set document handle text))
                (list "set-text" (show handle) (quoted text)))))

    (: element-text-set (-> Document I32 String Document))
    (define (element-text-set document handle text)
      (let* ((cleared (fold-left freed document (Entry-children (entry document handle))))
             (child (made cleared "#text" text))
             (text-handle (Node-handle (Pair-first child)))
             (document (Pair-second child)))
        (put (put document text-handle (Entry-parent-set (entry document text-handle) handle))
             handle
             (Entry-children-set (entry document handle) (list text-handle)))))

    (: property-set (-> Document Node String Property Document))
    (define (property-set document node name value)
      (commanded document
                 node
                 (list "set-property" (show (Node-handle node)) name (property->string value))
                 (lambda (changed)
                   (Entry-properties-set changed
                                         (assigned (Entry-properties changed) name (Some value))))))

    (: property->string (-> Property String))
    (define (property->string property)
      (match property
        ((Text value) (quoted value))
        ((Number value) (show value))
        ((Flag value) (if value "true" "false"))))

    (: property-of (-> Document Node String (Option Property)))
    (define (property-of document node name)
      (match (live document (Node-handle node))
        ((Some found)
         (match (find (lambda (pair) (string=? (Pair-first pair) name)) (Entry-properties found))
           ((Some pair) (Some (Pair-second pair)))
           ((None) (None))))
        ((None) (None))))

    ;; A child inserted where it is, or into a node under it, would leave
    ;; the tree; a child elsewhere moves.
    (: inserted (-> Document Node Node (Option Node) Document))
    (define (inserted document parent child before)
      (let ((into (Node-handle parent)) (moved (Node-handle child)))
        (when (or (= into moved) (under? document into moved))
          (panic (string-append "the node " (show moved) " cannot go inside itself")))
        (let* ((detached (detached document moved))
               (siblings (filter (lambda (sibling) (not (= sibling moved)))
                                 (Entry-children (entry detached into))))
               (placed (match before
                         ((Some node) (insert-before siblings (Node-handle node) moved))
                         ((None) (append siblings (list moved))))))
          (traced (put (put detached into (Entry-children-set (entry detached into) placed))
                       moved
                       (Entry-parent-set (entry detached moved) into))
                  (append (list "insert" (show moved) "into" (show into))
                          (match before
                            ((Some node) (list "before" (show (Node-handle node))))
                            ((None) (Nil))))))))

    (: insert-before (-> (List I32) I32 I32 (List I32)))
    (define (insert-before siblings before moved)
      (match siblings
        ((Cons first rest)
         (if (= first before)
             (Cons moved siblings)
             (Cons first (insert-before rest before moved))))
        ((Nil) (panic (string-append "the node " (show before) " is not a child there")))))

    ;; Whether `handle` lies under `ancestor`.
    (: under? (-> Document I32 I32 Bool))
    (define (under? document handle ancestor)
      (let ((parent (Entry-parent (entry document handle))))
        (and (>= parent 0) (or (= parent ancestor) (under? document parent ancestor)))))

    (: detached (-> Document I32 Document))
    (define (detached document handle)
      (let ((parent (Entry-parent (entry document handle))))
        (if (< parent 0)
            document
            (put (put document
                      parent
                      (Entry-children-set (entry document parent)
                                          (filter (lambda (child) (not (= child handle)))
                                                  (Entry-children (entry document parent)))))
                 handle
                 (Entry-parent-set (entry document handle) -1)))))

    ;; A removed node leaves its parent, and its handle and those under it
    ;; are freed.
    (: removed (-> Document Node Document))
    (define (removed document node)
      (let ((handle (Node-handle node)))
        (traced (freed (detached document handle) handle) (list "remove" (show handle)))))

    (: freed (-> Document I32 Document))
    (define (freed document handle)
      (let ((gone (entry document handle)))
        (put
         (fold-left (lambda (document child) (freed document child)) document (Entry-children gone))
         handle
         (Entry-live-set gone #f))))

    (: listened (-> Document Node String (List Capture) Prevent (Pair Listener Document)))
    (define (listened document node event captures prevent)
      (let* ((handle (Node-handle node))
             (id (Document-next-listener document))
             (on (entry document handle)))
        (Pair (Listener id)
              (traced (Document-owners-set
                       (Document-next-listener-set
                        (put document
                             handle
                             (Entry-listeners-set on
                                                  (append (Entry-listeners on)
                                                          (list (Hearing id event prevent)))))
                        (+ id 1))
                       (table-set (Document-owners document) (show id) handle))
                      (list "listen"
                            (show handle)
                            event
                            (string-append "#" (show id))
                            (show (capture-bits captures))
                            (prevent->string prevent))))))

    (: prevent->string (-> Prevent String))
    (define (prevent->string prevent)
      (match prevent
        ((Allow) "allow")
        ((Always) "always")
        ((Chords chords)
         (string-append "chords"
                        (string-concatenate
                         (map (lambda (chord)
                                (string-append " "
                                               (show (Chord-modifiers chord))
                                               "+"
                                               (quoted (Chord-key chord))))
                              chords))))))

    ;; A listener goes with its node, so its node must be there.
    (: unlistened (-> Document Listener Document))
    (define (unlistened document listener)
      (let* ((id (Listener-id listener))
             (handle (match (table-ref (Document-owners document) (show id))
                       ((Some handle) handle)
                       ((None) (panic (string-append "no listener has the id " (show id))))))
             (on (entry document handle)))
        (traced (put document
                     handle
                     (Entry-listeners-set on
                                          (filter
                                           (lambda (hearing) (not (= (Hearing-id hearing) id)))
                                           (Entry-listeners on))))
                (list "unlisten" (string-append "#" (show id))))))

    ;; ---- Events ----

    ;; A step of the script: an event to fire at the listener for `event`
    ;; on the element whose `id` attribute is `target`, or on the window,
    ;; carrying `data`, or the page hidden.
    (enum Cue
      (Fire ((target String)
             (event String)
             (data Event)))
      (FireWindow ((event String)
                   (data Event)))
      (Hide))

    ;; A cue's delivery.
    (: cued (-> Document Cue (Pair Delivery Document)))
    (define (cued document cue)
      (match cue
        ((Fire target event data) (fired document target (target-entry document target) event data))
        ((FireWindow event data) (fired document "window" (entry document -1) event data))
        ((Hide) (Pair (Hidden) (traced document (list "hide"))))))

    ;; The listener a scripted event fires, which must be there, and must
    ;; hear its key when it hears only chords.
    (: fired (-> Document String Entry String Event (Pair Delivery Document)))
    (define (fired document target on event data)
      (match (find (lambda (hearing) (string=? (Hearing-event hearing) event)) (Entry-listeners on))
        ((Some hearing)
         (unless (hears? (Hearing-prevent hearing) data)
           (panic
            (string-append "the " event " listener on " target " does not hear " (Event-key data))))
         (Pair (Fired (Listener (Hearing-id hearing)) data)
               (traced document
                       (list "fire" target event (string-append "#" (show (Hearing-id hearing)))))))
        ((None) (panic (string-append "nothing listens for " event " on " target)))))

    (: hears? (-> Prevent Event Bool))
    (define (hears? prevent data)
      (match prevent
        ((Chords chords)
         (any? (lambda (chord)
                 (and (string=? (Chord-key chord) (Event-key data))
                      (= (Chord-modifiers chord) (Event-modifiers data))))
               chords))
        (_ #t)))

    (: target-entry (-> Document String Entry))
    (define (target-entry document target)
      (match (element-handle document target 0)
        ((Some handle) (entry document handle))
        ((None) (panic (string-append "no element has the id " target)))))

    ;; ---- Commands ----

    ;; A node, unless it was removed.
    (: live (-> Document I32 (Option Entry)))
    (define (live document handle)
      (match (table-ref (Document-entries document) (show handle))
        ((Some found) (if (Entry-live found) (Some found) (None)))
        ((None) (panic (string-append "no node has the handle " (show handle))))))

    ;; A command's change to a node, traced by `words`, or the trace alone
    ;; when the node was removed.
    (: commanded (-> Document Node (List String) (-> Entry Entry) Document))
    (define (commanded document node words change)
      (let ((handle (Node-handle node)))
        (match (live document handle)
          ((Some found) (traced (put document handle (change found)) words))
          ((None) (traced document (append words (list "(removed)")))))))

    ;; The first node from `handle` on whose `id` is `target`.
    (: element-handle (-> Document String I32 (Option I32)))
    (define (element-handle document target handle)
      (cond ((>= handle (Document-next document)) (None))
            ((match (live document handle)
               ((Some found)
                (any? (lambda (pair)
                        (and (string=? (Pair-first pair) "id")
                             (string=? (Pair-second pair) target)))
                      (Entry-attributes found)))
               ((None) #f))
             (Some handle))
            (else (element-handle document target (+ handle 1)))))

    (: selected (-> Document Node I32 I32 Document))
    (define (selected document node start end)
      (commanded document
                 node
                 (list "select" (show (Node-handle node)) (show start) (show end))
                 (lambda (found) (selection-set found start end))))

    (: selection-set (-> Entry I32 I32 Entry))
    (define (selection-set found start end)
      (Entry-properties-set found
                            (assigned (assigned (Entry-properties found)
                                                "selectionStart"
                                                (Some (Number (i32->f64 start))))
                                      "selectionEnd"
                                      (Some (Number (i32->f64 end))))))

    ;; The field's value with the range replaced by `text`, and the caret
    ;; after it.
    (: text-inserted (-> Document Node I32 I32 String Document))
    (define (text-inserted document node start end text)
      (commanded document
                 node
                 (list "insert-text"
                       (show (Node-handle node))
                       (show start)
                       (show end)
                       (quoted text))
                 (lambda (found)
                   (let* ((value (match (find (lambda (pair) (string=? (Pair-first pair) "value"))
                                              (Entry-properties found))
                                   ((Some (Pair _ (Text value))) value)
                                   (_ "")))
                          (changed (string-append (substring value 0 (i32->i64 start))
                                                  text
                                                  (substring value
                                                             (i32->i64 end)
                                                             (string-length value))))
                          (caret (+ start (i64->i32 (string-length text)))))
                     (selection-set (Entry-properties-set found
                                                          (assigned (Entry-properties found)
                                                                    "value"
                                                                    (Some (Text changed))))
                                    caret
                                    caret)))))

    ;; The `input` event a field's listener hears after text is inserted
    ;; into it.
    (: input-fired (-> Document Node (Option Delivery)))
    (define (input-fired document node)
      (match (live document (Node-handle node))
        ((Some found)
         (match (find (lambda (hearing) (string=? (Hearing-event hearing) "input"))
                      (Entry-listeners found))
           ((Some hearing)
            (Some (Fired (Listener (Hearing-id hearing))
                         (Event-value-set no-event
                                          (match (property-of document node "value")
                                            ((Some (Text value)) value)
                                            (_ ""))))))
           ((None) (None))))
        ((None) (None))))

    ;; A document in memory has no layout: every measure is 0.
    (: measured (-> Document Node (Pair Measure Document)))
    (define (measured document node)
      (Pair (Measure 0.0 0.0 0.0 0.0 0.0 0.0 0.0)
            (commanded document
                       node
                       (list "measure" (show (Node-handle node)))
                       (lambda (found) found))))

    ;; ---- Handling ----

    ;; One operation's change to the document in `state`, and its answer.
    (: change!
       (All (A) (requires (Copy A)) (-> (Ref Document) (-> Document (Pair A Document)) A ! mut)))
    (define (change! state operation)
      (let ((result (operation (ref-get state))))
        (ref-set! state (Pair-second result))
        (Pair-first result)))

    (: alter! (-> (Ref Document) (-> Document Document) Unit ! mut))
    (define (alter! state operation)
      (ref-set! state (operation (ref-get state))))

    (: with-memory-dom
       (All (T e)
            (requires (Copy T))
            (-> (List Cue) (-> T ! dom e) (Pair T Document) ! mut e)))
    (define (with-memory-dom script work)
      (let ((state (ref empty-document)) (cues (ref script)) (woken (ref #f)) (inputs (ref (Nil))))
        (let ((value
               (handle dom
                   ((document-root (lambda () (Node 0)))
                    (create-element
                     (lambda (tag) (change! state (lambda (document) (created document tag "")))))
                    (create-text
                     (lambda (text)
                       (change! state (lambda (document) (created document "#text" text)))))
                    (set-attribute
                     (lambda (node name value)
                       (alter! state (lambda (document) (attribute-set document node name value)))))
                    (set-text
                     (lambda (node text)
                       (alter! state (lambda (document) (text-set document node text)))))
                    (set-string-property
                     (lambda (node name value)
                       (alter! state
                               (lambda (document) (property-set document node name (Text value))))))
                    (set-number-property
                     (lambda (node name value)
                       (alter! state
                               (lambda (document)
                                 (property-set document node name (Number value))))))
                    (set-flag-property
                     (lambda (node name value)
                       (alter! state
                               (lambda (document) (property-set document node name (Flag value))))))
                    (string-property
                     (lambda (node name)
                       (match (property-of (ref-get state) node name)
                         ((Some (Text value)) value)
                         (_ ""))))
                    (number-property
                     (lambda (node name)
                       (match (property-of (ref-get state) node name)
                         ((Some (Number value)) value)
                         (_ 0.0))))
                    (insert-node
                     (lambda (parent child before)
                       (alter! state (lambda (document) (inserted document parent child before)))))
                    (remove-node
                     (lambda (node) (alter! state (lambda (document) (removed document node)))))
                    (listen
                     (lambda (node event captures prevent)
                       (change! state
                                (lambda (document)
                                  (listened document node event captures prevent)))))
                    (unlisten
                     (lambda (listener)
                       (alter! state (lambda (document) (unlistened document listener)))))
                    (focus-node
                     (lambda (node)
                       (alter! state
                               (lambda (document)
                                 (commanded document
                                            node
                                            (list "focus" (show (Node-handle node)))
                                            (lambda (found) found))))))
                    (element-by-id
                     (lambda (id)
                       (match (element-handle (ref-get state) id 0)
                         ((Some handle) (Some (Node handle)))
                         ((None) (None)))))
                    (select-range
                     (lambda (node start end)
                       (alter! state (lambda (document) (selected document node start end)))))
                    (window-node (lambda () (Node -1)))
                    (confirm
                     (lambda (question)
                       (alter! state
                               (lambda (document)
                                 (traced document (list "confirm" (quoted question)))))
                       #t))
                    (insert-text
                     (lambda (node start end text)
                       (let ((taken (match (live (ref-get state) (Node-handle node))
                                      ((Some _) #t)
                                      ((None) #f))))
                         (alter! state
                                 (lambda (document) (text-inserted document node start end text)))
                         (match (input-fired (ref-get state) node)
                           ((Some delivery)
                            (ref-set! inputs (append (ref-get inputs) (list delivery))))
                           ((None) (unit)))
                         taken)))
                    (measure
                     (lambda (node) (change! state (lambda (document) (measured document node)))))
                    (wake
                     (lambda ()
                       (ref-set! woken #t)
                       (alter! state (lambda (document) (traced document (list "wake"))))))
                    (next-event
                     (lambda ()
                       (yield)
                       (match (ref-get inputs)
                         ((Cons delivery rest)
                          (ref-set! inputs rest)
                          delivery)
                         ((Nil)
                          (if (ref-get woken)
                              (begin
                                (ref-set! woken #f)
                                (Woken))
                              (match (ref-get cues)
                                ((Cons cue rest)
                                 (ref-set! cues rest)
                                 (change! state (lambda (document) (cued document cue))))
                                ((Nil)
                                 (alter! state (lambda (document) (traced document (list "close"))))
                                 (Closed)))))))))
                 (work))))
          (Pair value (ref-get state)))))

    ;; ---- Printing ----

    ;; The tree under the root as HTML would write it, with each property
    ;; as `.name=value` and each listener as `@event` among the attributes.
    (: document->html (-> Document String))
    (define (document->html document)
      (string-concatenate
       (map (lambda (child) (node->html document child)) (Entry-children (entry document 0)))))

    (: node->html (-> Document I32 String))
    (define (node->html document handle)
      (let ((node (entry document handle)))
        (if (string=? (Entry-tag node) "#text")
            (escaped (Entry-text node))
            (string-append "<"
                           (Entry-tag node)
                           (string-concatenate (map attribute->html (Entry-attributes node)))
                           (string-concatenate
                            (map (lambda (pair)
                                   (string-append " ."
                                                  (Pair-first pair)
                                                  "="
                                                  (property->string (Pair-second pair))))
                                 (Entry-properties node)))
                           (string-concatenate
                            (map (lambda (hearing) (string-append " @" (Hearing-event hearing)))
                                 (Entry-listeners node)))
                           ">"
                           (string-concatenate
                            (map (lambda (child) (node->html document child))
                                 (Entry-children node)))
                           "</"
                           (Entry-tag node)
                           ">"))))

    (: attribute->html (-> (Pair String String) String))
    (define (attribute->html pair)
      (string-append " " (Pair-first pair) "=\"" (escaped (Pair-second pair)) "\""))

    (: escaped (-> String String))
    (define (escaped text)
      (string-concatenate
       (map (lambda (char)
              (cond ((char=? char #\<) "&lt;")
                    ((char=? char #\>) "&gt;")
                    ((char=? char #\&) "&amp;")
                    ((char=? char #\") "&quot;")
                    (else (make-string 1 char))))
            (string->list text))))))
