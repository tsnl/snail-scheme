;; COLMAP's binary files read: a PINHOLE and a SIMPLE_PINHOLE camera, an
;; image with two 2D points its reader skips, a point with a track of
;; two, and a pose turned into splat training's camera param; then the
;; files the readers refuse.
(import
 (snail core base)
 (snail core io)
 (snail shell graphics colmap))

;; ---- Bytes ----

(define (integer-bytes (value I64) (count I64)) (→ (List I64))
  (map (lambda (k) (i64-and (i64-shift-right value (* 8 k)) 255)) (iota count)))

(define (f64-bytes (values (List F64))) (→ (List I64))
  (concatenate (map (lambda (v) (integer-bytes (f64->bits v) 8)) values)))

(define (text-bytes (text String)) (→ (List I64))
  (append (map char->integer (string->list text)) (list 0)))

(define (file (parts (List (List I64)))) (→ Bytes)
  (list->array (map (lambda (b) (i32->u8 (i64->i32 b))) (concatenate parts))))

(define cameras
  (→ Bytes)
  (file (list (integer-bytes 2 8)
              (integer-bytes 1 4)
              (integer-bytes 1 4)
              (integer-bytes 4946 8)
              (integer-bytes 3286 8)
              (f64-bytes (list 4649.5 4627.25 2473.0 1643.0))
              (integer-bytes 2 4)
              (integer-bytes 0 4)
              (integer-bytes 640 8)
              (integer-bytes 480 8)
              (f64-bytes (list 500.0 320.0 240.0)))))

(define images
  (→ Bytes)
  (file (list (integer-bytes 1 8)
              (integer-bytes 7 4)
              (f64-bytes (list 0.5 0.5 0.5 0.5))
              (f64-bytes (list 1.0 -2.0 3.5))
              (integer-bytes 1 4)
              (text-bytes "_DSC8679.JPG")
              (integer-bytes 2 8)
              (f64-bytes (list 10.0 20.0))
              (integer-bytes 5 8)
              (f64-bytes (list 30.0 40.0))
              (integer-bytes 6 8))))

(define points
  (→ Bytes)
  (file (list (integer-bytes 1 8)
              (integer-bytes 63145 8)
              (f64-bytes (list -0.5 0.25 2.0))
              (list 255 0 51)
              (f64-bytes (list 0.7))
              (integer-bytes 2 8)
              (integer-bytes 7 4)
              (integer-bytes 0 4)
              (integer-bytes 8 4)
              (integer-bytes 1 4))))

;; ---- Reading ----

(define (numbers (values (List F64))) (→ String) (string-join (map f64->string values) " "))

(match (read-cameras cameras)
  ((Ok read)
   (for-each (lambda (c)
               (write-line (string-append "camera "
                                          (show (● c id))
                                          ": "
                                          (show (● c width))
                                          "x"
                                          (show (● c height))
                                          " "
                                          (numbers (list (● c fx) (● c fy) (● c cx) (● c cy))))))
             read))
  ((Err why) (write-line why)))

(match (read-images images)
  ((Ok read)
   (for-each (lambda (i)
               (write-line (string-append "image "
                                          (show (● i id))
                                          " "
                                          (● i name)
                                          " on camera "
                                          (show (● i camera))))
               (write-line (string-append "rotation " (numbers (image-rotation i))))
               (match (read-cameras cameras)
                 ((Ok (Cons camera _))
                  (write-line (string-append "camera param at half size "
                                             (numbers (camera-values camera i 0.5)))))
                 (_ (unit))))
             read))
  ((Err why) (write-line why)))

(match (read-points points)
  ((Ok read)
   (for-each (lambda (p)
               (write-line (string-append "point "
                                          (numbers (● p position))
                                          " color "
                                          (numbers (● p color)))))
             read))
  ((Err why) (write-line why)))

;; ---- Refusals ----

(define (refusal (result (Result (List ColmapCamera) String))) (→ String)
  (match result
    ((Ok _) "read")
    ((Err why) why)))

(write-line (refusal (read-cameras (subarray cameras 0 40))))
(write-line (refusal (read-cameras (file (list (integer-bytes 1 8)
                                               (integer-bytes 1 4)
                                               (integer-bytes 4 4)
                                               (integer-bytes 8 8)
                                               (integer-bytes 8 8))))))
(write-line (match (read-images (subarray images 0 70))
              ((Ok _) "read")
              ((Err why) why)))
(write-line (match (read-points (subarray points 0 60))
              ((Ok _) "read")
              ((Err why) why)))
