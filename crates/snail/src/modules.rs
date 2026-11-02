//! The Wasm primitives of (snail shell wasm), as host/browser/load.mjs
//! provides them on Node and in the page: compiling modules, linking one
//! against providers a loader chooses, instantiating one by name in a
//! namespace, and finding what an instance exports. The engine
//! ((snail shell engine)) links a program compiled one library at a time
//! through them; `load-module` and `load-plugin` load modules while a
//! program runs.
//!
//! A per-library build is named by its modules.json, which `build-modules`
//! in host/chibi/snail/stage0/build.sld writes beside the modules:
//! `{"store": STORE, "runtime": OBJECT, "modules": [{"name": LIBRARY, ...OBJECT}, ...], "files": [OBJECT, ...]}`,
//! where an OBJECT is `{"digest": DIGEST, "size": SIZE}` naming a file of the
//! store, the libraries in program order; `snail imports` reads it.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde_json::Value;
use wasmtime::{AsContext, AsContextMut, Caller, Extern, ExternType, Func, ImportType};
use wasmtime::{Instance, Linker, Module, Val, ValType};
use wasmtime::{Trap, bail, format_err};

use crate::engine::run_export;
use crate::program::{Host, NODE_ONLY};

// ---- The manifest ----

/// A modules.json, its objects resolved in its store, `store/` beside the
/// manifest unless it says otherwise: the runtime and each library's
/// module, which `snail imports` reads; the engine links them.
pub struct Manifest {
    pub runtime: PathBuf,
    pub libraries: Vec<Library>,
}

