//! A tick of road traffic. Snail owns the bodies between ticks, including their
//! world-space momenta. No Rust handle, wheel, or contact cache enters a save.
use rapier3d_f64::control::{DynamicRayCastVehicleController, WheelTuning};
use rapier3d_f64::prelude::*;
use std::cell::RefCell;
use std::collections::BTreeSet;

struct Traffic {
    world: PhysicsWorld,
    hull: SharedShape,
    track: f64,
    wheelbase: f64,
    ride_height: f64,
    actors: Vec<Actor>,
    cars: Vec<Car>,
    walkers: Vec<Walker>,
    walls: BTreeSet<[u64; 4]>,
}

struct Actor {
    body: RigidBodyHandle,
    mass: f64,
    inertia: Vector,
    result: [f64; 13],
}

struct Car {
    wheels: DynamicRayCastVehicleController,
    road: ColliderHandle,
    can_park: bool,
    force: f64,
    steer: f64,
}

struct Walker {
    body: RigidBodyHandle,
    collider: ColliderHandle,
    active: bool,
}

// ---- City geometry ----

// Each actor samples the city's grade at its own position. Only that actor may
// touch its tangent plane. Walls and the other bodies are shared by the fleet.
struct RoadContact;

impl PhysicsHooks for RoadContact {
    fn filter_contact_pair(&self, ctx: &PairFilterContext) -> Option<SolverFlags> {
        let a = &ctx.colliders[ctx.collider1];
        let b = &ctx.colliders[ctx.collider2];
        (a.user_data == b.user_data).then_some(SolverFlags::COMPUTE_RIGID_IMPULSES)
    }
}

fn bodywork(width: f64, length: f64) -> SharedShape {
    // Sloping bonnet and boot transfer some of a bumper impact upwards.
    let mut corners = Vec::new();
    for (y, inset_x, inset_z) in [
        (-0.33, 0.10, 0.2),
        (-0.12, 0.0, 0.0),
        (0.17, 0.04, 0.58),
        (0.68, 0.16, 1.45),
    ] {
        for x in [-1.0, 1.0] {
            for z in [-1.0, 1.0] {
                corners.push(Vector::new(
                    x * (width * 0.5 - inset_x),
                    y,
                    z * (length * 0.5 - inset_z),
                ));
            }
        }
    }
    SharedShape::convex_hull(&corners).expect("solid car bodywork")
}

impl Traffic {
    fn new(width: f64, length: f64, wheelbase: f64, ride_height: f64) -> Self {
        Self {
            world: PhysicsWorld::default(),
            hull: bodywork(width, length),
            track: 0.41 * width,
            wheelbase,
            ride_height,
            actors: Vec::new(),
            cars: Vec::new(),
            walkers: Vec::new(),
            walls: BTreeSet::new(),
        }
    }

    fn road(&mut self, id: usize, point: Vector, normal: Vector) -> ColliderHandle {
        let rotation = Rotation::from_rotation_arc(Vector::Y, normal);
        let road = ColliderBuilder::cuboid(12.0, 0.5, 12.0)
            .position(Pose::from_parts(point - normal * 0.5, rotation))
            .user_data(id as u128 + 1)
            .active_hooks(ActiveHooks::FILTER_CONTACT_PAIRS);
        let handle = self.world.insert_collider(road, None);
        // The first wheel query precedes the first physics step. Publish just
        // the road bounds so the dynamics pipeline still sees every new body.
        self.world.broad_phase.set_aabb(
            &self.world.integration_parameters,
            handle,
            self.world.colliders[handle].compute_aabb(),
        );
        handle
    }

    fn wall(&mut self, west: f64, north: f64, east: f64, south: f64) {
        if self
            .walls
            .insert([west, north, east, south].map(f64::to_bits))
        {
            // City footprints are vertical obstacles throughout the playable elevation range.
            let wall = ColliderBuilder::cuboid((east - west) * 0.5, 2048.0, (south - north) * 0.5)
                .translation(Vector::new((west + east) * 0.5, 0.0, (north + south) * 0.5));
            self.world.insert_collider(wall, None);
        }
    }

