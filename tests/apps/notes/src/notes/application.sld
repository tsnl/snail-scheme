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
    (record Note
      ((id I64)
       (text String))
      (deriving Serialize Deserialize))

    (record Notes
      ((notes (List Note))
       (draft String)
       (next I64)
       (added I64)
       (server Server)))

    ;; What the server said: its greeting, its answer to the shared notes, and
    ;; the events heard from it.
    (record Server
      ((greeting String)
       (shared String)
       (heard (List String))))

    (define (no-server) (→ Server) (new Server (greeting "") (shared "") (heard (Nil))))

    (record Save
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

    (define (start (seed I32)) (→ Notes)
      (new Notes (notes (Nil)) (draft "") (next 0) (added 0) (server (no-server))))

    (define (update (model Notes) (message Message)) (→ (Pair Notes (List (Command Message))))
      (match message
        ((Typed text) (new Pair (first (Notes-draft-set model text)) (second (Nil))))
        ((Pressed key at) (pressed model key at))
        ((Add) (added model))
        ((Bullet) (new Pair (first model) (second (list bullet))))
        ((Clear) (new Pair (first model) (second (list clear))))
        ((Cleared) (new Pair (first (Notes-notes-set model (Nil))) (second (Nil))))
        ((Added count) (new Pair (first (Notes-added-set model count)) (second (Nil))))
        ((Remove id)
         (new Pair (first (Notes-notes-set model
                                           (filter (lambda (note) (not (= (● note id) id)))
                                                   (● model notes))))
              (second (Nil))))
        ((Load) (new Pair (first model) (second (list load))))
        ((Loaded text)
         (new Pair
           (first (Notes-server-set model (Server-greeting-set (● model server) text)))
           (second (Nil))))
        ((Share)
         (new Pair
           (first model)
           (second (list (lambda () (share (● model notes) (● model next)))))))
        ((Shared text)
         (new Pair
           (first (Notes-server-set model (Server-shared-set (● model server) text)))
           (second (Nil))))
        ((Listen)
         (new Pair (first model)
              (second (list
                       (lambda () (hear (stream-open "/api/events" (list "message" "note"))))))))
        ((Heard stream text)
         (new Pair (first (heard model text)) (second (list (lambda () (hear stream))))))
        ((Ended) (new Pair (first (heard model "ended")) (second (Nil))))))

    (define (pressed (model Notes) (key String) (at I32)) (→ (Pair Notes (List (Command Message))))
      (cond ((string=? key "Enter") (update model (Add)))
            ((string=? key "Tab")
             (new Pair (first model)
                  (second (list (lambda ()
                                  (with-draft
                                   (lambda (node) (insert-text node at at "  ") (unit)))
                                  (Pressed "" 0))))))
            (else (new Pair (first model) (second (Nil))))))

    (define (clear) (→ Message) (! dom)
      (if (confirm "Remove every note?") (Cleared) (Pressed "" 0)))

    (define (heard (model Notes) (text String)) (→ Notes)
      (let ((server (● model server)))
        (Notes-server-set model
                          (Server-heard-set server (append (● server heard) (list text))))))

    ;; ---- The server ----

    (define (load) (→ Message) (! fetch tasks)
      (Loaded (replied (request "GET" "/api/greeting" (Nil) ""))))

    ;; The notes, a line each, sent with the next id the server should expect.
    (define (share (notes (List Note)) (next I64)) (→ Message) (! fetch tasks)
      (Shared (replied (request "POST"
                                "/api/notes"
                                (list (new Header (name "Content-Type") (value "text/plain"))
                                      (new Header (name "If-Match") (value (show next))))
                                (string-join (map (lambda (record) (● record text)) notes)
                                             (make-string 1 #\newline))))))

    (define (replied (result (Result Reply String))) (→ String)
      (match result
        ((Ok reply) (string-append (show (● reply status)) " " (● reply body)))
        ((Err why) (string-append "failed: " why))))

    ;; The next event, which the update that hears it waits past.
    (define (hear (stream Stream)) (→ Message) (! fetch tasks)
      (match (stream-next stream)
        ((Some event)
         (Heard stream (string-append (● event kind) ":" (● event data))))
        ((None) (Ended))))

    ;; A note from the draft, unless it is empty, and the command that counts
    ;; it once it has yielded.
    (define (added (model Notes)) (→ (Pair Notes (List (Command Message))))
      (if (string=? (● model draft) "")
          (new Pair (first model) (second (Nil)))
          (let ((count (+ (● model added) 1)))
            (new Pair
              (first (new Notes
                       (notes (append (● model notes)
                                      (list (new Note (id (● model next)) (text (● model draft))))))
                       (draft "")
                       (next (+ (● model next) 1))
                       (added (● model added))
                       (server (● model server))))
              (second (list (lambda ()
                              (yield)
                              (with-draft focus-node)
                              (Added count))))))))

    ;; Does `act` to the draft field, if the view still shows it.
    (define (with-draft (act (Fn Node → Unit ! dom))) (→ Unit) (! dom)
      (match (element-by-id "draft")
        ((Some node) (act node))
        ((None) (unit))))

    ;; The field's input event, which inserting fires, carries the new draft;
    ;; the command's own answer leaves it as it is.
    (define (bullet) (→ Message) (! dom)
      (with-draft (lambda (node) (insert-text node 0 0 "- ") (unit)))
      (Pressed "" 0))

    (define (view (model Notes)) (→ (Html Message))
      (Element "main"
               (Nil)
               (list (Element "input"
                              (list (Attr "id" "draft")
                                    (Attr "placeholder" "A note")
                                    (StringProperty "value" (● model draft))
                                    (On "input"
                                        (list (Value))
                                        (Allow)
                                        (lambda (event) (Typed (● event value))))
                                    (On "keydown"
                                        (list (Key) (Selection))
                                        (Chords (list (new Chord (key "Enter") (modifiers 0))
                                                      (new Chord (key "Tab") (modifiers 0))))
                                        (lambda (event)
                                          (Pressed (● event key)
                                                   (● event selection-start)))))
                              (Nil))
                     (Element "button"
                              (list (Attr "id" "add")
                                    (On "click" (Nil) (Allow) (lambda (event) (Add))))
                              (list (Text "Add")))
                     (Element "button"
                              (list (Attr "id" "bullet")
                                    (On "click" (Nil) (Allow) (lambda (event) (Bullet))))
                              (list (Text "Bullet")))
                     (Element "ul" (list (Attr "id" "notes")) (map note-view (● model notes)))
                     (Element "div"
                              (Nil)
                              (list (button "share" "Share" (Share))
                                    (button "listen" "Listen" (Listen))
                                    (button "clear" "Clear" (Clear))))
                     (Element "p"
                              (list (Attr "id" "greeting"))
                              (list (Text (● (● model server) greeting))))
                     (Element "p"
                              (list (Attr "id" "shared"))
                              (list (Text (● (● model server) shared))))
                     (Element "p"
                              (list (Attr "id" "heard"))
                              (list (Text (string-join (● (● model server) heard) ","))))
                     (Element "p"
                              (list (Attr "id" "added"))
                              (list (Text (string-append (show (● model added)) " added")))))))

    (define (button (id String) (label String) (message Message)) (→ (Html Message))
      (Element "button"
               (list (Attr "id" id) (On "click" (Nil) (Allow) (lambda (event) message)))
               (list (Text label))))

    (define (note-view (note Note)) (→ (Html Message))
      (Element "li"
               (list (Keyed (show (● note id))))
               (list (Text (● note text))
                     (Element "button"
                              (list (Attr "id" (string-append "remove-" (show (● note id))))
                                    (On "click"
                                        (Nil)
                                        (Allow)
                                        (lambda (event) (Remove (● note id)))))
                              (list (Text "Remove"))))))

    (define (save (model Notes)) (→ Save)
      (new Save (notes (● model notes)) (next (● model next))))

    (define (restore (saved Save)) (→ Notes)
      (new Notes
        (notes (● saved notes))
        (draft "")
        (next (● saved next))
        (added 0)
        (server (no-server))))

    (define (window (model Notes)) (→ (List (Attribute Message)))
      (list (On "keydown"
                (Nil)
                (Chords (list (new Chord (key "Escape") (modifiers 0))))
                (lambda (event) (Typed "")))))

    (type NotesApplication (InterfaceApplication Notes))

    (define-page-state Notes)

    (instance (Interface Notes)
      (type Message Message)
      (define (interface-initialize (seed I32)) (→ Notes)
        (start seed))
      (define (interface-update (model Notes) (message Message))
        (→ (Pair Notes (List (Command Message))))
        (update model message))
      (define (interface-view (model Notes)) (→ (Html Message))
        (view model))
      (define (interface-window (model Notes)) (→ (List (Attribute Message)))
        (window model))
      (define (interface-messages (model Notes)) (→ (List Message))
        (list (Load)))
      (define (interface-save (model Notes)) (→ Bytes)
        (serialize (save model)))
      (define (interface-restore (bytes Bytes)) (→ Notes)
        (restore (deserialize bytes))))))
