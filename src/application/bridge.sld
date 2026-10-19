;; Private scalar ABI adapter. Application code sees immutable typed values;
;; only this codec stages a replacement snapshot in a host-owned transaction.
(define-library (application bridge)
  (export Program program run-program read-snapshot read-previous-snapshot
          read-program-world read-program-previous-world read-program-local read-program-previous-local)
  (import
   (scheme base)
   (application reducer)
   (browser application)
   (only (lofi base) i32->i64 i64->i32 unreachable ref ref-get ref-set!)
   (only (lofi core) datatype define-extern -> I32))
  (begin
    (define-extern snapshot-length "snail.reducer" "length" (-> I32 I32))
    (define-extern snapshot-read "snail.reducer" "read" (-> I32 I32 I32))
    (define-extern previous-length "snail.reducer" "previous-length" (-> I32 I32))
    (define-extern previous-read "snail.reducer" "previous-read" (-> I32 I32 I32))
    (define-extern snapshot-identity "snail.reducer" "identity" (-> I32 I32 I32))
    (define-extern stage-word "snail.reducer" "write" (-> I32 I32 I32 Unit))
    (define-extern stage-command "snail.reducer" "command" (-> I32 I32 I32 I32 Unit))
    (define-extern stage-note "snail.reducer" "note" (-> I32 I32 Unit))
    (define-extern stage-quad "snail.reducer" "quad" (-> I32 I32 I32 I32 I32 I32 Unit))
    (define-extern stage-label "snail.reducer" "label" (-> I32 I32 Unit))
    (define Program
      (datatype (WorldOwner State LocalOwner Local)
        (make-program
         (world (Application WorldOwner State) program-world)
         (local (Application LocalOwner Local) program-local)
         (world-size I32 program-world-size)
         (local-size I32 program-local-size)
         (decode-world (SnapshotDecoder State) program-decode-world)
         (encode-world (-> State (Vector I32)) program-encode-world)
         (decode-local (SnapshotDecoder Local) program-decode-local)
         (encode-local (-> Local (Vector I32)) program-encode-local)
         (view (-> State Local (List Quad)) program-view)
         (status (-> State Local String) program-status))))

    ;; ---- Bounded interpretations of exact immutable snapshots ----

    ;; This relies on the application contract: decoders are pure, and handlers
    ;; never mutate anything reachable from an earlier state. Each Program owns
    ;; its caches in its Wasm instance. Entries prove decoding, not publication;
    ;; only the host chooses which immutable bank is current, prior or proposed.
    (define DecodedSnapshot
      (datatype (State)
        (decoded-snapshot
         (identity I32 decoded-identity)
         (value State decoded-value))))
    (define SnapshotDecoder
      (datatype (State)
        (snapshot-decoder
         (owner I32 decoder-owner)
         (decode (-> (Vector I32) State) decoder-decode)
         (entries (Ref (List (DecodedSnapshot State))) decoder-entries))))
    (define (program world local world-size local-size decode-world encode-world decode-local encode-local view status)
      (make-program world local world-size local-size
                    (snapshot-decoder 1 decode-world (ref (empty-list))) encode-world
                    (snapshot-decoder 2 decode-local (ref (empty-list))) encode-local view status))
    (define (find-decoded entries identity)
      (cond ((null? entries) entries)
            ((= (decoded-identity (car entries)) identity) entries)
            (else (find-decoded (cdr entries) identity))))
    (define (recent-decoded entries identity remaining)
      (cond ((or (null? entries) (= remaining 0)) (empty-list))
            ((= (decoded-identity (car entries)) identity) (recent-decoded (cdr entries) identity remaining))
            (else (cons (car entries) (recent-decoded (cdr entries) identity (- remaining 1))))))
    (define (remember-decoded! decoder entry)
      ;; Three roots cover the usual current/prior/candidate working set. An
      ;; eviction only repeats pure decoding; no commit role lives in this list.
      (ref-set! (decoder-entries decoder)
                (cons entry (recent-decoded (ref-get (decoder-entries decoder)) (decoded-identity entry) 2))))
    (define (decode-bank decoder previous identity)
      (let* ((owner (decoder-owner decoder))
             (words (if previous (read-previous-snapshot owner) (read-snapshot owner)))
             (value ((decoder-decode decoder) words)))
        ;; No entry is installed until structural and application checks return.
        (let ((entry (decoded-snapshot identity value))) (remember-decoded! decoder entry) value)))
    (define (read-decoded decoder previous)
      (let* ((identity (snapshot-identity (decoder-owner decoder) (if previous 1 0)))
             (found (find-decoded (ref-get (decoder-entries decoder)) identity)))
        (if (null? found) (decode-bank decoder previous identity)
            (begin (remember-decoded! decoder (car found)) (decoded-value (car found))))))
    (define (read-program-world app) (read-decoded (program-decode-world app) #f))
    (define (read-program-previous-world app) (read-decoded (program-decode-world app) #t))
    (define (read-program-local app) (read-decoded (program-decode-local app) #f))
    (define (read-program-previous-local app) (read-decoded (program-decode-local app) #t))

    ;; ---- Copy a snapshot into the replacement module's managed heap ----

    (define (read-snapshot owner)
      (let* ((count (snapshot-length owner)) (words (make-vector (i32->i64 count) 0)))
        (let loop ((index 0))
          (when (< index count)
            (vector-set! words (i32->i64 index) (snapshot-read owner index)) (loop (+ index 1)))) words))
    (define (read-previous-snapshot owner)
      (let* ((count (previous-length owner)) (words (make-vector (i32->i64 count) 0)))
        (let loop ((index 0))
          (when (< index count)
            (vector-set! words (i32->i64 index) (previous-read owner index)) (loop (+ index 1)))) words))
    (define (write-words owner words)
      (stage-word owner -1 (i64->i32 (vector-length words)))
      (let loop ((index 0))
        (when (< (i32->i64 index) (vector-length words))
          (stage-word owner index (vector-ref words (i32->i64 index))) (loop (+ index 1)))))
    (define (stage-effects effects)
      (unless (null? effects)
        (let ((effect (car effects)))
          (if (= (effect-kind effect) 1)
              (stage-command (effect-owner effect) (effect-slot effect) (effect-a effect) (effect-b effect))
              (let ((text (effect-text effect)))
                (stage-note -1 (text-scalar text -1))
                (let loop ((index 0))
                  (when (< index (text-scalar text -1))
                    (stage-note index (text-scalar text index)) (loop (+ index 1)))))))
        (stage-effects (cdr effects))))
    (define (commit-transition owner encode next)
      (write-words owner (encode (transition-state next)))
      (stage-effects (transition-effects next)) 1)
    (define (draw-quads quads)
      (unless (null? quads)
        (let ((value (car quads)))
          (stage-quad (quad-x value) (quad-y value) (quad-width value)
                      (quad-height value) (quad-rgb value) (quad-opacity value)))
        (draw-quads (cdr quads))))
    (define (draw-label text)
      (stage-label -1 (text-scalar text -1))
      (let loop ((index 0))
        (when (< index (text-scalar text -1))
          (stage-label index (text-scalar text index)) (loop (+ index 1)))))

    ;; ---- One entry, explicit operations; the host owns committed state ----

    ;; 0 metadata; 1 initialize absent owner; 2 dispatch world; 3 dispatch local;
    ;; 4 presentation query; 10 validate state schema.
    (define (run-program app operation a b c)
      (cond
       ((= operation 0)
        (cond ((= a 0) 1) ((= a 1) (program-world-size app))
              ((= a 2) (program-local-size app)) ((= a 3) (application-schema (program-world app)))
              (else (application-schema (program-local app)))))
       ((= operation 1)
        (if (= a 1) (write-words 1 ((program-encode-world app) ((application-initial (program-world app)))))
            (write-words 2 ((program-encode-local app) ((application-initial (program-local app)))))) 1)
       ((= operation 2)
        (commit-transition 1 (program-encode-world app)
                           (dispatch-wire (program-world app) (read-program-world app) a b c)))
       ((= operation 3)
        (commit-transition 2 (program-encode-local app)
                           (dispatch-wire (program-local app) (read-program-local app) a b c)))
       ((= operation 4)
        (let ((world (read-program-world app))
              (local (read-program-local app)))
          (draw-quads ((program-view app) world local))
          (draw-label ((program-status app) world local)) 1))
       ((= operation 10)
        (if (and (or (= (snapshot-read 1 0) 0)
                     (= (snapshot-read 1 0) (application-schema (program-world app))))
                 (or (= (snapshot-read 2 0) 0)
                     (= (snapshot-read 2 0) (application-schema (program-local app)))))
            (begin
              (when (> (snapshot-read 1 0) 0) (read-program-world app))
              (when (> (snapshot-read 2 0) 0) (read-program-local app)) 1) 0))
       (else (unreachable))))))