    fn body(
        &mut self,
        pose: Pose,
        momentum: Vector,
        angular: Vector,
        mass: f64,
        inertia: Vector,
    ) -> usize {
        let spin = pose.rotation * ((pose.rotation.conjugate() * angular) / inertia);
        let body = RigidBodyBuilder::dynamic()
            .pose(pose)
            .linvel(momentum / mass)
            .angvel(spin)
            .additional_mass_properties(MassProperties::new(Vector::ZERO, mass, inertia));
        let handle = self.world.insert_body(body);
        let id = self.actors.len();
        self.actors.push(Actor {
            body: handle,
            mass,
            inertia,
            result: [0.0; 13],
        });
        id
    }

    fn car(&mut self, id: usize, road: ColliderHandle, accel: f64, steer: f64, can_park: bool) {
        let actor = &self.actors[id];
        let shape = ColliderBuilder::new(self.hull.clone())
            .density(0.0)
            .friction(0.45)
            .user_data(id as u128 + 1);
        self.world.insert_collider(shape, Some(actor.body));
        self.world.bodies[actor.body]
            .recompute_mass_properties_from_colliders(&self.world.colliders);
        self.cars.push(Car {
            wheels: wheels(actor.body, self.track, self.wheelbase, self.ride_height),
            road,
            can_park,
            force: actor.mass * accel * 0.25,
            steer,
        });
    }

    fn walker(&mut self, id: usize, active: bool) {
        let body = self.actors[id].body;
        self.world.bodies[body].set_gravity_scale(if active { 1.0 } else { 0.0 }, true);
        self.world.bodies[body].set_angular_damping(1.5);
        let shape = ColliderBuilder::new(walker_shape(active))
            .density(0.0)
            .friction(0.85)
            .user_data(id as u128 + 1);
        let collider = self.world.insert_collider(shape, Some(body));
        self.walkers.push(Walker {
            body,
            collider,
            active,
        });
    }

    // ---- Fleet step ----

    fn step(&mut self, seconds: f64) {
        let steps = (seconds / 0.0125).ceil().max(1.0) as usize;
        self.world.integration_parameters.dt = seconds / steps as f64;
        for _ in 0..steps {
            for car in &mut self.cars {
                car.drive(&mut self.world, self.ride_height);
            }
            self.world.step_with_events(&RoadContact, &());
            for walker in &mut self.walkers {
                walker.observe(&mut self.world, &self.cars);
            }
        }
        for actor in &mut self.actors {
            actor.capture(&self.world.bodies[actor.body]);
        }
    }
}

// ---- Wheels and pedestrians ----

fn wheels(
    body: RigidBodyHandle,
    track: f64,
    wheelbase: f64,
    ride_height: f64,
) -> DynamicRayCastVehicleController {
    let mut wheels = DynamicRayCastVehicleController::new(body);
    wheels.index_forward_axis = 2;
    // At rest four springs compress 9.81 / (4 * stiffness) metres.
    let tuning = WheelTuning {
        suspension_stiffness: 40.0,
        suspension_compression: 4.5,
        suspension_damping: 5.0,
        max_suspension_travel: 0.27,
        ..Default::default()
    };
    let radius = 0.24;
    let rest_length = ride_height - radius + 9.81 / (4.0 * tuning.suspension_stiffness);
    for z in [-0.5 * wheelbase, 0.5 * wheelbase] {
        for x in [-track, track] {
            wheels.add_wheel(
                Vector::new(x, 0.0, z),
                -Vector::Y,
                Vector::X,
                rest_length,
                radius,
                &tuning,
            );
        }
    }
    wheels
}

