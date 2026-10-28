//! Linking modules, as host/browser/load.mjs does on Node and in the page:
//! a program compiled one library at a time, linked when it starts, and
//! modules a program loads while it runs, through (snail-core wasm).
//!
//! A per-library build is named by its modules.json, which `build-modules`
//! in host/chibi/snail-core/build.sld writes beside the modules:
//! `{"runtime": FILE, "modules": [{"name": LIBRARY, "file": FILE}, ...]}`,
//! the libraries in program order. The Rust runtime is instantiated and
//! initialized first; then each library's module, which sees the runtime
//! as "snail.library", the modules before it under their library names,
//! and the host's modules. Each module's `main` then runs in program order
//! (program.rs).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde_json::Value;
use wasmtime::{AsContext, AsContextMut, Caller, Engine, Extern, ExternType, Func, ImportType};
use wasmtime::{Instance, Linker, Module};
use wasmtime::{Store, Trap, bail, format_err};

use crate::engine::{call, run_export};
use crate::program::{Host, Linked, NODE_ONLY, compile_module};

// ---- The manifest ----

/// A modules.json, its files resolved against its own directory.
pub struct Manifest {
    pub runtime: PathBuf,
    pub libraries: Vec<Library>,
}

/// A library's name, under which later modules import from it, and the
/// file holding its module.
pub struct Library {
    pub name: String,
    pub file: PathBuf,
}

impl Manifest {
    pub fn read(path: &Path) -> wasmtime::Result<Manifest> {
        let text = std::fs::read_to_string(path)
            .map_err(|error| format_err!("cannot read {}: {error}", path.display()))?;
        let directory = path.parent().unwrap_or(Path::new(""));
        let json = serde_json::from_str(&text).ok();
        let manifest = json.and_then(|json| Manifest::described(&json, directory));
        manifest
            .ok_or_else(|| format_err!("{} is not the modules.json of a program", path.display()))
    }

    // The manifest `json` describes, its files in `directory`, if it
    // describes one.
    fn described(json: &Value, directory: &Path) -> Option<Manifest> {
        let file = |value: &Value| Some(directory.join(value.as_str()?));
        let library = |entry: &Value| {
            let name = entry["name"].as_str()?.to_string();
            Some(Library {
                name,
                file: file(&entry["file"])?,
            })
        };
        let libraries = json["modules"]
            .as_array()?
            .iter()
            .map(library)
            .collect::<Option<_>>()?;
        Some(Manifest {
            runtime: file(&json["runtime"])?,
            libraries,
        })
    }

    /// The runtime's file, then each library's.
    pub fn files(&self) -> Vec<PathBuf> {
        let libraries = self.libraries.iter().map(|library| library.file.clone());
        std::iter::once(self.runtime.clone())
            .chain(libraries)
            .collect()
    }
}

// ---- Linking a program ----

/// A program compiled one library at a time, compiled: the runtime, and
/// each library's module by name, in program order.
pub struct Libraries {
    runtime: Module,
    libraries: Vec<(String, Module)>,
}

impl Libraries {
    pub fn compile(engine: &Engine, manifest: &Manifest) -> wasmtime::Result<Libraries> {
        let runtime = compile_module(engine, &manifest.runtime)?;
        let library =
            |library: &Library| Ok((library.name.clone(), compile_module(engine, &library.file)?));
        let libraries = manifest
            .libraries
            .iter()
            .map(library)
            .collect::<wasmtime::Result<_>>()?;
        Ok(Libraries { runtime, libraries })
    }

    /// Each library's module, in program order.
    pub fn modules(&self) -> impl Iterator<Item = &Module> {
        self.libraries.iter().map(|(_, module)| module)
    }

