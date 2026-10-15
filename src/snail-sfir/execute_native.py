"""Explicit loading, provider linking and isolated execution of SFIR native64 artifacts.

Native objects and providers are trusted executable code. Their versioned compiler
ABI is checked for consistency; this is neither a verifier of machine code nor a
sandbox. Each instance owns a process group, collector, globals and scalar services.
"""

from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import platform
import runpy
import select
import struct
import subprocess
import tempfile
import threading
import time
import weakref

ROOT = Path(__file__).resolve().parents[2]
BUILD = runpy.run_path(str(ROOT / 'scripts/build-native'))
SCALARS = {'I32', 'I64', 'F32', 'F64', 'Bool', 'Char'}
PHYSICAL = {'i32', 'i64', 'f32', 'f64'}
_codes, _linked = weakref.WeakSet(), weakref.WeakSet()
_instances = weakref.WeakKeyDictionary()


# ---- Compiler-owned ELF metadata ----


def region(data, offset, size):
    if offset < 0 or size < 0 or offset + size > len(data):
        raise ValueError('truncated native artifact')
    return data[offset:offset + size]


def string_at(data, offset):
    if offset < 0 or offset >= len(data) or b'\0' not in data[offset:]:
        raise ValueError('invalid native artifact string table')
    return data[offset:data.index(b'\0', offset)].decode('utf-8')


def elf_sections(data):
    header = struct.unpack('<16sHHIQQQIHHHHHH', region(data, 0, 64))
    magic, kind, machine, version, _, _, offset, _, size, _, _, stride, count, names = header
    if (magic[:7] != b'\x7fELF\x02\x01\x01' or magic[7] not in (0, 3)
            or (kind, machine, version, size, stride) != (1, 62, 1, 64, 64)
            or not 0 < names < count):
        raise ValueError('expected an x86-64 Linux relocatable ELF artifact')
    headers = [struct.unpack('<IIQQQQIIQQ', region(data, offset + i * 64, 64)) for i in range(count)]
    strings = region(data, headers[names][4], headers[names][5])
    return [(string_at(strings, item[0]), item) for item in headers]


def unique_section(sections, name):
    found = [(index, header) for index, (label, header) in enumerate(sections) if label == name]
    if len(found) != 1:
        raise ValueError(f'expected one native artifact section: {name}')
    return found[0]


def symbols(data, sections):
    _, header = unique_section(sections, '.symtab')
    if header[9] != 24 or header[5] % 24 or header[6] >= len(sections):
        raise ValueError('invalid native artifact symbol table')
    strings = sections[header[6]][1]
    names = region(data, strings[4], strings[5])
    result = {}
    for offset in range(header[4], header[4] + header[5], 24):
        name, info, visibility, section, value, size = struct.unpack('<IBBHQQ', region(data, offset, 24))
        if info >> 4 == 1 and section:
            result[string_at(names, name)] = (info & 15, visibility, section, value, size)
    return result


def check_bridge(data, sections, section_index, metadata, signature):
    exported = symbols(data, sections)
    entry, count, description = [exported.get(name) for name in
                                ('sfir_native_entry', 'sfir_native_arity', 'sfir_native_metadata')]
    if not entry or entry[:2] != (2, 0) or not count or count[:2] != (1, 0) or count[4] != 8:
        raise ValueError('native artifact lacks the fixed scalar bridge')
    witness = 'sfir_native_entry.' + ''.join(type_ + '_' for type_ in signature['parameters']) + '.' + signature['result']
    if exported.get(witness) != entry:
        raise ValueError('native artifact bridge signature disagrees with metadata')
    if description != (1, 0, section_index, 0, len(metadata)) or count[2] >= len(sections):
        raise ValueError('native artifact metadata symbol disagrees with its section')
    header = sections[count[2]][1]
    if struct.unpack('<Q', region(data, header[4] + count[3], 8))[0] != len(signature['parameters']):
        raise ValueError('native artifact bridge arity disagrees with metadata')


def json_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError('duplicate native metadata field')
    return result


@dataclass(frozen=True)
class NativeImport:
    module: str
    name: str
    symbol: str
    parameters: tuple
    result: str


