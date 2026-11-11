;; How the people of the prototypes look: an LPC character for each of the
;; rumor mill's residents and for the favor ledger's rivals. Looks are
;; dealt from a fixed seed per person, so everyone looks the same in every
;; game and can be recognized across them. Each audience dresses in its own
;; colors: warm in the Market, workwear in the Docks, dark in the Tower.
(define-library (hearsay cast)
  (export
   resident
   rival
   everyone
   person-picture
   rival-picture)
  (import
   (snail core base)
   (snail shell random)
   (lpc catalog)
   (lpc wardrobe)
   (only (hearsay mill) person-count audience-of)
   (only (hearsay ledger) vee kit))
  (begin

    ;; ---- Dealing ----

    ;; One item of a list, and the generator after the draw.
    (define (deal (random Random) (items (List T))) (→ (Pair T Random)) (∀ T) (⊨ (Copy T))
      (Pair (list-ref items (random-below random (length items))) (random-next random)))

    (define (names->dyes (names (List String))) (→ (List Dye))
      (map Dye names))

    ;; ---- Wardrobe ----

    (define (audience-dyes (audience I64)) (→ (List Dye))
      (names->dyes (list-ref (list (list "maroon" "orange" "teal" "rose")
                                   (list "forest" "brown" "slate" "tan")
                                   (list "charcoal" "navy" "black" "white"))
                             audience)))

    (define (build-heads (build Build)) (→ (List Head))
      (match build
        ((Female) (list (HumanFemale) (HumanFemale) (HumanFemale) (HumanFemaleElderly)))
        (_ (list (HumanMale) (HumanMale) (HumanMale) (HumanMaleElderly)))))

    (define (elderly? (head Head)) (→ Bool)
      (match head
        ((HumanMaleElderly) #t)
        ((HumanFemaleElderly) #t)
        (_ #f)))

    (define human-skins (map Skin (list "light" "amber" "olive" "taupe" "bronze" "brown" "black")))

    (define cuts
      (map HairStyle
           (list "bob"
                 "buzzcut"
                 "curly_short"
                 "long_messy"
                 "high_ponytail"
                 "afro"
                 "cowlick"
                 "bangs_bun")))

    (define (hair-shades (head Head)) (→ (List HairColor))
      (map HairColor
           (if (elderly? head)
               (list "gray" "white")
               (list "black" "dark_brown" "chestnut" "blonde" "ginger"))))

    (define (tops (build Build)) (→ (List Garment))
      (match build
        ((Male) (list (Longsleeve) (Shortsleeve) (Overalls) (Tabard)))
        ((Female) (list (Longsleeve) (Blouse) (Tunic) (Tanktop)))
        (_ (list (Longsleeve)))))

    (define (bottoms (build Build)) (→ (List Garment))
      (match build
        ((Female) (list (Pants) (Skirt) (Leggings)))
        (_ (list (Pants)))))

    (define footwear (list (Shoes) (Boots)))

    ;; Dark enough to tell from skin and floor at sprite size.
    (define shoe-dyes (map Dye (list "black" "charcoal" "walnut")))

    ;; A garment in the dye dealt, if the catalog draws it in that for the
    ;; build, and otherwise in the first dye it does: male pants come only
    ;; in green.
    (define (worn-in (build Build) (garment Garment) (dye Dye)) (→ Worn)
      (let ((drawn (garment-dyes build garment)))
        (Worn garment
              (if (any? (lambda (other) (string=? (● other name) (● dye name))) drawn)
                  dye
                  (match drawn
                    ((Cons first _) first)
                    ((Nil) dye))))))

    ;; Every look dealt here is one the catalog draws, so dressing never
    ;; fails. Were the tables to drift from the catalog, building (hearsay
    ;; art), which dresses everyone, would stop here.
    (define (dressed (build Build) (head Head) (skin Skin) (outfit Outfit)) (→ Character)
      (match (dress build head skin outfit)
        ((Some character) character)
        ((None) (panic "the cast wears something the catalog does not draw"))))

    ;; ---- People ----

    ;; A character dealt from `seed`, dressed in `palette`.
    (define (dealt (seed I64) (palette (List Dye))) (→ Character)
      (let* ((r (make-random seed))
             (build (deal r (list (Male) (Female) (Teen))))
             (head (deal (● build second) (build-heads (● build first))))
             (skin (deal (● head second) human-skins)) (cut (deal (● skin second) cuts))
             (shade (deal (● cut second) (hair-shades (● head first)))))
        (outfitted (● build first)
                   (● head first)
                   (● skin first)
                   (Hair (● cut first) (● shade first))
                   palette
                   (● shade second))))

    (define (outfitted (build Build)
                       (head Head)
                       (skin Skin)
                       (hair Hair)
                       (palette (List Dye))
                       (r Random))
      (→ Character)
      (let* ((top (deal r (tops build))) (top-dye (deal (● top second) palette))
             (bottom (deal (● top-dye second) (bottoms build)))
             (bottom-dye (deal (● bottom second) palette))
             (shoe (deal (● bottom-dye second) footwear))
             (shoe-dye (deal (● shoe second) shoe-dyes)))
        (dressed build head skin
                 (Outfit (Some hair) (Some (worn-in build (● top first) (● top-dye first)))
                         (Some (worn-in build (● bottom first) (● bottom-dye first)))
                         (Some (worn-in build (● shoe first) (● shoe-dye first)))))))

    ;; Resident `person` of the rumor mill, dressed in their audience's
    ;; colors.
    (define (resident (person I64)) (→ Character)
      (dealt (+ 1000 (* 7919 person)) (audience-dyes (audience-of person))))

    ;; The favor ledger's rivals, by fixer: Vee, and otherwise Kit.
    (define (rival (who I64)) (→ Character)
      (if (= who vee)
          (dressed (Female) (HumanFemale) (Skin "bronze")
                   (Outfit (Some (Hair (HairStyle "high_ponytail") (HairColor "raven")))
                           (Some (Worn (Tunic) (Dye "purple")))
                           (Some (Worn (Leggings) (Dye "black")))
                           (Some (Worn (Boots) (Dye "black")))))
          (dressed (Male) (HumanMale) (Skin "light")
                   (Outfit (Some (Hair (HairStyle "spiked") (HairColor "carrot")))
                           (Some (Worn (Tabard) (Dye "red")))
                           (Some (Worn (Pants) (Dye "green")))
                           (Some (Worn (Shoes) (Dye "black")))))))

    ;; Everyone drawn, for embedding their art.
    (define everyone (→ (List Character))
      (append (map resident (iota person-count)) (list (rival vee) (rival kit))))

    ;; ---- Pictures ----

    ;; The screens key the pictures they compose of the cast: 100 + p for
    ;; resident p, and 200 + f for the rival who is fixer f.
    (define (person-picture (person I64)) (→ I32)
      (i64->i32 (+ 100 person)))

    (define (rival-picture (who I64)) (→ I32)
      (i64->i32 (+ 200 who)))

    ))
