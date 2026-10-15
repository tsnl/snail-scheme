"""Real native execution is the oracle, including ownership failures and GC."""

import ctypes
from dataclasses import replace
import gc
import json
import math
import os
from pathlib import Path
import signal
import re
import struct
import subprocess
import sys
import time
import threading
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'src/snail-sfir'))
import execute_native as native

FIXTURES = Path(__file__).resolve().parent
OUTPUT = Path(sys.argv[1])
PROVIDERS = [native.CProvider('probe', FIXTURES / 'provider.h', FIXTURES / 'provider.c'), native.RustProvider()]


# ---- Retained compilation and owned instances ----


def fails(exception, action, message=''):
    try:
        action()
    except exception as error:
        assert message in str(error), (message, error)
        return error
    raise AssertionError(f'expected {exception.__name__}: {message}')


def linked(name, providers=PROVIDERS):
    return native.link_native(native.load_native((OUTPUT / f'{name}.o').read_bytes()), providers, OUTPUT)


def environment(name):
    return dict(SNAIL_NATIVE_GC_INTERVAL='1', SNAIL_GC_STATS='1',
                SNAIL_TEST_EFFECTS=str(OUTPUT / f'{name}-effects'),
                SNAIL_TEST_CHILD=str(OUTPUT / f'{name}-child'),
                SNAIL_TEST_RESOURCE=str(OUTPUT / f'{name}-resource'))


def gone(pid):
    deadline = time.monotonic() + 5
    while Path(f'/proc/{pid}').exists() and time.monotonic() < deadline:
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass
        time.sleep(0.01)
    assert not Path(f'/proc/{pid}').exists(), f'owned process remains: {pid}'


# ---- Tests ----


def check_state():
    code = linked('state')
    first = native.instantiate(code, environment=environment('first'))
    second = native.instantiate(code, environment=environment('second'))
    assert [native.invoke_entry(first, [amount]) for amount in (10, 20, 1)] == [11, 31, 32]
    assert native.invoke_entry(second, [2]) == 3
    # An attribute on the opaque handle cannot replace its owned signature.
    first.code = replace(code.code, parameters=('F64',))
    fails(TypeError, lambda: native.invoke_entry(first, [1.0]))
    assert native.invoke_entry(first, [1]) == 33
    for name, instance in [('first', first), ('second', second)]:
        native.close_instance(instance)
        native.close_instance(instance)
        fails(RuntimeError, lambda: native.invoke_entry(instance, [0]), 'closed')
        effects = (OUTPUT / f'{name}-effects').read_text().splitlines()
        assert [line.split()[1] for line in effects] == ['1', '2'], effects
    for log in code.directory.glob('instance-*/stderr'):
        assert int(re.search(r'collections=(\d+)', log.read_text())[1]) > 0
    third = native.instantiate(linked('state'), environment=environment('third'))
    assert native.invoke_entry(third, [2]) == 3
    native.close_instance(third)
    print('PASS independent globals, provider state, aliases, closure roots and repeated calls')


def check_scalars():
    cases = {'i32': [-2**31, 0, 2**31-1], 'i64': [-2**63, -(2**53+1), 0, 2**53+1, 2**63-1],
             'f32': [0.0, -0.0, 1.0+2**-24, 2**-149, 1e-50, math.inf, -math.inf, math.nan],
             'f64': [0.0, -0.0, 2**-1074, 1.1, math.inf, -math.inf, math.nan],
             'bool': [False, True], 'char': ['\0', 'A', '😀', chr(0x10ffff)], 'unit-result': []}
    bad = {'i32': [True, 2**31, -2**31-1, 1.0], 'i64': [True, 2**63, -2**63-1, 1.0],
           'f32': [1, 1e300], 'f64': [1], 'bool': [0, 1], 'char': ['', 'ab', '\ud800']}
    for name, values in cases.items():
        code = linked(name, [])
        instance = native.instantiate(code)
        for value in values:
            result = native.invoke_entry(instance, [value])
            if type(value) is float:
                expected = struct.unpack('<f', struct.pack('<f', value))[0] if name == 'f32' else value
                assert math.isnan(result) if math.isnan(expected) else result == expected
                assert value != 0 or math.copysign(1, value) == math.copysign(1, result)
            else:
                assert result == value and type(result) is type(value), (name, result, value)
        for value in bad.get(name, []):
            fails((TypeError, ValueError), lambda: native.invoke_entry(instance, [value]))
        if name == 'unit-result':
            assert native.invoke_entry(instance, []) is None
        else:
            fails(TypeError, lambda: native.invoke_entry(instance, []), 'parameter count')
        native.close_instance(instance)
    print('PASS exact I64, IEEE F32/F64, Bool, Unicode Char and Unit transport')