def native_import(value):
    if (not isinstance(value, list) or len(value) != 5
            or not all(isinstance(name, str) and name for name in value[:3])
            or not isinstance(value[3], list) or not all(isinstance(item, str) and item in PHYSICAL for item in value[3])
            or not isinstance(value[4], str) or value[4] not in PHYSICAL | {'void'}):
        raise ValueError('unsupported native provider metadata')
    return NativeImport(*value[:3], tuple(value[3]), value[4])


def entry_metadata(metadata):
    value = json.loads(metadata, object_pairs_hook=json_object)
    keys = {'abi', 'version', 'library', 'export', 'parameters', 'result', 'imports'}
    if (not isinstance(value, dict) or set(value) != keys or value['abi'] != 'sfir-native-1'
            or type(value['version']) is not int or value['version'] != 1
            or not isinstance(value['library'], list) or not value['library']
            or not all(isinstance(name, str) and name for name in value['library'])
            or not isinstance(value['export'], str) or not value['export']
            or not isinstance(value['parameters'], list) or len(value['parameters']) > 1024
            or not all(isinstance(item, str) and item in SCALARS for item in value['parameters'])
            or not isinstance(value['result'], str) or value['result'] not in SCALARS | {'Unit'}
            or not isinstance(value['imports'], list)):
        raise ValueError('unsupported native scalar entry metadata')
    return value


@dataclass(frozen=True, eq=False)
class NativeCode:
    bytes: bytes
    library: tuple
    export: str
    parameters: tuple
    result: str
    imports: tuple


def parse_entry(data, sections):
    if any(header[1] in (14, 16) and header[5] for _, header in sections):
        raise ValueError('native artifact must not have automatic initializers')
    index, header = unique_section(sections, '.sfir.entry')
    metadata = region(data, header[4], header[5])
    entry = entry_metadata(metadata)
    check_bridge(data, sections, index, metadata, entry)
    imports = tuple(map(native_import, entry['imports']))
    if len({(item.module, item.name) for item in imports}) != len(imports):
        raise ValueError('duplicate native provider metadata')
    return entry, imports


def load_native(artifact_bytes):
    if not isinstance(artifact_bytes, (bytes, bytearray, memoryview)):
        raise TypeError('load_native requires artifact bytes')
    data = bytes(artifact_bytes)
    entry, imports = parse_entry(data, elf_sections(data))
    code = NativeCode(data, tuple(entry['library']), entry['export'], tuple(entry['parameters']), entry['result'], imports)
    _codes.add(code)
    return code


# ---- Explicit foreign provider linking ----


@dataclass(frozen=True)
class CProvider:
    module: str
    header: Path
    source: Path


@dataclass(frozen=True)
class RustProvider:
    """The repository's scalar Rust services, compiled from their declared sources."""


@dataclass(frozen=True, eq=False)
class LinkedCode:
    code: NativeCode
    directory: Path
    executable: Path


def provider_objects(providers, directory, clang, records):
    declarations, objects = [], []
    for provider in providers:
        if isinstance(provider, RustProvider):
            declarations.extend(BUILD['rust_bindings']())
        elif isinstance(provider, CProvider):
            interface, object_file = compile_c_provider(provider, directory / f'provider-{len(objects)}.o', clang, records)
            declarations.extend(interface)
            objects.append(object_file)
        else:
            raise TypeError('providers must contain CProvider or RustProvider values')
    return declarations, objects


def compile_c_provider(provider, output, clang, records):
    header, source = Path(provider.header).resolve(), Path(provider.source).resolve()
    if source.suffix != '.c':
        raise ValueError('native C provider requires source checked against its header')
    interface = BUILD['c_bindings'](provider.module, header, clang, records)
    BUILD['run']([clang, '-O2', '-c', '-include', header, source, '-o', output], records)
    return interface, output


def check_providers(imports, declarations):
    supplied = {}
    for key, symbol, parameters, results in declarations:
        if tuple(key) in supplied:
            raise ValueError(f'duplicate native provider: {key}')
        supplied[tuple(key)] = NativeImport(*key, symbol, tuple(parameters), results[0] if results else 'void')
    for required in imports:
        actual = supplied.get((required.module, required.name))
        if actual is None:
            raise ValueError(f'missing native provider: {required.module}/{required.name}')
        if actual != required:
            raise ValueError(f'native provider signature or symbol mismatch: {required.module}/{required.name}')