    /// Links the runtime, then each library's module after those it may
    /// import from, into the program's own namespace, where a module loaded
    /// later sees it by name.
    pub fn link(
        self,
        store: &mut Store<Host>,
        linker: &mut Linker<Host>,
    ) -> wasmtime::Result<Linked> {
        let runtime = link_runtime(store, linker, &self.runtime)?;
        let names: Vec<&str> = self
            .libraries
            .iter()
            .map(|(name, _)| name.as_str())
            .collect();
        let mut mains = Vec::new();
        for (name, module) in &self.libraries {
            let imports = resolve(&mut *store, 0, module, &names).map_err(|missing| {
                format_err!("the library {name} imports {missing}, which nothing provides")
            })?;
            let instance = Instance::new(&mut *store, module, &imports)?;
            store.data_mut().loading.add_library(name, instance);
            mains.push(instance);
        }
        Ok(Linked {
            runtime,
            close: "snail:io/close-all",
            mains,
        })
    }
}

// The runtime reports a panic through its own export, which its platform
// import forwards to once the instance exists.
fn link_runtime(
    store: &mut Store<Host>,
    linker: &mut Linker<Host>,
    module: &Module,
) -> wasmtime::Result<Instance> {
    linker.func_wrap("snail.platform", "diagnostics/report-error", report_error)?;
    let runtime = linker.instantiate(&mut *store, module)?;
    store.data_mut().loading.set_runtime(runtime);
    call::<()>(&mut *store, &runtime, "_initialize")?;
    Ok(runtime)
}

fn report_error(mut caller: Caller<'_, Host>, pointer: i32, length: i32) -> wasmtime::Result<()> {
    let runtime = caller.data().loading.runtime()?;
    let report = runtime.get_typed_func::<(i32, i32), ()>(&mut caller, "snail:report-error")?;
    report.call(&mut caller, (pointer, length))
}

// ---- What a module sees ----

// A library's module and a module loaded while the program runs link the
// same way, as host/browser/load.mjs's `moduleImports` links both. A module
// in `namespace` sees the runtime as "snail.library", the modules of its
// namespace under their library names, and the host's `wasm` effect; in the
// program's namespace, also the files the program links. A function it
// imports from any other module links to one that fails if called: a
// library's module holds all of its functions, so it may import host
// services, such as the screen, that this host lacks and the program never
// calls, as a statically linked program would have left them out. What it
// imports from the runtime, from a module of its namespace, or from one of
// the `later` libraries not linked yet, still fails to link.
fn resolve(
    mut store: impl AsContextMut<Data = Host>,
    namespace: usize,
    module: &Module,
    later: &[&str],
) -> Result<Vec<Extern>, String> {
    let provide = |import: ImportType| {
        let provided = provider(&mut store, namespace, &import, later);
        provided.ok_or_else(|| format!("{} {}", import.module(), import.name()))
    };
    module.imports().map(provide).collect()
}

fn provider(
    store: &mut impl AsContextMut<Data = Host>,
    namespace: usize,
    import: &ImportType,
    later: &[&str],
) -> Option<Extern> {
    let (from, name, loading) = (
        import.module(),
        import.name(),
        &store.as_context().data().loading,
    );
    if let Some(library) = loading.library(namespace, from) {
        return library.get_export(&mut *store, name);
    }
    if let Some(Ok(host)) = loading
        .host(namespace, from)
        .map(|host| host.get(&mut *store, from, name))
    {
        return Some(host);
    }
    let (ExternType::Func(ty), false) = (import.ty(), later.contains(&from)) else {
        return None;
    };
    let missing = missing_host(from, name);
    Some(
        Func::new(&mut *store, ty, move |_, _, _| {
            Err(format_err!("{missing}"))
        })
        .into(),
    )
}

fn missing_host(from: &str, name: &str) -> String {
    if NODE_ONLY.contains(&from) {
        format!("{from} {name} runs on Node until tasks become effects (#511)")
    } else {
        format!("this host does not provide {from} {name}")
    }
}

// ---- Loading while the program runs ----

// The `wasm` effect of (snail-core wasm), which reads the files and decides
// what to link; the host only does what it cannot. `compile` takes the
// bytes of a module, `namespace` makes an empty namespace, `instantiate`
// links a module in one under a library name and runs its main, and
// `has-export` and `export-function` find what an instance exports by name.
// Names cross a character at a time, staged until the operation that takes
// them. Namespace 0 is the program's own, its linked libraries; a name
// already there is refused, since the modules that import it keep the
// instance they have. Another namespace holds a plugin's modules: each sees
// the modules before it there, then the runtime and the host's modules, as
// a child-first class loader resolves, and none of the files the program
// links. A failure answers a negative code, which (snail-core wasm) names;
// a trap in a module's main still ends the program.
const INVALID_MODULE: i32 = -1;
const NAME_TAKEN: i32 = -1;
const LINK_FAILED: i32 = -2;

