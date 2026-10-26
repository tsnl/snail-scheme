set -x
# assemble combinations of heads and bodies,  compare to BenCreating's original 
# bases https://opengameart.org/content/lpc-character-bases to see where our 
# method has created differences


# composite (layer) heads onto bodies
# humans first since they use hte ivory palettes which are the default
convert bodies/universal/male.png ../heads/human-male/universal/male.png -gravity center -background None -layers Flatten ../testing/human-male.png
convert bodies/universal/female.png ../heads/human-female/universal/female.png -gravity center -background None -layers Flatten ../testing/human-female.png
convert bodies/universal/teen.png ../heads/human-female/universal/teen.png -gravity center -background None -layers Flatten ../testing/human-teen.png
convert bodies/universal/child.png ../heads/human-child/universal/child.png -gravity center -background None -layers Flatten ../testing/human-child.png
convert bodies/universal/pregnant.png ../heads/human-female/universal/pregnant.png -gravity center -background None -layers Flatten ../testing/human-pregnant.png
convert bodies/universal/muscular.png ../heads/human-male/universal/muscular.png -gravity center -background None -layers Flatten ../testing/human-muscular.png

# these have palettes named for their body type, and have different heads for male/female
for body_type in "lizard" "wolf" "orc"; do
	convert bodies/universal/male/$body_type.png ../heads/$body_type-male/universal/male.png -gravity center -background None -layers Flatten ../testing/$body_type-male.png
	convert bodies/universal/muscular/$body_type.png ../heads/$body_type-male/universal/muscular.png -gravity center -background None -layers Flatten ../testing/$body_type-muscular.png
	convert bodies/universal/female/$body_type.png ../heads/$body_type-female/universal/female.png -gravity center -background None -layers Flatten ../testing/$body_type-female.png
	convert bodies/universal/pregnant/$body_type.png ../heads/$body_type-female/universal/pregnant.png -gravity center -background None -layers Flatten ../testing/$body_type-pregnant.png

	convert bodies/universal/teen/$body_type.png ../heads/$body_type-female/universal/female.png -gravity center -background None -layers Flatten ../testing/$body_type-teen.png
	convert bodies/universal/child/$body_type.png ../heads/$body_type-child/universal/child.png -gravity center -background None -layers Flatten ../testing/$body_type-child.png
done

# only one kind of head for different adult sexes
# not... uh... sexually dimorphic? 
for body_type in "minotaur" "boarman"; do
	convert bodies/universal/male/$body_type.png ../heads/$body_type/universal/male.png -gravity center -background None -layers Flatten ../testing/$body_type-male.png
	convert bodies/universal/muscular/$body_type.png ../heads/$body_type/universal/muscular.png -gravity center -background None -layers Flatten ../testing/$body_type-muscular.png
	convert bodies/universal/female/$body_type.png ../heads/$body_type/universal/female.png -gravity center -background None -layers Flatten ../testing/$body_type-female.png
	convert bodies/universal/pregnant/$body_type.png ../heads/$body_type/universal/pregnant.png -gravity center -background None -layers Flatten ../testing/$body_type-pregnant.png

	convert bodies/universal/teen/$body_type.png ../heads/$body_type/universal/female.png -gravity center -background None -layers Flatten ../testing/$body_type-teen.png
	convert bodies/universal/child/$body_type.png ../heads/$body_type-child/universal/child.png -gravity center -background None -layers Flatten ../testing/$body_type-child.png
done


# make comparison (diff) images and gifs
EXPECT='../testing/lpc-character-bases/'