def runtime_archive(cargo, records):
    runtime = ROOT / 'build/native-runtime'
    BUILD['run']([cargo, 'rustc', '--quiet', '--offline', '--release', '--crate-type=staticlib',
                  '--features=native-runtime', '--manifest-path', ROOT / 'Cargo.toml', '--target-dir', runtime], records)
    return runtime / 'release/libsnail_runtime.a'


def link_program(code, providers, directory, records):
    if platform.machine() != 'x86_64' or platform.system() != 'Linux':
        raise ValueError('native execution requires x86-64 Linux')
    clang, cargo, lld = [BUILD['tool'](name, default) for name, default in
                         [('CLANG', 'clang'), ('CARGO', 'cargo'), ('LLD', 'ld.lld')]]
    declarations, objects = provider_objects(providers, directory, clang, records)
    check_providers(code.imports, declarations)
    runtime = runtime_archive(cargo, records)
    (directory / 'artifact.o').write_bytes(code.bytes)
    BUILD['run']([clang, '-O2', '-DSFIR_NATIVE_SUPERVISOR', ROOT / 'src/snail-sfir/native-worker.c',
                  '-o', directory / 'supervisor'], records)
    BUILD['run']([clang, '-O2', '-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections',
                  f'-fuse-ld={lld}', '-I', ROOT / 'src', directory / 'artifact.o', ROOT / 'src/native.c',
                  ROOT / 'src/precise-gc.c', ROOT / 'src/snail-sfir/native-worker.c', *objects,
                  runtime, '-ldl', '-lpthread', '-lm', '-o', directory / 'program'], records)


def link_native(code, providers, directory):
    if type(code) is not NativeCode or code not in _codes:
        raise TypeError('link_native requires loaded native code')
    Path(directory).mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='native-link-', dir=Path(directory).resolve()))
    records = []
    try:
        link_program(code, providers, output, records)
    finally:
        (output / 'commands.json').write_text(json.dumps(records, indent=2) + '\n')
    linked = LinkedCode(code, output, output / 'program')
    _linked.add(linked)
    return linked


# ---- Semantic scalar values and exact transport ----


def unicode_scalar(value):
    return 0 <= value <= 0x10ffff and not 0xd800 <= value <= 0xdfff


def scalar_word(type_, value):
    if type_ in ('I32', 'I64'):
        width = 32 if type_ == 'I32' else 64
        if type(value) is not int or not -(1 << (width - 1)) <= value < (1 << (width - 1)):
            raise TypeError(f'value does not satisfy scalar type {type_}')
        return value & ((1 << width) - 1)
    if type_ == 'Bool' and type(value) is bool:
        return int(value)
    if type_ == 'Char' and isinstance(value, str) and len(value) == 1 and unicode_scalar(ord(value)):
        return ord(value)
    if type_ in ('F32', 'F64') and type(value) is float:
        try:
            return int.from_bytes(struct.pack('<f' if type_ == 'F32' else '<d', value), 'little')
        except OverflowError as error:
            raise ValueError('finite F32 value overflows its representation') from error
    raise TypeError(f'value does not satisfy scalar type {type_}')


def scalar_result(type_, word):
    if type_ in ('I32', 'F32', 'Bool', 'Char') and word >> 32:
        raise ValueError('native scalar result has nonzero padding')
    if type_ in ('I32', 'I64'):
        width = 32 if type_ == 'I32' else 64
        return word - (1 << width) if word >> (width - 1) else word
    if type_ in ('F32', 'F64'):
        width = 4 if type_ == 'F32' else 8
        return struct.unpack('<f' if width == 4 else '<d', word.to_bytes(width, 'little'))[0]
    if type_ == 'Bool' and word in (0, 1):
        return bool(word)
    if type_ == 'Char' and unicode_scalar(word):
        return chr(word)
    if type_ == 'Unit' and word == 0:
        return None
    raise ValueError(f'invalid {type_} entry result')


# ---- Instance lifetime ----


class InitializationError(RuntimeError):
    pass


class NativeExecutionError(RuntimeError):
    pass


