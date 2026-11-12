(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell json)
 (snail shell ui)
 (snail shell ide application)
 (only (snail shell ide palette) visible?))

;; The actual IDE update/view/command loop, with HTTP replies controlled at
;; the fetch effect. A Hide cue releases a held reply only after later input
;; has reached the model. Completion counts prove the test did not merely
;; close the document with the important command still suspended.
(enum Delay
  (NoDelay)
  (SaveReply)
  (ReloadReply)
  (SecondRead))

(define (reply (text String) (revision String)) (→ (Result Reply String))
  (Ok (Reply 200
             (json->string (JsonObject (list (Pair "text" (JsonString text))
                                             (Pair "revision" (JsonString revision))))))))

(define (key (name String) (modifiers I32)) (→ Cue)
  (FireWindow "keydown" (Event-modifiers-set (Event-key-set no-event name) modifiers)))

(define (input (id String) (text String)) (→ Cue)
  (Fire id "input" (Event-value-set no-event text)))

(define (invoke (name String)) (→ (List Cue))
  (list (key "F1" 0) (input "command-query" name)
        (Fire "command-query" "keydown" (Event-key-set no-event "Enter"))))

(define (snapshot (session (Borrow Session))) (→ Ide)
  (● session ide))

(define (finished (session Session)) (→ Ide) (! mut)
  (match session
    ((Session ide pending) (drop pending) ide)))

(define (run (delay Delay) (cues (List Cue))) (→ (Pair Ide Document)) (! mut output-port tasks)
  (let ((disk (ref "disk")) (revision (ref "initial")) (reads (ref 0))
        (writes (ref 0)) (completed (ref 0)) (streamed (ref #f)) (gate (make-mailbox)))
    (let ((result
           (handle fetch
               ((request
                 (lambda (method url headers body)
                   (if (string=? url "/api/project")
                       (Ok (Reply 200
                                  "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"notes.txt\"],\"directories\":[]}"))
                       (let ((saving (string=? method "PUT")))
                         (if saving
                             (begin (ref-set! disk body) (ref-set! revision "saved")
                                    (ref-set! writes (+ 1 (ref-get writes))))
                             (ref-set! reads (+ 1 (ref-get reads))))
                         (let ((answer (reply (ref-get disk) (ref-get revision))))
                           (when (and (= 2 (ref-get reads)) (match delay ((ReloadReply) #t) (_ #f)))
                             (ref-set! disk "watcher") (ref-set! revision "watched"))
                           (when (match delay
                                   ((SaveReply) saving)
                                   ((SecondRead) (and (not saving) (= 2 (ref-get reads))))
                                   ((ReloadReply) (and (not saving) (= 2 (ref-get reads))))
                                   ((NoDelay) #f))
                             (mailbox-receive gate))
                           (ref-set! completed (+ 1 (ref-get completed)))
                           answer)))))
                (stream-open (lambda (url kinds) (Stream 1)))
                (stream-next (lambda (stream)
                               (if (ref-get streamed) (None)
                                   (begin
                                     (ref-set! streamed #t)
                                     (Some (StreamEvent "open" ""))))))
                (stream-close (lambda (stream) (panic "unexpected stream close"))))
             (with-memory-dom cues
                              (lambda ()
                                (finished (run-reactor (begin-session initial)
                                                       (list (Open "notes.txt"))
                                                       (ann update-session
                                                            (Fn Session
                                                                (Option Msg)
                                                                →
                                                                Session
                                                                ! mut completion output-port dom fetch))
                                                       session-view
                                                       session-window
                                                       snapshot
                                                       (lambda (model) (unit))
                                                       (lambda (model)
                                                         (mailbox-post gate (unit))))))))))
      (unless (= (ref-get completed) (+ (ref-get reads) (ref-get writes)))
        (panic "the document closed before all replies completed"))
      (write-line (string-append "requests " (show (ref-get reads)) "/" (show (ref-get writes))))
      result)))

(define (report (model Ide)) (→ Unit) (! output-port)
  (match (buffer-at model "notes.txt")
    ((Some buffer)
     (write-line (● buffer text))
     (write-line (match (● buffer baseline)
                   ((Some snapshot) (● snapshot text))
                   ((None) "missing")))
     (write-line (show (dirty? buffer))))
    ((None) (panic "missing buffer"))))

(define (panes-after (cues (List Cue))) (→ Unit) (! mut output-port tasks)
  (let ((model (● (run (NoDelay) cues) first)))
    (write-line (show (length (● model panes))))))

(define (files-after (cues (List Cue))) (→ Unit) (! mut output-port tasks)
  (write-line (show (● (● (run (NoDelay) cues) first) files-shown))))

(define main
  (lambda ()
    (dispatch-local
     (once (lambda ()
             ;; A successful save changes the baseline, never subsequent typing.
             (report (● (run (SaveReply)
                             (list (input "text-0" "submitted") (key "s" control-key)
                                   (input "text-0" "later") (Hide))) first))
             ;; A newer watcher read can finish a confirmed dirty reload. Typing
             ;; after that read survives the original reload's delayed reply.
             (report (● (run (ReloadReply)
                             (concatenate (list (list (input "text-0" "discard"))
                                                (invoke "reload-buffer")
                                                (list (FireWindow "online" no-event)
                                                      (input "text-0" "later") (Hide))))) first))
             ;; Save invalidates reads that began before it.
             (report (● (run (SecondRead)
                             (append (invoke "reload-buffer")
                                     (list (input "text-0" "submitted") (key "s" control-key)
                                           (Hide)))) first))
             ;; Observe each transition: two broken operations must not cancel out.
             (panes-after (invoke "spri"))
             (panes-after (append (invoke "spri") (list (key "w" alt-key))))
             (files-after (invoke "toggle-files"))
             (files-after (append (invoke "toggle-files") (list (key "b" control-key))))
             (let ((model (● (run (NoDelay) (invoke "no-such-command")) first)))
               (write-line (show (visible? (● model palette))))))))
    (unit)))
