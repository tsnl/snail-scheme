//! A walking trial in the game's Rapier world. +x is forward, +y is up.
//! The pelvis can translate and pitch in the sagittal plane. Its six leg
//! motors only exchange torque with their parent. Only the ground can propel it.
use rapier3d_f64::prelude::*;
use std::cell::RefCell;

struct Biped {
    world: PhysicsWorld,
    pelvis: RigidBodyHandle,
    legs: [Leg; 2],
}

struct Leg {
    links: [RigidBodyHandle; 3],
    joints: [ImpulseJointHandle; 3],
}

// Origins are the anatomical joints. Offsetting each collider below its joint
// gives the dynamic body the corresponding centre of mass and inertia.
const THIGH: f64 = 0.421546;
const SHIN: f64 = 0.409870;
// The toe and heel used to place a walker at reset are the round box below.
const SOLE_CENTER: Vector = Vector::new(0.047, -0.022, 0.0);
const SOLE_HALF: Vector = Vector::new(0.104, 0.021, 0.04);
const BEVEL: f64 = 0.012;

fn segment(world: &mut PhysicsWorld, pose: Pose, collider: ColliderBuilder) -> RigidBodyHandle {
    let body = world.insert_body(
        RigidBodyBuilder::dynamic()
            .pose(pose)
            .enabled_translations(true, true, false)
            .enabled_rotations(false, false, true)
            .can_sleep(false),
    );
    world.insert_collider(collider.friction(0.9), Some(body));
    body
}

impl Leg {
    fn new(world: &mut PhysicsWorld, pelvis: RigidBodyHandle, side: f64, angles: [f64; 3]) -> Self {
        let mut parent = pelvis;
        let mut attach = Vector::new(0.0, 0.0, side * 0.085);
        let pairs = std::array::from_fn::<_, 3, _>(|i| {
            let shape = match i {
                0 => ColliderBuilder::capsule_y(0.15, 0.055)
                    .mass(4.5)
                    .translation(-Vector::Y * (THIGH / 2.0)),
                1 => ColliderBuilder::capsule_y(0.15, 0.05)
                    .mass(3.0)
                    .translation(-Vector::Y * (SHIN / 2.0)),
                _ => ColliderBuilder::round_cuboid(SOLE_HALF.x, SOLE_HALF.y, SOLE_HALF.z, BEVEL)
                    .mass(1.0)
                    .translation(SOLE_CENTER),
            };
            let pose = world.bodies[parent].position()
                * Pose::from_parts(attach, Rotation::from_rotation_z(angles[i]));
            let child = segment(world, pose, shape);
            let limits = [[-1.25, 1.6], [-2.45, 0.04], [-0.9, 0.9]][i];
            let joint = RevoluteJointBuilder::new(Vector::Z)
                .local_anchor1(attach)
                .limits(limits)
                .contacts_enabled(false)
                .motor_model(MotorModel::ForceBased)
                .motor_max_force([160.0, 125.0, 90.0][i]);
            let handle = world.insert_impulse_joint(parent, child, joint);
            parent = child;
            attach = -Vector::Y * [THIGH, SHIN, 0.0][i];
            (child, handle)
        });
        Self {
            links: pairs.map(|p| p.0),
            joints: pairs.map(|p| p.1),
        }
    }

    fn drive(&self, world: &mut PhysicsWorld, targets: [f64; 3]) {
        for (i, target) in targets.into_iter().enumerate() {
            let joint = world.impulse_joints.get_mut(self.joints[i], false).unwrap();
            joint.data.set_motor_position(
                JointAxis::AngX,
                target,
                [520.0, 440.0, 220.0][i],
                [32.0, 24.0, 13.0][i],
            );
        }
    }
}

impl Biped {
    fn new(height: f64, pitch: f64, angles: [[f64; 3]; 2]) -> Self {
        let mut world = PhysicsWorld::default();
        world.integration_parameters.dt = 1.0 / 120.0;
        let pelvis = segment(
            &mut world,
            Pose::from_parts(Vector::Y * height, Rotation::from_rotation_z(pitch)),
            ColliderBuilder::capsule_y(0.19, 0.115)
                .translation(Vector::Y * 0.24)
                .mass(28.0),
        );
        let legs = [
            Leg::new(&mut world, pelvis, 1.0, angles[0]),
            Leg::new(&mut world, pelvis, -1.0, angles[1]),
        ];
        Self {
            world,
            pelvis,
            legs,
        }
    }

    fn place_feet(&mut self, points: &[(f64, f64)]) {
        // Seed on the terrain. The round box touches where its inner heel
        // or toe has the least clearance, with the bevel below that point.
        let mut clearance = f64::INFINITY;
        for leg in &self.legs {
            let foot = self.world.bodies[leg.links[2]].position();
            for x in [-SOLE_HALF.x, SOLE_HALF.x] {
                let p = foot * (SOLE_CENTER + Vector::new(x, -SOLE_HALF.y, 0.0));
                clearance = clearance.min(p.y - BEVEL - surface_height(points, p.x));
            }
        }
        for (_, body) in self.world.bodies.iter_mut() {
            body.set_translation(body.translation() - Vector::Y * clearance, true);
        }
    }

    fn ground(&mut self, points: &[(f64, f64)]) {
        self.place_feet(points);
        let vertices = points
            .iter()
            .flat_map(|&(x, y)| [-1.0, 1.0].map(|z| Vector::new(x, y, z)))
            .collect();
        let triangles = (0..points.len() as u32 - 1)
            .flat_map(|i| {
                let j = 2 * i;
                [[j, j + 1, j + 2], [j + 1, j + 3, j + 2]]
            })
            .collect();
        let shape = ColliderBuilder::trimesh_with_flags(
            vertices,
            triangles,
            TriMeshFlags::FIX_INTERNAL_EDGES,
        )
        .expect("ordered walking surface");
        self.world.insert_collider(shape.friction(0.9), None);
    }

