(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell json)
 (snail shell ui)
 (snail shell ide application)
 (prefix (snail shell ide palette) palette-))

(record Requests
  ((reads I64)
   (completed I64)
   (events Bool)
   (hides I64)))

(record Request
  ((issued I64)))

(enum Delivery
  (Input ((message Msg)))
  (Produced ((read I64)
             (result CommandResult))))

;; This race driver controls when a command runs, using the IDE's actual
;; pure transitions. The other IDE tests run the owned-future reactor.
(record Model
  ((ide Ide)
   (answers I64)))

(define (jobs (delayed Bool)
              (gate (Mailbox Unit))
              (state Requests)
              (commands (List Command)))
  (→ (List (Fn → Delivery ! mut host output-port tasks dom fetch)))
  (! mut host)
  (match commands
    ((Nil) (Nil))
    ((Cons (Command work) rest)
     (Cons (lambda ()
             (when delayed
               (mailbox-receive gate)
               (set! (● state completed) (+ 1 (● state completed))))
             (observed work state))
           (jobs delayed gate state rest)))))

;; Record the request identity at its boundary, before it can suspend.
(define (observed (work (Fn → CommandResult ! tasks dom fetch)) (state Requests))
  (→ Delivery)
  (! mut tasks dom fetch)
  (let ((issued (new Request (issued 0))))
    (let ((result
           (handle fetch
               ((request (lambda (method url headers body)
                           (when (and (>= (string-length url) 10)
                                      (string=? (substring url 0 10) "/api/file?"))
                             (set! (● issued issued) (+ 1 (● state reads))))
                           (request method url headers body)))
                (stream-open (lambda (url kinds) (stream-open url kinds)))
                (stream-next (lambda (stream) (stream-next stream)))
                (stream-close (lambda (stream) (stream-close stream))))
             (work))))
      (Produced (● issued issued) result))))

(define (update-test (delayed-read Bool)
                     (gate (Mailbox Unit))
                     (state Requests)
                     (model Model)
                     (message Delivery))
  (→ (Pair Model
           (List (Fn → Delivery ! mut host output-port tasks dom fetch))))
  (! mut host)
  (match message
    ((Input message)
     (match (update (● model ide) message)
       ((Pair next commands)
        (new Pair
          (first (new Model (ide next) (answers (● model answers))))
          (second (jobs #f gate state commands))))))
    ((Produced read (CommandResult accept))
     (let ((transition (accept)))
       (match (transition (● model ide))
         ((Pair next commands)
          (new Pair
            (first (new Model (ide next) (answers (+ (● model answers) (if (> read 0) 1 0)))))
            (second (jobs (and (not delayed-read) (= read 2)) gate state commands)))))))))

(define (shown (model Model)) (→ (Html Delivery))
  (map-html Input (view (● model ide))))

(define (window-test (model Model)) (→ (List (Attribute Delivery)))
  (match (map-html Input (Element "window" (window (● model ide)) (Nil)))
    ((Element _ attributes _) attributes)
    (_ (panic "window attributes"))))

(define (input (text String))
  (→ Cue)
  (Fire "command-query" "input" (Event-value-set (no-event) text)))

(define (enter) (→ Cue) (Fire "command-query" "keydown" (Event-key-set (no-event) "Enter")))

(define (verify-focus (result (Pair Node Document))) (→ Unit)
  (let ((expected (string-append "focus " (show (● (● result first) handle))))
        (last (find (lambda (line) (and (>= (string-length line) 6)
                                        (string=? (substring line 0 6) "focus ")))
                    (reverse (document-trace (● result second))))))
    (match last
      ((Some line) (unless (string=? line expected) (panic "old task stole focus")))
      ((None) (panic "no focus")))))

(define (run (delayed-read Bool)) (→ Unit) (! mut host output-port tasks)
  (let ((state (new Requests (reads 0) (completed 0) (events #f) (hides 0))) (gate (make-mailbox)))
    (handle fetch
        ((request (lambda (method url headers body)
                    (cond ((string=? url "/api/project")
                           (Ok (new Reply (status 200)
                                    (body
                                     "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"notes.txt\"],\"directories\":[]}"))))
                          ((string=? url "/api/search?q=needle")
                           (Ok (new Reply (status 200)
                                    (body
                                     "{\"hits\":[{\"path\":\"notes.txt\",\"revision\":\"r\",\"line\":2,\"column\":1,\"snippet\":\"needle\"}],\"skipped\":0,\"limited\":false}"))))
                          (else
                           (set! (● state reads) (+ 1 (● state reads)))
                           (if (and delayed-read (= 2 (● state reads)))
                               (begin (mailbox-receive gate)
                                      (set! (● state completed) (+ 1 (● state completed)))
                                      (Err "obsolete failed read"))
                               (Ok
                                (new Reply
                                  (status 200)
                                  (body "{\"text\":\"line\\nneedle\",\"revision\":\"r\"}"))))))))
         (stream-open (lambda (url kinds) (new Stream (id 1))))
         (stream-next (lambda (stream)
                        (if (● state events) (None)
                            (begin
                              (set! (● state events) #t)
                              (Some (new StreamEvent (kind "open") (data "")))))))
         (stream-close (lambda (stream) (unit))))
      (verify-focus (with-memory-dom
                     (list (FireWindow "keydown" (Event-key-set (no-event) "F1"))
                           (input "search-project") (enter) (input "needle") (Hide) (enter)
                           (if delayed-read (FireWindow "online" (no-event))
                               (FireWindow "keydown"
                                           (Event-modifiers-set (Event-key-set (no-event) "\\")
                                                                (control-key))))
                           (Hide))
                     (lambda ()
                       (let ((final (run-ui (new Model (ide (initial)) (answers 0))
                                            (list (Input (Open "notes.txt")))
                                            (lambda (model message)
                                              (update-test delayed-read
                                                           gate
                                                           state
                                                           model
                                                           message))
                                            shown
                                            window-test
                                            (lambda (model) (unit))
                                            (lambda (model)
                                              (set! (● state hides) (+ 1 (● state hides)))
                                              (if (= (● state hides) 1)
                                                  (sleep 150)
                                                  (mailbox-post gate (unit)))))))
                         (unless (= (● state reads) (● final answers))
                           (panic "the delayed read did not finish")))
                       (match (element-by-id "text-0")
                         ((Some field) (write-line (show (● (selection-range field) first))))
                         ((None) (panic "missing original field")))
                       (match (element-by-id (if delayed-read "text-0" "text-1"))
                         ((Some node) node)
                         ((None) (panic "missing expected editor"))))))
      (unless (= (● state completed) 1)
        (panic "the delayed operation did not finish"))
      (write-line (if delayed-read "obsolete failure cannot reveal cached coordinates"
                      "queued reveal cannot steal focus after a split")))))

(define (main) (→ Unit) (! host mut output-port tasks)
  (dispatch-local (lambda () (run #t) (run #f)))
  (unit))
