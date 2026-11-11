//! Emit fixtures, execute correctness regressions, then time Wasm-to-Wasm calls.

mod modules;

use serde_json::{Value, json};
use std::{env, fs, path::Path, time::Instant};
use wasmtime::{Config, Engine, Instance, Linker, Module, OptLevel, Store, TypedFunc};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

// ---- Linking and regression checks ----

struct Guest {
    store: Store<()>,
    instance: Instance,
    runtime: Instance,
    reset: TypedFunc<(), ()>,
}

fn instantiate(engine: &Engine, directory: &Path, bits: u32) -> Result<Guest> {
    let mut store = Store::new(engine, ());
    let runtime = Module::from_file(engine, directory.join(format!("runtime{bits}.wasm")))?;
    let runtime = Instance::new(&mut store, &runtime, &[])?;
    let mut linker = Linker::new(engine);
    linker.instance(&mut store, "gc", runtime)?;
    let module = Module::from_file(engine, directory.join(format!("workload{bits}.wasm")))?;
    let instance = linker.instantiate(&mut store, &module)?;
    let reset = instance.get_typed_func(&mut store, "reset")?;
    Ok(Guest {
        store,
        instance,
        runtime,
        reset,
    })
}

fn check(guest: &mut Guest) -> Result<Vec<String>> {
    let names: Vec<_> = guest
        .instance
        .exports(&mut guest.store)
        .map(|e| e.name().to_string())
        .filter(|n| n.starts_with("test_") || n.starts_with("negative_") || n.starts_with("trap_"))
        .collect();
    for name in &names {
        guest.reset.call(&mut guest.store, ())?;
        let test = guest
            .instance
            .get_typed_func::<(), i32>(&mut guest.store, name)?;
        if name.starts_with("trap_") {
            assert!(test.call(&mut guest.store, ()).is_err(), "{name}");
        } else {
            assert_eq!(test.call(&mut guest.store, ())?, 1, "{name}");
        }
    }
    for roots in [1, 4, 16] {
        let mut checksums = Vec::new();
        for mode in ["locals", "shadow", "stack"] {
            guest.reset.call(&mut guest.store, ())?;
            guest
                .instance
                .get_typed_func::<i32, ()>(&mut guest.store, "stress")?
                .call(&mut guest.store, 1)?;
            let function = guest
                .instance
                .get_typed_func::<(i32, i32), i32>(&mut guest.store, &format!("{mode}_{roots}"))?;
            checksums.push(function.call(&mut guest.store, (3, 2))?);
        }
        assert!(checksums.windows(2).all(|pair| pair[0] == pair[1]));
    }
    Ok(names)
}

fn high_address(engine: &Engine, directory: &Path) -> Result<i32> {
    let module = Module::from_file(engine, directory.join("high-address.wasm"))?;
    let mut store = Store::new(engine, ());
    let instance = Instance::new(&mut store, &module, &[])?;
    Ok(instance
        .get_typed_func::<(), i32>(&mut store, "probe")?
        .call(&mut store, ())?)
}

// ---- Paired timing ----

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(f64::total_cmp);
    values[values.len() / 2]
}

fn timed(
    guest: &mut Guest,
    function: &TypedFunc<(i32, i32), i32>,
    n: i32,
    work: i32,
) -> Result<(f64, i32)> {
    guest.reset.call(&mut guest.store, ())?;
    let start = Instant::now();
    let checksum = function.call(&mut guest.store, (n, work))?;
    Ok((start.elapsed().as_secs_f64() * 1e9, checksum))
}

fn benchmark(guest: &mut Guest, roots: usize, work: i32) -> Result<Value> {
    let modes = ["locals", "shadow", "stack"];
    let functions: Vec<_> = modes
        .iter()
        .map(|mode| {
            guest
                .instance
                .get_typed_func::<(i32, i32), i32>(&mut guest.store, &format!("{mode}_{roots}"))
        })
        .collect::<std::result::Result<_, _>>()?;
    let mut iterations = 16384;
    while timed(guest, &functions[0], iterations, work)?.0 < 20_000_000.0 {
        iterations *= 2;
    }
    for function in &functions {
        for _ in 0..5 {
            timed(guest, function, iterations, work)?;
        }
    }
    let mut samples = vec![vec![0.0; 3]; 15];
    for (round, sample) in samples.iter_mut().enumerate() {
        let mut checksums = [0; 3];
        for offset in 0..3 {
            let mode = (round + offset) % 3;
            let (ns, checksum) = timed(guest, &functions[mode], iterations, work)?;
            sample[mode] = ns / iterations as f64;
            checksums[mode] = checksum;
        }
        assert!(checksums.windows(2).all(|pair| pair[0] == pair[1]));
    }
    let medians: Vec<_> = (0..3)
        .map(|i| median(&mut samples.iter().map(|s| s[i]).collect::<Vec<_>>()))
        .collect();
    let overhead: Vec<_> = (1..3)
        .map(|i| {
            median(
                &mut samples
                    .iter()
                    .map(|s| (s[i] / s[0] - 1.0) * 100.0)
                    .collect::<Vec<_>>(),
            )
        })
        .collect();
    Ok(
        json!({"roots": roots, "work": work, "iterations": iterations, "modes": modes,
        "ns_per_call": medians, "overhead_percent": overhead, "samples_ns_per_call": samples}),
    )
}

