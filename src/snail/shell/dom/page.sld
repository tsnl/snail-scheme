;; The page's document for the `dom` effect: `with-page-dom` binds each
;; operation to the browser host's document (host/browser/dom.mjs), which
;; keeps the interface's nodes and listeners in tables by handle, under the
;; container the page gives it. Deliveries come from the page's event queue
;; ((snail shell page)): a listener's event as a kind the host fires with
;; what it captured, a wake, the page hidden, and a reload, which closes
;; the document. Only the root task polls the queue, so only it may wait
;; for the next delivery; `wake` reaches the host from any task.
(define-library (snail shell dom page)
  (export
   with-page-dom)
  (import
   (snail core base)
   (prefix (snail runtime browser dom) host-)
   (snail shell utf8)
   (snail shell task)
   (snail shell page)
   (snail shell dom))
  (begin

    ;; ---- Handling ----

    (: with-page-dom (All (T e) (-> (-> T ! dom e) T ! events e)))
    (define (with-page-dom work)
      (handle dom
          ((document-root (lambda () (Node (host-root))))
           (create-element (lambda (tag) (Node (host-create-element (string->utf8 tag)))))
           (create-text (lambda (text) (Node (host-create-text (string->utf8 text)))))
           (set-attribute (lambda (node name value)
                            (host-set-attribute (Node-handle node) (named name value))))
           (set-text (lambda (node text) (host-set-text (Node-handle node) (string->utf8 text))))
           (set-string-property (lambda (node name value)
                                  (host-set-string-property (Node-handle node) (named name value))))
           (set-number-property (lambda (node name value)
                                  (host-set-number-property (Node-handle node)
                                                            value
                                                            (string->utf8 name))))
           (set-flag-property (lambda (node name value)
                                (host-set-flag-property (Node-handle node)
                                                        (if value 1 0)
                                                        (string->utf8 name))))
           (string-property (lambda (node name)
                              (host-reply
                               (host-string-property (Node-handle node) (string->utf8 name)))))
           (number-property (lambda (node name)
                              (host-number-property (Node-handle node) (string->utf8 name))))
           (insert-node (lambda (parent child before)
                          (host-insert (Node-handle parent)
                                       (Node-handle child)
                                       (match before
                                         ((Some node) (Node-handle node))
                                         ((None) -1)))))
           (remove-node (lambda (node) (host-remove (Node-handle node))))
           (listen (lambda (node event captures prevent) (listen-node node event captures prevent)))
           (unlisten (lambda (listener) (host-unlisten (Listener-id listener))))
           (focus-node (lambda (node) (host-focus (Node-handle node))))
           ;; dom.mjs keeps the window at handle -1.
           (window-node (lambda () (Node -1)))
           (confirm (lambda (question) (= (host-confirm (string->utf8 question)) 1)))
           (element-by-id (lambda (id)
                            (let ((handle (host-element-by-id (string->utf8 id))))
                              (if (< handle 0) (None) (Some (Node handle))))))
           (select-range (lambda (node start end) (host-select-range (Node-handle node) start end)))
           (selection-range (lambda (node)
                              (Pair (host-selection-start (Node-handle node))
                                    (host-selection-end (Node-handle node)))))
           (insert-text (lambda (node start end text)
                          (= (host-insert-text (Node-handle node) start end (string->utf8 text))
                             1)))
           (measure (lambda (node) (measure-node (Node-handle node))))
           (wake (lambda () (host-wake)))
           (next-event page-delivery))
        (work)))

    ;; ---- Deliveries ----

    ;; The kinds of event the host fires for an interface. A fired event's
    ;; fields are the listener's id, the modifier keys, the pointer's
    ;; buttons, the selection's start and end, and whether the target is
    ;; checked; its numbers, the pointer's position and the target's
    ;; scroll offsets, and its texts, the target's value and the key, are
    ;; read beside it.
    (: fired-kind I32)
    (define fired-kind 14)

    (: woken-kind I32)
    (define woken-kind 15)

    ;; The next delivery, skipping the display frames and resizes an
    ;; interface has no use for.
    (: page-delivery (-> Delivery ! events tasks))
    (define (page-delivery)
      (let ((kind (poll-event)))
        (cond ((= kind 0) (wait-event) (page-delivery))
              ((= kind fired-kind) (Fired (Listener (event-field 0)) (fired-event)))
              ((= kind woken-kind) (Woken))
              ((= kind hidden-kind) (Hidden))
              ((= kind reload-kind) (Closed))
              (else (page-delivery)))))

    (: fired-event (-> Event ! events))
    (define (fired-event)
      (Event (host-reply (host-event-text 0))
             (host-reply (host-event-text 1))
             (event-field 1)
             (host-event-number 0)
             (host-event-number 1)
             (event-field 2)
             (host-event-number 2)
             (host-event-number 3)
             (event-field 3)
             (event-field 4)
             (= (event-field 5) 1)))

    ;; ---- The browser host ----

    ;; A measure crosses a number at a time, in the order of its fields.
    (: measure-node (-> I32 Measure))
    (define (measure-node handle)
      (host-measure handle)
      (Measure (host-measured 0)
               (host-measured 1)
               (host-measured 2)
               (host-measured 3)
               (host-measured 4)
               (host-measured 5)
               (host-measured 6)))

    (: named (-> String String Bytes))
    (define (named name value)
      (string->utf8 (string-append name (make-string 1 #\null) value)))

    (: host-reply (-> I32 String))
    (define (host-reply count)
      (string-generate (i32->i64 count)
                       (lambda (index)
                         (integer->char (i32->i64 (host-reply-scalar (i64->i32 index)))))))

    ;; A listener prevents by kind: 0 never, 1 always, 2 for its chords,
    ;; which follow it.
    (: listen-node (-> Node String (List Capture) Prevent Listener))
    (define (listen-node node event captures prevent)
      (let ((id (host-listen (Node-handle node)
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
                                          (Chord-modifiers chord)
                                          (string->utf8 (Chord-key chord))))
                     chords))
          (_ (unit)))
        (Listener id)))))
