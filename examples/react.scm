;; Run with: chibi-scheme -I src examples/react.scm
(import (scheme base) (scheme write) (snail-scheme react))

(define (note kind children)
  (apply element 'note kind children))

(define (document title children)
  (element 'document title
           (element 'heading #f "Scheme components")
           (element note 'aside (element 'paragraph #f "These are ordinary functions."))
           (apply fragment children)))

(define page
  (element document "Composition"
           (apply fragment (map (lambda (n) (element 'paragraph #f "Square: " (* n n))) '(1 2 3)))))

(define window
  (element 'window "Editor"
           (element 'row #f (element 'button 'save "Save") (element 'button 'cancel "Cancel"))))

;; This example chooses an s-expression display format. The library returns
;; element records, and a different consumer can preserve richer Scheme data.
(define (tree->datum tree)
  (if (element? tree)
      (cons (element-type tree)
            (cons (element-data tree) (map tree->datum (element-children tree))))
      tree))

(write (map tree->datum (resolve page)))
(newline)
(write (map tree->datum (resolve window)))
(newline)
