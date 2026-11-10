(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell ui)
 (snail shell ide application))

;; A DOM edit can precede its input message. Change the live field after
;; formatting was scheduled but before its command runs. Neither replacement
;; nor scroll restoration may act on the obsolete field snapshot.
(: snapshot (-> (Borrow Session) Ide))
(define (snapshot session)
  (::ide session))

(: finished (-> Session Ide ! mut))
(define (finished session)
  (match session ((Session ide pending) (drop pending) ide)))

(: replace-field (-> Bool Unit ! dom))
(define (replace-field changed-path)
  (match (Pair (element-by-id "text-0") (element-by-id "editor-0"))
    ((Pair (Some field) (Some scroller))
     (set-string-property field (if changed-path "snailPath" "value")
                          (if changed-path "other.sld" "newer"))
     (set-number-property scroller "scrollTop" 88.0))
    (_ (panic "missing editor")))
  (unit))

(: race-update (-> Bool (Ref Bool) Session (Option Msg) Session ! mut completion dom fetch))
(define (race-update changed-path injected session message)
  (let ((next (update-session session message)))
    ;; The first completion applies the named command and queues formatting.
    ;; Change the DOM before that queued task gets its next scheduler turn.
    (when (and (match message ((None) #t) (_ #f)) (not (ref-get injected)))
      (ref-set! injected #t)
      (replace-field changed-path))
    next))

(: report-editor (-> Unit ! dom console))
(define (report-editor)
  (match (Pair (element-by-id "text-0") (element-by-id "editor-0"))
    ((Pair (Some field) (Some scroller))
     (write-line (string-property field "value"))
     (write-line (show (number-property scroller "scrollTop"))))
    (_ (panic "missing editor"))))

(: run (-> Bool Unit ! mut console tasks))
(define (run changed-path)
  (handle fetch
      ((request (lambda (method url headers body)
                  (Ok (Reply 200 "{\"text\":\"(a   b)\",\"revision\":\"first\"}"))))
       (stream-open (lambda (url kinds) (panic "stream")))
       (stream-next (lambda (stream) (panic "stream")))
       (stream-close (lambda (stream) (panic "stream"))))
    (let ((loaded (::first (with-memory-dom (Nil)
                                            (lambda ()
                                              (finished
                                               (run-reactor (begin-session initial)
                                                            (list (Open "main.sld"))
                                                            (ann update-session
                                                                 (-> Session
                                                                     (Option Msg)
                                                                     Session
                                                                     ! mut completion console dom fetch))
                                                            session-view session-window snapshot
                                                            (lambda (model) (unit))
                                                            (lambda (model) (unit))))))))
          (injected (ref #f)))
      (with-memory-dom (Nil)
                       (lambda ()
                         (drop (run-reactor (begin-session loaded)
                                            (list (DispatchCommand "format-buffer"))
                                            (ann (lambda (model msg)
                                                   (race-update changed-path injected model msg))
                                                 (-> Session
                                                     (Option Msg)
                                                     Session
                                                     ! mut completion console dom fetch))
                                            session-view session-window snapshot
                                            (lambda (model) (unit)) (lambda (model) (unit))))
                         (report-editor)))
      (unless (ref-get injected) (panic "the formatting race was not exercised"))
      (unit))))


(dispatch-local (once (lambda () (run #f) (run #t))))