/// What a program has loaded, and the host's imports for what it loads
/// next.
pub struct Loading {
    linker: Arc<Linker<Host>>,
    runtime: Option<Instance>,
    modules: Vec<Module>,
    instances: Vec<Instance>,
    namespaces: Vec<HashMap<String, Instance>>,
    current: String,
    staged: Option<String>,
}

impl Loading {
    pub fn new(linker: Linker<Host>) -> Loading {
        Loading {
            linker: Arc::new(linker),
            runtime: None,
            modules: Vec::new(),
            instances: Vec::new(),
            namespaces: vec![HashMap::new()],
            current: String::new(),
            staged: None,
        }
    }

    /// The instance holding the runtime: a loaded module's "snail.library",
    /// and the memory that holds the bytes `compile` is given.
    pub fn set_runtime(&mut self, runtime: Instance) {
        self.runtime = Some(runtime);
    }

    fn runtime(&self) -> wasmtime::Result<Instance> {
        self.runtime
            .ok_or_else(|| format_err!("the program is not linked yet"))
    }

    fn add_library(&mut self, name: &str, instance: Instance) {
        self.namespaces[0].insert(name.to_string(), instance);
    }

    // Every operation that takes a name takes one, so a second name ended
    // before the first is taken is a mistake of the caller's.
    fn stage(&mut self) -> wasmtime::Result<()> {
        if self.staged.is_some() {
            bail!("a name is staged already")
        }
        self.staged = Some(std::mem::take(&mut self.current));
        Ok(())
    }

    fn take_name(&mut self) -> wasmtime::Result<String> {
        self.staged
            .take()
            .ok_or_else(|| format_err!("no name is staged"))
    }

    // The namespace and the compiled module `instantiate` names.
    fn target(&self, namespace: i32, module: i32) -> wasmtime::Result<(usize, Module)> {
        let index = usize::try_from(namespace)
            .ok()
            .filter(|index| *index < self.namespaces.len());
        let compiled = usize::try_from(module)
            .ok()
            .and_then(|handle| self.modules.get(handle));
        match (index, compiled) {
            (Some(index), Some(compiled)) => Ok((index, compiled.clone())),
            (None, _) => bail!("no namespace {namespace}"),
            (_, None) => bail!("no compiled module {module}"),
        }
    }

    // The instance a module in `namespace` imports from as `from`: the
    // runtime, or one of the namespace's modules.
    fn library(&self, namespace: usize, from: &str) -> Option<Instance> {
        if from == "snail.library" {
            self.runtime
        } else {
            self.namespaces[namespace].get(from).copied()
        }
    }

    // The host's imports, when `from` is one of the host's modules a
    // loaded module in `namespace` sees.
    fn host(&self, namespace: usize, from: &str) -> Option<Arc<Linker<Host>>> {
        let files = from == "snail.link" || from == "snail.resource";
        (from == "snail.wasm" || (namespace == 0 && files)).then(|| Arc::clone(&self.linker))
    }

    // The instance's handle, once it is in its namespace under `name`.
    fn add_instance(
        &mut self,
        namespace: usize,
        name: String,
        instance: Instance,
    ) -> wasmtime::Result<i32> {
        self.namespaces[namespace].insert(name, instance);
        self.instances.push(instance);
        Ok(i32::try_from(self.instances.len() - 1)?)
    }

    fn instance(&self, handle: i32) -> wasmtime::Result<Instance> {
        let instance = usize::try_from(handle)
            .ok()
            .and_then(|index| self.instances.get(index));
        instance
            .copied()
            .ok_or_else(|| format_err!("no loaded instance {handle}"))
    }
}

