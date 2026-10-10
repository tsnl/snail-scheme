#!/usr/bin/env python3
"""Mirror the WasmGC numeric checks against translated native exports."""

import ctypes, math, os, resource, signal, sys
from pathlib import Path

library = ctypes.CDLL(
    str(
        Path(sys.argv[1] if len(sys.argv) > 1 else "build/wasm-llvm/check.so").resolve()
    )
)
library.wasm_init()
I32, I64, F64 = ctypes.c_int32, ctypes.c_int64, ctypes.c_double
count = 0


def invoke(name, *values):
    function = getattr(library, "wasm_export_" + name.replace("-", "_"))
    if name.endswith("_mixed"):
        function.argtypes = [I64, F64]
        function.restype = F64
    elif name.endswith("_i64"):
        function.argtypes = [I64] * len(values)
        function.restype = I64
    elif name.endswith("_f64"):
        function.argtypes = [F64] * len(values)
        function.restype = F64
    else:
        function.argtypes = [I32] * len(values)
        function.restype = I32
    return function(*values)


def check(name, args, expected):
    global count
    actual = invoke(name, *args)
    assert (
        actual == expected
        or isinstance(expected, float)
        and math.isnan(expected)
        and math.isnan(actual)
    ), (name, args, actual, expected)
    count += 1


def trap(name, args):
    global count
    child = os.fork()
    if child == 0:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        invoke(name, *args)
        os._exit(0)
    _, status = os.waitpid(child, 0)
    assert os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGILL, (
        name,
        args,
        status,
    )
    count += 1


maximum, minimum = (1 << 63) - 1, -(1 << 63)
for name, args, expected in [
    ("sum_i64", (1073741823, 1), 1073741824),
    ("sum", (1073741823, 1), 1073741824),
    ("sum", (-1073741824, 0), -1073741824),
    ("difference_i64", (-1073741824, 1), -1073741825),
    ("sum_i64", (-1073741824, -1073741824), -2147483648),
    ("sum_i64", (maximum, minimum), -1),
    ("difference_i64", (minimum, minimum), 0),
    ("sum_f64", (3.5, 2), 5.5),
    ("difference_f64", (4, 1.5), 2.5),
    ("sum_mixed", (3, 2.5), 5.5),
    ("sum_mixed", (9007199254740993, 0), 9007199254740992),
    ("sum_f64", (math.inf, 1), math.inf),
    ("difference_f64", (math.inf, math.inf), math.nan),
    ("double-sum_i64", (1073741823, 1073741823), 4294967292),
    ("truthy", (0,), 1),
    ("equal-number_mixed", (9007199254740993, 9007199254740992), 0),
    ("greater_mixed", (9007199254740993, 9007199254740992), 1),
    ("less_mixed", (9007199254740993, 9007199254740992), 0),
    ("less_mixed", (maximum, 9223372036854775808), 1),
    ("equal-number_mixed", (maximum, 9223372036854775808), 0),
    ("equal-number_mixed", (minimum, -9223372036854775808), 1),
    ("less_mixed", (minimum, -math.inf), 0),
    ("greater_mixed", (minimum, -math.inf), 1),
    ("less_mixed", (maximum, math.inf), 1),
    ("down", (2000000, 0), 2000000),
]:
    check(name, args, expected)
for name in ["equal-number", "less", "less-equal", "greater", "greater-equal"]:
    check(name + "_mixed", (1, math.nan), 0)
    check(name + "_f64", (math.nan, 1), 0)
for name, args in [
    ("sum_i64", (maximum, 1)),
    ("sum_i64", (minimum, -1)),
    ("difference_i64", (maximum, -1)),
    ("difference_i64", (minimum, 1)),
    ("type_error", ()),
    ("sum", (1073741824, 0)),
    ("sum", (-1073741825, 0)),
    ("double-sum", (1073741823, 1073741823)),
]:
    trap(name, args)
print(f"Native translated Wasm: {count} checks passed")
