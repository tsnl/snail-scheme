;; Atlas slots and quad runs, through the recording handler: pictures fill
;; shelves and pages, one a call, a version already there is not composed
;; again, one that no longer fits clears the pages, and a run of quads is
;; one draw.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
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
;; A created object's kind, id and path, and a pass's id and encoder,
;; without their descriptors.
(define (heads (lines (List String))) (→ (List String))
  (map (lambda (line)
         (let ((words (words-of line)))
           (cond ((string=? (list-ref words 0) "create") (string-join (take words 4) " "))
                 ((string=? (list-ref words 0) "pass") (string-join (take words 3) " "))
                 (else line))))
       lines))

(define (words-of (text String)) (→ (List String))
  (match (string-index text #\space)
    ((Some at)
     (Cons (substring text 0 at) (words-of (substring text (+ at 1) (string-length text)))))
    ((None) (list text))))

(define (compose (gpu Gpu) (atlas Atlas) (pictures (List Picture))) (→ Atlas)
  (let* ((encoder ((● gpu create-command-encoder)))
         (next (atlas-pictures gpu atlas encoder pictures)))
    ((● gpu submit) (list ((● gpu finish) encoder)))
    next))

;; Composed a call at a time, `calls` times.
(define (settled (gpu Gpu) (atlas Atlas) (pictures (List Picture)) (calls I64))
  (→ Atlas)
  (if (= calls 0) atlas (settled gpu (compose gpu atlas pictures) pictures (- calls 1))))

(define (frames (gpu Gpu)) (→ (List Atlas))
  ((● gpu request-device))
  (let* ((first (settled gpu (make-atlas gpu "test" 64 2)
                         (list (picture 1 1 30 20) (picture 2 1 30 20) (picture 3 1 30 40))
                         3))
         (again (compose gpu first (list (picture 1 1 30 20) (picture 2 1 30 20))))
         (fourth (compose gpu again (list (picture 4 1 60 60))))
         (full (compose gpu fourth (list (picture 4 1 60 60) (picture 5 1 60 60)))))
    (list first again fourth full)))

(define (main (out OutputPort)) (→ Unit)
  (let ((recorded (with-recorded-gpu (lambda (gpu) (frames gpu)))))
    (for-each (lambda (atlas) (write-line out (slots atlas (list 1 2 3 4 5)))) (● recorded first))
    (for-each (lambda (text) (write-line out text)) (heads (● recorded second))))
  (write-line out "quads:")
  (for-each (lambda (text) (write-line out text))
            (heads (● (with-recorded-gpu (lambda (gpu) (quad-frames gpu))) second)))
  (unit))

(define (quad (index I64)) (→ Quad)
  (new Quad
    (center (new Vec2f (x (i64->f32 index)) (y 0.0)))
    (size (new Vec2f (x 1.0) (y 1.0)))
    (angle 0.0)
    (page 0)
    (region (new Vec4f (x 0.0) (y 0.0) (z 2.0) (w 1.0)))
    (color (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 1.0)))))

;; A frame's run of quads, over a cleared canvas.
(define (quad-frame (gpu Gpu) (quads Quads) (count I64)) (→ Quads)
  (let* ((encoder ((● gpu create-command-encoder)))
         (pass ((● gpu begin-render-pass) encoder
                (new RenderPassDescriptor
                  (colors (list (Some (new ColorAttachment
                                        (view
                                         (view-of gpu
                                                  (● ((● gpu current-texture))
                                                     texture)
                                                  1))
                                        (load (Keep))
                                        (store #t)))))
                  (depth (None)))))
         (quads (draw-quads gpu pass
                            quads
                            (new View2D
                              (center (new Vec2f (x 0.0) (y 0.0)))
                              (extent (new Vec2f (x 10.0) (y 10.0)))
                              (pixels (new Vec2f (x 100.0) (y 100.0))))
                            (map quad (iota count)))))
    ((● gpu end-pass) pass)
    ((● gpu submit) (list ((● gpu finish) encoder)))
    quads))

;; A run of three, then runs of a hundred and of two hundred, which grow
;; the instances: the outgrown buffer goes at its frame's submit.
(define (quad-frames (gpu Gpu)) (→ Unit)
  ((● gpu request-device))
  (fold-left (lambda (quads count) (quad-frame gpu quads count))
             (make-quads gpu "test" (Bgra8Unorm) (● (make-atlas gpu "test" 64 2) texture))
             (list 3 100 200))
  (unit))

