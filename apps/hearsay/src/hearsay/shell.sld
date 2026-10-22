;; The menu that opens each prototype, and the Menu button that returns to
;; it. The shell owns actions from 9000; prototypes own the ones below.
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
   (lofi base)
   (lofi wire)
   (lofi app)
   (hearsay mill)
   (hearsay mill-screen)
   (hearsay ledger-screen))
  (begin

    ;; ---- State ----

    (enum Screen
      (Menu)
      (Rumors ((screen MillScreen)))
      (Favors ((screen LedgerScreen)))
      (deriving Serialize Deserialize))

    ;; `opened` counts the prototypes opened. A ledger's seed comes from
    ;; it, and so does the first version of a rumor mill's town, so the host
    ;; never mistakes a new town for one it has already drawn.
    (struct Shell
      ((screen Screen)
       (seed I64)
       (opened I64)
       (width I32)
       (height I32))
      (deriving Serialize Deserialize))

    (: new-shell (-> I32 I32 I32 Shell))
    (define (new-shell seed width height)
      (Shell (Menu) (i32->i64 seed) 0 width height))

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
      (let ((scenario (i32->i64 argument)) (opened (+ (Shell-opened shell) 1)))
        (cond ((= action action-ledger)
               (Shell-opened-set (Shell-screen-set shell (Favors (new-ledger-screen (+ (Shell-seed shell) opened)))) opened))
              ((and (= action action-scenario) (>= scenario 0) (< scenario mill-scenario-count))
               (Shell-opened-set (Shell-screen-set shell (Rumors (new-mill-screen scenario (* opened 1000) (Shell-width shell)
                                                                                  (Shell-height shell))))
                                 opened))
              (else shell))))

    (: forward (-> Shell Input Shell))
    (define (forward shell input)
      (match (Shell-screen shell)
        ((Menu) shell)
        ((Rumors screen) (Shell-screen-set shell (Rumors (update-mill-screen screen input))))
        ((Favors screen) (Shell-screen-set shell (Favors (update-ledger-screen screen input))))))

    (: press (-> Shell I32 I32 Shell))
    (define (press shell action argument)
      (cond ((= action action-menu) (Shell-screen-set shell (Menu)))
            ((match (Shell-screen shell) ((Menu) #t) (_ #f)) (open shell action argument))
            (else (forward shell (Press action argument)))))

    (: update-shell (-> Shell Input Shell))
    (define (update-shell shell input)
      (match input
        ((Press action argument) (press shell action argument))
        ((Resize width height) (forward (Shell-height-set (Shell-width-set shell width) height) input))
        (_ (forward shell input))))

    ;; ---- View ----

    (define menu-frame
      (Frame (Camera (Vec3 0.0 10.0 10.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8)) (Light (Vec3 0.0 1.0 0.0) 0.0 1.0)
             (rgb 16 20 28) 1.0 (Nil) (Nil)))

    ;; `art` gives the bytes of each sheet the cast wears; main.sld passes
    ;; the embedded ones, and tests may pass none.
    (: view-shell (-> Shell (-> String (Option Source)) Frame))
    (define (view-shell shell art)
      (match (Shell-screen shell)
        ((Menu) menu-frame)
        ((Rumors screen) (view-mill-screen screen art))
        ((Favors screen) (view-ledger-screen screen art))))

    (: menu-panels (List Panel))
    (define menu-panels
      (list (Panel "menu" (At (TopLeft) 0)
                   (append (list (Label (look "title") "Hearsay prototypes")
                                 (Label (look "subtitle") "Each one asks one question about whether the design is fun."))
                           (append (map (lambda (index)
                                          (Button (look (string-append "scenario-" (show index)))
                                                  (string-append "Rumor mill: " (mill-scenario-name index)) "" action-scenario
                                                  (i64->i32 index) (Enabled) -1.0))
                                        (iota mill-scenario-count))
                                   (list (Button (look "ledger") "Favor ledger" "" action-ledger 0 (Enabled) -1.0)))))))

    ;; Each prototype puts the Menu button first in the top-right corner.
    (: menu-button (List Panel))
    (define menu-button
      (list (Panel "back" (At (TopRight) 0) (list (Button (look "back") "Menu" "" action-menu 0 (Enabled) -1.0)))))

    (: shell-hud (-> Shell (List Panel)))
    (define (shell-hud shell)
      (match (Shell-screen shell)
        ((Menu) menu-panels)
        ((Rumors screen) (mill-screen-hud screen menu-button))
        ((Favors screen) (ledger-screen-hud screen menu-button))))

    ))
