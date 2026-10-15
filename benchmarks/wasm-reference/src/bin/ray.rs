use r7rs_wasm_reference::{input, report};
use std::fs::{File, remove_file};
use std::hint::black_box;
use std::io::{self, BufWriter, Write};
use std::time::Instant;

// ---- Points and sphere intersections ----

#[derive(Clone, Copy, Debug)]
struct Point {
    x: f64,
    y: f64,
    z: f64,
}
struct Sphere {
    color: f64,
    radius: f64,
    center: Point,
}
const EYE: Point = Point {
    x: 0.0,
    y: 0.0,
    z: 200.0,
};

fn magnitude(x: f64, y: f64, z: f64) -> f64 {
    (x * x + y * y + z * z).sqrt()
}
fn unit(x: f64, y: f64, z: f64) -> Point {
    let distance = magnitude(x, y, z);
    Point {
        x: x / distance,
        y: y / distance,
        z: z / distance,
    }
}
fn distance(a: Point, b: Point) -> f64 {
    magnitude(a.x - b.x, a.y - b.y, a.z - b.z)
}

fn minimum_root(a: f64, b: f64, c: f64) -> Option<f64> {
    if a == 0.0 {
        return Some(-c / b);
    }
    let discriminant = b * b - 4.0 * a * c;
    if discriminant < 0.0 {
        return None;
    }
    let root = discriminant.sqrt();
    Some(((-b + root) / (2.0 * a)).min((-b - root) / (2.0 * a)))
}

fn intersect(s: &Sphere, pt: Point, ray: Point) -> Option<Point> {
    let (dx, dy, dz) = (pt.x - s.center.x, pt.y - s.center.y, pt.z - s.center.z);
    let n = minimum_root(
        ray.x * ray.x + ray.y * ray.y + ray.z * ray.z,
        2.0 * (dx * ray.x + dy * ray.y + dz * ray.z),
        dx * dx + dy * dy + dz * dz - s.radius * s.radius,
    )?;
    Some(Point {
        x: pt.x + n * ray.x,
        y: pt.y + n * ray.y,
        z: pt.z + n * ray.z,
    })
}

// ---- Nearest surface and Lambert illumination ----

fn first_hit(world: &[Sphere], pt: Point, ray: Point) -> Option<(&Sphere, Point)> {
    let (mut result, mut nearest) = (None, 1e308);
    for sphere in world {
        if let Some(hit) = intersect(sphere, pt, ray) {
            let d = distance(hit, pt);
            if d < nearest {
                nearest = d;
                result = Some((sphere, hit));
            }
        }
    }
    result
}

fn lambert(s: &Sphere, hit: Point, ray: Point) -> f64 {
    let normal = unit(s.center.x - hit.x, s.center.y - hit.y, s.center.z - hit.z);
    (ray.x * normal.x + ray.y * normal.y + ray.z * normal.z).max(0.0)
}

fn color_at(world: &[Sphere], x: f64, y: f64) -> u32 {
    let ray = unit(x - EYE.x, y - EYE.y, -EYE.z);
    let color = first_hit(world, EYE, ray).map_or(0.0, |(s, p)| lambert(s, p, ray) * s.color);
    (color * 255.0).round_ties_even() as u32
}

fn scene() -> Vec<Sphere> {
    let mut world = vec![
        Sphere {
            color: 0.8,
            radius: 200.0,
            center: Point {
                x: 0.0,
                y: -300.0,
                z: -1200.0,
            },
        },
        Sphere {
            color: 0.7,
            radius: 200.0,
            center: Point {
                x: -80.0,
                y: -150.0,
                z: -1200.0,
            },
        },
        Sphere {
            color: 0.9,
            radius: 200.0,
            center: Point {
                x: 70.0,
                y: -100.0,
                z: -1200.0,
            },
        },
    ];
    for x in -2..=2 {
        for z in 2..=7 {
            world.push(Sphere {
                color: 0.75,
                radius: 40.0,
                center: Point {
                    x: x as f64 * 200.0,
                    y: 300.0,
                    z: z as f64 * -400.0,
                },
            });
        }
    }
    world.reverse(); // Source defsphere prepends every sphere.
    world
}

// ---- Complete ASCII PGM output ----

fn trace(filename: &str, resolution: usize) -> io::Result<()> {
    let world = scene();
    if std::path::Path::new(filename).exists() {
        remove_file(filename)?;
    }
    let mut out = BufWriter::new(File::create(filename)?);
    let extent = resolution * 100;
    writeln!(out, "P2 {extent} {extent} 255")?;
    for y in 0..extent {
        for x in 0..extent {
            writeln!(
                out,
                "{}",
                color_at(
                    &world,
                    -50.0 + x as f64 / resolution as f64,
                    -50.0 + y as f64 / resolution as f64
                )
            )?;
        }
    }
    out.flush()
}

// ---- Benchmark driver ----

fn main() -> io::Result<()> {
    let values = input()?;
    let (count, resolution, filename) = (values[0].number(), values[1].number(), values[2].atom());
    let start = Instant::now();
    for _ in 0..count {
        trace(black_box(filename), black_box(resolution))?;
    }
    assert_eq!(values[3].atom(), "ok");
    report("ray", count, start, "ok");
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn closest_root_hit_and_missing_surface() {
        assert_eq!(minimum_root(1.0, -5.0, 6.0), Some(2.0));
        assert_eq!(minimum_root(1.0, 0.0, 1.0), None);
        let sphere = Sphere {
            color: 1.0,
            radius: 1.0,
            center: Point {
                x: 0.0,
                y: 0.0,
                z: 0.0,
            },
        };
        let hit = intersect(
            &sphere,
            Point {
                x: 0.0,
                y: 0.0,
                z: 3.0,
            },
            Point {
                x: 0.0,
                y: 0.0,
                z: -1.0,
            },
        )
        .unwrap();
        assert_eq!((hit.x, hit.y, hit.z), (0.0, 0.0, 1.0));
        assert_eq!(scene().len(), 33);
    }
}
