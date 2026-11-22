;; The LPC libraries against the packs checked in under src/lpc: every sheet
;; the catalog names exists, dressing refuses what no pack draws, layers come
;; in drawing order, heads are recolored ramp for ramp, and a spritebook
;; picks the heading a viewer should see and the cell its strip shows.
(import
 (snail core base)
 (snail core io)
 (only (snail shell graphics atlas) Rect)
 (snail shell sprite)
 (lpc layout)
 (lpc catalog)
 (lpc wardrobe))

(define (missing (fs Fs) (paths (List String))) (→ (List String)) (! mut)
  (filter (lambda (path) (not (file-exists? fs path))) paths))

(define (report (fs Fs) (out OutputPort) (title String) (paths (List String))) (→ Unit) (! mut)
  (write-line out (string-append title
                             ": "
                             (show (length paths))
                             " sheets, missing "
                             (show (length (missing fs paths))))))

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

(define (cell-text (cell Rect)) (→ String)
  (string-append "cell at " (show (● cell x)) "," (show (● cell y))))

(define (main (fs Fs) (out OutputPort)) (→ Unit) (! mut)

  (report fs out "bodies"
          (concatenate
           (map (lambda (build) (map (lambda (skin) (● (body-sheet build skin) path)) skins))
                builds)))
  (report fs out "heads" (map (lambda (head) (● (head-sheet head (list-ref skins 0)) path)) heads))
  (report fs out "garments"
          (concatenate (map (lambda (garment)
                              (map (lambda (build)
                                     (match (garment-sheet build
                                                           garment
                                                           (list-ref (garment-dyes build garment)
                                                                     0))
                                       ((Some sheet) (● sheet path))
                                       ((None) "(no sheet)")))
                                   (garment-builds garment)))
                            garments)))
  (report fs out "hair"
          (concatenate (map (lambda (style)
                              (map (lambda (build)
                                     (● (hair-sheet build style (list-ref hair-colors 0)) path))
                                   (list (Male) (Female))))
                            hair-styles)))
  (write-line out (string-append "female: " (describe (dress (Female) (HumanFemale) (olive) (outfit)))))
  (write-line out
   (string-append "male in navy pants: " (describe (dress (Male) (HumanMale) (olive) (outfit)))))
  (write-line out (string-append "male in green pants: "
                             (describe (dress (Male)
                                              (HumanMale)
                                              (olive)
                                              (new Outfit (hair (None))
                                                   (torso (None))
                                                   (legs (Some (new Worn
                                                                 (garment (Pants))
                                                                 (dye (new Dye (name "green"))))))
                                                   (feet (None)))))))
  (write-line out (string-append "shoes on the torso: "
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
                 (write-line out (string-append "  "
                                            (substring (● sheet path)
                                                       8
                                                       (string-length (● sheet path)))
                                            " swaps " (show (length (● sheet swaps))))))
               (● who sheets))
     (write-line out (string-append "same character, same fingerprint: "
                                (if (same-fingerprint? (Some who)
                                                       (dress (Female)
                                                              (HumanFemale)
                                                              (olive)
                                                              (outfit)))
                                    "yes"
                                    "no")))
     (write-line out (string-append "another skin, another fingerprint: "
                                (if (same-fingerprint? (Some who)
                                                       (dress (Female)
                                                              (HumanFemale)
                                                              (new Skin (name "light"))
                                                              (outfit)))
                                    "no"
                                    "yes"))))
    ((None) (write-line out "refused")))
  ;; Down the screen faces the viewer, +x their right.
  (write-line out (string-append "headings: "
                             (string-join (map (lambda (facing)
                                                 (show
                                                  (heading 4 (● facing first) (● facing second))))
                                               (list (new Pair (first 0.0) (second -1.0))
                                                     (new Pair (first 1.0) (second 0.0))
                                                     (new Pair (first 0.0) (second 1.0))
                                                     (new Pair (first -1.0) (second 0.0))
                                                     (new Pair (first 0.7) (second -0.8))))
                                          " ")))
  (write-line out (string-append "standing toward the viewer: "
                             (cell-text (cell-at (walk-book 7) (Stand) 0 5000))))
  (write-line out (string-append "strolling to the right, 200 ms in: "
                             (cell-text (cell-at (walk-book 7) (Stroll) 1 200))))
  (write-line out (string-append "slashing away, a full cycle in: "
                             (cell-text (cell-at (universal-book 7) (Slash) 2 480))))
  (unit))