fn churn(guest: &mut Guest) -> Result<Value> {
    let function = guest.instance.get_typed_func(&mut guest.store, "churn")?;
    let collections = guest
        .runtime
        .get_typed_func::<(), i32>(&mut guest.store, "collections")?;
    let mut samples = Vec::new();
    for _ in 0..9 {
        let (ns, checksum) = timed(guest, &function, 1_000_000, 0)?;
        assert_eq!(checksum, 1234567);
        samples.push(ns / 1_000_000.0);
    }
    let count = collections.call(&mut guest.store, ())?;
    assert!(count > 0);
    Ok(
        json!({"allocations": 1_000_000, "collections": count, "ns_per_allocation": median(&mut samples)}),
    )
}

fn pauses(guest: &mut Guest) -> Result<Vec<Value>> {
    let prepare = guest
        .instance
        .get_typed_func::<i32, ()>(&mut guest.store, "prepare_live")?;
    let collect = guest
        .instance
        .get_typed_func::<(), ()>(&mut guest.store, "collect_live")?;
    let live = guest
        .runtime
        .get_typed_func::<(), i32>(&mut guest.store, "live")?;
    let mut results = Vec::new();
    for count in [1, 1000, 10000] {
        guest.reset.call(&mut guest.store, ())?;
        prepare.call(&mut guest.store, count)?;
        let mut samples = Vec::new();
        for _ in 0..15 {
            let start = Instant::now();
            collect.call(&mut guest.store, ())?;
            samples.push(start.elapsed().as_secs_f64() * 1e6);
        }
        assert_eq!(live.call(&mut guest.store, ())?, count);
        results.push(json!({"live_objects": count, "payload_bytes": count * 32, "median_us": median(&mut samples)}));
    }
    Ok(results)
}

// ---- Command line ----

fn emit(directory: &Path) -> Result<()> {
    fs::create_dir_all(directory)?;
    for bits in [32, 64] {
        let text = modules::workload(bits);
        fs::write(
            directory.join(format!("workload{bits}.wasm")),
            wat::parse_str(&text)?,
        )?;
        fs::write(directory.join(format!("workload{bits}.wat")), text)?;
    }
    fs::write(
        directory.join("high-address.wasm"),
        wat::parse_str(modules::HIGH_ADDRESS)?,
    )?;
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<_> = env::args().collect();
    let directory = Path::new(
        args.get(2)
            .ok_or("usage: linear-gc-runner emit|check|bench DIRECTORY")?,
    );
    if args[1] == "emit" {
        return emit(directory);
    }
    assert!(args[1] == "check" || args[1] == "bench");
    let mut config = Config::new();
    config
        .wasm_memory64(true)
        .cranelift_opt_level(OptLevel::Speed);
    let engine = Engine::new(&config)?;
    let mut results = Vec::new();
    for bits in [32, 64] {
        let mut guest = instantiate(&engine, directory, bits)?;
        let tests = check(&mut guest)?;
        let mut cases = Vec::new();
        if args[1] == "bench" {
            for (roots, work) in [(1, 1), (4, 1), (16, 1), (16, 64)] {
                cases.push(benchmark(&mut guest, roots, work)?);
            }
        }
        results.push(json!({"bits": bits, "tests": tests, "cases": cases, "churn": churn(&mut guest)?, "pauses": pauses(&mut guest)?}));
    }
    assert_eq!(high_address(&engine, directory)?, 1234567);
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({"engine": "Wasmtime 48.0.7 / Cranelift speed",
        "high_address": "passed: 4 GiB + 16", "results": results}))?
    );
    Ok(())
}
