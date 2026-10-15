;; A local Chibi host: GET observes a prepared page; POST reduces a message and
;; prepares its successor. One session owns the app and serializes publication.
(define-library (snail-scheme ui-server)
  (export run-ui application->html)
  (import (scheme base) (srfi 18) (srfi 27)
          (chibi net) (chibi net http-server) (chibi net servlet)
          (snail-scheme ui) (snail-scheme html))
  (begin
    (define-record-type <page>
      (make-page app revision content actions)
      page?
      (app page-app)
      (revision page-revision)
      (content page-content)
      (actions page-actions))

    (define-record-type <session>
      (make-session page mutex)
      session?
      (page session-page session-page-set!)
      (mutex session-mutex))

    (define (prepare-page app revision)
      (let ((prefix (string-append "/event/" (number->string revision) "/")))
        (let-values (((body actions) (render-html (application-view app) prefix)))
          (make-page app revision (string-append "<!doctype html>" body) actions))))

    (define (application->html app)
      (let-values (((body actions) (render-html (application-view app))))
        (string-append "<!doctype html>" body)))

    ;; Starting each run at a fresh revision prevents an old tab from submitting
    ;; its actions to a restarted application. This is not authentication.
    (define (initial-revision)
      (let ((source (make-random-source)))
        (random-source-randomize! source)
        ((random-source-make-integers source) (expt 2 128))))

    (define (run-ui app port)
      (run-http-server (get-address-info "127.0.0.1" port)
                       (session-servlet (make-session (prepare-page app (initial-revision))
                                                      (make-mutex)))))

    (define (session-servlet session)
      (lambda (config request next restart)
        (dynamic-wind
            (lambda () (mutex-lock! (session-mutex session)))
            (lambda () (serve-request session request))
            (lambda () (mutex-unlock! (session-mutex session))))))

    (define (serve-request session request)
      (case (request-method request)
        ((GET)
         (if (string=? (request-path request) "/")
             (servlet-write request (page-content (session-page session))
                            '((Cache-Control . "no-store")))
             (servlet-respond request 404 "Not Found")))
        ((POST) (serve-action session request))
        (else (servlet-respond request 405 "Method Not Allowed" '((Allow . "GET, POST"))))))

    (define (serve-action session request)
      (let* ((page (session-page session))
             (action (assoc (request-path request) (page-actions page))))
        (if action
            (begin
              (publish-message! session page (cdr action))
              (servlet-respond request 303 "See Other" '((Location . "/") (Cache-Control . "no-store"))))
            (servlet-write-conflict request))))

    ;; Complete reduction and view rendering before replacing the current page.
    ;; Reducers and views must preserve their input model: host mutation cannot
    ;; be rolled back. Exceptions otherwise leave the old page and actions intact.
    (define (publish-message! session page message)
      (let ((next (prepare-page (dispatch (page-app page) message) (+ 1 (page-revision page)))))
        (session-page-set! session next)))

    (define (servlet-write-conflict request)
      (servlet-respond request 409 "Conflict")
      (servlet-write request "This view is out of date. <a href=\"/\">Reload the page</a>."))))
