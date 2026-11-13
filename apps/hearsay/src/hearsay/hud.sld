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
   (snail core base)
   (snail shell app))
  (begin

    ;; ---- Widgets ----

    (define (toned (key String) (tone Tone) (text String)) (→ Widget)
      (Label (Look-tone-set (look key) tone) text))

    ;; A section's title.
    (define (section-heading (key String) (text String)) (→ Widget)
      (label (string-append "heading-" key) text))

    ;; A heading over its widgets, or over a muted line saying there are none.
    (define (section (key String) (title String) (none String) (widgets (List Widget)))
      (→ (List Widget))
      (Cons (section-heading key title)
            (if (null? widgets) (list (toned (string-append "none-" key) (Muted) none)) widgets)))

    ;; Each line as its own label.
    (define (line-labels (prefix String) (texts (List String))) (→ (List Widget))
      (map-indexed (lambda (index text) (label (string-append prefix "-" (show index)) text))
                   texts))

    ;; A button showing its terms as its caption: disabled with the reason
    ;; as its help when `refusal` says why it would fail now, and otherwise
    ;; enabled with `help`.
    (define (choice-button (key String)
                           (text String)
                           (caption String)
                           (action I32)
                           (argument I32)
                           (refusal (Option String))
                           (help String))
      (→ Widget)
      (match refusal
        ((Some why)
         (Button (Look-help-set (look key) why) text caption action argument (Disabled) -1.0))
        ((None)
         (Button (Look-help-set (look key) help) text caption action argument (Enabled) -1.0))))

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
    (define (guide-open) (→ I32) 50)

    (define (guide-next) (→ I32) 51)

    (define (guide-back) (→ I32) 52)

    (define (guide-close) (→ I32) 53)

    (define (guide-action? (action I32)) (→ Bool)
      (and (>= action (guide-open)) (<= action (guide-close))))

    ;; The page open after pressing `action` in a guide of `pages`: Next
    ;; past the last page closes it, Back stops at the first.
    (define (turn-guide (page (Option I64)) (pages (List Page)) (action I32)) (→ (Option I64))
      (cond ((= action (guide-open)) (Some 0))
            ((= action (guide-close)) (None))
            (else (match page
                    ((Some index)
                     (cond ((= action (guide-next))
                            (if (< (+ index 1) (length pages)) (Some (+ index 1)) (None)))
                           (else (Some (max 0 (- index 1))))))
                    ((None) (None))))))

    ;; ---- Dialog ----

    ;; The open page of the guide to the prototype called `name`, as a
    ;; dialog that closes when touched outside; nothing while it is closed.
    (define (guide-panels (name String) (pages (List Page)) (page (Option I64))) (→ (List Panel))
      (match page
        ((Some index) (list (guide-panel name pages index)))
        ((None) (Nil))))

    (define (guide-panel (name String) (pages (List Page)) (index I64)) (→ Panel)
      (let ((page (list-ref pages index)) (last? (= (+ index 1) (length pages))))
        (Panel "guide" (Dialog (guide-close))
               (concatenate
                (list (Cons (label "guide-title" (● page title))
                            (line-labels "guide-text" (● page paragraphs)))
                      (● page extras)
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
                                    (guide-back)
                                    0
                                    (if (= index 0) (Disabled) (Enabled))
                                    -1.0)
                            (button "guide-next"
                                    (if last? "Start playing" "Next")
                                    (guide-next))))))))

    ;; ---- Scene ----

    ;; The color behind every screen.
    (define (backdrop) (→ I32) (rgb 16 20 28))

    ;; A scene with nothing in it, carrying `pictures` for the HUD's images.
    (define (empty-frame (pictures (List Picture))) (→ Frame)
      (Frame (Camera (Vec3 0.0 10.0 10.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8))
             (Light (Vec3 0.0 1.0 0.0) 0.0 1.0)
             (backdrop)
             1.0
             (Nil)
             pictures))

    ))
