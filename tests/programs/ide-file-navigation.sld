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

;; Files are supplied by the service. Selection and fuzzy filtering run in
;; the IDE, and the selected path is read through the ordinary buffer flow.
(: snapshot (-> (Borrow Session) Ide))
(define (snapshot session)
  (::ide session))

(: finished (-> Session Ide ! mut))
(define (finished session)
  (match session
    ((Session ide pending) (drop pending) ide)))

(dispatch-local
 (once (lambda ()
         (let ((events (ref #f)) (requests (ref (ann (Nil) (List String)))))
           (let ((result
                  (handle fetch
                      ((request (lambda (method url headers body)
                                  (ref-set! requests (append (ref-get requests) (list url)))
                                  (Ok (Reply 200
                                             (cond ((string=? url "/api/project")
                                                    "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"main.sld\",\"lib/notes.txt\"],\"directories\":[\"lib\"]}")
                                                   ((string=? url "/api/file?path=main.sld")
                                                    "{\"text\":\"main\",\"revision\":\"main\"}")
                                                   ((string=? url "/api/file?path=lib%2Fnotes.txt")
                                                    "{\"text\":\"notes\",\"revision\":\"notes\"}")
                                                   (else (panic url)))))))
                       (stream-open (lambda (url kinds) (Stream 1)))
                       (stream-next (lambda (stream)
                                      (if (ref-get events) (None)
                                          (begin
                                            (ref-set! events #t)
                                            (Some (StreamEvent "open" ""))))))
                       (stream-close (lambda (stream) (unit))))
                    (with-memory-dom
                     (list (FireWindow "keydown"
                                       (Event-modifiers-set (Event-key-set no-event "p") meta-key))
                           (Fire "command-query" "input" (Event-value-set no-event "lnote"))
                           (Fire "command-query" "keydown" (Event-key-set no-event "Enter")))
                     (lambda ()
                       (finished (run-reactor (begin-session initial)
                                              (list (Connect))
                                              (ann update-session
                                                   (-> Session
                                                       (Option Msg)
                                                       Session
                                                       ! mut completion console dom fetch))
                                              session-view
                                              session-window
                                              snapshot
                                              (lambda (model) (unit))
                                              (lambda (model) (unit)))))))))
             (for-each write-line (ref-get requests))
             (match (buffer-at (::first result) "lib/notes.txt")
               ((Some buffer) (write-line (::text buffer)))
               ((None) (panic "file navigation did not finish"))))))))
