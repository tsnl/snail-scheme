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
   skins
   HairStyle
   hair-styles
   HairColor
   hair-colors
   Dye
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
    (record Skin
      ((name String))
      (deriving Serialize Deserialize))

    (record HairStyle
      ((name String))
      (deriving Serialize Deserialize))

    (record HairColor
      ((name String))
      (deriving Serialize Deserialize))

    (record Dye
      ((name String))
      (deriving Serialize Deserialize))

    (define (skins) (→ (List Skin))
      (map (lambda (name) (new Skin (name name)))
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

    (define (hair-styles) (→ (List HairStyle))
      (map (lambda (name) (new HairStyle (name name)))
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

    (define (hair-colors) (→ (List HairColor))
      (map (lambda (name) (new HairColor (name name)))
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

    (define (dyes) (→ (List Dye))
      (map (lambda (name) (new Dye (name name)))
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

    (define (builds) (→ (List Build))
      (list (Male) (Female) (Teen) (Muscular) (Pregnant)))

    (define (build-name (build Build)) (→ String)
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

    (define (heads) (→ (List Head))
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
    (define (head-folder (head Head)) (→ (Pair String String))
      (match head
        ((HumanMale) (new Pair (first "human_male") (second "light")))
        ((HumanFemale) (new Pair (first "human_female") (second "light")))
        ((HumanMaleElderly) (new Pair (first "human_male_elderly") (second "light")))
        ((HumanFemaleElderly) (new Pair (first "human_female_elderly") (second "light")))
        ((OrcMale) (new Pair (first "orc_male") (second "green")))
        ((OrcFemale) (new Pair (first "orc_female") (second "green")))
        ((LizardMale) (new Pair (first "lizard_male") (second "green")))
        ((LizardFemale) (new Pair (first "lizard_female") (second "green")))
        ((WolfMale) (new Pair (first "wolf_male") (second "fur_brown")))
        ((WolfFemale) (new Pair (first "wolf_female") (second "fur_brown")))
        ((Boarman) (new Pair (first "boarman") (second "fur_brown")))
        ((Minotaur) (new Pair (first "minotaur") (second "fur_tan")))))

    ;; ---- Sheets ----

    ;; Where a layer's walking rows are: a file, the region of it holding
    ;; them, and the swaps that recolor it.
    (record Sheet
      ((path String)
       (from Rect)
       (swaps (List (Pair I32 I32)))))

    (define (bases) (→ String) "src/lpc/lpc-character-bases-v3_1")

    (define (universal (path String)) (→ Sheet)
      (new Sheet (path path) (from (walk-region)) (swaps (Nil))))

    (define (body-sheet (build Build) (skin Skin)) (→ Sheet)
      (universal
       (string-append (bases) "/bodies/" (build-name build) "/universal/" (● skin name) ".png")))

    ;; Each color of the head's own ramp becomes the color at the same place
    ;; in `skin`'s; a head already in that skin needs no swaps.
    (define (head-sheet (head Head) (skin Skin)) (→ Sheet)
      (let ((folder (head-folder head)))
        (new Sheet
          (path (string-append (bases) "/heads/" (● folder first) "/universal.png"))
          (from (walk-region))
          (swaps (filter (lambda (pair) (not (= (● pair first) (● pair second))))
                         (zip (ramp (● folder second)) (ramp (● skin name))))))))

    ;; Hair is drawn for male heads and female heads; female and pregnant
    ;; bodies wear the female cut.
    (define (hair-sheet (build Build) (style HairStyle) (color HairColor)) (→ Sheet)
      (let ((cut (match build ((Female) "female") ((Pregnant) "female") (_ "male"))))
        (universal (string-append "src/lpc/lpc-hair/hair/"
                                  (● style name)
                                  "/"
                                  cut
                                  "/"
                                  (● color name)
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

    (define (garments) (→ (List Garment))
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

    (define (garment-slot (garment Garment)) (→ Slot)
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
    (define (garment-folder (garment Garment)) (→ (Pair String (List Build)))
      (match garment
        ((Longsleeve)
         (new Pair
           (first "torso/clothes/longsleeve")
           (second (list (Male) (Female) (Teen) (Pregnant)))))
        ((Shortsleeve)
         (new Pair (first "torso/clothes/shortsleeve") (second (list (Male) (Female) (Pregnant)))))
        ((Blouse) (new Pair (first "torso/clothes/blouse") (second (list (Female)))))
        ((Tunic) (new Pair (first "torso/clothes/tunic") (second (list (Female)))))
        ((Tanktop) (new Pair (first "torso/clothes/tanktop") (second (list (Female) (Pregnant)))))
        ((ScoopShirt)
         (new Pair (first "torso/clothes/scoop_shirt") (second (list (Female) (Pregnant)))))
        ((Sleeveless)
         (new Pair (first "torso/clothes/sleeveless") (second (list (Female) (Pregnant)))))
        ((Overalls) (new Pair (first "torso/aprons/overalls") (second (list (Male) (Female)))))
        ((Tabard) (new Pair (first "torso/jacket/tabard") (second (list (Male) (Female)))))
        ((Pants) (new Pair (first "legs/pants") (second (list (Female) (Teen) (Pregnant)))))
        ((Skirt) (new Pair (first "legs/skirts/plain") (second (list (Male) (Female)))))
        ((Leggings) (new Pair (first "legs/leggings") (second (list (Female)))))
        ((Shoes) (new Pair (first "feet/shoes") (second (list (Male) (Female)))))
        ((Boots) (new Pair (first "feet/boots") (second (list (Male) (Female)))))
        ((Sandals) (new Pair (first "feet/sandals") (second (list (Male) (Female)))))))

    ;; Male pants come from wulax's original sprites, which draw them in one
    ;; greenish color on a sheet of walking rows alone.
    (define (male-pants) (→ Sheet)
      (new Sheet
        (path "src/lpc/lpc_entry/png/walkcycle/LEGS_pants_greenish.png")
        (from (new Rect (x 0) (y 0) (width 576) (height 256)))
        (swaps (Nil))))

    ;; No pack draws teen footwear, but a teen's feet stand close enough to
    ;; a man's that the male sheets fit.
    (define (drawn-build (garment Garment) (build Build)) (→ Build)
      (match (new Pair (first (garment-slot garment)) (second build))
        ((Pair (Feet) (Teen)) (Male))
        (_ build)))

    ;; How a pack draws a garment for a build: in the clothing updates, in
    ;; every dye, on the sheets of a build; or on a single sheet, in one dye.
    (enum Drawing
      (Dyed ((folder String) (build Build)))
      (Single ((dye Dye) (sheet Sheet))))

    ;; How a garment is drawn for a build, or None where no pack draws it.
    ;; This is the one place that says what each build can wear.
    (define (garment-drawing (build Build) (garment Garment)) (→ (Option Drawing))
      (match (new Pair (first garment) (second build))
        ((Pair (Pants) (Male)) (Some (Single (new Dye (name "green")) (male-pants))))
        (_ (let ((folder (garment-folder garment)) (drawn (drawn-build garment build)))
             (if (any? (lambda (other) (string=? (build-name other) (build-name drawn)))
                       (● folder second))
                 (Some (Dyed (● folder first) drawn))
                 (None))))))

    ;; The dyes a build can wear a garment in, none where no pack draws it.
    (define (garment-dyes (build Build) (garment Garment)) (→ (List Dye))
      (match (garment-drawing build garment)
        ((Some (Dyed _ _)) (dyes))
        ((Some (Single dye _)) (list dye))
        ((None) (Nil))))

    ;; The builds that can wear a garment.
    (define (garment-builds (garment Garment)) (→ (List Build))
      (filter (lambda (build) (not (null? (garment-dyes build garment)))) (builds)))

    ;; The garment in `dye` on `build`, or None where no pack draws it so.
    (define (garment-sheet (build Build) (garment Garment) (dye Dye)) (→ (Option Sheet))
      (match (garment-drawing build garment)
        ((Some (Dyed folder drawn))
         (if (any? (lambda (other) (string=? (● other name) (● dye name))) (dyes))
             (Some (universal (string-append "src/lpc/lpc-clothing-updates/spritesheets/"
                                             folder
                                             "/"
                                             (build-name drawn)
                                             "/"
                                             (● dye name)
                                             ".png")))
             (None)))
        ((Some (Single only sheet))
         (if (string=? (● only name) (● dye name)) (Some sheet) (None)))
        ((None) (None))))

    ))
