;; HTTP test fixture: view counting checks caching; failures check publication.
(import (scheme base) (scheme process-context)
        (snail-scheme react) (snail-scheme ui) (snail-scheme html) (snail-scheme ui-server))

(define view-calls 0)
(define (update message model)
  (case message
    ((fail-update) (error "intentional reducer failure"))
    ((fail-view) 'broken-view)
    ((fail-html) 'broken-html)
    ((noop) model)
    (else (+ model 1))))

(define (view model)
  (set! view-calls (+ view-calls 1))
  (case model
    ((broken-view) (error "intentional view failure"))
    ((broken-html) (element 'img '() "invalid child"))
    (else
     (element 'main '()
              (element 'output '((id . "count")) model)
              (element 'output '((id . "calls")) view-calls)
              (button #f "False message") (button 'noop "No change")
              (button 'fail-update "Fail reducer") (button 'fail-view "Fail view")
              (button 'fail-html "Fail HTML")))))

(run-ui (application 0 update view) (string->number (cadr (command-line))))
