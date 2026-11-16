;; The menu that opens each prototype, and the Menu and Guide buttons beside
;; each one. The shell owns actions from 9000; prototypes own the ones
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
   (only (snail core io) clock monotonic-nanoseconds)
   (only (snail shell task) tasks)
   (only (snail shell gpu) gpu)
   (except (snail shell app) Quad Picture Layer Source Rect)
   (snail shell graphics pod)
   (only (snail shell graphics atlas) Source Picture)
   (only (snail shell graphics quad) View2D)
   (apps hearsay mill)
   (apps hearsay mill-screen)
   (apps hearsay ledger-screen)
   (apps hearsay hud)
   (apps hearsay drawing))
  (begin

    ;; ---- State ----

    (enum Screen
      (Menu)
      (Rumors ((screen MillScreen)))
      (Favors ((screen LedgerScreen)))
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
    ;; i, or the ledger as 9100.
    (define action-scenario (→ I32) 9000)
    (define action-ledger (→ I32) 9100)
    (define action-menu (→ I32) 9999)

    ;; ---- Updates ----

    (define (open (shell Shell) (action I32) (argument I32)) (→ Shell)
      (let ((index (i32->i64 argument)) (opened (+ (● shell opened) 1)))
        (cond ((= action action-ledger)
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
    (define (draw-shell (shell Shell) (drawing Drawing) (art (Fn String → (Option Source))))
      (→ Drawing)
      (! gpu clock tasks)
      (let ((time (quotient (monotonic-nanoseconds) 1000000)))
        (match (● shell screen)
          ((Rumors screen)
           (draw-quads-frame drawing
                             (shell-pictures shell art)
                             backdrop
                             (mill-view screen)
                             (lambda (atlas) (mill-quads screen atlas time))))
          (_
           (draw-quads-frame drawing
                             (shell-pictures shell art)
                             backdrop
                             (still-view shell)
                             (lambda (atlas) (Nil)))))))

    (define (shell-pictures (shell Shell) (art (Fn String → (Option Source)))) (→ (List Picture))
      (match (● shell screen)
        ((Menu) (Nil))
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
                                               (Enabled) -1.0))))))))

    ;; Each prototype puts the Menu and Guide buttons first in the top-right
    ;; corner.
    (define menu-button (→ (List Panel))
      (list (new Panel (key "back") (place (At (TopRight) 0))
                 (widgets (list (button "back" "Menu" action-menu)
                                (button "open-guide" "Guide" guide-open))))))

    (define (shell-hud (shell Shell)) (→ (List Panel))
      (match (● shell screen)
        ((Menu) menu-panels)
        ((Rumors screen) (mill-screen-hud screen menu-button))
        ((Favors screen) (ledger-screen-hud screen menu-button))))

    ))
