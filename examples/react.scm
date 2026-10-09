;; Run with: chibi-scheme -I src examples/react.scm
(import (scheme base) (scheme write) (snail-scheme react))

(define (notice props children)
  (create-element 'admonition props children))

(define (document props children)
  (create-element 'document props
                  (create-element 'heading '() "Scheme components")
                  (create-element notice '((kind . warning))
                                  (create-element 'paragraph '() "These are ordinary functions."))
                  children))

(define (button props children)
  (create-element 'button props children))

(define page
  (create-element document '((title . "Composition"))
                  (map (lambda (n)
                         (create-element 'paragraph '() "Square: " (* n n)))
                       '(1 2 3))))

(define window
  (create-element 'window '((title . "Editor"))
                  (create-element 'row '()
                                  (create-element button '((action . save)) "Save")
                                  (create-element button '((action . cancel)) "Cancel"))))

(write (render page))
(newline)
(write (render window))
(newline)
