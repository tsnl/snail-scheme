//! Whole source programs: the same batches and sampling as programs/run.mjs.

use super::Result;
use serde_json::{Value, json};
use std::{fs, time::Instant};
use wasmtime::{Config, Engine, Instance, Linker, Module, OptLevel, Store};
use wasmtime_wasi::{
    WasiCtxBuilder,
    p1::{self, WasiP1Ctx},
};

const WORK: [(&str, i64); 6] = [
    ("arithmetic", 1_000_000),
    ("rooted-calls", 300_000),
    ("lists", 50_000),
    ("arrays", 100_000),
    ("closures", 10_000),
    ("effects", 2_000),
];

// ---- Execution and sampling ----

fn workload(
    store: &mut Store<WasiP1Ctx>,
    instance: Instance,
    name: &str,
    count: i64,
) -> Result<Value> {
    let call = instance.get_typed_func::<i64, i64>(&mut *store, name)?;
    let checksum = call.call(&mut *store, count)?;
    for _ in 0..32 {
        assert_eq!(call.call(&mut *store, count)?, checksum);
    }
    let mut samples = Vec::new();
    for _ in 0..9 {
        let start = Instant::now();
        for _ in 0..32 {
            assert_eq!(call.call(&mut *store, count)?, checksum);
        }
        samples.push(start.elapsed().as_secs_f64() * 1000.0 / 32.0);
    }
    let mut sorted = samples.clone();
    sorted.sort_by(f64::total_cmp);
    let profile = profile(store, instance, name, count, checksum)?;
    let memory = instance
        .get_memory(&mut *store, "memory")
        .unwrap()
        .data_size(&*store);
    Ok(
        json!({"name": name, "count": count, "checksum": checksum.to_string(),
        "samples_ms": samples, "median_ms": sorted[4], "profile": profile,
        "linear_memory_bytes": memory}),
    )
}

fn profile(
    store: &mut Store<WasiP1Ctx>,
    instance: Instance,
    name: &str,
    count: i64,
    checksum: i64,
) -> Result<Value> {
    let Ok(toggle) = instance.get_typed_func::<i32, ()>(&mut *store, "snail:gc/profile") else {
        return Ok(Value::Null);
    };
    let collections = instance.get_typed_func::<(), i32>(&mut *store, "snail:gc/collections")?;
    let before = collections.call(&mut *store, ())?;
    toggle.call(&mut *store, 1)?;
    let call = instance.get_typed_func::<i64, i64>(&mut *store, name)?;
    for _ in 0..9 {
        assert_eq!(call.call(&mut *store, count)?, checksum);
    }
    let mut data =
        json!({"batches": 9, "collections": collections.call(&mut *store, ())? - before});
    for key in [
        "profile-allocations",
        "profile-bytes",
        "pause-ns",
        "longest-pause-ns",
    ] {
        let read = instance.get_typed_func::<(), i64>(&mut *store, &format!("snail:gc/{key}"))?;
        data[key] = json!(read.call(&mut *store, ())?.to_string());
    }
    toggle.call(&mut *store, 0)?;
    Ok(data)
}

// ---- One artifact per fresh process ----

pub fn run(path: &str, variant: &str) -> Result<()> {
    let mut config = Config::new();
    config
        .cranelift_opt_level(OptLevel::Speed)
        .max_wasm_stack(64 << 20)
        .async_stack_size(64 << 20);
    let engine = Engine::new(&config)?;
    let bytes = fs::read(path)?;
    let start = Instant::now();
    let module = Module::new(&engine, &bytes)?;
    let compile_ms = start.elapsed().as_secs_f64() * 1000.0;
    let mut linker = Linker::new(&engine);
    p1::add_to_linker_sync(&mut linker, |wasi| wasi)?;
    let mut store = Store::new(&engine, WasiCtxBuilder::new().build_p1());
    let start = Instant::now();
    let instance = linker.instantiate(&mut store, &module)?;
    if let Ok(initialize) = instance.get_typed_func::<(), ()>(&mut store, "_initialize") {
        initialize.call(&mut store, ())?;
    }
    instance
        .get_typed_func::<(), i32>(&mut store, "main")?
        .call(&mut store, ())?;
    let initialize_ms = start.elapsed().as_secs_f64() * 1000.0;
    let workloads = WORK
        .into_iter()
        .map(|(name, count)| workload(&mut store, instance, name, count))
        .collect::<Result<Vec<_>>>()?;
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({"variant": variant,
        "engine": "Wasmtime 48.0.7 / Cranelift speed / DRC for WasmGC",
        "max_rss_kib": peak_rss(), "wasm_bytes": bytes.len(), "compile_ms": compile_ms, "initialize_ms": initialize_ms,
        "samples": 9, "calls_per_sample": 32, "warmup_calls": 32, "workloads": workloads}))?
    );
    Ok(())
}

// Linux peak RSS includes the engine, native code and both kinds of Wasm heap.
fn peak_rss() -> Option<u64> {
    let status = fs::read_to_string("/proc/self/status").ok()?;
    status
        .lines()
        .find(|line| line.starts_with("VmHWM:"))?
        .split_whitespace()
        .nth(1)?
        .parse()
        .ok()
}
