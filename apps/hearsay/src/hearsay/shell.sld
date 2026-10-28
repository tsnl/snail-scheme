;; The menu that opens each prototype, and the Menu and Guide buttons beside
;; each one. The shell owns actions from 9000; prototypes own the ones
;; below, and the Guide button presses the prototype's own guide-open.
(define-library (hearsay shell)
  (export
   Shell
   new-shell
   update-shell
   view-shell
   shell-hud
   shell-save
   shell-restore)
  (import
   (snail-core base)
   (snail-core wire)
   (snail-core app)
   (hearsay mill)
   (hearsay mill-screen)
   (hearsay ledger-screen)
   (hearsay hud))
  (begin

    ;; ---- State ----

    (enum Screen
      (Menu)
      (Rumors ((screen MillScreen)))
      (Favors ((screen LedgerScreen)))
      (deriving Serialize Deserialize))

    ;; `opened` counts the prototypes opened. A ledger's seed comes from
    ;; it, and so does the first version of a rumor mill's town, so the host
    ;; never mistakes a new town for one it has already drawn. Each guide
    ;; opens by itself until its prototype has been opened once.
    (struct Shell
      ((screen Screen)
       (seed I64)
       (opened I64)
       (mill-guided Bool)
       (ledger-guided Bool)
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    (: new-shell (-> I32 I32 I32 Shell))
    (define (new-shell seed width height)
      (Shell (Menu) (i32->i64 seed) 0 #f #f width height))

    ;; The whole shell is the save; the host reports the screen's size after
    ;; restoring.
    (: shell-save (-> Shell Shell))
    (define (shell-save shell)
      shell)

    (: shell-restore (-> Shell Shell))
    (define (shell-restore shell)
      shell)

    ;; Menu buttons open rumor-mill scenario i as action 9000 with argument
    ;; i, or the ledger as 9100.
    (define action-scenario 9000)
    (define action-ledger 9100)
    (define action-menu 9999)

    ;; ---- Updates ----

    (: open (-> Shell I32 I32 Shell))
    (define (open shell action argument)
      (let ((index (i32->i64 argument)) (opened (+ (Shell-opened shell) 1)))
        (cond ((= action action-ledger)
               (show-opened (Shell-ledger-guided-set shell #t)
                            (Favors
                             (new-ledger-screen (+ (Shell-seed shell) opened)))
                            (Shell-ledger-guided shell)))
              ((and (= action action-scenario)
                    (>= index 0)
                    (< index (length scenarios)))
               (show-opened (Shell-mill-guided-set shell #t)
                            (Rumors (new-mill-screen (list-ref scenarios index)
                                                     (* opened 1000)
                                                     (Shell-width shell)
                                                     (Shell-height shell)))
                            (Shell-mill-guided shell)))
              (else shell))))

    ;; Shows a newly opened prototype and counts it, pressing its Guide
    ;; button unless it has been `guided` before.
    (: show-opened (-> Shell Screen Bool Shell))
    (define (show-opened shell screen guided)
      (let ((shown (Shell-opened-set (Shell-screen-set shell screen)
                                     (+ (Shell-opened shell) 1))))
        (if guided shown (forward shown (Press guide-open 0)))))

    (: forward (-> Shell Input Shell))
    (define (forward shell input)
      (match (Shell-screen shell)
        ((Menu) shell)
        ((Rumors screen)
         (Shell-screen-set shell (Rumors (update-mill-screen screen input))))
        ((Favors screen)
         (Shell-screen-set shell
                           (Favors (update-ledger-screen screen input))))))

    (: press (-> Shell I32 I32 Shell))
    (define (press shell action argument)
      (cond ((= action action-menu) (Shell-screen-set shell (Menu)))
            ((match (Shell-screen shell) ((Menu) #t) (_ #f))
             (open shell action argument))
            (else (forward shell (Press action argument)))))

    (: update-shell (-> Shell Input Shell))
    (define (update-shell shell input)
      (match input
        ((Press action argument) (press shell action argument))
        ((Resize width height)
         (forward (Shell-height-set (Shell-width-set shell width) height)
                  input))
        (_ (forward shell input))))

    ;; ---- View ----

    ;; `art` gives the bytes of each sheet the cast wears; main.sld passes
    ;; the embedded ones, and tests may pass none.
    (: view-shell (-> Shell (-> String (Option Source)) Frame))
    (define (view-shell shell art)
      (match (Shell-screen shell)
        ((Menu) (empty-frame (Nil)))
        ((Rumors screen) (view-mill-screen screen art))
        ((Favors screen) (view-ledger-screen screen art))))

    (: menu-panels (List Panel))
    (define menu-panels
      (list (Panel "menu" (At (TopLeft) 0)
                   (concatenate
                    (list (list (label "title" "Hearsay prototypes")
                                (label "subtitle"
                                       "Each prototype asks one question about whether a piece of the design is fun. Each opens with a short guide to its rules and to what to watch for while you play.")
                                (label "heading-rumors"
                                       "The rumor mill: is steering belief fun?"))
                          (map-indexed (lambda (index scenario)
                                         (let ((rules
                                                (scenario-rules scenario)))
                                           (Button
                                            (look (string-append "scenario-"
                                                                 (show index)))
                                            (Rules-name rules)
                                            (Rules-pitch rules)
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
                                        (Enabled) -1.0)))))))

    ;; Each prototype puts the Menu and Guide buttons first in the top-right
    ;; corner.
    (: menu-button (List Panel))
    (define menu-button
      (list (Panel "back" (At (TopRight) 0)
                   (list (button "back" "Menu" action-menu)
                         (button "open-guide" "Guide" guide-open)))))

    (: shell-hud (-> Shell (List Panel)))
    (define (shell-hud shell)
      (match (Shell-screen shell)
        ((Menu) menu-panels)
        ((Rumors screen) (mill-screen-hud screen menu-button))
        ((Favors screen) (ledger-screen-hud screen menu-button))))

    ))
