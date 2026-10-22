;; The LPC libraries against the packs checked in under lib/lpc: every sheet
;; the catalog names exists, dressing refuses what no pack draws, layers come
;; in drawing order, heads are recolored ramp for ramp, and a pose picks the
;; strip a viewer should see.
(import
 (lofi base)
 (lofi io)
 (lofi app)
 (lofi sprite)
 (lpc layout)
 (lpc catalog)
 (lpc wardrobe))

(: missing (-> (List String) (List String) ! fs))
(define (missing paths)
  (filter (lambda (path) (not (file-exists? path))) paths))

(: report (-> String (List String) Unit ! console fs))
(define (report title paths)
  (write-line (string-append title ": " (show (length paths)) " sheets, missing " (show (length (missing paths))))))

(report "bodies" (concatenate (map (lambda (build) (map (lambda (skin) (Sheet-path (body-sheet build skin))) skins)) builds)))
(report "heads" (map (lambda (head) (Sheet-path (head-sheet head (list-ref skins 0)))) heads))
(report "garments"
        (concatenate (map (lambda (garment)
                            (map (lambda (build)
                                   (match (garment-sheet build garment (list-ref (garment-dyes build garment) 0))
                                     ((Some sheet) (Sheet-path sheet))
                                     ((None) "(no sheet)")))
                                 (garment-builds garment)))
                          garments)))
(report "hair" (concatenate (map (lambda (style) (map (lambda (build) (Sheet-path (hair-sheet build style (list-ref hair-colors 0)))) (list (Male) (Female))))
                                 hair-styles)))

(define olive (Skin "olive"))
(define outfit (Outfit (Some (Hair (HairStyle "bob") (HairColor "ginger"))) (Some (Worn (Longsleeve) (Dye "teal"))) (Some (Worn (Pants) (Dye "navy")))
                       (Some (Worn (Shoes) (Dye "brown")))))

(: describe (-> (Option Character) String))
(define (describe who)
  (match who
    ((Some character) (string-append "dressed in " (show (length (Character-sheets character))) " layers"))
    ((None) "refused")))

(write-line (string-append "female: " (describe (dress (Female) (HumanFemale) olive outfit))))
(write-line (string-append "male in navy pants: " (describe (dress (Male) (HumanMale) olive outfit))))
(write-line (string-append "male in green pants: "
                           (describe (dress (Male) (HumanMale) olive (Outfit (None) (None) (Some (Worn (Pants) (Dye "green"))) (None))))))
(write-line (string-append "shoes on the torso: "
                           (describe (dress (Female) (HumanFemale) olive (Outfit (None) (Some (Worn (Shoes) (Dye "brown"))) (None) (None))))))

(: same-fingerprint? (-> (Option Character) (Option Character) Bool))
(define (same-fingerprint? a b)
  (match (Pair a b)
    ((Pair (Some one) (Some other)) (= (fingerprint one) (fingerprint other)))
    (_ #f)))

(match (dress (Female) (HumanFemale) olive outfit)
  ((Some who)
   (for-each (lambda (sheet) (write-line (string-append "  " (substring (Sheet-path sheet) 8 (string-length (Sheet-path sheet)))
                                                        " swaps " (show (length (Sheet-swaps sheet))))))
             (Character-sheets who))
   (write-line (string-append "same character, same fingerprint: "
                              (if (same-fingerprint? (Some who) (dress (Female) (HumanFemale) olive outfit)) "yes" "no")))
   (write-line (string-append "another skin, another fingerprint: "
                              (if (same-fingerprint? (Some who) (dress (Female) (HumanFemale) (Skin "light") outfit)) "no" "yes"))))
  ((None) (write-line "refused")))

;; A camera looking down -z: a figure facing +z faces the viewer, one
;; facing +x their right.
(define camera (Camera (Vec3 0.0 5.0 10.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8)))

(write-line (string-append "headings: "
                           (string-join (map (lambda (facing) (show (heading 4 facing camera)))
                                             (list (Vec3 0.0 0.0 1.0) (Vec3 1.0 0.0 0.0) (Vec3 0.0 0.0 -1.0) (Vec3 -1.0 0.0 0.0) (Vec3 0.7 0.0 0.8)))
                                        " ")))

(: texture-text (-> Item String))
(define (texture-text item)
  (match (Material-texture (Item-material item))
    ((Some (Texture picture region frames period))
     (string-append "picture " (show picture) " at " (show (Rect-x region)) "," (show (Rect-y region)) ", " (show frames) " frames"))
    ((None) "untextured")))

(write-line (string-append "standing toward the viewer: " (texture-text (pose (walk-book 7) (Stand) (Vec3 0.0 0.0 0.0) (Vec3 0.0 0.0 1.0) 2.0 camera))))
(write-line (string-append "strolling to the right: " (texture-text (pose (walk-book 7) (Stroll) (Vec3 0.0 0.0 0.0) (Vec3 1.0 0.0 0.0) 2.0 camera))))
(write-line (string-append "slashing away: " (texture-text (pose (universal-book 7) (Slash) (Vec3 0.0 0.0 0.0) (Vec3 0.0 0.0 -1.0) 2.0 camera))))
