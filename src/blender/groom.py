"""Paint a strand atlas and comb skinned, alpha-tested ribbons in Blender."""

from math import pi, sin

import bpy
import numpy as np


def tuft_material(name, color, roughness, transmission, anisotropy, seed):
    # Four combs with different parting, strand lengths, and flyaways. Roots
    # overlap to cover the undercoat; individual tips separate in silhouette.
    rng = np.random.default_rng(seed)
    height, tile = 256, 64
    v, x = np.mgrid[0:height, 0:tile]
    v = v / (height - 1)
    rgba = np.zeros((height, 4 * tile, 4), dtype=np.float32)
    for i in range(4):
        alpha, value = np.zeros_like(v), np.ones_like(v)
        for root in np.linspace(5, tile - 5, 44):
            tip = rng.uniform(0.62, 1.01)
            curve = (
                root + rng.uniform(-9, 9) * v**2 + rng.uniform(-2, 2) * np.sin(pi * v)
            )
            coverage = np.clip(0.65 + 1.13 * (1 - v / tip) - abs(x - curve), 0, 1)
            coverage *= np.clip((tip - v) * 65, 0, 1)
            value = np.where(coverage > alpha, rng.uniform(0.68, 1.25), value)
            alpha = np.maximum(alpha, coverage)
        patch = rgba[:, i * tile : (i + 1) * tile]
        patch[:, :, :3] = np.array(color) * (value * (0.83 + 0.28 * v))[:, :, None]
        patch[:, :, 3] = alpha
    image = bpy.data.images.new(name, tile * 4, height, alpha=True)
    image.alpha_mode = "STRAIGHT"
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = False
    m["snailDiffuseTransmission"] = transmission
    m["snailFiberAnisotropy"] = anisotropy
    tree = m.node_tree
    shader = tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Anisotropic"].default_value = anisotropy
    image_node = tree.nodes.new("ShaderNodeTexImage")
    image_node.image = image
    cutoff = tree.nodes.new("ShaderNodeMath")
    cutoff.operation = "GREATER_THAN"
    cutoff.inputs[1].default_value = 0.37
    tree.links.new(image_node.outputs["Color"], shader.inputs["Base Color"])
    tree.links.new(image_node.outputs["Alpha"], cutoff.inputs[0])
    tree.links.new(cutoff.outputs[0], shader.inputs["Alpha"])
    return m


class Ribbons:
    def __init__(self):
        self.vertices, self.faces, self.uv, self.weights = [], [], [], []

    def comb(self, points, normal, radius, tile, weights, tip_width=0.41):
        start = len(self.vertices)
        for j, p in enumerate(points):
            t = j / (len(points) - 1)
            flow = (
                points[min(j + 1, len(points) - 1)] - points[max(j - 1, 0)]
            ).normalized()
            across = flow.cross(normal).normalized()
            width = radius * (0.73 + 0.27 * sin(pi * t) - (0.73 - tip_width) * t)
            for k in range(3):
                self.vertices.append(
                    p + (k - 1) * width * across + (k % 2) * width * 0.15 * normal
                )
                self.uv.append(((tile + 0.025 + 0.475 * k) / 4, 0.008 + 0.984 * t))
                self.weights.append(weights)
            if j:
                a = start + 3 * (j - 1)
                self.faces.extend(
                    [(a, a + 1, a + 4, a + 3), (a + 1, a + 2, a + 5, a + 4)]
                )