def wait_for_pipe(descriptor, writing, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError('native execution timed out')
    ready = select.select([] if writing else [descriptor], [descriptor] if writing else [], [], remaining)
    if not ready[1 if writing else 0] or time.monotonic() >= deadline:
        raise TimeoutError('native execution timed out')


def receive_word(response, deadline):
    data = bytearray()
    while len(data) < 8:
        wait_for_pipe(response, False, deadline)
        chunk = os.read(response, 8 - len(data))
        if not chunk:
            raise NativeExecutionError('native instance exited; see retained instance stderr')
        data.extend(chunk)
    return struct.unpack('<Q', data)[0]


def send_message(request, data, deadline):
    while data:
        wait_for_pipe(request, True, deadline)
        data = data[os.write(request, data):]


def reap_process(process, request, response):
    try:
        os.write(request, b'\0')
    except OSError:
        pass
    os.close(request)
    os.close(response)
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    return process.returncode


class NativeInstance:
    """Opaque instance handle; only instantiate publishes one."""


class InstanceState:
    def __init__(self, linked, directory, process, request, response, timeout, instance):
        self.code, self.directory = linked.code, directory
        self.request, self.response, self.timeout = request, response, timeout
        self.lock = threading.Lock()
        self.finalizer = weakref.finalize(instance, reap_process, process, request, response)


def spawn_instance(linked, directory, timeout, environment):
    request, writer = os.pipe()
    reader, response = os.pipe()
    os.set_blocking(writer, False)
    command = [str(linked.directory / 'supervisor'), str(linked.executable), str(request), str(response), str(os.getpid()),
               str(len(linked.code.parameters))]
    try:
        with (directory / 'stdout').open('wb') as stdout, (directory / 'stderr').open('wb') as stderr:
            process = subprocess.Popen(command, pass_fds=(request, response), start_new_session=True,
                                       stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                       env={**os.environ, **environment})
    except BaseException:
        os.close(writer)
        os.close(reader)
        raise
    finally:
        os.close(request)
        os.close(response)
    instance = NativeInstance()
    state = InstanceState(linked, directory, process, writer, reader, timeout, instance)
    try:
        (directory / 'process.json').write_text(json.dumps(dict(command=command, pid=process.pid, environment=environment)) + '\n')
    except BaseException:
        state.finalizer()
        raise
    return instance, state


def instantiate(linked, *, timeout=30, environment=None):
    if type(linked) is not LinkedCode or linked not in _linked:
        raise TypeError('instantiate requires explicitly linked native code')
    if not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise ValueError('native instance timeout must be finite and positive')
    directory = Path(tempfile.mkdtemp(prefix='instance-', dir=linked.directory))
    instance, state = spawn_instance(linked, directory, timeout, environment or {})
    try:
        if receive_word(state.response, time.monotonic() + timeout) != 0x3152494653:
            raise NativeExecutionError('invalid native initialization response')
    except BaseException as error:
        state.finalizer()
        if isinstance(error, (OSError, NativeExecutionError)):
            raise InitializationError(f'SFIR instance initialization failed; logs: {directory}') from error
        raise
    _instances[instance] = state
    return instance


def invoke_entry(instance, arguments):
    if type(instance) is not NativeInstance or instance not in _instances:
        raise TypeError('invoke_entry requires a native instance')
    state = _instances[instance]
    if not state.lock.acquire(blocking=False):
        raise RuntimeError('native instance is already executing')
    try:
        if not state.finalizer.alive:
            raise RuntimeError('native instance is closed')
        if not isinstance(arguments, (list, tuple)) or len(arguments) != len(state.code.parameters):
            raise TypeError('entry arguments do not match the saved parameter count')
        words = [scalar_word(type_, value) for type_, value in zip(state.code.parameters, arguments)]
        return call_instance(state, words)
    finally:
        state.lock.release()


def call_instance(instance, words):
    try:
        deadline = time.monotonic() + instance.timeout
        send_message(instance.request, b'\1' + b''.join(struct.pack('<Q', word) for word in words), deadline)
        return scalar_result(instance.code.result, receive_word(instance.response, deadline))
    except BaseException as error:
        instance.finalizer()
        instance.code = None
        if isinstance(error, (OSError, NativeExecutionError, ValueError)):
            raise NativeExecutionError(f'native instance failed and is closed; logs: {instance.directory}') from error
        raise


def close_instance(instance):
    if type(instance) is not NativeInstance or instance not in _instances:
        raise TypeError('close_instance requires a native instance')
    state = _instances[instance]
    if not state.lock.acquire(blocking=False):
        raise RuntimeError('native instance is already executing')
    try:
        status = state.finalizer()
        state.code = None
        if status:
            raise NativeExecutionError(f'native instance cleanup failed; logs: {state.directory}')
    finally:
        state.lock.release()