/// A library's name, under which later modules import from it, and the
/// object holding its module.
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
        let manifest = manifest.ok_or_else(|| {
            format_err!("{} is not the modules.json of a program", path.display())
        })?;
        if let Some(library) = manifest
            .libraries
            .iter()
            .find(|library| host_provided(&library.name))
        {
            bail!(
                "no library may be linked as {}, which the host provides",
                library.name
            )
        }
        Ok(manifest)
    }

    // The manifest `json` describes, its objects in the store it names in
    // `directory`, if it describes one.
    fn described(json: &Value, directory: &Path) -> Option<Manifest> {
        let store = directory.join(json["store"].as_str().unwrap_or("store/"));
        let object = |value: &Value| Some(store.join("sha256").join(value["digest"].as_str()?));
        let library = |entry: &Value| {
            let name = entry["name"].as_str()?.to_string();
            Some(Library {
                name,
                file: object(entry)?,
            })
        };
        let libraries = json["modules"]
            .as_array()?
            .iter()
            .map(library)
            .collect::<Option<_>>()?;
        Some(Manifest {
            runtime: object(&json["runtime"])?,
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

// ---- The platform ----

/// Defines "snail.platform" "diagnostics/report-error", which a runtime
/// imports to report a panic, through its own export.
pub fn define_platform(linker: &mut Linker<Host>) -> wasmtime::Result<()> {
    linker.func_wrap("snail.platform", "diagnostics/report-error", report_error)?;
    Ok(())
}

fn report_error(mut caller: Caller<'_, Host>, pointer: i32, length: i32) -> wasmtime::Result<()> {
    let report = match caller.get_export("snail:report-error") {
        Some(Extern::Func(report)) => report,
        _ => {
            let runtime = caller.data().loading.runtime()?;
            runtime
                .get_func(&mut caller, "snail:report-error")
                .ok_or_else(|| format_err!("the runtime exports no snail:report-error"))?
        }
    };
    report
        .typed::<(i32, i32), ()>(&caller)?
        .call(&mut caller, (pointer, length))
}

// ---- What a module sees ----

// A library's module and a module loaded while the program runs link the
// same way, as host/browser/load.mjs's `moduleImports` links both. A module
// in `namespace` sees the runtime as "snail.core.support", the modules of its
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
        format!("{from} {name} runs on Node")
    } else {
        format!("this host does not provide {from} {name}")
    }
}

// ---- Loading while the program runs ----

// The `wasm` effect of (snail shell wasm), which reads the files and decides
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
// links. A failure answers a negative code, which (snail shell wasm) names;
// a trap in a module's main still ends the program.
//
// A loader that chooses a module's providers itself lists the imports
// with `import-count` and `import-at`, which holds the import's module and
// field names for `held-length` and `held-char`, the reverse of the
// staging above; then `prepare-link`, one provider per import in import
// order (`provide-export` of an instance under a staged name,
// `provide-host` for a function of this host's own, `provide-missing` for
// `provide-constant` for a function answering a constant, `provide-missing`
// for one that fails if called) and `link-prepared`, which answers the
// instance or a negative code, having initialized it when it exports
// `_initialize`. A provider that is not found provides nothing, and the
// loader gives another or the link fails. Instance 0 is the loading
// program's runtime, whose exports a loaded module may import;
// `name-instance` puts an instance in the program's namespace under a
// staged name, and naming one `snail.core.support` makes it the program's
// runtime, whose memory stages the Bytes the host reads; `call-export`
// calls an export of no argument or one i64, such as `main` or
// `tasks:turn`, for its result as an i64.
const INVALID_MODULE: i32 = -1;
const NAME_TAKEN: i32 = -1;
const LINK_FAILED: i32 = -2;

/// What a program has loaded, and the host's imports for what it loads
/// next.
pub struct Loading {
    linker: Arc<Linker<Host>>,
    loader: Option<Instance>,
    runtime: Option<Instance>,
    modules: Vec<Module>,
    instances: Vec<Instance>,
    namespaces: Vec<HashMap<String, Instance>>,
    current: String,
    staged: Option<String>,
    held: [String; 2],
    prepared: Option<Prepared>,
}

/// A link under way: the module, its imports, and the providers given so
/// far.
struct Prepared {
    module: Module,
    imports: Vec<(String, String, ExternType)>,
    providers: Vec<Extern>,
}

impl Prepared {
    fn new(module: &Module) -> Prepared {
        let imports = module
            .imports()
            .map(|import| {
                (
                    import.module().to_string(),
                    import.name().to_string(),
                    import.ty(),
                )
            })
            .collect();
        Prepared {
            module: module.clone(),
            imports,
            providers: Vec::new(),
        }
    }

    // The import the next provider is for.
    fn current(&self) -> wasmtime::Result<&(String, String, ExternType)> {
        self.imports
            .get(self.providers.len())
            .ok_or_else(|| format_err!("every import of the module being linked has its provider"))
    }

    // A provider that is not found provides nothing; the loader gives
    // another, or the link fails for the import left without one.
    fn bind(&mut self, provider: Option<Extern>) -> i32 {
        match provider {
            Some(provider) => {
                self.providers.push(provider);
                1
            }
            None => 0,
        }
    }
}

impl Loading {
    pub fn new(linker: Linker<Host>) -> Loading {
        Loading {
            linker: Arc::new(linker),
            loader: None,
            runtime: None,
            modules: Vec::new(),
            instances: Vec::new(),
            namespaces: vec![HashMap::new()],
            current: String::new(),
            staged: None,
            held: [String::new(), String::new()],
            prepared: None,
        }
    }

    /// The instance holding the runtime: a loaded module's "snail.core.support",
    /// and the memory that holds the bytes `compile` is given.
    pub fn set_runtime(&mut self, runtime: Instance) {
        self.runtime = Some(runtime);
    }

    /// The program that loads, instance 0, whose exports a module it links
    /// may import: the module this host started, which is the runtime too
    /// until the engine names the program's.
    pub fn set_loader(&mut self, loader: Instance) {
        self.loader = Some(loader);
    }

    fn runtime(&self) -> wasmtime::Result<Instance> {
        self.runtime
            .ok_or_else(|| format_err!("the program is not linked yet"))
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
        if from == "snail.core.support" {
            self.runtime
        } else {
            self.namespaces[namespace].get(from).copied()
        }
    }

    // The host's imports, when `from` is one of the host's modules a
    // loaded module in `namespace` sees.
    fn host(&self, namespace: usize, from: &str) -> Option<Arc<Linker<Host>>> {
        let files = from == "snail.runtime.link" || from == "snail.runtime.resource";
        (from == "snail.runtime.wasm" || (namespace == 0 && files))
            .then(|| Arc::clone(&self.linker))
    }

    // The instance's handle, once it is in its namespace under `name`.
    fn add_instance(
        &mut self,
        namespace: usize,
        name: String,
        instance: Instance,
    ) -> wasmtime::Result<i32> {
        self.namespaces[namespace].insert(name, instance);
        self.hold(instance)
    }

    // Handles count from 1: handle 0 is the loading program's runtime.
    fn hold(&mut self, instance: Instance) -> wasmtime::Result<i32> {
        self.instances.push(instance);
        Ok(i32::try_from(self.instances.len())?)
    }

    fn instance(&self, handle: i32) -> wasmtime::Result<Instance> {
        if handle == 0 {
            return self.loader.map_or_else(|| self.runtime(), Ok);
        }
        let instance = usize::try_from(handle)
            .ok()
            .and_then(|index| self.instances.get(index.wrapping_sub(1)));
        instance
            .copied()
            .ok_or_else(|| format_err!("no loaded instance {handle}"))
    }

    fn module(&self, handle: i32) -> wasmtime::Result<Module> {
        usize::try_from(handle)
            .ok()
            .and_then(|index| self.modules.get(index))
            .cloned()
            .ok_or_else(|| format_err!("no compiled module {handle}"))
    }

    fn prepared(&mut self) -> wasmtime::Result<&mut Prepared> {
        self.prepared
            .as_mut()
            .ok_or_else(|| format_err!("no link is prepared"))
    }

    fn held(&self, which: i32) -> wasmtime::Result<&str> {
        usize::try_from(which)
            .ok()
            .and_then(|index| self.held.get(index))
            .map(String::as_str)
            .ok_or_else(|| format_err!("no held name {which}"))
    }
}

// The kind of an import, as (snail shell wasm) numbers them.
fn import_kind(ty: &ExternType) -> i32 {
    match ty {
        ExternType::Func(_) => 0,
        ExternType::Table(_) => 1,
        ExternType::Memory(_) => 2,
        ExternType::Global(_) => 3,
        _ => -1,
    }
}

pub fn define_loading(linker: &mut Linker<Host>) -> wasmtime::Result<()> {
    linker.func_wrap(
        "snail.runtime.wasm",
        "argument-character",
        |mut caller: Caller<'_, Host>, code: u32| {
            let character =
                char::from_u32(code).ok_or_else(|| format_err!("no character {code}"))?;
            caller.data_mut().loading.current.push(character);
            wasmtime::Result::<()>::Ok(())
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "argument-end",
        |mut caller: Caller<'_, Host>| caller.data_mut().loading.stage(),
    )?;
    linker.func_wrap("snail.runtime.wasm", "compile", compile)?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "namespace",
        |mut caller: Caller<'_, Host>| {
            let namespaces = &mut caller.data_mut().loading.namespaces;
            namespaces.push(HashMap::new());
            i32::try_from(namespaces.len() - 1).unwrap_or(i32::MAX)
        },
    )?;
    linker.func_wrap("snail.runtime.wasm", "instantiate", instantiate)?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "has-export",
        |mut caller: Caller<'_, Host>, handle: i32| {
            let instance = caller.data().loading.instance(handle)?;
            let name = caller.data_mut().loading.take_name()?;
            Ok(i32::from(instance.get_func(&mut caller, &name).is_some()))
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "export-function",
        |mut caller: Caller<'_, Host>, handle: i32| {
            let instance = caller.data().loading.instance(handle)?;
            let name = caller.data_mut().loading.take_name()?;
            Ok(instance.get_func(&mut caller, &name))
        },
    )?;
    define_linking(linker)
}

