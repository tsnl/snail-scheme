"""Prepare the shared shot and capture scene-linear Cycles films or render timings."""

import argparse
import json
import math
import sys
import tempfile
from pathlib import Path
from time import perf_counter

import bpy
import numpy as np
from mathutils import Vector


def surface(name, rgb, roughness, metal=0, emission=0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    p = material.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metal
    p.inputs["IOR"].default_value = 1.5
    if emission:
        p.inputs["Emission Color"].default_value = (1, 0.91, 0.78, 1)
        p.inputs["Emission Strength"].default_value = emission
    return material


def quad(name, corners, material):
    data = bpy.data.meshes.new(name)
    data.from_pydata(corners, [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(material)


def fixture():
    grey = surface("Plaster", (0.55, 0.55, 0.55), 0.85)
    red = surface("Red wall", (0.55, 0.085, 0.05), 0.85)
    quad("Floor", [(-3, -6, 0), (3, -6, 0), (3, 2, 0), (-3, 2, 0)], grey)
    quad("Rear", [(-3, 2, 0), (3, 2, 0), (3, 2, 3.4), (-3, 2, 3.4)], grey)
    quad("Side", [(-3, -3, 0), (-3, 2, 0), (-3, 2, 3.4), (-3, -3, 3.4)], red)
    # A downward-facing mesh emitter is shared by both light samplers.
    quad(
        "Softbox",
        [(-1.3, -0.7, 2.8), (-1.3, 0.2, 2.8), (-0.1, 0.2, 2.8), (-0.1, -0.7, 2.8)],
        surface("Emitter", (0, 0, 0), 0.5, emission=6),
    )
    for x, material in [
        (-0.76, surface("Clay", (0.51, 0.20, 0.10), 0.68)),
        (0.79, surface("Brushed metal", (0.68, 0.71, 0.74), 0.30, metal=1)),
    ]:
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=64, ring_count=32, radius=0.67, location=(x, 0.34, 0.67)
        )
        obj = bpy.context.object
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.materials.append(material)


def environment_image(path, village):
    # Each row is rotationally symmetric, so both lat-long conventions
    # sample the same daylight. The room uses exactly 0.125 in every channel.
    width, height = 16, 64
    hdr = bytearray(
        f"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {height} +X {width}\n".encode()
    )
    for row in range(height):
        up = max(0, math.cos(math.pi * (row + 0.5) / height))
        rgb = (
            (0.20 + 0.52 * up, 0.24 + 0.57 * up, 0.29 + 0.62 * up)
            if village
            else (0.125,) * 3
        )
        _, exponent = math.frexp(max(rgb))
        rgbe = [int(math.ldexp(v, 8 - exponent)) for v in rgb] + [exponent + 128]
        hdr.extend([2, 2, 0, width])
        for component in rgbe:
            hdr.extend([128 + width, component])
    path.write_bytes(hdr)


def copy_color(source, destination, tree):
    if source.is_linked:
        tree.links.new(source.links[0].from_socket, destination)
    else:
        destination.default_value = source.default_value


def with_cutout(tree, shader, alpha):
    if not alpha.is_linked:
        return shader
    mix = tree.nodes.new("ShaderNodeMixShader")
    tree.links.new(alpha.links[0].from_socket, mix.inputs[0])
    tree.links.new(
        tree.nodes.new("ShaderNodeBsdfTransparent").outputs[0], mix.inputs[1]
    )
    tree.links.new(shader, mix.inputs[2])
    return mix.outputs[0]


def leaf_materials():
    # glTF extras have no built-in Cycles closure. Split leaf light between
    # its textured front and diffuse transmission to approximate the engine.
    for material in bpy.data.materials:
        weight = material.get("snailDiffuseTransmission", 0)
        if weight <= 0:
            continue
        tree = material.node_tree
        surface = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        output = next(n for n in tree.nodes if n.type == "OUTPUT_MATERIAL")
        sheet = tree.nodes.new("ShaderNodeBsdfTranslucent")
        copy_color(surface.inputs["Base Color"], sheet.inputs["Color"], tree)
        mix = tree.nodes.new("ShaderNodeMixShader")
        mix.inputs[0].default_value = weight
        tree.links.new(sheet.outputs[0], mix.inputs[2])
        tree.links.new(surface.outputs[0], mix.inputs[1])
        # Preserve glTF alpha masks on both faces.
        alpha = surface.inputs["Alpha"]
        closure = with_cutout(tree, mix.outputs[0], alpha)
        if alpha.is_linked:
            tree.links.remove(alpha.links[0])
            alpha.default_value = 1.0
        tree.links.new(closure, output.inputs["Surface"])


def export_linear(exr, raw):
    image = bpy.data.images.load(str(exr), check_existing=False)
    width, height = image.size
    pixels = np.empty(width * height * 4, np.float32)
    image.pixels.foreach_get(pixels)
    pixels.reshape(height, width, 4)[::-1].astype("<f4").tofile(raw)
    bpy.data.images.remove(image)


def render_linear(scene, path):
    scene.render.filepath = str(path.with_suffix(".exr"))
    start = perf_counter()
    bpy.ops.render.render(write_still=True)
    elapsed = perf_counter() - start
    export_linear(scene.render.filepath, path.with_suffix(".rgba32f"))
    return elapsed


def first_hit_colors(scene, out):
    # Match Snail's single Halton guide ray (1/2, 1/3) before shading.
    # Emission makes the texture visible independently of either BSDF.
    original = []
    for material in bpy.data.materials:
        tree = material.node_tree
        if not tree:
            continue
        surface = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not surface:
            continue
        output = next(n for n in tree.nodes if n.type == "OUTPUT_MATERIAL").inputs[
            "Surface"
        ]
        original.append((tree, output, output.links[0].from_socket))
        color = tree.nodes.new("ShaderNodeEmission")
        copy_color(surface.inputs["Base Color"], color.inputs["Color"], tree)
        tree.links.new(
            with_cutout(tree, color.outputs[0], surface.inputs["Alpha"]), output
        )
    world = scene.world.node_tree.nodes.get("Background").inputs["Strength"]
    world.default_value = 0
    scene.camera.data.shift_y = (1 / 6) / scene.render.resolution_y
    scene.cycles.pixel_filter_type = "GAUSSIAN"
    scene.cycles.filter_width = 0.01
    scene.cycles.samples = 8
    render_linear(scene, out / "cycles-albedo")
    for tree, output, socket in original:
        tree.links.new(socket, output)
    world.default_value = 1
    scene.camera.data.shift_y = 0
    scene.cycles.pixel_filter_type = "BOX"
    scene.cycles.samples = 128


def timing_device(scene, backend):
    if backend == "CPU":
        return {"backend": backend, "name": "CPU", "threads": scene.render.threads}
    preferences = bpy.context.preferences.addons["cycles"].preferences
    preferences.compute_device_type = backend
    preferences.refresh_devices()
    devices = [device for device in preferences.devices if device.type == backend]
    if len(devices) != 1:
        raise RuntimeError(f"Expected one {backend} device, found {[d.name for d in devices]}")
    for device in preferences.devices:
        device.use = device.id == devices[0].id
    scene.cycles.device = "GPU"
    return {"backend": backend, "name": devices[0].name, "id": devices[0].id}


def time_renders(scene, started, backend, out):
    device = timing_device(scene, backend)
    scene.render.use_persistent_data = True
    setup = perf_counter() - started
    times = []
    for index in range(6):
        seed = index * scene.cycles.samples
        scene.cycles.seed = seed
        before = perf_counter()
        if "FINISHED" not in bpy.ops.render.render():
            raise RuntimeError("Cycles did not finish the film")
        times.append(perf_counter() - before)
    # Loading an EXR changes Blender's dependency graph. Export the last
    # completed film for comparison only after collecting every timing.
    with tempfile.TemporaryDirectory() as tmp:
        path = str(Path(tmp) / "finished.exr")
        bpy.data.images["Render Result"].save_render(path)
        export_linear(path, out / "cycles-timing.rgba32f")
    return dict(device=device, setupSeconds=setup, warmupSeconds=times[0], renderSeconds=times[1:])


def main(out, village, backend, size):
    started = perf_counter()
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if village:
        scene_file = Path("src/apps/iygtw/willowbank/main.resources/willowbank.glb").resolve()
        bpy.ops.import_scene.gltf(filepath=str(scene_file))
        eye, target = Vector((-7, -47, 7.48)), Vector((-7, -26, 8.4))
    else:
        fixture()
        scene_file = out / "room.glb"
        bpy.ops.export_scene.gltf(filepath=str(scene_file), export_format="GLB")
        eye, target = Vector((0, -4.9, 1.55)), Vector((0, 0.4, 1.10))
    hdr = out / "studio.hdr"
    environment_image(hdr, village)
    scene = bpy.context.scene
    scene.world = bpy.data.worlds.new("Studio")
    scene.world.use_nodes = True
    tree = scene.world.node_tree
    light = tree.nodes.new("ShaderNodeTexEnvironment")
    light.interpolation = "Closest"
    light.image = bpy.data.images.load(str(hdr))
    tree.links.new(light.outputs["Color"], tree.nodes.get("Background").inputs["Color"])
    bpy.ops.object.camera_add(location=eye)
    scene.camera = bpy.context.object
    camera = scene.camera.data
    scene.camera.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    camera.sensor_fit = "VERTICAL"
    camera.lens = camera.sensor_height / (2 * math.tan(0.8 / 2))
    width, height = size
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.use_denoising = False
    # A hole in an alpha mask is a visibility test in Snail. Allow chains
    # of transparent skips independently of the eight scattering events.
    scene.cycles.transparent_max_bounces = 128
    for key in (
        "max_bounces",
        "diffuse_bounces",
        "glossy_bounces",
        "transmission_bounces",
    ):
        setattr(scene.cycles, key, 8)
    scene.cycles.sample_clamp_direct = scene.cycles.sample_clamp_indirect = 0
    scene.cycles.blur_glossy = 0
    scene.cycles.pixel_filter_type = "BOX"
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.view_settings.view_transform = "Standard"
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 8
    if not backend:
        first_hit_colors(scene, out)
    if village:
        leaf_materials()
    if backend:
        measurements = {"timing": time_renders(scene, started, backend, out)}
    else:
        captures = []
        for seed in (0, 128):
            scene.cycles.seed = seed
            captures.append(render_linear(scene, out / f"cycles-{seed}"))
        measurements = {"cyclesSeconds": captures}

    def gltf(p):
        return [float(p.x), float(p.z), float(-p.y)]

    (out / "shot.json").write_text(
        json.dumps(
            {
                "scene": str(scene_file),
                "width": width,
                "height": height,
                "samples": 128,
                "bounces": 8,
                "eye": gltf(eye),
                "target": gltf(target),
                "blender": bpy.app.version_string,
                **measurements,
            }
        )
        + "\n"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("scene", choices=["room", "village"], default="room", nargs="?")
    parser.add_argument("--timing")
    parser.add_argument("--size", default="256x160")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    main(args.out.resolve(), args.scene == "village", args.timing,
         tuple(map(int, args.size.split("x"))))
