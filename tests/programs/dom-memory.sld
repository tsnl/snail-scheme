(import
 (snail core base)
 (snail core io)
 (snail shell dom)
 (snail shell dom memory))

;; The document in memory, driven through the `dom` effect: building a
;; tree, moving a node within it, replacing an element's text, typed
;; properties read back, listeners made and dropped, and removing a
;; subtree. The trace has a line per operation; the tree prints as HTML.

(: build (-> String ! dom))
(define (build)
  (let* ((root (document-root))
         (list-node (create-element "ul"))
         (first (create-element "li"))
         (second (create-element "li"))
         (field (create-element "input")))
    (set-attribute list-node "class" "items")
    (insert-node root list-node (None))
    (insert-node list-node first (None))
    (insert-node list-node second (Some first))
    (insert-node first (create-text "one < two") (None))
    (set-text second "two")
    (set-text second "deux")
    (insert-node list-node second (None))
    (insert-node root field (None))
    (set-string-property field "value" "typed")
    (set-number-property field "scrollTop" 12.5)
    (set-flag-property field "disabled" #t)
    (set-attribute list-node "class" "")
    (let ((keys (listen field
                        "keydown"
                        (list (Key) (Value))
                        (Chords (list (Chord "Tab" 0) (Chord "s" control-key)))))
          (clicks (listen first "click" (Nil) (Always))))
      (unlisten clicks)
      (focus-node field)
      (string-append (string-property field "value")
                     " "
                     (show (number-property field "scrollTop"))
                     " ["
                     (string-property field "missing")
                     "] "
                     (show (Listener-id keys))))))

(: result (Pair String Document))
(define result (with-memory-dom (Nil) build))

(write-line (Pair-first result))
(write-line (document->html (Pair-second result)))
(for-each write-line (document-trace (Pair-second result)))

(: removed Document)
(define removed
  (Pair-second (with-memory-dom (Nil) (lambda ()
                                        (let ((outer (create-element "div"))
                                              (inner (create-element "p")))
                                          (insert-node (document-root) outer (None))
                                          (insert-node outer inner (None))
                                          (remove-node outer)
                                          (insert-node (document-root)
                                                       (create-text "after")
                                                       (None)))))))

(write-line (document->html removed))