// ---- Linking by hand ----

fn define_linking(linker: &mut Linker<Host>) -> wasmtime::Result<()> {
    linker.func_wrap(
        "snail.runtime.wasm",
        "import-count",
        |caller: Caller<'_, Host>, handle: i32| {
            let module = caller.data().loading.module(handle)?;
            Ok(i32::try_from(module.imports().len())?)
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "import-at",
        |mut caller: Caller<'_, Host>, handle: i32, index: i32| {
            let module = caller.data().loading.module(handle)?;
            let Some(import) = usize::try_from(index)
                .ok()
                .and_then(|index| module.imports().nth(index))
            else {
                return Ok(-1);
            };
            caller.data_mut().loading.held =
                [import.module().to_string(), import.name().to_string()];
            Ok(import_kind(&import.ty()))
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "held-length",
        |caller: Caller<'_, Host>, which: i32| {
            Ok(i32::try_from(
                caller.data().loading.held(which)?.chars().count(),
            )?)
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "held-char",
        |caller: Caller<'_, Host>, which: i32, index: i32| {
            let held = caller.data().loading.held(which)?;
            let character = usize::try_from(index)
                .ok()
                .and_then(|index| held.chars().nth(index))
                .ok_or_else(|| format_err!("no character {index} in the held name"))?;
            Ok(u32::from(character))
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "prepare-link",
        |mut caller: Caller<'_, Host>, handle: i32| {
            let module = caller.data().loading.module(handle)?;
            caller.data_mut().loading.prepared = Some(Prepared::new(&module));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "provide-export",
        |mut caller: Caller<'_, Host>, handle: i32| {
            let instance = caller.data().loading.instance(handle)?;
            let name = caller.data_mut().loading.take_name()?;
            caller.data_mut().loading.prepared()?.current()?;
            let provider = instance.get_export(&mut caller, &name);
            Ok(caller.data_mut().loading.prepared()?.bind(provider))
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "provide-host",
        |mut caller: Caller<'_, Host>| {
            let (from, name, _) = caller.data_mut().loading.prepared()?.current()?.clone();
            let linker = Arc::clone(&caller.data().loading.linker);
            let provider = linker.get(&mut caller, &from, &name).ok();
            Ok(caller.data_mut().loading.prepared()?.bind(provider))
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "provide-missing",
        |mut caller: Caller<'_, Host>| {
            let (from, name, ty) = caller.data_mut().loading.prepared()?.current()?.clone();
            let ExternType::Func(ty) = ty else {
                bail!("{from} {name} is not a function, so nothing stands in for it")
            };
            let missing = missing_host(&from, &name);
            let stub = Func::new(&mut caller, ty, move |_, _, _| {
                Err(format_err!("{missing}"))
            });
            caller
                .data_mut()
                .loading
                .prepared()?
                .bind(Some(stub.into()));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "link-prepared",
        |mut caller: Caller<'_, Host>| {
            let prepared = caller
                .data_mut()
                .loading
                .prepared
                .take()
                .ok_or_else(|| format_err!("no link is prepared"))?;
            if prepared.providers.len() != prepared.imports.len() {
                return Ok(LINK_FAILED);
            }
            let instance = match Instance::new(&mut caller, &prepared.module, &prepared.providers) {
                Ok(instance) => instance,
                Err(error) if error.downcast_ref::<Trap>().is_some() => return Err(error),
                Err(_) => return Ok(LINK_FAILED),
            };
            if instance.get_func(&mut caller, "_initialize").is_some() {
                run_export(&mut caller, &instance, "_initialize")?;
            }
            caller.data_mut().loading.hold(instance)
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "provide-constant",
        |mut caller: Caller<'_, Host>, value: i32| {
            caller.data_mut().loading.prepared()?.current()?;
            let provider = Func::wrap(&mut caller, move || value).into();
            caller.data_mut().loading.prepared()?.bind(Some(provider));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "name-instance",
        |mut caller: Caller<'_, Host>, handle: i32| {
            let instance = caller.data().loading.instance(handle)?;
            let name = caller.data_mut().loading.take_name()?;
            let loading = &mut caller.data_mut().loading;
            if name == "snail.core.support" {
                loading.set_runtime(instance);
                return Ok(1);
            }
            if loading.namespaces[0].contains_key(&name) || host_provided(&name) {
                return Ok(0);
            }
            loading.namespaces[0].insert(name, instance);
            Ok(1)
        },
    )?;
    linker.func_wrap(
        "snail.runtime.wasm",
        "call-export",
        |mut caller: Caller<'_, Host>, handle: i32, argument: i64| {
            let instance = caller.data().loading.instance(handle)?;
            let name = caller.data_mut().loading.take_name()?;
            let function = instance
                .get_func(&mut caller, &name)
                .ok_or_else(|| format_err!("the instance exports no function {name}"))?;
            call_with(&mut caller, &function, argument)
        },
    )?;
    Ok(())
}

