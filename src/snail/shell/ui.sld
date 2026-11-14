;; User interfaces in the shape Elm gave them. An interface is a model, a
;; `view` from the model to a tree of `Html`, and an `update` from the
;; model and a message to the next model and the commands it starts. The
;; tree is plain data: `run-ui` shows it in the document through the `dom`
;; effect, and after each update changes only what differs from the tree
;; it showed before, so a node keeps its identity, and with it the focus,
;; selection and scroll the page gave it, for as long as the view keeps it.
;; Events come back as messages: a listener holds a function from what its
;; event carried to a message, which stays in Snail Scheme, as the host sees
;; only the listener's id. A command is work, run as a task, whose
;; answer is a message: it posts the answer to the interface's mailbox and
;; wakes the interface's task, the only one that waits on the document.
;; The window is no node of the tree, so the listeners on it, for what
;; reaches the whole page, are a list of their own the model gives; and an
;; interface may start with messages, to start the commands it needs
;; before anything happens.
(define-library (snail shell ui)
  (export
   Html
   Element
   Text
   Attribute
   Attr
   StringProperty
   NumberProperty
   FlagProperty
   On
   Keyed
   map-html
   run-ui
   run-reactor)
  (import
   (snail core base)
   (only (snail core forms) host)
   (snail core table)
   (snail shell task)
   (only (snail shell future) completion completed)
   (snail shell dom))
  (begin

    ;; ---- Trees ----

    ;; An element, or a text. An element's `Keyed` attribute tells it apart
    ;; from its siblings from one view to the next, so it keeps its node
    ;; when they move; siblings' keys differ. Children without one are
    ;; matched by their place among the others without one.
    (enum (Html M)
      (Element ((tag String)
                (attributes (List (Attribute M)))
                (children (List (Html M)))))
      (Text ((text String))))

    ;; An attribute, a property of one of the three kinds, a listener, or
    ;; the element's key. An attribute or property the view leaves out is
    ;; cleared: an attribute removed, a property set to "", 0 or false.
    (enum (Attribute M)
      (Attr ((name String) (value String)))
      (StringProperty ((name String) (value String)))
      (NumberProperty ((name String) (value F64)))
      (FlagProperty ((name String) (value Bool)))
      (On ((event String)
           (captures (List Capture))
           (prevent Prevent)
           (message (Fn Event → M))))
      (Keyed ((key String))))

    ;; A component keeps its own message type. Only its event listeners need
    ;; wrapping when its tree is embedded in a larger application.

    (define (map-html (wrap (Fn A → B)) (html (Html A))) (→ (Html B)) (∀ (A B))
      (match html
        ((Text text) (Text text))
        ((Element tag attributes children)
         (Element tag (map (lambda (attribute) (map-attribute wrap attribute)) attributes)
                  (map (lambda (child) (map-html wrap child)) children)))))

    (define (map-attribute (wrap (Fn A → B)) (attribute (Attribute A)))
      (→ (Attribute B))
      (∀ (A B))
      (match attribute
        ((Attr name value) (Attr name value))
        ((StringProperty name value) (StringProperty name value))
        ((NumberProperty name value) (NumberProperty name value))
        ((FlagProperty name value) (FlagProperty name value))
        ((Keyed key) (Keyed key))
        ((On name captures prevent message)
         (On name captures prevent (lambda (event) (wrap (message event)))))))

    ;; ---- What is shown ----

    ;; The tree as the document holds it: each node's handle beside what
    ;; the view said of it, and an element's listeners by event.
    (enum (Shown M)
      (ShownElement ((node Node)
                     (tag String)
                     (attributes (List (Attribute M)))
                     (listeners (List (Pair String Listener)))
                     (children (List (Shown M)))))
      (ShownText ((node Node) (text String))))

    (define (shown-node (shown (Shown M))) (→ Node) (∀ (M))
      (match shown
        ((ShownElement node _ _ _ _) node)
        ((ShownText node _) node)))

    ;; A shown node's handle as a table's key.

    (define (node-name (shown (Shown M))) (→ String) (∀ (M))
      (show (● (shown-node shown) handle)))

    (define (key-of (attributes (List (Attribute M)))) (→ String) (∀ (M))
      (match attributes
        ((Cons (Keyed key) _) key)
        ((Cons _ rest) (key-of rest))
        ((Nil) "")))

    ;; ---- Creating ----

    (define (create (html (Html M))) (→ (Shown M)) (! dom) (∀ (M))
      (match html
        ((Text text) (ShownText (create-text text) text))
        ((Element tag attributes children)
         (let ((node (create-element tag)))
           (for-each (lambda (attribute) (apply-attribute node attribute)) attributes)
           (let ((shown (map create children)))
             (for-each (lambda (child) (insert-node node (shown-node child) (None))) shown)
             (ShownElement node tag attributes (listen-all node attributes) shown))))))

    (define (apply-attribute (node Node) (attribute (Attribute M))) (→ Unit) (! dom) (∀ (M))
      (match attribute
        ((Attr name value) (set-attribute node name value))
        ((StringProperty name value) (set-string-property node name value))
        ((NumberProperty name value) (set-number-property node name value))
        ((FlagProperty name value) (set-flag-property node name value))
        (_ (unit))))

    (define (listen-all (node Node) (attributes (List (Attribute M))))
      (→ (List (Pair String Listener)))
      (! dom)
      (∀ (M))
      (match attributes
        ((Cons (On event captures prevent _) rest)
         (Cons (new Pair (first event) (second (listen node event captures prevent)))
               (listen-all node rest)))
        ((Cons _ rest) (listen-all node rest))
        ((Nil) (Nil))))

    ;; ---- Patching ----

    ;; The shown tree changed to what `html` says, in place where the kinds
    ;; and tags and keys agree, and otherwise by a new subtree; the caller
    ;; places a new one and removes the old.

    (define (patch (shown (Shown M)) (html (Html M))) (→ (Shown M)) (! dom) (∀ (M))
      (if (matches? shown html)
          (match (new Pair (first shown) (second html))
            ((Pair (ShownText node text) (Text updated))
             (unless (string=? text updated) (set-text node updated))
             (ShownText node updated))
            ((Pair (ShownElement node tag attributes listeners children)
                   (Element _ new-attributes new-children))
             (patch-attributes node attributes new-attributes)
             (ShownElement node
                           tag
                           new-attributes
                           (patch-listeners node attributes listeners new-attributes)
                           (patch-children node children new-children)))
            (_ (panic "internal error: a match of different kinds")))
          (create html)))

    (define (matches? (shown (Shown M)) (html (Html M))) (→ Bool) (∀ (M))
      (match (new Pair (first shown) (second html))
        ((Pair (ShownText _ _) (Text _)) #t)
        ((Pair (ShownElement _ tag attributes _ _) (Element new-tag new-attributes _))
         (and (string=? tag new-tag) (string=? (key-of attributes) (key-of new-attributes))))
        (_ #f)))

    ;; Each attribute and property the view now gives a value other than
    ;; the one it gave is set, and each it no longer gives is cleared.

    (define (patch-attributes (node Node) (old (List (Attribute M))) (updated (List (Attribute M))))
      (→ Unit)
      (! dom)
      (∀ (M))
      (for-each (lambda (attribute)
                  (unless (any? (lambda (before) (same-value? before attribute)) old)
                    (apply-attribute node attribute)))
                updated)
      (for-each (lambda (attribute)
                  (unless (any? (lambda (after) (same-name? attribute after)) updated)
                    (clear-attribute node attribute)))
                old))

    (define (same-name? (a (Attribute M)) (b (Attribute M))) (→ Bool) (∀ (M))
      (match (new Pair (first a) (second b))
        ((Pair (Attr x _) (Attr y _)) (string=? x y))
        ((Pair (StringProperty x _) (StringProperty y _)) (string=? x y))
        ((Pair (NumberProperty x _) (NumberProperty y _)) (string=? x y))
        ((Pair (FlagProperty x _) (FlagProperty y _)) (string=? x y))
        (_ #f)))

    (define (same-value? (a (Attribute M)) (b (Attribute M))) (→ Bool) (∀ (M))
      (and (same-name? a b)
           (match (new Pair (first a) (second b))
             ((Pair (Attr _ x) (Attr _ y)) (string=? x y))
             ((Pair (StringProperty _ x) (StringProperty _ y)) (string=? x y))
             ((Pair (NumberProperty _ x) (NumberProperty _ y)) (= x y))
             ((Pair (FlagProperty _ x) (FlagProperty _ y)) (= x y))
             (_ #f))))

    (define (clear-attribute (node Node) (attribute (Attribute M))) (→ Unit) (! dom) (∀ (M))
      (match attribute
        ((Attr name _) (set-attribute node name ""))
        ((StringProperty name _) (set-string-property node name ""))
        ((NumberProperty name _) (set-number-property node name 0.0))
        ((FlagProperty name _) (set-flag-property node name #f))
        (_ (unit))))

    ;; A listener stays while the view keeps its event, captures and
    ;; prevention; its function may change, since only the table holds it.

    (define (patch-listeners (node Node)
                             (old (List (Attribute M)))
                             (listeners (List (Pair String Listener)))
                             (updated (List (Attribute M))))
      (→ (List (Pair String Listener)))
      (! dom)
      (∀ (M))
      (for-each (lambda (pair)
                  (unless (kept-listener? (● pair first) old updated) (unlisten (● pair second))))
                listeners)
      (append (filter (lambda (pair) (kept-listener? (● pair first) old updated)) listeners)
              (listen-all node
                          (filter (lambda (attribute)
                                    (match attribute
                                      ((On event _ _ _) (not (kept-listener? event old updated)))
                                      (_ #f)))
                                  updated))))

    (define (kept-listener? (event String)
                            (old (List (Attribute M)))
                            (updated (List (Attribute M))))
      (→ Bool)
      (∀ (M))
      (match (new Pair (first (listening event old)) (second (listening event updated)))
        ((Pair (Some (On _ captures prevent _)) (Some (On _ new-captures new-prevent _)))
         (and (= (capture-bits captures) (capture-bits new-captures))
              (same-prevent? prevent new-prevent)))
        (_ #f)))

    (define (listening (event String) (attributes (List (Attribute M))))
      (→ (Option (Attribute M)))
      (∀ (M))
      (find (lambda (attribute)
              (match attribute
                ((On name _ _ _) (string=? name event))
                (_ #f)))
            attributes))

    (define (same-prevent? (a Prevent) (b Prevent)) (→ Bool)
      (match (new Pair (first a) (second b))
        ((Pair (Allow) (Allow)) #t)
        ((Pair (Always) (Always)) #t)
        ((Pair (Chords x) (Chords y))
         (and (= (length x) (length y)) (every? same-chord? (zip x y))))
        (_ #f)))

    (define (same-chord? (pair (Pair Chord Chord))) (→ Bool)
      (match pair
        ((Pair a b)
         (and (string=? (● a key) (● b key)) (= (● a modifiers) (● b modifiers))))))

    ;; ---- Children ----

    ;; A child with a key takes the old child with that key, and one
    ;; without takes the old child at its place among those without, when
    ;; they match; any other is new. The old children not taken are
    ;; removed, which leaves the document holding the taken ones in their
    ;; old order, and then the children are put in their new order.

    (define (patch-children (parent Node) (old (List (Shown M))) (updated (List (Html M))))
      (→ (List (Shown M)))
      (! dom)
      (∀ (M))
      (let* ((pairs (taking old updated))
             (taken (taken-names pairs))
             (children (map (lambda (pair)
                              (match (● pair first)
                                ((Some shown) (patch shown (● pair second)))
                                ((None) (create (● pair second)))))
                            pairs)))
        (for-each (lambda (shown)
                    (unless (table-contains? taken (node-name shown))
                      (remove-node (shown-node shown))))
                  old)
        (order parent
               (reverse children)
               (reverse (filter (lambda (shown) (table-contains? taken (node-name shown))) old))
               taken
               (None))
        children))

    ;; Each new child with the old child it takes: the one with its key,
    ;; or for a child without one, the next old child without one, when
    ;; it matches.

    (define (taking (old (List (Shown M))) (updated (List (Html M))))
      (→ (List (Pair (Option (Shown M)) (Html M))))
      (∀ (M))
      (let ((keys (filter (lambda (key) (not (string=? key ""))) (map html-key updated))))
        (unless (= (length keys) (length (delete-duplicates string=? keys)))
          (panic "two children have the same key"))
        (taking-from (fold-left (lambda (keyed shown)
                                  (if (string=? (shown-key shown) "")
                                      keyed
                                      (table-set keyed (shown-key shown) shown)))
                                (empty-table)
                                old)
                     (filter (lambda (shown) (string=? (shown-key shown) "")) old)
                     updated)))

    (define (taking-from (keyed (Table (Shown M)))
                         (unkeyed (List (Shown M)))
                         (updated (List (Html M))))
      (→ (List (Pair (Option (Shown M)) (Html M))))
      (∀ (M))
      (match updated
        ((Cons html rest)
         (if (string=? (html-key html) "")
             (match unkeyed
               ((Cons first others)
                (Cons (new Pair (first (matching first html)) (second html))
                      (taking-from keyed others rest)))
               ((Nil)
                (Cons (new Pair (first (None)) (second html)) (taking-from keyed unkeyed rest))))
             (Cons (new Pair (first (match (table-ref keyed (html-key html))
                                      ((Some shown) (matching shown html))
                                      ((None) (None))))
                        (second html))
                   (taking-from keyed unkeyed rest))))
        ((Nil) (Nil))))

    (define (matching (shown (Shown M)) (html (Html M))) (→ (Option (Shown M))) (∀ (M))
      (if (matches? shown html) (Some shown) (None)))

    (define (taken-names (pairs (List (Pair (Option (Shown M)) (Html M))))) (→ (Table Bool)) (∀ (M))
      (fold-left (lambda (taken pair)
                   (match (● pair first)
                     ((Some shown) (table-set taken (node-name shown) #t))
                     ((None) taken)))
                 (empty-table)
                 pairs))

    (define (shown-key (shown (Shown M))) (→ String) (∀ (M))
      (match shown
        ((ShownElement _ _ attributes _ _) (key-of attributes))
        ((ShownText _ _) "")))

    (define (html-key (html (Html M))) (→ String) (∀ (M))
      (match html
        ((Element _ attributes _) (key-of attributes))
        ((Text _) "")))

    (define (same-node? (a (Shown M)) (b (Shown M))) (→ Bool) (∀ (M))
      (= (● (shown-node a) handle) (● (shown-node b) handle)))

    ;; From the last child to the first, each goes before the one after it
    ;; unless it already is there. The document holds the taken children
    ;; not yet placed, `unplaced`, in their old order, before those placed;
    ;; so a child already is where it goes when it is the last of them.

    (define (order (parent Node)
                   (children (List (Shown M)))
                   (unplaced (List (Shown M)))
                   (taken (Table Bool))
                   (next (Option Node)))
      (→ Unit)
      (! dom)
      (∀ (M))
      (match children
        ((Cons child rest)
         (order parent
                rest
                (placed parent child unplaced taken next)
                taken
                (Some (shown-node child))))
        ((Nil) (unit))))

    ;; `child` placed before `next`, and the taken children left unplaced,
    ;; last first. Only a taken child that moves leaves them out of turn.

    (define (placed (parent Node)
                    (child (Shown M))
                    (unplaced (List (Shown M)))
                    (taken (Table Bool))
                    (next (Option Node)))
      (→ (List (Shown M)))
      (! dom)
      (∀ (M))
      (match unplaced
        ((Cons last others)
         (if (same-node? last child) others (moved parent child unplaced taken next)))
        ((Nil) (moved parent child unplaced taken next))))

    (define (moved (parent Node)
                   (child (Shown M))
                   (unplaced (List (Shown M)))
                   (taken (Table Bool))
                   (next (Option Node)))
      (→ (List (Shown M)))
      (! dom)
      (∀ (M))
      (insert-node parent (shown-node child) next)
      (if (table-contains? taken (node-name child))
          (filter (lambda (shown) (not (same-node? shown child))) unplaced)
          unplaced))

    ;; ---- The window ----

    ;; The window is shown as an element without attributes or children:
    ;; only the listeners given it are patched, so any other attribute is
    ;; ignored.

    (define (window-shown (attributes (List (Attribute M)))) (→ (Shown M)) (! dom) (∀ (M))
      (let ((node (window-node)))
        (ShownElement node "#window" attributes (listen-all node attributes) (Nil))))

    (define (patch-window (shown (Shown M)) (attributes (List (Attribute M))))
      (→ (Shown M))
      (! dom)
      (∀ (M))
      (match shown
        ((ShownElement node tag old listeners _)
         (ShownElement node tag attributes (patch-listeners node old listeners attributes) (Nil)))
        ((ShownText _ _) (panic "internal error: the window shown as text"))))

    ;; ---- Listeners ----

    ;; Each listener's function in the trees, by the listener's id.

    (define (listener-table (trees (List (Shown M)))) (→ (Table (Fn Event → M))) (∀ (M))
      (fold-left (lambda (table pair)
                   (table-set table (show (● (● pair second) id)) (● pair first)))
                 (empty-table)
                 (concatenate (map listener-functions trees))))

    (define (listener-functions (shown (Shown M)))
      (→ (List (Pair (Fn Event → M) Listener)))
      (∀ (M))
      (match shown
        ((ShownText _ _) (Nil))
        ((ShownElement _ _ attributes listeners children)
         (append (concatenate
                  (map (lambda (pair)
                         (match (listening (● pair first) attributes)
                           ((Some (On _ _ _ message))
                            (list (new Pair (first message) (second (● pair second)))))
                           (_ (Nil))))
                       listeners))
                 (concatenate (map listener-functions children))))))

    ;; ---- Running ----

    ;; The interface between deliveries: its model, the tree shown, the
    ;; window's listeners, and the listeners' functions by listener id,
    ;; which only `showing` builds, so they agree.
    (record (Running Model M)
      ((model Model)
       (shown (Shown M))
       (window (Shown M))
       (listeners (Table (Fn Event → M)))))

    (define (showing (model Model) (shown (Shown M)) (window (Shown M)))
      (→ (Running Model M))
      (∀ (Model M))
      (new Running
        (model model)
        (shown shown)
        (window window)
        (listeners (listener-table (list window shown)))))

    ;; Shows the view of `model` in the document's root, with the listeners
    ;; `window` gives the window, updates it with each message in `start`,
    ;; and runs the interface, a delivery at a time, until the document
    ;; closes, then answers the last model. An event at a listener the view has since
    ;; dropped is ignored. `commit` publishes complete presentations;
    ;; `checkpoint` saves on request, hiding and close. A
    ;; command still running then never answers. Both `view` and `update`
    ;; take the model, and the loop keeps it for `checkpoint`, so a model
    ;; is shared rather than moved: it must be Copy.

    (define (run-ui (model Model)
                    (start (List M))
                    (update (Fn Model M → (Pair Model (List (Fn → M ! tasks e))) ! mut host e))
                    (view (Fn Model → (Html M)))
                    (window (Fn Model → (List (Attribute M))))
                    (commit (Fn Model → Unit ! e))
                    (checkpoint (Fn Model → Unit ! tasks e)))
      (→ Model)
      (! mut host dom tasks e)
      (∀ (Model M e))
      (let ((box (make-mailbox)) (shown (create (view model))))
        (insert-node (document-root) (shown-node shown) (None))
        (serve box
               update
               view
               window
               commit checkpoint
               (fold-left (lambda (running message)
                            (updated box update view window running message))
                          (showing model shown (window-shown (window model)))
                          start))))

    (define (serve (box (Mailbox M))
                   (update (Fn Model M → (Pair Model (List (Fn → M ! tasks e))) ! mut host e))
                   (view (Fn Model → (Html M)))
                   (window (Fn Model → (List (Attribute M))))
                   (commit (Fn Model → Unit ! e))
                   (checkpoint (Fn Model → Unit ! tasks e))
                   (running (Running Model M)))
      (→ Model)
      (! mut host dom tasks e)
      (∀ (Model M e))
      (commit (● running model))
      (match (next-event)
        ((Fired listener event)
         (serve box
                update
                view
                window
                commit checkpoint
                (match (table-ref (● running listeners) (show (● listener id)))
                  ((Some message) (updated box update view window running (message event)))
                  ((None) running))))
        ((Woken)
         (serve box
                update
                view
                window
                commit
                checkpoint
                (answered box update view window commit running)))
        ((Hidden)
         (checkpoint (● running model))
         (serve box update view window commit checkpoint running))
        ((SaveRequested)
         (checkpoint (● running model))
         (serve box update view window commit checkpoint running))
        ((Closed)
         (checkpoint (● running model))
         (● running model))))

    ;; The interface after every answer the mailbox holds.

    (define (answered (box (Mailbox M))
                      (update
                       (Fn Model M → (Pair Model (List (Fn → M ! tasks e))) ! mut host e))
                      (view (Fn Model → (Html M)))
                      (window (Fn Model → (List (Attribute M))))
                      (commit (Fn Model → Unit ! e))
                      (running (Running Model M)))
      (→ (Running Model M))
      (! mut host dom tasks e)
      (∀ (Model M e))
      (match (mailbox-try-receive box)
        ((Some message)
         (let ((next (updated box update view window running message)))
           (commit (● next model))
           (answered box update view window commit next)))
        ((None) running)))

    ;; The update for one message, the commands it started dispatched, and
    ;; the view and window of the next model shown.

    (define (updated (box (Mailbox M))
                     (update (Fn Model M → (Pair Model (List (Fn → M ! tasks e))) ! mut host e))
                     (view (Fn Model → (Html M)))
                     (window (Fn Model → (List (Attribute M))))
                     (running (Running Model M))
                     (message M))
      (→ (Running Model M))
      (! mut host dom tasks e)
      (∀ (Model M e))
      (match (update (● running model) message)
        ((Pair model commands)
         (start-commands box commands)
         (showing model
                  (patch-root (● running shown) (view model))
                  (patch-window (● running window) (window model))))))

    (define (start-commands (box (Mailbox M)) (commands (List (Fn → M ! tasks e))))
      (→ Unit)
      (! mut host dom tasks e)
      (∀ (M e))
      (match commands
        ((Cons command rest)
         (dispatch-local (lambda () (answer box command)))
         (start-commands box rest))
        ((Nil) (unit))))

    (define (answer (box (Mailbox M)) (command (Fn → M ! tasks e)))
      (→ Unit)
      (! mut dom tasks e)
      (∀ (M e))
      (mailbox-post box (command))
      (wake))

    ;; ---- Reactors ----

    ;; A reactor's update takes an input: Some message, or None for a
    ;; completion wake. The loop holds the model across waits; only
    ;; snapshots reach commit and checkpoint.

    (define (run-reactor (model Model)
                         (start (List M))
                         (update (Fn Model (Option M) → Model ! mut host completion tasks e))
                         (view (Fn Model → (Html M) ! mut host e))
                         (window (Fn Model → (List (Attribute M)) ! mut host e))
                         (snapshot (Fn Model → S ! mut host e))
                         (commit (Fn S → Unit ! mut e))
                         (checkpoint (Fn S → Unit ! mut tasks e)))
      (→ Model)
      (! mut host dom tasks e)
      (∀ (Model M S e))
      (handle completion ((completed wake))
        (mount-reactor model start update view window snapshot commit checkpoint)))

    (define (mount-reactor (model Model)
                           (start (List M))
                           (update (Fn Model (Option M) → Model ! mut host completion tasks e))
                           (view (Fn Model → (Html M) ! mut host e))
                           (window (Fn Model → (List (Attribute M)) ! mut host e))
                           (snapshot (Fn Model → S ! mut host e))
                           (commit (Fn S → Unit ! mut e))
                           (checkpoint (Fn S → Unit ! mut tasks e)))
      (→ Model)
      (! mut host completion dom tasks e)
      (∀ (Model M S e))
      (let ((shown (create (view model)))
            (window-shown (window-shown (window model))))
        (insert-node (document-root) (shown-node shown) (None))
        (serve-reactor update view window snapshot commit checkpoint
                       (fold-left (lambda (running message)
                                    (step-reactor update view window running (Some message)))
                                  (showing model shown window-shown)
                                  start))))

    (define (serve-reactor (update (Fn Model (Option M) → Model ! mut host completion tasks e))
                           (view (Fn Model → (Html M) ! mut host e))
                           (window (Fn Model → (List (Attribute M)) ! mut host e))
                           (snapshot (Fn Model → S ! mut host e))
                           (commit (Fn S → Unit ! mut e))
                           (checkpoint (Fn S → Unit ! mut tasks e))
                           (running (Running Model M)))
      (→ Model)
      (! mut host completion dom tasks e)
      (∀ (Model M S e))
      (match running
        ((Running model shown window-shown listeners)
         (commit (snapshot model))
         ;; Give dispatched work a turn even when input is already queued.
         (yield)
         (match (next-event)
           ((Closed) (checkpoint (snapshot model)) model)
           ((Hidden)
            (checkpoint (snapshot model))
            (serve-reactor update view window snapshot commit checkpoint
                           (new Running
                             (model model)
                             (shown shown)
                             (window window-shown)
                             (listeners listeners))))
           ((SaveRequested)
            (checkpoint (snapshot model))
            (serve-reactor update view window snapshot commit checkpoint
                           (new Running
                             (model model)
                             (shown shown)
                             (window window-shown)
                             (listeners listeners))))
           ((Woken)
            (serve-reactor update view window snapshot commit checkpoint
                           (step-reactor update view window
                                         (new Running
                                           (model model)
                                           (shown shown)
                                           (window window-shown)
                                           (listeners listeners))
                                         (None))))
           ((Fired listener event)
            (let ((running (new Running
                             (model model)
                             (shown shown)
                             (window window-shown)
                             (listeners listeners))))
              (serve-reactor update view window snapshot commit checkpoint
                             (match (table-ref listeners (show (● listener id)))
                               ((Some message)
                                (step-reactor update view window running (Some (message event))))
                               ((None) running)))))))))

    (define (step-reactor (update (Fn Model (Option M) → Model ! mut host completion tasks e))
                          (view (Fn Model → (Html M) ! mut host e))
                          (window (Fn Model → (List (Attribute M)) ! mut host e))
                          (running (Running Model M))
                          (message (Option M)))
      (→ (Running Model M))
      (! mut host completion dom tasks e)
      (∀ (Model M e))
      (match running
        ((Running model shown window-shown _)
         (render-reactor view window (update model message) shown window-shown))))

    ;; The model is shared with both presentations, not copied. An
    ;; application stops its own resource work before closing.

    (define (render-reactor (view (Fn Model → (Html M) ! mut host e))
                            (window (Fn Model → (List (Attribute M)) ! mut host e))
                            (model Model)
                            (shown (Shown M))
                            (window-shown (Shown M)))
      (→ (Running Model M))
      (! mut host dom e)
      (∀ (Model M e))
      (let ((shown (patch-root shown (view model)))
            (window-shown (patch-window window-shown (window model))))
        (showing model shown window-shown)))

    ;; The root's one child, patched, or replaced by a new one.

    (define (patch-root (shown (Shown M)) (html (Html M))) (→ (Shown M)) (! dom) (∀ (M))
      (let ((next (patch shown html)))
        (unless (same-node? next shown)
          (insert-node (document-root) (shown-node next) (None))
          (remove-node (shown-node shown)))
        next))))
