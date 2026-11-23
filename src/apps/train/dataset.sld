;; A COLMAP dataset's files as a scene (apps train trainer) trains on, for
;; the app's two entry points. A `Dataset` says how its files are read,
;; each by its path in the dataset, and which folder holds the
;; photographs; `linked-dataset` makes one of a generated library's linked
;; files, as (datasets mipnerf360 bicycle) gives them, read through the
;; host's `Resources`: a page fetches them from beside it, and a program
;; on Node reads them from its package.
;;
;; The dataset holds the sparse reconstruction, `sparse/0/cameras.bin`,
;; `images.bin` and `points3D.bin`, and each image's photograph by its
;; name in the folder of photographs. Every eighth photograph, in order of
;; name, is held out, as Mip-NeRF 360's scenes are judged.
;;
;; The options are `name=value` pairs, a page's query or a program's
;; arguments: the steps (`steps`, 30,000), the most gaussians the device
;; holds (`gaussians`, 4,194,304) and the step whose kernels are timed
;; (`profile`, none).
(define-library (apps train dataset)
  (export
   Dataset
   linked-dataset
   options-of
   setting
   dataset-scene
   dataset-photograph)
  (import
   (snail core base)
   (only (snail shell resource) Resource Resources read-resource)
   (only (snail shell gpu) Gpu Image TextureObject)
   (snail shell graphics colmap)
   (only (apps train trainer) Scene make-scene Options))
  (begin

    ;; ---- Datasets ----

    ;; `read` gives a file's bytes by its path in the dataset, such as
    ;; "sparse/0/cameras.bin", and `photographs` names the folder of
    ;; photographs in it.
    (record Dataset
      ((read (Fn String → Bytes))
       (photographs String)))

    ;; The dataset of `files`, each a linked file by its path, read when the
    ;; trainer asks for it.
    (define (linked-dataset (resources Resources)
                            (files (List (Pair String Resource)))
                            (photographs String))
      (→ Dataset)
      (new Dataset
        (read (lambda (path)
                (match (find (lambda (file) (string=? (● file first) path)) files)
                  ((Some file) (read-resource resources (● file second)))
                  ((None) (panic (string-append "the dataset has no file " path))))))
        (photographs photographs)))

    ;; ---- Options ----

    ;; The options in a page address's query, each one missing at its
    ;; default.
    (define (options-of (address String)) (→ Options)
      (let ((value (lambda (name default)
                     (match (setting address name)
                       ((Some given) given)
                       ((None) default)))))
        (new Options
          (steps (number (value "steps" "30000") 30000))
          (gaussians (number (value "gaussians" "4194304") 4194304))
          (profile (number (value "profile" "0") 0)))))

    ;; The value a page address's query gives `name`, among the
    ;; `name=value` pairs after its `?`.
    (define (setting (address String) (name String)) (→ (Option String))
      (let* ((query (match (string-index address #\?)
                      ((Some at) (substring address (+ at 1) (string-length address)))
                      ((None) "")))
             (pairs (map (lambda (part) (split-on part #\=)) (split-on query #\&))))
        (match (find (lambda (pair) (and (= (length pair) 2) (string=? (list-ref pair 0) name)))
                     pairs)
          ((Some pair) (Some (list-ref pair 1)))
          ((None) (None)))))

    (define (number (text String) (default I64)) (→ I64)
      (match (string->i64 text)
        ((Some n) n)
        ((None) default)))

    ;; The pieces of a text between each `separator`.
    (define (split-on (text String) (separator Char)) (→ (List String))
      (match (string-index text separator)
        ((Some at)
         (Cons (substring text 0 at)
               (split-on (substring text (+ at 1) (string-length text)) separator)))
        ((None) (list text))))

    ;; ---- The scene ----

    ;; The scene in the dataset: its first camera, its images in order of
    ;; name, every eighth held out, and its sparse points. The first
    ;; photograph is decoded for the size they share, which the camera is
    ;; scaled to.
    (define (dataset-scene (gpu Gpu) (dataset Dataset)) (→ Scene)
      (let* ((sparse (lambda (file) ((● dataset read) (string-append "sparse/0/" file))))
             (camera (list-ref (parsed (read-cameras (sparse "cameras.bin"))) 0))
             (images (list-sort (lambda (a b) (string<? (● a name) (● b name)))
                                (parsed (read-images (sparse "images.bin")))))
             (points (parsed (read-points (sparse "points3D.bin"))))
             (first (dataset-photograph gpu dataset (list-ref images 0)))
             (held? (lambda (k) (= (remainder k 8) 0))))
        ((● gpu destroy) (TextureObject (● first texture)))
        (make-scene (camera-sized camera (i32->i64 (● first width)) (i32->i64 (● first height)))
                    (filter-indexed (lambda (k) (not (held? k))) images)
                    (filter-indexed held? images)
                    points)))

    (define (parsed (result (Result T String))) (→ T) (∀ (T))
      (match result
        ((Ok value) value)
        ((Err why) (panic why))))

    (define (filter-indexed (keep (Fn I64 → Bool)) (items (List T))) (→ (List T)) (∀ (T))
      (map (lambda (pair) (● pair second))
           (filter (lambda (pair) (keep (● pair first))) (zip (iota (length items)) items))))

    ;; An image's photograph, read and decoded onto the device.
    (define (dataset-photograph (gpu Gpu) (dataset Dataset) (image ColmapImage)) (→ Image)
      (let ((path (string-append (● dataset photographs) "/" (● image name))))
        (match ((● gpu decode-image) ((● dataset read) path))
          ((Some photo) photo)
          ((None) (panic (string-append path " is no image the host decodes"))))))

    ))