// Calls a function of no parameter, or one i32 or i64, with `argument`,
// answering its first result widened to i64, or 0 when it has none.
fn call_with(
    caller: &mut Caller<'_, Host>,
    function: &Func,
    argument: i64,
) -> wasmtime::Result<i64> {
    let ty = function.ty(&*caller);
    let arguments: Vec<Val> = ty
        .params()
        .map(|param| match param {
            ValType::I64 => Ok(Val::I64(argument)),
            ValType::I32 => Ok(Val::I32(argument as i32)),
            other => bail!("an export called with one argument takes {other}, not an integer"),
        })
        .collect::<wasmtime::Result<_>>()?;
    let mut results = vec![Val::I32(0); ty.results().len()];
    function.call(&mut *caller, &arguments, &mut results)?;
    Ok(match results.first() {
        Some(Val::I32(result)) => i64::from(*result),
        Some(Val::I64(result)) => *result,
        _ => 0,
    })
}

// The names only a host or the runtime gives a module: the runtime
// interfaces, `snail.runtime.…`, and the Rust support module. A library
// linked under one would take the place of what every module imports from
// there, so none may be.
pub fn host_provided(name: &str) -> bool {
    name.starts_with("snail.runtime.") || name == "snail.core.support"
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

// A foreign Bytes argument borrows staging memory, the caller's own when
// it exports one and the runtime's otherwise: a little-endian u32 length
// at `address` and that many bytes after it, copied before anything can
// overwrite them.
fn byte_snapshot(caller: &mut Caller<'_, Host>, address: u32) -> wasmtime::Result<Vec<u8>> {
    let memory = match caller.get_export("memory") {
        Some(Extern::Memory(memory)) => memory,
        _ => {
            let runtime = caller.data().loading.runtime()?;
            runtime
                .get_memory(&mut *caller, "memory")
                .ok_or_else(|| format_err!("the program exports no memory"))?
        }
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
    if caller.data().loading.namespaces[namespace].contains_key(&name) || host_provided(&name) {
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
        (import "snail.core.support" "initialized" (func $initialized (result i32)))
        (import "snail.runtime.browser.screen" "draw" (func (param i32)))
        (func (export "main") (result i32)
          (if (i32.eqz (call $initialized)) (then (unreachable)))
          (i32.const 0))
        (func (export "lib:answer") (result i32) (i32.const 40)))"#;

    // The program's own module, last, answering through the library.
    const MAIN: &str = r#"(module
        (import "lib" "lib:answer" (func $answer (result i32)))
        (func (export "main") (result i32) (i32.add (call $answer) (i32.const 2))))"#;

    // A per-library build in a directory of its own: each module an object
    // of store/ beside the manifest, under a name standing for its digest,
    // and the manifest naming them.
    fn build(name: &str, runtime_text: &str) -> PathBuf {
        let runtime_file = PathBuf::from(module_file(&format!("{name}-runtime"), runtime_text));
        let directory = runtime_file.with_extension("build");
        let objects = directory.join("store").join("sha256");
        std::fs::create_dir_all(&objects).unwrap();
        std::fs::rename(&runtime_file, objects.join("runtime")).unwrap();
        std::fs::write(objects.join("lib"), wat::parse_str(LIBRARY).unwrap()).unwrap();
        std::fs::write(objects.join("main"), wat::parse_str(MAIN).unwrap()).unwrap();
        let manifest = r#"{"runtime": {"digest": "runtime", "size": 0}, "modules": [{"name": "lib", "digest": "lib", "size": 0}, {"name": "main", "digest": "main", "size": 0}], "files": []}"#;
        std::fs::write(directory.join("modules.json"), manifest).unwrap();
        directory.join("modules.json")
    }

    #[test]
    fn a_manifest_names_its_files_beside_it() {
        let manifest = build("manifest", &runtime(0));
        let read = Manifest::read(&manifest).unwrap();
        let objects = manifest.parent().unwrap().join("store/").join("sha256");
        assert_eq!(
            read.files(),
            [
                objects.join("runtime"),
                objects.join("lib"),
                objects.join("main")
            ]
        );
        assert_eq!(read.libraries[0].name, "lib");
    }

    #[test]
    fn a_manifest_names_the_store_its_objects_are_in() {
        let manifest = build("store", &runtime(0));
        let text = std::fs::read_to_string(&manifest).unwrap();
        std::fs::write(
            &manifest,
            text.replace(
                r#"{"runtime""#,
                r#"{"store": "../.snail-store/", "runtime""#,
            ),
        )
        .unwrap();
        let read = Manifest::read(&manifest).unwrap();
        let store = manifest.parent().unwrap().join("../.snail-store/");
        assert_eq!(read.runtime, store.join("sha256").join("runtime"));
    }

    #[test]
    fn what_is_not_a_manifest_is_refused() {
        let manifest = build("invalid", &runtime(0));
        std::fs::write(&manifest, r#"{"runtime": {"digest": "runtime"}}"#).unwrap();
        let error = Manifest::read(&manifest).err().unwrap().to_string();
        assert!(error.ends_with("modules.json is not the modules.json of a program"));
    }

    #[test]
    fn no_library_may_take_a_name_the_host_provides() {
        let manifest = build("reserved", &runtime(0));
        let text = std::fs::read_to_string(&manifest).unwrap();
        std::fs::write(
            &manifest,
            text.replace(r#""name": "lib""#, r#""name": "snail.runtime.wasm""#),
        )
        .unwrap();
        let error = Manifest::read(&manifest).err().unwrap().to_string();
        assert_eq!(
            error,
            "no library may be linked as snail.runtime.wasm, which the host provides"
        );
        assert!(host_provided("snail.core.support") && !host_provided("snail.core.control"));
    }
}
