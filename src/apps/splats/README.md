# Splats

A gaussian-splat viewer drawn with `(snail shell graphics splat)`: one
procedural ring of 20,000 gaussians, written three times, each copy on its
own row of the transforms table. Each frame poses the rows, so two rings
turn linked like a chain's while a third, smaller, tumbles around them; the
gaussians stay where they were written. Drag to orbit and use the wheel to
come nearer.

```sh
./snail-scheme build --release --target browser src/apps/splats/main.scm
python3 -m http.server 4193 --directory build/src/apps/splats/main
```

Open `http://127.0.0.1:4193` in a browser with WebGPU. A trained 3D
Gaussian Splatting scene reads into a cloud with `(snail shell graphics
ply)`'s `read-ply`; the viewer has no way to fetch one yet.