TEST_CASES=(
"human-male::$EXPECT/Human/Male"
"human-female::$EXPECT/Human/Female"
"human-pregnant::$EXPECT/Human/Female Pregnant"
"human-muscular::$EXPECT/Human/Male Muscular"
"human-teen::$EXPECT/Human/Teen"
"human-child::$EXPECT/Human/Child"
"lizard-male::$EXPECT/Humanoid Animals/Lizardman/Male"
"lizard-female::$EXPECT/Humanoid Animals/Lizardman/Female"
"lizard-pregnant::$EXPECT/Humanoid Animals/Lizardman/Female Pregnant"
"wolf-male::$EXPECT/Humanoid Animals/Wolfman/Male"
"wolf-female::$EXPECT/Humanoid Animals/Wolfman/Female"
"wolf-pregnant::$EXPECT/Humanoid Animals/Wolfman/Female Pregnant"
"orc-male::$EXPECT/Orc/Male"
"orc-female::$EXPECT/Orc/Female"
"orc-pregnant::$EXPECT/Orc/Female Pregnant"
)

for index in "${TEST_CASES[@]}"; do
    TEST_CASE="${index%%::*}"
    EXPECTED="${index##*::}/Universal.png"
	# EXPECTED="${TEST_CASES[$TEST_CASE]}/Universal.png"
	echo $TEST_CASE
	echo $EXPECTED
	ACTUAL="../testing/$TEST_CASE.png"
	DIFF="../testing/$TEST_CASE-diff.png"
	GIFF="../testing/$TEST_CASE-diff.gif"
	compare "$EXPECTED" "$ACTUAL" "$DIFF"	
	convert -delay 100 "$DIFF" "$ACTUAL" "$EXPECTED" -loop 0 "$GIFF"
done 


# construct preview image

# preview_dir="../testing/preview"
# mkdir -p $preview_dir

# PREVIEWS=(
# "human-male"
# "human-female"
# "human-pregnant"
# "human-muscular"
# "human-teen"
# "human-child"
# "lizard-male"
# "lizard-female"
# "lizard-pregnant"
# "lizard-muscular"
# "lizard-teen"
# "lizard-child"
# "wolf-male"
# "wolf-female"
# "wolf-pregnant"
# "wolf-muscular"
# "wolf-teen"
# "wolf-child"
# "orc-male"
# "orc-female"
# "orc-pregnant"
# "orc-muscular"
# "orc-teen"
# "orc-child"
# "minotaur-male"
# "minotaur-female"
# "minotaur-pregnant"
# "minotaur-muscular"
# "minotaur-teen"
# "minotaur-child"
# "boarman-male"
# "boarman-female"
# "boarman-pregnant"
# "boarman-muscular"
# "boarman-teen"
# "boarman-child"
# )

# for body in "${PREVIEWS[@]}"; do

# 	tilefile="$preview_dir/$body.png"
# 	magick -extract 32x64+16+640 "../testing/$body.png" $tilefile
# done

# n_cols=6
# montage -border 0 -geometry 32x64 -gravity Center -tile "$n_cols"x $preview_dir/*.png ../testing/preview.png



# compare $EXPECT/Human/Male/Universal.png ../testing/human-male.png ../testing/human-male-diff.png
# compare $EXPECT/Human/Female/Universal.png ../testing/human-female.png ../testing/human-female-diff.png
# compare $EXPECT/Human/Female\ Pregnant/Universal.png ../testing/human-pregnant.png ../testing/human-pregnant-diff.png

# compare $EXPECT/Humanoid\ Animals/Lizardman/Male/Universal.png  ../testing/lizard-male.png ../testing/lizard-male-diff.png
# compare $EXPECT/Humanoid\ Animals/Lizardman/Female/Universal.png  ../testing/lizard-female.png ../testing/lizard-female-diff.png
# compare $EXPECT/Humanoid\ Animals/Lizardman/Female\ Pregnant/Universal.png  ../testing/lizard-pregnant.png ../testing/lizard-pregnant-diff.png
# convert -delay 50 $EXPECT/Humanoid\ Animals/Lizardman/Female\ Pregnant/Universal.png ../testing/lizard-pregnant.png ../testing/lizard-pregnant-diff.png -loop 0 ../testing/lizard-pregnant-diff.gif
# 
# 