def check_rejections():
    code = native.load_native((OUTPUT / 'state.o').read_bytes())
    fails(TypeError, lambda: native.link_native(replace(code), PROVIDERS, OUTPUT), 'loaded native code')
    class EqualCode(native.NativeCode):
        def __hash__(self):
            return hash(code)
        def __eq__(self, other):
            return other is code
    forged = EqualCode(code.bytes, code.library, code.export, code.parameters, code.result, code.imports)
    fails(TypeError, lambda: native.link_native(forged, PROVIDERS, OUTPUT), 'loaded native code')
    fails(ValueError, lambda: native.link_native(code, [], OUTPUT), 'missing native provider')
    wrong = native.CProvider('probe', FIXTURES / 'wrong.h', FIXTURES / 'wrong.c')
    fails(ValueError, lambda: native.link_native(code, [wrong], OUTPUT), 'signature or symbol mismatch')
    valid = linked('i32', [])
    fails(TypeError, lambda: native.instantiate(replace(valid)), 'explicitly linked')
    fails(TypeError, lambda: native.invoke_entry(native.NativeInstance(), [1]), 'native instance')
    changed = code.bytes.replace(b'"parameters":["I32"]', b'"parameters":["I64"]')
    assert changed != code.bytes
    fails(ValueError, lambda: native.load_native(changed), 'bridge signature disagrees')
    fails(ValueError, lambda: native.load_native(code.bytes[:40]), 'truncated')
    for name in ('bad-bool', 'bad-char'):
        instance = native.instantiate(linked(name))
        fails(native.NativeExecutionError, lambda: native.invoke_entry(instance, []), 'closed')
    rust = native.instantiate(linked('lowercase', [native.RustProvider()]))
    assert native.invoke_entry(rust, ['Ω']) == 'ω'
    native.close_instance(rust)
    print('PASS owned descriptors, actual provider declarations, bridge witness and Rust provider')


def check_failure():
    code = linked('failed')
    fails(native.InitializationError, lambda: native.instantiate(code, environment=environment('failed')))
    assert [line.split()[1] for line in (OUTPUT / 'failed-effects').read_text().splitlines()] == ['7']
    assert (OUTPUT / 'failed-resource').read_text() == 'x'
    gone(int((OUTPUT / 'failed-child').read_text()))
    code = linked('traps', [])
    first, second = native.instantiate(code), native.instantiate(code)
    fails(native.NativeExecutionError, lambda: native.invoke_entry(first, [0]), 'closed')
    fails(RuntimeError, lambda: native.invoke_entry(first, [1]), 'closed')
    assert native.invoke_entry(second, [42]) == 42
    native.close_instance(second)
    print('PASS unpublished failed initialization, retained effects and isolated trap lifetime')


def check_lifetime():
    code = linked('lifetime')
    instance = native.instantiate(code, environment=environment('lifetime'))
    assert native.invoke_entry(instance, []) == 42
    native.close_instance(instance)
    gone(int((OUTPUT / 'lifetime-child').read_text()))
    assert (OUTPUT / 'lifetime-resource').read_text() == 'x'
    # Dropping the last handle owns the same shutdown operation as explicit close.
    instance = native.instantiate(code, environment=environment('dropped'))
    del instance
    gc.collect()
    gone(int((OUTPUT / 'dropped-child').read_text()))
    assert (OUTPUT / 'dropped-resource').read_text() == 'x'
    print('PASS normal close, finalization, TERM-ignoring descendants and Rust resource cleanup')


def check_publication_failure():
    code = linked('lifetime')
    original, processes = Path.write_text, []
    popen = subprocess.Popen
    def record_process(*arguments, **keywords):
        process = popen(*arguments, **keywords)
        processes.append(process)
        return process
    def fail_record(path, *arguments, **keywords):
        if path.name == 'process.json':
            raise OSError('injected publication failure')
        return original(path, *arguments, **keywords)
    with patch.object(Path, 'write_text', fail_record), patch.object(native.subprocess, 'Popen', record_process):
        fails(OSError, lambda: native.instantiate(code, environment=environment('publication')), 'injected')
    assert len(processes) == 1 and processes[0].poll() is not None
    gone(processes[0].pid)
    if (OUTPUT / 'publication-child').exists():
        gone(int((OUTPUT / 'publication-child').read_text()))
    print('PASS cleanup ownership survives failed startup record publication')


