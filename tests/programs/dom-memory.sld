(import
 (snail core base)
 (snail core io)
 (snail shell dom)
 (snail shell dom memory))

;; The document in memory, driven through the `dom` effect: building a
;; tree, moving a node within it, replacing an element's text, typed
;; properties read back, listeners made and dropped, and removing a
;; subtree. The trace has a line per operation; the tree prints as HTML.

(define (build (dom Dom)) (→ String)
  (let* ((root (document-root dom))
         (list-node (create-element dom "ul"))
         (first (create-element dom "li"))
         (second (create-element dom "li"))
         (field (create-element dom "input")))
    (set-attribute dom list-node "class" "items")
    (insert-node dom root list-node (None))
    (insert-node dom list-node first (None))
    (insert-node dom list-node second (Some first))
    (insert-node dom first (create-text dom "one < two") (None))
    (set-text dom second "two")
    (set-text dom second "deux")
    (insert-node dom list-node second (None))
    (insert-node dom root field (None))
    (set-string-property dom field "value" "typed")
    (set-number-property dom field "scrollTop" 12.5)
    (set-flag-property dom field "disabled" #t)
    (set-attribute dom list-node "class" "")
    (let ((keys (listen dom field
                        "keydown"
                        (list (Key) (Value))
                        (Chords (list (new Chord (key "Tab") (modifiers 0))
                                      (new Chord (key "s") (modifiers control-key))))))
          (clicks (listen dom first "click" (Nil) (Always))))
      (unlisten dom clicks)
      (focus-node dom field)
      (string-append (string-property dom field "value")
                     " "
                     (show (number-property dom field "scrollTop"))
                     " ["
                     (string-property dom field "missing")
                     "] "
                     (show (● keys id))))))

(define (main (mut Mut) (out OutputPort)) (→ Unit)

  (define result (→ (Pair String Document)) (with-memory-dom mut (Nil) (lambda (dom) (build dom))))
  (define removed (→ Document)
    (● (with-memory-dom mut (Nil) (lambda (dom)
                                    (let ((outer (create-element dom "div"))
                                          (inner (create-element dom "p")))
                                      (insert-node dom (document-root dom) outer (None))
                                      (insert-node dom outer inner (None))
                                      (remove-node dom outer)
                                      (insert-node dom (document-root dom)
                                                   (create-text dom "after")
                                                   (None))))) second))
  (write-line out (● result first))
  (write-line out (document->html (● result second)))
  (for-each (lambda (text) (write-line out text)) (document-trace (● result second)))
  (write-line out (document->html removed))
  (unit))
