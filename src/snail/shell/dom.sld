;; A page's document as a capability, `Dom`: the primitives a user
;; interface needs to build and change it. A node is a handle the host keeps in a table, so no
;; host object crosses into `snail-scheme` and no closure crosses out. A
;; listener says, when it is made, what its events carry and which of them
;; the host prevents the default action of, since the host must decide both
;; synchronously, while the event is being dispatched. `(snail shell dom
;; page)` makes the page's `Dom`, and `(snail shell dom memory)` one over a
;; document in memory, so an interface can be tested without a page.
(define-library (snail shell dom)
  (export
   Node
   Listener
   Capture
   Value
   Key
   Pointer
   Scroll
   Selection
   Checked
   Prevent
   Allow
   Always
   Chords
   Chord
   Event
   Event-value-set
   Event-key-set
   Event-modifiers-set
   Event-x-set
   Event-y-set
   Event-buttons-set
   Event-scroll-top-set
   Event-scroll-left-set
   Event-selection-start-set
   Event-selection-end-set
   Event-checked-set
   no-event
   Measure
   Delivery
   Fired
   Woken
   Hidden
   SaveRequested
   Closed
   control-key
   shift-key
   alt-key
   meta-key
   Dom
   document-root
   create-element
   create-text
   set-attribute
   set-text
   set-string-property
   set-number-property
   set-flag-property
   string-property
   number-property
   insert-node
   remove-node
   listen
   unlisten
   focus-node
   window-node
   confirm
   InstallationStatus InstallUnavailable InstallAvailable AppInstalled
   InstallResult
   InstallAccepted
   InstallDismissed
   InstallNotAvailable
   GestureRequired
   InstallFailed
   InstallAlreadyInstalled
   installation-status install-app fullscreen? set-fullscreen
   element-by-id
   select-range
   selection-range
   insert-text
   measure
   wake
   next-event
   capture-bits)
  (import
   (snail core base))
  (begin

    ;; ---- Handles ----

    ;; A node of the document. The root is the page's container, which the
    ;; interface owns entirely; removing a node frees its handle and those
    ;; of the nodes under it.
    (record Node
      ((handle I32)))

    (record Listener
      ((id I32)))

    ;; ---- Listeners ----

    ;; What a listener reads from its event as it fires, for the interface
    ;; to read when it handles it: the target's value, the key and its
    ;; modifiers, the pointer's position and buttons, the target's scroll
    ;; offsets, its selection, or whether it is checked.
    (enum Capture
      (Value)
      (Key)
      (Pointer)
      (Scroll)
      (Selection)
      (Checked))

    ;; Whether the host prevents an event's default action: never, always,
    ;; or for a key that matches one of the chords exactly, modifiers and
    ;; all. A listener with chords hears only those keys, so the keys an
    ;; interface leaves alone never reach it, and never a key that ends an
    ;; input method's composition, which belongs to the input method.
    (enum Prevent
      (Allow)
      (Always)
      (Chords ((chords (List Chord)))))

    ;; A key as an event names it, such as "Tab" or "s", and the modifiers
    ;; held with it, the sum of the modifier keys' bits below.
    (record Chord
      ((key String)
       (modifiers I32)))

    (define control-key (→ I32) 1)

    (define shift-key (→ I32) 2)

    (define alt-key (→ I32) 4)

    (define meta-key (→ I32) 8)

    ;; The captures as the host's bits, each kind's bit its position in
    ;; `Capture`.

    (define (capture-bits (captures (List Capture))) (→ I32)
      (fold-left + 0 (delete-duplicates = (map capture-bit captures))))

    (define (capture-bit (capture Capture)) (→ I32)
      (match capture
        ((Value) 1)
        ((Key) 2)
        ((Pointer) 4)
        ((Scroll) 8)
        ((Selection) 16)
        ((Checked) 32)))

    ;; ---- Events ----

    ;; What an event carried when it fired: each field its listener
    ;; captured, and the rest as `no-event` has them. A selection's offsets
    ;; count scalars, as a String's indices do.
    (record Event
      ((value String)
       (key String)
       (modifiers I32)
       (x F64)
       (y F64)
       (buttons I32)
       (scroll-top F64)
       (scroll-left F64)
       (selection-start I32)
       (selection-end I32)
       (checked Bool)))

    (define no-event
      (→ Event)
      (new Event
        (value "")
        (key "")
        (modifiers 0)
        (x 0.0)
        (y 0.0)
        (buttons 0)
        (scroll-top 0.0)
        (scroll-left 0.0)
        (selection-start 0)
        (selection-end 0)
        (checked #f)))

    ;; What the next event is: a listener fired, carrying what it captured;
    ;; something performed `wake`; the page was hidden, so an interface
    ;; should keep what it would lose; or the document will fire no more.
    (enum Delivery
      (Fired ((listener Listener)
              (event Event)))
      (Woken)
      (Hidden)
      (SaveRequested)
      (Closed))

    ;; ---- Measuring ----

    ;; Where a node's box lies in the page's viewport and how big it is, the
    ;; size of what it shows inside its borders and scroll bars, and the
    ;; height of its lines, in CSS pixels.
    (record Measure
      ((left F64)
       (top F64)
       (width F64)
       (height F64)
       (client-width F64)
       (client-height F64)
       (line-height F64)))

    ;; ---- Window applications ----

    ;; A browser offer is opaque and single use. Acceptance of its prompt
    ;; precedes the distinct appinstalled event. An expired activation does
    ;; not consume the offer; another explicit click can try again.
    (enum InstallationStatus (InstallUnavailable) (InstallAvailable) (AppInstalled))
    (enum InstallResult (InstallAccepted) (InstallDismissed) (InstallNotAvailable)
          (GestureRequired) (InstallFailed) (InstallAlreadyInstalled))

    ;; ---- The capability ----

    ;; An attribute set to "" is removed. A property is the node's own
    ;; field, such as an input's `value` or `checked` or an element's
    ;; `scrollTop`, of one of three kinds; reading one the node does not
    ;; have answers "" or 0. A node inserted where it already is moves
    ;; there, before `before` or at the end. A text node's text is its
    ;; data; an element's is its only child. `next-event` waits for the
    ;; next delivery, in the order they happened. Only the task that runs
    ;; the interface waits for them; any other task calls `wake` to
    ;; have that one woken, once however many times it is called
    ;; before the wait sees it.
    ;;
    ;; A command reaches the nodes the view made by their `id` attribute,
    ;; through `element-by-id`, to do what a view cannot say: focus, select
    ;; a range of a text field or read its selection, insert text into one
    ;; as typing would, so the page can undo it, scroll through the scroll
    ;; properties, and measure, and offsets count scalars here too. A command may run after
    ;; the view has removed its node, so these find a removed node does
    ;; nothing, and reads of it answer "" or 0. `insert-text` answers
    ;; whether the field took the text; one that could not leaves it as
    ;; it was. `confirm` asks the person a question and answers whether
    ;; they agreed.
    ;;
    ;; `window-node` is the page's window, which holds the document and no
    ;; view does: the interface's window listeners are on it, for what
    ;; reaches the whole page, such as a shortcut or the page going back
    ;; online. It has no attributes or properties.
    (record Dom
      ((document-root (Fn → Node ! mut))
       (create-element (Fn String → Node ! mut))
       (create-text (Fn String → Node ! mut))
       (set-attribute (Fn Node String String → Unit ! mut))
       (set-text (Fn Node String → Unit ! mut))
       (set-string-property (Fn Node String String → Unit ! mut))
       (set-number-property (Fn Node String F64 → Unit ! mut))
       (set-flag-property (Fn Node String Bool → Unit ! mut))
       (string-property (Fn Node String → String ! mut))
       (number-property (Fn Node String → F64 ! mut))
       (insert-node (Fn Node Node (Option Node) → Unit ! mut))
       (remove-node (Fn Node → Unit ! mut))
       (listen (Fn Node String (List Capture) Prevent → Listener ! mut))
       (unlisten (Fn Listener → Unit ! mut))
       (focus-node (Fn Node → Unit ! mut))
       (window-node (Fn → Node ! mut))
       (confirm (Fn String → Bool ! mut))
       (installation-status (Fn → InstallationStatus ! mut))
       (install-app (Fn → InstallResult ! mut))
       (fullscreen? (Fn → Bool ! mut))
       (set-fullscreen (Fn Bool → Bool ! mut))
       (element-by-id (Fn String → (Option Node) ! mut))
       (select-range (Fn Node I32 I32 → Unit ! mut))
       (selection-range (Fn Node → (Pair I32 I32) ! mut))
       (insert-text (Fn Node I32 I32 String → Bool ! mut))
       (measure (Fn Node → Measure ! mut))
       (wake (Fn → Unit ! mut))
       (next-event (Fn → Delivery ! mut))))

    (define (document-root (dom Dom)) (→ Node) (! mut)
      ((● dom document-root)))

    (define (create-element (dom Dom) (tag String)) (→ Node) (! mut)
      ((● dom create-element) tag))

    (define (create-text (dom Dom) (text String)) (→ Node) (! mut)
      ((● dom create-text) text))

    (define (set-attribute (dom Dom) (node Node) (name String) (value String)) (→ Unit) (! mut)
      ((● dom set-attribute) node name value))

    (define (set-text (dom Dom) (node Node) (text String)) (→ Unit) (! mut)
      ((● dom set-text) node text))

    (define (set-string-property (dom Dom) (node Node) (name String) (value String))
      (→ Unit)
      (! mut)
      ((● dom set-string-property) node name value))

    (define (set-number-property (dom Dom) (node Node) (name String) (value F64)) (→ Unit) (! mut)
      ((● dom set-number-property) node name value))

    (define (set-flag-property (dom Dom) (node Node) (name String) (value Bool)) (→ Unit) (! mut)
      ((● dom set-flag-property) node name value))

    (define (string-property (dom Dom) (node Node) (name String)) (→ String) (! mut)
      ((● dom string-property) node name))

    (define (number-property (dom Dom) (node Node) (name String)) (→ F64) (! mut)
      ((● dom number-property) node name))

    (define (insert-node (dom Dom) (parent Node) (child Node) (before (Option Node)))
      (→ Unit)
      (! mut)
      ((● dom insert-node) parent child before))

    (define (remove-node (dom Dom) (node Node)) (→ Unit) (! mut)
      ((● dom remove-node) node))

    (define (listen (dom Dom)
                    (node Node)
                    (event String)
                    (captures (List Capture))
                    (prevent Prevent))
      (→ Listener)
      (! mut)
      ((● dom listen) node event captures prevent))

    (define (unlisten (dom Dom) (listener Listener)) (→ Unit) (! mut)
      ((● dom unlisten) listener))

    (define (focus-node (dom Dom) (node Node)) (→ Unit) (! mut)
      ((● dom focus-node) node))

    (define (window-node (dom Dom)) (→ Node) (! mut)
      ((● dom window-node)))

    (define (confirm (dom Dom) (question String)) (→ Bool) (! mut)
      ((● dom confirm) question))

    (define (installation-status (dom Dom)) (→ InstallationStatus) (! mut)
      ((● dom installation-status)))

    (define (install-app (dom Dom)) (→ InstallResult) (! mut)
      ((● dom install-app)))

    (define (fullscreen? (dom Dom)) (→ Bool) (! mut)
      ((● dom fullscreen?)))

    (define (set-fullscreen (dom Dom) (enter Bool)) (→ Bool) (! mut)
      ((● dom set-fullscreen) enter))

    (define (element-by-id (dom Dom) (id String)) (→ (Option Node)) (! mut)
      ((● dom element-by-id) id))

    (define (select-range (dom Dom) (node Node) (start I32) (end I32)) (→ Unit) (! mut)
      ((● dom select-range) node start end))

    (define (selection-range (dom Dom) (node Node)) (→ (Pair I32 I32)) (! mut)
      ((● dom selection-range) node))

    (define (insert-text (dom Dom) (node Node) (start I32) (end I32) (text String)) (→ Bool) (! mut)
      ((● dom insert-text) node start end text))

    (define (measure (dom Dom) (node Node)) (→ Measure) (! mut)
      ((● dom measure) node))

    (define (wake (dom Dom)) (→ Unit) (! mut)
      ((● dom wake)))

    (define (next-event (dom Dom)) (→ Delivery) (! mut)
      ((● dom next-event)))))
