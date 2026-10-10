#!/usr/bin/env python3
"""Dirty HIR-to-WasmGC subset: dynamic eqrefs, i31 values, and native Wasm calls."""

import argparse, ast, re
from pathlib import Path

# ---- Input ----


def read_sexp(text):
    tokens = iter(re.findall(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+', text))

    def read(token):
        if token == "(":
            result = []
            for token in tokens:
                if token == ")":
                    return result
                result.append(read(token))
            raise ValueError("unterminated list")
        if token.startswith('"'):
            return ast.literal_eval(token)
        try:
            return int(token)
        except ValueError:
            return token

    return read(next(tokens))


# ---- Checked numeric operators ----


def arithmetic_fallback(op):
    instruction = "add" if op == 0 else "sub"
    overflow = (
        "(i64.and (i64.xor (local.get $n) (local.get $x)) (i64.xor (local.get $n) (local.get $y)))"
        if op == 0
        else "(i64.and (i64.xor (local.get $x) (local.get $y)) (i64.xor (local.get $x) (local.get $n)))"
    )
    return f"""(func $slow_{op} (param $a eqref) (param $b eqref) (result eqref)
      (local $x i64) (local $y i64) (local $n i64)
      (if (result eqref) (i32.and (call $is_integer (local.get $a)) (call $is_integer (local.get $b)))
        (then
          (local.set $x (call $integer_value (local.get $a)))
          (local.set $y (call $integer_value (local.get $b)))
          (local.set $n (i64.{instruction} (local.get $x) (local.get $y)))
          (if (i64.lt_s {overflow} (i64.const 0)) (then (call $fail (i32.const 2))))
          (call $pack_integer (local.get $n)))
        (else (struct.new $float (f64.{instruction} (call $float_value (local.get $a)) (call $float_value (local.get $b)))))))"""


def numeric_operator(op):
    if op < 2:
        fast = f"""(local.set $n (i32.{"add" if op == 0 else "sub"} (local.get $x) (local.get $y)))
          (if (result eqref) (i32.le_u (i32.add (local.get $n) (i32.const 1073741824)) (i32.const 2147483647))
            (then (ref.i31 (local.get $n))) (else (call $slow_{op} (local.get $a) (local.get $b))))"""
        slow = f"(call $slow_{op} (local.get $a) (local.get $b))"
    else:
        predicate = ["eq", "lt_s", "le_s", "gt_s", "ge_s"][op - 2]
        fast = f"(call $pack_boolean (i32.{predicate} (local.get $x) (local.get $y)))"
        slow = f"""(local.set $order (call $compare (local.get $a) (local.get $b)))
          (call $pack_boolean (i32.and (i32.ne (local.get $order) (i32.const 2))
                                     (i32.{predicate} (local.get $order) (i32.const 0))))"""
    return f"""(func $op_{op} (param $a eqref) (param $b eqref) (result eqref)
      (local $x i32) (local $y i32) (local $n i32) (local $order i32)
      (if (result eqref)
        (i32.and (ref.test (ref i31) (local.get $a)) (ref.test (ref i31) (local.get $b)))
        (then
          (local.set $x (i31.get_s (ref.cast (ref i31) (local.get $a))))
          (local.set $y (i31.get_s (ref.cast (ref i31) (local.get $b))))
          {fast})
        (else {slow})))"""


# ---- HIR expressions and real Wasm calls ----


def expression(node, index, tail=False):
    op, *args = node
    if op == "literal":
        return f"(ref.i31 (i32.const {args[0]}))"
    if op == "argument":
        return f"(local.get $arg{args[0]})"
    if op == "sequence":
        if len(args) == 1:
            return expression(args[0], index, tail)
        return (
            "(block (result eqref) "
            + " ".join("(drop " + expression(item, index) + ")" for item in args[:-1])
            + " "
            + expression(args[-1], index, tail)
            + ")"
        )
    if op == "if":
        condition = (
            f"(i32.eqz (ref.eq {expression(args[0], index)} (global.get $false)))"
        )
        return f"(if (result eqref) {condition} (then {expression(args[1], index, tail)}) (else {expression(args[2], index, tail)}))"
    instruction = "return_call" if op == "recur" and tail else "call"
    target = f"$function_{index}" if op == "recur" else f"$op_{op}"
    return (
        f"({instruction} {target} "
        + " ".join(expression(arg, index) for arg in args)
        + ")"
    )


def function(name, index, arity, body):
    parameters = " ".join(f"(param $arg{i} eqref)" for i in range(arity))
    return f"(func $function_{index} {parameters} (result eqref)\n  {expression(body, index, True)})"


def adapter(name, index, arity, kind):
    types = [kind] * arity
    if kind == "mixed":
        types = ["i64", "f64"]
    suffix = "" if kind == "i32" else "_" + kind
    params = " ".join(f"(param $a{i} {type})" for i, type in enumerate(types))
    constructors = {
        "i32": "call $input_i31",
        "i64": "call $pack_integer",
        "f64": "struct.new $float",
    }
    args = " ".join(
        f"({constructors[type]} (local.get $a{i}))" for i, type in enumerate(types)
    )
    result = f"(call $function_{index} {args})"
    if kind == "i32":
        result = f"(call $result_i32 {result})"
        return_type = "i32"
    elif kind == "i64":
        result = f"(call $result_integer {result})"
        return_type = "i64"
    else:
        result = f"(call $result_float {result})"
        return_type = "f64"
    return f'(func (export "{name + suffix}") {params} (result {return_type}) {result})'


def main():
    p = argparse.ArgumentParser()
    p.add_argument("descriptors")
    p.add_argument("output")
    a = p.parse_args()
    functions = read_sexp(Path(a.descriptors).read_text())
    module = [Path(__file__).with_name("numbers.wat").read_text()]
    module += [arithmetic_fallback(op) for op in range(2)]
    module += [numeric_operator(op) for op in range(7)]
    for name, index, arity, body in functions:
        module.append(function(name, index, arity, body))
        module += [
            adapter(name, index, arity, kind)
            for kind in ["i32", "i64", "f64"] + (["mixed"] if arity == 2 else [])
        ]
    module += [
        """(func (export "type_error") (result eqref)
                    (call $op_0 (global.get $false) (ref.i31 (i32.const 1))))"""
    ]
    Path(a.output).write_text("(module\n" + "\n\n".join(module) + "\n)\n")
    print(
        "WasmGC functions:", [(name, arity) for name, index, arity, body in functions]
    )


if __name__ == "__main__":
    main()
