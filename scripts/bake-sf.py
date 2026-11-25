"""Bake the one-download San Francisco taxi map from OSM, the city shoreline and USGS 3DEP."""

import argparse
import collections
import concurrent.futures
import hashlib
import json
import math
import multiprocessing
import os
import struct
import zlib
from pathlib import Path
from xml.sax.saxutils import escape

import numpy as np
import osmium
import shapely
from PIL import Image, ImageDraw
from shapely.geometry import LineString, Point, Polygon, box, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1] / "src/apps/last-mile"
ASSETS, PUBLIC = ROOT / "assets", ROOT / "public"
SIDE, STEP = 256, 32
# Street frame used by the original Lombard simulation: right is east along Lombard.
LON, LAT = -122.4179869, 37.8022186
C, S = math.cos(math.radians(9.05)), math.sin(math.radians(9.05))
MX, MZ = 111320 * math.cos(math.radians(LAT)), 111132
WIDTHS = {
    "motorway": 14,
    "trunk": 13,
    "primary": 12,
    "secondary": 10,
    "tertiary": 9,
    "residential": 8.5,
    "unclassified": 7,
    "living_street": 5,
    "service": 4.2,
}
WIDTHS.update(
    {k + "_link": 6 for k in ("motorway", "trunk", "primary", "secondary", "tertiary")}
)
BASE = {
    "road": (0.115, 0.13, 0.15),
    "walk": (0.54, 0.50, 0.43),
    "land": (0.32, 0.36, 0.23),
    "park": (0.20, 0.38, 0.19),
    "water": (0.015, 0.049, 0.041),
    "line": (0.91, 0.69, 0.25),
    "roof": (0.26, 0.28, 0.29),
    "trunk": (0.23, 0.16, 0.10),
    "tree": (0.19, 0.38, 0.22),
    "bin": (0.11, 0.28, 0.23),
    "glass": (0.15, 0.30, 0.36),
    "lamp": (0.97, 0.82, 0.51),
    "paper": (0.75, 0.71, 0.58),
    "bag": (0.12, 0.14, 0.15),
    "seat": (0.55, 0.35, 0.19),
    "awning0": (0.63, 0.19, 0.11),
    "awning1": (0.12, 0.39, 0.36),
    "awning2": (0.78, 0.54, 0.18),
}
for i, c in enumerate(
    [
        (0.88, 0.77, 0.64),
        (0.68, 0.79, 0.76),
        (0.85, 0.67, 0.57),
        (0.78, 0.77, 0.72),
        (0.71, 0.75, 0.82),
    ]
):
    BASE["house" + str(i)] = c


# ---- Map frame and survey ----


def local(lon, lat):
    dx, dz = (lon - LON) * MX, (lat - LAT) * MZ
    return -2 + dx * C + dz * S, -8.1 + dx * S - dz * C


def geographic(x, z):
    return LON + ((x + 2) * C + (z + 8.1) * S) / MX, LAT + (
        (x + 2) * S - (z + 8.1) * C
    ) / MZ


def pieces(g, kind):
    if g.geom_type == kind and not g.is_empty:
        yield g
    elif hasattr(g, "geoms"):
        for p in g.geoms:
            yield from pieces(p, kind)


def rings(g):
    return pieces(g, "Polygon")


def num(text, default):
    try:
        return float(str(text).lower().removesuffix(" m").split(";")[0])
    except (TypeError, ValueError):
        return default


def acceptable(lon, lat, bridges=False):
    x, z = local(lon, lat)
    if shapely.contains_xy(road_land, x, z):
        return True
    bay = bridges and -122.397 < lon < -122.359 and 37.782 < lat < 37.818
    golden = bridges and -122.485 < lon < -122.473 and 37.803 < lat < 37.8355
    return bay or golden


