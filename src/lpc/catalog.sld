;; What the LPC packs in this folder draw, and where: adult bodies and heads
;; from the character bases, hair from the hair pack, and garments from the
;; clothing updates and wulax's original sprites. The catalog names each
;; variant the way the pack's files do and gives, for each layer, the file
;; and region holding its walking rows and the color swaps that recolor it.
;; It also says which builds can wear each garment, and in which dyes.
;; Children, skeletons and zombies are not catalogued yet.
(define-library (lpc catalog)
  (export
   Build
   Male
   Female
   Teen
   Muscular
   Pregnant
   builds
   Head
   HumanMale
   HumanFemale
   HumanMaleElderly
   HumanFemaleElderly
   OrcMale
   OrcFemale
   LizardMale
   LizardFemale
   WolfMale
   WolfFemale
   Boarman
   Minotaur
   heads
   Skin
   Skin-name
   skins
   HairStyle
   HairStyle-name
   hair-styles
   HairColor
   HairColor-name
   hair-colors
   Dye
   Dye-name
   dyes
   Garment
   Longsleeve
   Shortsleeve
   Blouse
   Tunic
   Tanktop
   ScoopShirt
   Sleeveless
   Overalls
   Tabard
   Pants
   Skirt
   Leggings
   Shoes
   Boots
   Sandals
   garments
   Slot
   Torso
   Legs
   Feet
   garment-slot
   garment-dyes
   garment-builds
   Sheet
   Sheet-path
   Sheet-from
   Sheet-swaps
   body-sheet
   head-sheet
   hair-sheet
   garment-sheet)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell app)
   (lpc layout)
   (lpc skins))
  (begin

    ;; ---- Variants ----

    ;; Skins, hair styles, hair colors and dyes are names the packs' files
    ;; use; each list holds every one a pack draws.
    (struct Skin
      ((name String))
      (deriving Serialize Deserialize))

    (struct HairStyle
      ((name String))
      (deriving Serialize Deserialize))

    (struct HairColor
      ((name String))
      (deriving Serialize Deserialize))

    (struct Dye
      ((name String))
      (deriving Serialize Deserialize))

    (: skins (List Skin))
    (define skins
      (map Skin
           (list "amber"
                 "black"
                 "blue"
                 "bright_green"
                 "bronze"
                 "brown"
                 "dark_green"
                 "fur_black"
                 "fur_brown"
                 "fur_copper"
                 "fur_gold"
                 "fur_grey"
                 "fur_tan"
                 "fur_white"
                 "green"
                 "lavender"
                 "light"
                 "olive"
                 "pale_green"
                 "taupe"
                 "zombie_green")))

    (: hair-styles (List HairStyle))
    (define hair-styles
      (map HairStyle
           (list "afro"
                 "balding"
                 "bangs_bun"
                 "bob"
                 "bob_side_part"
                 "braid"
                 "braid2"
                 "buzzcut"
                 "cornrows"
                 "cowlick"
                 "cowlick_tall"
                 "curly_long"
                 "curly_short"
                 "curtains"
                 "curtains_long"
                 "dreadlocks_long"
                 "dreadlocks_short"
                 "flat_top_fade"
                 "flat_top_straight"
                 "half_up"
                 "halfmessy"
                 "high_and_tight"
                 "high_ponytail"
                 "idol"
                 "lob"
                 "long_band"
                 "long_center_part"
                 "long_messy"
                 "long_messy2"
                 "long_tied"
                 "messy3"
                 "mop"
                 "natural"
                 "part2"
                 "pigtails"
                 "pigtails_bangs"
                 "sara"
                 "spiked"
                 "spiked2"
                 "spiked_beehive"
                 "spiked_liberty"
                 "spiked_liberty2"
                 "spiked_porcupine"
                 "twists_fade"
                 "twists_straight")))

    (: hair-colors (List HairColor))
    (define hair-colors
      (map HairColor
           (list "ash"
                 "black"
                 "blonde"
                 "blue"
                 "carrot"
                 "chestnut"
                 "dark_brown"
                 "dark_gray"
                 "ginger"
                 "gold"
                 "gray"
                 "green"
                 "light_brown"
                 "navy"
                 "orange"
                 "pink"
                 "platinum"
                 "purple"
                 "raven"
                 "red"
                 "redhead"
                 "rose"
                 "sandy" "strawberry" "violet" "white")))

    (: dyes (List Dye))
    (define dyes
      (map Dye
           (list "black"
                 "blue"
                 "bluegray"
                 "brown"
                 "charcoal"
                 "forest"
                 "gray"
                 "green"
                 "lavender"
                 "leather"
                 "maroon"
                 "navy"
                 "orange"
                 "pink"
                 "purple"
                 "red"
                 "rose"
                 "sky"
                 "slate"
                 "tan"
                 "teal"
                 "walnut"
                 "white"
                 "yellow")))

    ;; ---- Bodies and heads ----

    ;; Adult bodies. Every one shares the male body's head and hand
    ;; positions, so any head and any hair fits any of them.
    (enum Build
      (Male)
      (Female)
      (Teen)
      (Muscular)
      (Pregnant)
      (deriving Serialize Deserialize))

    (: builds (List Build))
    (define builds
      (list (Male) (Female) (Teen) (Muscular) (Pregnant)))

    (: build-name (-> Build String))
    (define (build-name build)
      (match build
        ((Male) "male")
        ((Female) "female")
        ((Teen) "teen")
        ((Muscular) "muscular")
        ((Pregnant) "pregnant")))

    (enum Head
      (HumanMale)
      (HumanFemale)
      (HumanMaleElderly)
      (HumanFemaleElderly)
      (OrcMale)
      (OrcFemale)
      (LizardMale)
      (LizardFemale)
      (WolfMale)
      (WolfFemale)
      (Boarman)
      (Minotaur)
      (deriving Serialize Deserialize))

    (: heads (List Head))
    (define heads
      (list (HumanMale)
            (HumanFemale)
            (HumanMaleElderly)
            (HumanFemaleElderly)
            (OrcMale)
            (OrcFemale)
            (LizardMale)
            (LizardFemale)
            (WolfMale) (WolfFemale) (Boarman) (Minotaur)))

    ;; A head's folder, and the skin ramp its walking sheet is drawn in.
    ;; The pack recolors heads only for its smaller sheets, so the walking
    ;; rows are recolored here by swapping one ramp for another.
    (: head-folder (-> Head (Pair String String)))
    (define (head-folder head)
      (match head
        ((HumanMale) (Pair "human_male" "light"))
        ((HumanFemale) (Pair "human_female" "light"))
        ((HumanMaleElderly) (Pair "human_male_elderly" "light"))
        ((HumanFemaleElderly) (Pair "human_female_elderly" "light"))
        ((OrcMale) (Pair "orc_male" "green"))
        ((OrcFemale) (Pair "orc_female" "green"))
        ((LizardMale) (Pair "lizard_male" "green"))
        ((LizardFemale) (Pair "lizard_female" "green"))
        ((WolfMale) (Pair "wolf_male" "fur_brown"))
        ((WolfFemale) (Pair "wolf_female" "fur_brown"))
        ((Boarman) (Pair "boarman" "fur_brown"))
        ((Minotaur) (Pair "minotaur" "fur_tan"))))

    ;; ---- Sheets ----

    ;; Where a layer's walking rows are: a file, the region of it holding
    ;; them, and the swaps that recolor it.
    (struct Sheet
      ((path String)
       (from Rect)
       (swaps (List (Pair I32 I32)))))

    (define bases "src/lpc/lpc-character-bases-v3_1")

    (: universal (-> String Sheet))
    (define (universal path)
      (Sheet path walk-region (Nil)))

    (: body-sheet (-> Build Skin Sheet))
    (define (body-sheet build skin)
      (universal
       (string-append bases "/bodies/" (build-name build) "/universal/" (Skin-name skin) ".png")))

    ;; Each color of the head's own ramp becomes the color at the same place
    ;; in `skin`'s; a head already in that skin needs no swaps.
    (: head-sheet (-> Head Skin Sheet))
    (define (head-sheet head skin)
      (let ((folder (head-folder head)))
        (Sheet (string-append bases "/heads/" (Pair-first folder) "/universal.png") walk-region
               (filter (lambda (pair) (not (= (Pair-first pair) (Pair-second pair))))
                       (zip (ramp (Pair-second folder)) (ramp (Skin-name skin)))))))

    ;; Hair is drawn for male heads and female heads; female and pregnant
    ;; bodies wear the female cut.
    (: hair-sheet (-> Build HairStyle HairColor Sheet))
    (define (hair-sheet build style color)
      (let ((cut (match build ((Female) "female") ((Pregnant) "female") (_ "male"))))
        (universal (string-append "src/lpc/lpc-hair/hair/"
                                  (HairStyle-name style)
                                  "/"
                                  cut
                                  "/"
                                  (HairColor-name color)
                                  ".png"))))

    ;; ---- Garments ----

    (enum Garment
      (Longsleeve)
      (Shortsleeve)
      (Blouse)
      (Tunic)
      (Tanktop)
      (ScoopShirt)
      (Sleeveless)
      (Overalls)
      (Tabard)
      (Pants)
      (Skirt)
      (Leggings)
      (Shoes)
      (Boots)
      (Sandals)
      (deriving Serialize Deserialize))

    (: garments (List Garment))
    (define garments
      (list (Longsleeve)
            (Shortsleeve)
            (Blouse)
            (Tunic)
            (Tanktop)
            (ScoopShirt)
            (Sleeveless)
            (Overalls)
            (Tabard)
            (Pants)
            (Skirt)
            (Leggings) (Shoes) (Boots) (Sandals)))

    ;; Where a garment is worn.
    (enum Slot
      (Feet)
      (Legs)
      (Torso)
      (deriving Serialize Deserialize))

    (: garment-slot (-> Garment Slot))
    (define (garment-slot garment)
      (match garment
        ((Pants) (Legs))
        ((Skirt) (Legs))
        ((Leggings) (Legs))
        ((Shoes) (Feet))
        ((Boots) (Feet))
        ((Sandals) (Feet))
        (_ (Torso))))

    ;; A garment's folder in the clothing updates, and the builds it is drawn
    ;; for there.
    (: garment-folder (-> Garment (Pair String (List Build))))
    (define (garment-folder garment)
      (match garment
        ((Longsleeve) (Pair "torso/clothes/longsleeve" (list (Male) (Female) (Teen) (Pregnant))))
        ((Shortsleeve) (Pair "torso/clothes/shortsleeve" (list (Male) (Female) (Pregnant))))
        ((Blouse) (Pair "torso/clothes/blouse" (list (Female))))
        ((Tunic) (Pair "torso/clothes/tunic" (list (Female))))
        ((Tanktop) (Pair "torso/clothes/tanktop" (list (Female) (Pregnant))))
        ((ScoopShirt) (Pair "torso/clothes/scoop_shirt" (list (Female) (Pregnant))))
        ((Sleeveless) (Pair "torso/clothes/sleeveless" (list (Female) (Pregnant))))
        ((Overalls) (Pair "torso/aprons/overalls" (list (Male) (Female))))
        ((Tabard) (Pair "torso/jacket/tabard" (list (Male) (Female))))
        ((Pants) (Pair "legs/pants" (list (Female) (Teen) (Pregnant))))
        ((Skirt) (Pair "legs/skirts/plain" (list (Male) (Female))))
        ((Leggings) (Pair "legs/leggings" (list (Female))))
        ((Shoes) (Pair "feet/shoes" (list (Male) (Female))))
        ((Boots) (Pair "feet/boots" (list (Male) (Female))))
        ((Sandals) (Pair "feet/sandals" (list (Male) (Female))))))

    ;; Male pants come from wulax's original sprites, which draw them in one
    ;; greenish color on a sheet of walking rows alone.
    (define male-pants
      (Sheet "src/lpc/lpc_entry/png/walkcycle/LEGS_pants_greenish.png" (Rect 0 0 576 256) (Nil)))

    ;; No pack draws teen footwear, but a teen's feet stand close enough to
    ;; a man's that the male sheets fit.
    (: drawn-build (-> Garment Build Build))
    (define (drawn-build garment build)
      (match (Pair (garment-slot garment) build)
        ((Pair (Feet) (Teen)) (Male))
        (_ build)))

    ;; How a pack draws a garment for a build: in the clothing updates, in
    ;; every dye, on the sheets of a build; or on a single sheet, in one dye.
    (enum Drawing
      (Dyed ((folder String) (build Build)))
      (Single ((dye Dye) (sheet Sheet))))

    ;; How a garment is drawn for a build, or None where no pack draws it.
    ;; This is the one place that says what each build can wear.
    (: garment-drawing (-> Build Garment (Option Drawing)))
    (define (garment-drawing build garment)
      (match (Pair garment build)
        ((Pair (Pants) (Male)) (Some (Single (Dye "green") male-pants)))
        (_ (let ((folder (garment-folder garment)) (drawn (drawn-build garment build)))
             (if (any? (lambda (other) (string=? (build-name other) (build-name drawn)))
                       (Pair-second folder))
                 (Some (Dyed (Pair-first folder) drawn))
                 (None))))))

    ;; The dyes a build can wear a garment in, none where no pack draws it.
    (: garment-dyes (-> Build Garment (List Dye)))
    (define (garment-dyes build garment)
      (match (garment-drawing build garment)
        ((Some (Dyed _ _)) dyes)
        ((Some (Single dye _)) (list dye))
        ((None) (Nil))))

    ;; The builds that can wear a garment.
    (: garment-builds (-> Garment (List Build)))
    (define (garment-builds garment)
      (filter (lambda (build) (not (null? (garment-dyes build garment)))) builds))

    ;; The garment in `dye` on `build`, or None where no pack draws it so.
    (: garment-sheet (-> Build Garment Dye (Option Sheet)))
    (define (garment-sheet build garment dye)
      (match (garment-drawing build garment)
        ((Some (Dyed folder drawn))
         (if (any? (lambda (other) (string=? (Dye-name other) (Dye-name dye))) dyes)
             (Some (universal (string-append "src/lpc/lpc-clothing-updates/spritesheets/"
                                             folder
                                             "/"
                                             (build-name drawn)
                                             "/"
                                             (Dye-name dye)
                                             ".png")))
             (None)))
        ((Some (Single only sheet))
         (if (string=? (Dye-name only) (Dye-name dye)) (Some sheet) (None)))
        ((None) (None))))

    ))
