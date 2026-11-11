;; A page's document as an effect: the primitives a user interface needs to
;; build and change it. A node is a handle the host keeps in a table, so no
;; host object crosses into Snail-Core and no closure crosses out. A
;; listener says, when it is made, what its events carry and which of them
;; the host prevents the default action of, since the host must decide both
;; synchronously, while the event is being dispatched. The browser host
;; binds the effect to the page; `(snail shell dom memory)` binds it to a
;; document in memory, so an interface can be tested without one.
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
   dom
   document-root
   refresh-page
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
   (snail core base)
   (only (snail shell task) tasks))
  (begin

    ;; ---- Handles ----

    ;; A node of the document. The root is the page's container, which the
    ;; interface owns entirely; removing a node frees its handle and those
    ;; of the nodes under it.
    (struct Node
      ((handle I32)))

    (struct Listener
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
    (struct Chord
      ((key String)
       (modifiers I32)))

    (: control-key I32)
    (define control-key 1)

    (: shift-key I32)
    (define shift-key 2)

    (: alt-key I32)
    (define alt-key 4)

    (: meta-key I32)
    (define meta-key 8)

    ;; The captures as the host's bits, each kind's bit its position in
    ;; `Capture`.
    (: capture-bits (impl (Fn (List Capture) -> I32)))
    (define (capture-bits captures)
      (fold-left + 0 (delete-duplicates = (map capture-bit captures))))

    (: capture-bit (impl (Fn Capture -> I32)))
    (define (capture-bit capture)
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
    (struct Event
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

    (: no-event Event)
    (define no-event (Event "" "" 0 0.0 0.0 0 0.0 0.0 0 0 #f))

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
    (struct Measure
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

    ;; ---- The effect ----

    ;; An attribute set to "" is removed. A property is the node's own
    ;; field, such as an input's `value` or `checked` or an element's
    ;; `scrollTop`, of one of three kinds; reading one the node does not
    ;; have answers "" or 0. A node inserted where it already is moves
    ;; there, before `before` or at the end. A text node's text is its
    ;; data; an element's is its only child. `next-event` waits for the
    ;; next delivery, in the order they happened. Only the task that runs
    ;; the interface waits for them; any other task performs `wake` to
    ;; have that one woken, once however many times it is performed
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
    (effect dom
      ((document-root (dyn (Fn -> Node)))
       (create-element (dyn (Fn String -> Node)))
       (create-text (dyn (Fn String -> Node)))
       (set-attribute (dyn (Fn Node String String -> Unit)))
       (set-text (dyn (Fn Node String -> Unit)))
       (set-string-property (dyn (Fn Node String String -> Unit)))
       (set-number-property (dyn (Fn Node String F64 -> Unit)))
       (set-flag-property (dyn (Fn Node String Bool -> Unit)))
       (string-property (dyn (Fn Node String -> String)))
       (number-property (dyn (Fn Node String -> F64)))
       (insert-node (dyn (Fn Node Node (Option Node) -> Unit)))
       (remove-node (dyn (Fn Node -> Unit)))
       (listen (dyn (Fn Node String (List Capture) Prevent -> Listener)))
       (unlisten (dyn (Fn Listener -> Unit)))
       (focus-node (dyn (Fn Node -> Unit)))
       (window-node (dyn (Fn -> Node)))
       (refresh-page (dyn (Fn -> Unit)))
       (confirm (dyn (Fn String -> Bool)))
       (installation-status (dyn (Fn -> InstallationStatus)))
       (install-app (dyn (Fn -> InstallResult ! tasks)))
       (fullscreen? (dyn (Fn -> Bool)))
       (set-fullscreen (dyn (Fn Bool -> Bool ! tasks)))
       (element-by-id (dyn (Fn String -> (Option Node))))
       (select-range (dyn (Fn Node I32 I32 -> Unit)))
       (selection-range (dyn (Fn Node -> (Pair I32 I32))))
       (insert-text (dyn (Fn Node I32 I32 String -> Bool)))
       (measure (dyn (Fn Node -> Measure)))
       (wake (dyn (Fn -> Unit)))
       (next-event (dyn (Fn -> Delivery ! tasks)))))))
