(define-library (apps iygtw hud)
  (export Hud
          make-hud
          show!
          loading-screen
          RideKey
          SaveRide
          LoadRide
          SetSamples
          FocusControl
          focus-control!
          start-sound!
          bell!
          coast!)
  (import
   (snail core base)
   (snail shell dom)
   (prefix (snail shell ui) ui:)
   (snail shell static-resource)
   (snail shell base64)
   (snail shell game vehicle)
   (snail shell game locomotion)
   (apps iygtw ride)
   (apps iygtw rider)
   (apps iygtw render))
  (begin
    (define (mib (bytes I64)) (→ String)
      (let ((n (quotient (* bytes 10) 1048576)))
        (string-append (show (quotient n 10)) "." (show (remainder n 10)))))
    (define (download-view (s StaticProgress)) (→ (ui:Html Unit))
      (let* ((done (+ (● s downloaded) (● s cached))) (total (● s total))
             (detail (string-append (mib done) " / " (mib total) " MiB"
                                    (if (> (● s cached) 0)
                                        (string-append " · " (mib (● s cached)) " cached")
                                        "")
                                    (if (and (> total 0) (= done total))
                                        " · Preparing the valley"
                                        "")))
             (bar (list (ui:Attr "class" "download-bar") (ui:Attr "aria-label" "Village download")
                        (ui:Attr "max" (show (max 1 total))) (ui:Attr "value" (show done)))))
        (ui:Element "div" (list (ui:Attr "class" "download"))
                    (list (ui:Element "progress" bar (Nil))
                          (ui:Element "span"
                                      (list (ui:Attr "class" "download-size"))
                                      (list (ui:Text detail)))))))
    (define (loading-screen (d Dom)) (→ (Fn StaticProgress → Unit))
      (let ((root (ui:render-root d ((● d document-root)))))
        (define (progress (state StaticProgress))
          (→ Unit)
          (ui:render! root (list (download-view state))))
        (progress (new StaticProgress (downloaded 0) (cached 0) (total 0))) progress))

    (enum HudAction
      (RideKey ((key I32)))
      (SaveRide)
      (LoadRide)
      (SetSamples ((samples I32)))
      (FocusControl ((id String))))
    (record Hud
      ((view (ui:Root HudAction))
       (paused Bool)
       (save-status String)
       (hub-url String)
       (bell-url String)
       (hub (Option Node))
       (bell (Option Node))))
    (define (make-hud (d Dom) (hub Bytes) (bell Bytes)) (→ Hud)
      (new Hud (view (ui:render-root d ((● d document-root)))) (paused #f) (save-status "")
           (hub-url (data-url "audio/wav" hub)) (bell-url (data-url "audio/wav" bell))
           (hub (None)) (bell (None))))

    ;; ---- Pause menu ----

    (define (focus-control! (d Dom) (id String)) (→ Unit)
      (match ((● d element-by-id) id) ((Some node) ((● d focus-node) node)) (_ (unit))))
    (define (chord (key String) (mods I32)) (→ Chord) (new Chord (key key) (modifiers mods)))
    (define (sample-picker (samples I32)) (→ (ui:Html HudAction))
      (let* ((keys (Chords (list (chord "Tab" shift-key) (chord "p" 0) (chord "Escape" 0))))
             (keydown (ui:On "keydown" (list (Key)) keys (lambda (e)
                                                           (if (string=? (● e key) "Tab")
                                                               (FocusControl "ride-reset")
                                                               (RideKey 112)))))
             (change (ui:On "change" (list (Value)) (Allow)
                            (lambda (e) (SetSamples (if (string=? (● e value) "4") 4 1)))))
             (options (map (lambda (n)
                             (ui:Element "option" (list (ui:FlagProperty "selected" (= n samples)))
                                         (list (ui:Text (show n))))) (list 1 4)))
             (field (list (ui:Attr "class" "msaa") (ui:Attr "id" "ride-samples") change keydown)))
        (ui:Element "label" (list (ui:Attr "class" "setting"))
                    (list (ui:Element "span" (Nil) (list (ui:Text "Raster samples (MSAA)")))
                          (ui:Element "select" field options)))))
    (define (pause-actions) (→ (ui:Html HudAction))
      (let ((wrap (ui:On "keydown" (list (Key)) (Chords (list (chord "Tab" 0)))
                         (lambda (_) (FocusControl "ride-samples")))))
        (ui:Element "div" (list (ui:Attr "class" "pause-actions"))
                    (list (button "resume"
                                  (RideKey 112)
                                  "Resume ride"
                                  (list (ui:Attr "id" "ride-resume")))
                          (button "save-game" (SaveRide) "Save game" (Nil))
                          (button "load-game" (LoadRide) "Load game" (Nil))
                          (button "reset"
                                  (RideKey 114)
                                  "Reset to Lantern Row"
                                  (list (ui:Attr "id" "ride-reset") wrap))))))
    (define (pause-panel (samples I32) (paused Bool) (status String)) (→ (ui:Html HudAction))
      (let* ((dialog (list (ui:Attr "class" "pause-screen")
                           (ui:Attr "role" "dialog")
                           (ui:Attr "aria-modal" "true")
                           (ui:Attr "aria-label" "Ride paused")
                           (ui:FlagProperty "hidden" (not paused))))
             (title (ui:Element "h2" (Nil) (list (ui:Text "Ride paused"))))
             (legend (ui:Element "legend" (Nil) (list (ui:Text "Rendering"))))
             (settings (ui:Element "fieldset" (Nil) (list legend (sample-picker samples))))
             (panel (ui:Element "div"
                                (list (ui:Attr "class" "pause-panel"))
                                (list title settings (pause-actions)
                                      (ui:Element "p"
                                                  (list (ui:Attr "class" "save-status")
                                                        (ui:Attr "role" "status"))
                                                  (list (ui:Text status)))))))
        (ui:Element "section" dialog (list panel))))


    ;; ---- Live dashboard ----

    (define (surface-reading (v Valley) (s Ride) (speed F64)) (→ String)
      (match (● s travel)
        ((GettingOff _ _) "Getting off")
        ((GettingOn _ _) "Getting on")
        ((Slowing) "Braking to get off")
        ((OnFoot _) (cond
                     ((> speed 2.7) "Running")
                     ((> speed 0.15) "Walking")
                     (else "On foot")))
        (_ (cond ((can-remount? (● s rider)) "E · Get back on")
                 ((fallen? (● s rider)) "Taking a tumble")
                 ((< (signed-speed (● s bike)) -0.06) "Walking bike back")
                 (else (surface-name (surface-at v (● (player-body s) position))))))))
    (define (bicycle-action (v Valley) (s Ride)) (→ String)
      (match (● s travel)
        ((Astride) (cond ((can-remount? (● s rider)) "Get back on · F")
                         ((fallen? (● s rider)) "") (else "Get off · F")))
        ((Slowing) "Cancel stop · F")
        ((OnFoot w) (if (nearby-bicycle? v s w) "Ride · F" ""))
        (_ "")))
    (define (waymark (v Valley) (s Ride)) (→ (ui:Html HudAction))
      (let* ((speed (pace (player-body s))) (name (place-at v (● (player-body s) position)))
             (title (ui:Element "h1" (list (ui:Attr "class" "place")) (list (ui:Text name))))
             (surface (ui:Element "span"
                                  (list (ui:Attr "class" "surface"))
                                  (list (ui:Text (surface-reading v s speed)))))
             (attributes (list (ui:Attr "class" "speed")
                               (ui:Attr "data-metres" (show (f64->i64 (● s metres))))))
             (kph (string-append (show (f64->i64 (round (* speed 3.6)))) " km/h"))
             (pace-display (ui:Element "span" attributes (list (ui:Text kph))))
             (readings
              (ui:Element "div" (list (ui:Attr "class" "readings")) (list surface pace-display))))
        (ui:Element "section" (list (ui:Attr "class" "waymark")) (list title readings))))
    (define (button (class String)
                    (action HudAction)
                    (label String)
                    (attributes (List (ui:Attribute HudAction))))
      (→ (ui:Html HudAction))
      (ui:Element "button" (append (list (ui:Attr "class" class)
                                         (ui:On "click" (Nil) (Allow) (lambda (_) action)))
                                   attributes)
                  (list (ui:Text label))))
    (define (ride-buttons (v Valley) (s Ride) (paused Bool)) (→ (ui:Html HudAction))
      (let ((action (bicycle-action v s)))
        (ui:Element "nav" (list (ui:Attr "class" "options") (ui:Attr "aria-label" "Ride settings"))
                    (list (button "bicycle"
                                  (RideKey 102)
                                  action
                                  (list (ui:FlagProperty "hidden" (string=? action ""))))
                          (button "light"
                                  (RideKey 108)
                                  (light-name (● s light))
                                  (list (ui:Attr "title" "Change time of day (L)")))
                          (button "pause" (RideKey 112) (if paused "Resume" "Pause")
                                  (list (ui:Attr "id" "ride-pause")
                                        (ui:Attr "aria-haspopup" "dialog")))))))
    (define (show! (d Dom) (h Hud) (v Valley) (s Ride) (paused Bool)) (→ Unit)
      (ui:render! (● h view)
                  (list (waymark v s)
                        (ride-buttons v s paused)
                        (pause-panel (● s samples) paused (● h save-status))))
      (when (if paused (not (● h paused)) (● h paused))
        (unless paused (set! (● h save-status) ""))
        (set! (● h paused) paused)
        (focus-control! d (if paused "ride-resume" "ride-pause"))))
    ;; Use standard audio elements. A rider's first input starts the freewheel;
    ;; its playback rate follows wheel speed and the ratchet is silent under load.
    (define (sound (d Dom) (url String) (looping Bool) (volume F64)) (→ Node)
      (let ((n ((● d create-element) "audio")))
        ((● d set-string-property) n "src" url) ((● d set-flag-property) n "loop" looping)
        ((● d set-number-property) n "volume" volume) ((● d set-flag-property) n "autoplay" #t)
        ((● d insert-node) ((● d document-root)) n (None)) n))
    (define (start-sound! (d Dom) (h Hud)) (→ Unit)
      (match (● h hub) ((None) (set! (● h hub) (Some (sound d (● h hub-url) #t 0.0)))) (_ (unit))))
    (define (bell! (d Dom) (h Hud)) (→ Unit)
      (match (● h bell) ((Some n) ((● d remove-node) n)) (_ (unit)))
      (set! (● h bell) (Some (sound d (● h bell-url) #f 0.32))))
    (define (coast! (d Dom) (h Hud) (speed F64) (free Bool)) (→ Unit)
      (match (● h hub)
        ((Some n) ((● d set-number-property) n "playbackRate" (max 0.4 (min 2.6 (/ speed 4.0))))
         ((● d set-number-property) n "volume" (if free (min 0.22 (* speed 0.04)) 0.0)))
        (_ (unit))))))
