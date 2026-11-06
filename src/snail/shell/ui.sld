;; User interfaces in the shape Elm gave them. An interface is a model, a
;; `view` from the model to a tree of `Html`, and an `update` from the
;; model and a message to the next model and the commands it starts. The
;; tree is plain data: `run-ui` shows it in the document through the `dom`
;; effect, and after each update changes only what differs from the tree
;; it showed before, so a node keeps its identity, and with it the focus,
;; selection and scroll the page gave it, for as long as the view keeps it.
;; Events come back as messages: a listener holds a function from what its
;; event carried to a message, which stays in Snail-Core, as the host sees
;; only the listener's id. A command is one-shot work, run as a task, whose
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
           (message (-> Event M))))
      (Keyed ((key String))))

    ;; A component keeps its own message type. Only its event listeners need
    ;; wrapping when its tree is embedded in a larger application.
    (: map-html (All (A B) (-> (-> A B) (Html A) (Html B))))
    (define (map-html wrap html)
      (match html
        ((Text text) (Text text))
        ((Element tag attributes children)
         (Element tag (map (lambda (attribute) (map-attribute wrap attribute)) attributes)
                  (map (lambda (child) (map-html wrap child)) children)))))

    (: map-attribute (All (A B) (-> (-> A B) (Attribute A) (Attribute B))))
    (define (map-attribute wrap attribute)
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

    (: shown-node (All (M) (-> (Shown M) Node)))
    (define (shown-node shown)
      (match shown
        ((ShownElement node _ _ _ _) node)
        ((ShownText node _) node)))

    ;; A shown node's handle as a table's key.
    (: node-name (All (M) (-> (Shown M) String)))
    (define (node-name shown)
      (show (::handle (shown-node shown))))

    (: key-of (All (M) (-> (List (Attribute M)) String)))
    (define (key-of attributes)
      (match attributes
        ((Cons (Keyed key) _) key)
        ((Cons _ rest) (key-of rest))
        ((Nil) "")))

    ;; ---- Creating ----

    (: create (All (M) (-> (Html M) (Shown M) ! dom)))
    (define (create html)
      (match html
        ((Text text) (ShownText (create-text text) text))
        ((Element tag attributes children)
         (let ((node (create-element tag)))
           (for-each (lambda (attribute) (apply-attribute node attribute)) attributes)
           (let ((shown (map create children)))
             (for-each (lambda (child) (insert-node node (shown-node child) (None))) shown)
             (ShownElement node tag attributes (listen-all node attributes) shown))))))

    (: apply-attribute (All (M) (-> Node (Attribute M) Unit ! dom)))
    (define (apply-attribute node attribute)
      (match attribute
        ((Attr name value) (set-attribute node name value))
        ((StringProperty name value) (set-string-property node name value))
        ((NumberProperty name value) (set-number-property node name value))
        ((FlagProperty name value) (set-flag-property node name value))
        (_ (unit))))

    (: listen-all (All (M) (-> Node (List (Attribute M)) (List (Pair String Listener)) ! dom)))
    (define (listen-all node attributes)
      (match attributes
        ((Cons (On event captures prevent _) rest)
         (Cons (Pair event (listen node event captures prevent)) (listen-all node rest)))
        ((Cons _ rest) (listen-all node rest))
        ((Nil) (Nil))))

    ;; ---- Patching ----

    ;; The shown tree changed to what `html` says, in place where the kinds
    ;; and tags and keys agree, and otherwise by a new subtree; the caller
    ;; places a new one and removes the old.
    (: patch (All (M) (-> (Shown M) (Html M) (Shown M) ! dom)))
    (define (patch shown html)
      (if (matches? shown html)
          (match (Pair shown html)
            ((Pair (ShownText node text) (Text new))
             (unless (string=? text new) (set-text node new))
             (ShownText node new))
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

    (: matches? (All (M) (-> (Shown M) (Html M) Bool)))
    (define (matches? shown html)
      (match (Pair shown html)
        ((Pair (ShownText _ _) (Text _)) #t)
        ((Pair (ShownElement _ tag attributes _ _) (Element new-tag new-attributes _))
         (and (string=? tag new-tag) (string=? (key-of attributes) (key-of new-attributes))))
        (_ #f)))

    ;; Each attribute and property the view now gives a value other than
    ;; the one it gave is set, and each it no longer gives is cleared.
    (: patch-attributes (All (M) (-> Node (List (Attribute M)) (List (Attribute M)) Unit ! dom)))
    (define (patch-attributes node old new)
      (for-each (lambda (attribute)
                  (unless (any? (lambda (before) (same-value? before attribute)) old)
                    (apply-attribute node attribute)))
                new)
      (for-each (lambda (attribute)
                  (unless (any? (lambda (after) (same-name? attribute after)) new)
                    (clear-attribute node attribute)))
                old))

    (: same-name? (All (M) (-> (Attribute M) (Attribute M) Bool)))
    (define (same-name? a b)
      (match (Pair a b)
        ((Pair (Attr x _) (Attr y _)) (string=? x y))
        ((Pair (StringProperty x _) (StringProperty y _)) (string=? x y))
        ((Pair (NumberProperty x _) (NumberProperty y _)) (string=? x y))
        ((Pair (FlagProperty x _) (FlagProperty y _)) (string=? x y))
        (_ #f)))

    (: same-value? (All (M) (-> (Attribute M) (Attribute M) Bool)))
    (define (same-value? a b)
      (and (same-name? a b)
           (match (Pair a b)
             ((Pair (Attr _ x) (Attr _ y)) (string=? x y))
             ((Pair (StringProperty _ x) (StringProperty _ y)) (string=? x y))
             ((Pair (NumberProperty _ x) (NumberProperty _ y)) (= x y))
             ((Pair (FlagProperty _ x) (FlagProperty _ y)) (= x y))
             (_ #f))))

    (: clear-attribute (All (M) (-> Node (Attribute M) Unit ! dom)))
    (define (clear-attribute node attribute)
      (match attribute
        ((Attr name _) (set-attribute node name ""))
        ((StringProperty name _) (set-string-property node name ""))
        ((NumberProperty name _) (set-number-property node name 0.0))
        ((FlagProperty name _) (set-flag-property node name #f))
        (_ (unit))))

    ;; A listener stays while the view keeps its event, captures and
    ;; prevention; its function may change, since only the table holds it.
    (: patch-listeners
       (All (M)
            (-> Node
                (List (Attribute M))
                (List (Pair String Listener))
                (List (Attribute M))
                (List (Pair String Listener))
                ! dom)))
    (define (patch-listeners node old listeners new)
      (for-each (lambda (pair)
                  (unless (kept-listener? (::first pair) old new) (unlisten (::second pair))))
                listeners)
      (append (filter (lambda (pair) (kept-listener? (::first pair) old new)) listeners)
              (listen-all node
                          (filter (lambda (attribute)
                                    (match attribute
                                      ((On event _ _ _) (not (kept-listener? event old new)))
                                      (_ #f)))
                                  new))))

    (: kept-listener? (All (M) (-> String (List (Attribute M)) (List (Attribute M)) Bool)))
    (define (kept-listener? event old new)
      (match (Pair (listening event old) (listening event new))
        ((Pair (Some (On _ captures prevent _)) (Some (On _ new-captures new-prevent _)))
         (and (= (capture-bits captures) (capture-bits new-captures))
              (same-prevent? prevent new-prevent)))
        (_ #f)))

    (: listening (All (M) (-> String (List (Attribute M)) (Option (Attribute M)))))
    (define (listening event attributes)
      (find (lambda (attribute)
              (match attribute
                ((On name _ _ _) (string=? name event))
                (_ #f)))
            attributes))

    (: same-prevent? (-> Prevent Prevent Bool))
    (define (same-prevent? a b)
      (match (Pair a b)
        ((Pair (Allow) (Allow)) #t)
        ((Pair (Always) (Always)) #t)
        ((Pair (Chords x) (Chords y))
         (and (= (length x) (length y)) (every? same-chord? (zip x y))))
        (_ #f)))

    (: same-chord? (-> (Pair Chord Chord) Bool))
    (define (same-chord? pair)
      (match pair
        ((Pair a b)
         (and (string=? (::key a) (::key b)) (= (::modifiers a) (::modifiers b))))))

    ;; ---- Children ----

    ;; A child with a key takes the old child with that key, and one
    ;; without takes the old child at its place among those without, when
    ;; they match; any other is new. The old children not taken are
    ;; removed, which leaves the document holding the taken ones in their
    ;; old order, and then the children are put in their new order.
    (: patch-children (All (M) (-> Node (List (Shown M)) (List (Html M)) (List (Shown M)) ! dom)))
    (define (patch-children parent old new)
      (let* ((pairs (taking old new))
             (taken (taken-names pairs))
             (children (map (lambda (pair)
                              (match (::first pair)
                                ((Some shown) (patch shown (::second pair)))
                                ((None) (create (::second pair)))))
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
    (: taking
       (All (M) (-> (List (Shown M)) (List (Html M)) (List (Pair (Option (Shown M)) (Html M))))))
    (define (taking old new)
      (let ((keys (filter (lambda (key) (not (string=? key ""))) (map html-key new))))
        (unless (= (length keys) (length (delete-duplicates string=? keys)))
          (panic "two children have the same key"))
        (taking-from (fold-left (lambda (keyed shown)
                                  (if (string=? (shown-key shown) "")
                                      keyed
                                      (table-set keyed (shown-key shown) shown)))
                                empty-table
                                old)
                     (filter (lambda (shown) (string=? (shown-key shown) "")) old)
                     new)))

    (: taking-from
       (All (M)
            (-> (Table (Shown M))
                (List (Shown M))
                (List (Html M))
                (List (Pair (Option (Shown M)) (Html M))))))
    (define (taking-from keyed unkeyed new)
      (match new
        ((Cons html rest)
         (if (string=? (html-key html) "")
             (match unkeyed
               ((Cons first others)
                (Cons (Pair (matching first html) html) (taking-from keyed others rest)))
               ((Nil) (Cons (Pair (None) html) (taking-from keyed unkeyed rest))))
             (Cons (Pair (match (table-ref keyed (html-key html))
                           ((Some shown) (matching shown html))
                           ((None) (None)))
                         html)
                   (taking-from keyed unkeyed rest))))
        ((Nil) (Nil))))

    (: matching (All (M) (-> (Shown M) (Html M) (Option (Shown M)))))
    (define (matching shown html)
      (if (matches? shown html) (Some shown) (None)))

    (: taken-names (All (M) (-> (List (Pair (Option (Shown M)) (Html M))) (Table Bool))))
    (define (taken-names pairs)
      (fold-left (lambda (taken pair)
                   (match (::first pair)
                     ((Some shown) (table-set taken (node-name shown) #t))
                     ((None) taken)))
                 empty-table
                 pairs))

    (: shown-key (All (M) (-> (Shown M) String)))
    (define (shown-key shown)
      (match shown
        ((ShownElement _ _ attributes _ _) (key-of attributes))
        ((ShownText _ _) "")))

    (: html-key (All (M) (-> (Html M) String)))
    (define (html-key html)
      (match html
        ((Element _ attributes _) (key-of attributes))
        ((Text _) "")))

    (: same-node? (All (M) (-> (Shown M) (Shown M) Bool)))
    (define (same-node? a b)
      (= (::handle (shown-node a)) (::handle (shown-node b))))

    ;; From the last child to the first, each goes before the one after it
    ;; unless it already is there. The document holds the taken children
    ;; not yet placed, `unplaced`, in their old order, before those placed;
    ;; so a child already is where it goes when it is the last of them.
    (: order
       (All (M) (-> Node (List (Shown M)) (List (Shown M)) (Table Bool) (Option Node) Unit ! dom)))
    (define (order parent children unplaced taken next)
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
    (: placed
       (All (M)
            (-> Node (Shown M) (List (Shown M)) (Table Bool) (Option Node) (List (Shown M)) ! dom)))
    (define (placed parent child unplaced taken next)
      (match unplaced
        ((Cons last others)
         (if (same-node? last child) others (moved parent child unplaced taken next)))
        ((Nil) (moved parent child unplaced taken next))))

    (: moved
       (All (M)
            (-> Node (Shown M) (List (Shown M)) (Table Bool) (Option Node) (List (Shown M)) ! dom)))
    (define (moved parent child unplaced taken next)
      (insert-node parent (shown-node child) next)
      (if (table-contains? taken (node-name child))
          (filter (lambda (shown) (not (same-node? shown child))) unplaced)
          unplaced))

    ;; ---- The window ----

    ;; The window is shown as an element without attributes or children:
    ;; only the listeners given it are patched, so any other attribute is
    ;; ignored.
    (: window-shown (All (M) (-> (List (Attribute M)) (Shown M) ! dom)))
    (define (window-shown attributes)
      (let ((node (window-node)))
        (ShownElement node "#window" attributes (listen-all node attributes) (Nil))))

    (: patch-window (All (M) (-> (Shown M) (List (Attribute M)) (Shown M) ! dom)))
    (define (patch-window shown attributes)
      (match shown
        ((ShownElement node tag old listeners _)
         (ShownElement node tag attributes (patch-listeners node old listeners attributes) (Nil)))
        ((ShownText _ _) (panic "internal error: the window shown as text"))))

    ;; ---- Listeners ----

    ;; Each listener's function in the trees, by the listener's id.
    (: listener-table (All (M) (-> (List (Shown M)) (Table (-> Event M)))))
    (define (listener-table trees)
      (fold-left (lambda (table pair)
                   (table-set table (show (::id (::second pair))) (::first pair)))
                 empty-table
                 (concatenate (map listener-functions trees))))

    (: listener-functions (All (M) (-> (Shown M) (List (Pair (-> Event M) Listener)))))
    (define (listener-functions shown)
      (match shown
        ((ShownText _ _) (Nil))
        ((ShownElement _ _ attributes listeners children)
         (append (concatenate
                  (map (lambda (pair)
                         (match (listening (::first pair) attributes)
                           ((Some (On _ _ _ message)) (list (Pair message (::second pair))))
                           (_ (Nil))))
                       listeners))
                 (concatenate (map listener-functions children))))))

    ;; ---- Running ----

    ;; The interface between deliveries: its model, the tree shown, the
    ;; window's listeners, and the listeners' functions by listener id,
    ;; which only `showing` builds, so they agree.
    (struct (Running Model M)
      ((model Model)
       (shown (Shown M))
       (window (Shown M))
       (listeners (Table (-> Event M)))))

    (: showing (All (Model M) (-> Model (Shown M) (Shown M) (Running Model M))))
    (define (showing model shown window)
      (Running model shown window (listener-table (list window shown))))

    ;; Shows the view of `model` in the document's root, with the listeners
    ;; `window` gives the window, updates it with each message in `start`,
    ;; and runs the interface, a delivery at a time, until the document
    ;; closes, then answers the last model. An event at a listener the view has since
    ;; dropped is ignored. `commit` publishes complete presentations;
    ;; `checkpoint` saves on request, hiding and close. A
    ;; command still running then never answers. Both `view` and `update`
    ;; take the model, and the loop keeps it for `checkpoint`, so a model
    ;; is shared rather than moved: it must be Copy.
    (: run-ui
       (All (Model M e) (requires (Copy Model))
            (-> Model
                (List M)
                (-> Model M (Pair Model (List (FnOnce M ! tasks e))))
                (-> Model (Html M))
                (-> Model (List (Attribute M)))
                (-> Model Unit ! e)
                (-> Model Unit ! tasks e)
                Model
                ! mut dom tasks e)))
    (define (run-ui model start update view window commit checkpoint)
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

    (: serve
       (All (Model M e) (requires (Copy Model))
            (-> (Mailbox M)
                (-> Model M (Pair Model (List (FnOnce M ! tasks e))))
                (-> Model (Html M))
                (-> Model (List (Attribute M)))
                (-> Model Unit ! e)
                (-> Model Unit ! tasks e)
                (Running Model M)
                Model
                ! mut dom tasks e)))
    (define (serve box update view window commit checkpoint running)
      (commit (::model running))
      (match (next-event)
        ((Fired listener event)
         (serve box
                update
                view
                window
                commit checkpoint
                (match (table-ref (::listeners running) (show (::id listener)))
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
         (checkpoint (::model running))
         (serve box update view window commit checkpoint running))
        ((SaveRequested)
         (checkpoint (::model running))
         (serve box update view window commit checkpoint running))
        ((Closed)
         (checkpoint (::model running))
         (::model running))))

    ;; The interface after every answer the mailbox holds.
    (: answered
       (All (Model M e) (requires (Copy Model))
            (-> (Mailbox M)
                (-> Model M (Pair Model (List (FnOnce M ! tasks e))))
                (-> Model (Html M))
                (-> Model (List (Attribute M)))
                (-> Model Unit ! e)
                (Running Model M)
                (Running Model M)
                ! mut dom e)))
    (define (answered box update view window commit running)
      (match (mailbox-try-receive box)
        ((Some message)
         (let ((next (updated box update view window running message)))
           (commit (::model next))
           (answered box update view window commit next)))
        ((None) running)))

    ;; The update for one message, the commands it started dispatched, and
    ;; the view and window of the next model shown.
    (: updated
       (All (Model M e) (requires (Copy Model))
            (-> (Mailbox M)
                (-> Model M (Pair Model (List (FnOnce M ! tasks e))))
                (-> Model (Html M))
                (-> Model (List (Attribute M)))
                (Running Model M)
                M
                (Running Model M)
                ! mut dom e)))
    (define (updated box update view window running message)
      (match (update (::model running) message)
        ((Pair model commands)
         (start-commands box commands)
         (showing model
                  (patch-root (::shown running) (view model))
                  (patch-window (::window running) (window model))))))

    (: start-commands (All (M e) (-> (Mailbox M) (List (FnOnce M ! tasks e)) Unit ! mut dom e)))
    (define (start-commands box commands)
      (match commands
        ((Cons command rest)
         (dispatch-local (once (lambda () (answer box command))))
         (start-commands box rest))
        ((Nil) (unit))))

    (: answer (All (M e) (-> (Mailbox M) (FnOnce M ! tasks e) Unit ! mut dom tasks e)))
    (define (answer box command)
      (mailbox-post box (command))
      (wake))

    ;; ---- Owned models ----

    ;; The model owns its pending futures. An input is Some message; None
    ;; is a generic wake after a completion. Update polls without waiting.
    ;; View, window and snapshot run inside explicit lexical loans. The loop keeps
    ;; ownership across waits; commit and checkpoint receive only snapshots.
    ;; The compiler checks update's callback has no control effects.
    (: run-reactor
       (All (Model M S e) (requires (Drop (! mut e) Model))
            (-> Model
                (List M)
                (-> Model (Option M) Model ! mut completion e)
                (-> (Borrow Model) (Html M))
                (-> (Borrow Model) (List (Attribute M)))
                (-> (Borrow Model) S)
                (-> S Unit ! mut e)
                (-> S Unit ! mut tasks e)
                Model ! mut dom tasks e)))
    (define (run-reactor model start update view window snapshot commit checkpoint)
      (handle completion ((completed wake))
        (mount-reactor model start update view window snapshot commit checkpoint)))

    (: mount-reactor
       (All (Model M S e) (requires (Drop (! mut e) Model))
            (-> Model
                (List M)
                (-> Model (Option M) Model ! mut completion e)
                (-> (Borrow Model) (Html M))
                (-> (Borrow Model) (List (Attribute M)))
                (-> (Borrow Model) S)
                (-> S Unit ! mut e)
                (-> S Unit ! mut tasks e)
                Model ! mut completion dom tasks e)))
    (define (mount-reactor model start update view window snapshot commit checkpoint)
      (let ((shown (create (with-borrow (read model) (view read))))
            (window-shown (window-shown (with-borrow (read model) (window read)))))
        (insert-node (document-root) (shown-node shown) (None))
        (serve-reactor update view window snapshot commit checkpoint
                       (fold-left (lambda (running message)
                                    (step-reactor update view window running (Some message)))
                                  (showing model shown window-shown)
                                  start))))

    (: serve-reactor
       (All (Model M S e) (requires (Drop (! mut e) Model))
            (-> (-> Model (Option M) Model ! mut completion e)
                (-> (Borrow Model) (Html M))
                (-> (Borrow Model) (List (Attribute M)))
                (-> (Borrow Model) S)
                (-> S Unit ! mut e)
                (-> S Unit ! mut tasks e)
                (Running Model M)
                Model ! mut completion dom tasks e)))
    (define (serve-reactor update view window snapshot commit checkpoint running)
      (match running
        ((Running model shown window-shown listeners)
         (commit (with-borrow (read model) (snapshot read)))
         ;; Give dispatched work a turn even when input is already queued.
         (yield)
         (match (next-event)
           ((Closed) (checkpoint (with-borrow (read model) (snapshot read))) model)
           ((Hidden)
            (checkpoint (with-borrow (read model) (snapshot read)))
            (serve-reactor update view window snapshot commit checkpoint
                           (Running model shown window-shown listeners)))
           ((SaveRequested)
            (checkpoint (with-borrow (read model) (snapshot read)))
            (serve-reactor update view window snapshot commit checkpoint
                           (Running model shown window-shown listeners)))
           ((Woken)
            (serve-reactor update view window snapshot commit checkpoint
                           (step-reactor update view window
                                         (Running model shown window-shown listeners) (None))))
           ((Fired listener event)
            (let ((running (Running model shown window-shown listeners)))
              (serve-reactor update view window snapshot commit checkpoint
                             (match (table-ref listeners (show (::id listener)))
                               ((Some message)
                                (step-reactor update view window running (Some (message event))))
                               ((None) running)))))))))

    (: step-reactor
       (All (Model M e)
            (-> (-> Model (Option M) Model ! mut completion e)
                (-> (Borrow Model) (Html M))
                (-> (Borrow Model) (List (Attribute M)))
                (Running Model M) (Option M)
                (Running Model M) ! mut completion dom e)))
    (define (step-reactor update view window running message)
      (match running
        ((Running model shown window-shown _)
         (render-reactor view window (update model message) shown window-shown))))

    ;; Finish both reads before moving the owner into Running. Listeners
    ;; may capture copied display data, but never the borrowed model.
    (: render-reactor
       (All (Model M)
            (-> (-> (Borrow Model) (Html M))
                (-> (Borrow Model) (List (Attribute M)))
                Model (Shown M) (Shown M) (Running Model M) ! dom)))
    (define (render-reactor view window model shown window-shown)
      (let ((shown (patch-root shown (with-borrow (read model) (view read))))
            (window-shown (patch-window window-shown (with-borrow (read model) (window read)))))
        (showing model shown window-shown)))

    ;; The root's one child, patched, or replaced by a new one.
    (: patch-root (All (M) (-> (Shown M) (Html M) (Shown M) ! dom)))
    (define (patch-root shown html)
      (let ((next (patch shown html)))
        (unless (same-node? next shown)
          (insert-node (document-root) (shown-node next) (None))
          (remove-node (shown-node shown)))
        next))))
