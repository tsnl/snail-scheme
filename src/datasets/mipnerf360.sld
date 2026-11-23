;; Mip-NeRF 360's scenes (Barron et al., 2022), as Google publishes them,
;; for `generate-library` recipes: nine scenes each photographed from all
;; around, with COLMAP's sparse reconstruction, `sparse/0`, and the
;; photographs at their full size, `images`, and at a half, a quarter and
;; an eighth of it, `images_2`, `images_4` and `images_8`. Seven scenes
;; are in one archive of 12.5 GB, and flowers and treehill in another of
;; 4.5 GB. Each archive is pinned here by its end's digest, and a scene's
;; files are read from it a member at a time into the machine's cache
;; ((snail shell web zip)), so a scene at the size the paper trains it
;; fetches a few hundred megabytes, once a machine.
;;
;; `scene-library` is a recipe's work: the library of a scene's
;; reconstruction and one folder of its photographs, exporting `files`,
;; each file by its path in the scene with its linked file, and
;; `photographs`, the folder's name. (datasets mipnerf360 bicycle) and the
;; other scenes' libraries are each at the size 3D Gaussian Splatting
;; trains it: the outdoor scenes at a quarter, the indoor at a half.
;; `scene-folder` is the same files for a program that reads a folder, as
;; another implementation's trainer does: it answers where they are.
(define-library (datasets mipnerf360)
  (export
   scenes
   scene-library
   scene-folder)
  (import
   (snail core base)
   (only (snail core io) Fs ProcessEnvironment)
   (snail shell syntax)
   (only (snail shell web) Web)
   (snail shell web zip))
  (begin

    ;; ---- Archives ----

    (define main-archive (→ WebZip)
      (new WebZip
        (url "https://storage.googleapis.com/gresearch/refraw360/360_v2.zip")
        (end "0be64f576d63b68855fc9746daa2d62262f013c2ddf82abf20aadbf62c0f8477")))

    (define extra-archive (→ WebZip)
      (new WebZip
        (url "https://storage.googleapis.com/gresearch/refraw360/360_extra_scenes.zip")
        (end "5e03bca24bdfaa2b3d21df4a1ee324bd1480038f0bafd4991111b3c3aa6551ec")))

    (define scenes (→ (List String))
      (list "bicycle" "bonsai" "counter" "flowers" "garden" "kitchen" "room" "stump" "treehill"))

    (define (scene-archive (scene String)) (→ WebZip)
      (cond ((not (member? scene scenes))
             (panic (string-append "Mip-NeRF 360 has no scene " scene)))
            ((member? scene (list "flowers" "treehill")) extra-archive)
            (else main-archive)))

    ;; ---- Files ----

    ;; The scene's reconstruction and the folders of photographs named,
    ;; each file by its path in the scene, with where the cache keeps it.

    (define (scene-files (fs Fs) (web Web)
                         (environment ProcessEnvironment)
                         (scene String)
                         (folders (List String)))
      (→ (List (Pair String String)))
      (let* ((prefix (string-append scene "/"))
             (within (map (lambda (folder) (string-append prefix folder "/"))
                          (Cons "sparse/0" folders))))
        (map (lambda (member)
               (new Pair
                 (first (substring (● member first) (string-length prefix)
                                   (string-length (● member first))))
                 (second (● member second))))
             (zip-members fs web (machine-cache environment)
                          (scene-archive scene)
                          (lambda (name)
                            (any? (lambda (folder) (prefixed? folder name)) within))))))

    (define (prefixed? (prefix String) (text String)) (→ Bool)
      (and (<= (string-length prefix) (string-length text))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    ;; Where the cache keeps the scene's files, once they are there.

    (define (scene-folder (fs Fs) (web Web)
                          (environment ProcessEnvironment)
                          (scene String)
                          (folders (List String)))
      (→ String)
      (match (scene-files fs web environment scene folders)
        ((Cons (Pair path file) _)
         (substring file 0 (- (string-length file) (+ (string-length path) 1))))
        ((Nil) (panic (string-append "the scene " scene " has no files")))))

    ;; ---- Libraries ----

    ;; The library `name`, of the scene's reconstruction and its folder of
    ;; photographs `photographs`, exporting `files` ((snail shell syntax)'s
    ;; `linked-files`) and `photographs`, the folder's name.

    (define (scene-library (fs Fs) (web Web)
                           (environment ProcessEnvironment)
                           (name (List String))
                           (scene String)
                           (photographs String))
      (→ Syntax)
      (library-syntax name
                      (list "files" "photographs")
                      (list (list "snail" "core" "base") (list "snail" "shell" "resource"))
                      (list (linked-files "files"
                                          (scene-files fs web environment
                                                       scene
                                                       (list photographs)))
                            (form "define"
                                  (list (SymbolSyntax "photographs")
                                        (form "→" (list (SymbolSyntax "String")))
                                        (StringSyntax photographs))))))

    ))
