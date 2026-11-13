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

(define (olive) (→ Skin) (Skin "olive"))

(define (outfit) (→ Outfit)
  (Outfit (Some (Hair (HairStyle "bob") (HairColor "ginger")))
          (Some (Worn (Longsleeve) (Dye "teal")))
          (Some (Worn (Pants) (Dye "navy")))
          (Some (Worn (Shoes) (Dye "brown")))))

(define (describe (who (Option Character))) (→ String)
  (match who
    ((Some character)
     (string-append "dressed in " (show (length (● character sheets))) " layers"))
    ((None) "refused")))

(define (same-fingerprint? (a (Option Character)) (b (Option Character))) (→ Bool)
  (match (Pair a b)
    ((Pair (Some one) (Some other)) (= (fingerprint one) (fingerprint other)))
    (_ #f)))

;; A camera looking down -z: a figure facing +z faces the viewer, one
;; facing +x their right.
(define (camera) (→ Camera) (Camera (Vec3 0.0 5.0 10.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8)))

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
                                              (Outfit (None)
                                                      (None)
                                                      (Some (Worn (Pants) (Dye "green")))
                                                      (None))))))
  (write-line (string-append "shoes on the torso: "
                             (describe (dress (Female)
                                              (HumanFemale)
                                              (olive)
                                              (Outfit (None)
                                                      (Some (Worn (Shoes) (Dye "brown")))
                                                      (None)
                                                      (None))))))
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
                                                              (Skin "light")
                                                              (outfit)))
                                    "no"
                                    "yes"))))
    ((None) (write-line "refused")))
  (write-line (string-append "headings: "
                             (string-join (map (lambda (facing) (show (heading 4 facing (camera))))
                                               (list (Vec3 0.0 0.0 1.0)
                                                     (Vec3 1.0 0.0 0.0)
                                                     (Vec3 0.0 0.0 -1.0)
                                                     (Vec3 -1.0 0.0 0.0)
                                                     (Vec3 0.7 0.0 0.8)))
                                          " ")))
  (write-line (string-append "standing toward the viewer: "
                             (texture-text (pose (walk-book 7)
                                                 (Stand)
                                                 (Vec3 0.0 0.0 0.0)
                                                 (Vec3 0.0 0.0 1.0)
                                                 2.0
                                                 (camera)))))
  (write-line (string-append "strolling to the right: "
                             (texture-text (pose (walk-book 7)
                                                 (Stroll)
                                                 (Vec3 0.0 0.0 0.0)
                                                 (Vec3 1.0 0.0 0.0)
                                                 2.0
                                                 (camera)))))
  (write-line (string-append "slashing away: "
                             (texture-text (pose (universal-book 7)
                                                 (Slash)
                                                 (Vec3 0.0 0.0 0.0)
                                                 (Vec3 0.0 0.0 -1.0)
                                                 2.0
                                                 (camera)))))
  (unit))
