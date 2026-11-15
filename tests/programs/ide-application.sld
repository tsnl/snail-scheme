(import
 (snail core base)
 (only (snail core forms) Host)
 (snail core io)
 (snail shell task)
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
(record Requests
  ((disk String)
   (revision String)
   (reads I64)
   (writes I64)
   (completed I64)
   (streamed Bool)))

(enum Delay
  (No-delay)
  (Save-reply)
  (Reload-reply)
  (Second-read))

(define (reply (text String) (revision String)) (→ (Result Reply String))
  (Ok (new Reply (status 200)
           (body
            (json->string (Json-object (list (new Pair (first "text") (second (Json-string text)))
                                             (new Pair
                                               (first "revision")
                                               (second (Json-string revision))))))))))

(define (key (name String) (modifiers I32)) (→ Cue)
  (Fire-window "keydown" (event-modifiers-set (event-key-set (no-event) name) modifiers)))

(define (input (id String) (text String)) (→ Cue)
  (Fire id "input" (event-value-set (no-event) text)))

(define (invoke (name String)) (→ (List Cue))
  (list (key "F1" 0) (input "command-query" name)
        (Fire "command-query" "keydown" (event-key-set (no-event) "Enter"))))

(define (run (delay Delay) (cues (List Cue)))
  (→ (Pair Ide Document))
  (! Mut Host Output-port Tasks)
  (let ((state (new Requests
                 (disk "disk")
                 (revision "initial")
                 (reads 0)
                 (writes 0)
                 (completed 0)
                 (streamed #f)))
        (gate (make-mailbox)))
    (let ((result
           (handle Fetch
               ((request
                 (lambda (method url headers body)
                   (if (string=? url "/api/project")
                       (Ok (new Reply (status 200)
                                (body
                                 "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"notes.txt\"],\"directories\":[]}")))
                       (let ((saving (string=? method "PUT")))
                         (if saving
                             (begin (set! (● state disk) body) (set! (● state revision) "saved")
                                    (set! (● state writes) (+ 1 (● state writes))))
                             (set! (● state reads) (+ 1 (● state reads))))
                         (let ((answer (reply (● state disk) (● state revision))))
                           (when (and (= 2 (● state reads))
                                      (match delay ((Reload-reply) #t) (_ #f)))
                             (set! (● state disk) "watcher") (set! (● state revision) "watched"))
                           (when (match delay
                                   ((Save-reply) saving)
                                   ((Second-read) (and (not saving) (= 2 (● state reads))))
                                   ((Reload-reply) (and (not saving) (= 2 (● state reads))))
                                   ((No-delay) #f))
                             (mailbox-receive gate))
                           (set! (● state completed) (+ 1 (● state completed)))
                           answer)))))
                (stream-open (lambda (url kinds) (new Stream (id 1))))
                (stream-next (lambda (stream)
                               (if (● state streamed) (None)
                                   (begin
                                     (set! (● state streamed) #t)
                                     (Some (new Stream-event (kind "open") (data "")))))))
                (stream-close (lambda (stream) (panic "unexpected stream close"))))
             (with-memory-dom cues
                              (lambda ()
                                (run-ui (initial)
                                        (list (Open "notes.txt"))
                                        (lambda (model message) (ui-update model message))
                                        (lambda (model) (view model))
                                        (lambda (model) (window model))
                                        (lambda (model) (unit))
                                        (lambda (model) (mailbox-post gate (unit)))))))))
      (unless (= (● state completed) (+ (● state reads) (● state writes)))
        (panic "the document closed before all replies completed"))
      (write-line (string-append "requests " (show (● state reads)) "/" (show (● state writes))))
      result)))

(define (report (model Ide)) (→ Unit) (! Output-port)
  (match (buffer-at model "notes.txt")
    ((Some buffer)
     (write-line (● buffer text))
     (write-line (match (● buffer baseline)
                   ((Some snapshot) (● snapshot text))
                   ((None) "missing")))
     (write-line (show (dirty? buffer))))
    ((None) (panic "missing buffer"))))

(define (panes-after (cues (List Cue))) (→ Unit) (! Mut Host Output-port Tasks)
  (let ((model (● (run (No-delay) cues) first)))
    (write-line (show (length (● model panes))))))

(define (files-after (cues (List Cue))) (→ Unit) (! Mut Host Output-port Tasks)
  (write-line (show (● (● (run (No-delay) cues) first) files-shown))))

(define (main) (→ Unit) (! Host Mut Output-port Tasks)
  (dispatch
   (lambda ()
     ;; A successful save changes the baseline, never subsequent typing.
     (report (● (run (Save-reply)
                     (list (input "text-0" "submitted") (key "s" (control-key))
                           (input "text-0" "later") (Hide))) first))
     ;; A newer watcher read can finish a confirmed dirty reload. Typing
     ;; after that read survives the original reload's delayed reply.
     (report (● (run (Reload-reply)
                     (concatenate (list (list (input "text-0" "discard"))
                                        (invoke "reload-buffer")
                                        (list (Fire-window "online" (no-event))
                                              (input "text-0" "later") (Hide))))) first))
     ;; Save invalidates reads that began before it.
     (report (● (run (Second-read)
                     (append (invoke "reload-buffer")
                             (list (input "text-0" "submitted") (key "s" (control-key))
                                   (Hide)))) first))
     ;; Observe each transition: two broken operations must not cancel out.
     (panes-after (invoke "spri"))
     (panes-after (append (invoke "spri") (list (key "w" (alt-key)))))
     (files-after (invoke "toggle-files"))
     (files-after (append (invoke "toggle-files") (list (key "b" (control-key)))))
     (let ((model (● (run (No-delay) (invoke "no-such-command")) first)))
       (write-line (show (visible? (● model palette)))))))
  (unit))
