#!/bin/bash
# requires lpctools http://github.com/bluecarrot16/lpctools
# usage: 
# 	cd _build
# 	bash build.sh

# create palette mapping for each head, because some heads use different source palettes
mkdir -p palettes/skin
lpctools colors convert-mapping --input "palettes/skin.json" --output "palettes/skin/_human.json" --reindex "light"
lpctools colors convert-mapping --input "palettes/skin.json" --output "palettes/skin/_wolf.json" --reindex "fur_brown"
lpctools colors convert-mapping --input "palettes/skin.json" --output "palettes/skin/_boarman.json" --reindex "fur_brown"
lpctools colors convert-mapping --input "palettes/skin.json" --output "palettes/skin/_minotaur.json" --reindex "fur_tan"
lpctools colors convert-mapping --input "palettes/skin.json" --output "palettes/skin/_lizard.json" --reindex "green"
lpctools colors convert-mapping --input "palettes/skin.json" --output "palettes/skin/_orc.json" --reindex "green"



# no run animation for children
LAYOUTS=("universal" "jump" "idle" "sit" "run")
CHILD_LAYOUTS=("universal" "jump" "idle" "sit")

NO_RECOLORS=("zombie" "skeleton")

# build a complete set of heads for different bodies
mkdir -p ../heads
cd heads
for filename in *.png; do

	# get the filename before the extension
	head="${filename%.*}"
	echo $head

	# get the portion of the filename before the first underscore
	arr_head=(${head//_/ })
	palette="${arr_head[0]}"
	echo "-> palettes/skin/_$palette.json"

	# delete folder containing generated heads
	rm -r $head

	# unpack heads/$head.png (3x6 format) to heads/$head/{e,s,w,...}.png
	lpctools arrange unpack --input $filename --layout 'heads' --output-dir $head --pattern '%d-%n%f.png'

	# rename a few files due to current limitations in the formatting options for the `unpack` verb
	rename -v 's/-NoneNone//' $head/*.png
	rename -v 's/-cast1/-cast1-cast4/' $head/*.png
	rename -v 's/-cast2/-cast2-cast3/' $head/*.png

	# adults use a different frame for the last frame of the jump animation
	if [[ $head == *"child"* ]]; 
	then
		rename -v 's/-hurt1/-hurt1-jump4/' $head/*.png
	else
		rename -v 's/-hurt2/-hurt2-jump4/' $head/*.png
	fi

	# remove output files which will be replaced
	rm -r ../../heads/$head/{universal,jump}


	# child is handled differently because child heads are not applied to
	# adult bodies. 
	if [[ $head == *"child"* ]]; then
		for layout in ${CHILD_LAYOUTS[@]}; do
			lpctools arrange distribute \
				--input ./$head \
				--output ../../heads/$head/$layout.png \
				--layout $layout \
				--mask ../masks/$layout/masks-child.png \
				--offsets ../masks/$layout/offsets-child.png
		done
	else 

		# we USED to have to create a separate spritesheet for each body type; however
		# since v2.4 the adult sprites all have the same head positions

		for layout in ${LAYOUTS[@]}; do

			# male layout is used for everything now
			lpctools arrange distribute \
				--input ./$head \
				--output ../../heads/$head/$layout.png \
				--layout $layout \
				--mask ../masks/$layout/masks-male.png \
				--offsets ../masks/$layout/offsets-male.png

			# # muscular
			# lpctools arrange distribute \
			# 	--input ./$head \
			# 	--output ../../heads/$head/$layout/muscular.png \
			# 	--layout $layout \
			# 	--mask ../masks/$layout/masks-muscular.png \
			# 	--offsets ../masks/$layout/offsets-male.png

			# # female
			# lpctools arrange distribute \
			# 	--input ./$head \
			# 	--output ../../heads/$head/$layout/female.png \
			# 	--layout $layout \
			# 	--mask ../masks/$layout/masks-female.png \
			# 	--offsets ../masks/$layout/offsets-female.png

			# # pregnant
			# lpctools arrange distribute \
			# 	--input ./$head \
			# 	--output ../../heads/$head/$layout/pregnant.png \
			# 	--layout $layout \
			# 	--mask ../masks/$layout/masks-pregnant.png \
			# 	--offsets ../masks/$layout/offsets-female.png

			# # teen
			# lpctools arrange distribute \
			# 	--input ./$head \
			# 	--output ../../heads/$head/$layout/teen.png \
			# 	--layout $layout \
			# 	--mask ../masks/$layout/masks-female.png \
			# 	--offsets ../masks/$layout/offsets-female.png
		done
	fi

	# create recolors of heads
	for layout in ${LAYOUTS[@]}; do
		# if [ "$palette" != "skeleton" ]; then
		if [[ ! (" ${NO_RECOLORS[*]} " =~ " ${palette} ") ]]; then
			if test -f $body_type/$layout.png; then
				lpctools colors recolor --input ../../heads/$head/$layout.png --mapping ../palettes/skin/_$palette.json
			fi
		fi
	done
done

# recolor bodies to different skin colors
cd ../bodies
mkdir -p ../../bodies
cp -r ./* ../../bodies
cd ../../bodies
for body_type in */; do
	if [[ $body_type == *"child"* ]]; then
		_layouts=("${CHILD_LAYOUTS[@]}") 
	else
		_layouts=("${LAYOUTS[@]}") 
	fi
	
	# if [ ! ($body_type == *"skeleton"*) ]; then
	if [[ ! " ${NO_RECOLORS[*]} " =~ " ${body_type} " ]]; then
		for layout in ${_layouts[@]}; do
			if test -f $body_type/$layout.png; then
				echo "$body_type/$layout.png"
				lpctools colors recolor --input $body_type/$layout.png --mapping ../palettes/skin.json
			fi
		done
	fi
done

