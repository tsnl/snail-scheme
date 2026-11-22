;; The page's document for the `dom` effect: `with-page-dom` binds each
;; operation to the browser host's document (host/browser/dom.mjs), which
;; keeps the interface's nodes and listeners in tables by handle, under the
;; container the page gives it. Deliveries come from the page's event queue
;; ((snail shell page)): a listener's event as a kind the host fires with
;; what it captured, a wake, the page hidden, and a save's timer. A page's
;; document never closes. One task, the interface's loop, waits for the
;; next delivery; `wake` reaches the host from any task.
(define-library (snail shell dom page)
  (export
   page-dom)
  (import
   (snail core base)
   (prefix (snail runtime browser dom) host-)
   (snail shell utf8)
   (snail shell task)
   (snail shell page)
   (snail shell dom))
  (begin

    ;; ---- Handling ----

    (define (page-dom (events Events)) (→ Dom)
      (new Dom
        (document-root (lambda () (new Node (handle (host-root)))))
        (create-element
         (lambda (tag) (new Node (handle (host-create-element (string->utf8 tag))))))
        (create-text (lambda (text) (new Node (handle (host-create-text (string->utf8 text))))))
        (set-attribute (lambda (node name value)
                         (host-set-attribute (● node handle) (named name value))))
        (set-text (lambda (node text) (host-set-text (● node handle) (string->utf8 text))))
        (set-string-property (lambda (node name value)
                               (host-set-string-property (● node handle) (named name value))))
        (set-number-property (lambda (node name value)
                               (host-set-number-property (● node handle)
                                                         value
                                                         (string->utf8 name))))
        (set-flag-property (lambda (node name value)
                             (host-set-flag-property (● node handle)
                                                     (if value 1 0)
                                                     (string->utf8 name))))
        (string-property (lambda (node name)
                           (host-reply
                            (host-string-property (● node handle) (string->utf8 name)))))
        (number-property (lambda (node name)
                           (host-number-property (● node handle) (string->utf8 name))))
        (insert-node (lambda (parent child before)
                       (host-insert (● parent handle)
                                    (● child handle)
                                    (match before
                                      ((Some node) (● node handle))
                                      ((None) -1)))))
        (remove-node (lambda (node) (host-remove (● node handle))))
        (listen (lambda (node event captures prevent) (listen-node node event captures prevent)))
        (unlisten (lambda (listener) (host-unlisten (● listener id))))
        (focus-node (lambda (node) (host-focus (● node handle))))
        (window-node (lambda () (new Node (handle -1))))
        (confirm (lambda (question) (= (host-confirm (string->utf8 question)) 1)))
        (installation-status page-installation-status)
        (install-app page-install)
        (fullscreen? (lambda () (= 1 (host-fullscreen))))
        (set-fullscreen (lambda (enter)
                          (= 1
                             (through-host
                              (lambda (ticket) (host-start-fullscreen ticket (if enter 1 0)))
                              host-finish-fullscreen))))
        (element-by-id (lambda (id)
                         (let ((handle (host-element-by-id (string->utf8 id))))
                           (if (< handle 0) (None) (Some (new Node (handle handle)))))))
        (select-range (lambda (node start end) (host-select-range (● node handle) start end)))
        (selection-range (lambda (node)
                           (new Pair (first (host-selection-start (● node handle)))
                                (second (host-selection-end (● node handle))))))
        (insert-text (lambda (node start end text)
                       (= (host-insert-text (● node handle) start end (string->utf8 text))
                          1)))
        (measure (lambda (node) (measure-node (● node handle))))
        (wake (lambda () (host-wake)))
        (next-event (lambda () (page-delivery events)))))

    ;; ---- Window applications ----

    (define (page-installation-status) (→ InstallationStatus)
      (case (host-installation-status)
        ((1) (InstallAvailable)) ((2) (AppInstalled)) (else (InstallUnavailable))))

    (define (page-install) (→ InstallResult)
      (case (through-host host-start-install host-finish-install)
        ((0) (InstallAccepted)) ((1) (InstallDismissed)) ((2) (InstallNotAvailable))
        ((3) (GestureRequired)) ((5) (InstallAlreadyInstalled)) (else (InstallFailed))))

    ;; ---- Deliveries ----

    ;; The kinds of event the host fires for an interface. A fired event's
    ;; fields are the listener's id, the modifier keys, the pointer's
    ;; buttons, the selection's start and end, and whether the target is
    ;; checked; its numbers, the pointer's position and the target's
    ;; scroll offsets, and its texts, the target's value and the key, are
    ;; read beside it.

    (define fired-kind (→ I32) 14)

    (define woken-kind (→ I32) 15)

    ;; The next delivery, skipping the display frames and resizes an
    ;; interface has no use for.

    (define (page-delivery (events Events)) (→ Delivery) (! mut)
      (let ((kind (poll-event events)))
        (cond ((= kind 0) (wait-event events) (page-delivery events))
              ((= kind fired-kind)
               (Fired (new Listener (id (event-field events 0))) (fired-event events)))
              ((= kind woken-kind) (Woken))
              ((= kind hidden-kind) (Hidden))
              ((= kind save-kind) (SaveRequested))
              (else (page-delivery events)))))

    (define (fired-event (events Events)) (→ Event) (! mut)
      (new Event (value (host-reply (host-event-text 0)))
           (key (host-reply (host-event-text 1)))
           (modifiers (event-field events 1))
           (x (host-event-number 0))
           (y (host-event-number 1))
           (buttons (event-field events 2))
           (scroll-top (host-event-number 2))
           (scroll-left (host-event-number 3))
           (selection-start (event-field events 3))
           (selection-end (event-field events 4))
           (checked (= (event-field events 5) 1))))

    ;; ---- The browser host ----

    ;; A measure crosses a number at a time, in the order of its fields.

    (define (measure-node (handle I32)) (→ Measure)
      (host-measure handle)
      (new Measure (left (host-measured 0))
           (top (host-measured 1))
           (width (host-measured 2))
           (height (host-measured 3))
           (client-width (host-measured 4))
           (client-height (host-measured 5))
           (line-height (host-measured 6))))

    (define (named (name String) (value String)) (→ Bytes)
      (string->utf8 (string-append name (make-string 1 #\null) value)))

    (define (host-reply (count I32)) (→ String)
      (string-generate (i32->i64 count)
                       (lambda (index)
                         (integer->char (i32->i64 (host-reply-scalar (i64->i32 index)))))))

    ;; A listener prevents by kind: 0 never, 1 always, 2 for its chords,
    ;; which follow it.

    (define (listen-node (node Node) (event String) (captures (List Capture)) (prevent Prevent))
      (→ Listener)
      (let ((id (host-listen (● node handle)
                             (capture-bits captures)
                             (match prevent
                               ((Allow) 0)
                               ((Always) 1)
                               ((Chords _) 2))
                             (string->utf8 event))))
        (match prevent
          ((Chords chords)
           (for-each (lambda (chord)
                       (host-listen-chord id
                                          (● chord modifiers)
                                          (string->utf8 (● chord key))))
                     chords))
          (_ (unit)))
        (new Listener (id id))))))