impl Car {
    fn drive(&mut self, world: &mut PhysicsWorld, ride_height: f64) {
        let body = &mut world.bodies[self.wheels.chassis];
        if self.can_park && self.supported_at_rest(body, &world.colliders[self.road], ride_height) {
            body.sleep();
            return;
        }
        for (index, wheel) in self.wheels.wheels_mut().iter_mut().enumerate() {
            wheel.engine_force = self.force;
            wheel.steering = if index < 2 { -self.steer } else { 0.0 };
        }
        let own_road = |handle, _: &Collider| handle == self.road;
        let queries = world.broad_phase.as_query_pipeline_mut(
            world.narrow_phase.query_dispatcher(),
            &mut world.bodies,
            &mut world.colliders,
            QueryFilter::default().predicate(&own_road),
        );
        self.wheels
            .update_vehicle(world.integration_parameters.dt, queries);
    }

    fn supported_at_rest(&self, body: &RigidBody, road: &Collider, ride_height: f64) -> bool {
        let floor = road.position();
        let normal = floor.rotation * Vector::Y;
        if normal.y < 0.76
            || body.linvel().length_squared() >= 0.012
            || body.angvel().length_squared() >= 0.025
        {
            return false;
        }
        // Static tyre friction holds a stopped cab only when all four wheel
        // mounts are at ride height. An airborne or overturned cab falls.
        let up = body.rotation() * Vector::Y;
        up.dot(normal) > 0.99
            && self.wheels.wheels().iter().all(|wheel| {
                let mount = body
                    .position()
                    .transform_point(wheel.chassis_connection_point_cs);
                let height = (mount - floor.translation).dot(normal) - 0.5;
                (height - ride_height).abs() < 0.055
            })
    }
}

// Foot placement belongs to the walking animation. The torso can be struck by
// a bumper; a fallen pedestrian also has support all the way down to the feet.
fn walker_shape(fallen: bool) -> SharedShape {
    let lower = if fallen { -0.52 } else { 0.30 };
    SharedShape::capsule(Vector::Y * lower, Vector::Y * 0.52, 0.30)
}

impl Walker {
    fn observe(&mut self, world: &mut PhysicsWorld, cars: &[Car]) {
        if !self.active
            && cars.iter().any(|car| {
                let body = &world.bodies[car.wheels.chassis];
                body.linvel().length_squared() > 0.16
                    && world
                        .contact_pair(self.collider, body.colliders()[0])
                        .is_some_and(|pair| pair.has_any_active_contact())
            })
        {
            self.active = true;
            world.colliders[self.collider].set_shape(walker_shape(true));
            world.bodies[self.body].set_gravity_scale(1.0, true);
        }
    }
}

impl Actor {
    fn capture(&mut self, body: &RigidBody) {
        let q = *body.rotation();
        let momentum = body.linvel() * self.mass;
        let angular = q * ((q.conjugate() * body.angvel()) * self.inertia);
        self.result[..3].copy_from_slice(&body.translation().to_array());
        self.result[3..7].copy_from_slice(&q.to_array());
        self.result[7..10].copy_from_slice(&momentum.to_array());
        self.result[10..].copy_from_slice(&angular.to_array());
    }
}

// ---- Scalar Wasm boundary ----

// begin through end is one synchronous Snail call with no effects that can
// suspend or call back into the game. Indices are valid only within that call.
thread_local! {
    static TRAFFIC: RefCell<Option<Traffic>> = const { RefCell::new(None) };
}

fn with_traffic<T>(f: impl FnOnce(&mut Traffic) -> T) -> T {
    TRAFFIC.with_borrow_mut(|world| f(world.as_mut().expect("begin a traffic tick")))
}

#[unsafe(export_name = "snail:traffic/begin")]
pub extern "C" fn begin(width: f64, length: f64, wheelbase: f64, ride_height: f64) {
    TRAFFIC.set(Some(Traffic::new(width, length, wheelbase, ride_height)));
}

