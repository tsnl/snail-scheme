;; What the prototypes' screens share: labels with a tone, headings over
;; sections, buttons that say why they cannot be pressed, the guide, a few
;; pages shown in a dialog over a prototype the first time it opens and
;; whenever its Guide button is pressed, and the scene behind a screen
;; that draws none. The page's stylesheet styles the keys given here:
;; `heading-` labels and the guide's `guide-` widgets.
(define-library (hearsay hud)
  (export
   toned
   section-heading
   section
   line-labels
   choice-button
   Page
   guide-open
   guide-next
   guide-close
   guide-action?
   turn-guide
   guide-panels
   backdrop
   empty-frame)
  (import
   (snail-core base)
   (snail-core app))
  (begin

    ;; ---- Widgets ----

    (: toned (-> String Tone String Widget))
    (define (toned key tone text)
      (Label (Look-tone-set (look key) tone) text))

    ;; A section's title.
    (: section-heading (-> String String Widget))
    (define (section-heading key text)
      (label (string-append "heading-" key) text))

    ;; A heading over its widgets, or over a muted line saying there are none.
    (: section (-> String String String (List Widget) (List Widget)))
    (define (section key title none widgets)
      (Cons (section-heading key title)
            (if (null? widgets)
                (list (toned (string-append "none-" key) (Muted) none))
                widgets)))

    ;; Each line as its own label.
    (: line-labels (-> String (List String) (List Widget)))
    (define (line-labels prefix texts)
      (map-indexed (lambda (index text)
                     (label (string-append prefix "-" (show index)) text))
                   texts))

    ;; A button showing its terms as its caption: disabled with the reason
    ;; as its help when `refusal` says why it would fail now, and otherwise
    ;; enabled with `help`.
    (: choice-button
       (-> String String String I32 I32 (Option String) String Widget))
    (define (choice-button key text caption action argument refusal help)
      (match refusal
        ((Some why)
         (Button (Look-help-set (look key) why)
                 text
                 caption
                 action
                 argument
                 (Disabled)
                 -1.0))
        ((None)
         (Button (Look-help-set (look key) help)
                 text
                 caption
                 action
                 argument
                 (Enabled)
                 -1.0))))

    ;; ---- Guide pages ----

    ;; A title and its paragraphs, with any widgets to show beneath them,
    ;; such as a portrait.
    (struct Page
      ((title String)
       (paragraphs (List String))
       (extras (List Widget))))

    ;; ---- Turning ----

    ;; The guide's buttons, actions 50 to 53, which no screen uses for its
    ;; own. A screen keeps its guide's open page, or None, and passes these
    ;; actions here.
    (: guide-open I32)
    (define guide-open 50)

    (: guide-next I32)
    (define guide-next 51)

    (: guide-back I32)
    (define guide-back 52)

    (: guide-close I32)
    (define guide-close 53)

    (: guide-action? (-> I32 Bool))
    (define (guide-action? action)
      (and (>= action guide-open) (<= action guide-close)))

    ;; The page open after pressing `action` in a guide of `pages`: Next
    ;; past the last page closes it, Back stops at the first.
    (: turn-guide (-> (Option I64) (List Page) I32 (Option I64)))
    (define (turn-guide page pages action)
      (cond ((= action guide-open) (Some 0))
            ((= action guide-close) (None))
            (else (match page
                    ((Some index)
                     (cond ((= action guide-next)
                            (if (< (+ index 1) (length pages))
                                (Some (+ index 1))
                                (None)))
                           (else (Some (max 0 (- index 1))))))
                    ((None) (None))))))

    ;; ---- Dialog ----

    ;; The open page of the guide to the prototype called `name`, as a
    ;; dialog that closes when touched outside; nothing while it is closed.
    (: guide-panels (-> String (List Page) (Option I64) (List Panel)))
    (define (guide-panels name pages page)
      (match page
        ((Some index) (list (guide-panel name pages index)))
        ((None) (Nil))))

    (: guide-panel (-> String (List Page) I64 Panel))
    (define (guide-panel name pages index)
      (let ((page (list-ref pages index))
            (last? (= (+ index 1) (length pages))))
        (Panel "guide" (Dialog guide-close)
               (concatenate
                (list (Cons (label "guide-title" (Page-title page))
                            (line-labels "guide-text" (Page-paragraphs page)))
                      (Page-extras page)
                      (list (toned "guide-page"
                                   (Muted)
                                   (string-append name
                                                  " guide, "
                                                  (show (+ index 1))
                                                  " of "
                                                  (show (length pages))))
                            (Button (look "guide-back")
                                    "Back"
                                    ""
                                    guide-back
                                    0
                                    (if (= index 0) (Disabled) (Enabled))
                                    -1.0)
                            (button "guide-next"
                                    (if last? "Start playing" "Next")
                                    guide-next)))))))

    ;; ---- Scene ----

    ;; The color behind every screen.
    (: backdrop I32)
    (define backdrop (rgb 16 20 28))

    ;; A scene with nothing in it, carrying `pictures` for the HUD's images.
    (: empty-frame (-> (List Picture) Frame))
    (define (empty-frame pictures)
      (Frame (Camera (Vec3 0.0 10.0 10.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8))
             (Light (Vec3 0.0 1.0 0.0) 0.0 1.0)
             backdrop
             1.0
             (Nil)
             pictures))

    ))