def facade_style(tags, height, area, ident):
    kind = tags.get("building", "")
    if height >= 35 or kind in ("office", "commercial", "retail", "hotel"):
        return 4
    if kind in ("warehouse", "industrial", "garages") or area > 1800 and height < 13:
        return 3
    if tags.get("building:material") in ("brick", "masonry") or kind == "school":
        return 2
    return (ident // 2) % 3


class Survey(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.roads, self.buildings, self.props, self.parks = [], [], [], []
        self.paths, self.water = [], []
        self.wkb = osmium.geom.WKBFactory()

    def point(self, t, x, z, ident):
        amenity = t.get("amenity", "")
        if t.get("shop") or amenity in (
            "cafe",
            "restaurant",
            "bar",
            "pharmacy",
            "bakery",
        ):
            self.props.append(
                (x, z, "shop", ident, t.get("name") or t.get("brand", ""))
            )
        elif (
            amenity in ("bench", "waste_basket", "recycling")
            or t.get("highway") == "street_lamp"
        ):
            self.props.append(
                (
                    x,
                    z,
                    "lamp"
                    if t.get("highway") == "street_lamp"
                    else "bench"
                    if amenity == "bench"
                    else "bin",
                    ident,
                    "",
                )
            )
        elif t.get("natural") == "tree":
            self.props.append((x, z, "tree", ident, ""))

    def node(self, n):
        if n.tags and acceptable(n.location.lon, n.location.lat):
            self.point(n.tags, *local(n.location.lon, n.location.lat), n.id)

    def way(self, w):
        t = w.tags
        kind = t.get("highway", "")
        if (
            kind in ("footway", "path", "cycleway", "pedestrian", "steps")
            and not t.get("tunnel")
            and t.get("area") != "yes"
        ):
            pts = [
                local(n.location.lon, n.location.lat)
                for n in w.nodes
                if n.location.valid() and acceptable(n.location.lon, n.location.lat)
            ]
            if len(pts) > 1:
                self.paths.append(LineString(pts).simplify(0.65))
            return
        if (
            kind not in WIDTHS
            or t.get("access") in ("private", "no")
            or t.get("motor_vehicle") in ("private", "no")
            or t.get("service") in ("parking_aisle", "driveway")
            or t.get("area") == "yes"
        ):
            return
        bridge = (
            kind in ("motorway", "motorway_link", "trunk", "trunk_link")
            or t.get("bridge") == "yes"
        )
        width = max(2.6, min(24, num(t.get("width"), WIDTHS[kind])))
        direction = t.get(
            "oneway",
            "yes" if kind == "motorway" or t.get("junction") == "roundabout" else "no",
        )
        segment = []

        def finish():
            if len(segment) > 1:
                self.roads.append(
                    (
                        list(reversed(segment)) if direction == "-1" else segment[:],
                        width,
                        t.get("name", t.get("ref", "Access road")),
                        direction in ("yes", "1", "true", "-1"),
                        bool(t.get("bridge") and t.get("bridge") != "no"),
                        kind,
                    )
                )

        for n in w.nodes:
            if n.location.valid() and acceptable(
                n.location.lon, n.location.lat, bridge
            ):
                x, z = local(n.location.lon, n.location.lat)
                segment.append((n.ref, round(x, 1), round(z, 1)))
            else:
                finish()
                segment = []
        finish()

    def area(self, a):
        t = a.tags
        building = t.get("building") and t.get("building") != "no"
        park = t.get("leisure") in (
            "park",
            "garden",
            "golf_course",
            "pitch",
            "nature_reserve",
        ) or t.get("landuse") in ("grass", "forest", "recreation_ground")
        shop = t.get("shop") or t.get("amenity") in ("restaurant", "cafe", "bar")
        water = t.get("natural") == "water" or t.get("landuse") in (
            "reservoir",
            "basin",
        )
        if not (building or park or shop or water):
            return
        try:
            g = shapely.from_wkb(bytes.fromhex(self.wkb.create_multipolygon(a)))
        except (RuntimeError, ValueError):
            return
        p = g.representative_point()
        if not acceptable(p.x, p.y):
            return
        g = shapely.transform(g, local, interleaved=False)
        if not g.is_valid:
            g = shapely.make_valid(g)
        g = g.simplify(0.48)
        if building:
            h = max(
                2.7,
                min(
                    340, num(t.get("height"), 3.1 * num(t.get("building:levels"), 2.5))
                ),
            )
            for poly in rings(g):
                if poly.area <= 5:
                    continue
                style = facade_style(t, h, poly.area, a.id)
                roof = t.get("roof:shape", "")
                pitched = roof in ("gabled", "hipped") or (
                    not roof and style == 0 and h < 14 and poly.area < 220
                )
                self.buildings.append((poly, h, a.id, style, pitched))
        if park:
            self.parks.extend(rings(g))
        if water:
            self.water.extend(rings(g))
        if shop:
            self.point(t, *local(p.x, p.y), a.id)


# ---- Terrain and road graph ----


def terrain(dem):
    global samples
    Image.MAX_IMAGE_PIXELS = None
    with Image.open(dem) as img:
        dx, dy, _ = img.tag_v2[33550]
        col, row, _, lon0, lat0, _ = img.tag_v2[33922]
        xs, zs = np.meshgrid(
            np.arange(west, east + STEP, STEP), np.arange(north, south + STEP, STEP)
        )
        lon, lat = geographic(xs, zs)
        u = col + (lon - lon0) / dx - 0.5
        v = row + (lat0 - lat) / dy - 0.5
        ix = np.floor(u).astype(int)
        iz = np.floor(v).astype(int)
        u -= ix
        v -= iz
        xmin, xmax = ix.min(), ix.max() + 2
        zmin, zmax = iz.min(), iz.max() + 2
        pix = np.asarray(img.crop((int(xmin), int(zmin), int(xmax), int(zmax))))
        ix -= xmin
        iz -= zmin
        samples = (1 - v) * ((1 - u) * pix[iz, ix] + u * pix[iz, ix + 1]) + v * (
            (1 - u) * pix[iz + 1, ix] + u * pix[iz + 1, ix + 1]
        )
        samples = np.maximum(0, np.nan_to_num(samples))
    # Bare-earth DEM has no bridge deck. A continuous approximate deck joins the
    # two shores of the western Bay Bridge span. Its surface is used for contact too.
    if bridge_lines:
        line = unary_union(bridge_lines)
        ids = np.where((xs > 900) & (zs < 2700) & (zs > -1800))
        ds = shapely.distance(shapely.points(xs[ids], zs[ids]), line)
        lons = lon[ids]
        ramp = np.clip((lons + 122.397) / 0.008, 0, 1) * np.clip(
            (-122.360 - lons) / 0.006, 0, 1
        )
        samples[ids] = np.maximum(
            samples[ids], 55 * ramp * np.clip((75 - ds) / 35, 0, 1)
        )
    if golden_lines:
        ids = np.where((xs < -4300) & (zs < -1000))
        dist = shapely.distance(
            shapely.points(xs[ids], zs[ids]), unary_union(golden_lines)
        )
        ramp = np.clip((lat[ids] - 37.806) / 0.004, 0, 1) * np.clip(
            (37.8355 - lat[ids]) / 0.004, 0, 1
        )
        samples[ids] = np.maximum(
            samples[ids], 68 * ramp * np.clip((65 - dist) / 26, 0, 1)
        )


def height(x, z):
    u = max(0, min(samples.shape[1] - 1.00001, (x - west) / STEP))
    v = max(0, min(samples.shape[0] - 1.00001, (z - north) / STEP))
    i, j = int(u), int(v)
    u -= i
    v -= j
    a, b = samples[j, i : i + 2]
    d, c = samples[j + 1, i : i + 2]
    return a + (b - a) * u + (c - b) * v if u >= v else a + (c - d) * u + (d - a) * v


def lookup(items, geometries):
    return items, shapely.STRtree(geometries)


def near(index, region):
    items, tree = index
    return [items[i] for i in sorted(tree.query(region, predicate="intersects"))]


def packed(data):
    c = zlib.compressobj(7, zlib.DEFLATED, -15)
    return struct.pack("<I", len(data)) + c.compress(data) + c.flush()


def path_data(points):
    return [(round((x - west) / 8), round((z - north) / 8)) for x, z in points]


def navigation(roads):
    nodes, positions, edges, names = {}, [], collections.defaultdict(set), {}
    for points, width, name, one, bridge, kind in roads:
        street = names.setdefault(name, len(names))
        prev = None
        for ident, x, z in points:
            n = nodes.get(ident)
            if n is None:
                n = len(positions)
                nodes[ident] = n
                positions.append((round(x), round(z)))
            if prev is not None and n != prev:
                edges[prev].add((n, street))
                if not one:
                    edges[n].add((prev, street))
            prev = n
    offsets = [0]
    links = bytearray()
    for i in range(len(positions)):
        for n, s in sorted(edges[i]):
            links.extend(struct.pack("<IH", n, s))
        offsets.append(len(links) // 6)
    labels = b"\n".join(n.encode() for n in names)
    output = struct.pack(
        "<4sIII", b"NAV1", len(positions), len(links) // 6, len(labels)
    )
    output += (
        b"".join(struct.pack("<hh", *p) for p in positions)
        + np.asarray(offsets, dtype="<u4").tobytes()
        + links
        + labels
    )
    (ASSETS / "streets.nav").write_bytes(output)
    return len(positions), len(links) // 6


# ---- Local scene geometry ----


def triangle_coords(poly):
    if poly.area < 0.002:
        return
    for t in shapely.get_parts(shapely.constrained_delaunay_triangles(poly)):
        yield list(t.exterior.coords)[:3]


class Mesh:
    def __init__(self, x, z):
        self.x, self.z = x, z
        self.parts = {}
        self.lamps = []

    def face(self, material, xyz, uv=None):
        verts, indices = self.parts.setdefault(material, ({}, []))
        for (x, y, z), (u, v) in zip(xyz, uv or [(0, 0)] * 3):
            key = (
                max(0, min(65535, round((x - self.x) * 100))),
                max(0, min(65535, round((y + 12) * 100))),
                max(0, min(65535, round((z - self.z) * 100))),
                max(0, min(255, round(u))),
                max(0, min(255, round(v))),
            )
            indices.append(verts.setdefault(key, len(verts)))

    def quad(self, name, a, b, c, d, uv=None):
        q = uv or [(0, 0)] * 4
        self.face(name, [a, b, c], [q[0], q[1], q[2]])
        self.face(name, [a, c, d], [q[0], q[2], q[3]])

    def wall(self, name, x, z, xx, zz, y, yy, top):
        h = max(1, round((top - min(y, yy)) / 3))
        n = max(1, round(math.hypot(x - xx, z - zz) / 4))
        self.quad(
            name,
            (x, y, z),
            (xx, yy, zz),
            (xx, top, zz),
            (x, top, z),
            [(0, h), (n, h), (n, 0), (0, 0)],
        )

    def box(self, mat, x, z, w, d, h, base, angle=0):
        c, s = math.cos(angle), math.sin(angle)
        p = [
            (x + a * c - b * s, z + a * s + b * c)
            for a, b in [
                (-w / 2, -d / 2),
                (w / 2, -d / 2),
                (w / 2, d / 2),
                (-w / 2, d / 2),
            ]
        ]
        lo = [(a, base, b) for a, b in p]
        hi = [(a, base + h, b) for a, b in p]
        self.quad(mat, *hi)
        for i in range(4):
            self.quad(mat, lo[i], lo[i - 1], hi[i - 1], hi[i])

    def light(self, x, y, z, kind):
        self.lamps.append(
            struct.pack(
                "<HHHBB",
                round((x - self.x) * 100),
                round((y + 12) * 100),
                round((z - self.z) * 100),
                kind,
                0,
            )
        )

    def street_lamp(self, x, z, y, dx=0.55, dz=0.0):
        self.box("glass", x, z, 0.15, 0.15, 4.1, y)
        self.box(
            "lamp",
            x + dx / 2,
            z + dz / 2,
            0.90,
            0.42,
            0.24,
            y + 4.02,
            math.atan2(dz, dx),
        )
        self.light(x + dx, y + 3.98, z + dz, 0)

    def encode(self):
        # A tile's positions and UVs share an eight-byte vertex. The GPU unpacks
        # this very buffer into the tracer's vertices; no per-vertex Scheme objects.
        counts = []
        blob = bytearray()
        for name, (verts, indices) in self.parts.items():
            start = len(blob)
            blob.extend(b"".join(struct.pack("<HHHBB", *v) for v in verts))
            at = len(blob)
            blob.extend(np.asarray(indices, dtype="<u4").tobytes())
            counts.append((list(BASE).index(name), len(verts), len(indices), start, at))
        return (
            struct.pack("<I", len(counts))
            + b"".join(struct.pack("<5I", *p) for p in counts)
            + blob
            + b"".join(self.lamps)
            + struct.pack("<I4s", len(self.lamps), b"LIT1")
        )


def draw_poly(draw, poly, color, origin, hole=0):
    x, z = origin

    def pts(r):
        return [(round(a - x), round(b - z)) for a, b in r.coords]

    draw.polygon(pts(poly.exterior), fill=color)
    for ring in poly.interiors:
        draw.polygon(pts(ring), fill=hole)


def street_props(mesh, props, roads, occupancy):
    shops = []
    for x, z, kind, ident, name in props:
        if kind == "tree" and ident % 4:
            continue
        if not roads and kind == "shop":
            continue
        y = height(x, z) + 0.16
        if kind == "shop":
            road = min(roads, key=lambda q: q[0].distance(Point(x, z)))
            line = road[0]
            t = line.project(Point(x, z))
            at = line.interpolate(t)
            dx, dz = x - at.x, z - at.y
            d = math.hypot(dx, dz)
            if d < 0.2 or d > 48:
                continue
            dx /= d
            dz /= d
            # The customer-facing strip sits behind the pavement, toward its tagged business.
            front = road[1] / 2 + 2.8
            for ds in np.arange(road[1] / 2 + 0.6, min(d + 3.0, 26.0), 0.5):
                px, pz = int(at.x + dx * ds - mesh.x), int(at.y + dz * ds - mesh.z)
                if 0 <= px < SIDE and 0 <= pz < SIDE and occupancy.getpixel((px, pz)):
                    front = ds - 0.52
                    break
            x, z = at.x + dx * front, at.y + dz * front
            if not (
                mesh.x + 2 < x < mesh.x + SIDE - 2
                and mesh.z + 2 < z < mesh.z + SIDE - 2
            ):
                continue
            a = math.atan2(-dx, dz)
            y = height(x, z) + 0.16
            mesh.box("glass", x, z, 3.8, 0.24, 2.35, y, a)
            mesh.box(
                "awning" + str(ident % 3),
                x - dx * 0.46,
                z - dz * 0.46,
                4.4,
                1.25,
                0.33,
                y + 2.35,
                a,
            )
            mesh.box("lamp", x - dx * 0.19, z - dz * 0.19, 1.9, 0.15, 0.26, y + 2.02, a)
            mesh.light(x - dx * 0.35, y + 1.98, z - dz * 0.35, 1)
            shops.append((round(x - mesh.x), round(z - mesh.z), name))
            if ident % 3 == 0:
                mesh.box("bin", x - dx * 1.5, z - dz * 1.5, 0.58, 0.55, 0.91, y)
                mesh.box("bag", x - dx * 1.9 + 0.5, z - dz * 1.9, 0.4, 0.36, 0.38, y)
            if ident % 4 == 0:
                mesh.box(
                    "paper",
                    x - dx * 1.65 - 0.7,
                    z - dz * 1.65,
                    0.32,
                    0.18,
                    0.03,
                    y + 0.02,
                    a,
                )
        elif kind == "tree":
            mesh.box("trunk", x, z, 0.27, 0.27, 2.7, y)
            mesh.box("tree", x, z, 2.5, 2.3, 2.6, y + 2.4, ident % 6)
            ImageDraw.Draw(occupancy).point(
                (round(x - mesh.x), round(z - mesh.z)), fill=1
            )
        elif kind == "bench":
            mesh.box("seat", x, z, 1.55, 0.52, 0.46, y, ident % 6)
        elif kind == "lamp":
            mesh.street_lamp(x, z, y)
        else:
            mesh.box("bin", x, z, 0.57, 0.56, 0.94, y)
    return shops


def surfaces(region, halo, roads):
    pavement = unary_union(
        [
            line.intersection(halo).buffer(w / 2, quad_segs=2, join_style="round")
            for line, w, *_ in roads
        ]
    )
    road = pavement.intersection(region)
    water = near(water_idx, region)
    dry = land.intersection(region).difference(unary_union([g for g, _ in water]))
    lip = pavement.buffer(0.5, quad_segs=1).intersection(region)
    # Buffer uncut roads across tile edges to keep kerbs out of crossing streets.
    sidewalk = pavement.buffer(2.1, quad_segs=1).intersection(region)
    parks = unary_union(near(park_idx, region)).intersection(dry)
    paths = (
        unary_union(
            [
                p.intersection(halo).buffer(0.83, quad_segs=1)
                for p in near(path_idx, halo)
            ]
        )
        .intersection(dry)
        .difference(sidewalk)
    )
    bare = dry.difference(sidewalk.union(paths))
    layers = [
        ("road", road, 0),
        ("walk", lip.difference(road), 1),
        ("walk", sidewalk.difference(lip), 2),
        ("walk", paths, 2),
        ("park", bare.intersection(parks), 2),
        ("land", bare.difference(parks), 2),
    ]
    wet = region.difference(dry.union(sidewalk))
    for body, level in water:
        if level > 0 and wet.intersects(body):
            layers.append(("water", wet.intersection(body), level))
            wet = wet.difference(body)
    layers.append(("water", wet, 0.0))
    return road, dry.union(sidewalk), layers


def ground_mesh(mesh, road, layers):
    x, z = mesh.x, mesh.z
    cells = [0]
    ground = bytearray()
    n = SIDE // STEP
    for j in range(n):
        for i in range(n):
            a, b = x + STEP * i, z + STEP * j
            for tri in [
                [(a, b), (a + STEP, b), (a + STEP, b + STEP)],
                [(a, b), (a + STEP, b + STEP), (a, b + STEP)],
            ]:
                patch = Polygon(tri)
                for mat, g, k in layers:
                    if g.is_empty or not g.intersects(patch):
                        continue
                    triangles = (
                        [tri]
                        if g.covers(patch)
                        else (
                            t
                            for p in rings(g.intersection(patch))
                            for t in triangle_coords(p)
                        )
                    )
                    for pts in triangles:
                        coords = []
                        for px, pz in pts:
                            h = k if mat == "water" else height(px, pz)
                            if mat == "walk" and k == 1:
                                h += 0.16 * min(1, road.distance(Point(px, pz)) / 0.5)
                            if mat != "water" and k == 2:
                                h += 0.16
                            coords.append(
                                (
                                    round((px - a) * 100),
                                    round((pz - b) * 100),
                                    max(-32768, min(32767, round(h * 100))),
                                )
                            )
                        (ax, az, _), (bx, bz, _), (cx, cz, _) = coords
                        if (bx - ax) * (cz - az) == (bz - az) * (cx - ax):
                            continue
                        ground.extend(
                            struct.pack("<HHhHHhHHh", *(v for pt in coords for v in pt))
                        )
                        mesh.face(
                            mat,
                            [
                                (a + dx / 100, h / 100, b + dz / 100)
                                for dx, dz, h in coords
                            ],
                        )
            cells.append(len(ground) // 18)
    return cells, ground


def facade_textures():
    # One repeat is about four metres wide by one storey high. Each image
    # has its own window rhythm and trim, preserved by the texture mip chain.
    for style, name in enumerate(("facade", "stucco", "brick", "works", "office")):
        img = Image.new(
            "RGB",
            (128, 128),
            ("#dad2bb", "#e5cda9", "#ad7057", "#acaaa0", "#71848b")[style],
        )
        d = ImageDraw.Draw(img)
        if style == 0:
            for y in range(0, 128, 7):
                d.line((0, y, 127, y), fill="#b0aea0")
        if style == 2:
            for y in range(0, 128, 8):
                d.line((0, y, 127, y), fill="#c2967c")
                for x in range(12 if y % 16 else 0, 128, 24):
                    d.line((x, y, x, y + 8), fill="#c2967c")
        windows = ((11, 48), (22, 54), (12, 50), (4, 124), (1, 63))[style]
        left, right = windows
        for x in [left] if style == 3 else [left, left + 64]:
            width = right - left
            top, bottom = [(23, 96), (31, 96), (24, 98), (45, 85), (5, 108)][style]
            d.rectangle((x - 3, top - 4, x + width + 3, bottom + 3), fill="#5b5046")
            d.rectangle(
                (x, top, x + width, bottom),
                fill=("#66767b", "#668081", "#626e74", "#758b91", "#587987")[style],
            )
            d.polygon([(x, top), (x + width, top), (x, top + 23)], fill="#87989a")
            for xx in range(
                x + (16 if style == 3 else width // 2),
                x + width,
                (16 if style == 3 else width),
            ):
                d.line((xx, top, xx, bottom), fill="#d4cdc0", width=2)
            d.line(
                (x, top + (bottom - top) // 2, x + width, top + (bottom - top) // 2),
                fill="#c3b9a4",
                width=2,
            )
            if style in (0, 1, 2):
                d.rectangle(
                    (x - 5, bottom + 2, x + width + 5, bottom + 6), fill="#ddd3bc"
                )
                if style == 1:
                    d.arc(
                        (x - 6, top - 15, x + width + 6, top + 16),
                        180,
                        360,
                        fill="#c19768",
                        width=4,
                    )
        d.rectangle(
            (0, 119, 127, 125),
            fill=("#a7a495", "#d5ba97", "#86533f", "#989887", "#475861")[style],
        )
        img.save(ASSETS / f"sf-{name}.png")


def bay_window(mesh, poly, top, style):
    # Pick a street-facing wall of an intact narrow house. The bay hangs
    # above the pavement; the surveyed footprint still governs contacts.
    road = road_idx[0][road_idx[1].nearest(poly.centroid)][0]
    edges = list(zip(poly.exterior.coords, list(poly.exterior.coords)[1:]))
    good = [(a, b) for a, b in edges if 4.5 <= math.dist(a, b) <= 13]
    if not good:
        return

    def center(edge):
        a, b = edge
        return Point((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)

    a, b = min(good, key=lambda e: center(e).distance(road))
    mid = center((a, b))
    if mid.distance(road) > 18:
        return
    width = math.dist(a, b)
    dx, dz = (b[0] - a[0]) / width, (b[1] - a[1]) / width
    nx, nz = -dz, dx
    if poly.covers(Point(mid.x + nx * 0.3, mid.y + nz * 0.3)):
        nx, nz = -nx, -nz
    base = height(mid.x, mid.y) + 2.8
    if top - base < 2.5:
        return

    def at(across, out):
        return (mid.x + dx * across + nx * out, mid.y + dz * across + nz * out)

    corners = [at(-1.6, 0.0), at(-1.1, 0.85), at(1.1, 0.85), at(1.6, 0.0)]
    if not all(
        mesh.x <= x <= mesh.x + SIDE and mesh.z <= z <= mesh.z + SIDE
        for x, z in corners
    ):
        return
    for u, v in zip(corners, corners[1:]):
        mesh.wall("house" + str(style), *u, *v, base, base, top - 0.22)
    mesh.quad("roof", *((x, top - 0.22, z) for x, z in corners))
    mesh.quad("roof", *((x, base, z) for x, z in reversed(corners)))


def buildings(mesh, region, occupancy):
    x, z = mesh.x, mesh.z
    draw = ImageDraw.Draw(occupancy)
    for p, h, ident, style, pitched in near(build_idx, region):
        for g in rings(p.intersection(region)):
            if g.area < 1:
                continue
            draw_poly(draw, g, 1, (x, z))
            coords = list(g.exterior.coords)
            top = max(height(a, b) for a, b in p.exterior.coords) + h
            # Keep pitched roofs inside the surveyed outline. Clip-edge and
            # irregular footprints retain their level roof across sector seams.
            ridge = (
                pitched and region.covers(p) and len(coords) == 5 and not g.interiors
            )
            if ridge:
                corners = coords[:-1]
                if math.dist(*corners[:2]) > math.dist(*corners[1:3]):
                    corners = corners[1:] + corners[:1]
                rise = min(2.2, math.dist(*corners[:2]) * 0.28)
                eaves = [(a, top - rise, b) for a, b in corners]
                ridge_a, ridge_b = [
                    ((a[0] + b[0]) / 2, top, (a[2] + b[2]) / 2)
                    for a, b in ((eaves[0], eaves[1]), (eaves[2], eaves[3]))
                ]
                mesh.quad("roof", eaves[1], eaves[2], ridge_b, ridge_a)
                mesh.quad("roof", eaves[3], eaves[0], ridge_a, ridge_b)
                mesh.face("roof", [eaves[0], eaves[1], ridge_a])
                mesh.face("roof", [eaves[2], eaves[3], ridge_b])
                top -= rise
            else:
                for t in triangle_coords(g):
                    mesh.face("roof", [(a, top, b) for a, b in t])
            if (
                style in (0, 1)
                and 6 < h < 18
                and 40 < p.area < 360
                and region.covers(p)
            ):
                bay_window(mesh, p, top, style)
            for ring in [g.exterior, *g.interiors]:
                for (a, b), (c, d) in zip(ring.coords, list(ring.coords)[1:]):
                    mesh.wall(
                        "house" + str(style),
                        a,
                        b,
                        c,
                        d,
                        height(a, b) - 0.25,
                        height(c, d) - 0.25,
                        top,
                    )


def road_markings(mesh, region, roads):
    # Paint centre markings only on named streets wide enough for two lanes.
    for line, w, name, *_ in roads:
        if w < 7 or not name:
            continue
        for part in pieces(line.intersection(region), "LineString"):
            for t in range(5, int(part.length) - 4, 14):
                a, b = part.interpolate(t), part.interpolate(t + 3)
                if a.distance(b) < 1:
                    continue
                dx = (b.y - a.y) * 0.035
                dz = (a.x - b.x) * 0.035
                p = [
                    (a.x + dx, a.y + dz),
                    (a.x - dx, a.y - dz),
                    (b.x - dx, b.y - dz),
                    (b.x + dx, b.y + dz),
                ]
                mesh.quad("line", *[(u, height(u, v) + 0.045, v) for u, v in p])


def scatter_furniture(mesh, roads, occ):
    x, z = mesh.x, mesh.z
    for line, w, name, _, _, kind in roads:
        if kind not in ("residential", "primary", "secondary", "tertiary"):
            continue
        for m in range(22, int(line.length) - 2, 47):
            a, b = line.interpolate(m), line.interpolate(m + 1)
            seed = (round(a.x) * 73856093 ^ round(a.y) * 19349663) & 0xFFFFFFFF
            furniture = seed % (6 if kind == "residential" else 3) == 0
            lamp = (seed >> 7) % (3 if kind == "residential" else 2) == 0
            if not (furniture or lamp):
                continue
            dx, dz = b.x - a.x, b.y - a.y
            length = math.hypot(dx, dz)
            if length < 0.1:
                continue
            side = 1 if seed & 8 else -1
            u = a.x - side * dz / length * (w / 2 + 1.45)
            v = a.y + side * dx / length * (w / 2 + 1.45)
            if not (
                x + 2 < u < x + SIDE - 2 and z + 2 < v < z + SIDE - 2
            ) or occ.getpixel((int(u - x), int(v - z))):
                continue
            y = height(u, v) + 0.16
            if lamp:
                mesh.street_lamp(
                    u, v, y, side * dz / length * 0.55, -side * dx / length * 0.55
                )
            if not furniture:
                continue
            if seed & 16:
                mesh.box("bin", u, v, 0.56, 0.51, 0.88, y)
            else:
                mesh.box("seat", u, v, 1.3, 0.46, 0.45, y, math.atan2(dz, dx))
            if seed & 32:
                mesh.box("bag", u + 0.6, v + 0.35, 0.44, 0.38, 0.36, y)
            if seed & 64:
                mesh.box(
                    "paper", u - 0.57, v + 0.2, 0.30, 0.21, 0.025, y + 0.008, seed % 5
                )


def contact_bytes(x, z, cells, ground, occ):
    n = SIDE // STEP
    occ = np.asarray(occ) > 0
    lines = [0]
    spans = bytearray()
    for line in occ:
        ends = np.flatnonzero(np.diff(np.r_[False, line, False])).astype("<u2")
        spans.extend(ends.tobytes())
        lines.append(len(spans) // 4)
    return (
        struct.pack("<4siiIIII", b"GRD1", x, z, n, n, STEP, len(ground) // 18)
        + np.asarray(cells, dtype="<u4").tobytes()
        + ground
        + np.asarray(lines, dtype="<u4").tobytes()
        + spans
    )


def street_labels(roads):
    """Place names once across tile edges so neighbouring streets stay readable."""
    suffix = {
        "Street": "St",
        "Avenue": "Ave",
        "Boulevard": "Blvd",
        "Drive": "Dr",
        "Road": "Rd",
    }
    candidates = []
    for line, width, name, *_ in roads:
        words = name.split()
        if not words or name == "Access road" or len(name) > 25 or line.length < 40:
            continue
        words[-1] = suffix.get(words[-1], words[-1])
        label = " ".join(words)
        count = math.ceil(line.length / SIDE)
        for i in range(count):
            p = line.interpolate((i + 0.5) / count, normalized=True)
            candidates.append((width * min(SIDE, line.length), label, p.x, p.y))
    labels = {}
    for _, name, x, z in sorted(candidates, reverse=True):
        tx, tz = math.floor(x / SIDE) * SIDE, math.floor(z / SIDE) * SIDE
        if (tx, tz) in labels:
            continue
        neighbours = (
            labels[k]
            for dx in (-SIDE, 0, SIDE)
            for dz in (-SIDE, 0, SIDE)
            if (k := (tx + dx, tz + dz)) in labels
        )
        if any(
            (name == other and math.hypot(x - ox, z - oz) < 330)
            or (abs(z - oz) < 29 and abs(x - ox) < 7.5 * (len(name) + len(other)) + 8)
            for other, ox, oz in neighbours
        ):
            continue
        labels[tx, tz] = name, x, z
    return labels


def street_chart(region, layers, roads, x, z):
    """A vector tile in map metres. The browser displays only nine at a time."""

    def coords(points):
        return " ".join(f"{round(px - x)},{round(pz - z)}" for px, pz in points)

    def areas(geometry):
        return "".join(
            "M" + coords(ring.coords) + "Z"
            for poly in rings(geometry.simplify(0.7))
            for ring in [poly.exterior, *poly.interiors]
        )

    out = [
        f"<g transform='translate({x - west} {z - north})'><rect width='{SIDE}' height='{SIDE}' fill='#535e56'/>"
    ]
    for material, geometry, _ in layers:
        if material in ("water", "park"):
            color = "#28596a" if material == "water" else "#365548"
            out.append(
                f"<path fill='{color}' fill-rule='evenodd' d='{areas(geometry)}'/>"
            )
    blocks = "".join(
        areas(building.intersection(region)) for building, *_ in near(build_idx, region)
    )
    out.append(f"<path fill='#687269' fill-rule='evenodd' d='{blocks}'/>")
    strokes = collections.defaultdict(list)
    for line, width, *_ in roads:
        for part in pieces(line.intersection(region), "LineString"):
            strokes[round(width)].append("M" + coords(part.coords))
    for width, paths in sorted(strokes.items()):
        color = "#eed5a8" if width >= 10 else "#c9cec0"
        out.append(
            f"<path fill='none' stroke='{color}' stroke-width='{max(4, width)}' stroke-linecap='round' stroke-linejoin='round' d='{''.join(paths)}'/>"
        )
    if (x, z) in chart_labels:
        name, lx, lz = chart_labels[x, z]
        sector = (x - west) // SIDE + ((z - north) // SIDE) * ((east - west) // SIDE)
        out.append(
            f"<defs><text id='street-{sector}' x='{round(lx - west)}' y='{round(lz - north - 8)}' text-anchor='middle' font-family='sans-serif' font-size='23' font-weight='600' stroke='#38493e' stroke-width='3.5' paint-order='stroke' fill='#f5f6ed'>{escape(name)}</text></defs>"
        )
    return "".join(out) + "</g>"


def build_tile(task):
    col, row = task
    x, z = west + col * SIDE, north + row * SIDE
    region = box(x, z, x + SIDE, z + SIDE)
    halo = region.buffer(18, join_style="mitre")
    roads = near(road_idx, halo)
    if not roads and not land.intersects(region):
        return task, None
    mesh = Mesh(x, z)
    road, walkable, layers = surfaces(region, halo, roads)
    cells, ground = ground_mesh(mesh, road, layers)
    occ = Image.new("L", (SIDE, SIDE), 1)
    draw = ImageDraw.Draw(occ)
    for polygon in rings(walkable):
        draw_poly(draw, polygon, 0, (x, z), 1)
    buildings(mesh, region, occ)
    road_markings(mesh, region, roads)
    shops = street_props(mesh, near(prop_idx, region), roads, occ)
    scatter_furniture(mesh, roads, occ)
    contact = contact_bytes(x, z, cells, ground, occ)
    geometry = mesh.encode()
    signs = b"".join(
        struct.pack("<hhH", a, b, len(t.encode())) + t.encode() for a, b, t in shops
    )
    chart = street_chart(region, layers, roads, x, z).encode()
    data = (
        struct.pack("<IIII", len(contact), len(geometry), len(shops), len(chart))
        + contact
        + geometry
        + chart
        + signs
    )
    return task, packed(data)


# ---- Distant geometry and overview ----


def lower_relief(fine, stride):
    """A continuous coarse mesh below every triangle of the detailed DEM."""
    corners = fine[::stride, ::stride]
    a, b = corners[:-1, :-1], corners[:-1, 1:]
    d, c = corners[1:, :-1], corners[1:, 1:]
    rows, cols = a.shape
    excess = np.zeros_like(a)
    # Both grids use the NW to SE diagonal. The difference between their
    # planes reaches its maximum at a fine vertex, including on that diagonal.
    for j in range(stride + 1):
        for i in range(stride + 1):
            u, v = i / stride, j / stride
            coarse = (a + (b - a) * u + (c - b) * v if i >= j
                      else a + (c - d) * u + (d - a) * v)
            detail = fine[j:j + rows * stride:stride, i:i + cols * stride:stride]
            np.maximum(excess, coarse - detail, out=excess)
    # Neighbours share their corner heights. A quarter metre covers both
    # centimetre quantization and the depth precision of the distant mesh.
    drop = np.zeros_like(corners)
    for j, i in ((0, 0), (0, 1), (1, 0), (1, 1)):
        shared = drop[j:j + rows, i:i + cols]
        np.maximum(shared, excess, out=shared)
    return corners - drop - 0.25


def distant_city(buildings):
    # Coarse relief, water and the tallest actual buildings remain visible beyond
    # the detailed streets. The lower surface sits beneath nearby contact meshes.
    groups = collections.defaultdict(list)
    step = 128
    relief = lower_relief(samples, step // STEP)
    xs, zs = np.meshgrid(np.arange(west, east, step), np.arange(north, south, step))
    dry_cells = shapely.contains_xy(land, xs + step / 2, zs + step / 2)
    # All cells meeting an ocean corner share its sea level. From a bluff,
    # a coarse island with an open edge otherwise shows its own underside.
    wet_corners = {
        (int(x) + dx, int(z) + dz)
        for x, z in zip(xs[~dry_cells], zs[~dry_cells])
        for dx, dz in ((0, 0), (step, 0), (step, step), (0, step))
    }
    for row, z in enumerate(range(north, south, step)):
        for col, x in enumerate(range(west, east, step)):
            x0, x1, z0, z1 = x, x + step, z, z + step
            if dry_cells[row, col]:
                corners = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
                vs = []
                for (a, b), (dx, dz) in zip(corners, ((0, 0), (1, 0), (1, 1), (0, 1))):
                    y = relief[row + dz, col + dx]
                    vs.append((a, min(y, -0.15) if (a, b) in wet_corners else y, b))
                ground = groups["land"]
            else:
                # Continue seaward cells across the optical horizon. Driving
                # and collision still use the original survey bounds.
                reach = 32000
                x0 -= reach if x == west else 0
                x1 += reach if x1 == east else 0
                z0 -= reach if z == north else 0
                z1 += reach if z1 == south else 0
                vs = [
                    (a, -0.15, b) for a, b in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))
                ]
                ground = groups["water"]
            ground.extend((vs[0], vs[2], vs[1], vs[0], vs[3], vs[2]))
    for lake, level in water_idx[0]:
        if level > 0:
            for t in triangle_coords(lake.simplify(3)):
                groups["water"].extend((a, level - 0.15, b) for a, b in t)
    for poly, h, ident, style, _ in buildings:
        if h < 24:
            continue
        # An inset, closed footprint extends the middle-distance skyline.
        # Omit narrow appendages and stay inside the full-detail mesh nearby.
        for outline in rings(poly.simplify(1.8).buffer(-1.8, join_style="mitre")):
            base = min(height(x, z) for x, z in outline.exterior.coords) - 3
            top = base + h
            for t in triangle_coords(outline):
                groups["roof"].extend((x, top, z) for x, z in t)
            ring = list(outline.exterior.coords)
            for (x, z), (xx, zz) in zip(ring, ring[1:]):
                a, b, c, d = (x, base, z), (xx, base, zz), (xx, top, zz), (x, top, z)
                groups["house" + str(style)].extend((a, b, c, a, c, d))

    def beam(group, a, b, size):
        a, b = np.asarray(a), np.asarray(b)
        d = b - a
        d = d / np.linalg.norm(d)
        right = np.cross(d, [0, 1, 0]) if abs(d[1]) < 0.99 else np.array([1.0, 0, 0])
        right = right / np.linalg.norm(right) * size
        up = np.cross(d, right)
        corners = [right + up, right - up, -right - up, -right + up]
        for i, c in enumerate(corners):
            cc = corners[(i + 1) % 4]
            groups[group].extend([a + c, a + cc, b + cc, a + c, b + cc, b + c])

    def suspension(coords, material, deck, top):
        p, q = [np.array(local(lon, lat)) for lon, lat in coords]
        axis = q - p
        length = np.linalg.norm(axis)
        axis /= length
        side = np.array([-axis[1], axis[0]])

        def v(m, y, l):
            a, b = p + axis * m + side * l
            return a, y, b

        for m in (0, length):
            for l in (-16, 16):
                beam(material, v(m, 0, l), v(m, top, l), 3.4)
            for y in (deck + 4, top * 0.72, top - 4):
                beam(material, v(m, y, -16), v(m, y, 16), 3)
        for l in (-16, 16):

            def cable(m):
                return deck + 12 + (top - deck - 16) * (2 * m / length - 1) ** 2

            for i in range(32):
                a, b = length * i / 32, length * (i + 1) / 32
                beam(material, v(a, cable(a), l), v(b, cable(b), l), 0.85)
                beam(material, v(a, deck, l), v(a, cable(a), l), 0.30)

    BASE.update(orange=(0.57, 0.14, 0.064), steel=(0.43, 0.48, 0.52))
    suspension([(-122.4777, 37.8154), (-122.4795, 37.8269)], "orange", 68, 219)
    suspension([(-122.3854, 37.7898), (-122.3793, 37.7950)], "steel", 55, 143)
    suspension([(-122.3759, 37.7978), (-122.3702, 37.8024)], "steel", 55, 143)
    blob = bytearray()
    views = []
    acc = []
    prims = []
    mats = []
    for material, points in groups.items():
        points = np.asarray(points, dtype="<f4")
        idx = len(acc)
        raw = points.tobytes()
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)})
        blob.extend(raw)
        acc.append(
            {
                "bufferView": idx,
                "count": len(points),
                "componentType": 5126,
                "type": "VEC3",
                "min": points.min(axis=0).tolist(),
                "max": points.max(axis=0).tolist(),
            }
        )
        prims.append({"material": idx, "attributes": {"POSITION": idx}})
        mats.append(
            {
                "doubleSided": True,
                **({"extras": {"snailWater": True}} if material == "water" else {}),
                "pbrMetallicRoughness": {
                    "baseColorFactor": [*BASE[material], 1],
                    "roughnessFactor": 0.13 if material == "water" else 1,
                    "metallicFactor": 0,
                },
            }
        )
    doc = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": prims}],
        "materials": mats,
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": acc,
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    (ASSETS / "horizon.glb").write_bytes(
        struct.pack("<4sII", b"glTF", 2, 28 + len(js) + len(blob))
        + struct.pack("<I4s", len(js), b"JSON")
        + js
        + struct.pack("<I4s", len(blob), b"BIN\0")
        + blob
    )


def overview_map(survey, roads):
    overview = Image.new(
        "RGB", ((east - west) // 8, (south - north) // 8), (41, 69, 83)
    )
    dr = ImageDraw.Draw(overview)
    for p in rings(land):
        dr.polygon(path_data(p.exterior.coords), fill=(90, 96, 88))
    for p in survey.parks:
        dr.polygon(path_data(p.exterior.coords), fill=(67, 99, 75))
    for p in survey.water:
        dr.polygon(path_data(p.exterior.coords), fill=(41, 69, 83))
    for line, w, _, _, _, _ in sorted(roads, key=lambda r: r[1]):
        dr.line(
            path_data(line.coords),
            fill=(218, 192, 138) if w > 10 else (151, 159, 150),
            width=max(1, round(w / 6)),
        )
    overview.save(ASSETS / "sf-map.png", optimize=True)


# ---- Package the city ----


def pack_bands(temp, cols, rows, report):
    # Six immutable objects keep every source file comfortably below Git's blob limit.
    # Each is fetched at startup. Offsets in a band are local to its linked file.
    count = 0
    total = 0
    signs = 0
    for band in range(6):
        lo = rows * band // 6
        hi = rows * (band + 1) // 6
        offsets = [0]
        data = bytearray()
        for j in range(lo, hi):
            for i in range(cols):
                b = (temp / f"{i}-{j}").read_bytes()
                count += bool(b)
                data.extend(b)
                offsets.append(len(data))
                if b:
                    header = zlib.decompressobj(-15).decompress(memoryview(b)[4:], 12)
                    signs += struct.unpack_from("<I", header, 8)[0]
        header = struct.pack(
            "<4siiiiIII", b"SFB2", west, north, cols, rows, SIDE, lo, hi
        )
        out = header + np.asarray(offsets, dtype="<u4").tobytes() + data
        (ASSETS / f"sf-{band}.bin").write_bytes(out)
        total += len(out)
    report.update(land_sectors=count, packed_bytes=total, storefronts=signs)
    objects = {}
    for file in [
        *sorted(ASSETS.glob("sf-*.bin")),
        ASSETS / "streets.nav",
        ASSETS / "sf-map.png",
        ASSETS / "horizon.glb",
    ]:
        digest = file_hash(file)
        objects[file.name] = {
            "size": file.stat().st_size,
            "sha256": digest,
            "url": f"../store/sha256/{digest[:2]}/{digest}",
        }
    report["objects"] = objects


def file_hash(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for p in ("osm", "shore", "dem"):
        parser.add_argument(p, type=Path)
    parser.add_argument("--jobs", type=int, default=min(12, os.cpu_count() or 1))
    parser.add_argument("--work", type=Path, default=Path("build/sf-bake"))
    args = parser.parse_args()
    global \
        land, \
        road_land, \
        west, \
        north, \
        east, \
        south, \
        road_idx, \
        chart_labels, \
        build_idx, \
        prop_idx, \
        park_idx, \
        water_idx, \
        path_idx, \
        bridge_lines, \
        golden_lines
    shore = shape(json.loads(args.shore.read_bytes())["features"][0]["geometry"])
    # Drivable SF and the nearby islands. The Farallones have no connecting streets.
    land = shapely.transform(
        shore.intersection(box(-122.526, 37.705, -122.347, 37.841)),
        local,
        interleaved=False,
    ).simplify(1)
    landing = Point(*local(-122.4797, 37.8327)).buffer(320)
    road_land = land.buffer(24).union(landing)
    shapely.prepare(road_land)
    a, b, c, d = road_land.bounds
    west, north = math.floor(a / SIDE) * SIDE, math.floor(b / SIDE) * SIDE
    east, south = math.ceil(c / SIDE) * SIDE, math.ceil(d / SIDE) * SIDE
    cols, rows = (east - west) // SIDE, (south - north) // SIDE
    survey = Survey()
    survey.apply_file(str(args.osm), locations=True)
    roads = [
        (
            LineString([(x, z) for _, x, z in p]).simplify(0.45),
            w,
            name,
            one,
            bridge,
            kind,
        )
        for p, w, name, one, bridge, kind in survey.roads
    ]
    road_idx = lookup(roads, [r[0] for r in roads])
    chart_labels = street_labels(roads)
    build_idx = lookup(survey.buildings, [r[0] for r in survey.buildings])
    prop_idx = lookup(survey.props, [Point(x, z) for x, z, *_ in survey.props])
    park_idx = lookup(survey.parks, survey.parks)
    path_idx = lookup(survey.paths, survey.paths)
    bridge_lines = [
        g
        for g, w, name, one, bridge, k in roads
        if bridge
        and k in ("motorway", "motorway_link")
        and g.centroid.x > 1000
        and g.centroid.y < 2400
    ]
    golden_lines = [
        g for g, w, name, one, bridge, k in roads if name == "Golden Gate Bridge"
    ]
    terrain(args.dem)
    # Sample each inland lake once so adjacent tiles meet at the same waterline.
    water = []
    for body in survey.water:
        p = body.representative_point()
        water.append((body, height(p.x, p.y) if land.covers(p) else 0.0))
    water_idx = lookup(water, survey.water)
    ASSETS.mkdir(exist_ok=True)
    facade_textures()
    distant_city(survey.buildings)
    nodes, edges = navigation(survey.roads)
    overview_map(survey, roads)
    report = {
        "bounds": [west, north, east, south],
        "side": SIDE,
        "cols": cols,
        "rows": rows,
        "nodes": nodes,
        "directed_edges": edges,
        "roads": len(roads),
        "buildings": len(survey.buildings),
        "shops": sum(p[2] == "shop" for p in survey.props),
        "props": len(survey.props),
        "heights": [float(samples.min()), float(samples.max())],
        "sources": {
            name: file_hash(path)
            for name, path in [
                ("SanFrancisco.osm.pbf", args.osm),
                ("shoreline.geojson", args.shore),
                ("USGS_13_n38w123.tif", args.dem),
            ]
        },
    }
    print(report, flush=True)
    # A fingerprint keeps interrupted builds resumable without reusing stale sectors.
    identity = hashlib.sha256(
        Path(__file__).read_bytes() + json.dumps(report, sort_keys=True).encode()
    ).hexdigest()[:16]
    temp = args.work / identity
    temp.mkdir(parents=True, exist_ok=True)
    todo = [
        (i, j)
        for j in range(rows)
        for i in range(cols)
        if not (temp / f"{i}-{j}").exists()
    ]
    with concurrent.futures.ProcessPoolExecutor(
        args.jobs, mp_context=multiprocessing.get_context("fork")
    ) as pool:
        for k, ((i, j), data) in enumerate(pool.map(build_tile, todo, chunksize=2)):
            dest = temp / f"{i}-{j}"
            partial = dest.with_suffix(".partial")
            partial.write_bytes(data or b"")
            partial.replace(dest)
            if k % 240 == 0:
                print("sectors", k, "/", len(todo), flush=True)
    pack_bands(temp, cols, rows, report)
    (PUBLIC / "geodata/city.json").write_text(json.dumps(report, indent=2) + "\n")
    print("city packaged", report, flush=True)


if __name__ == "__main__":
    main()
