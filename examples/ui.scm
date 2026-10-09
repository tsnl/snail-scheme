;; Run: chibi-scheme -I src examples/ui.scm [PORT]
;; Snapshot the same application: chibi-scheme -I src examples/ui.scm --html
(import (scheme base) (scheme process-context) (scheme write)
        (snail-scheme react) (snail-scheme ui) (snail-scheme html) (snail-scheme ui-server))

(define-record-type <model>
  (make-model count notes?)
  model?
  (count model-count)
  (notes? model-notes?))

(define (update message model)
  (case (if (pair? message) (car message) message)
    ((adjust) (make-model (+ (model-count model) (cadr message)) (model-notes? model)))
    ((toggle-notes) (make-model (model-count model) (not (model-notes? model))))
    ((reset) (make-model 0 #f))
    (else (error "unknown message" message))))

(define (counter model children)
  (element 'section `((aria-label . "Counter") (style . ,panel-style))
           (element 'h2 '() "Try a small change")
           (element 'output '((id . "count") (aria-live . "polite") (style . "display:block;font-size:3em")) (model-count model))
           (element 'div '((style . "display:flex;flex-wrap:wrap;gap:12px"))
                    (button '(adjust -1) "Decrease")
                    (button '(adjust 1) "Increase")
                    (button 'reset "Reset"))))

(define (notes model children)
  (if (model-notes? model)
      (element 'aside `((id . "notes") (style . ,panel-style))
               (element 'h2 '() "One view, different moments")
               (element 'p '() "A document describes the current model. An action changes the model, "
                        "and the same view describes what comes next."))
      (fragment)))

(define (workbook model)
  (element 'main '()
           (element 'p '() "SNAIL-SCHEME / A SMALL WORKBOOK")
           (element 'h1 '() "A document that responds")
           (element 'p '() "Read a paragraph, try an idea, and see the result. "
                    "The prose and the controls belong to the same document.")
           (element counter model)
           (button 'toggle-notes (if (model-notes? model) "Hide explanation" "Show explanation"))
           (element notes model)))

(define panel-style
  "background:white;padding:24px;border:1px solid #ddd9cd;border-radius:12px;margin:24px 0")

;; The document shell belongs to the application, just like its content.
(define (view model)
  (element 'html '((lang . "en"))
           (element 'head '()
                    (element 'meta '((charset . "utf-8")))
                    (element 'meta '((name . "viewport") (content . "width=device-width, initial-scale=1")))
                    (element 'title '() "A document that responds"))
           (element 'body '((style . "margin:0;background:#f5f3ed;color:#242a29;font:18px/1.6 system-ui,sans-serif"))
                    (element 'div '((style . "max-width:740px;margin:64px auto;padding:0 24px"))
                             (workbook model)))))

(define app (application (make-model 0 #f) update view))
(define arguments (cdr (command-line)))
(if (> (length arguments) 1) (error "usage: ui.scm [PORT | --html]"))
(if (equal? arguments '("--html"))
    (display (application->html app))
    (let ((port (if (null? arguments) 8765 (string->number (car arguments)))))
      (if (not (and (exact-integer? port) (< 0 port 65536))) (error "invalid port" port))
      (display "Open http://127.0.0.1:") (display port) (display "/\n")
      (flush-output-port (current-output-port))
      (run-ui app port)))
