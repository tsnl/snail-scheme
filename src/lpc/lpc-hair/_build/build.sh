out_dir="../hair"


echo "STYLES"
# for hair in 'astarea' 'balding' 'betty' 'braid' 'buzzcut' 'curly-long' 'curly-short' 'george' 'half-up' 'halfmessy' 'high-ponytail' 'lidia' 'shura' 'spiked'; do
for hair in $(find . -maxdepth 1 -mindepth 1 -type d); do
	echo $hair

	for sex in 'male' 'female'; do
		lpctools arrange distribute --input $hair/*.png --output $out_dir/$hair/$sex.png --layout universal --offset reference_points_$sex.png --mask masks_$sex.png
		lpctools colors recolor --input $out_dir/$hair/$sex.png --mapping ./palettes.json
	done
done


preview_dir="../preview"

mkdir -p "$preview_dir/body"
mkdir -p "$preview_dir/tiles"


echo "BUILDING PREVIEW"
for hair in $(find "$out_dir" -maxdepth 1 -mindepth 1 -type d | sort); do
	echo $(basename $hair)
	for color in $(find "$hair/male" -maxdepth 1 -mindepth 1 | sort); do
		tilefile=$preview_dir/tiles/$(basename $hair)-$(basename $color)
		echo "$color > $tilefile"
		magick -extract 64x64+64+64 $color $tilefile
		outfile=$preview_dir/body/$(basename $hair)-$(basename $color)
		magick composite -gravity center "$tilefile" "$preview_dir/body.png"    "$outfile"
	done
	n_colors=$(ls "$hair/male" | wc -l)
done

montage -border 0 -geometry 64x64 -tile "$n_colors"x $preview_dir/body/*.png $preview_dir/preview.png

# echo "$preview_dir/body/"*.png
