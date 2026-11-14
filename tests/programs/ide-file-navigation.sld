(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell ui)
 (snail shell wire)
 (snail shell ide application))

(record Requests
  ((events Bool)
   (requests (List String))))

;; Files are supplied by the service. Selection and fuzzy filtering run in
;; the IDE, and the selected path is read through the ordinary buffer flow.
(define (snapshot (session Session)) (→ Ide) (! mut host)
  (● session ide))

(define (finished (session Session)) (→ Ide) (! mut host)
  (close-session! session)
  (● session ide))

(define (recovered (bytes Bytes)) (→ Unit) (! output-port)
  (let ((model (restored (read-recovery bytes))))
    (write-line (string-join (● (list-ref (● model panes) 0) tabs) ","))
    (match (buffer-at model "lib/notes.txt")
      ((Some buffer) (write-line (● buffer text)))
      ((None) (panic "draft lost during recovery")))))

(define (main) (→ Unit) (! host mut output-port completion tasks)
  (dispatch-local
   (once (lambda ()
           (let ((state (new Requests (events #f) (requests (Nil)))))
             (let ((result
                    (handle fetch
                        ((request (lambda (method url headers body)
                                    (set! (● state requests) (append (● state requests) (list url)))
                                    (Ok (new Reply (status 200)
                                             (body (cond ((string=? url "/api/project")
                                                          "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"main.sld\",\"lib/notes.txt\"],\"directories\":[\"lib\"]}")
                                                         ((string=? url "/api/file?path=main.sld")
                                                          "{\"text\":\"main\",\"revision\":\"main\"}")
                                                         ((string=? url
                                                                    "/api/file?path=lib%2Fnotes.txt")
                                                          "{\"text\":\"notes\",\"revision\":\"notes\"}")
                                                         (else (panic url))))))))
                         (stream-open (lambda (url kinds) (new Stream (id 1))))
                         (stream-next (lambda (stream)
                                        (if (● state events) (None)
                                            (begin
                                              (set! (● state events) #t)
                                              (Some (new StreamEvent (kind "open") (data "")))))))
                         (stream-close (lambda (stream) (unit))))
                      (with-memory-dom
                       (list (FireWindow "keydown"
                                         (Event-modifiers-set (Event-key-set (no-event) "p")
                                                              (meta-key)))
                             (Fire "command-query" "input" (Event-value-set (no-event) "lnote"))
                             (Fire "command-query" "keydown" (Event-key-set (no-event) "Enter"))
                             (Fire "text-0" "input" (Event-value-set (no-event) "draft notes")))
                       (lambda ()
                         (finished (run-reactor (begin-session (initial))
                                                (list (Connect))
                                                (lambda (model message)
                                                  (update-session model message))
                                                (lambda (model) (session-view model))
                                                (lambda (model) (session-window model))
                                                (lambda (model) (snapshot model))
                                                (lambda (model) (unit))
                                                (lambda (model) (unit)))))))))
               (for-each write-line (● state requests))
               ;; The new envelope retains tab order; the original wire record
               ;; upgrades to one tab per pane and keeps the same unsaved draft.
               (recovered (serialize (kept (● result first))))
               (recovered (serialize (● (kept (● result first)) previous)))
               (match (buffer-at (● result first) "lib/notes.txt")
                 ((Some buffer) (write-line (● buffer text)))
                 ((None) (panic "file navigation did not finish"))))))))
  (unit))
