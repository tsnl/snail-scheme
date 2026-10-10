;; An application is a model and two ordinary procedures. The host owns the
;; current application value; components never allocate hidden state slots.
(define-library (snail-scheme ui)
  (export application application? application-model application-view dispatch)
  (import (scheme base))
  (begin
    (define-record-type <application>
      (application model update view)
      application?
      (model application-model)
      (update application-update)
      (view application-view-procedure))

    (define (application-view app)
      ((application-view-procedure app) (application-model app)))

    ;; Reducers follow Elm's argument order: message, then model. Return a new
    ;; model without mutating the old one; exceptions leave the old app usable.
    (define (dispatch app message)
      (application ((application-update app) message (application-model app))
                   (application-update app) (application-view-procedure app)))))