    fn step(&mut self, angles: [[f64; 3]; 2]) {
        for (leg, targets) in self.legs.iter().zip(angles) {
            leg.drive(&mut self.world, targets);
        }
        for _ in 0..4 {
            self.world.step();
        }
    }

    fn body(&self, link: usize) -> &RigidBody {
        let handle = if link == 0 {
            self.pelvis
        } else {
            self.legs[(link - 1) / 3].links[(link - 1) % 3]
        };
        &self.world.bodies[handle]
    }
}

fn surface_height(points: &[(f64, f64)], x: f64) -> f64 {
    let i = points
        .partition_point(|p| p.0 < x)
        .clamp(1, points.len() - 1);
    let (a, h) = points[i - 1];
    let (b, k) = points[i];
    h + (k - h) * ((x - a) / (b - a)).clamp(0.0, 1.0)
}

fn seed_velocity(body: &mut RigidBody, velocity: Vector, rate: f64) {
    let omega = Vector::Z * rate;
    body.set_linvel(
        velocity + omega.cross(body.center_of_mass() - body.translation()),
        true,
    );
    body.set_angvel(omega, true);
}

// ---- Scalar boundary ----

// One active trial per instance. Starting a trial drops the previous world's
// bodies, contacts and warm-start impulses. No managed pointer enters Rust.
thread_local! {
    static TRIAL: RefCell<Option<Biped>> = const { RefCell::new(None) };
    static PROFILE: RefCell<Vec<(f64, f64)>> = const { RefCell::new(Vec::new()) };
}

#[unsafe(export_name = "snail:biped/ground-point")]
pub extern "C" fn ground_point(x: f64, y: f64) {
    PROFILE.with_borrow_mut(|points| points.push((x, y)));
}

#[unsafe(export_name = "snail:biped/start")]
pub extern "C" fn start(
    height: f64,
    pitch: f64,
    rh: f64,
    rk: f64,
    ra: f64,
    lh: f64,
    lk: f64,
    la: f64,
) {
    let mut trial = Biped::new(height, pitch, [[rh, rk, ra], [lh, lk, la]]);
    PROFILE.with_borrow_mut(|points| {
        trial.ground(points);
        points.clear();
    });
    TRIAL.set(Some(trial));
}

// Seed the captured joint velocities once at reset. Rapier stores linear
// velocity at the centre of mass, while the clip measures joint origins.
#[unsafe(export_name = "snail:biped/launch")]
pub extern "C" fn launch(
    vx: f64,
    vy: f64,
    spin: f64,
    rh: f64,
    rk: f64,
    ra: f64,
    lh: f64,
    lk: f64,
    la: f64,
) {
    TRIAL.with_borrow_mut(|trial| {
        let b = trial.as_mut().unwrap();
        seed_velocity(
            &mut b.world.bodies[b.pelvis],
            Vector::new(vx, vy, 0.0),
            spin,
        );
        for (leg, rates) in b.legs.iter().zip([[rh, rk, ra], [lh, lk, la]]) {
            let mut parent = b.pelvis;
            for (child, rate) in leg.links.into_iter().zip(rates) {
                let base = &b.world.bodies[parent];
                let v = base.velocity_at_point(b.world.bodies[child].translation());
                let w = base.angvel().z + rate;
                seed_velocity(&mut b.world.bodies[child], v, w);
                parent = child;
            }
        }
    });
}

#[unsafe(export_name = "snail:biped/step")]
pub extern "C" fn step(rh: f64, rk: f64, ra: f64, lh: f64, lk: f64, la: f64) {
    TRIAL.with_borrow_mut(|t| t.as_mut().unwrap().step([[rh, rk, ra], [lh, lk, la]]));
}

#[unsafe(export_name = "snail:biped/state")]
pub extern "C" fn state(link: i64, axis: i64) -> f64 {
    TRIAL.with_borrow(|t| {
        let b = t.as_ref().unwrap().body(link as usize);
        match axis {
            0 => b.translation().x,
            1 => b.translation().y,
            2 => {
                let x = b.rotation() * Vector::X;
                x.y.atan2(x.x)
            }
            3 => b.linvel().x,
            4 => b.angvel().z,
            _ => unreachable!("unknown biped coordinate"),
        }
    })
}

#[unsafe(export_name = "snail:biped/end")]
pub extern "C" fn end() {
    TRIAL.set(None);
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn motors_cannot_propel_an_airborne_walker() {
        let mut b = Biped::new(4.0, 0.0, [[0.2, -0.4, 0.2]; 2]);
        for _ in 0..12 {
            b.step([[0.5, -0.9, 0.3], [-0.2, -0.1, 0.0]]);
        }
        let momentum: f64 = b
            .world
            .bodies
            .iter()
            .map(|(_, body)| body.mass() * body.linvel().x)
            .sum();
        assert!(momentum.abs() < 1e-7, "horizontal momentum {momentum}");
        assert!(b.body(0).translation().y < 3.6);
    }

    #[test]
    fn a_grade_places_the_lowest_sole_at_contact() {
        let mut b = Biped::new(1.7, 0.0, [[0.0; 3]; 2]);
        b.ground(&[(-2.0, -0.2), (2.0, 0.2)]);
        let foot = b.body(3).position();
        let toe = foot * Vector::new(0.151, -0.043, 0.0);
        assert!((toe.y - 0.012 - 0.1 * toe.x).abs() < 1e-7);
    }
}