#[unsafe(export_name = "snail:traffic/body")]
pub extern "C" fn body(
    x: f64,
    y: f64,
    z: f64,
    qx: f64,
    qy: f64,
    qz: f64,
    qw: f64,
    px: f64,
    py: f64,
    pz: f64,
    lx: f64,
    ly: f64,
    lz: f64,
    inv_mass: f64,
    ix: f64,
    iy: f64,
    iz: f64,
) -> i64 {
    let pose = Pose::from_parts(
        Vector::new(x, y, z),
        Rotation::from_xyzw(qx, qy, qz, qw).normalize(),
    );
    with_traffic(|t| {
        t.body(
            pose,
            Vector::new(px, py, pz),
            Vector::new(lx, ly, lz),
            1.0 / inv_mass,
            Vector::new(ix, iy, iz).recip(),
        ) as i64
    })
}

#[unsafe(export_name = "snail:traffic/wall")]
pub extern "C" fn wall(west: f64, north: f64, east: f64, south: f64) {
    with_traffic(|t| t.wall(west, north, east, south));
}

#[unsafe(export_name = "snail:traffic/car")]
pub extern "C" fn car(
    id: i64,
    x: f64,
    y: f64,
    z: f64,
    nx: f64,
    ny: f64,
    nz: f64,
    accel: f64,
    steer: f64,
    park: i32,
) {
    with_traffic(|t| {
        let road = t.road(id as usize, Vector::new(x, y, z), Vector::new(nx, ny, nz));
        t.car(id as usize, road, accel, steer, park != 0);
    });
}

#[unsafe(export_name = "snail:traffic/walker")]
pub extern "C" fn walker(id: i64, x: f64, y: f64, z: f64, nx: f64, ny: f64, nz: f64, active: i32) {
    with_traffic(|t| {
        t.road(id as usize, Vector::new(x, y, z), Vector::new(nx, ny, nz));
        t.walker(id as usize, active != 0);
    });
}

#[unsafe(export_name = "snail:traffic/step")]
pub extern "C" fn step(seconds: f64) {
    with_traffic(|t| t.step(seconds));
}

#[unsafe(export_name = "snail:traffic/value")]
pub extern "C" fn value(id: i64, component: i64) -> f64 {
    with_traffic(|t| t.actors[id as usize].result[component as usize])
}

#[unsafe(export_name = "snail:traffic/walker-active")]
pub extern "C" fn walker_active(index: i64) -> i32 {
    with_traffic(|t| i32::from(t.walkers[index as usize].active))
}

#[unsafe(export_name = "snail:traffic/end")]
pub extern "C" fn end() {
    TRAFFIC.set(None);
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn four_wheels_see_only_their_own_street_from_the_first_substep() {
        let mut traffic = Traffic::new(1.875, 4.6, 2.376, 0.60);
        // The low car is airborne over its road. A neighbour's raised road
        // runs directly under its wheels, but must support only the neighbour.
        for (x, road_height) in [(0.0, 0.0), (4.0, 8.0)] {
            let pose = Pose::from_translation(Vector::new(x, 8.6, 0.0));
            let id = traffic.body(
                pose,
                Vector::ZERO,
                Vector::ZERO,
                1500.0,
                Vector::splat(1000.0),
            );
            let road = traffic.road(id, Vector::new(x, road_height, 0.0), Vector::Y);
            traffic.car(id, road, 4.0, 0.0, false);
        }
        traffic.step(0.0125);
        let grounded = |car: &Car| {
            car.wheels
                .wheels()
                .iter()
                .filter(|wheel| wheel.raycast_info().is_in_contact)
                .count()
        };
        assert_eq!(grounded(&traffic.cars[0]), 0);
        assert_eq!(grounded(&traffic.cars[1]), 4);
        assert!(traffic.actors[0].result[1] < 8.6);
        assert!(traffic.actors[1].result[2] < 0.0);
    }
}
