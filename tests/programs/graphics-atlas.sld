;; Atlas slots and quad runs, through the recording handler: pictures fill
;; shelves and pages, a version already there is not composed again, one
;; that no longer fits clears the pages, and a run of quads is one draw.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
 (only (snail shell task) tasks)
 (snail shell graphics pod)
 (snail shell graphics atlas)
 (snail shell graphics quad))

(define two-texels
  #u8(137 80
          78
          71
          13
          10
          26
          10
          0
          0
          0
          13
          73
          72
          68
          82
          0
          0
          0
          2
          0
          0
          0
          1
          8
          6
          0
          0
          0
          244
          34
          127
          138
          0
          0
          0
          14
          73
          68
          65
          84
          120
          156
          99
          248
          207
          192
          240
          31
          4
          1
          16
          248
          3
          253
          78
          149
          193
          111
          0
          0
          0
          0
          73
          69
          78
          68
          174
          66
          96 130))

(define source (→ Source) (new Source (key 1) (bytes (lambda () two-texels))))

(define (picture (key I32) (version I32) (width I32) (height I32)) (→ Picture)
  (new Picture
    (key key)
    (version version)
    (width width)
    (height height)
    (layers (lambda ()
              (list (new Layer
                      (source source)
                      (from (new Rect (x 0) (y 0) (width 2) (height 1)))
                      (x 0)
                      (y 0)
                      (swaps (list (new Pair (first 16711680) (second 255))))))))))

(define (slots (atlas Atlas) (keys (List I32))) (→ String)
  (string-join (map (lambda (key)
                      (match (atlas-slot atlas key)
                        ((Some slot)
                         (string-append (show key)
                                        ": page "
                                        (show (● slot page))
                                        " at "
                                        (show (● slot x))
                                        ","
                                        (show (● slot y))))
                        ((None) (string-append (show key) ": none"))))
                    keys)
               "; "))

;; Only the commands, without their descriptors.
(define (heads (lines (List String))) (→ (List String))
  (map (lambda (line)
         (match (string-index line #\{)
           ((Some at) (substring line 0 at))
           ((None) line)))
       lines))

(define (compose (atlas Atlas) (pictures (List Picture))) (→ Atlas) (! gpu tasks)
  (let* ((encoder (create-command-encoder)) (next (atlas-pictures atlas encoder pictures)))
    (submit (list (finish encoder)))
    next))

(define (frames) (→ (List Atlas)) (! gpu tasks)
  (request-device 100000000)
  (let* ((first (compose (make-atlas "test" 64 2)
                         (list (picture 1 1 30 20) (picture 2 1 30 20) (picture 3 1 30 40))))
         (again (compose first (list (picture 1 1 30 20) (picture 2 1 30 20))))
         (full (compose again (list (picture 4 1 60 60) (picture 5 1 60 60)))))
    (list first again full)))

(let ((recorded (with-recorded-gpu 100000000 (lambda () (frames)))))
  (for-each (lambda (atlas) (write-line (slots atlas (list 1 2 3 4 5)))) (● recorded first))
  (for-each write-line (heads (● recorded second))))

(write-line "quads:")
(for-each write-line
          (heads (● (with-recorded-gpu 100000000
                                       (lambda ()
                                         (request-device 100000000)
                                         (let* ((encoder (create-command-encoder))
                                                (pass (begin-render-pass encoder
                                                                         (new RenderPassDescriptor
                                                                           (colors
                                                                            (list
                                                                             (new ColorAttachment
                                                                               (view
                                                                                (view-of
                                                                                 (current-texture)
                                                                                 1))
                                                                               (load (Keep))
                                                                               (store #t))))
                                                                           (depth (None))))))
                                           (draw-quads pass
                                                       "test"
                                                       (Bgra8Unorm)
                                                       (new View2D
                                                         (center (new Vec2f (x 0.0) (y 0.0)))
                                                         (extent (new Vec2f (x 10.0) (y 10.0)))
                                                         (pixels (new Vec2f (x 100.0) (y 100.0))))
                                                       (atlas-texture (make-atlas "test" 64 2))
                                                       (map (lambda (index)
                                                              (new Quad
                                                                (center (new Vec2f
                                                                          (x (i64->f32 index))
                                                                          (y 0.0)))
                                                                (size (new Vec2f (x 1.0) (y 1.0)))
                                                                (angle 0.0)
                                                                (page 0)
                                                                (region (new Vec4f
                                                                          (x 0.0)
                                                                          (y 0.0)
                                                                          (z 2.0)
                                                                          (w 1.0)))
                                                                (color (new Vec4f
                                                                         (x 1.0)
                                                                         (y 1.0)
                                                                         (z 1.0)
                                                                         (w 1.0)))))
                                                            (iota 3)))
                                           (end-pass pass)
                                           (submit (list (finish encoder))))))
                    second)))
