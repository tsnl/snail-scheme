(import
 (snail core base)
 (snail core io)
 (snail shell app)
 (snail shell page)
 (snail shell resource)
 (snail shell png)
 (snail shell game atlas)
 (snail shell game roads)
 (only (snail shell game vehicle) DriverControls neutral-driver)
 (only (snail shell game boarding) aboard?)
 (only (snail shell dom) Dom)
 (only (snail shell gpu) Gpu)
 (only (snail shell graphics gltf) attempt-reading)
 (apps last-mile assets)
 (apps last-mile game)
 (apps last-mile hud)
 (apps last-mile render))

;; ---- Input between simulation ticks ----

(record Controls
  ((keys (List I32))
   (driving DriverControls)
   (wide Bool)
   (sharp Bool)
   (choice I64)
   (use Bool)
   (paused Bool)
   (locked Bool)
   (yaw F64)
   (pitch F64)
   (before Game)
   (carry I64)))

(define (controls (w Game)) (→ Controls)
  (new Controls
    (keys (Nil))
    (driving (neutral-driver))
    (wide #f) (sharp #f) (choice (modulo (● w dispatch) 16))
    (use #f)
    (paused #f)
    (locked #f)
    (yaw 0.0)
    (pitch 0.28)
    (before (snapshot w))
    (carry 0)))

(define (key-bit (key I32)) (→ I64)
  (case key
    ((119 3) 1)
    ((115 4) 2)
    ((97) 4)
    ((100) 8)
    ((1) 128)
    ((2) 256)
    ((32) 16)
    ((98) 32)
    (else 0)))

(define (held (c Controls)) (→ I64)
  (fold-left (lambda (mask key) (i64-or mask (key-bit key)))
             (if (● c locked) 64 0)
             (● c keys)))

(define (key-down! (c Controls) (w Game) (key I32)) (→ Game)
  (if (member? key (● c keys)) w
      (begin (set! (● c keys) (Cons key (● c keys)))
             (case key
               ((112 27)
                (set! (● c paused) (not (● c paused)))
                (set! (● c use) #f)
                w)
               ((113) (set! (● c sharp) (not (● c sharp))) w)
               ((99) (set! (● c yaw) 0.0) (set! (● c pitch) 0.28) w)
               ((101) (unless (● c paused) (set! (● c use) #t)) w)
               ((116) (unless (● c paused) (speak! w -1)) w)
               ((49 50 51 52 53 54 55 56 57)
                (unless (● c paused) (speak! w (- (i32->i64 key) 49)))
                w)
               ((109)
                (set! (● c wide) (not (● c wide)))
                (set! (● c choice) (modulo (● w dispatch) 16))
                w)
               ((91 93)
                (when (● c wide)
                  (set! (● c choice) (modulo (+ (● c choice) (if (= key 93) 1 15)) 16)))
                w)
               ((13)
                (when (and (● c wide) (start-stand! w (● c choice)))
                  (set! (● c wide) #f)
                  (set! (● c paused) #f)
                  (set! (● c carry) 0) (set! (● c yaw) 0.0)) w)
               ((108) (when (match (● w fare) ((Waiting) #t) (_ #f)) (shift-time! w)) w)
               (else w)))))

(define (input! (c Controls) (w Game) (input Input)) (→ Game)
  (match input
    ((KeyDown key _) (key-down! c w key))
    ((KeyUp key) (set! (● c keys) (filter (lambda (k) (not (= k key))) (● c keys))) w)
    ((PointerLock captured)
     (set! (● c locked) captured)
     (unless captured (set! (● c keys) (Nil)) (set! (● c use) #f))
     w)
    ((PointerDelta dx dy)
     (unless (● c paused)
       (let ((turn (* 0.0035 (i32->f64 dx))))
         (if (aboard? (● w driver)) (set! (● c yaw) (+ (● c yaw) turn))
             (begin (set! (● c yaw) 0.0) (turn-driver! w turn)))
         (set! (● c pitch) (max -0.32 (min 1.16 (+ (● c pitch) (* 0.003 (i32->f64 dy))))))))
     w)
    (_ w)))

(define (elapsed! (g Area) (roads Roads) (c Controls) (w Game) (ms I32)) (→ Unit)
  (unless (● c paused)
    (let loop ((carry (+ (● c carry) (min 250 (i32->i64 ms)))))
      (if (< carry tick-ms) (set! (● c carry) carry)
          (begin (when (< carry (* 2 tick-ms)) (set! (● c before) (snapshot w)))
                 (step! g
                        roads
                        w
                        (new Order (driving (● c driving)) (buttons (held c)) (interact (● c use))))
                 (unless (aboard? (● w driver)) (set! (● c yaw) 0.0))
                 (focus-area! g (● (carrier w) position))
                 (set! (● c use) #f)
                 (loop (- carry tick-ms)))))))

;; ---- Page and save ----

(define (play (events Events) (gpu Gpu) (dom Dom) (renderer Renderer) (hud Hud)
              (g Area) (roads Roads) (world Game) (save (Fn Game → Unit))) (→ Unit)
              (let loop ((w world) (c (controls world)) (since 100))
                (match (next-event events)
                  ((FrameEvent ms)
                   (when (null? (● w traffic))
                     (focus-area! g (● (carrier w) position))
                     (populate! g roads w)
                     (set! (● c before) (snapshot w)))
                   (elapsed! g roads c w ms)
                   (let ((due (>= (+ since ms) 100)))
                     (when due
                       (show! dom
                              hud
                              g
                              roads
                              w
                              (● c paused)
                              (● c wide)
                              (● c choice)
                              (render-resolution renderer (● c sharp))))
                     (draw! renderer
                            gpu
                            (● c before)
                            w
                            (/ (i64->f64 (● c carry)) (i64->f64 tick-ms))
                            (● c yaw)
                            (● c pitch)
                            ms (● c sharp))
                     ((● events report-ready)) (loop w c (if due 0 (+ since ms)))))
                  ((InputEvent event) (loop (input! c w event) c 100))
                  ((HudEvent listener)
                   (match (clicked-stand hud listener)
                     ((Some i) (when (● c wide) (set! (● c choice) i)))
                     ((None) (unless (● c paused) (click-reply! hud w listener))))
                   (loop w c 100))
                  ((Hidden) (save w) (loop w (controls w) 100))
                  ((SaveRequested) (save w) (loop w c since)) (_ (loop w c since)))))

(define (main (events Events)
              (gpu Gpu)
              (dom Dom)
              (resources Resources)
              (storage PageStorage)
              (out OutputPort))
  (→ Unit)
  (let* ((files (read-resources resources
                                (append city-bands
                                        (list streets-model
                                              map-image
                                              taxi-model
                                              other-model
                                              people-model
                                              horizon-model))))
         (atlas (read-atlas (take files 6))) (roads (read-roads (list-ref files 6)))
         (hud (make-hud dom atlas (png-data-url (list-ref files 7)))) (models (list-drop files 8)))
    (run-page events storage new-world save-game restore-game
              (lambda (w save)
                (let ((g (open-area atlas (● (carrier w) position))))
                  (when (or (null? (● w residents)) (null? (● w traffic))) (populate! g roads w))
                  (match (attempt-reading (lambda ()
                                            (make-renderer gpu
                                                           (lambda (paths)
                                                             (art-reader resources paths))
                                                           models
                                                           g
                                                           roads
                                                           w)))
                    ((Ok renderer) (play events gpu dom renderer hud g roads w save))
                    ((Err why) (write-line out why) (panic why))))))))