def check_interruption():
    code = linked('i32', [])
    instance = native.instantiate(code)
    with patch.object(native, 'receive_word', side_effect=KeyboardInterrupt):
        fails(KeyboardInterrupt, lambda: native.invoke_entry(instance, [42]))
    fails(RuntimeError, lambda: native.invoke_entry(instance, [43]), 'closed')
    with patch.object(native, 'receive_word', side_effect=KeyboardInterrupt):
        fails(KeyboardInterrupt, lambda: native.instantiate(code))
    print('PASS interrupted startup and outstanding calls close their owned execution')


def check_constructor():
    code = linked('i32')
    env = {**environment('constructor'), 'SNAIL_TEST_CONSTRUCTOR': '1'}
    instance = native.instantiate(code, environment=env)
    assert native.invoke_entry(instance, [42]) == 42
    native.close_instance(instance)
    gone(int((OUTPUT / 'constructor-child').read_text()))
    print('PASS provider constructors run only after process ownership is established')


def check_busy_and_timeouts():
    instance = native.instantiate(linked('i32', []))
    entered, resume, results = threading.Event(), threading.Event(), []
    original = native.receive_word
    def held_receive(*arguments):
        entered.set()
        assert resume.wait(3)
        return original(*arguments)
    with patch.object(native, 'receive_word', held_receive):
        thread = threading.Thread(target=lambda: results.append(native.invoke_entry(instance, [42])))
        thread.start()
        assert entered.wait(3)
        fails(RuntimeError, lambda: native.invoke_entry(instance, [43]), 'already executing')
        fails(RuntimeError, lambda: native.close_instance(instance), 'already executing')
        resume.set()
        thread.join(3)
    assert results == [42]
    native.close_instance(instance)
    code = linked('i32')
    env = {**environment('init-timeout'), 'SNAIL_TEST_CONSTRUCTOR': '1', 'SNAIL_TEST_CONSTRUCTOR_HANG': '1'}
    fails(native.InitializationError, lambda: native.instantiate(code, timeout=0.05, environment=env))
    gone(int((OUTPUT / 'init-timeout-child').read_text()))
    instance = native.instantiate(linked('hang'), timeout=0.05)
    fails(native.NativeExecutionError, lambda: native.invoke_entry(instance, []), 'closed')
    print('PASS racing call/close rejection and real startup/call timeouts')


def check_deadlines():
    reader, writer = os.pipe()
    try:
        os.write(writer, b'12345678')
        with patch.object(native.time, 'monotonic', return_value=11):
            fails(TimeoutError, lambda: native.receive_word(reader, 10))
            fails(TimeoutError, lambda: native.send_message(writer, b'extra', 10))
        with patch.object(native.time, 'monotonic', side_effect=[9, 11]):
            fails(TimeoutError, lambda: native.receive_word(reader, 10))
        assert os.read(reader, 8) == b'12345678'
        os.set_blocking(reader, False)
        fails(BlockingIOError, lambda: os.read(reader, 1))
    finally:
        os.close(reader)
        os.close(writer)
    print('PASS an expired absolute deadline prevents I/O even on a ready pipe')


def lost_host():
    code = linked('lifetime')
    # Keep the actual handle live until the host is killed.
    instance = native.instantiate(code, environment=environment('host-loss-live'))
    records = sorted(code.directory.glob('instance-*/process.json'), key=lambda path: path.stat().st_mtime_ns)
    (OUTPUT / 'host-ready').write_text(json.dumps(json.loads(records[-1].read_text())))
    time.sleep(60)
    native.close_instance(instance)


def check_host_loss():
    # The test itself reaps the orphaned supervisor after it reaps its workers.
    assert ctypes.CDLL(None).prctl(36, 1, 0, 0, 0) == 0
    with (OUTPUT / 'host-loss.stdout').open('wb') as stdout, (OUTPUT / 'host-loss.stderr').open('wb') as stderr:
        process = subprocess.Popen([sys.executable, __file__, str(OUTPUT), 'lost-host'], stdout=stdout, stderr=stderr)
    try:
        deadline = time.monotonic() + 20
        while not (OUTPUT / 'host-ready').exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.01)
        assert (OUTPUT / 'host-ready').exists(), (OUTPUT / 'host-loss.stderr').read_text()
        supervisor = json.loads((OUTPUT / 'host-ready').read_text())['pid']
        process.kill()
        process.wait(timeout=3)
        gone(supervisor)
        gone(int((OUTPUT / 'host-loss-live-child').read_text()))
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
    print('PASS host SIGKILL is detected and owned TERM-ignoring descendants are reaped')


if __name__ == '__main__':
    if len(sys.argv) > 2:
        lost_host()
    else:
        for check in [check_state, check_scalars, check_rejections, check_failure, check_lifetime,
                      check_publication_failure, check_interruption, check_constructor, check_busy_and_timeouts,
                      check_deadlines, check_host_loss]:
            check()
