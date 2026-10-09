;; HTML is one consumer of generic trees. Attribute and text conventions live
;; here; the composition library does not know about tags, forms, or escaping.
(define-library (snail-scheme html)
  (export button render-html)
  (import (scheme base) (scheme write) (snail-scheme react))
  (begin
    (define-record-type <action>
      (make-action message)
      action?
      (message action-message))

    (define (button message label)
      (if (not (string? label)) (error "button: expected a text label" label))
      (element 'button (make-action message) label))

    ;; Return markup and a URL-to-message alist. Without a prefix, emit a static
    ;; snapshot with disabled buttons. Messages never leave the Scheme host.
    (define (render-html description . prefix)
      (let ((out (open-output-string)) (actions '()) (next-action 0))
        (define (register message)
          (let ((url (string-append (car prefix) (number->string next-action))))
            (set! actions (cons (cons url message) actions))
            (set! next-action (+ next-action 1))
            url))
        (for-each (lambda (node) (write-node node out (and (pair? prefix) register) #f))
                  (resolve description))
        (values (get-output-string out) (reverse actions))))

    (define (write-node node out register in-form?)
      (cond
       ((element? node) (write-element node out register in-form?))
       ((string? node) (write-escaped node out))
       ((number? node) (write-escaped (number->string node) out))
       ((char? node) (write-escaped (string node) out))
       (else (error "HTML: expected an element, string, number, or character" node))))

    (define (write-escaped text out)
      (string-for-each
       (lambda (character)
         (display (case character
                    ((#\&) "&amp;") ((#\<) "&lt;") ((#\>) "&gt;")
                    ((#\") "&quot;") ((#\') "&#39;")
                    (else character)) out))
       text))

    (define (html-name name)
      (if (not (symbol? name)) (error "HTML: expected a symbol name" name))
      (let ((text (symbol->string name)))
        (if (or (zero? (string-length text))
                (not (char<=? #\a (string-ref text 0) #\z))
                (not (valid-name-tail? (string->list text))))
            (error "HTML: invalid name" name))
        text))

    (define (valid-name-tail? characters)
      (or (null? characters)
          (and (or (char<=? #\a (car characters) #\z)
                   (char<=? #\0 (car characters) #\9)
                   (memv (car characters) '(#\- #\_ #\:)))
               (valid-name-tail? (cdr characters)))))

    (define (write-element node out register in-form?)
      (if (action? (element-data node))
          (write-node (button-tree node register in-form?) out register in-form?)
          (write-tag (element-type node) (element-data node)
                     (element-children node) out register in-form?)))

    (define (button-tree node register in-form?)
      (if register
          (begin
            (if in-form? (error "HTML: action button cannot nest inside a form"))
            (element 'form `((method . "post") (action . ,(register (action-message (element-data node)))))
                     (apply element 'button '((type . "submit")) (element-children node))))
          (apply element 'button '((type . "button") (disabled . #t)) (element-children node))))

    ;; Raw-text elements need a different escaping contract. Check structural
    ;; errors before writing a tag; ordinary style attributes are supported.
    (define (check-tag type children in-form?)
      (if (memq type '(script style xmp iframe noembed noframes plaintext noscript))
          (error "HTML: raw-text element unsupported" type))
      (if (and in-form? (eq? type 'form)) (error "HTML: nested form"))
      (if (and (void-tag? type) (pair? children)) (error "HTML: void element has children" type)))

    (define (void-tag? type)
      (memq type '(area base br col embed hr img input link meta param source track wbr)))

    (define (write-tag type attributes children out register in-form?)
      (let ((name (html-name type)))
        (check-tag type children in-form?)
        (display (string-append "<" name) out)
        (write-attributes attributes out)
        (display ">" out)
        (if (not (void-tag? type))
            (begin
              (for-each (lambda (child) (write-node child out register (or in-form? (eq? type 'form))))
                        children)
              (display (string-append "</" name ">") out)))))

    (define (write-attributes attributes out)
      (if (not (list? attributes)) (error "HTML: expected attribute association list" attributes))
      (let loop ((entries attributes) (seen '()))
        (if (pair? entries)
            (let ((entry (car entries)))
              (if (not (pair? entry)) (error "HTML: expected attribute pair" entry))
              (if (memq (car entry) seen) (error "HTML: duplicate attribute" (car entry)))
              (write-attribute (html-name (car entry)) (cdr entry) out)
              (loop (cdr entries) (cons (car entry) seen))))))

    (define (write-attribute name value out)
      (if value
          (begin
            (display (string-append " " name) out)
            (if (not (eq? value #t))
                (begin
                  (display "=\"" out)
                  (write-escaped (attribute-text value) out)
                  (display "\"" out))))))

    (define (attribute-text value)
      (cond ((string? value) value)
            ((number? value) (number->string value))
            (else (error "HTML: expected a string, number, or boolean attribute" value))))))
