;; A document in memory for the `dom` effect, so an interface runs, and is
;; tested, without a page. `with-memory-dom` handles the effect around its
;; work and answers the work's value with the document it left: its tree,
;; which `document->html` prints, and the trace of every operation, one
;; line each. Its events are a script, delivered in turn as the work
;; waits for them: firing a listener on the element with an `id`, or
;; hiding the page. A `wake` is delivered before the script goes on, and
;; once the script is done and no wake is waiting, the document is closed.
;; As a page delivers only between the tasks it runs, each delivery waits
;; until every other ready task has run, so it finds the document as they
;; left it.
;;
;; The document is strict where a page would forgive: a node used after
;; it was removed, a listener dropped after its node was, or a node
;; inserted into itself, is a panic, so the tests of an interface catch
;; what a page would hide.
(define-library (snail shell dom memory)
  (export
   Document
   Cue
   Fire
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
       (listeners (List (Pair I32 String)))
       (live Bool)))

    (enum Property
      (Text ((value String)))
      (Number ((value F64)))
      (Flag ((value Bool))))

    ;; Every node made, by handle; the node each listener is on, by its id;
    ;; the next handle and listener id; and the trace's lines, newest
    ;; first. Handle 0 is the root.
    (struct Document
      ((entries (Table Entry))
       (owners (Table I32))
       (next I32)
       (next-listener I32)
       (lines (List String))))

    (: empty-document Document)
    (define empty-document
      (Document (table-set empty-table "0" (new-entry "#root" "")) empty-table 1 1 (Nil)))

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
      (let* ((handle (Node-handle node)) (changed (entry document handle)))
        (traced (put document
                     handle
                     (Entry-properties-set changed
                                           (assigned (Entry-properties changed) name (Some value))))
                (list "set-property" (show handle) name (property->string value)))))

    (: property->string (-> Property String))
    (define (property->string property)
      (match property
        ((Text value) (quoted value))
        ((Number value) (show value))
        ((Flag value) (if value "true" "false"))))

    (: property-of (-> Document Node String (Option Property)))
    (define (property-of document node name)
      (match (find (lambda (pair) (string=? (Pair-first pair) name))
                   (Entry-properties (entry document (Node-handle node))))
        ((Some pair) (Some (Pair-second pair)))
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
                                                          (list (Pair id event)))))
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
                                          (filter (lambda (pair) (not (= (Pair-first pair) id)))
                                                  (Entry-listeners on))))
                (list "unlisten" (string-append "#" (show id))))))

    ;; ---- Events ----

    ;; A step of the script: an event to fire at the listener for `event`
    ;; on the element whose `id` attribute is `target`, carrying `data`, or
    ;; the page hidden.
    (enum Cue
      (Fire ((target String)
             (event String)
             (data Event)))
      (Hide))

    ;; A cue's delivery.
    (: cued (-> Document Cue (Pair Delivery Document)))
    (define (cued document cue)
      (match cue
        ((Fire target event data) (fired document target event data))
        ((Hide) (Pair (Hidden) (traced document (list "hide"))))))

    ;; The listener a scripted event fires, which must be there.
    (: fired (-> Document String String Event (Pair Delivery Document)))
    (define (fired document target event data)
      (match (find (lambda (pair) (string=? (Pair-second pair) event))
                   (Entry-listeners (target-entry document target)))
        ((Some pair)
         (Pair (Fired (Listener (Pair-first pair)) data)
               (traced document
                       (list "fire" target event (string-append "#" (show (Pair-first pair)))))))
        ((None) (panic (string-append "nothing listens for " event " on " target)))))

    (: target-entry (-> Document String Entry))
    (define (target-entry document target)
      (match (find (lambda (node)
                     (and (Entry-live node)
                          (any? (lambda (pair)
                                  (and (string=? (Pair-first pair) "id")
                                       (string=? (Pair-second pair) target)))
                                (Entry-attributes node))))
                   (table-values (Document-entries document)))
        ((Some found) found)
        ((None) (panic (string-append "no element has the id " target)))))

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
      (let ((state (ref empty-document)) (cues (ref script)) (woken (ref #f)))
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
                                 (entry document (Node-handle node))
                                 (traced document (list "focus" (show (Node-handle node))))))))
                    (wake
                     (lambda ()
                       (ref-set! woken #t)
                       (alter! state (lambda (document) (traced document (list "wake"))))))
                    (next-event
                     (lambda ()
                       (yield)
                       (cond ((ref-get woken) (ref-set! woken #f) (Woken))
                             (else
                              (match (ref-get cues)
                                ((Cons cue rest)
                                 (ref-set! cues rest)
                                 (change! state (lambda (document) (cued document cue))))
                                ((Nil)
                                 (alter! state (lambda (document) (traced document (list "close"))))
                                 (Closed))))))))
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
                            (map (lambda (pair) (string-append " @" (Pair-second pair)))
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
