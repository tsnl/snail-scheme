# Splats

A gaussian-splat viewer drawn with `(snail shell graphics splat)`, flown
through with the mouse and keys: drag to look, W, A, S and D to fly, Q and E
down and up, and the wheel for speed.

```sh
./snail-scheme build --release --target browser src/apps/splats/main.scm
python3 -m http.server 4193 --directory build/src/apps/splats/main
```

Open `http://127.0.0.1:4193` in a browser with WebGPU. The page opens on
one procedural ring of 20,000 gaussians, written three times, each copy on
its own row of the transforms table. Each frame poses the rows, so two rings
turn linked like a chain's while a third, smaller, tumbles around them; the
gaussians stay where they were written.

## A trained scene

A scene trained by 3D Gaussian Splatting takes the rings' place: the `.ply`
file the reference implementation writes, and [Train](../train/README.md)
with `cloud=PATH`, read by `(snail shell graphics ply)`. Drop it on the page, press O to pick files, or name it in the
page's address, `?cloud=ADDRESS`.

Such a scene stands in its reconstruction's frame, which has no up of its
own. The cameras that photographed it say which way is up: add the scene's
COLMAP `sparse/0/images.bin` to the files, or name it with
`&poses=ADDRESS`, whose last part must be `images.bin`. The cloud is turned
by its row of the transforms table so the mean of the cameras' ups is the
view's, and the view starts at the first camera, at a speed that suits
where the cameras stood. Without poses, up is COLMAP's own -y, and the view
starts back from the middle of the cloud.

A file is read whole before it is shown, so a large one takes a while:
Mip-NeRF 360's bicycle as [Train](../train/README.md) trains it, a 1 GB
file of 4,194,304 gaussians, took 22 seconds from a local server in Chrome,
and then flew at the display's 60 frames a second on an RTX 5090. Files
that cannot be shown leave the view as it was, and the page says why.

## Two renderers

T draws the splats tile by tile, by the renderer [Train](../train/README.md)
trains through, and again as quads. Every two seconds the console has the
frame rate and how long one frame's compute and render passes took on the
device, where it has timestamps. A page's times are rounded to 100 μs.

`compare.scm` draws a trained scene both ways on Node, at the views it was
photographed from. It times each frame on the device and compares the
images with each other and with the photographs:

```sh
./snail-scheme run --target node src/apps/splats/compare.scm \
  cloud=bicycle.ply scene=datasets/bicycle/ photos=images_4 views=8
```

`scene` is the COLMAP dataset's folder, ending in a slash, and `photos`
the folder of its photographs at the views' size, 1237 pixels wide unless
`width` says otherwise. `profile=1` also times each of the tiles' steps
alone. [The graphics chapter](../../../doc/book/graphics/plan.md#scans-sorts-and-gaussian-splats)
has bicycle's numbers.
