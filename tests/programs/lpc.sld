;; The LPC libraries against the packs checked in under src/lpc: every sheet
;; the catalog names exists, dressing refuses what no pack draws, layers come
;; in drawing order, heads are recolored ramp for ramp, and a pose picks the
;; strip a viewer should see.
(import
 (snail core base)
 (snail core io)
 (snail shell app)
 (snail shell sprite)
 (lpc layout)
 (lpc catalog)
 (lpc wardrobe))

(define (missing (paths (List String))) (→ (List String)) (! fs)
  (filter (lambda (path) (not (file-exists? path))) paths))

(define (report (title String) (paths (List String))) (→ Unit) (! output-port fs)
  (write-line (string-append title
                             ": "
                             (show (length paths))
                             " sheets, missing "
                             (show (length (missing paths))))))

(define (olive) (→ Skin) (new Skin (name "olive")))

(define (outfit) (→ Outfit)
  (new Outfit
    (hair
     (Some (new Hair (style (new HairStyle (name "bob"))) (color (new HairColor (name "ginger"))))))
    (torso (Some (new Worn (garment (Longsleeve)) (dye (new Dye (name "teal"))))))
    (legs (Some (new Worn (garment (Pants)) (dye (new Dye (name "navy"))))))
    (feet (Some (new Worn (garment (Shoes)) (dye (new Dye (name "brown"))))))))

(define (describe (who (Option Character))) (→ String)
  (match who
    ((Some character)
     (string-append "dressed in " (show (length (● character sheets))) " layers"))
    ((None) "refused")))

(define (same-fingerprint? (a (Option Character)) (b (Option Character))) (→ Bool)
  (match (new Pair (first a) (second b))
    ((Pair (Some one) (Some other)) (= (fingerprint one) (fingerprint other)))
    (_ #f)))

;; A camera looking down -z: a figure facing +z faces the viewer, one
;; facing +x their right.
(define (camera)
  (→ Camera)
  (new Camera
    (eye (new Vec3 (x 0.0) (y 5.0) (z 10.0)))
    (target (new Vec3 (x 0.0) (y 0.0) (z 0.0)))
    (projection (Perspective 0.8))))

(define (texture-text (item Item)) (→ String)
  (match (● (● item material) texture)
    ((Some (Texture picture region frames period))
     (string-append "picture "
                    (show picture)
                    " at "
                    (show (● region x))
                    ","
                    (show (● region y))
                    ", "
                    (show frames)
                    " frames"))
    ((None) "untextured")))

(define (main) (→ Unit) (! fs output-port)

  (report "bodies"
          (concatenate
           (map (lambda (build) (map (lambda (skin) (● (body-sheet build skin) path)) (skins)))
                (builds))))
  (report "heads" (map (lambda (head) (● (head-sheet head (list-ref (skins) 0)) path)) (heads)))
  (report "garments"
          (concatenate (map (lambda (garment)
                              (map (lambda (build)
                                     (match (garment-sheet build
                                                           garment
                                                           (list-ref (garment-dyes build garment)
                                                                     0))
                                       ((Some sheet) (● sheet path))
                                       ((None) "(no sheet)")))
                                   (garment-builds garment)))
                            (garments))))
  (report "hair"
          (concatenate (map (lambda (style)
                              (map (lambda (build)
                                     (● (hair-sheet build style (list-ref (hair-colors) 0)) path))
                                   (list (Male) (Female))))
                            (hair-styles))))
  (write-line (string-append "female: " (describe (dress (Female) (HumanFemale) (olive) (outfit)))))
  (write-line
   (string-append "male in navy pants: " (describe (dress (Male) (HumanMale) (olive) (outfit)))))
  (write-line (string-append "male in green pants: "
                             (describe (dress (Male)
                                              (HumanMale)
                                              (olive)
                                              (new Outfit (hair (None))
                                                   (torso (None))
                                                   (legs (Some (new Worn
                                                                 (garment (Pants))
                                                                 (dye (new Dye (name "green"))))))
                                                   (feet (None)))))))
  (write-line (string-append "shoes on the torso: "
                             (describe (dress (Female)
                                              (HumanFemale)
                                              (olive)
                                              (new Outfit (hair (None))
                                                   (torso (Some (new Worn
                                                                  (garment (Shoes))
                                                                  (dye (new Dye (name "brown"))))))
                                                   (legs (None))
                                                   (feet (None)))))))
  (match (dress (Female) (HumanFemale) (olive) (outfit))
    ((Some who)
     (for-each (lambda (sheet)
                 (write-line (string-append "  "
                                            (substring (● sheet path)
                                                       8
                                                       (string-length (● sheet path)))
                                            " swaps " (show (length (● sheet swaps))))))
               (● who sheets))
     (write-line (string-append "same character, same fingerprint: "
                                (if (same-fingerprint? (Some who)
                                                       (dress (Female)
                                                              (HumanFemale)
                                                              (olive)
                                                              (outfit)))
                                    "yes"
                                    "no")))
     (write-line (string-append "another skin, another fingerprint: "
                                (if (same-fingerprint? (Some who)
                                                       (dress (Female)
                                                              (HumanFemale)
                                                              (new Skin (name "light"))
                                                              (outfit)))
                                    "no"
                                    "yes"))))
    ((None) (write-line "refused")))
  (write-line (string-append "headings: "
                             (string-join (map (lambda (facing) (show (heading 4 facing (camera))))
                                               (list (new Vec3 (x 0.0) (y 0.0) (z 1.0))
                                                     (new Vec3 (x 1.0) (y 0.0) (z 0.0))
                                                     (new Vec3 (x 0.0) (y 0.0) (z -1.0))
                                                     (new Vec3 (x -1.0) (y 0.0) (z 0.0))
                                                     (new Vec3 (x 0.7) (y 0.0) (z 0.8))))
                                          " ")))
  (write-line (string-append "standing toward the viewer: "
                             (texture-text (pose (walk-book 7)
                                                 (Stand)
                                                 (new Vec3 (x 0.0) (y 0.0) (z 0.0))
                                                 (new Vec3 (x 0.0) (y 0.0) (z 1.0))
                                                 2.0
                                                 (camera)))))
  (write-line (string-append "strolling to the right: "
                             (texture-text (pose (walk-book 7)
                                                 (Stroll)
                                                 (new Vec3 (x 0.0) (y 0.0) (z 0.0))
                                                 (new Vec3 (x 1.0) (y 0.0) (z 0.0))
                                                 2.0
                                                 (camera)))))
  (write-line (string-append "slashing away: "
                             (texture-text (pose (universal-book 7)
                                                 (Slash)
                                                 (new Vec3 (x 0.0) (y 0.0) (z 0.0))
                                                 (new Vec3 (x 0.0) (y 0.0) (z -1.0))
                                                 2.0
                                                 (camera)))))
  (unit))