pub fn define_loading(linker: &mut Linker<Host>) -> wasmtime::Result<()> {
    linker.func_wrap(
        "snail.wasm",
        "argument-character",
        |mut caller: Caller<'_, Host>, code: u32| {
            let character =
                char::from_u32(code).ok_or_else(|| format_err!("no character {code}"))?;
            caller.data_mut().loading.current.push(character);
            wasmtime::Result::<()>::Ok(())
        },
    )?;
    linker.func_wrap(
        "snail.wasm",
        "argument-end",
        |mut caller: Caller<'_, Host>| caller.data_mut().loading.stage(),
    )?;
    linker.func_wrap("snail.wasm", "compile", compile)?;
    linker.func_wrap("snail.wasm", "namespace", |mut caller: Caller<'_, Host>| {
        let namespaces = &mut caller.data_mut().loading.namespaces;
        namespaces.push(HashMap::new());
        i32::try_from(namespaces.len() - 1).unwrap_or(i32::MAX)
    })?;
    linker.func_wrap("snail.wasm", "instantiate", instantiate)?;
    linker.func_wrap(
        "snail.wasm",
        "has-export",
        |mut caller: Caller<'_, Host>, handle: i32| {
            let instance = caller.data().loading.instance(handle)?;
            let name = caller.data_mut().loading.take_name()?;
            Ok(i32::from(instance.get_func(&mut caller, &name).is_some()))
        },
    )?;
    linker.func_wrap(
        "snail.wasm",
        "export-function",
        |mut caller: Caller<'_, Host>, handle: i32| {
            let instance = caller.data().loading.instance(handle)?;
            let name = caller.data_mut().loading.take_name()?;
            Ok(instance.get_func(&mut caller, &name))
        },
    )?;
    Ok(())
}

fn compile(mut caller: Caller<'_, Host>, address: u32) -> wasmtime::Result<i32> {
    let bytes = byte_snapshot(&mut caller, address)?;
    let Ok(module) = Module::new(caller.engine(), &bytes) else {
        return Ok(INVALID_MODULE);
    };
    let modules = &mut caller.data_mut().loading.modules;
    modules.push(module);
    Ok(i32::try_from(modules.len() - 1)?)
}

// A foreign Bytes argument borrows the runtime's staging memory: a
// little-endian u32 length at `address` and that many bytes after it,
// copied before anything can overwrite them.
fn byte_snapshot(caller: &mut Caller<'_, Host>, address: u32) -> wasmtime::Result<Vec<u8>> {
    let runtime = caller.data().loading.runtime()?;
    let Some(memory) = runtime.get_memory(&mut *caller, "memory") else {
        bail!("the program exports no memory")
    };
    let (data, start) = (memory.data(&*caller), address as usize);
    let length = data
        .get(start..start + 4)
        .map(|word| u32::from_le_bytes([word[0], word[1], word[2], word[3]]));
    let bytes = length.and_then(|length| data.get(start + 4..start + 4 + length as usize));
    Ok(bytes
        .ok_or_else(|| format_err!("Bytes at {address} lie outside memory"))?
        .to_vec())
}

fn instantiate(mut caller: Caller<'_, Host>, namespace: i32, module: i32) -> wasmtime::Result<i32> {
    let name = caller.data_mut().loading.take_name()?;
    let (namespace, module) = caller.data().loading.target(namespace, module)?;
    if caller.data().loading.namespaces[namespace].contains_key(&name) {
        return Ok(NAME_TAKEN);
    }
    let Some(instance) = link_loaded(&mut caller, namespace, &module)? else {
        return Ok(LINK_FAILED);
    };
    let handle = caller
        .data_mut()
        .loading
        .add_instance(namespace, name, instance)?;
    if instance.get_func(&mut caller, "main").is_some() {
        run_export(&mut caller, &instance, "main")?;
    }
    Ok(handle)
}

