;; `snail dev`'s service in Snail-Core: one project's editor, builds and run
;; targets behind one local port. (snail shell development)'s pure `step`
;; decides; this library carries out what it decides, with tasks that each
;; wait on one thing:
;;
;; - the owner, which holds the service and everything the step leaves to
;;   its host, and receives every message;
;; - the disk task, which holds the latest inventory of the project's
;;   inputs, takes another when asked, hinted or each second, and reports
;;   what changed;
;; - the resident builder, `snail resident PROJECT`, in a child process,
;;   with a task writing its requests, one reading its replies and one its
;;   standard error and exit;
;; - a supervisor for each run target, which owns that target's process;
;; - a task for each HTTP connection, which serves the editor's API, and
;;   for an event stream, writes what the owner sends it.
;;
;; No cell holds state: each task threads its own through its loop. It is
;; #567 step B3; host/native/project-http.mjs, project-develop.mjs,
;; application-process.mjs and watch.mjs are the JavaScript service this
;; replaces.
(define-library (snail shell project service)
  (export
   Setup
   develop)
  (import
   (snail core base)
   (snail core io)
   (snail shell task)
   (snail shell socket)
   (rename (snail shell process)
           (Command ProcessCommand))
   (snail shell http)
   (snail shell http exchange)
   (snail shell json)
   (snail shell json read)
   (only (snail shell text) string-downcase)
   (snail shell utf8)
   (snail shell watch)
   (snail shell development)
   (snail shell project files))
  (begin

    ;; ---- Setup ----

    ;; What the service runs with: the repository's root; the command
    ;; line's program and the runtime it links programs with, which the
    ;; resident runs as; Node, which runs them; the editor's formatter; the
    ;; project, absolute; and the port to listen on, 0 for any.
    (struct Setup
      ((root String)
       (cli String)
       (runtime String)
       (node String)
       (formatter String)
       (project String)
       (port I32)))

    (: runner (-> Setup String))
    (define (runner setup)
      (string-append (Setup-root setup) "/host/native/run-snail.mjs"))

    ;; ---- Messages ----

    ;; What the owner receives. `Step` is an event for the pure step;
    ;; `Ask` one an HTTP handler waits on, answered on its reply mailbox;
    ;; the rest are the host's own: the debounce timer, the resident, run
    ;; supervisors and event streams.
    (enum Message
      (Step ((event Event)))
      (Ask
       ((event Event)
        (reply (Mailbox Answer))))
      (Status ((reply (Mailbox Answer))))
      (Fired ((serial I64)))
      (Built
       ((epoch I64)
        (reply Reply)
        (targets Json)))
      (ResidentGone ((message String)))
      (Overdue)
      (RunChanged
       ((name String)
        (status Json)))
      (RunStopped)
      (Joined
       ((id I64)
        (connection Connection)
        (frames (Mailbox (Option Bytes)))
        (reply (Mailbox Answer))))
      (Written
       ((id I64)
        (count I64)))
      (Connected
       ((id I64)
        (connection Connection)))
      (Disconnected ((id I64))))

    ;; The owner's answer to a handler, as the response it sends.
    (struct Answer
      ((status I32)
       (body Json)))

    ;; What the disk task is asked: to reconcile for the step, to scan
    ;; because something may have changed, as after a save or a hint,
    ;; whether to go on, for the 1 s timer, for the regular files it found,
    ;; or to stop.
    (enum Scan
      (Reconciling)
      (Prompted)
      (Ticked ((reply (Mailbox Bool))))
      (Listing ((reply (Mailbox (Result (List String) String)))))
      (Stopping))

    ;; What a run target's supervisor is asked: to run a request, or none;
    ;; or to finish, once its process has ended. The rest come from its
    ;; process, by the serial of the request it runs.
    (enum Supervision
      (Want ((request (Option RunRequest))))
      (Output
       ((serial I64)
        (stream Stream)
        (bytes Bytes)))
      (Ended
       ((serial I64)
        (exit (Result Exit ProcessError))))
      (Late ((serial I64)))
      (Finish))

    ;; ---- The owner's state ----

    ;; An event stream, by its connection's number, and how many bytes the
    ;; owner sent it that its writer has not written yet.
    (struct Client
      ((id I64)
       (connection Connection)
       (frames (Mailbox (Option Bytes)))
       (pending I64)))

    (struct Supervised
      ((name String)
       (inbox (Mailbox Supervision))
       (status Json)))

    ;; Everything the step leaves to its host. `targets` is the latest
    ;; reply's candidate, by epoch, and `published` the targets of the one
    ;; published, as the status shows them. `frames` are the last status
    ;; and runs frames sent, so a frame is sent only when it changes.
    ;; `connections` are the ones whose handlers have not finished, by
    ;; number, and `clients` those of them that are event streams.
    ;; `stopping` holds the commands after Shutdown, run once `waiting`, the
    ;; resident, the supervisors and the handlers still running, reaches
    ;; zero.
    (struct Host
      ((setup Setup)
       (owner (Mailbox Message))
       (disk (Mailbox Scan))
       (requests (Mailbox (Option String)))
       (resident Process)
       (resident-alive Bool)
       (listener Listener)
       (service Service)
       (snapshot Snapshot)
       (serial I64)
       (reservation (Option (Pair I64 String)))
       (targets (Option (Pair I64 Json)))
       (published Json)
       (runs (List Supervised))
       (clients (List Client))
       (connections (List (Pair I64 Connection)))
       (frames (Pair String String))
       (stopping (Option (List Command)))
       (waiting I64)
       (done Bool)))

    ;; ---- Starting ----

    ;; Dispatches the task that starts the service; the scheduler runs it
    ;; once the program's main returns. The service ends when the owner has
    ;; shut everything down, and fails the program if the step went fatal.
    (: develop (-> Setup Unit ! mut tcp process fs modes hints console signals))
    (define (develop setup)
      (dispatch-local (once (lambda () (start setup)))))

    ;; Listens, starts the resident, announces the editor's URL, and
    ;; dispatches every other task.
    (: start (-> Setup Unit ! mut tasks tcp process fs modes hints console signals))
    (define (start setup)
      (let* ((listener (listening setup))
             (setup (Setup-port-set setup (Listener-port listener)))
             (resident (resident-process setup))
             (owner (make-mailbox))
             (disk (make-mailbox))
             (requests (make-mailbox)))
        (dispatch-local (once (lambda () (scan-disk setup owner disk))))
        (dispatch-local (once (lambda () (tick disk))))
        (dispatch-local (once (lambda () (write-requests resident requests))))
        (dispatch-local (once (lambda () (read-replies resident owner (Nil)))))
        (dispatch-local (once (lambda () (await-resident resident owner (Nil)))))
        (dispatch-local (once (lambda () (accept-connections setup listener owner disk))))
        (dispatch-local (once (lambda () (mailbox-post owner (Step (wait-for-signal))))))
        (mailbox-post owner (Step (ResidentStarted)))
        (write-line (string-append "editing " (Setup-project setup) " at " (origin setup) "/"))
        (own (new-host setup owner disk requests resident listener))))

    (: wait-for-signal (-> Event ! tasks signals))
    (define (wait-for-signal)
      (termination)
      (Close))

    (: listening (-> Setup Listener ! tasks tcp))
    (define (listening setup)
      (match (listen (Endpoint "127.0.0.1" (Setup-port setup)))
        ((Ok listener) listener)
        ((Err error)
         (panic (string-append "cannot listen on port "
                               (show (Setup-port setup))
                               ": "
                               (SocketError-code error))))))

    (: origin (-> Setup String))
    (define (origin setup)
      (string-append "http://127.0.0.1:" (show (Setup-port setup))))

    (: new-host
       (-> Setup (Mailbox Message) (Mailbox Scan) (Mailbox (Option String)) Process Listener
           Host))
    (define (new-host setup owner disk requests resident listener)
      (Host setup
            owner
            disk
            requests
            resident
            #t
            listener
            (new-service (Setup-root setup) (Setup-project setup))
            (Snapshot (Starting) 0 (Nil) (None) (Nil))
            0
            (None)
            (None)
            (JsonNull)
            (Nil)
            (Nil)
            (Nil)
            (Pair "" "")
            (None)
            0
            #f))

    ;; ---- The owner ----

    (: own (-> Host Unit ! mut tasks tcp process fs))
    (define (own host)
      (let ((host (receive host (mailbox-receive (Host-owner host)))))
        (if (Host-done host) (finish host) (own host))))

    ;; A fatal service fails the program, with the diagnostic that ended it.
    (: finish (-> Host Unit))
    (define (finish host)
      (match (Snapshot-phase (Host-snapshot host))
        ((Fatal) (panic (first-message (Host-snapshot host))))
        (_ (unit))))

    (: first-message (-> Snapshot String))
    (define (first-message snapshot)
      (match (Snapshot-diagnostics snapshot)
        ((Cons diagnostic _) (Diagnostic-message diagnostic))
        ((Nil) "the service failed")))

    (: receive (-> Host Message Host ! mut tasks tcp process fs))
    (define (receive host message)
      (match message
        ((Step event) (stepped (touched-files host event) event))
        ((Ask event reply) (asked host event reply))
        ((Status reply) (mailbox-post reply (Answer 200 (status->json host))) host)
        ((Fired serial) (if (= serial (Host-serial host)) (stepped host (TimerFired)) host))
        ((Built epoch reply targets)
         (stepped (Host-targets-set host (Some (Pair epoch targets))) (BuildReplied epoch reply)))
        ((ResidentGone message) (resident-gone host message))
        ((Overdue) (overdue host))
        ((RunChanged name status) (broadcast-changes (run-changed host name status)))
        ((RunStopped) (stopped-one host))
        ((Joined id connection frames reply) (joined host id connection frames reply))
        ((Written id count) (written host id count))
        ((Connected id connection) (connected host id connection))
        ((Disconnected id) (disconnected host id))))

    (: stepped (-> Host Event Host ! mut tasks tcp process fs))
    (define (stepped host event)
      (let ((result (step (Host-service host) event)))
        (perform-all (Host-service-set host (Pair-first result)) (Pair-second result))))

    ;; A handler's event, answered once its commands ran: the step's
    ;; refusal, or what the request asked for.
    (: asked (-> Host Event (Mailbox Answer) Host ! mut tasks tcp process fs))
    (define (asked host event reply)
      (let* ((result (step (Host-service host) event))
             (host
              (perform-all (Host-service-set host (Pair-first result)) (Pair-second result))))
        (mailbox-post reply (answer-for host event (refusal-of (Pair-second result))))
        host))

    (: refusal-of (-> (List Command) (Option Refusal)))
    (define (refusal-of commands)
      (match commands
        ((Nil) (None))
        ((Cons (Refuse refusal) _) (Some refusal))
        ((Cons _ rest) (refusal-of rest))))

    (: answer-for (-> Host Event (Option Refusal) Answer))
    (define (answer-for host event refusal)
      (match refusal
        ((Some (UnknownRunTarget name))
         (Answer 404 (message->json (string-append "unknown accepted run target: " name))))
        ((Some (ServiceClosed)) (Answer 503 (message->json "project development is closing")))
        ((None)
         (match event
           ((RequestBuild) (Answer 202 (editor-status (Host-snapshot host))))
           (_ (Answer 204 (JsonNull)))))))

    ;; ---- Carrying out commands ----

    ;; Each command in order. The commands after Shutdown wait until the
    ;; resident and every run's process have stopped.
    (: perform-all (-> Host (List Command) Host ! mut tasks tcp process fs))
    (define (perform-all host commands)
      (match commands
        ((Nil) host)
        ((Cons (Shutdown) rest) (shut-down host rest))
        ((Cons command rest) (perform-all (perform host command) rest))))

    (: perform (-> Host Command Host ! mut tcp process fs))
    (define (perform host command)
      (match command
        ((Build epoch) (build host epoch))
        ((Reconcile) (mailbox-post (Host-disk host) (Reconciling)) host)
        ((Publish epoch) (request host (epoch-request "publish" epoch (Nil))))
        ((Discard epoch) (request host (epoch-request "discard" epoch (Nil))))
        ((Abandon epoch) (give-up host epoch #t))
        ((Release epoch) (give-up host epoch #f))
        ((Arm) (arm host))
        ((Launch name wanted) (launch host name wanted))
        ((Refuse _) host)
        ((Notify snapshot) (notify host snapshot))
        ((Shutdown) host)
        ((Closed) (Host-done-set host #t))))

    (: request (-> Host String Host ! mut))
    (define (request host line)
      (mailbox-post (Host-requests host) (Some line))
      host)

    (: epoch-request (-> String I64 (List (Pair String Json)) String))
    (define (epoch-request kind epoch rest)
      (json->string (JsonObject (append (list (Pair "kind" (JsonString kind))
                                              (Pair "epoch" (JsonInteger epoch)))
                                        rest))))

    ;; An attempt's build directory, reserved under build/ before the
    ;; resident makes generations beside it, named for it.
    (: build (-> Host I64 Host ! mut fs))
    (define (build host epoch)
      (match (reserve (string-append (Setup-project (Host-setup host)) "/build") 0)
        ((Ok directory)
         (request (Host-reservation-set host (Some (Pair epoch directory)))
                  (epoch-request "build"
                                 epoch
                                 (list (Pair "prefix"
                                             (JsonString
                                              (string-append (base-name directory) "-")))))))
        ((Err message)
         (mailbox-post (Host-owner host) (Step (ResidentExited message)))
         host)))

    ;; A name no entry of build/ has, nor begins, so the generations the
    ;; resident names with it are this attempt's alone, even beside what an
    ;; earlier service left there.
    (: reserve (-> String I64 (Result String String) ! fs))
    (define (reserve build number)
      (match (make-directories build)
        ((Err error) (Err (string-append "cannot make " build ": " (show error))))
        ((Ok _)
         (match (list-directory build)
           ((Err error) (Err (string-append "cannot list " build ": " (show error))))
           ((Ok names) (reserve-unused build names number))))))

    (: reserve-unused (-> String (List String) I64 (Result String String) ! fs))
    (define (reserve-unused build names number)
      (let* ((name (string-append ".snail-attempt-" (show number)))
             (taken? (any? (lambda (entry)
                             (or (string=? entry name)
                                 (starts-with? entry (string-append name "-"))))
                           names)))
        (if taken?
            (reserve-unused build names (+ number 1))
            (match (make-directory (string-append build "/" name))
              ((Ok _) (Ok (string-append build "/" name)))
              ((Err (AlreadyExists)) (reserve-unused build names (+ number 1)))
              ((Err error) (Err (string-append "cannot reserve " name ": " (show error))))))))

    (: base-name (-> String String))
    (define (base-name path)
      (let loop ((index (string-length path)))
        (cond ((= index 0) path)
              ((char=? (string-ref path (- index 1)) #\/)
               (substring path index (string-length path)))
              (else (loop (- index 1))))))

    ;; Gives up an attempt's directory, and when the attempt still owns
    ;; them, the generations the resident named for it.
    (: give-up (-> Host I64 Bool Host ! fs))
    (define (give-up host epoch generations?)
      (match (Host-reservation host)
        ((Some (Pair reserved directory))
         (if (= reserved epoch)
             (begin
               (when generations? (remove-generations directory))
               (remove-tree directory)
               (Host-reservation-set host (None)))
             host))
        ((None) host)))

    (: remove-generations (-> String Unit ! fs))
    (define (remove-generations directory)
      (let ((build (substring directory 0 (- (string-length directory)
                                             (+ (string-length (base-name directory)) 1))))
            (prefix (string-append (base-name directory) "-")))
        (match (list-directory build)
          ((Ok names)
           (for-each (lambda (name)
                       (when (starts-with? name prefix)
                         (remove-tree (string-append build "/" name))
                         (unit)))
                     names))
          ((Err _) (unit)))))

    (: starts-with? (-> String String Bool))
    (define (starts-with? text prefix)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    ;; Arming replaces the timer armed before: the owner ignores a firing
    ;; whose serial is not the latest.
    (: arm (-> Host Host ! mut))
    (define (arm host)
      (let ((serial (+ (Host-serial host) 1)) (owner (Host-owner host)))
        (dispatch-local (once (lambda ()
                                (sleep 40)
                                (mailbox-post owner (Fired serial)))))
        (Host-serial-set host serial)))

    ;; ---- Run targets ----

    ;; A launch goes to the target's supervisor, started the first time
    ;; the target is launched.
    (: launch (-> Host String (Option RunRequest) Host ! mut process))
    (define (launch host name wanted)
      (match (find (lambda (run) (string=? (Supervised-name run) name)) (Host-runs host))
        ((Some run) (mailbox-post (Supervised-inbox run) (Want wanted)) host)
        ((None)
         (let ((inbox (make-mailbox)) (setup (Host-setup host)) (owner (Host-owner host)))
           (dispatch-local (once (lambda () (supervise (new-supervisor setup owner inbox name)))))
           (mailbox-post inbox (Want wanted))
           (Host-runs-set host
                          (append (Host-runs host)
                                  (list (Supervised name inbox (idle-run name)))))))))

    (: run-changed (-> Host String Json Host))
    (define (run-changed host name status)
      (Host-runs-set host
                     (map (lambda (run)
                            (if (string=? (Supervised-name run) name)
                                (Supervised-status-set run status)
                                run))
                          (Host-runs host))))

    ;; ---- Status ----

    ;; A snapshot to every event stream, as the frames that changed. A
    ;; fatal one closes the service.
    (: notify (-> Host Snapshot Host ! mut tcp))
    (define (notify host snapshot)
      (let ((host (broadcast-changes (Host-snapshot-set (published host snapshot) snapshot))))
        (match (Snapshot-phase snapshot)
          ((Fatal) (mailbox-post (Host-owner host) (Step (Close))) host)
          (_ host))))

    ;; The published targets, once the snapshot names the build whose
    ;; candidate the owner kept.
    (: published (-> Host Snapshot Host))
    (define (published host snapshot)
      (match (Pair (Snapshot-published snapshot) (Host-targets host))
        ((Pair (Some build) (Some (Pair epoch targets)))
         (if (= (Published-id build) epoch)
             (Host-published-set host
                                 (JsonObject (list (Pair "id" (JsonInteger epoch))
                                                   (Pair "targets" targets))))
             host))
        (_ host)))

    (: editor-status (-> Snapshot Json))
    (define (editor-status snapshot)
      (JsonObject (list (Pair "phase" (JsonString (phase-name (Snapshot-phase snapshot))))
                        (Pair "id" (JsonInteger (Snapshot-id snapshot)))
                        (Pair "diagnostics"
                              (JsonArray
                               (map diagnostic->json (Snapshot-diagnostics snapshot)))))))

    ;; All a client can observe in one snapshot: the attempt, the published
    ;; targets, the resident's process and the run targets.
    (: status->json (-> Host Json))
    (define (status->json host)
      (match (editor-status (Host-snapshot host))
        ((JsonObject members)
         (JsonObject (append members
                             (list (Pair "published" (Host-published host))
                                   (Pair "compiler"
                                         (if (Host-resident-alive host)
                                             (JsonObject (list (Pair "worker"
                                                                     (JsonInteger
                                                                      (i32->i64
                                                                       (Process-id
                                                                        (Host-resident host)))))))
                                             (JsonNull)))
                                   (Pair "runs" (runs->json host))))))
        (other other)))

    (: phase-name (-> Phase String))
    (define (phase-name phase)
      (match phase
        ((Starting) "starting")
        ((Building) "building")
        ((Succeeded) "succeeded")
        ((Failed) "failed")
        ((Superseded) "superseded")
        ((Fatal) "fatal")))

    (: diagnostic->json (-> Diagnostic Json))
    (define (diagnostic->json diagnostic)
      (JsonObject (list (Pair "severity" (JsonString "error"))
                        (Pair "message" (JsonString (Diagnostic-message diagnostic)))
                        (Pair "source"
                              (match (Diagnostic-source diagnostic)
                                ((Some point)
                                 (JsonObject
                                  (list (Pair "file" (JsonString (SourcePoint-file point)))
                                        (Pair "line" (JsonInteger (SourcePoint-line point)))
                                        (Pair "column"
                                              (JsonInteger (SourcePoint-column point))))))
                                ((None) (JsonNull)))))))

    (: message->json (-> String Json))
    (define (message->json message)
      (JsonObject (list (Pair "message" (JsonString message)))))

    ;; Each run target the step knows, with its process as its supervisor
    ;; last reported it.
    (: runs->json (-> Host Json))
    (define (runs->json host)
      (JsonArray (map (lambda (run)
                        (match (run-status host (RunStatus-name run))
                          ((JsonObject members)
                           (JsonObject (append members
                                               (list
                                                (Pair "wanted" (JsonBool (RunStatus-wanted run)))
                                                (Pair "available"
                                                      (JsonBool (RunStatus-available run)))))))
                          (other other)))
                      (Snapshot-runs (Host-snapshot host)))))

    (: run-status (-> Host String Json))
    (define (run-status host name)
      (match (find (lambda (run) (string=? (Supervised-name run) name)) (Host-runs host))
        ((Some run) (Supervised-status run))
        ((None) (idle-run name))))

    (: idle-run (-> String Json))
    (define (idle-run name)
      (JsonObject (list (Pair "target" (JsonString name))
                        (Pair "desired" (JsonNull))
                        (Pair "attempt" (JsonNull)))))

    ;; ---- Event streams ----

    (: frame (-> String Json String))
    (define (frame kind value)
      (string-append "event: " kind "\ndata: " (json->string value) "\n\n"))

    ;; The status and runs frames that changed since the last sent, in one
    ;; write, so a large status cannot leave the runs frame to find a
    ;; healthy stream still writing it.
    (: broadcast-changes (-> Host Host ! mut tcp))
    (define (broadcast-changes host)
      (let* ((status (frame "status" (editor-status (Host-snapshot host))))
             (runs (frame "runs" (runs->json host)))
             (sent (Host-frames host))
             (text (string-append (if (string=? status (Pair-first sent)) "" status)
                                  (if (string=? runs (Pair-second sent)) "" runs))))
        (if (string=? text "")
            host
            (broadcast (Host-frames-set host (Pair status runs)) text))))

    ;; A change under the project tells each editor to list its files again.
    (: touched-files (-> Host Event Host ! mut tcp))
    (define (touched-files host event)
      (match event
        ((Touched paths)
         (let ((project (Setup-project (Host-setup host))))
           (if (any? (lambda (path) (or (string=? path project)
                                        (starts-with? path (string-append project "/"))))
                     paths)
               (broadcast host (frame "files" (JsonNull)))
               host)))
        (_ host)))

    ;; Each client gets the frame, unless 16 KiB it was sent before are
    ;; still unwritten, as Node's stream refuses more: then it is dropped,
    ;; and reconnecting gets it the current status.
    (: broadcast (-> Host String Host ! mut tcp))
    (define (broadcast host text)
      (Host-clients-set host (sent-to (Host-clients host) (string->utf8 text))))

    (: sent-to (-> (List Client) Bytes (List Client) ! mut tcp))
    (define (sent-to clients bytes)
      (match clients
        ((Nil) (Nil))
        ((Cons client rest)
         (if (>= (Client-pending client) 16384)
             (begin
               (close-connection (Client-connection client))
               (mailbox-post (Client-frames client) (None))
               (sent-to rest bytes))
             (begin
               (mailbox-post (Client-frames client) (Some bytes))
               (Cons (Client-pending-set client (+ (Client-pending client) (vector-length bytes)))
                     (sent-to rest bytes)))))))

    ;; A new event stream gets the status, the runs and a prompt to list
    ;; files, unless there are 64 already or the service is closing.
    (: joined
       (-> Host I64 Connection (Mailbox (Option Bytes)) (Mailbox Answer) Host ! mut tcp))
    (define (joined host id connection frames reply)
      (cond ((option-some? (Host-stopping host))
             (mailbox-post reply (Answer 503 (message->json "project development is closing")))
             host)
            ((>= (length (Host-clients host)) 64)
             (mailbox-post reply (Answer 429 (message->json "too many event connections")))
             host)
            (else
             (mailbox-post reply (Answer 200 (JsonNull)))
             (Host-clients-set host
                               (append (sent-to (list (Client id connection frames 0))
                                                (string->utf8 (first-frames host)))
                                       (Host-clients host))))))

    (: first-frames (-> Host String))
    (define (first-frames host)
      (string-append "retry: 1000\n\n"
                     (frame "status" (editor-status (Host-snapshot host)))
                     (frame "runs" (runs->json host))
                     (frame "files" (JsonNull))))

    (: option-some? (All (T) (requires (Copy T)) (-> (Option T) Bool)))
    (define (option-some? option)
      (match option
        ((Some _) #t)
        ((None) #f)))

    (: written (-> Host I64 I64 Host))
    (define (written host id count)
      (Host-clients-set host
                        (map (lambda (client)
                               (if (= (Client-id client) id)
                                   (Client-pending-set client (- (Client-pending client) count))
                                   client))
                             (Host-clients host))))


    ;; ---- Shutting down ----

    ;; No new work: the listener and every stream close, each supervisor
    ;; stops its process, and the resident's input ends, so it finishes the
    ;; request it is answering and exits, or is killed after 2 s.
    (: shut-down (-> Host (List Command) Host ! mut tasks tcp process fs))
    (define (shut-down host rest)
      (close-listener (Host-listener host))
      (for-each (lambda (client) (mailbox-post (Client-frames client) (None))) (Host-clients host))
      (for-each (lambda (open) (close-connection (Pair-second open)) (unit))
                (Host-connections host))
      (for-each (lambda (run) (mailbox-post (Supervised-inbox run) (Finish))) (Host-runs host))
      (mailbox-post (Host-requests host) (None))
      (mailbox-post (Host-disk host) (Stopping))
      (let ((owner (Host-owner host)))
        (dispatch-local (once (lambda () (sleep 2000) (mailbox-post owner (Overdue))))))
      (resumed
       (Host-waiting-set (Host-connections-set (Host-stopping-set (Host-clients-set host (Nil))
                                                                  (Some rest))
                                               (Nil))
                         (+ (+ (length (Host-runs host)) (length (Host-connections host)))
                            (if (Host-resident-alive host) 1 0)))))

    ;; A connection accepted while stopping is closed at once; its handler
    ;; still reports that it finished.
    (: connected (-> Host I64 Connection Host ! tcp))
    (define (connected host id connection)
      (match (Host-stopping host)
        ((Some _)
         (close-connection connection)
         (Host-waiting-set host (+ (Host-waiting host) 1)))
        ((None) (Host-connections-set host (Cons (Pair id connection) (Host-connections host))))))

    ;; A finished handler's connection, and its event stream if it had one.
    (: disconnected (-> Host I64 Host ! mut tasks tcp process fs))
    (define (disconnected host id)
      (match (Host-stopping host)
        ((Some _) (stopped-one host))
        ((None)
         (Host-clients-set (Host-connections-set host
                                                 (filter
                                                  (lambda (open) (not (= (Pair-first open) id)))
                                                  (Host-connections host)))
                           (filter (lambda (client) (not (= (Client-id client) id)))
                                   (Host-clients host))))))

    ;; Once nothing is still stopping, the commands after Shutdown.
    (: resumed (-> Host Host ! mut tasks tcp process fs))
    (define (resumed host)
      (match (Host-stopping host)
        ((Some rest)
         (if (= (Host-waiting host) 0)
             (perform-all (Host-stopping-set host (Some (Nil))) rest)
             host))
        ((None) host)))

    (: stopped-one (-> Host Host ! mut tasks tcp process fs))
    (define (stopped-one host)
      (resumed (Host-waiting-set host (- (Host-waiting host) 1))))

    (: resident-gone (-> Host String Host ! mut tasks tcp process fs))
    (define (resident-gone host message)
      (let ((host (Host-resident-alive-set host #f)))
        (match (Host-stopping host)
          ((Some _) (stopped-one host))
          ((None) (stepped host (ResidentExited message))))))

    (: overdue (-> Host Host ! process))
    (define (overdue host)
      (when (Host-resident-alive host)
        (send-signal (Host-resident host) (Kill))
        (unit))
      host)

    ;; ---- The disk ----

    ;; The project, the libraries and the browser host, leaving out build
    ;; output and Git's directory.
    (: watched (-> Setup (Pair (List String) (List String))))
    (define (watched setup)
      (let ((root (Setup-root setup)) (project (Setup-project setup)))
        (Pair (list project (string-append root "/src") (string-append root "/host/browser"))
              (list (string-append project "/build")
                    (string-append project "/.git")
                    (string-append root "/build")))))

    (: take-inventory (-> Setup (Result Inventory String) ! fs))
    (define (take-inventory setup)
      (let ((roots (watched setup)))
        (inventory (Pair-first roots) (Pair-second roots))))

    ;; The last complete inventory, and why the latest failed, if it did.
    (struct Disk
      ((taken Inventory)
       (failure (Option String))))

    ;; Takes the first inventory as what is there, then one for each scan
    ;; asked, reporting what changed since the last. Hints from a watch of
    ;; each root ask for one at once; the timer asks each second, as a
    ;; watch can miss a change. After Stopping it closes the watches,
    ;; answers the timer that it is done, and ends.
    (: scan-disk (-> Setup (Mailbox Message) (Mailbox Scan) Unit ! mut tasks fs hints))
    (define (scan-disk setup owner requests)
      (let* ((roots (watched setup))
             (watches (watch-roots (Pair-first roots) (Pair-second roots) requests)))
        (let loop ((disk (rescan setup owner (Disk empty-inventory (None)) #f)) (stopping #f))
          (match (mailbox-receive requests)
            ((Stopping)
             (for-each close-watch watches)
             (loop disk #t))
            ((Ticked reply)
             (mailbox-post reply (not stopping))
             (unless stopping (loop (rescan setup owner disk #t) #f)))
            ((Listing reply)
             (let ((next (rescan setup owner disk #t)))
               (mailbox-post reply (disk-result next (inventory-files (Disk-taken next))))
               (loop next stopping)))
            ((Prompted) (loop (if stopping disk (rescan setup owner disk #t)) stopping))
            ((Reconciling)
             (let ((next (rescan setup owner disk #t)))
               (mailbox-post owner (Step (Reconciled (disk-result next (unit)))))
               (loop next stopping)))))))

    ;; What the latest inventory found, unless it failed.
    (: disk-result (All (T) (requires (Copy T)) (-> Disk T (Result T String))))
    (define (disk-result disk value)
      (match (Disk-failure disk)
        ((Some message) (Err message))
        ((None) (Ok value))))

    ;; A watch of each root that can be watched, each with a task that
    ;; turns its hints into scans until it closes.
    (: watch-roots (-> (List String) (List String) (Mailbox Scan) (List Watch) ! mut hints))
    (define (watch-roots roots excluded disk)
      (match roots
        ((Nil) (Nil))
        ((Cons root rest)
         (match (watch-tree root excluded)
           ((Some watch)
            (dispatch-local (once (lambda () (relay-hints watch disk))))
            (Cons watch (watch-roots rest excluded disk)))
           ((None) (watch-roots rest excluded disk))))))

    (: relay-hints (-> Watch (Mailbox Scan) Unit ! mut tasks hints))
    (define (relay-hints watch disk)
      (when (next-hint watch)
        (mailbox-post disk (Prompted))
        (relay-hints watch disk)))

    ;; Another inventory, reported as what changed since the last complete
    ;; one when `report?`, as it is but for the first. A failure keeps the
    ;; last, and is reported once, when it begins; the next inventory that
    ;; succeeds reports the recovery, after what changed meanwhile.
    (: rescan (-> Setup (Mailbox Message) Disk Bool Disk ! mut fs))
    (define (rescan setup owner disk report?)
      (match (take-inventory setup)
        ((Ok next)
         (let ((changes (inventory-changes (Disk-taken disk) next)))
           (when (and report? (not (null? changes)))
             (mailbox-post owner (Step (Touched changes))))
           (when (option-some? (Disk-failure disk))
             (mailbox-post owner (Step (Uncertain (None)))))
           (Disk next (None))))
        ((Err message)
         (unless (option-some? (Disk-failure disk))
           (mailbox-post owner (Step (Uncertain (Some message)))))
         (Disk-failure-set disk (Some message)))))

    ;; A scan each second, until the disk task stops.
    (: tick (-> (Mailbox Scan) Unit ! mut tasks))
    (define (tick disk)
      (sleep 1000)
      (let ((reply (make-mailbox)))
        (mailbox-post disk (Ticked reply))
        (when (mailbox-receive reply)
          (tick disk))))

    ;; ---- The resident ----

    (: resident-process (-> Setup Process ! tasks process))
    (define (resident-process setup)
      (match (spawn (ProcessCommand (Setup-node setup)
                                    (list "--no-warnings"
                                          (runner setup)
                                          (Setup-cli setup)
                                          (Setup-root setup)
                                          (Setup-runtime setup)
                                          "resident"
                                          (Setup-project setup))
                                    "."))
        ((Ok process) process)
        ((Err error)
         (panic (string-append "cannot start the resident builder: "
                               (ProcessError-code error))))))

    ;; One request a line, until the input ends.
    (: write-requests (-> Process (Mailbox (Option String)) Unit ! mut tasks process))
    (define (write-requests resident requests)
      (match (mailbox-receive requests)
        ((Some line)
         (match (write-all resident (string->utf8 (string-append line "\n")))
           ((Ok _) (write-requests resident requests))
           ((Err _) (unit))))
        ((None)
         (close-input resident)
         (unit))))

    (: write-all (-> Process Bytes (Result Unit ProcessError) ! tasks process))
    (define (write-all child bytes)
      (if (= (vector-length bytes) 0)
          (Ok (unit))
          (match (write-input child bytes)
            ((Ok count)
             (write-all child (subvector bytes (i32->i64 count) (vector-length bytes))))
            ((Err error) (Err error)))))

    ;; Each reply line, as the message it is. `pending` holds the bytes of a
    ;; line not yet ended, newest chunk first.
    (: read-replies (-> Process (Mailbox Message) (List Bytes) Unit ! mut tasks process))
    (define (read-replies resident owner pending)
      (match (read-output resident (Stdout) 65536)
        ((Ok (Some bytes)) (read-replies resident owner (post-lines owner (Cons bytes pending))))
        (_ (unit))))

    ;; Posts each whole line in the chunks, and keeps what follows the last.
    (: post-lines (-> (Mailbox Message) (List Bytes) (List Bytes) ! mut))
    (define (post-lines owner pending)
      (let* ((bytes (vector-concatenate (reverse pending))) (end (vector-index-of bytes 10)))
        (match end
          ((Some at)
           (mailbox-post owner (reply-message (subvector bytes 0 at)))
           (post-lines owner (list (subvector bytes (+ at 1) (vector-length bytes)))))
          ((None) (list bytes)))))

    (: vector-index-of (-> Bytes I32 (Option I64)))
    (define (vector-index-of bytes code)
      (let loop ((index 0))
        (cond ((= index (vector-length bytes)) (None))
              ((= (u8->i32 (vector-ref bytes index)) code) (Some index))
              (else (loop (+ index 1))))))

    ;; A reply, by the members it has: a build's diagnostics, a
    ;; publication's error, or a discard's epoch alone. One that is not
    ;; JSON is the resident failing.
    (: reply-message (-> Bytes Message))
    (define (reply-message line)
      (match (match (utf8->string line)
               ((Ok text) (string->json text))
               ((Err _) (None)))
        ((Some json)
         (match (json-member json "epoch")
           ((Some (JsonInteger epoch)) (epoch-reply json epoch))
           (_ (Step (ResidentExited "the resident builder replied without an epoch")))))
        ((None)
         (Step (ResidentExited "the resident builder replied with something other than JSON")))))

    (: epoch-reply (-> Json I64 Message))
    (define (epoch-reply json epoch)
      (cond ((option-some? (json-member json "diagnostics"))
             (Built epoch (json->reply json) (candidate-targets json)))
            ((option-some? (json-member json "error"))
             (Step (PublishReplied epoch (match (json-member json "error")
                                           ((Some (JsonString message)) (Some message))
                                           (_ (None))))))
            (else (Step (DiscardReplied epoch)))))

    ;; Reads what the resident writes to stderr, a panic's message, then
    ;; waits for it to exit, which the end of stderr means is near.
    (: await-resident (-> Process (Mailbox Message) (List Bytes) Unit ! mut tasks process))
    (define (await-resident resident owner tail)
      (match (read-output resident (Stderr) 65536)
        ((Ok (Some bytes)) (await-resident resident owner (Cons bytes tail)))
        (_
         (mailbox-post owner
                       (ResidentGone (string-append "the resident builder exited with "
                                                    (exit-text (wait-exit resident))
                                                    (stderr-text tail)))))))

    (: exit-text (-> (Result Exit ProcessError) String))
    (define (exit-text exit)
      (match exit
        ((Ok (Exited code)) (string-append "status " (show code)))
        ((Ok (Signaled name)) name)
        ((Err error) (ProcessError-code error))))

    ;; The last 4096 bytes written, trimmed, after a colon.
    (: stderr-text (-> (List Bytes) String))
    (define (stderr-text tail)
      (let* ((bytes (vector-concatenate (reverse tail)))
             (start (max 0 (- (vector-length bytes) 4096)))
             (text (match (utf8->string (subvector bytes start (vector-length bytes)))
                     ((Ok text) (trimmed text))
                     ((Err _) ""))))
        (if (string=? text "") "" (string-append ": " text))))

    (: trimmed (-> String String))
    (define (trimmed text)
      (let loop ((start 0) (end (string-length text)))
        (cond
         ((and (< start end) (char-whitespace? (string-ref text start))) (loop (+ start 1) end))
         ((and (< start end) (char-whitespace? (string-ref text (- end 1))))
          (loop start (- end 1)))
         (else (substring text start end)))))

    ;; ---- The resident's replies ----

    (: json->reply (-> Json Reply))
    (define (json->reply json)
      (Reply (match (json-object json "description")
               ((Some description) (Some (json->description description)))
               ((None) (None)))
             (match (json-object json "candidate")
               ((Some candidate) (Some (json->candidate candidate)))
               ((None) (None)))
             (map json->diagnostic (json-items json "diagnostics"))))

    (: json->description (-> Json Description))
    (define (json->description json)
      (let ((builds (json-items json "builds")))
        (Description (map (lambda (build) (json-text build "entry")) builds)
                     (fold-right (lambda (build publics)
                                   (match (json-member build "public")
                                     ((Some (JsonString path)) (Cons path publics))
                                     (_ publics)))
                                 (Nil)
                                 builds)
                     (map (lambda (run)
                            (RunDefinition (json-text run "name")
                                           (json-text run "build")
                                           (map json-string-value (json-items run "args"))))
                          (json-items json "runs")))))

    (: json->candidate (-> Json Candidate))
    (define (json->candidate json)
      (Candidate (match (json-member json "description")
                   ((Some description) (json->description description))
                   ((None) (Description (Nil) (Nil) (Nil))))
                 (map (lambda (target)
                        (Generation (json-text target "name")
                                    (json-text target "directory")
                                    (json-text target "digest")))
                      (json-items json "targets"))))

    ;; The candidate's targets as the status shows them.
    (: candidate-targets (-> Json Json))
    (define (candidate-targets json)
      (match (json-member json "candidate")
        ((Some candidate)
         (JsonArray (map (lambda (target)
                           (JsonObject (fold-right (lambda (name kept)
                                                     (match (json-member target name)
                                                       ((Some value)
                                                        (Cons (Pair name value) kept))
                                                       ((None) kept)))
                                                   (Nil)
                                                   (list "name"
                                                         "directory"
                                                         "digest"
                                                         "compiled"))))
                         (json-items candidate "targets"))))
        ((None) (JsonArray (Nil)))))

    (: json->diagnostic (-> Json Diagnostic))
    (define (json->diagnostic json)
      (Diagnostic (json-text json "message")
                  (match (json-object json "source")
                    ((Some source)
                     (Some (SourcePoint (json-text source "file")
                                        (json-integer source "line")
                                        (json-integer source "column"))))
                    ((None) (None)))))

    ;; A member that is an object, as a null one is not.
    (: json-object (-> Json String (Option Json)))
    (define (json-object json name)
      (match (json-member json name)
        ((Some (JsonObject members)) (Some (JsonObject members)))
        (_ (None))))

    (: json-items (-> Json String (List Json)))
    (define (json-items json name)
      (match (json-member json name)
        ((Some (JsonArray items)) items)
        (_ (Nil))))

    (: json-text (-> Json String String))
    (define (json-text json name)
      (match (json-member json name)
        ((Some value) (json-string-value value))
        ((None) "")))

    (: json-string-value (-> Json String))
    (define (json-string-value json)
      (match json
        ((JsonString text) text)
        (_ "")))

    (: json-integer (-> Json String I64))
    (define (json-integer json name)
      (match (json-member json name)
        ((Some (JsonInteger value)) value)
        (_ 0)))

    ;; ---- Supervising a run target ----

    ;; One run target, its latest request and the process it owns. Each
    ;; request has a serial, so a request repeated is run again, and output
    ;; or an exit for an earlier process is ignored.
    (struct Child
      ((serial I64)
       (request RunRequest)
       (process (Option Process))
       (stopping Bool)
       (exit (Option (Result Exit ProcessError)))
       (stdout Bytes)
       (stderr Bytes)))

    (struct Supervisor
      ((setup Setup)
       (owner (Mailbox Message))
       (inbox (Mailbox Supervision))
       (name String)
       (desired (Option (Pair I64 RunRequest)))
       (serial I64)
       (child (Option Child))
       (finishing Bool)))

    (: new-supervisor (-> Setup (Mailbox Message) (Mailbox Supervision) String Supervisor))
    (define (new-supervisor setup owner inbox name)
      (Supervisor setup owner inbox name (None) 0 (None) #f))

    ;; Receives, runs what is wanted, and reports. A finishing supervisor
    ;; ends once its process has.
    (: supervise (-> Supervisor Unit ! mut tasks process))
    (define (supervise supervisor)
      (let ((supervisor (reconcile-run (supervised supervisor
                                                   (mailbox-receive
                                                    (Supervisor-inbox supervisor))))))
        (mailbox-post (Supervisor-owner supervisor)
                      (RunChanged (Supervisor-name supervisor) (supervisor->json supervisor)))
        (if (and (Supervisor-finishing supervisor) (not (running? supervisor)))
            (mailbox-post (Supervisor-owner supervisor) (RunStopped))
            (supervise supervisor))))

    (: supervised (-> Supervisor Supervision Supervisor ! process))
    (define (supervised supervisor message)
      (match message
        ((Want wanted)
         (let ((serial (+ (Supervisor-serial supervisor) 1)))
           (Supervisor-serial-set (Supervisor-desired-set supervisor
                                                          (match wanted
                                                            ((Some request)
                                                             (Some (Pair serial request)))
                                                            ((None) (None))))
                                  serial)))
        ((Output serial stream bytes) (child-output supervisor serial stream bytes))
        ((Ended serial exit) (child-ended supervisor serial exit))
        ((Late serial) (late supervisor serial))
        ((Finish) (Supervisor-finishing-set (Supervisor-desired-set supervisor (None)) #t))))

    (: running? (-> Supervisor Bool))
    (define (running? supervisor)
      (match (Supervisor-child supervisor)
        ((Some child) (not (option-some? (Child-exit child))))
        ((None) #f)))

    ;; A process that is not the one wanted is stopped; once none runs,
    ;; the one wanted is launched, unless it already ran and ended.
    (: reconcile-run (-> Supervisor Supervisor ! mut tasks process))
    (define (reconcile-run supervisor)
      (match (Pair (Supervisor-child supervisor) (Supervisor-desired supervisor))
        ((Pair (Some child) wanted)
         (cond ((option-some? (Child-exit child))
                (match wanted
                  ((Some (Pair serial request))
                   (if (= serial (Child-serial child))
                       supervisor
                       (start-child supervisor serial request)))
                  ((None) supervisor)))
               ((and (not (Child-stopping child)) (not (wants? wanted (Child-serial child))))
                (stop-child supervisor child))
               (else supervisor)))
        ((Pair (None) (Some (Pair serial request))) (start-child supervisor serial request))
        ((Pair (None) (None)) supervisor)))

    (: wants? (-> (Option (Pair I64 RunRequest)) I64 Bool))
    (define (wants? wanted serial)
      (match wanted
        ((Some (Pair wanted-serial _)) (= wanted-serial serial))
        ((None) #f)))

    ;; SIGTERM, and SIGKILL if the process has not ended 2 s later.
    (: stop-child (-> Supervisor Child Supervisor ! mut process))
    (define (stop-child supervisor child)
      (match (Child-process child)
        ((Some process) (send-signal process (Terminate)) (unit))
        ((None) (unit)))
      (let ((inbox (Supervisor-inbox supervisor)) (serial (Child-serial child)))
        (dispatch-local (once (lambda () (sleep 2000) (mailbox-post inbox (Late serial))))))
      (Supervisor-child-set supervisor (Some (Child-stopping-set child #t))))

    (: late (-> Supervisor I64 Supervisor ! process))
    (define (late supervisor serial)
      (match (Supervisor-child supervisor)
        ((Some child)
         (when (and (= (Child-serial child) serial) (not (option-some? (Child-exit child))))
           (match (Child-process child)
             ((Some process) (send-signal process (Kill)) (unit))
             ((None) (unit))))
         supervisor)
        ((None) supervisor)))

    ;; The run's program on Node, with its standard input closed, and a
    ;; task for each of its outputs and its exit.
    (: start-child (-> Supervisor I64 RunRequest Supervisor ! mut tasks process))
    (define (start-child supervisor serial request)
      (let ((setup (Supervisor-setup supervisor)) (inbox (Supervisor-inbox supervisor)))
        (match (spawn (ProcessCommand (Setup-node setup)
                                      (append
                                       (list "--no-warnings"
                                             (runner setup)
                                             (RunRequest-entry request))
                                       (RunRequest-arguments request))
                                      "."))
          ((Ok process)
           (close-input process)
           (dispatch-local (once (lambda () (forward-output process inbox serial (Stdout)))))
           (dispatch-local (once (lambda () (forward-output process inbox serial (Stderr)))))
           (dispatch-local
            (once (lambda () (mailbox-post inbox (Ended serial (wait-exit process))))))
           (Supervisor-child-set supervisor
                                 (Some (Child serial
                                              request
                                              (Some process)
                                              #f
                                              (None)
                                              (empty-bytes)
                                              (empty-bytes)))))
          ((Err error)
           (Supervisor-child-set supervisor
                                 (Some (Child serial
                                              request
                                              (None)
                                              #f
                                              (Some (Err error))
                                              (empty-bytes)
                                              (empty-bytes))))))))

    (: empty-bytes (-> Bytes))
    (define (empty-bytes)
      (make-vector 0 (i32->u8 0)))

    (: forward-output (-> Process (Mailbox Supervision) I64 Stream Unit ! mut tasks process))
    (define (forward-output process inbox serial stream)
      (match (read-output process stream 65536)
        ((Ok (Some bytes))
         (mailbox-post inbox (Output serial stream bytes))
         (forward-output process inbox serial stream))
        (_ (unit))))

    ;; Each output keeps its last 64 KiB.
    (: child-output (-> Supervisor I64 Stream Bytes Supervisor))
    (define (child-output supervisor serial stream bytes)
      (match (Supervisor-child supervisor)
        ((Some child)
         (if (= (Child-serial child) serial)
             (Supervisor-child-set supervisor
                                   (Some (match stream
                                           ((Stdout)
                                            (Child-stdout-set child
                                                              (output-tail (Child-stdout child)
                                                                           bytes)))
                                           ((Stderr)
                                            (Child-stderr-set child
                                                              (output-tail (Child-stderr child)
                                                                           bytes))))))
             supervisor))
        ((None) supervisor)))

    (: output-tail (-> Bytes Bytes Bytes))
    (define (output-tail kept bytes)
      (let* ((joined (vector-concatenate (list kept bytes))) (length (vector-length joined)))
        (subvector joined (max 0 (- length 65536)) length)))

    (: child-ended (-> Supervisor I64 (Result Exit ProcessError) Supervisor ! process))
    (define (child-ended supervisor serial exit)
      (match (Supervisor-child supervisor)
        ((Some child)
         (if (= (Child-serial child) serial)
             (begin
               (match (Child-process child)
                 ((Some process) (close-process process) (unit))
                 ((None) (unit)))
               (Supervisor-child-set supervisor (Some (Child-exit-set child (Some exit)))))
             supervisor))
        ((None) supervisor)))

    ;; The target's status, as application-process.mjs reports it.
    (: supervisor->json (-> Supervisor Json))
    (define (supervisor->json supervisor)
      (JsonObject (list (Pair "target" (JsonString (Supervisor-name supervisor)))
                        (Pair "desired"
                              (match (Supervisor-desired supervisor)
                                ((Some (Pair _ request))
                                 (JsonObject
                                  (list (Pair "build" (JsonInteger (RunRequest-build request))))))
                                ((None) (JsonNull))))
                        (Pair "attempt"
                              (match (Supervisor-child supervisor)
                                ((Some child) (child->json child))
                                ((None) (JsonNull)))))))

    (: child->json (-> Child Json))
    (define (child->json child)
      (JsonObject (list (Pair "build" (JsonInteger (RunRequest-build (Child-request child))))
                        (Pair "pid"
                              (match (Child-process child)
                                ((Some process) (JsonInteger (i32->i64 (Process-id process))))
                                ((None) (JsonNull))))
                        (Pair "phase" (JsonString (child-phase child)))
                        (Pair "code"
                              (match (Child-exit child)
                                ((Some (Ok (Exited code))) (JsonInteger (i32->i64 code)))
                                (_ (JsonNull))))
                        (Pair "signal"
                              (match (Child-exit child)
                                ((Some (Ok (Signaled name))) (JsonString name))
                                (_ (JsonNull))))
                        (Pair "error"
                              (match (Child-exit child)
                                ((Some (Err error)) (JsonString (ProcessError-code error)))
                                (_ (JsonNull))))
                        (Pair "stdout" (JsonString (lossy-text (Child-stdout child))))
                        (Pair "stderr" (JsonString (lossy-text (Child-stderr child)))))))

    (: child-phase (-> Child String))
    (define (child-phase child)
      (match (Child-exit child)
        ((Some (Err _)) "failed")
        ((Some (Ok _)) "exited")
        ((None)
         (cond ((Child-stopping child) "stopping")
               ((option-some? (Child-process child)) "running")
               (else "starting")))))

    ;; Output as text, each byte that is not UTF-8 as U+FFFD.
    (: lossy-text (-> Bytes String))
    (define (lossy-text bytes)
      (match (utf8->string bytes)
        ((Ok text) text)
        ((Err _)
         (list->string (map (lambda (byte)
                              (if (< (u8->i32 byte) 128)
                                  (i32->char (u8->i32 byte))
                                  (i32->char 65533)))
                            (vector->list bytes))))))

    ;; ---- HTTP ----

    ;; One handler task for each connection.
    (: accept-connections
       (-> Setup Listener (Mailbox Message) (Mailbox Scan) Unit ! mut tasks tcp fs modes))
    (define (accept-connections setup listener owner disk)
      (let loop ((id 0))
        (match (accept listener)
          ((Ok connection)
           (mailbox-post owner (Connected id connection))
           (dispatch-local (once (lambda ()
                                   (serve-connection setup owner disk id connection)
                                   (mailbox-post owner (Disconnected id)))))
           (loop (+ id 1)))
          ((Err _) (unit)))))

    (: security-headers (List Header))
    (define security-headers
      (list (Header "Cache-Control" "no-store")
            (Header "X-Content-Type-Options" "nosniff")
            (Header "X-Frame-Options" "DENY")))

    (: json-response (-> I32 Json Response))
    (define (json-response status body)
      (Response status
                (Cons (Header "Content-Type" "application/json") security-headers)
                (if (= status 204) (empty-bytes) (string->utf8 (json->string body)))))

    (: refused (-> I32 String Response))
    (define (refused status message)
      (json-response status (message->json message)))

    ;; A connection's one request, by the connection's number.
    (: serve-connection
       (-> Setup (Mailbox Message) (Mailbox Scan) I64 Connection Unit ! mut tasks tcp fs modes))
    (define (serve-connection setup owner disk id connection)
      (match (read-request connection)
        ((Ok request)
         (let ((method (RequestHead-method (Request-head request))))
           (match (route setup owner disk id connection request)
             ((Some response) (finish-exchange connection (Some method) response))
             ((None) (unit)))))
        ((Err error) (finish-exchange connection (None) (exchange-refusal error)))))

    (: finish-exchange (-> Connection (Option String) Response Unit ! tcp tasks))
    (define (finish-exchange connection method response)
      (match (ann (respond connection 2000 method response) (Result Unit (ExchangeError Unit)))
        ((Ok _) (unit))
        ((Err _) (close-connection connection) (unit))))

    (: exchange-refusal (-> (ExchangeError Unit) Response))
    (define (exchange-refusal error)
      (match error
        ((ProtocolFailure (Unsupported "Transfer-Encoding"))
         (refused 411 "requests must give a Content-Length, not a Transfer-Encoding"))
        ((ProtocolFailure (HeadTooLarge)) (refused 431 "the request head is too large"))
        ((ProtocolFailure (BodyTooLarge)) (refused 413 "request exceeds 8 MiB"))
        (_ (refused 400 "malformed request"))))

    ;; The response to a request, or None for an event stream, which this
    ;; task then writes until it ends.
    (: route
       (-> Setup
           (Mailbox Message)
           (Mailbox Scan)
           I64
           Connection
           Request
           (Option Response)
           ! mut tasks tcp fs modes))
    (define (route setup owner disk id connection request)
      (let ((head (Request-head request)))
        (match (parse-target (RequestHead-target head))
          ((Err _) (Some (refused 400 "malformed request target")))
          ((Ok target)
           (match (authorization setup head target)
             ((Some message) (Some (refused 403 message)))
             ((None) (endpoint setup owner disk id connection request target)))))))

    ;; A GET of an editor asset, the event stream, or the API.
    (: endpoint
       (-> Setup
           (Mailbox Message)
           (Mailbox Scan)
           I64
           Connection
           Request
           Target
           (Option Response)
           ! mut tasks tcp fs modes))
    (define (endpoint setup owner disk id connection request target)
      (let ((method (RequestHead-method (Request-head request))) (path (Target-path target)))
        (cond ((not (string=? method "GET"))
               (Some (api setup owner disk request method path (Target-query target))))
              ((same-strings? path (list "api" "events"))
               (stream-events owner id connection)
               (None))
              (else
               (Some (match (asset setup path)
                       ((Some found) (serve-asset found))
                       ((None)
                        (api setup owner disk request method path (Target-query target)))))))))

    (: api
       (-> Setup
           (Mailbox Message)
           (Mailbox Scan)
           Request
           String
           (List String)
           (List (Pair String String))
           Response
           ! mut tasks fs modes))
    (define (api setup owner disk request method path query)
      (match (Pair method path)
        ((Pair "GET" (Cons "api" (Cons "project" (Nil)))) (project-listing setup disk))
        ((Pair "GET" (Cons "api" (Cons "file" (Nil))))
         (file-response (read-project-text (Setup-project setup) (query-value query "path"))))
        ((Pair "GET" (Cons "api" (Cons "status" (Nil))))
         (asking owner (lambda (reply) (Status reply))))
        ((Pair "POST" (Cons "api" (Cons "build" (Nil))))
         (commanding request owner (RequestBuild)))
        ((Pair "POST" (Cons "api" (Cons "run" (Cons action (Nil)))))
         (match (run-control action (query-value query "target"))
           ((Some event) (commanding request owner event))
           ((None) (refused 404 "unknown project endpoint"))))
        ((Pair "PUT" (Cons "api" (Cons "file" (Nil))))
         (save setup disk request (query-value query "path")))
        (_ (refused 404 "unknown project endpoint"))))

    (: run-control (-> String String (Option Event)))
    (define (run-control action target)
      (cond ((string=? action "start") (Some (StartRun target)))
            ((string=? action "stop") (Some (StopRun target)))
            ((string=? action "restart") (Some (RestartRun target)))
            (else (None))))

    (: query-value (-> (List (Pair String String)) String String))
    (define (query-value query name)
      (match (find (lambda (pair) (string=? (Pair-first pair) name)) query)
        ((Some pair) (Pair-second pair))
        ((None) "")))

    ;; A command takes no body; the owner answers it once the step has.
    (: commanding (-> Request (Mailbox Message) Event Response ! mut tasks))
    (define (commanding request owner event)
      (if (> (vector-length (Request-body request)) 0)
          (refused 400 "command takes no request body")
          (asking owner (lambda (reply) (Ask event reply)))))

    (: asking (-> (Mailbox Message) (-> (Mailbox Answer) Message) Response ! mut tasks))
    (define (asking owner message)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (message reply))
        (let ((answer (mailbox-receive reply)))
          (json-response (Answer-status answer) (Answer-body answer)))))

    (: project-listing (-> Setup (Mailbox Scan) Response ! mut tasks fs))
    (define (project-listing setup disk)
      (let ((reply (make-mailbox)) (project (Setup-project setup)))
        (mailbox-post disk (Listing reply))
        (match (mailbox-receive reply)
          ((Err message) (refused 500 message))
          ((Ok paths)
           (match (project-text-paths project paths)
             ((Ok files)
              (json-response 200
                             (JsonObject (list (Pair "name" (JsonString (base-name project)))
                                               (Pair "directory" (JsonString project))
                                               (Pair "files" (JsonArray (map JsonString files)))))))
             ((Err refusal) (file-refusal refusal)))))))

    (: file-response (-> (Result ProjectText FileRefusal) Response))
    (define (file-response result)
      (match result
        ((Ok text)
         (json-response 200
                        (JsonObject (list (Pair "text" (JsonString (ProjectText-text text)))
                                          (Pair "revision"
                                                (JsonString (ProjectText-revision text)))))))
        ((Err refusal) (file-refusal refusal))))

    (: file-refusal (-> FileRefusal Response))
    (define (file-refusal refusal)
      (match refusal
        ((ChangedOnDisk) (refused 409 "the file changed on disk; reload it before saving"))
        ((NotServed message) (refused 400 message))
        ((DiskFailed (NotFound)) (refused 404 "no such file or directory"))
        ((DiskFailed (PermissionDenied)) (refused 403 "permission denied"))
        ((DiskFailed error) (refused 500 (show error)))))

    ;; A save names one quoted revision and sends UTF-8 text/plain. Once it
    ;; is on disk, the disk task scans, so the build sees it within the
    ;; debounce rather than the next second.
    (: save (-> Setup (Mailbox Scan) Request String Response ! mut fs modes))
    (define (save setup disk request path)
      (let ((head (Request-head request)))
        (match (expected-revision head)
          ((None) (refused 400 "save requires one quoted If-Match revision"))
          ((Some revision)
           (if (not (plain-text? head))
               (refused 415 "save requires UTF-8 text/plain")
               (match (utf8->string (Request-body request))
                 ((Err _) (refused 400 "save requires valid UTF-8"))
                 ((Ok text)
                  (let ((response (file-response
                                   (save-project-text (Setup-project setup) path revision text))))
                    (mailbox-post disk (Prompted))
                    response))))))))

    ;; One strong opaque tag: lists, wildcards and weak tags are not this API.
    (: expected-revision (-> RequestHead (Option String)))
    (define (expected-revision head)
      (match (header-values (RequestHead-headers head) "if-match")
        ((Cons value (Nil))
         (let ((length (string-length value)))
           (if (and (>= length 3)
                    (char=? (string-ref value 0) #\")
                    (char=? (string-ref value (- length 1)) #\")
                    (every? tag-char? (string->list (substring value 1 (- length 1)))))
               (Some (substring value 1 (- length 1)))
               (None))))
        (_ (None))))

    (: tag-char? (-> Char Bool))
    (define (tag-char? char)
      (let ((code (char->i32 char)))
        (or (= code 33) (and (>= code 35) (<= code 91)) (and (>= code 93) (<= code 126)))))

    (: plain-text? (-> RequestHead Bool))
    (define (plain-text? head)
      (match (header-values (RequestHead-headers head) "content-type")
        ((Cons value (Nil))
         (let ((type (list->string (filter (lambda (char) (not (char-whitespace? char)))
                                           (string->list (string-downcase value))))))
           (or (string=? type "text/plain") (string=? type "text/plain;charset=utf-8"))))
        (_ #f)))

    ;; The host and origin must be this service's, so another page cannot
    ;; reach it; a fetch from another site is refused, except a navigation
    ;; to the editor itself; and a change must come from the project's own
    ;; page.
    (: authorization (-> Setup RequestHead Target (Option String)))
    (define (authorization setup head target)
      (let ((headers (RequestHead-headers head)) (origin (origin setup)))
        (cond ((not (same-strings? (header-values headers "host")
                                   (list (substring origin 7 (string-length origin)))))
               (Some "unexpected host"))
              ((not (or (null? (header-values headers "origin"))
                        (same-strings? (header-values headers "origin") (list origin))))
               (Some "unexpected origin"))
              ((and (not (navigation? head target)) (cross-site? headers))
               (Some "unexpected fetch context"))
              ((and (not (string=? (RequestHead-method head) "GET"))
                    (not (same-strings? (header-values headers "origin") (list origin))))
               (Some "mutation requires the project origin"))
              (else (None)))))

    ;; The target `/`, which parses as no segment or one empty one.
    (: root-path? (-> (List String) Bool))
    (define (root-path? path)
      (match path
        ((Nil) #t)
        ((Cons "" (Nil)) #t)
        (_ #f)))

    (: navigation? (-> RequestHead Target Bool))
    (define (navigation? head target)
      (let ((headers (RequestHead-headers head)))
        (and (string=? (RequestHead-method head) "GET")
             (root-path? (Target-path target))
             (same-strings? (header-values headers "sec-fetch-mode") (list "navigate"))
             (same-strings? (header-values headers "sec-fetch-dest") (list "document")))))

    (: cross-site? (-> (List Header) Bool))
    (define (cross-site? headers)
      (match (header-values headers "sec-fetch-site")
        ((Cons site _) (not (or (string=? site "same-origin") (string=? site "none"))))
        ((Nil) #f)))

    (: same-strings? (-> (List String) (List String) Bool))
    (define (same-strings? left right)
      (and (= (length left) (length right))
           (every? (lambda (pair) (string=? (Pair-first pair) (Pair-second pair)))
                   (zip left right))))

    ;; ---- The editor's assets ----

    ;; Only the editor's own files share the API's origin: its page,
    ;; scripts, style and formatter. Project files are never served here.
    (: asset (-> Setup (List String) (Option (Pair String String))))
    (define (asset setup path)
      (let ((root (Setup-root setup)))
        (match (if (root-path? path) (Nil) path)
          ((Nil) (Some (Pair (string-append root "/host/ide/index.html") "text/html")))
          ((Cons name (Nil))
           (cond ((string=? name "format.wasm")
                  (Some (Pair (Setup-formatter setup) "application/wasm")))
                 ((string=? name "load.mjs")
                  (Some (Pair (string-append root "/host/browser/load.mjs") "text/javascript")))
                 ((string=? name "ide.css")
                  (Some (Pair (string-append root "/host/ide/ide.css") "text/css")))
                 ((member? name (list "ide.mjs" "editor.mjs" "panes.mjs" "formatter.mjs"))
                  (Some (Pair (string-append root "/host/ide/" name) "text/javascript")))
                 (else (None))))
          (_ (None)))))

    ;; The page and its scripts may load only from this origin, and no other
    ;; page may frame them.
    (: content-policy String)
    (define content-policy
      (string-join (list "default-src 'self'"
                         "script-src 'self' 'wasm-unsafe-eval'"
                         "style-src 'self' 'unsafe-inline'"
                         "frame-ancestors 'none'"
                         "base-uri 'none'"
                         "worker-src 'none'")
                   "; "))

    (: serve-asset (-> (Pair String String) Response ! fs))
    (define (serve-asset found)
      (match found
        ((Pair path type)
         (if (file-exists? path)
             (Response 200
                       (append (list (Header "Content-Type" type)
                                     (Header "Content-Security-Policy" content-policy))
                               security-headers)
                       (read-bytes path))
             (refused 404 "editor asset is unavailable")))))

    ;; ---- Writing an event stream ----

    ;; Joins the owner's streams, then writes each frame it sends until it
    ;; sends none, or a write fails. The handler's end tells the owner the
    ;; stream has gone.
    (: stream-events (-> (Mailbox Message) I64 Connection Unit ! mut tasks tcp))
    (define (stream-events owner id connection)
      (let ((frames (make-mailbox)) (reply (make-mailbox)))
        (mailbox-post owner (Joined id connection frames reply))
        (let ((answer (mailbox-receive reply)))
          (if (= (Answer-status answer) 200)
              (match (encode-stream-head 200
                                         (Cons (Header "Content-Type" "text/event-stream")
                                               security-headers))
                ((Ok head) (when (sent? connection head) (write-frames owner id connection frames)))
                ((Err _) (unit)))
              (finish-exchange connection
                               (Some "GET")
                               (json-response (Answer-status answer) (Answer-body answer)))))))

    (: write-frames
       (-> (Mailbox Message) I64 Connection (Mailbox (Option Bytes)) Unit ! mut tasks tcp))
    (define (write-frames owner id connection frames)
      (match (mailbox-receive frames)
        ((Some bytes)
         (if (sent? connection bytes)
             (begin
               (mailbox-post owner (Written id (vector-length bytes)))
               (write-frames owner id connection frames))
             (begin
               (close-connection connection)
               (unit))))
        ((None) (close-connection connection) (unit))))

    (: sent? (-> Connection Bytes Bool ! tasks tcp))
    (define (sent? connection bytes)
      (if (= (vector-length bytes) 0)
          #t
          (match (write connection bytes)
            ((Ok count)
             (and (> count 0)
                  (sent? connection (subvector bytes (i32->i64 count) (vector-length bytes)))))
            ((Err _) #f))))))
