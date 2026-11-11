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
;;   for an event stream, writes what the owner sends it; and one for each
;;   connection to the applications' origin, which serves each browser
;;   target's builds ((snail shell project bundle)).
;;
;; No cell holds state: each task threads its own through its loop. It is
;; #567 steps B3 to B5, which replaced a service in JavaScript.
(define-library (snail shell project service)
  (export
   Setup
   develop)
  (import
   (snail shell project web-app)
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
   (snail shell project bundle)
   (snail shell project files)
   (prefix (snail shell gitignore) ignore-)
   (prefix (snail shell project protocol) protocol-)
   (prefix (snail shell project search) search-))
  (begin

    ;; ---- Setup ----

    ;; What the service runs with: the repository's root; the command
    ;; line's program and the runtime it links programs with, which the
    ;; resident runs as; Node, which runs them; the editor's published bundle; the
    ;; reload client's program, which browser targets' pages load; the
    ;; project, absolute; and the port to listen on, 0 for any.
    (struct Setup
      ((root String)
       (cli String)
       (runtime String)
       (node String)
       (editor String)
       (client String)
       (project String)
       (port I32)))

    (define (runner (setup Setup)) (→ String)
      (string-append (::root setup) "/host/native/run-snail.mjs"))

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
      (EditorAssets ((reply (Mailbox (List EditorBundle)))))
      (EditorBuilt ((result (Result EditorBundle String))))
      (Applications ((reply (Mailbox (List Application)))))
      (Fired ((serial I64)))
      (Built
       ((epoch I64)
        (reply Reply)
        (targets Json)))
      (ResidentGone ((message String)))
      (Overdue)
      (RunChanged
       ((name String)
        (status protocol-Run)))
      (RunStopped)
      (Joined
       ((id I64)
        (watching (Option String))
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
      (Listing ((reply (Mailbox (Result Inventory String)))))
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

    ;; A browser target as the applications' origin serves it: its name and
    ;; the builds of it retained, newest first.
    (struct Application
      ((name String)
       (builds (List BuildDirectory))))

    ;; An event stream, by its connection's number: the browser target a
    ;; page's stream hears of builds of, or none for an editor's; and how
    ;; many bytes the owner sent it that its writer has not written yet.
    (struct Client
      ((id I64)
       (watching (Option String))
       (connection Connection)
       (frames (Mailbox (Option Bytes)))
       (pending I64)))

    (struct Supervised
      ((name String)
       (inbox (Mailbox Supervision))
       (status protocol-Run)))

    ;; Everything the step leaves to its host. `targets` is the latest
    ;; reply's candidate, by epoch, and `published` the targets of the one
    ;; published, as the status shows them. `frames` is the last complete
    ;; editor snapshot sent. The owner holds its instance and file counter.
    ;; `connections` are the ones whose handlers have not finished, by
    ;; number, and `clients` those of them that are event streams; `told`
    ;; is the event last sent to each browser target's pages.
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
       (applications Listener)
       (service Service)
       (snapshot Snapshot)
       (serial I64)
       (reservation (Option (Pair I64 String)))
       (targets (Option (Pair I64 Json)))
       (published Json)
       (runs (List Supervised))
       (clients (List Client))
       (told (List (Pair String String)))
       (connections (List (Pair I64 Connection)))
       (frames String)
       (instance String)
       (files I64)
       (editors (List EditorBundle))
       (editor-process (Option Process))
       (editor-again Bool)
       (editor-problem String)
       (stopping (Option (List Command)))
       (waiting I64)
       (done Bool)))

    ;; ---- Starting ----

    ;; Dispatches the task that starts the service; the scheduler runs it
    ;; once the program's main returns. The service ends when the owner has
    ;; shut everything down, and fails the program if the step went fatal.

    (define (develop (setup Setup))
      (→ Unit)
      (! mut tcp process fs modes hints console signals clock)
      (dispatch-local (once (lambda () (start setup)))))

    ;; Listens, starts the resident, announces the editor's URL and the
    ;; applications', and dispatches every other task.

    (define (start (setup Setup))
      (→ Unit)
      (! mut tasks tcp process fs modes hints console signals clock)
      (let* ((listener (listening setup))
             (applications (applications-listening (::port setup)))
             (setup (Setup-port-set setup (::port listener)))
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
        (dispatch-local (once (lambda () (accept-applications setup applications owner))))
        (dispatch-local (once (lambda () (mailbox-post owner (Step (wait-for-signal))))))
        (mailbox-post owner (Step (ResidentStarted)))
        (write-line (string-append "editing " (::project setup) " at " (origin setup) "/"))
        (write-line (string-append "serving its browser targets at "
                                   (listener-origin applications)
                                   "/NAME/"))
        (own (new-host setup owner disk requests resident listener applications))))

    (define (wait-for-signal) (→ Event) (! tasks signals)
      (termination)
      (Close))

    (define (listening (setup Setup)) (→ Listener) (! tasks tcp)
      (match (listen-locally (::port setup))
        ((Ok listener) listener)
        ((Err error)
         (panic (string-append "cannot listen on port "
                               (show (::port setup))
                               ": "
                               (::code error))))))

    (define (origin (setup Setup)) (→ String)
      (string-append "http://127.0.0.1:" (show (::port setup))))

    ;; The applications' origin is apart from the editor's, so no page of
    ;; the project can reach the editor's API. It takes the port after the
    ;; editor's when the editor's was asked for, or any port when that one
    ;; is taken or none was.

    (define (applications-listening (port I32)) (→ Listener) (! tasks tcp)
      (match (if (= port 0)
                 (Err (SocketError "unasked"))
                 (listen-locally (+ port 1)))
        ((Ok listener) listener)
        ((Err _)
         (match (listen-locally 0)
           ((Ok listener) listener)
           ((Err error)
            (panic (string-append "cannot listen for the applications: "
                                  (::code error))))))))

    ;; The service listens on the loopback address alone.

    (define (listen-locally (port I32)) (→ (Result Listener SocketError)) (! tasks tcp)
      (match (endpoint "127.0.0.1" port)
        ((Ok local) (listen local))
        ((Err error) (Err error))))

    (define (listener-host (listener Listener)) (→ String)
      (string-append "127.0.0.1:" (show (::port listener))))

    (define (listener-origin (listener Listener)) (→ String)
      (string-append "http://" (listener-host listener)))

    (define (new-host (setup Setup)
                      (owner (Mailbox Message))
                      (disk (Mailbox Scan))
                      (requests (Mailbox (Option String)))
                      (resident Process)
                      (listener Listener)
                      (applications Listener))
      (→ Host)
      (! clock fs)
      (Host setup
            owner
            disk
            requests
            resident
            #t
            listener
            applications
            (new-service (::root setup) (::project setup))
            (Snapshot (Starting) 0 (Nil) (Nil) (Nil))
            0
            (None)
            (None)
            (JsonNull)
            (Nil)
            (Nil)
            (Nil)
            (Nil)
            ""
            (string-append (show (::id resident)) ":" (show (monotonic-nanoseconds)))
            0
            (list (match (editor-bundle setup)
                    ((Ok bundle) bundle) ((Err message) (panic message))))
            (None)
            #f
            ""
            (None)
            0
            #f))

    ;; ---- The owner ----

    (define (own (host Host)) (→ Unit) (! mut tasks tcp process fs)
      (let ((host (receive host (mailbox-receive (::owner host)))))
        (if (::done host) (finish host) (own host))))

    ;; A fatal service fails the program, with the diagnostic that ended it.

    (define (finish (host Host)) (→ Unit)
      (match (::phase (::snapshot host))
        ((Fatal) (panic (first-message (::snapshot host))))
        (_ (unit))))

    (define (first-message (snapshot Snapshot)) (→ String)
      (match (::diagnostics snapshot)
        ((Cons diagnostic _) (::message diagnostic))
        ((Nil) "the service failed")))

    (define (receive (host Host) (message Message)) (→ Host) (! mut tasks tcp process fs)
      (match message
        ((Step event) (stepped (touched-editor (touched-files host event) event) event))
        ((Ask event reply) (asked host event reply))
        ((Status reply) (mailbox-post reply (Answer 200 (status->json host))) host)
        ((EditorAssets reply) (mailbox-post reply (::editors host)) host)
        ((EditorBuilt result) (editor-built host result))
        ((Applications reply) (mailbox-post reply (served-applications host)) host)
        ((Fired serial) (if (= serial (::serial host)) (stepped host (TimerFired)) host))
        ((Built epoch reply targets)
         (stepped (Host-targets-set host (Some (Pair epoch targets))) (BuildReplied epoch reply)))
        ((ResidentGone message) (resident-gone host message))
        ((Overdue) (overdue host))
        ((RunChanged name status) (broadcast-changes (run-changed host name status)))
        ((RunStopped) (stopped-one host))
        ((Joined id watching connection frames reply)
         (joined host id watching connection frames reply))
        ((Written id count) (written host id count))
        ((Connected id connection) (connected host id connection))
        ((Disconnected id) (disconnected host id))))

    (define (stepped (host Host) (event Event)) (→ Host) (! mut tasks tcp process fs)
      (let ((result (step (::service host) event)))
        (perform-all (Host-service-set host (::first result)) (::second result))))

    ;; A handler's event, answered once its commands ran: the step's
    ;; refusal, or what the request asked for.

    (define (asked (host Host) (event Event) (reply (Mailbox Answer)))
      (→ Host)
      (! mut tasks tcp process fs)
      (let* ((result (step (::service host) event))
             (host
              (perform-all (Host-service-set host (::first result)) (::second result))))
        (mailbox-post reply (answer-for host event (refusal-of (::second result))))
        host))

    (define (refusal-of (commands (List Command))) (→ (Option Refusal))
      (match commands
        ((Nil) (None))
        ((Cons (Refuse refusal) _) (Some refusal))
        ((Cons _ rest) (refusal-of rest))))

    (define (answer-for (host Host) (event Event) (refusal (Option Refusal))) (→ Answer)
      (match refusal
        ((Some (UnknownRunTarget name))
         (Answer 404 (protocol-message->json (string-append "unknown accepted run target: " name))))
        ((Some (ServiceClosed))
         (Answer 503 (protocol-message->json "project development is closing")))
        ((None)
         (match event
           ((RequestBuild) (Answer 202 (protocol-build->json (editor-status (::snapshot host)))))
           (_ (Answer 204 (JsonNull)))))))

    ;; ---- Carrying out commands ----

    ;; Each command in order. The commands after Shutdown wait until the
    ;; resident and every run's process have stopped.

    (define (perform-all (host Host) (commands (List Command)))
      (→ Host)
      (! mut tasks tcp process fs)
      (match commands
        ((Nil) host)
        ((Cons (Shutdown) rest) (shut-down host rest))
        ((Cons command rest) (perform-all (perform host command) rest))))

    (define (perform (host Host) (command Command)) (→ Host) (! mut tcp process fs)
      (match command
        ((Build epoch) (build host epoch))
        ((Reconcile) (mailbox-post (::disk host) (Reconciling)) host)
        ((Publish epoch) (request host (epoch-request "publish" epoch (Nil))))
        ((Discard epoch) (request host (epoch-request "discard" epoch (Nil))))
        ((Abandon epoch) (give-up host epoch #t))
        ((Release epoch) (give-up host epoch #f))
        ((Arm) (arm host))
        ((Launch name wanted) (launch host name wanted))
        ((Refuse _) host)
        ((Notify snapshot) (notify host snapshot))
        ((Reclaim directories)
         (for-each (lambda (directory)
                     (remove-tree directory)
                     (unit))
                   directories)
         host)
        ((Shutdown) host)
        ((Closed) (Host-done-set host #t))))

    (define (request (host Host) (line String)) (→ Host) (! mut)
      (mailbox-post (::requests host) (Some line))
      host)

    (define (epoch-request (kind String) (epoch I64) (rest (List (Pair String Json)))) (→ String)
      (json->string (JsonObject (append (list (Pair "kind" (JsonString kind))
                                              (Pair "epoch" (JsonInteger epoch)))
                                        rest))))

    ;; An attempt's build directory, reserved under build/ before the
    ;; resident makes generations beside it, named for it.

    (define (build (host Host) (epoch I64)) (→ Host) (! mut fs)
      (match (reserve (string-append (::project (::setup host)) "/build") 0)
        ((Ok directory)
         (request (Host-reservation-set host (Some (Pair epoch directory)))
                  (epoch-request "build"
                                 epoch
                                 (list (Pair "prefix"
                                             (JsonString
                                              (string-append (base-name directory) "-")))))))
        ((Err message)
         (mailbox-post (::owner host) (Step (ResidentExited message)))
         host)))

    ;; A name no entry of build/ has, nor begins, so the generations the
    ;; resident names with it are this attempt's alone, even beside what an
    ;; earlier service left there.

    (define (reserve (build String) (number I64)) (→ (Result String String)) (! fs)
      (match (make-directories build)
        ((Err error) (Err (string-append "cannot make " build ": " (show error))))
        ((Ok _)
         (match (list-directory build)
           ((Err error) (Err (string-append "cannot list " build ": " (show error))))
           ((Ok names) (reserve-unused build names number))))))

    (define (reserve-unused (build String) (names (List String)) (number I64))
      (→ (Result String String))
      (! fs)
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

    (define (base-name (path String)) (→ String)
      (let loop ((index (string-length path)))
        (cond ((= index 0) path)
              ((char=? (string-ref path (- index 1)) #\/)
               (substring path index (string-length path)))
              (else (loop (- index 1))))))

    ;; Gives up an attempt's directory, and when the attempt still owns
    ;; them, the generations the resident named for it.

    (define (give-up (host Host) (epoch I64) (generations? Bool)) (→ Host) (! fs)
      (match (::reservation host)
        ((Some (Pair reserved directory))
         (if (= reserved epoch)
             (begin
               (when generations? (remove-generations directory))
               (remove-tree directory)
               (Host-reservation-set host (None)))
             host))
        ((None) host)))

    (define (remove-generations (directory String)) (→ Unit) (! fs)
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

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    ;; Arming replaces the timer armed before: the owner ignores a firing
    ;; whose serial is not the latest.

    (define (arm (host Host)) (→ Host) (! mut)
      (let ((serial (+ (::serial host) 1)) (owner (::owner host)))
        (dispatch-local (once (lambda ()
                                (sleep 40)
                                (mailbox-post owner (Fired serial)))))
        (Host-serial-set host serial)))

    ;; ---- Run targets ----

    ;; A launch goes to the target's supervisor, started the first time
    ;; the target is launched.

    (define (launch (host Host) (name String) (wanted (Option RunRequest))) (→ Host) (! mut process)
      (match (find (lambda (run) (string=? (::name run) name)) (::runs host))
        ((Some run) (mailbox-post (::inbox run) (Want wanted)) host)
        ((None)
         (let ((inbox (make-mailbox)) (setup (::setup host)) (owner (::owner host)))
           (dispatch-local (once (lambda () (supervise (new-supervisor setup owner inbox name)))))
           (mailbox-post inbox (Want wanted))
           (Host-runs-set host
                          (append (::runs host)
                                  (list (Supervised name inbox (idle-run name)))))))))

    (define (run-changed (host Host) (name String) (status protocol-Run)) (→ Host)
      (Host-runs-set host
                     (map (lambda (run)
                            (if (string=? (::name run) name)
                                (Supervised-status-set run status)
                                run))
                          (::runs host))))

    ;; ---- Status ----

    ;; A snapshot to every event stream, as the frames that changed. A
    ;; fatal one closes the service.

    (define (notify (host Host) (snapshot Snapshot)) (→ Host) (! mut tcp fs)
      (let ((host (told-pages
                   (broadcast-changes (Host-snapshot-set (published host snapshot) snapshot)))))
        (match (::phase snapshot)
          ((Fatal) (mailbox-post (::owner host) (Step (Close))) host)
          (_ host))))

    ;; The published targets, once the snapshot names the build whose
    ;; candidate the owner kept; a browser target's has the URL it is
    ;; served at.

    (define (published (host Host) (snapshot Snapshot)) (→ Host)
      (match (Pair (::publications snapshot) (::targets host))
        ((Pair (Cons build _) (Some (Pair epoch targets)))
         (if (= (::id build) epoch)
             (Host-published-set host
                                 (JsonObject (list (Pair "id" (JsonInteger epoch))
                                                   (Pair "targets"
                                                         (with-urls host build targets)))))
             host))
        (_ host)))

    (define (with-urls (host Host) (build Published) (targets Json)) (→ Json)
      (let ((browsers (::browsers (::description (::candidate build)))))
        (match targets
          ((JsonArray items)
           (JsonArray (map (lambda (target) (with-url host browsers target)) items)))
          (other other))))

    (define (with-url (host Host) (browsers (List String)) (target Json)) (→ Json)
      (let ((name (json-text target "name")))
        (match target
          ((JsonObject members)
           (if (member? name browsers)
               (JsonObject
                (append members (list (Pair "url" (JsonString (application-url host name))))))
               target))
          (other other))))

    (define (application-url (host Host) (name String)) (→ String)
      (string-append (listener-origin (::applications host)) "/" name "/"))

    ;; The browser targets of the publication, each with its builds the
    ;; service retains, newest first. A target the latest description no
    ;; longer has is not served.

    (define (served-applications (host Host)) (→ (List Application))
      (let ((publications (::publications (::snapshot host))))
        (match publications
          ((Cons latest _)
           (map (lambda (name) (Application name (builds-of publications name)))
                (::browsers (::description (::candidate latest)))))
          ((Nil) (Nil)))))

    (define (builds-of (publications (List Published)) (name String)) (→ (List BuildDirectory))
      (concatenate (map (lambda (published)
                          (map (lambda (generation)
                                 (BuildDirectory (::id published)
                                                 (::directory generation)
                                                 (::files generation)
                                                 (::milliseconds
                                                  (::candidate published))))
                               (filter
                                (lambda (generation) (string=? (::name generation) name))
                                (::generations (::candidate published)))))
                        publications)))

    (define (editor-status (snapshot Snapshot)) (→ protocol-Build)
      (protocol-Build (phase-name (::phase snapshot)) (::id snapshot)
                      (map diagnostic-report (::diagnostics snapshot))))

    (define (editor-state (host Host)) (→ protocol-ServerState)
      (protocol-ServerState (::instance host) (::files host)
                            (editor-status (::snapshot host)) (run-states host)
                            (editor-base (list-ref (::editors host) 0))
                            (::editor-problem host)))

    ;; All a client can observe in one snapshot: the attempt, the published
    ;; targets, the resident's process and the run targets.

    (define (status->json (host Host)) (→ Json)
      (match (protocol-build->json (editor-status (::snapshot host)))
        ((JsonObject members)
         (JsonObject (append members
                             (list (Pair "published" (::published host))
                                   (Pair "compiler"
                                         (if (::resident-alive host)
                                             (JsonObject (list (Pair "worker"
                                                                     (JsonInteger
                                                                      (i32->i64
                                                                       (::id
                                                                        (::resident host)))))))
                                             (JsonNull)))
                                   (Pair "runs" (runs->json host))))))
        (other other)))

    (define (phase-name (phase Phase)) (→ String)
      (match phase
        ((Starting) "starting")
        ((Building) "building")
        ((Succeeded) "succeeded")
        ((Failed) "failed")
        ((Superseded) "superseded")
        ((Fatal) "fatal")))

    (define (diagnostic-report (diagnostic Diagnostic)) (→ protocol-Report)
      (protocol-Report "error" (::message diagnostic)
                       (match (::source diagnostic)
                         ((Some point) (Some (protocol-Point (::file point)
                                                             (::line point)
                                                             (::column point))))
                         ((None) (None)))))

    (define (runs->json (host Host)) (→ Json)
      (JsonArray (map protocol-run->json (run-states host))))

    ;; One typed snapshot combines the step's intention and each supervisor's
    ;; latest observation. Neither task constructs fragments of wire JSON.

    (define (run-states (host Host)) (→ (List protocol-Run))
      (map (lambda (run)
             (protocol-Run-available-set
              (protocol-Run-wanted-set (run-status host (::name run))
                                       (::wanted run))
              (::available run)))
           (::runs (::snapshot host))))

    (define (run-status (host Host) (name String)) (→ protocol-Run)
      (match (find (lambda (run) (string=? (::name run) name)) (::runs host))
        ((Some run) (::status run))
        ((None) (idle-run name))))

    (define (idle-run (name String)) (→ protocol-Run)
      (protocol-Run name (None) (None) #f #f))

    ;; ---- Event streams ----

    ;; A complete snapshot replaces the separate build, process and file
    ;; events. Suppress duplicates; a new connection always gets current state.

    (define (broadcast-changes (host Host)) (→ Host) (! mut tcp)
      (let ((text (protocol-state->event (editor-state host))))
        (if (string=? text (::frames host)) host
            (broadcast (Host-frames-set host text) text))))

    ;; A change under the project tells each editor to list its files again.

    (define (touched-files (host Host) (event Event)) (→ Host) (! mut tcp)
      (match event
        ((Touched paths)
         (let ((project (::project (::setup host))))
           (if (any? (lambda (path) (or (string=? path project)
                                        (starts-with? path (string-append project "/"))))
                     paths)
               (broadcast-changes (Host-files-set host (+ (::files host) 1)))
               host)))
        (_ host)))

    ;; Each client gets the frame, unless 16 KiB it was sent before are
    ;; still unwritten, as Node's stream refuses more: then it is dropped,
    ;; and reconnecting gets it the current status.

    (define (broadcast (host Host) (text String)) (→ Host) (! mut tcp)
      (Host-clients-set host
                        (sent-to (::clients host)
                                 (lambda (client) (not (option-some? (::watching client))))
                                 (string->utf8 text))))

    ;; Each client `chosen` picks gets the frame; the rest are left as they
    ;; are.

    (define (sent-to (clients (List Client)) (chosen (dyn (Fn Client → Bool))) (bytes Bytes))
      (→ (List Client))
      (! mut tcp)
      (match clients
        ((Nil) (Nil))
        ((Cons client rest)
         (cond ((not (chosen client)) (Cons client (sent-to rest chosen bytes)))
               ((>= (::pending client) 16384)
                (close-connection (::connection client))
                (mailbox-post (::frames client) (None))
                (sent-to rest chosen bytes))
               (else
                (mailbox-post (::frames client) (Some bytes))
                (Cons (Client-pending-set client (+ (::pending client) (vector-length bytes)))
                      (sent-to rest chosen bytes)))))))

    ;; A new event stream gets the status, the runs and a prompt to list
    ;; files, unless there are 64 already or the service is closing.

    (define (joined (host Host)
                    (id I64)
                    (watching (Option String))
                    (connection Connection)
                    (frames (Mailbox (Option Bytes)))
                    (reply (Mailbox Answer)))
      (→ Host)
      (! mut tcp fs)
      (cond ((option-some? (::stopping host))
             (mailbox-post reply
                           (Answer 503 (protocol-message->json "project development is closing")))
             host)
            ((>= (length (::clients host)) 64)
             (mailbox-post reply (Answer 429 (protocol-message->json "too many event connections")))
             host)
            (else
             (mailbox-post reply (Answer 200 (JsonNull)))
             (Host-clients-set host
                               (append (sent-to (list (Client id watching connection frames 0))
                                                (lambda (client) #t)
                                                (string->utf8 (match watching
                                                                ((Some name)
                                                                 (page-first-frames host name))
                                                                ((None) (first-frames host)))))
                                       (::clients host))))))

    ;; ---- Pages' event streams ----

    ;; What a browser target's pages hear of the latest attempt, with the
    ;; target's latest build: the reload client relinks a page when one is
    ;; published, and shows when one is under way or why one failed.

    (define (page-event (snapshot Snapshot) (application Application)) (→ String) (! fs)
      (bundle-event (string-append "/" (::name application) "/")
                    (match (::phase snapshot)
                      ((Succeeded) (BuildPublished))
                      ((Failed) (BuildFailed (diagnostic-text snapshot)))
                      ((Fatal) (BuildFailed (diagnostic-text snapshot)))
                      (_ (BuildUnderway)))
                    (match (::builds application)
                      ((Cons latest _) (Some latest))
                      ((Nil) (None)))))

    ;; Each diagnostic as a compiler prints it, after its place when it has
    ;; one.

    (define (diagnostic-text (snapshot Snapshot)) (→ String)
      (string-join (map (lambda (diagnostic)
                          (match (::source diagnostic)
                            ((Some point)
                             (string-append (::file point)
                                            ":"
                                            (show (::line point))
                                            ":"
                                            (show (::column point))
                                            ": "
                                            (::message diagnostic)))
                            ((None) (::message diagnostic))))
                        (::diagnostics snapshot))
                   "\n\n"))

    ;; An event as the browser's EventSource reads it. It is one line, as
    ;; the strings in it are written with their newlines escaped.

    (define (page-frame (text String)) (→ String)
      (string-append "data: " text "\n\n"))

    ;; A page's stream starts with its target's current event, so a page
    ;; that reconnects hears of the build it missed.

    (define (page-first-frames (host Host) (name String)) (→ String) (! fs)
      (let ((snapshot (::snapshot host)))
        (string-append "retry: 1000\n\n"
                       (page-frame (page-event snapshot
                                               (Application name
                                                            (builds-of
                                                             (::publications snapshot)
                                                             name)))))))

    ;; Each browser target's pages hear its event when it changes.

    (define (told-pages (host Host)) (→ Host) (! mut tcp fs)
      (fold-left (lambda (host application)
                   (let ((name (::name application))
                         (event (page-event (::snapshot host) application)))
                     (match (assoc-ref (::told host) name)
                       ((Some told) (if (string=? told event) host (told-page host name event)))
                       ((None) (told-page host name event)))))
                 host
                 (served-applications host)))

    ;; `event` to the pages of target `name`, kept as the last they heard.

    (define (told-page (host Host) (name String) (event String)) (→ Host) (! mut tcp)
      (Host-clients-set
       (Host-told-set host
                      (Cons (Pair name event)
                            (filter (lambda (told) (not (string=? (::first told) name)))
                                    (::told host))))
       (sent-to (::clients host)
                (lambda (client)
                  (match (::watching client)
                    ((Some watched) (string=? watched name))
                    ((None) #f)))
                (string->utf8 (page-frame event)))))

    (define (first-frames (host Host)) (→ String)
      (string-append "retry: 1000\n\n" (protocol-state->event (editor-state host))))

    (define (option-some? (option (Option T))) (→ Bool) (∀ T) (⊨ (Copy T))
      (match option
        ((Some _) #t)
        ((None) #f)))

    (define (written (host Host) (id I64) (count I64)) (→ Host)
      (Host-clients-set host
                        (map (lambda (client)
                               (if (= (::id client) id)
                                   (Client-pending-set client (- (::pending client) count))
                                   client))
                             (::clients host))))

    ;; ---- Shutting down ----

    ;; No new work: the listeners and every stream close, each supervisor
    ;; stops its process, and the resident's input ends, so it finishes the
    ;; request it is answering and exits, or is killed after 2 s.

    (define (shut-down (host Host) (rest (List Command))) (→ Host) (! mut tasks tcp process fs)
      (close-listener (::listener host))
      (close-listener (::applications host))
      (for-each (lambda (client) (mailbox-post (::frames client) (None))) (::clients host))
      (for-each (lambda (open) (close-connection (::second open)) (unit))
                (::connections host))
      (for-each (lambda (run) (mailbox-post (::inbox run) (Finish))) (::runs host))
      (mailbox-post (::requests host) (None))
      (mailbox-post (::disk host) (Stopping))
      (match (::editor-process host)
        ((Some child) (close-process child) (unit))
        ((None) (unit)))
      (let ((owner (::owner host)))
        (dispatch-local (once (lambda () (sleep 2000) (mailbox-post owner (Overdue))))))
      (resumed
       (Host-waiting-set (Host-connections-set (Host-stopping-set (Host-clients-set host (Nil))
                                                                  (Some rest))
                                               (Nil))
                         (+ (+ (length (::runs host)) (length (::connections host)))
                            (+ (if (::resident-alive host) 1 0)
                               (if (option-some? (::editor-process host)) 1 0))))))

    ;; A connection accepted while stopping is closed at once; its handler
    ;; still reports that it finished.

    (define (connected (host Host) (id I64) (connection Connection)) (→ Host) (! tcp)
      (match (::stopping host)
        ((Some _)
         (close-connection connection)
         (Host-waiting-set host (+ (::waiting host) 1)))
        ((None) (Host-connections-set host (Cons (Pair id connection) (::connections host))))))

    ;; A finished handler's connection, and its event stream if it had one.

    (define (disconnected (host Host) (id I64)) (→ Host) (! mut tasks tcp process fs)
      (match (::stopping host)
        ((Some _) (stopped-one host))
        ((None)
         (Host-clients-set (Host-connections-set host
                                                 (filter
                                                  (lambda (open) (not (= (::first open) id)))
                                                  (::connections host)))
                           (filter (lambda (client) (not (= (::id client) id)))
                                   (::clients host))))))

    ;; Once nothing is still stopping, the commands after Shutdown.

    (define (resumed (host Host)) (→ Host) (! mut tasks tcp process fs)
      (match (::stopping host)
        ((Some rest)
         (if (= (::waiting host) 0)
             (perform-all (Host-stopping-set host (Some (Nil))) rest)
             host))
        ((None) host)))

    (define (stopped-one (host Host)) (→ Host) (! mut tasks tcp process fs)
      (resumed (Host-waiting-set host (- (::waiting host) 1))))

    (define (resident-gone (host Host) (message String)) (→ Host) (! mut tasks tcp process fs)
      (let ((host (Host-resident-alive-set host #f)))
        (match (::stopping host)
          ((Some _) (stopped-one host))
          ((None) (stepped host (ResidentExited message))))))

    (define (overdue (host Host)) (→ Host) (! process)
      (when (::resident-alive host)
        (send-signal (::resident host) (Kill))
        (unit))
      host)

    ;; ---- The disk ----

    ;; The project, the libraries and the browser host, leaving out build
    ;; output and Git's directory.

    (define (watched (setup Setup)) (→ (Pair (List String) (List String)))
      (let ((root (::root setup)) (project (::project setup)))
        (Pair (list project (string-append root "/src") (string-append root "/host/browser")
                    (string-append root "/host/ide"))
              (list (string-append project "/build")
                    (string-append project "/.git")
                    (string-append root "/build") (string-append root "/host/ide/build")))))

    (define (take-inventory (setup Setup)) (→ (Result Inventory String)) (! fs)
      (let ((roots (watched setup)))
        (inventory (::first roots) (::second roots))))

    ;; The last complete inventory, and why the latest failed, if it did.
    (struct Disk
      ((taken Inventory)
       (failure (Option String))))

    ;; Takes the first inventory as what is there, then one for each scan
    ;; asked, reporting what changed since the last. Hints from a watch of
    ;; each root ask for one at once; the timer asks each second, as a
    ;; watch can miss a change. After Stopping it closes the watches,
    ;; answers the timer that it is done, and ends.

    (define (scan-disk (setup Setup) (owner (Mailbox Message)) (requests (Mailbox Scan)))
      (→ Unit)
      (! mut tasks fs hints)
      (let* ((roots (watched setup))
             (watches (watch-roots (::first roots) (::second roots) requests)))
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
               (mailbox-post reply (disk-result next (::taken next)))
               (loop next stopping)))
            ((Prompted) (loop (if stopping disk (rescan setup owner disk #t)) stopping))
            ((Reconciling)
             (let ((next (rescan setup owner disk #t)))
               (mailbox-post owner (Step (Reconciled (disk-result next (unit)))))
               (loop next stopping)))))))

    ;; What the latest inventory found, unless it failed.

    (define (disk-result (disk Disk) (value T)) (→ (Result T String)) (∀ T) (⊨ (Copy T))
      (match (::failure disk)
        ((Some message) (Err message))
        ((None) (Ok value))))

    ;; A watch of each root that can be watched, each with a task that
    ;; turns its hints into scans until it closes.

    (define (watch-roots (roots (List String)) (excluded (List String)) (disk (Mailbox Scan)))
      (→ (List Watch))
      (! mut hints)
      (match roots
        ((Nil) (Nil))
        ((Cons root rest)
         (match (watch-tree root excluded)
           ((Some watch)
            (dispatch-local (once (lambda () (relay-hints watch disk))))
            (Cons watch (watch-roots rest excluded disk)))
           ((None) (watch-roots rest excluded disk))))))

    (define (relay-hints (watch Watch) (disk (Mailbox Scan))) (→ Unit) (! mut tasks hints)
      (when (next-hint watch)
        (mailbox-post disk (Prompted))
        (relay-hints watch disk)))

    ;; Another inventory, reported as what changed since the last complete
    ;; one when `report?`, as it is but for the first. A failure keeps the
    ;; last, and is reported once, when it begins; the next inventory that
    ;; succeeds reports the recovery, after what changed meanwhile.

    (define (rescan (setup Setup) (owner (Mailbox Message)) (disk Disk) (report? Bool))
      (→ Disk)
      (! mut fs)
      (match (take-inventory setup)
        ((Ok next)
         (let ((changes (inventory-changes (::taken disk) next)))
           (when (and report? (not (null? changes)))
             (mailbox-post owner (Step (Touched changes))))
           (when (option-some? (::failure disk))
             (mailbox-post owner (Step (Uncertain (None)))))
           (Disk next (None))))
        ((Err message)
         (unless (option-some? (::failure disk))
           (mailbox-post owner (Step (Uncertain (Some message)))))
         (Disk-failure-set disk (Some message)))))

    ;; A scan each second, until the disk task stops.

    (define (tick (disk (Mailbox Scan))) (→ Unit) (! mut tasks)
      (sleep 1000)
      (let ((reply (make-mailbox)))
        (mailbox-post disk (Ticked reply))
        (when (mailbox-receive reply)
          (tick disk))))

    ;; ---- The resident ----

    (define (resident-process (setup Setup)) (→ Process) (! tasks process)
      (match (spawn (ProcessCommand (::node setup)
                                    (list "--no-warnings"
                                          (runner setup)
                                          (::cli setup)
                                          (::root setup)
                                          (::runtime setup)
                                          "resident"
                                          (::project setup))
                                    "."))
        ((Ok process) process)
        ((Err error)
         (panic (string-append "cannot start the resident builder: "
                               (::code error))))))

    ;; One request a line, until the input ends.

    (define (write-requests (resident Process) (requests (Mailbox (Option String))))
      (→ Unit)
      (! mut tasks process)
      (match (mailbox-receive requests)
        ((Some line)
         (match (write-all resident (string->utf8 (string-append line "\n")))
           ((Ok _) (write-requests resident requests))
           ((Err _) (unit))))
        ((None)
         (close-input resident)
         (unit))))

    (define (write-all (child Process) (bytes Bytes))
      (→ (Result Unit ProcessError))
      (! tasks process)
      (if (= (vector-length bytes) 0)
          (Ok (unit))
          (match (write-input child bytes)
            ((Ok count)
             (write-all child (subvector bytes (i32->i64 count) (vector-length bytes))))
            ((Err error) (Err error)))))

    ;; Each reply line, as the message it is. `pending` holds the bytes of a
    ;; line not yet ended, newest chunk first.

    (define (read-replies (resident Process) (owner (Mailbox Message)) (pending (List Bytes)))
      (→ Unit)
      (! mut tasks process)
      (match (read-output resident (Stdout) 65536)
        ((Ok (Some bytes)) (read-replies resident owner (post-lines owner (Cons bytes pending))))
        (_ (unit))))

    ;; Posts each whole line in the chunks, and keeps what follows the last.

    (define (post-lines (owner (Mailbox Message)) (pending (List Bytes))) (→ (List Bytes)) (! mut)
      (let* ((bytes (vector-concatenate (reverse pending))) (end (vector-index-of bytes 10)))
        (match end
          ((Some at)
           (mailbox-post owner (reply-message (subvector bytes 0 at)))
           (post-lines owner (list (subvector bytes (+ at 1) (vector-length bytes)))))
          ((None) (list bytes)))))

    (define (vector-index-of (bytes Bytes) (code I32)) (→ (Option I64))
      (let loop ((index 0))
        (cond ((= index (vector-length bytes)) (None))
              ((= (u8->i32 (vector-ref bytes index)) code) (Some index))
              (else (loop (+ index 1))))))

    ;; A reply, by the members it has: a build's diagnostics, a
    ;; publication's error, or a discard's epoch alone. One that is not
    ;; JSON is the resident failing.

    (define (reply-message (line Bytes)) (→ Message)
      (match (match (utf8->string line)
               ((Ok text) (string->json text))
               ((Err _) (None)))
        ((Some json)
         (match (json-member json "epoch")
           ((Some (JsonInteger epoch)) (epoch-reply json epoch))
           (_ (Step (ResidentExited "the resident builder replied without an epoch")))))
        ((None)
         (Step (ResidentExited "the resident builder replied with something other than JSON")))))

    (define (epoch-reply (json Json) (epoch I64)) (→ Message)
      (cond ((option-some? (json-member json "diagnostics"))
             (Built epoch (json->reply json) (candidate-targets json)))
            ((option-some? (json-member json "error"))
             (Step (PublishReplied epoch (match (json-member json "error")
                                           ((Some (JsonString message)) (Some message))
                                           (_ (None))))))
            (else (Step (DiscardReplied epoch)))))

    ;; Reads what the resident writes to stderr, a panic's message, then
    ;; waits for it to exit, which the end of stderr means is near.

    (define (await-resident (resident Process) (owner (Mailbox Message)) (tail (List Bytes)))
      (→ Unit)
      (! mut tasks process)
      (match (read-output resident (Stderr) 65536)
        ((Ok (Some bytes)) (await-resident resident owner (Cons bytes tail)))
        (_
         (mailbox-post owner
                       (ResidentGone (string-append "the resident builder exited with "
                                                    (exit-text (wait-exit resident))
                                                    (stderr-text tail)))))))

    (define (exit-text (exit (Result Exit ProcessError))) (→ String)
      (match exit
        ((Ok (Exited code)) (string-append "status " (show code)))
        ((Ok (Signaled name)) name)
        ((Err error) (::code error))))

    ;; The last 4096 bytes written, trimmed, after a colon.

    (define (stderr-text (tail (List Bytes))) (→ String)
      (let* ((bytes (vector-concatenate (reverse tail)))
             (start (max 0 (- (vector-length bytes) 4096)))
             (text (match (utf8->string (subvector bytes start (vector-length bytes)))
                     ((Ok text) (trimmed text))
                     ((Err _) ""))))
        (if (string=? text "") "" (string-append ": " text))))

    (define (trimmed (text String)) (→ String)
      (let loop ((start 0) (end (string-length text)))
        (cond
         ((and (< start end) (char-whitespace? (string-ref text start))) (loop (+ start 1) end))
         ((and (< start end) (char-whitespace? (string-ref text (- end 1))))
          (loop start (- end 1)))
         (else (substring text start end)))))

    ;; ---- The resident's replies ----

    (define (json->reply (json Json)) (→ Reply)
      (Reply (match (json-object json "description")
               ((Some description) (Some (json->description description)))
               ((None) (None)))
             (match (json-object json "candidate")
               ((Some candidate) (Some (json->candidate candidate)))
               ((None) (None)))
             (map json->diagnostic (json-items json "diagnostics"))))

    (define (json->description (json Json)) (→ Description)
      (let ((builds (json-items json "builds")))
        (Description (map (lambda (build) (json-text build "entry")) builds)
                     (fold-right (lambda (build publics)
                                   (match (json-member build "public")
                                     ((Some (JsonString path)) (Cons path publics))
                                     (_ publics)))
                                 (Nil)
                                 builds)
                     (map (lambda (build) (json-text build "name"))
                          (filter (lambda (build) (string=? (json-text build "kind") "browser"))
                                  builds))
                     (map (lambda (run)
                            (RunDefinition (json-text run "name")
                                           (json-text run "build")
                                           (map json-string-value (json-items run "args"))))
                          (json-items json "runs")))))

    (define (json->candidate (json Json)) (→ Candidate)
      (Candidate (match (json-member json "description")
                   ((Some description) (json->description description))
                   ((None) (Description (Nil) (Nil) (Nil) (Nil))))
                 (map (lambda (target)
                        (Generation (json-text target "name")
                                    (json-text target "directory")
                                    (json-text target "digest")
                                    (match (json-member target "files")
                                      ((Some (JsonObject members))
                                       (map (lambda (member)
                                              (Pair (::first member)
                                                    (json-string-value (::second member))))
                                            members))
                                      (_ (Nil)))
                                    (map json-string-value (json-items target "linked"))))
                      (json-items json "targets"))
                 (json-integer json "milliseconds")))

    ;; The candidate's targets as the status shows them.

    (define (candidate-targets (json Json)) (→ Json)
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

    (define (json->diagnostic (json Json)) (→ Diagnostic)
      (Diagnostic (json-text json "message")
                  (match (json-object json "source")
                    ((Some source)
                     (Some (SourcePoint (json-text source "file")
                                        (json-integer source "line")
                                        (json-integer source "column"))))
                    ((None) (None)))))

    ;; A member that is an object, as a null one is not.

    (define (json-object (json Json) (name String)) (→ (Option Json))
      (match (json-member json name)
        ((Some (JsonObject members)) (Some (JsonObject members)))
        (_ (None))))

    (define (json-items (json Json) (name String)) (→ (List Json))
      (match (json-member json name)
        ((Some (JsonArray items)) items)
        (_ (Nil))))

    (define (json-text (json Json) (name String)) (→ String)
      (match (json-member json name)
        ((Some value) (json-string-value value))
        ((None) "")))

    (define (json-string-value (json Json)) (→ String)
      (match json
        ((JsonString text) text)
        (_ "")))

    (define (json-integer (json Json) (name String)) (→ I64)
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

    (define (new-supervisor (setup Setup)
                            (owner (Mailbox Message))
                            (inbox (Mailbox Supervision))
                            (name String))
      (→ Supervisor)
      (Supervisor setup owner inbox name (None) 0 (None) #f))

    ;; Receives, runs what is wanted, and reports. A finishing supervisor
    ;; ends once its process has.

    (define (supervise (supervisor Supervisor)) (→ Unit) (! mut tasks process)
      (let ((supervisor (reconcile-run (supervised supervisor
                                                   (mailbox-receive
                                                    (::inbox supervisor))))))
        (mailbox-post (::owner supervisor)
                      (RunChanged (::name supervisor) (supervisor-state supervisor)))
        (if (and (::finishing supervisor) (not (running? supervisor)))
            (mailbox-post (::owner supervisor) (RunStopped))
            (supervise supervisor))))

    (define (supervised (supervisor Supervisor) (message Supervision)) (→ Supervisor) (! process)
      (match message
        ((Want wanted)
         (let ((serial (+ (::serial supervisor) 1)))
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

    (define (running? (supervisor Supervisor)) (→ Bool)
      (match (::child supervisor)
        ((Some child) (not (option-some? (::exit child))))
        ((None) #f)))

    ;; A process that is not the one wanted is stopped; once none runs,
    ;; the one wanted is launched, unless it already ran and ended.

    (define (reconcile-run (supervisor Supervisor)) (→ Supervisor) (! mut tasks process)
      (match (Pair (::child supervisor) (::desired supervisor))
        ((Pair (Some child) wanted)
         (cond ((option-some? (::exit child))
                (match wanted
                  ((Some (Pair serial request))
                   (if (= serial (::serial child))
                       supervisor
                       (start-child supervisor serial request)))
                  ((None) supervisor)))
               ((and (not (::stopping child)) (not (wants? wanted (::serial child))))
                (stop-child supervisor child))
               (else supervisor)))
        ((Pair (None) (Some (Pair serial request))) (start-child supervisor serial request))
        ((Pair (None) (None)) supervisor)))

    (define (wants? (wanted (Option (Pair I64 RunRequest))) (serial I64)) (→ Bool)
      (match wanted
        ((Some (Pair wanted-serial _)) (= wanted-serial serial))
        ((None) #f)))

    ;; SIGTERM, and SIGKILL if the process has not ended 2 s later.

    (define (stop-child (supervisor Supervisor) (child Child)) (→ Supervisor) (! mut process)
      (match (::process child)
        ((Some process) (send-signal process (Terminate)) (unit))
        ((None) (unit)))
      (let ((inbox (::inbox supervisor)) (serial (::serial child)))
        (dispatch-local (once (lambda () (sleep 2000) (mailbox-post inbox (Late serial))))))
      (Supervisor-child-set supervisor (Some (Child-stopping-set child #t))))

    (define (late (supervisor Supervisor) (serial I64)) (→ Supervisor) (! process)
      (match (::child supervisor)
        ((Some child)
         (when (and (= (::serial child) serial) (not (option-some? (::exit child))))
           (match (::process child)
             ((Some process) (send-signal process (Kill)) (unit))
             ((None) (unit))))
         supervisor)
        ((None) supervisor)))

    ;; The run's program on Node, with its standard input closed, and a
    ;; task for each of its outputs and its exit.

    (define (start-child (supervisor Supervisor) (serial I64) (request RunRequest))
      (→ Supervisor)
      (! mut tasks process)
      (let ((setup (::setup supervisor)) (inbox (::inbox supervisor)))
        (match (spawn (ProcessCommand (::node setup)
                                      (append
                                       (list "--no-warnings"
                                             (runner setup)
                                             (::entry request))
                                       (::arguments request))
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

    (define (empty-bytes) (→ Bytes)
      (make-vector 0 (i32->u8 0)))

    (define (forward-output (process Process)
                            (inbox (Mailbox Supervision))
                            (serial I64)
                            (stream Stream))
      (→ Unit)
      (! mut tasks process)
      (match (read-output process stream 65536)
        ((Ok (Some bytes))
         (mailbox-post inbox (Output serial stream bytes))
         (forward-output process inbox serial stream))
        (_ (unit))))

    ;; Each output keeps its last 64 KiB.

    (define (child-output (supervisor Supervisor) (serial I64) (stream Stream) (bytes Bytes))
      (→ Supervisor)
      (match (::child supervisor)
        ((Some child)
         (if (= (::serial child) serial)
             (Supervisor-child-set supervisor
                                   (Some (match stream
                                           ((Stdout)
                                            (Child-stdout-set child
                                                              (output-tail (::stdout child)
                                                                           bytes)))
                                           ((Stderr)
                                            (Child-stderr-set child
                                                              (output-tail (::stderr child)
                                                                           bytes))))))
             supervisor))
        ((None) supervisor)))

    (define (output-tail (kept Bytes) (bytes Bytes)) (→ Bytes)
      (let* ((joined (vector-concatenate (list kept bytes))) (length (vector-length joined)))
        (subvector joined (max 0 (- length 65536)) length)))

    (define (child-ended (supervisor Supervisor) (serial I64) (exit (Result Exit ProcessError)))
      (→ Supervisor)
      (! process)
      (match (::child supervisor)
        ((Some child)
         (if (= (::serial child) serial)
             (begin
               (match (::process child)
                 ((Some process) (close-process process) (unit))
                 ((None) (unit)))
               (Supervisor-child-set supervisor (Some (Child-exit-set child (Some exit)))))
             supervisor))
        ((None) supervisor)))

    ;; The target's status: what is wanted, and the process it owns.

    (define (supervisor-state (supervisor Supervisor)) (→ protocol-Run)
      (protocol-Run (::name supervisor)
                    (match (::desired supervisor)
                      ((Some (Pair _ request)) (Some (::build request)))
                      ((None) (None)))
                    (match (::child supervisor)
                      ((Some child) (Some (child-state child)))
                      ((None) (None)))
                    #f #f))

    (define (child-state (child Child)) (→ protocol-Attempt)
      (protocol-Attempt
       (::build (::request child))
       (match (::process child)
         ((Some process) (Some (i32->i64 (::id process)))) ((None) (None)))
       (child-phase child)
       (match (::exit child)
         ((Some (Ok (Exited code))) (Some (i32->i64 code))) (_ (None)))
       (match (::exit child) ((Some (Ok (Signaled name))) name) (_ ""))
       (match (::exit child) ((Some (Err error)) (::code error)) (_ ""))
       (lossy-text (::stdout child)) (lossy-text (::stderr child))))

    (define (child-phase (child Child)) (→ String)
      (match (::exit child)
        ((Some (Err _)) "failed")
        ((Some (Ok _)) "exited")
        ((None)
         (cond ((::stopping child) "stopping")
               ((option-some? (::process child)) "running")
               (else "starting")))))

    ;; Output as text, each byte that is not UTF-8 as U+FFFD.

    (define (lossy-text (bytes Bytes)) (→ String)
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

    (define (accept-connections (setup Setup)
                                (listener Listener)
                                (owner (Mailbox Message))
                                (disk (Mailbox Scan)))
      (→ Unit)
      (! mut tasks tcp fs modes process)
      (let loop ((id 0))
        (match (accept listener)
          ((Ok connection)
           (mailbox-post owner (Connected id connection))
           (dispatch-local (once (lambda ()
                                   (serve-connection setup owner disk id connection)
                                   (mailbox-post owner (Disconnected id)))))
           (loop (+ id 1)))
          ((Err _) (unit)))))

    (define security-headers (→ (List Header))
      (list (Header "Cache-Control" "no-store")
            (Header "X-Content-Type-Options" "nosniff")
            (Header "X-Frame-Options" "DENY")))

    (define (json-response (status I32) (body Json)) (→ Response)
      (Response status
                (Cons (Header "Content-Type" "application/json") security-headers)
                (if (= status 204) (empty-bytes) (string->utf8 (json->string body)))))

    (define (refused (status I32) (message String)) (→ Response)
      (json-response status (protocol-message->json message)))

    ;; A connection's one request, by the connection's number.

    (define (serve-connection (setup Setup)
                              (owner (Mailbox Message))
                              (disk (Mailbox Scan))
                              (id I64)
                              (connection Connection))
      (→ Unit)
      (! mut tasks tcp fs modes process)
      (match (read-request connection)
        ((Ok request)
         (let ((method (::method (::head request))))
           (match (route setup owner disk id connection request)
             ((Some response) (finish-exchange connection (Some method) response))
             ((None) (unit)))))
        ((Err error) (finish-exchange connection (None) (exchange-refusal error)))))

    (define (finish-exchange (connection Connection) (method (Option String)) (response Response))
      (→ Unit)
      (! tcp tasks)
      (match (ann (respond connection 2000 method response) (Result Unit (ExchangeError Unit)))
        ((Ok _) (unit))
        ((Err _) (close-connection connection) (unit))))

    (define (exchange-refusal (error (ExchangeError Unit))) (→ Response)
      (match error
        ((ProtocolFailure (Unsupported "Transfer-Encoding"))
         (refused 411 "requests must give a Content-Length, not a Transfer-Encoding"))
        ((ProtocolFailure (HeadTooLarge)) (refused 431 "the request head is too large"))
        ((ProtocolFailure (BodyTooLarge)) (refused 413 "request exceeds 8 MiB"))
        (_ (refused 400 "malformed request"))))

    ;; The response to a request, or None for an event stream, which this
    ;; task then writes until it ends.

    (define (route (setup Setup)
                   (owner (Mailbox Message))
                   (disk (Mailbox Scan))
                   (id I64)
                   (connection Connection)
                   (request Request))
      (→ (Option Response))
      (! mut tasks tcp fs modes process)
      (let ((head (::head request)))
        (match (parse-target (::target head))
          ((Err _) (Some (refused 400 "malformed request target")))
          ((Ok target)
           (match (authorization setup head target)
             ((Some message) (Some (refused 403 message)))
             ((None) (serve-target setup owner disk id connection request target)))))))

    ;; A GET of an editor asset, the event stream, or the API.

    (define (serve-target (setup Setup)
                          (owner (Mailbox Message))
                          (disk (Mailbox Scan))
                          (id I64)
                          (connection Connection)
                          (request Request)
                          (target Target))
      (→ (Option Response))
      (! mut tasks tcp fs modes process)
      (let ((method (::method (::head request))) (path (::path target)))
        (cond ((not (string=? method "GET"))
               (Some (api setup owner disk request method path (::query target))))
              ((same-strings? path (list "manifest.webmanifest")) (Some (editor-manifest)))
              ((same-strings? path (list "api" "events"))
               (stream-events owner id connection (None))
               (None))
              (else
               (Some (if (match path ((Cons "api" _) #t) (_ #f))
                         (api setup owner disk request method path (::query target))
                         (editor-asset setup owner path)))))))

    (define (api (setup Setup)
                 (owner (Mailbox Message))
                 (disk (Mailbox Scan))
                 (request Request)
                 (method String)
                 (path (List String))
                 (query (List (Pair String String))))
      (→ Response)
      (! mut tasks fs modes process)
      (match (Pair method path)
        ((Pair "GET" (Cons "api" (Cons "project" (Nil)))) (project-listing setup disk))
        ((Pair "GET" (Cons "api" (Cons "search" (Nil))))
         (project-search setup disk (query-value query "q")))
        ((Pair "GET" (Cons "api" (Cons "file" (Nil))))
         (file-response (read-project-text (::project setup) (query-value query "path"))))
        ((Pair "GET" (Cons "api" (Cons "status" (Nil))))
         (asking owner (lambda (reply) (Status reply))))
        ((Pair "POST" (Cons "api" (Cons "build" (Nil))))
         (commanding request owner (RequestBuild)))
        ((Pair "POST" (Cons "api" (Cons "run" (Cons action (Nil)))))
         (match (run-control action (query-value query "target"))
           ((Some event) (commanding request owner event))
           ((None) (refused 404 "unknown project endpoint"))))
        ((Pair "POST" (Cons "api" (Cons "file" (Nil))))
         (create-entry-response setup disk request (query-value query "path") #f))
        ((Pair "POST" (Cons "api" (Cons "directory" (Nil))))
         (create-entry-response setup disk request (query-value query "path") #t))
        ((Pair "PUT" (Cons "api" (Cons "file" (Nil))))
         (save setup disk request (query-value query "path")))
        (_ (refused 404 "unknown project endpoint"))))

    (define (run-control (action String) (target String)) (→ (Option Event))
      (cond ((string=? action "start") (Some (StartRun target)))
            ((string=? action "stop") (Some (StopRun target)))
            ((string=? action "restart") (Some (RestartRun target)))
            (else (None))))

    (define (query-value (query (List (Pair String String))) (name String)) (→ String)
      (match (find (lambda (pair) (string=? (::first pair) name)) query)
        ((Some pair) (::second pair))
        ((None) "")))

    ;; A command takes no body; the owner answers it once the step has.

    (define (commanding (request Request) (owner (Mailbox Message)) (event Event))
      (→ Response)
      (! mut tasks)
      (if (> (vector-length (::body request)) 0)
          (refused 400 "command takes no request body")
          (asking owner (lambda (reply) (Ask event reply)))))

    (define (asking (owner (Mailbox Message)) (message (dyn (Fn (Mailbox Answer) → Message))))
      (→ Response)
      (! mut tasks)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (message reply))
        (let ((answer (mailbox-receive reply)))
          (json-response (::status answer) (::body answer)))))

    (struct ProjectEntries
      ((files (List String))
       (directories (List String))))

    ;; Both listing and search use a fresh inventory, filtered through the
    ;; same served-path boundary as file reads, then Git's visibility rules.
    ;; Ignore filtering never changes compiler inputs or explicit file access.

    (define (project-files (setup Setup) (disk (Mailbox Scan)))
      (→ (Result ProjectEntries Response))
      (! mut tasks fs process)
      (let ((reply (make-mailbox)))
        (mailbox-post disk (Listing reply))
        (match (mailbox-receive reply)
          ((Err message) (Err (refused 500 message)))
          ((Ok taken)
           (match (project-text-paths (::project setup) (inventory-files taken))
             ((Ok files)
              (visible-entries (::project setup)
                               (ProjectEntries files (project-directory-paths (::project setup)
                                                                              (inventory-directories
                                                                               taken)))))
             ((Err refusal) (Err (file-refusal refusal))))))))

    (define (visible-entries (directory String) (entries ProjectEntries))
      (→ (Result ProjectEntries Response))
      (! mut tasks process)
      (match (ignore-read-gitignore directory)
        ((Err message) (Err (refused 500 message)))
        ((Ok (None)) (Ok entries))
        ((Ok (Some snapshot))
         (let ((visible? (lambda (path) (not (ignore-ignored? snapshot path)))))
           (Ok (ProjectEntries (filter visible? (::files entries))
                               (filter visible? (::directories entries))))))))

    (define (project-listing (setup Setup) (disk (Mailbox Scan)))
      (→ Response)
      (! mut tasks fs process)
      (match (project-files setup disk)
        ((Err response) response)
        ((Ok files)
         (let ((project (::project setup)))
           (json-response 200
                          (protocol-project->json
                           (protocol-Project (base-name project) project
                                             (::files files)
                                             (::directories files))))))))

    (define (project-search (setup Setup) (disk (Mailbox Scan)) (text String))
      (→ Response)
      (! mut tasks fs process)
      (match (search-parse-query text)
        ((Err message) (refused 400 message))
        ((Ok query)
         (match (project-files setup disk)
           ((Err response) response)
           ((Ok paths)
            (json-response 200
                           (search-json
                            (search-search-project (::project setup)
                                                   (::files paths)
                                                   query))))))))

    (define (search-json (results search-Results)) (→ Json)
      (protocol-search->json
       (protocol-SearchResults
        (map (lambda (hit)
               (protocol-Hit (protocol-Point (::path hit) (::line hit)
                                             (::column hit))
                             (::revision hit) (::snippet hit)))
             (::hits results))
        (::skipped results) (::limited results))))

    (define (file-response (result (Result ProjectText FileRefusal))) (→ Response)
      (match result
        ((Ok text)
         (json-response 200 (protocol-file->json (protocol-Snapshot (::text text)
                                                                    (::revision text)))))
        ((Err refusal) (file-refusal refusal))))

    (define (file-refusal (refusal FileRefusal)) (→ Response)
      (match refusal
        ((ChangedOnDisk) (refused 409 "the file changed on disk; reload it before saving"))
        ((NotServed message) (refused 400 message))
        ((DiskFailed (NotFound)) (refused 404 "no such file or directory"))
        ((DiskFailed (AlreadyExists))
         (refused 409 "a file or directory already exists at that path"))
        ((DiskFailed (PermissionDenied)) (refused 403 "permission denied"))
        ((DiskFailed error) (refused 500 (show error)))))

    (define (create-entry-response (setup Setup)
                                   (disk (Mailbox Scan))
                                   (request Request)
                                   (path String)
                                   (directory Bool))
      (→ Response)
      (! mut fs)
      (if (> (vector-length (::body request)) 0)
          (refused 400 "creation takes no request body")
          (match (if directory (create-project-directory (::project setup) path)
                     (create-project-file (::project setup) path))
            ((Err refusal) (file-refusal refusal))
            ((Ok _)
             (mailbox-post disk (Prompted))
             (json-response 201 (JsonObject (list (Pair "path" (JsonString path)))))))))

    ;; A save names one quoted revision and sends UTF-8 text/plain. Once it
    ;; is on disk, the disk task scans, so the build sees it within the
    ;; debounce rather than the next second.

    (define (save (setup Setup) (disk (Mailbox Scan)) (request Request) (path String))
      (→ Response)
      (! mut fs modes)
      (let ((head (::head request)))
        (match (expected-revision head)
          ((None) (refused 400 "save requires one quoted If-Match revision"))
          ((Some revision)
           (if (not (plain-text? head))
               (refused 415 "save requires UTF-8 text/plain")
               (match (utf8->string (::body request))
                 ((Err _) (refused 400 "save requires valid UTF-8"))
                 ((Ok text)
                  (let ((response (file-response
                                   (save-project-text (::project setup) path revision text))))
                    (mailbox-post disk (Prompted))
                    response))))))))

    ;; One strong opaque tag: lists, wildcards and weak tags are not this API.

    (define (expected-revision (head RequestHead)) (→ (Option String))
      (match (header-values (::headers head) "if-match")
        ((Cons value (Nil))
         (let ((length (string-length value)))
           (if (and (>= length 3)
                    (char=? (string-ref value 0) #\")
                    (char=? (string-ref value (- length 1)) #\")
                    (every? tag-char? (string->list (substring value 1 (- length 1)))))
               (Some (substring value 1 (- length 1)))
               (None))))
        (_ (None))))

    (define (tag-char? (char Char)) (→ Bool)
      (let ((code (char->i32 char)))
        (or (= code 33) (and (>= code 35) (<= code 91)) (and (>= code 93) (<= code 126)))))

    (define (plain-text? (head RequestHead)) (→ Bool)
      (match (header-values (::headers head) "content-type")
        ((Cons value (Nil))
         (let ((type (list->string (filter (lambda (char) (not (char-whitespace? char)))
                                           (string->list (string-downcase value))))))
           (or (string=? type "text/plain") (string=? type "text/plain;charset=utf-8"))))
        (_ #f)))

    ;; The host and origin must be this service's, so another page cannot
    ;; reach it; a fetch from another site is refused, except a navigation
    ;; to the editor itself; and a change must come from the project's own
    ;; page.

    (define (authorization (setup Setup) (head RequestHead) (target Target)) (→ (Option String))
      (let ((headers (::headers head)) (origin (origin setup)))
        (cond ((not (same-strings? (header-values headers "host")
                                   (list (substring origin 7 (string-length origin)))))
               (Some "unexpected host"))
              ((not (or (null? (header-values headers "origin"))
                        (same-strings? (header-values headers "origin") (list origin))))
               (Some "unexpected origin"))
              ((and (not (navigation? head target)) (cross-site? headers))
               (Some "unexpected fetch context"))
              ((and (not (string=? (::method head) "GET"))
                    (not (same-strings? (header-values headers "origin") (list origin))))
               (Some "mutation requires the project origin"))
              (else (None)))))

    ;; The target `/`, which parses as no segment or one empty one.

    (define (root-path? (path (List String))) (→ Bool)
      (match path
        ((Nil) #t)
        ((Cons "" (Nil)) #t)
        (_ #f)))

    (define (navigation? (head RequestHead) (target Target)) (→ Bool)
      (let ((headers (::headers head)))
        (and (string=? (::method head) "GET")
             (root-path? (::path target))
             (same-strings? (header-values headers "sec-fetch-mode") (list "navigate"))
             (same-strings? (header-values headers "sec-fetch-dest") (list "document")))))

    (define (cross-site? (headers (List Header))) (→ Bool)
      (match (header-values headers "sec-fetch-site")
        ((Cons site _) (not (or (string=? site "same-origin") (string=? site "none"))))
        ((Nil) #f)))

    (define (same-strings? (left (List String)) (right (List String))) (→ Bool)
      (and (= (length left) (length right))
           (every? (lambda (pair) (string=? (::first pair) (::second pair)))
                   (zip left right))))

    ;; ---- The applications' origin ----

    ;; One handler task for each connection, numbered apart from the
    ;; editor's, so the owner tracks both alike and shutdown waits for both.

    (define (accept-applications (setup Setup) (listener Listener) (owner (Mailbox Message)))
      (→ Unit)
      (! mut tasks tcp fs)
      (let loop ((id 1099511627776))
        (match (accept listener)
          ((Ok connection)
           (mailbox-post owner (Connected id connection))
           (dispatch-local (once (lambda ()
                                   (serve-application setup listener owner id connection)
                                   (mailbox-post owner (Disconnected id)))))
           (loop (+ id 1)))
          ((Err _) (unit)))))

    (define (serve-application (setup Setup)
                               (listener Listener)
                               (owner (Mailbox Message))
                               (id I64)
                               (connection Connection))
      (→ Unit)
      (! mut tasks tcp fs)
      (match (read-request connection)
        ((Ok request)
         (let ((head (::head request)))
           (match (application-response setup listener owner id connection head)
             ((Some response)
              (finish-exchange connection (Some (::method head)) response))
             ((None) (unit)))))
        ((Err error) (finish-exchange connection (None) (exchange-refusal error)))))

    ;; Only reads, and only for this origin's own host, so a page of another
    ;; site that rebinds a name to this address reads nothing. None for a
    ;; page's event stream, which this task then writes until it ends.

    (define (application-response (setup Setup)
                                  (listener Listener)
                                  (owner (Mailbox Message))
                                  (id I64)
                                  (connection Connection)
                                  (head RequestHead))
      (→ (Option Response))
      (! mut tasks tcp fs)
      (let ((method (::method head)))
        (cond ((not (same-strings? (header-values (::headers head) "host")
                                   (list (listener-host listener))))
               (Some (refused 403 "unexpected host")))
              ((not (or (string=? method "GET") (string=? method "HEAD")))
               (Some (refused 405 "the applications' origin only serves files")))
              (else
               (match (parse-target (::target head))
                 ((Ok target)
                  (match (::path target)
                    ((Cons name (Cons ".snail" (Cons "events" (Nil))))
                     (stream-events owner id connection (Some name))
                     (None))
                    (path (Some (application-file setup owner path)))))
                 ((Err _) (Some (refused 400 "malformed request target"))))))))

    ;; `/` lists the browser targets, and /NAME/ serves one's builds.

    (define (application-file (setup Setup) (owner (Mailbox Message)) (path (List String)))
      (→ Response)
      (! mut tasks fs)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (Applications reply))
        (let ((applications (mailbox-receive reply)))
          (match (if (root-path? path) (Nil) path)
            ((Nil) (application-index applications))
            ((Cons name rest)
             (match (find (lambda (application) (string=? (::name application) name))
                          applications)
               ((Some application)
                (bundle-response (string-append "/" name "/")
                                 (Reloading (string-append (::root setup) "/host/browser")
                                            (::client setup))
                                 (::builds application)
                                 rest))
               ((None) (refused 404 (string-append "no browser target " name)))))))))

    (define (application-index (applications (List Application))) (→ Response)
      (Response 200
                (Cons (Header "Content-Type" "text/html; charset=utf-8") security-headers)
                (string->utf8
                 (string-append
                  "<!doctype html>\n<meta charset=\"utf-8\">\n<title>Browser targets</title>\n"
                  (if (null? applications)
                      "<p>No browser target is built yet.</p>\n"
                      (string-concatenate
                       (map (lambda (application)
                              (let ((name (html-text (::name application))))
                                (string-append "<p><a href=\"/" name "/\">" name "</a></p>\n")))
                            applications)))))))

    (define (html-text (text String)) (→ String)
      (string-concatenate
       (map (lambda (char)
              (cond ((char=? char #\<) "&lt;")
                    ((char=? char #\>) "&gt;")
                    ((char=? char #\&) "&amp;")
                    ((char=? char #\") "&quot;")
                    (else (make-string 1 char))))
            (string->list text))))

    ;; ---- The editor's builds ----

    ;; The IDE is a normal browser target. Keep complete successful generations
    ;; for this service's lifetime; no client leases or partially updated assets.
    (struct EditorBundle
      ((id String)
       (directory String)))

    (define (editor-bundle (setup Setup)) (→ (Result EditorBundle String)) (! fs)
      (match (read-symbolic-link (::editor setup))
        ((Ok name)
         (Ok (EditorBundle name (string-append (::root setup) "/host/ide/build/" name))))
        ((Err error) (Err (string-append "cannot locate IDE build: " (show error))))))

    (define (editor-base (bundle EditorBundle)) (→ String)
      (string-append "/.snail/ide/" (::id bundle) "/"))

    (define (touched-editor (host Host) (event Event)) (→ Host) (! mut tasks process fs tcp)
      (match (::stopping host)
        ((Some _) host)
        ((None) (editor-change host event))))

    (define (editor-change (host Host) (event Event)) (→ Host) (! mut tasks process fs tcp)
      (match event
        ((Touched paths)
         (if (any? (lambda (path)
                     (any? (lambda (part)
                             (starts-with? path
                                           (string-append (::root (::setup host)) part)))
                           (list "/src/" "/host/ide/" "/host/browser/"))) paths)
             (match (::editor-process host)
               ((Some _) (Host-editor-again-set host #t))
               ((None) (start-editor host)))
             host))
        (_ host)))

    (define (start-editor (host Host)) (→ Host) (! mut tasks process fs tcp)
      (let ((setup (::setup host)))
        (match (spawn (ProcessCommand (::node setup)
                                      (list "--no-warnings" (runner setup) (::cli setup)
                                            (::root setup) (::runtime setup)
                                            "build" "--release"
                                            (string-append (::root setup) "/host/ide") "ide")
                                      (::root setup)))
          ((Err error) (broadcast-changes
                        (Host-editor-problem-set host (::code error))))
          ((Ok child)
           (close-input child)
           (dispatch-local (once (lambda () (await-editor setup (::owner host) child))))
           (Host-editor-process-set (Host-editor-again-set host #f) (Some child))))))

    ;; Drain both pipes while the compiler runs, so neither can block it.
    ;; The owner remains responsive and closes the child during shutdown.

    (define (await-editor (setup Setup) (owner (Mailbox Message)) (child Process))
      (→ Unit)
      (! mut tasks process fs)
      (let ((errors (make-mailbox)))
        (dispatch-local (once (lambda () (mailbox-post errors (editor-output child (Stderr) "")))))
        (editor-output child (Stdout) "")
        (let ((exit (wait-exit child)) (error (mailbox-receive errors)))
          (close-process child)
          (mailbox-post owner
                        (EditorBuilt (match exit
                                       ((Ok (Exited 0)) (editor-bundle setup))
                                       (_ (Err
                                           (if (string=? error "") "IDE build failed" error)))))))))

    (define (editor-output (child Process) (stream Stream) (kept String))
      (→ String)
      (! tasks process)
      (match (read-output child stream 65536)
        ((Ok (Some bytes))
         (let* ((text (string-append kept (lossy-text bytes))) (size (string-length text)))
           (editor-output child stream (substring text (max 0 (- size 4096)) size))))
        (_ kept)))

    (define (editor-built (host Host) (result (Result EditorBundle String)))
      (→ Host)
      (! mut tasks process fs tcp)
      (match (::stopping host)
        ((Some _) (stopped-one host))
        ((None)
         (let ((host (Host-editor-process-set host (None))))
           (if (::editor-again host) (start-editor host)
               (broadcast-changes
                (match result
                  ((Ok bundle)
                   (Host-editor-problem-set
                    (Host-editors-set host (Cons bundle (::editors host)))
                    ""))
                  ((Err message) (Host-editor-problem-set host message)))))))))

    ;; ---- The editor's assets ----

    ;; Page-relative references are pinned to one complete generation. The
    ;; manifest remains at the stable root, and recovery is keyed by project.

    (define (editor-manifest) (→ Response)
      (Response 200
                (Cons (Header "Content-Type" "application/manifest+json") security-headers)
                (string->utf8 (json->string (web-app-manifest "Snail IDE")))))

    (define (editor-asset (setup Setup) (owner (Mailbox Message)) (path (List String)))
      (→ Response)
      (! mut tasks fs)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (EditorAssets reply))
        (let* ((bundles (mailbox-receive reply)) (latest (list-ref bundles 0)))
          (cond ((root-path? path) (editor-page setup latest))
                (else
                 (match path
                   ((Cons ".snail" (Cons "ide" (Cons id rest)))
                    (match (find (lambda (bundle) (string=? (::id bundle) id)) bundles)
                      ((Some bundle) (editor-file bundle rest))
                      ((None) (refused 404 "no such IDE generation"))))
                   ;; Stable icon links belong to the manifest. Other assets
                   ;; are named by generation, including program.wasm.
                   ((Cons name (Nil))
                    (if (member? name
                                 (list "snail-icon.svg" "snail-icon-192.png" "snail-icon-512.png"))
                        (editor-file latest path) (refused 404 "no such editor asset")))
                   (_ (refused 404 "no such editor asset"))))))))

    (define (editor-page (setup Setup) (bundle EditorBundle)) (→ Response) (! fs)
      (let ((text (stable-web-app
                   (read-file (string-append (::directory bundle) "/index.html")) "/")))
        (Response 200 (Cons (Header "Content-Type" "text/html; charset=utf-8") editor-headers)
                  (string->utf8
                   (insert-metadata text (list (PageBase (editor-base bundle))
                                               (PageMeta "snail-workspace"
                                                         (::project setup))))))))

    (define (editor-file (bundle EditorBundle) (path (List String))) (→ Response) (! fs)
      (let ((response (bundle-file (::directory bundle) path)))
        (Response (::status response)
                  (append (::headers response) editor-headers) (::body response))))

    (define editor-headers (→ (List Header))
      (Cons (Header "Content-Security-Policy"
                    "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'self'; worker-src 'none'")
            security-headers))

    ;; ---- Writing an event stream ----

    ;; Joins the owner's streams, then writes each frame it sends until it
    ;; sends none, or a write fails. The handler's end tells the owner the
    ;; stream has gone.

    (define (stream-events (owner (Mailbox Message))
                           (id I64)
                           (connection Connection)
                           (watching (Option String)))
      (→ Unit)
      (! mut tasks tcp)
      (let ((frames (make-mailbox)) (reply (make-mailbox)))
        (mailbox-post owner (Joined id watching connection frames reply))
        (let ((answer (mailbox-receive reply)))
          (if (= (::status answer) 200)
              (match (encode-stream-head 200
                                         (Cons (Header "Content-Type" "text/event-stream")
                                               security-headers))
                ((Ok head) (when (sent? connection head) (write-frames owner id connection frames)))
                ((Err _) (unit)))
              (finish-exchange connection
                               (Some "GET")
                               (json-response (::status answer) (::body answer)))))))

    (define (write-frames (owner (Mailbox Message))
                          (id I64)
                          (connection Connection)
                          (frames (Mailbox (Option Bytes))))
      (→ Unit)
      (! mut tasks tcp)
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

    (define (sent? (connection Connection) (bytes Bytes)) (→ Bool) (! tasks tcp)
      (if (= (vector-length bytes) 0)
          #t
          (match (write connection bytes)
            ((Ok count)
             (and (> count 0)
                  (sent? connection (subvector bytes (i32->i64 count) (vector-length bytes)))))
            ((Err _) #f))))))
