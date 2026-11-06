(define-library (notes application)
  (export NotesApplication)
  (import
   (snail core base)
   (snail shell task)
   (snail shell dom)
   (snail shell fetch)
   (snail shell ui)
   (snail shell ui page)
   (snail shell wire))
  (begin
    (struct Note
      ((id I64)
       (text String))
      (deriving Serialize Deserialize))

    (struct Notes
      ((notes (List Note))
       (draft String)
       (next I64)
       (added I64)
       (server Server)))

    ;; What the server said: its greeting, its answer to the shared notes, and
    ;; the events heard from it.
    (struct Server
      ((greeting String)
       (shared String)
       (heard (List String))))

    (: no-server Server)
    (define no-server (Server "" "" (Nil)))

    (struct Save
      ((notes (List Note))
       (next I64))
      (deriving Serialize Deserialize))

    (enum Message
      (Typed ((text String)))
      (Pressed ((key String) (at I32)))
      (Add)
      (Bullet)
      (Clear)
      (Cleared)
      (Added ((count I64)))
      (Remove ((id I64)))
      (Load)
      (Loaded ((text String)))
      (Share)
      (Shared ((text String)))
      (Listen)
      (Heard ((stream Stream) (text String)))
      (Ended))

    (: start (-> I32 Notes))
    (define (start seed)
      (Notes (Nil) "" 0 0 no-server))

    (: update (-> Notes Message (Pair Notes (List (Command Message)))))
    (define (update model message)
      (match message
        ((Typed text) (Pair (Notes-draft-set model text) (Nil)))
        ((Pressed key at) (pressed model key at))
        ((Add) (added model))
        ((Bullet) (Pair model (list (once bullet))))
        ((Clear) (Pair model (list (once clear))))
        ((Cleared) (Pair (Notes-notes-set model (Nil)) (Nil)))
        ((Added count) (Pair (Notes-added-set model count) (Nil)))
        ((Remove id)
         (Pair (Notes-notes-set model
                                (filter (lambda (note) (not (= (::id note) id)))
                                        (::notes model)))
               (Nil)))
        ((Load) (Pair model (list (once load))))
        ((Loaded text)
         (Pair (Notes-server-set model (Server-greeting-set (::server model) text)) (Nil)))
        ((Share)
         (Pair model (list (once (lambda () (share (::notes model) (::next model)))))))
        ((Shared text)
         (Pair (Notes-server-set model (Server-shared-set (::server model) text)) (Nil)))
        ((Listen)
         (Pair model
               (list
                (once (lambda () (hear (stream-open "/api/events" (list "message" "note"))))))))
        ((Heard stream text) (Pair (heard model text) (list (once (lambda () (hear stream))))))
        ((Ended) (Pair (heard model "ended") (Nil)))))

    (: pressed (-> Notes String I32 (Pair Notes (List (Command Message)))))
    (define (pressed model key at)
      (cond ((string=? key "Enter") (update model (Add)))
            ((string=? key "Tab")
             (Pair model
                   (list (once (lambda ()
                                 (with-draft (lambda (node) (insert-text node at at "  ") (unit)))
                                 (Pressed "" 0))))))
            (else (Pair model (Nil)))))

    (: clear (-> Message ! dom))
    (define (clear)
      (if (confirm "Remove every note?") (Cleared) (Pressed "" 0)))

    (: heard (-> Notes String Notes))
    (define (heard model text)
      (let ((server (::server model)))
        (Notes-server-set model
                          (Server-heard-set server (append (::heard server) (list text))))))

    ;; ---- The server ----

    (: load (-> Message ! fetch tasks))
    (define (load)
      (Loaded (replied (request "GET" "/api/greeting" (Nil) ""))))

    ;; The notes, a line each, sent with the next id the server should expect.
    (: share (-> (List Note) I64 Message ! fetch tasks))
    (define (share notes next)
      (Shared (replied (request "POST"
                                "/api/notes"
                                (list (Header "Content-Type" "text/plain")
                                      (Header "If-Match" (show next)))
                                (string-join (map ::text notes) (make-string 1 #\newline))))))

    (: replied (-> (Result Reply String) String))
    (define (replied result)
      (match result
        ((Ok reply) (string-append (show (::status reply)) " " (::body reply)))
        ((Err why) (string-append "failed: " why))))

    ;; The next event, which the update that hears it waits past.
    (: hear (-> Stream Message ! fetch tasks))
    (define (hear stream)
      (match (stream-next stream)
        ((Some event)
         (Heard stream (string-append (::kind event) ":" (::data event))))
        ((None) (Ended))))

    ;; A note from the draft, unless it is empty, and the command that counts
    ;; it once it has yielded.
    (: added (-> Notes (Pair Notes (List (Command Message)))))
    (define (added model)
      (if (string=? (::draft model) "")
          (Pair model (Nil))
          (let ((count (+ (::added model) 1)))
            (Pair
             (Notes
              (append (::notes model) (list (Note (::next model) (::draft model))))
              ""
              (+ (::next model) 1)
              (::added model)
              (::server model))
             (list (once (lambda ()
                           (yield)
                           (with-draft focus-node)
                           (Added count))))))))

    ;; Does `act` to the draft field, if the view still shows it.
    (: with-draft (-> (-> Node Unit ! dom) Unit ! dom))
    (define (with-draft act)
      (match (element-by-id "draft")
        ((Some node) (act node))
        ((None) (unit))))

    ;; The field's input event, which inserting fires, carries the new draft;
    ;; the command's own answer leaves it as it is.
    (: bullet (-> Message ! dom))
    (define (bullet)
      (with-draft (lambda (node) (insert-text node 0 0 "- ") (unit)))
      (Pressed "" 0))

    (: view (-> Notes (Html Message)))
    (define (view model)
      (Element "main"
               (Nil)
               (list (Element "input"
                              (list (Attr "id" "draft")
                                    (Attr "placeholder" "A note")
                                    (StringProperty "value" (::draft model))
                                    (On "input"
                                        (list (Value))
                                        (Allow)
                                        (lambda (event) (Typed (::value event))))
                                    (On "keydown"
                                        (list (Key) (Selection))
                                        (Chords (list (Chord "Enter" 0) (Chord "Tab" 0)))
                                        (lambda (event)
                                          (Pressed (::key event)
                                                   (::selection-start event)))))
                              (Nil))
                     (Element "button"
                              (list (Attr "id" "add")
                                    (On "click" (Nil) (Allow) (lambda (event) (Add))))
                              (list (Text "Add")))
                     (Element "button"
                              (list (Attr "id" "bullet")
                                    (On "click" (Nil) (Allow) (lambda (event) (Bullet))))
                              (list (Text "Bullet")))
                     (Element "ul" (list (Attr "id" "notes")) (map note-view (::notes model)))
                     (Element "div"
                              (Nil)
                              (list (button "share" "Share" (Share))
                                    (button "listen" "Listen" (Listen))
                                    (button "clear" "Clear" (Clear))))
                     (Element "p"
                              (list (Attr "id" "greeting"))
                              (list (Text (::greeting (::server model)))))
                     (Element "p"
                              (list (Attr "id" "shared"))
                              (list (Text (::shared (::server model)))))
                     (Element "p"
                              (list (Attr "id" "heard"))
                              (list (Text (string-join (::heard (::server model)) ","))))
                     (Element "p"
                              (list (Attr "id" "added"))
                              (list (Text (string-append (show (::added model)) " added")))))))

    (: button (-> String String Message (Html Message)))
    (define (button id label message)
      (Element "button"
               (list (Attr "id" id) (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (: note-view (-> Note (Html Message)))
    (define (note-view note)
      (Element "li"
               (list (Keyed (show (::id note))))
               (list (Text (::text note))
                     (Element "button"
                              (list (Attr "id" (string-append "remove-" (show (::id note))))
                                    (On "click"
                                        (Nil)
                                        (Allow)
                                        (lambda (event) (Remove (::id note)))))
                              (list (Text "Remove"))))))

    (: save (-> Notes Save))
    (define (save model)
      (Save (::notes model) (::next model)))

    (: restore (-> Save Notes))
    (define (restore saved)
      (Notes (::notes saved) "" (::next saved) 0 no-server))

    (: window (-> Notes (List (Attribute Message))))
    (define (window model)
      (list (On "keydown"
                (Nil)
                (Chords (list (Chord "Escape" 0)))
                (lambda (event) (Typed "")))))

    (type NotesApplication (InterfaceApplication Notes))

    (define-page-state Notes)

    (instance (Interface Notes)
      (type Message Message)
      (define (interface-initialize seed) (start seed))
      (define (interface-update model message) (update model message))
      (define (interface-view model) (view model))
      (define (interface-window model) (window model))
      (define (interface-messages model) (list (Load)))
      (define (interface-save model) (serialize (save model)))
      (define (interface-restore bytes) (restore (deserialize bytes))))))
