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
  (let* ((root ((● dom document-root)))
         (list-node ((● dom create-element) "ul"))
         (first ((● dom create-element) "li"))
         (second ((● dom create-element) "li"))
         (field ((● dom create-element) "input")))
    ((● dom set-attribute) list-node "class" "items")
    ((● dom insert-node) root list-node (None))
    ((● dom insert-node) list-node first (None))
    ((● dom insert-node) list-node second (Some first))
    ((● dom insert-node) first ((● dom create-text) "one < two") (None))
    ((● dom set-text) second "two")
    ((● dom set-text) second "deux")
    ((● dom insert-node) list-node second (None))
    ((● dom insert-node) root field (None))
    ((● dom set-string-property) field "value" "typed")
    ((● dom set-number-property) field "scrollTop" 12.5)
    ((● dom set-flag-property) field "disabled" #t)
    ((● dom set-attribute) list-node "class" "")
    (let ((keys ((● dom listen) field
                 "keydown"
                 (list (Key) (Value))
                 (Chords (list (new Chord (key "Tab") (modifiers 0))
                               (new Chord (key "s") (modifiers control-key))))))
          (clicks ((● dom listen) first "click" (Nil) (Always))))
      ((● dom unlisten) clicks)
      ((● dom focus-node) field)
      (string-append ((● dom string-property) field "value")
                     " "
                     (show ((● dom number-property) field "scrollTop"))
                     " ["
                     ((● dom string-property) field "missing")
                     "] "
                     (show (● keys id))))))

(define (main (out OutputPort)) (→ Unit)

  (define result (→ (Pair String Document)) (with-memory-dom (Nil) (lambda (dom) (build dom))))
  (define removed (→ Document)
    (● (with-memory-dom (Nil) (lambda (dom)
                                (let ((outer ((● dom create-element) "div"))
                                      (inner ((● dom create-element) "p")))
                                  ((● dom insert-node) ((● dom document-root)) outer (None))
                                  ((● dom insert-node) outer inner (None))
                                  ((● dom remove-node) outer)
                                  ((● dom insert-node) ((● dom document-root))
                                   ((● dom create-text) "after")
                                   (None))))) second))
  (write-line out (● result first))
  (write-line out (document->html (● result second)))
  (for-each (lambda (text) (write-line out text)) (document-trace (● result second)))
  (write-line out (document->html removed))
  (unit))
