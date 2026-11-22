;; The menu that opens each prototype and the credits, and the Menu and
;; Guide buttons beside each prototype. The shell owns actions from 9000; prototypes own the ones
;; below, and the Guide button presses the prototype's own guide-open.
(define-library (apps hearsay shell)
  (export
   Shell
   new-shell
   update-shell
   draw-shell
   shell-pictures
   shell-hud
   shell-save
   shell-restore)
  (import
   (snail core base)
   (snail shell wire)
   (only (snail core io) Clock)
   (only (snail shell gpu) Gpu)
   (snail shell app)
   (snail shell graphics pod)
   (only (snail shell graphics atlas) Source Picture)
   (only (snail shell graphics quad) View2D)
   (apps hearsay mill)
   (apps hearsay mill-screen)
   (apps hearsay ledger-screen)
   (apps hearsay hud)
   (apps hearsay drawing)
   (lpc credits)
   (apps hearsay credits))
  (begin

    ;; ---- State ----

    (enum Screen
      (Menu)
      (Rumors ((screen MillScreen)))
      (Favors ((screen LedgerScreen)))
      (Credits)
      (deriving Serialize Deserialize))

    ;; `opened` counts the prototypes opened, and a ledger's seed comes
    ;; from it. Each guide opens by itself until its prototype has been
    ;; opened once.
    (record Shell
      ((screen Screen)
       (seed I64)
       (opened I64)
       (mill-guided Bool)
       (ledger-guided Bool)
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    (define (new-shell (seed I32) (width I32) (height I32)) (→ Shell)
      (new Shell
        (screen (Menu))
        (seed (i32->i64 seed))
        (opened 0)
        (mill-guided #f)
        (ledger-guided #f)
        (width width)
        (height height)))

    ;; The whole shell is the save; the host reports the screen's size after
    ;; restoring.
    (define (shell-save (shell Shell)) (→ Shell)
      shell)

    (define (shell-restore (shell Shell)) (→ Shell)
      shell)

    ;; Menu buttons open rumor-mill scenario i as action 9000 with argument
    ;; i, the ledger as 9100, or the credits as 9200.
    (define action-scenario (→ I32) 9000)
    (define action-ledger (→ I32) 9100)
    (define action-credits (→ I32) 9200)
    (define action-menu (→ I32) 9999)

    ;; ---- Updates ----

    (define (open (shell Shell) (action I32) (argument I32)) (→ Shell)
      (let ((index (i32->i64 argument)) (opened (+ (● shell opened) 1)))
        (cond ((= action action-credits) (Shell-screen-set shell (Credits)))
              ((= action action-ledger)
               (show-opened (Shell-ledger-guided-set shell #t)
                            (Favors (new-ledger-screen (+ (● shell seed) opened)))
                            (● shell ledger-guided)))
              ((and (= action action-scenario) (>= index 0) (< index (length scenarios)))
               (show-opened (Shell-mill-guided-set shell #t)
                            (Rumors (new-mill-screen (list-ref scenarios index)
                                                     (● shell width)
                                                     (● shell height)))
                            (● shell mill-guided)))
              (else shell))))

    ;; Shows a newly opened prototype and counts it, pressing its Guide
    ;; button unless it has been `guided` before.
    (define (show-opened (shell Shell) (screen Screen) (guided Bool)) (→ Shell)
      (let ((shown (Shell-opened-set (Shell-screen-set shell screen) (+ (● shell opened) 1))))
        (if guided shown (forward shown (Press guide-open 0)))))

    (define (forward (shell Shell) (input Input)) (→ Shell)
      (match (● shell screen)
        ((Menu) shell)
        ((Credits) shell)
        ((Rumors screen) (Shell-screen-set shell (Rumors (update-mill-screen screen input))))
        ((Favors screen) (Shell-screen-set shell (Favors (update-ledger-screen screen input))))))

    (define (press (shell Shell) (action I32) (argument I32)) (→ Shell)
      (cond ((= action action-menu) (Shell-screen-set shell (Menu)))
            ((match (● shell screen) ((Menu) #t) (_ #f)) (open shell action argument))
            (else (forward shell (Press action argument)))))

    (define (update-shell (shell Shell) (input Input)) (→ Shell)
      (match input
        ((Press action argument) (press shell action argument))
        ((Resize width height)
         (forward (Shell-height-set (Shell-width-set shell width) height) input))
        (_ (forward shell input))))

    ;; ---- Drawing ----

    ;; The screen's pictures composed and its quads drawn over the
    ;; backdrop. `art` gives the bytes of each sheet the cast wears;
    ;; main.scm passes the embedded ones, and tests may pass none. Only
    ;; the rumor mill has a scene; the ledger's pictures are its rivals'
    ;; portraits.
    (define (draw-shell (gpu Gpu)
                        (clock Clock)
                        (shell Shell)
                        (drawing Drawing)
                        (art (Fn String → (Option Source))))
      (→ Drawing)
      (let ((time (quotient ((● clock monotonic-nanoseconds)) 1000000)))
        (match (● shell screen)
          ((Rumors screen)
           (draw-quads-frame gpu drawing
                             (shell-pictures shell art)
                             backdrop
                             (mill-view screen)
                             (lambda (atlas) (mill-quads screen atlas time))))
          (_
           (draw-quads-frame gpu drawing
                             (shell-pictures shell art)
                             backdrop
                             (still-view shell)
                             (lambda (atlas) (Nil)))))))

    (define (shell-pictures (shell Shell) (art (Fn String → (Option Source)))) (→ (List Picture))
      (match (● shell screen)
        ((Menu) (Nil))
        ((Credits) (Nil))
        ((Rumors _) (mill-pictures art))
        ((Favors _) (ledger-pictures art))))

    ;; A view for a screen with no scene.
    (define (still-view (shell Shell)) (→ View2D)
      (let ((size (new Vec2f
                    (x (max 1.0 (i32->f32 (● shell width))))
                    (y (max 1.0 (i32->f32 (● shell height)))))))
        (new View2D (center (new Vec2f (x 0.0) (y 0.0))) (extent size) (pixels size))))

    (define menu-panels (→ (List Panel))
      (list (new Panel (key "menu") (place (At (TopLeft) 0))
                 (widgets (concatenate
                           (list (list (label "title" "Hearsay prototypes")
                                       (label "subtitle"
                                              "Each prototype asks one question about whether a piece of the design is fun. Each opens with a short guide to its rules and to what to watch for while you play.")
                                       (label "heading-rumors"
                                              "The rumor mill: is steering belief fun?"))
                                 (map-indexed (lambda (index scenario)
                                                (let ((rules (scenario-rules scenario)))
                                                  (Button
                                                   (look (string-append "scenario-" (show index)))
                                                   (● rules name)
                                                   (● rules pitch)
                                                   action-scenario
                                                   (i64->i32 index)
                                                   (Enabled)
                                                   -1.0)))
                                              scenarios)
                                 (list (label "heading-favors"
                                              "The favor ledger: do favors trade, or get hoarded?")
                                       (Button (look "ledger")
                                               "Favor ledger"
                                               "Trade markers and promises with two rival fixers."
                                               action-ledger
                                               0
                                               (Enabled) -1.0)
                                       (Button (look "credits")
                                               "Credits"
                                               "Who drew the characters, and under which licenses."
                                               action-credits
                                               0
                                               (Enabled) -1.0))))))))

    ;; Each prototype puts the Menu and Guide buttons first in the top-right
    ;; corner.
    (define menu-button (→ (List Panel))
      (list (new Panel (key "back") (place (At (TopRight) 0))
                 (widgets (list (button "back" "Menu" action-menu)
                                (button "open-guide" "Guide" guide-open))))))

    ;; ---- Credits ----

    ;; The characters are composed from LPC sheets, one panel crediting
    ;; each part they come from: title, authors, licenses and sources, as a
    ;; CC-BY credit asks, with what each author changed. The pictures
    ;; composed from them are adaptations, shared alike.
    (define credits-panels (→ (List Panel))
      (append (list (new Panel (key "back") (place (At (TopRight) 0))
                         (widgets (list (button "back" "Menu" action-menu))))
                    (new Panel (key "credits") (place (At (TopLeft) 0))
                         (widgets (list (label "title" "Credits")
                                        (label "subtitle" credits-notice)
                                        (Link (look "attribution")
                                              "Each pack's full credits"
                                              attribution-url))))
                    (new Panel (key "licenses") (place (At (TopLeft) 0))
                         (widgets (Cons (label "heading" "The licenses")
                                        (map (lambda (license)
                                               (Link (look (● license first))
                                                     (● license first)
                                                     (● license second)))
                                             licenses)))))
              (map-indexed credit-panel credits)))

    ;; Each license a credited part names, and its text.
    (define licenses (→ (List (Pair String String)))
      (list
       (new Pair (first "CC-BY-SA 3.0") (second "https://creativecommons.org/licenses/by-sa/3.0/"))
       (new Pair (first "CC-BY 3.0") (second "https://creativecommons.org/licenses/by/3.0/"))
       (new Pair (first "CC-BY 4.0") (second "https://creativecommons.org/licenses/by/4.0/"))
       (new Pair (first "OGA-BY 3.0") (second "https://static.opengameart.org/OGA-BY-3.0.txt"))
       (new Pair
         (first "GPL 2.0")
         (second "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"))
       (new Pair (first "GPL 3.0") (second "https://www.gnu.org/licenses/gpl-3.0.html"))
       (new Pair (first "CC0 1.0") (second "https://creativecommons.org/publicdomain/zero/1.0/"))))

    (define credits-notice (→ String)
      "The characters are drawn from Liberated Pixel Cup art. Each part below keeps the licenses its authors gave it; the characters composed from them are shared under CC-BY-SA 3.0. The parts are named as their packs name them.")

    (define attribution-url (→ String)
      "https://github.com/tsnl/snail-scheme/blob/main/src/lpc/ATTRIBUTION.md")

    (define (credit-panel (index I64) (credit Credit)) (→ Panel)
      (new Panel
        (key (string-append "credit-" (show index)))
        (place (At (TopLeft) 0))
        (widgets (append (credit-terms credit) (credit-sources credit)))))

    ;; The part and its pack, then its authors, licenses and changes, and
    ;; the sheets of it the cast wears.
    (define (credit-terms (credit Credit)) (→ (List Widget))
      (let ((pack (string-append " from " (● credit pack)))
            (sheets (string-join (● credit sheets) ", ")))
        (list (Text (look "part") (list (Strong (● credit title)) (Normal pack)))
              (label "authors" (string-append "By " (● credit authors)))
              (label "licenses" (string-append "Licenses: " (● credit licenses)))
              (label "changes" (● credit changes))
              (label "sheets" (string-append "Sheets used: " sheets)))))

    (define (credit-sources (credit Credit)) (→ (List Widget))
      (map-indexed (lambda (index url) (Link (look (string-append "source-" (show index))) url url))
                   (● credit sources)))

    (define (shell-hud (shell Shell)) (→ (List Panel))
      (match (● shell screen)
        ((Menu) menu-panels)
        ((Credits) credits-panels)
        ((Rumors screen) (mill-screen-hud screen menu-button))
        ((Favors screen) (ledger-screen-hud screen menu-button))))

    ))
