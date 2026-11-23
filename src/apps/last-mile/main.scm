(import
 (snail core base)
 (snail core io)
 (snail shell app)
 (snail shell page)
 (snail shell fetch)
 (only (snail shell dom) Dom)
 (only (snail shell gpu) Gpu)
 (only (snail shell graphics gltf) attempt-reading unreadable)
 (apps last-mile game)
 (apps last-mile hud)
 (apps last-mile render))

;; ---- Input between simulation ticks ----

(record Controls
  ((keys (List I32))
   (pointer Bool)
   (use Bool)
   (shot Bool)
   (paused Bool)
   (carry I64)))

(define (controls) (→ Controls)
  (new Controls (keys (Nil)) (pointer #f) (use #f) (shot #f) (paused #f) (carry 0)))

(define (key-bit (key I32)) (→ I64)
  (case key ((119 3) 1) ((115 4) 2) ((97 1) 4) ((100 2) 8) ((32) 16) ((98) 32) (else 0)))

(define (held (c Controls)) (→ I64)
  (fold-left (lambda (mask key) (i64-or mask (key-bit key)))
             (if (or (● c pointer) (● c shot)) 16 0)
             (● c keys)))

(define (key-down! (c Controls) (w Game) (key I32)) (→ Game)
  (if (member? key (● c keys)) w
      (begin (set! (● c keys) (Cons key (● c keys)))
             (case key
               ((112 27)
                (set! (● c paused) (not (● c paused)))
                (set! (● c use) #f)
                (set! (● c shot) #f)
                w)
               ((101) (unless (● c paused) (set! (● c use) #t)) w)
               ((32) (unless (● c paused) (set! (● c shot) #t)) w)
               ((116) (unless (● c paused) (speak! w -1)) w)
               ((49 50 51 52 53 54 55 56 57)
                (unless (● c paused) (speak! w (- (i32->i64 key) 49)))
                w)
               ((114) (match (● w mission) ((Finished) (set! (● c paused) #f) (new-world)) (_ w)))
               (else w)))))

(define (input! (c Controls) (w Game) (input Input)) (→ Game)
  (match input
    ((KeyDown key _) (key-down! c w key))
    ((KeyUp key) (set! (● c keys) (filter (lambda (k) (not (= k key))) (● c keys))) w)
    ((PointerDown _ _ _ 0) (set! (● c pointer) #t) (set! (● c shot) (not (● c paused))) w)
    ((PointerUp _ _ _) (set! (● c pointer) #f) w)
    ((PointerCancel _) (set! (● c pointer) #f) w)
    (_ w)))

(define (elapsed! (c Controls) (w Game) (ms I32)) (→ Unit)
  (unless (● c paused)
    (let loop ((carry (+ (● c carry) (min 250 (i32->i64 ms)))))
      (if (< carry tick-ms) (set! (● c carry) carry)
          (begin (step! w (new Order (buttons (held c)) (interact (● c use))))
                 (set! (● c use) #f) (set! (● c shot) #f) (loop (- carry tick-ms)))))))

;; ---- Page and save ----

(define (read-files (fetch Fetch) (paths (List String))) (→ (List Bytes))
  (map (lambda (path)
         (match (fetch-bytes fetch path)
           ((Ok bytes) bytes) ((Err why) (unreadable (string-append path " " why))))) paths))

(define (play (events Events) (gpu Gpu) (dom Dom) (renderer Renderer) (hud Hud)
              (world Game) (save (Fn Game → Unit))) (→ Unit)
              (let loop ((w world) (c (controls)) (since 100))
                (match (next-event events)
                  ((FrameEvent ms)
                   (elapsed! c w ms)
                   (let ((due (>= (+ since ms) 100)))
                     (when due (show! dom hud w (● c paused)))
                     (draw! renderer gpu w ms)
                     ((● events report-ready))
                     (loop w c (if due 0 (+ since ms)))))
                  ((InputEvent event) (loop (input! c w event) c 100))
                  ((Hidden) (save w) (loop w (controls) 100))
                  ((SaveRequested) (save w) (loop w c since))
                  (_ (loop w c since)))))

(define (main (events Events)
              (gpu Gpu)
              (dom Dom)
              (fetch Fetch)
              (storage PageStorage)
              (out OutputPort))
  (→ Unit)
  (let ((hud (make-hud dom)))
    (run-page events
              storage
              new-world
              save-game
              restore-game
              (lambda (w save)
                (match (attempt-reading
                        (lambda () (make-renderer gpu (lambda (paths) (read-files fetch paths)) w)))
                  ((Ok renderer) (play events gpu dom renderer hud w save))
                  ((Err why) (write-line out why) (panic why)))))))
