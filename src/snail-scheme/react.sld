;; A Chibi-hosted experiment in functional tree composition. Constructing an
;; element describes a call; rendering resolves components into ordinary data.
(define-library (snail-scheme react)
  (export create-element element? element-type element-props element-children render)
  (import (scheme base))
  (begin
    ;; Descriptions
    ;;
    ;; A symbol names a host node; a procedure is a component taking props and
    ;; unrendered children. Descriptions, their lists, and property values are
    ;; immutable by convention. The record deliberately has no setters.
    (define-record-type <element>
      (make-element type props children)
      element?
      (type element-type)
      (props element-props)
      (children element-children))

    (define (create-element type props . children)
      (if (not (or (symbol? type) (procedure? type)))
          (error "create-element: expected a symbol or component procedure" type))
      (check-props props)
      (make-element type props children))

    (define (check-props props)
      (if (not (list? props))
          (error "create-element: expected a property association list" props))
      (let loop ((entries props) (names '()))
        (if (pair? entries)
            (let ((name (checked-property-name (car entries))))
              (if (memq name names)
                  (error "create-element: duplicate property" name))
              (loop (cdr entries) (cons name names))))))

    (define (checked-property-name entry)
      (if (not (and (pair? entry) (symbol? (car entry))))
          (error "create-element: expected a property with a symbol name" entry))
      (car entry))

    ;; Rendering
    ;;
    ;; The result is a forest: strings, numbers, and (tag props child ...) lists.
    ;; Proper lists of descriptions are fragments; #f and () contribute nothing.
    ;; Visit selected children from left to right. A reversed accumulator avoids
    ;; repeatedly appending the prefixes of nested fragments.
    (define (render description)
      (reverse (render-into description '())))

    (define (render-into description reversed)
      (cond
       ((or (eq? description #f) (null? description)) reversed)
       ((or (string? description) (number? description)) (cons description reversed))
       ((element? description) (render-element description reversed))
       ((pair? description) (render-children description reversed))
       (else (error "render: expected an element, text, number, fragment, or #f"
                    description))))

    (define (render-children children reversed)
      (if (not (list? children)) (error "render: expected a proper child list" children))
      (let loop ((children children) (reversed reversed))
        (if (null? children) reversed
            (loop (cdr children) (render-into (car children) reversed)))))

    (define (render-element element reversed)
      (let ((type (element-type element))
            (props (element-props element))
            (children (element-children element)))
        (if (procedure? type)
            (render-into (type props children) reversed)
            (cons (cons type (cons props (render children))) reversed))))))
