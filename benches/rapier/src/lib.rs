//! The test track belongs to this Wasm instance. Only controls and observations cross into Snail.
extern crate snail_scheme_support as _;

use rapier3d_f64::control::{DynamicRayCastVehicleController, WheelTuning};
use rapier3d_f64::prelude::*;
use std::cell::RefCell;

struct Track {
    world: PhysicsWorld,
    car: DynamicRayCastVehicleController,
}

impl Track {
    fn new() -> Self {
        let mut world = PhysicsWorld::default();
        world.integration_parameters.dt = 1.0 / 60.0;
        world.insert_collider(
            ColliderBuilder::cuboid(20.0, 0.5, 100.0).translation(Vector::new(0.0, -0.5, 0.0)),
            None,
        );
        let (chassis, _) = world.insert(
            RigidBodyBuilder::dynamic().translation(Vector::new(0.0, 3.0, 0.0)),
            ColliderBuilder::cuboid(0.8, 0.24, 1.5).mass(640.0),
        );
        Self {
            world,
            car: vehicle(chassis),
        }
    }

    fn step(&mut self, force: f64) -> f64 {
        for wheel in self.car.wheels_mut() {
            wheel.engine_force = force;
        }
        let world = &mut self.world;
        let ground = world.broad_phase.as_query_pipeline_mut(
            world.narrow_phase.query_dispatcher(),
            &mut world.bodies,
            &mut world.colliders,
            QueryFilter::default().exclude_rigid_body(self.car.chassis),
        );
        self.car
            .update_vehicle(world.integration_parameters.dt, ground);
        world.step();
        world.bodies[self.car.chassis].translation().z
    }
}

fn vehicle(chassis: RigidBodyHandle) -> DynamicRayCastVehicleController {
    let mut car = DynamicRayCastVehicleController::new(chassis);
    car.index_forward_axis = 2;
    let tuning = WheelTuning {
        suspension_stiffness: 24.0,
        ..Default::default()
    };
    for z in [-1.1, 1.1] {
        for x in [-0.75, 0.75] {
            car.add_wheel(
                Vector::new(x, 0.0, z),
                -Vector::Y,
                -Vector::X,
                0.42,
                0.32,
                &tuning,
            );
        }
    }
    car
}

// A single track per instance suffices for this example. Reset and close drop all bodies together.
thread_local! {
    static TRACK: RefCell<Option<Track>> = const { RefCell::new(None) };
}

#[unsafe(export_name = "snail:rapier/reset")]
pub extern "C" fn reset() {
    TRACK.set(Some(Track::new()));
}

#[unsafe(export_name = "snail:rapier/step")]
pub extern "C" fn step(force: f64) -> f64 {
    TRACK.with_borrow_mut(|track| {
        track
            .as_mut()
            .expect("reset the track before stepping")
            .step(force)
    })
}

#[unsafe(export_name = "snail:rapier/height")]
pub extern "C" fn height() -> f64 {
    TRACK.with_borrow(|track| {
        let track = track.as_ref().expect("reset the track before reading it");
        track.world.bodies[track.car.chassis].translation().y
    })
}

#[unsafe(export_name = "snail:rapier/grounded-wheels")]
pub extern "C" fn grounded_wheels() -> i32 {
    TRACK.with_borrow(|track| {
        let track = track.as_ref().expect("reset the track before reading it");
        track
            .car
            .wheels()
            .iter()
            .filter(|w| w.raycast_info().is_in_contact)
            .count() as i32
    })
}

#[unsafe(export_name = "snail:rapier/close")]
pub extern "C" fn close() {
    TRACK.set(None);
}
