(import
 (snail core base)
 (snail core io)
 (snail shell dom)
 (snail shell dom memory))

;; The document in memory, driven through the `dom` effect: building a
;; tree, moving a node within it, replacing an element's text, typed
;; properties read back, listeners made and dropped, and removing a
;; subtree. The trace has a line per operation; the tree prints as HTML.

(define (build) (→ String) (! dom)
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
                        (Chords (list (new Chord (key "Tab") (modifiers 0))
                                      (new Chord (key "s") (modifiers (control-key)))))))
          (clicks (listen first "click" (Nil) (Always))))
      (unlisten clicks)
      (focus-node field)
      (string-append (string-property field "value")
                     " "
                     (show (number-property field "scrollTop"))
                     " ["
                     (string-property field "missing")
                     "] "
                     (show (● keys id))))))

(define (main) (→ Unit) (! mut output-port)

  (define result (→ (Pair String Document)) (with-memory-dom (Nil) (once build)))
  (define removed (→ Document)
    (● (with-memory-dom (Nil) (lambda ()
                                (let ((outer (create-element "div"))
                                      (inner (create-element "p")))
                                  (insert-node (document-root) outer (None))
                                  (insert-node outer inner (None))
                                  (remove-node outer)
                                  (insert-node (document-root)
                                               (create-text "after")
                                               (None))))) second))
  (write-line (● result first))
  (write-line (document->html (● result second)))
  (for-each write-line (document-trace (● result second)))
  (write-line (document->html removed))
  (unit))