// An instance of the module, or None when an import has no provider of
// its type. A trap while instantiating still ends the program.
fn link_loaded(
    caller: &mut Caller<'_, Host>,
    namespace: usize,
    module: &Module,
) -> wasmtime::Result<Option<Instance>> {
    let Ok(imports) = resolve(&mut *caller, namespace, module, &[]) else {
        return Ok(None);
    };
    match Instance::new(&mut *caller, module, &imports) {
        Ok(instance) => Ok(Some(instance)),
        Err(error) if error.downcast_ref::<Trap>().is_some() => Err(error),
        Err(_) => Ok(None),
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::tests::module_file;
    use crate::program;

    // A runtime that closes its resources with `close`.
    fn runtime(close: i32) -> String {
        format!(
            r#"(module
                 (import "snail.platform" "diagnostics/report-error" (func (param i32 i32)))
                 (memory (export "memory") 1)
                 (global $initialized (mut i32) (i32.const 0))
                 (func (export "_initialize") (global.set $initialized (i32.const 1)))
                 (func (export "initialized") (result i32) (global.get $initialized))
                 (func (export "snail:report-error") (param i32 i32))
                 (func (export "snail:io/close-all") (result i32) (i32.const {close})))"#
        )
    }

    // A library whose main fails unless the runtime was initialized, and
    // which imports a host service it never calls.
    const LIBRARY: &str = r#"(module
        (import "snail.library" "initialized" (func $initialized (result i32)))
        (import "snail.screen" "draw" (func (param i32)))
        (func (export "main") (result i32)
          (if (i32.eqz (call $initialized)) (then (unreachable)))
          (i32.const 0))
        (func (export "lib:answer") (result i32) (i32.const 40)))"#;

    // The program's own module, last, answering through the library.
    const MAIN: &str = r#"(module
        (import "lib" "lib:answer" (func $answer (result i32)))
        (func (export "main") (result i32) (i32.add (call $answer) (i32.const 2))))"#;

    // A per-library build in a directory of its own: each module's file,
    // and the manifest naming them.
    fn build(name: &str, runtime_text: &str) -> PathBuf {
        let runtime_file = PathBuf::from(module_file(&format!("{name}-runtime"), runtime_text));
        let directory = runtime_file.with_extension("build");
        std::fs::create_dir_all(&directory).unwrap();
        std::fs::rename(&runtime_file, directory.join("runtime.wasm")).unwrap();
        std::fs::write(directory.join("lib.wasm"), wat::parse_str(LIBRARY).unwrap()).unwrap();
        std::fs::write(directory.join("main.wasm"), wat::parse_str(MAIN).unwrap()).unwrap();
        let manifest = r#"{"runtime": "runtime.wasm", "modules": [{"name": "lib", "file": "lib.wasm"}, {"name": "main", "file": "main.wasm"}]}"#;
        std::fs::write(directory.join("modules.json"), manifest).unwrap();
        directory.join("modules.json")
    }

    #[test]
    fn a_manifest_names_its_files_beside_it() {
        let manifest = build("manifest", &runtime(0));
        let read = Manifest::read(&manifest).unwrap();
        let directory = manifest.parent().unwrap();
        assert_eq!(
            read.files(),
            [
                directory.join("runtime.wasm"),
                directory.join("lib.wasm"),
                directory.join("main.wasm")
            ]
        );
        assert_eq!(read.libraries[0].name, "lib");
    }

    #[test]
    fn what_is_not_a_manifest_is_refused() {
        let manifest = build("invalid", &runtime(0));
        std::fs::write(&manifest, r#"{"runtime": "runtime.wasm"}"#).unwrap();
        let error = Manifest::read(&manifest).err().unwrap().to_string();
        assert!(error.ends_with("modules.json is not the modules.json of a program"));
    }

    #[test]
    fn libraries_link_in_program_order_and_the_last_main_answers() {
        let manifest = build("linked", &runtime(0));
        assert_eq!(program::run(&manifest.to_string_lossy(), &[]), 42);
    }

    #[test]
    fn the_runtime_closes_a_linked_programs_resources() {
        let manifest = build("unclosed", &runtime(1));
        assert_eq!(program::run(&manifest.to_string_lossy(), &[]), 42);
        std::fs::write(
            manifest.with_file_name("main.wasm"),
            wat::parse_str(&MAIN.replace("(i32.const 2)", "(i32.const -40)")).unwrap(),
        )
        .unwrap();
        assert_eq!(program::run(&manifest.to_string_lossy(), &[]), 1);
    }
}
