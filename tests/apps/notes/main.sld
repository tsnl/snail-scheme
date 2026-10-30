;; The smallest document interface: notes typed into a field and added to a
;; keyed list, by the button or by Enter, each with a button that removes
;; it. Adding also starts a command that answers once it has yielded, so
;; the count of notes added arrives by a wake, and focuses the field again.
;; A bullet button's command inserts "- " at the start of the field as
;; typing would, so the field's input event brings the draft up to date. The browser test
;; (tests/browser/ui.mjs) drives it, and checks that the save a hidden page
;; stores brings the notes back on a fresh load.
(import
 (snail core base)
 (snail shell task)
 (snail shell dom)
 (snail shell ui)
 (snail shell ui page))

(struct Note
  ((id I64)
   (text String))
  (deriving Serialize Deserialize))

(struct Notes
  ((notes (List Note))
   (draft String)
   (next I64)
   (added I64)))

(struct Save
  ((notes (List Note))
   (next I64))
  (deriving Serialize Deserialize))

(enum Message
  (Typed ((text String)))
  (Pressed ((key String)))
  (Add)
  (Bullet)
  (Added ((count I64)))
  (Remove ((id I64))))

(: start (-> I32 Notes))
(define (start seed)
  (Notes (Nil) "" 0 0))

(: update (-> Notes Message (Pair Notes (List (Command Message)))))
(define (update model message)
  (match message
    ((Typed text) (Pair (Notes-draft-set model text) (Nil)))
    ((Pressed key) (if (string=? key "Enter") (update model (Add)) (Pair model (Nil))))
    ((Add) (added model))
    ((Bullet) (Pair model (list (once bullet))))
    ((Added count) (Pair (Notes-added-set model count) (Nil)))
    ((Remove id)
     (Pair (Notes-notes-set model
                            (filter (lambda (note) (not (= (Note-id note) id)))
                                    (Notes-notes model)))
           (Nil)))))

;; A note from the draft, unless it is empty, and the command that counts
;; it once it has yielded.
(: added (-> Notes (Pair Notes (List (Command Message)))))
(define (added model)
  (if (string=? (Notes-draft model) "")
      (Pair model (Nil))
      (let ((count (+ (Notes-added model) 1)))
        (Pair
         (Notes (append (Notes-notes model) (list (Note (Notes-next model) (Notes-draft model))))
                ""
                (+ (Notes-next model) 1)
                (Notes-added model))
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
  (with-draft (lambda (node) (insert-text node 0 0 "- ")))
  (Pressed ""))

(: view (-> Notes (Html Message)))
(define (view model)
  (Element "main"
           (Nil)
           (list (Element "input"
                          (list (Attr "id" "draft")
                                (Attr "placeholder" "A note")
                                (StringProperty "value" (Notes-draft model))
                                (On "input"
                                    (list (Value))
                                    (Allow)
                                    (lambda (event) (Typed (Event-value event))))
                                (On "keydown"
                                    (list (Key))
                                    (Chords (list (Chord "Enter" 0)))
                                    (lambda (event) (Pressed (Event-key event)))))
                          (Nil))
                 (Element "button"
                          (list (Attr "id" "add") (On "click" (Nil) (Allow) (lambda (event) (Add))))
                          (list (Text "Add")))
                 (Element "button"
                          (list (Attr "id" "bullet")
                                (On "click" (Nil) (Allow) (lambda (event) (Bullet))))
                          (list (Text "Bullet")))
                 (Element "ul" (list (Attr "id" "notes")) (map note-view (Notes-notes model)))
                 (Element "p"
                          (list (Attr "id" "added"))
                          (list (Text (string-append (show (Notes-added model)) " added")))))))

(: note-view (-> Note (Html Message)))
(define (note-view note)
  (Element "li"
           (list (Keyed (show (Note-id note))))
           (list (Text (Note-text note))
                 (Element "button"
                          (list (Attr "id" (string-append "remove-" (show (Note-id note))))
                                (On "click" (Nil) (Allow) (lambda (event) (Remove (Note-id note)))))
                          (list (Text "Remove"))))))

(: save (-> Notes Save))
(define (save model)
  (Save (Notes-notes model) (Notes-next model)))

(: restore (-> Save Notes))
(define (restore saved)
  (Notes (Save-notes saved) "" (Save-next saved) 0))

(define-ui Notes
  Message
  (init: start)
  (update: update)
  (view: view)
  (save: save)
  (restore: restore))
