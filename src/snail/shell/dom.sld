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
   Node-handle
   Listener
   Listener-id
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
   Chord-key
   Chord-modifiers
   Event
   Event-value
   Event-value-set
   Event-key
   Event-key-set
   Event-modifiers
   Event-modifiers-set
   Event-x
   Event-x-set
   Event-y
   Event-y-set
   Event-buttons
   Event-buttons-set
   Event-scroll-top
   Event-scroll-top-set
   Event-scroll-left
   Event-scroll-left-set
   Event-selection-start
   Event-selection-start-set
   Event-selection-end
   Event-selection-end-set
   Event-checked
   Event-checked-set
   no-event
   Measure
   Measure-left
   Measure-top
   Measure-width
   Measure-height
   Measure-client-width
   Measure-client-height
   Measure-line-height
   Delivery
   Fired
   Woken
   Hidden
   Closed
   control-key
   shift-key
   alt-key
   meta-key
   dom
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
   element-by-id
   select-range
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
    ;; all.
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
    (: capture-bits (-> (List Capture) I32))
    (define (capture-bits captures)
      (fold-left + 0 (delete-duplicates = (map capture-bit captures))))

    (: capture-bit (-> Capture I32))
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
    ;; captured, and the rest as `no-event` has them.
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
    ;; a range of a text field, insert text into one as typing would, so
    ;; the page can undo it, scroll through the scroll properties, and
    ;; measure. A command may run after the view has removed its node, so
    ;; these find a removed node does nothing, and reads of it answer ""
    ;; or 0.
    (effect dom
      ((document-root (-> Node))
       (create-element (-> String Node))
       (create-text (-> String Node))
       (set-attribute (-> Node String String Unit))
       (set-text (-> Node String Unit))
       (set-string-property (-> Node String String Unit))
       (set-number-property (-> Node String F64 Unit))
       (set-flag-property (-> Node String Bool Unit))
       (string-property (-> Node String String))
       (number-property (-> Node String F64))
       (insert-node (-> Node Node (Option Node) Unit))
       (remove-node (-> Node Unit))
       (listen (-> Node String (List Capture) Prevent Listener))
       (unlisten (-> Listener Unit))
       (focus-node (-> Node Unit))
       (element-by-id (-> String (Option Node)))
       (select-range (-> Node I32 I32 Unit))
       (insert-text (-> Node I32 I32 String Unit))
       (measure (-> Node Measure))
       (wake (-> Unit))
       (next-event (-> Delivery ! tasks))))))
