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

    (define empty-document (→ Document)
      (Document (table-set (table-set empty-table "0" (new-entry "#root" ""))
                           "-1"
                           (new-entry "#window" ""))
                empty-table
                1
                1
                (Nil)))

    (define (new-entry (tag String) (text String)) (→ Entry)
      (Entry tag text (Nil) (Nil) (Nil) -1 (Nil) #t))

    ;; The trace, a line per operation, oldest first.

    (define (document-trace (document Document)) (→ (List String))
      (reverse (● document lines)))

    (define (entry (document Document) (handle I32)) (→ Entry)
      (match (table-ref (● document entries) (show handle))
        ((Some found)
         (if (● found live)
             found
             (panic (string-append "the node " (show handle) " was removed"))))
        ((None) (panic (string-append "no node has the handle " (show handle))))))

    (define (put (document Document) (handle I32) (changed Entry)) (→ Document)
      (Document-entries-set document
                            (table-set (● document entries) (show handle) changed)))

    (define (traced (document Document) (words (List String))) (→ Document)
      (Document-lines-set document (Cons (string-join words " ") (● document lines))))

    (define (quoted (text String)) (→ String)
      (repr text))

    ;; ---- Operations ----

    (define (created (document Document) (tag String) (text String)) (→ (Pair Node Document))
      (let ((made (made document tag text)))
        (Pair (● made first)
              (traced (● made second)
                      (if (string=? tag "#text")
                          (list "create-text" (show (● (● made first) handle)) (quoted text))
                          (list "create-element" (show (● (● made first) handle)) tag))))))

    (define (made (document Document) (tag String) (text String)) (→ (Pair Node Document))
      (let ((handle (● document next)))
        (Pair (Node handle)
              (Document-next-set (put document handle (new-entry tag text)) (+ handle 1)))))

    (define (attribute-set (document Document) (node Node) (name String) (value String))
      (→ Document)
      (let* ((handle (● node handle)) (changed (entry document handle)))
        (traced (put document
                     handle
                     (Entry-attributes-set changed
                                           (assigned (● changed attributes)
                                                     name
                                                     (if (string=? value "") (None) (Some value)))))
                (list "set-attribute" (show handle) name (quoted value)))))

    ;; `pairs` with `name` given `value`, in place when it is there and last
    ;; when it is new, or without it.

    (define (assigned (pairs (List (Pair String V))) (name String) (value (Option V)))
      (→ (List (Pair String V)))
      (∀ V)
      (⊨ (Copy V) (Drop (!) V))
      (let ((others (filter (lambda (pair) (not (string=? (● pair first) name))) pairs)))
        (match value
          ((None) others)
          ((Some value)
           (if (any? (lambda (pair) (string=? (● pair first) name)) pairs)
               (map (lambda (pair) (if (string=? (● pair first) name) (Pair name value) pair))
                    pairs)
               (append pairs (list (Pair name value))))))))

    ;; An element's text replaces its children, whose handles are freed,
    ;; with one text node of its own.

    (define (text-set (document Document) (node Node) (text String)) (→ Document)
      (let ((handle (● node handle)))
        (traced (if (string=? (● (entry document handle) tag) "#text")
                    (put document handle (Entry-text-set (entry document handle) text))
                    (element-text-set document handle text))
                (list "set-text" (show handle) (quoted text)))))

    (define (element-text-set (document Document) (handle I32) (text String)) (→ Document)
      (let* ((cleared (fold-left freed document (● (entry document handle) children)))
             (child (made cleared "#text" text))
             (text-handle (● (● child first) handle))
             (document (● child second)))
        (put (put document text-handle (Entry-parent-set (entry document text-handle) handle))
             handle
             (Entry-children-set (entry document handle) (list text-handle)))))

    (define (property-set (document Document) (node Node) (name String) (value Property))
      (→ Document)
      (commanded document
                 node
                 (list "set-property" (show (● node handle)) name (property->string value))
                 (lambda (changed)
                   (Entry-properties-set changed
                                         (assigned (● changed properties) name (Some value))))))

    (define (property->string (property Property)) (→ String)
      (match property
        ((Text value) (quoted value))
        ((Number value) (show value))
        ((Flag value) (if value "true" "false"))))

    (define (property-of (document Document) (node Node) (name String)) (→ (Option Property))
      (match (live document (● node handle))
        ((Some found)
         (match (find (lambda (pair) (string=? (● pair first) name)) (● found properties))
           ((Some pair) (Some (● pair second)))
           ((None) (None))))
        ((None) (None))))

    ;; A child inserted where it is, or into a node under it, would leave
    ;; the tree; a child elsewhere moves.

    (define (inserted (document Document) (parent Node) (child Node) (before (Option Node)))
      (→ Document)
      (let ((into (● parent handle)) (moved (● child handle)))
        (when (or (= into moved) (under? document into moved))
          (panic (string-append "the node " (show moved) " cannot go inside itself")))
        (let* ((detached (detached document moved))
               (siblings (filter (lambda (sibling) (not (= sibling moved)))
                                 (● (entry detached into) children)))
               (placed (match before
                         ((Some node) (insert-before siblings (● node handle) moved))
                         ((None) (append siblings (list moved))))))
          (traced (put (put detached into (Entry-children-set (entry detached into) placed))
                       moved
                       (Entry-parent-set (entry detached moved) into))
                  (append (list "insert" (show moved) "into" (show into))
                          (match before
                            ((Some node) (list "before" (show (● node handle))))
                            ((None) (Nil))))))))

    (define (insert-before (siblings (List I32)) (before I32) (moved I32)) (→ (List I32))
      (match siblings
        ((Cons first rest)
         (if (= first before)
             (Cons moved siblings)
             (Cons first (insert-before rest before moved))))
        ((Nil) (panic (string-append "the node " (show before) " is not a child there")))))

    ;; Whether `handle` lies under `ancestor`.

    (define (under? (document Document) (handle I32) (ancestor I32)) (→ Bool)
      (let ((parent (● (entry document handle) parent)))
        (and (>= parent 0) (or (= parent ancestor) (under? document parent ancestor)))))

    (define (detached (document Document) (handle I32)) (→ Document)
      (let ((parent (● (entry document handle) parent)))
        (if (< parent 0)
            document
            (put (put document
                      parent
                      (Entry-children-set (entry document parent)
                                          (filter (lambda (child) (not (= child handle)))
                                                  (● (entry document parent) children))))
                 handle
                 (Entry-parent-set (entry document handle) -1)))))

    ;; A removed node leaves its parent, and its handle and those under it
    ;; are freed.

    (define (removed (document Document) (node Node)) (→ Document)
      (let ((handle (● node handle)))
        (traced (freed (detached document handle) handle) (list "remove" (show handle)))))

    (define (freed (document Document) (handle I32)) (→ Document)
      (let ((gone (entry document handle)))
        (put
         (fold-left (lambda (document child) (freed document child)) document (● gone children))
         handle
         (Entry-live-set gone #f))))

    (define (listened (document Document)
                      (node Node)
                      (event String)
                      (captures (List Capture))
                      (prevent Prevent))
      (→ (Pair Listener Document))
      (let* ((handle (● node handle))
             (id (● document next-listener))
             (on (entry document handle)))
        (Pair (Listener id)
              (traced (Document-owners-set
                       (Document-next-listener-set
                        (put document
                             handle
                             (Entry-listeners-set on
                                                  (append (● on listeners)
                                                          (list (Hearing id event prevent)))))
                        (+ id 1))
                       (table-set (● document owners) (show id) handle))
                      (list "listen"
                            (show handle)
                            event
                            (string-append "#" (show id))
                            (show (capture-bits captures))
                            (prevent->string prevent))))))

    (define (prevent->string (prevent Prevent)) (→ String)
      (match prevent
        ((Allow) "allow")
        ((Always) "always")
        ((Chords chords)
         (string-append "chords"
                        (string-concatenate
                         (map (lambda (chord)
                                (string-append " "
                                               (show (● chord modifiers))
                                               "+"
                                               (quoted (● chord key))))
                              chords))))))

    ;; A listener goes with its node, so its node must be there.

    (define (unlistened (document Document) (listener Listener)) (→ Document)
      (let* ((id (● listener id))
             (handle (match (table-ref (● document owners) (show id))
                       ((Some handle) handle)
                       ((None) (panic (string-append "no listener has the id " (show id))))))
             (on (entry document handle)))
        (traced (put document
                     handle
                     (Entry-listeners-set on
                                          (filter
                                           (lambda (hearing) (not (= (● hearing id) id)))
                                           (● on listeners))))
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

    (define (cued (document Document) (cue Cue)) (→ (Pair Delivery Document))
      (match cue
        ((Fire target event data) (fired document target (target-entry document target) event data))
        ((FireWindow event data) (fired document "window" (entry document -1) event data))
        ((Hide) (Pair (Hidden) (traced document (list "hide"))))))

    ;; The listener a scripted event fires, which must be there, and must
    ;; hear its key when it hears only chords.

    (define (fired (document Document) (target String) (on Entry) (event String) (data Event))
      (→ (Pair Delivery Document))
      (match (find (lambda (hearing) (string=? (● hearing event) event)) (● on listeners))
        ((Some hearing)
         (unless (hears? (● hearing prevent) data)
           (panic
            (string-append "the " event " listener on " target " does not hear " (● data key))))
         (Pair (Fired (Listener (● hearing id)) data)
               (traced document
                       (list "fire" target event (string-append "#" (show (● hearing id)))))))
        ((None) (panic (string-append "nothing listens for " event " on " target)))))

    (define (hears? (prevent Prevent) (data Event)) (→ Bool)
      (match prevent
        ((Chords chords)
         (any? (lambda (chord)
                 (and (string=? (● chord key) (● data key))
                      (= (● chord modifiers) (● data modifiers))))
               chords))
        (_ #t)))

    (define (target-entry (document Document) (target String)) (→ Entry)
      (match (element-handle document target 0)
        ((Some handle) (entry document handle))
        ((None) (panic (string-append "no element has the id " target)))))

    ;; ---- Commands ----

    ;; A node, unless it was removed.

    (define (live (document Document) (handle I32)) (→ (Option Entry))
      (match (table-ref (● document entries) (show handle))
        ((Some found) (if (● found live) (Some found) (None)))
        ((None) (panic (string-append "no node has the handle " (show handle))))))

    ;; A command's change to a node, traced by `words`, or the trace alone
    ;; when the node was removed.

    (define (commanded (document Document)
                       (node Node)
                       (words (List String))
                       (change (Fn Entry → Entry)))
      (→ Document)
      (let ((handle (● node handle)))
        (match (live document handle)
          ((Some found) (traced (put document handle (change found)) words))
          ((None) (traced document (append words (list "(removed)")))))))

    ;; The first node from `handle` on whose `id` is `target`.

    (define (element-handle (document Document) (target String) (handle I32)) (→ (Option I32))
      (cond ((>= handle (● document next)) (None))
            ((match (live document handle)
               ((Some found)
                (any? (lambda (pair)
                        (and (string=? (● pair first) "id")
                             (string=? (● pair second) target)))
                      (● found attributes)))
               ((None) #f))
             (Some handle))
            (else (element-handle document target (+ handle 1)))))

    (define (selected (document Document) (node Node) (start I32) (end I32)) (→ Document)
      (commanded document
                 node
                 (list "select" (show (● node handle)) (show start) (show end))
                 (lambda (found) (selection-set found start end))))

    (define (selection-set (found Entry) (start I32) (end I32)) (→ Entry)
      (Entry-properties-set found
                            (assigned (assigned (● found properties)
                                                "selectionStart"
                                                (Some (Number (i32->f64 start))))
                                      "selectionEnd"
                                      (Some (Number (i32->f64 end))))))

    (define (offset-property (document Document) (node Node) (name String)) (→ I32)
      (match (property-of document node name)
        ((Some (Number offset)) (f64->i32 offset))
        (_ 0)))

    ;; The field's value with the range replaced by `text`, and the caret
    ;; after it.

    (define (text-inserted (document Document) (node Node) (start I32) (end I32) (text String))
      (→ Document)
      (commanded document
                 node
                 (list "insert-text"
                       (show (● node handle))
                       (show start)
                       (show end)
                       (quoted text))
                 (lambda (found)
                   (let* ((value (match (find (lambda (pair) (string=? (● pair first) "value"))
                                              (● found properties))
                                   ((Some (Pair _ (Text value))) value)
                                   (_ "")))
                          (changed (string-append (substring value 0 (i32->i64 start))
                                                  text
                                                  (substring value
                                                             (i32->i64 end)
                                                             (string-length value))))
                          (caret (+ start (i64->i32 (string-length text)))))
                     (selection-set (Entry-properties-set found
                                                          (assigned (● found properties)
                                                                    "value"
                                                                    (Some (Text changed))))
                                    caret
                                    caret)))))

    ;; The `input` event a field's listener hears after text is inserted
    ;; into it.

    (define (input-fired (document Document) (node Node)) (→ (Option Delivery))
      (match (live document (● node handle))
        ((Some found)
         (match (find (lambda (hearing) (string=? (● hearing event) "input"))
                      (● found listeners))
           ((Some hearing)
            (Some (Fired (Listener (● hearing id))
                         (Event-value-set no-event
                                          (match (property-of document node "value")
                                            ((Some (Text value)) value)
                                            (_ ""))))))
           ((None) (None))))
        ((None) (None))))

    ;; A document in memory has no layout: every measure is 0.

    (define (measured (document Document) (node Node)) (→ (Pair Measure Document))
      (Pair (Measure 0.0 0.0 0.0 0.0 0.0 0.0 0.0)
            (commanded document
                       node
                       (list "measure" (show (● node handle)))
                       (lambda (found) found))))

    ;; ---- Handling ----

    ;; The simulated host shares one explicit state record among handlers.
    (struct Memory
      ((document Document)
       (cues (List Cue))
       (woken Bool)
       (inputs (List Delivery))))

    ;; One operation's change to the document in `state`, and its answer.

    (define (change! (state Memory) (operation (Fn Document → (Pair A Document))))
      (→ A)
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Drop (!) A))
      (let ((result (operation (● state document))))
        (set! (● state document) (● result second))
        (● result first)))

    (define (alter! (state Memory) (operation (Fn Document → Document)))
      (→ Unit)
      (! mut)
      (set! (● state document) (operation (● state document))))

    (define (with-memory-dom (script (List Cue)) (work (FnOnce → T ! dom e)))
      (→ (Pair T Document))
      (! mut e)
      (∀ T e)
      (let ((state (Memory empty-document script #f (Nil))))
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
                       (match (property-of (● state document) node name)
                         ((Some (Text value)) value)
                         (_ ""))))
                    (number-property
                     (lambda (node name)
                       (match (property-of (● state document) node name)
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
                                            (list "focus" (show (● node handle)))
                                            (lambda (found) found))))))
                    (element-by-id
                     (lambda (id)
                       (match (element-handle (● state document) id 0)
                         ((Some handle) (Some (Node handle)))
                         ((None) (None)))))
                    (select-range
                     (lambda (node start end)
                       (alter! state (lambda (document) (selected document node start end)))))
                    (selection-range
                     (lambda (node)
                       (Pair (offset-property (● state document) node "selectionStart")
                             (offset-property (● state document) node "selectionEnd"))))
                    (window-node (lambda () (Node -1)))
                    (refresh-page (lambda () (unit)))
                    (confirm
                     (lambda (question)
                       (alter! state
                               (lambda (document)
                                 (traced document (list "confirm" (quoted question)))))
                       #t))
                    ;; This document has no browser window or installation offer.
                    (installation-status (lambda () (InstallUnavailable)))
                    (install-app (lambda () (InstallNotAvailable)))
                    (fullscreen? (lambda () #f))
                    (set-fullscreen (lambda (enter) #f))
                    (insert-text
                     (lambda (node start end text)
                       (let ((taken (match (live (● state document) (● node handle))
                                      ((Some _) #t)
                                      ((None) #f))))
                         (alter! state
                                 (lambda (document) (text-inserted document node start end text)))
                         (match (input-fired (● state document) node)
                           ((Some delivery)
                            (set! (● state inputs) (append (● state inputs) (list delivery))))
                           ((None) (unit)))
                         taken)))
                    (measure
                     (lambda (node) (change! state (lambda (document) (measured document node)))))
                    (wake
                     (lambda ()
                       (set! (● state woken) #t)
                       (alter! state (lambda (document) (traced document (list "wake"))))))
                    (next-event
                     (lambda ()
                       (yield)
                       (match (● state inputs)
                         ((Cons delivery rest)
                          (set! (● state inputs) rest)
                          delivery)
                         ((Nil)
                          (if (● state woken)
                              (begin
                                (set! (● state woken) #f)
                                (Woken))
                              (match (● state cues)
                                ((Cons cue rest)
                                 (set! (● state cues) rest)
                                 (change! state (lambda (document) (cued document cue))))
                                ((Nil)
                                 (alter! state (lambda (document) (traced document (list "close"))))
                                 (Closed)))))))))
                 (work))))
          (Pair value (● state document)))))

    ;; ---- Printing ----

    ;; The tree under the root as HTML would write it, with each property
    ;; as `.name=value` and each listener as `@event` among the attributes.

    (define (document->html (document Document)) (→ String)
      (string-concatenate
       (map (lambda (child) (node->html document child)) (● (entry document 0) children))))

    (define (node->html (document Document) (handle I32)) (→ String)
      (let ((node (entry document handle)))
        (if (string=? (● node tag) "#text")
            (escaped (● node text))
            (string-append "<"
                           (● node tag)
                           (string-concatenate (map attribute->html (● node attributes)))
                           (string-concatenate
                            (map (lambda (pair)
                                   (string-append " ."
                                                  (● pair first)
                                                  "="
                                                  (property->string (● pair second))))
                                 (● node properties)))
                           (string-concatenate
                            (map (lambda (hearing) (string-append " @" (● hearing event)))
                                 (● node listeners)))
                           ">"
                           (string-concatenate
                            (map (lambda (child) (node->html document child))
                                 (● node children)))
                           "</"
                           (● node tag)
                           ">"))))

    (define (attribute->html (pair (Pair String String))) (→ String)
      (string-append " " (● pair first) "=\"" (escaped (● pair second)) "\""))

    (define (escaped (text String)) (→ String)
      (string-concatenate
       (map (lambda (char)
              (cond ((char=? char #\<) "&lt;")
                    ((char=? char #\>) "&gt;")
                    ((char=? char #\&) "&amp;")
                    ((char=? char #\") "&quot;")
                    (else (make-string 1 char))))
            (string->list text))))))
