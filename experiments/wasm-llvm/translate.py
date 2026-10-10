#!/usr/bin/env python3
"""Two-pass, bounded WasmGC-to-LLVM prototype. Binaryen decodes actual .wasm.

No Scheme/HIR input is accepted. Pass one records module declarations; pass two
emits functions. LLVM promotes native local slots to SSA. References are raw
BDWGC pointers or odd tagged signed31 words; boxed structs use 8-byte slots.
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
from pathlib import Path

# ---- Binary decoding and declarations ----

BINARYEN = "/nix/store/nd1279k2zlbp23gfqcl0qp5xk40xlxr8-binaryen-132/bin/wasm-dis"


def parse(text):
    tokens = iter(
        re.findall(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+', re.sub(r";;[^\n]*", "", text))
    )

    def read(token):
        if token == "(":
            out = []
            for nested in tokens:
                if nested == ")":
                    return out
                out.append(read(nested))
            raise ValueError("unterminated WAT list")
        return json.loads(token) if token.startswith('"') else token

    result = read(next(tokens))
    if next(tokens, None) is not None:
        raise ValueError("trailing WAT forms")
    return result


def llvm_type(type):
    if isinstance(type, list) and type[0] == "tuple":
        return "{ " + ", ".join(llvm_type(t) for t in type[1:]) + " }"
    if isinstance(type, list) and type[0] == "ref":
        return "i64"
    if type in ("eqref", "i31ref", "structref", "anyref", "nullref"):
        return "i64"
    if type in ("i32", "i64"):
        return type
    if type == "f64":
        return "double"
    raise ValueError(f"unsupported value type: {type}")


def zero(type):
    if type.startswith("{"):
        return "zeroinitializer"
    return "0.0" if type == "double" else "0"


def named(prefix, name):
    return prefix + re.sub(r"[^A-Za-z0-9_]", "_", name.lstrip("$"))


def signature(node):
    params = []
    locals = []
    result = "void"
    body = []
    for item in node[2:]:
        if item[0] in ("param", "local"):
            target = params if item[0] == "param" else locals
            values = item[1:]
            if isinstance(values[0], str) and values[0].startswith("$"):
                target.append((values[0], llvm_type(values[1])))
            else:
                base = len(params) + len(locals)
                target.extend(
                    (f"${base + i}", llvm_type(t)) for i, t in enumerate(values)
                )
        elif item[0] == "result":
            if len(item) != 2:
                raise ValueError("multi-value results unsupported")
            result = llvm_type(item[1])
        elif item[0] != "type":
            body.append(item)
    return {
        "name": node[1],
        "params": params,
        "locals": locals,
        "result": result,
        "body": body,
    }


class Module:
    def __init__(self, node):
        if node[0] != "module":
            raise ValueError("expected module")
        self.structs = {}
        self.functions = {}
        self.globals = {}
        self.exports = []
        self.imports = {}
        self.function_types = {}
        self.continuations = {}
        self.tags = {}
        self.continuation_entries = set()
        for entry in node[1:]:
            op = entry[0]
            if op == "type":
                definition = entry[2]
                if definition[0] == "struct":
                    fields = []
                    for field in definition[1:]:
                        if field[0] != "field":
                            raise ValueError("unsupported struct field")
                        type = field[-1]
                        fields.append(
                            llvm_type(
                                type[1]
                                if isinstance(type, list) and type[0] == "mut"
                                else type
                            )
                        )
                    self.structs[entry[1]] = (len(self.structs) + 1, fields)
                elif definition[0] == "func":
                    self.function_types[entry[1]] = definition
                elif definition[0] == "cont":
                    self.continuations[entry[1]] = definition[1]
                else:
                    raise ValueError(f"unsupported type: {definition[0]}")
            elif op == "func":
                self.functions[entry[1]] = signature(entry)
            elif op == "global":
                type = entry[2]
                type = type[1] if isinstance(type, list) and type[0] == "mut" else type
                self.globals[entry[1]] = (llvm_type(type), entry[3])
            elif op == "export":
                self.exports.append((entry[1], entry[2]))
            elif op == "import":
                if (
                    entry[1] != "env"
                    or entry[2]
                    not in ("collect", "observe", "foreign_enter", "foreign_leave")
                    or entry[3][0] != "func"
                ):
                    raise ValueError(f"unsupported import: {entry[1:3]}")
                function = signature(entry[3])
                function["symbol"] = "native_" + entry[2]
                self.imports[entry[3][1]] = function
            elif op == "tag":
                tag = signature(entry)
                if [t for _, t in tag["params"]] != ["i64"] or tag["result"] != "i64":
                    raise ValueError("prototype control tags require i64 -> i64")
                if len(self.tags) == 64:
                    raise ValueError("prototype supports at most 64 control tags")
                self.tags[entry[1]] = len(self.tags)
            elif op == "memory":
                pass  # Declaration only; memory operations fail below.
            else:
                raise ValueError(f"unsupported module declaration: {op}")
        symbols = [named("fn_", name) for name in self.functions]
        symbols += [named("global_", name) for name in self.globals]
        symbols += [function["symbol"] for function in self.imports.values()]
        symbols += [
            named("wasm_export_" if target[0] == "func" else "wasm_global_", export)
            for export, target in self.exports
            if target[0] != "memory"
        ]
        if len(symbols) != len(set(symbols)):
            raise ValueError("module names collide in the prototype's native ABI")


# ---- Native blocks and values ----


class Function:
    def __init__(self, module, signature):
        self.module = module
        self.signature = signature
        self.lines = []
        self.serial = 0
        self.block = "entry"
        self.locals = {}
        self.targets = []
        self.lines.append("entry:")
        for index, (name, type) in enumerate(signature["params"] + signature["locals"]):
            pointer = self.value("ptr", f"alloca {type}, align 8")
            self.locals[name] = (type, pointer)
            initial = f"%arg{index}" if index < len(signature["params"]) else zero(type)
            self.line(f"store {type} {initial}, ptr {pointer}, align 8")

    def fresh(self, prefix="v"):
        self.serial += 1
        return prefix + str(self.serial)

    def line(self, text):
        if self.block is None:
            raise ValueError(
                "terminating operand expressions are outside this prototype"
            )
        self.lines.append("  " + text)

    def value(self, type, instruction):
        value = "%" + self.fresh()
        self.line(f"{value} = {instruction}")
        return value

    def label(self, label):
        self.lines.append(label + ":")
        self.block = label

    def finish(self, instruction):
        self.line(instruction)
        self.block = None

    def trap(self):
        self.line("call void @llvm.trap()")
        self.finish("unreachable")

    def guard(self, condition):
        yes, no = self.fresh("b"), self.fresh("b")
        self.finish(f"br i1 {condition}, label %{yes}, label %{no}")
        self.label(no)
        self.trap()
        self.label(yes)

    def condition(self, value):
        type, word = value
        return word if type == "i1" else self.value("i1", f"icmp ne {type} {word}, 0")

    def boolean(self, condition):
        return ("i32", self.value("i32", f"zext i1 {condition} to i32"))

    def sequence(self, nodes):
        result = None
        for node in nodes:
            if self.block is None:
                break
            result = self.emit(node)
        return result

    def structured_if(self, args):
        if args and isinstance(args[0], list) and args[0][0] == "result":
            args = args[1:]
        condition = self.condition(self.emit(args[0]))
        yes, no, join = [self.fresh("b") for _ in range(3)]
        self.finish(f"br i1 {condition}, label %{yes}, label %{no}")
        incoming = []
        for label, nodes in [
            (yes, args[1][1:]),
            (no, args[2][1:] if len(args) > 2 else []),
        ]:
            self.label(label)
            value = self.sequence(nodes)
            if self.block is not None:
                incoming.append((value, self.block))
                self.finish(f"br label %{join}")
        if not incoming:
            return None
        self.label(join)
        if incoming[0][0] is None:
            return None
        type = incoming[0][0][0]
        if any(value is None or value[0] != type for value, _ in incoming):
            raise ValueError("invalid if result")
        values = ", ".join(f"[{value[1]}, %{block}]" for value, block in incoming)
        return type, self.value(type, f"phi {type} {values}")

    # ---- Structured branch results ----

    def tuple(self, values):
        type = "{ " + ", ".join(t for t, _ in values) + " }"
        word = "poison"
        for index, (field_type, value) in enumerate(values):
            word = self.value(
                type, f"insertvalue {type} {word}, {field_type} {value}, {index}"
            )
        return type, word

    def target(self, name):
        for target in reversed(self.targets):
            if target["name"] == name:
                return target
        raise ValueError(f"unknown block label: {name}")

    def branch(self, target, value):
        expected = target["type"]
        if (value[0] if value else "void") != expected:
            raise ValueError(
                f"branch result mismatch: expected {expected}, got {value}"
            )
        target["incoming"].append((value, self.block))
        self.finish(f"br label %{target['label']}")

    def structured_block(self, args):
        name = args.pop(0) if args and isinstance(args[0], str) else None
        results = next((arg[1:] for arg in args if arg[0] == "result"), [])
        type = (
            llvm_type(["tuple", *results])
            if len(results) > 1
            else llvm_type(results[0])
            if results
            else "void"
        )
        target = {
            "name": name,
            "label": self.fresh("block"),
            "type": type,
            "incoming": [],
        }
        self.targets.append(target)
        result = self.sequence(
            [arg for arg in args if arg[0] not in ("result", "type")]
        )
        if self.block is not None:
            self.branch(target, result)
        self.targets.pop()
        if not target["incoming"]:
            return None
        self.label(target["label"])
        if type == "void":
            return None
        incoming = ", ".join(
            f"[{value[1]}, %{block}]" for value, block in target["incoming"]
        )
        return type, self.value(type, f"phi {type} {incoming}")

    # ---- Single-shot delimited continuations ----

    def continuation_type(self, name):
        definition = self.module.function_types[self.module.continuations[name]]
        function = signature(["func", "$entry", *definition[1:]])
        if [t for _, t in function["params"]] != ["i64"] or function["result"] != "i64":
            raise ValueError("prototype continuations require i64 -> i64")

    def resume(self, args):
        self.continuation_type(args[0])
        handlers = [arg for arg in args[1:] if arg[0] == "on"]
        operands = [self.emit(arg) for arg in args[1:] if arg[0] != "on"]
        if [t for t, _ in operands] != ["i64", "i64"]:
            raise ValueError("resume requires one i64 argument and a continuation")
        mask = sum(1 << self.module.tags[tag] for tag in {h[1] for h in handlers})
        token, tag, payload = self.continuation_event(
            operands[1][1], operands[0][1], mask
        )
        done, suspended = self.fresh("done"), self.fresh("suspended")
        finished = self.value("i1", f"icmp eq i64 {token}, 0")
        self.finish(f"br i1 {finished}, label %{done}, label %{suspended}")
        self.label(suspended)
        self.resume_handlers(handlers, tag, payload, token)
        self.label(done)
        return "i64", payload

    def continuation_event(self, token, argument, mask):
        # C Event: null token means normal return; otherwise tag/payload suspend.
        type = "{ i64, i32, i64 }"
        event = self.value("ptr", f"alloca {type}, align 8")
        self.line(
            f"call void @native_cont_resume(i64 {token}, i64 {argument}, i64 {mask}, ptr {event})"
        )
        result = self.value(type, f"load {type}, ptr {event}, align 8")
        return tuple(
            self.value(t, f"extractvalue {type} {result}, {i}")
            for i, t in enumerate(("i64", "i32", "i64"))
        )

    def resume_handlers(self, handlers, tag, payload, token):
        for _, handled_tag, label in handlers:
            if label == "switch":
                raise ValueError("switch handlers are outside the prototype")
            matches = self.value(
                "i1", f"icmp eq i32 {tag}, {self.module.tags[handled_tag]}"
            )
            yes, no = self.fresh("handler"), self.fresh("handler")
            self.finish(f"br i1 {matches}, label %{yes}, label %{no}")
            self.label(yes)
            self.branch(
                self.target(label), self.tuple([("i64", payload), ("i64", token)])
            )
            self.label(no)
        self.trap()  # Runtime must only return tags selected by this resume.

    # ---- GC references and fixed structs ----

    def reference_test(self, target, value):
        nullable = isinstance(target, list) and "null" in target
        target = target[-1] if isinstance(target, list) else target
        low = self.value("i64", f"and i64 {value}, 1")
        odd = self.value("i1", f"icmp ne i64 {low}, 0")
        if target == "i31":
            condition = odd
        elif target in self.module.structs:
            nonzero = self.value("i1", f"icmp ne i64 {value}, 0")
            even = self.value("i1", f"xor i1 {odd}, true")
            pointer = self.value("i1", f"and i1 {nonzero}, {even}")
            yes, no, join = [self.fresh("b") for _ in range(3)]
            self.finish(f"br i1 {pointer}, label %{yes}, label %{no}")
            self.label(yes)
            address = self.value("ptr", f"inttoptr i64 {value} to ptr")
            kind = self.value("i32", f"load i32, ptr {address}, align 8")
            match = self.value(
                "i1", f"icmp eq i32 {kind}, {self.module.structs[target][0]}"
            )
            yes_end = self.block
            self.finish(f"br label %{join}")
            self.label(no)
            self.finish(f"br label %{join}")
            self.label(join)
            condition = self.value(
                "i1", f"phi i1 [{match}, %{yes_end}], [false, %{no}]"
            )
        else:
            raise ValueError(f"unsupported heap type: {target}")
        if nullable:
            null = self.value("i1", f"icmp eq i64 {value}, 0")
            condition = self.value("i1", f"or i1 {condition}, {null}")
        return condition

    def new_struct(self, name, operands):
        kind, fields = self.module.structs[name]
        values = [self.emit(arg) for arg in operands]
        if [value[0] for value in values] != fields:
            raise ValueError("struct field types mismatch")
        pointer = self.value("ptr", f"call ptr @GC_malloc(i64 {8 + 8 * len(fields)})")
        self.guard(self.value("i1", f"icmp ne ptr {pointer}, null"))
        self.line(f"store i32 {kind}, ptr {pointer}, align 8")
        for index, (type, value) in enumerate(values):
            slot = self.value(
                "ptr", f"getelementptr i8, ptr {pointer}, i64 {8 + 8 * index}"
            )
            self.line(f"store {type} {value}, ptr {slot}, align 8")
        return "i64", self.value("i64", f"ptrtoint ptr {pointer} to i64")

    def struct_slot(self, name, index, object):
        self.guard(self.value("i1", f"icmp ne i64 {object}, 0"))
        pointer = self.value("ptr", f"inttoptr i64 {object} to ptr")
        return self.module.structs[name][1][index], self.value(
            "ptr", f"getelementptr i8, ptr {pointer}, i64 {8 + 8 * index}"
        )

    # ---- Numeric instructions ----

    def binary(self, op, args):
        type, operation = op.split(".", 1)
        type = llvm_type(type)
        left, right = [self.emit(arg) for arg in args]
        if left[0] != type or right[0] != type:
            raise ValueError(f"operand types mismatch: {op}")
        a, b = left[1], right[1]
        compares = {
            "eq": "eq",
            "ne": "ne",
            "lt_s": "slt",
            "lt_u": "ult",
            "le_s": "sle",
            "le_u": "ule",
            "gt_s": "sgt",
            "gt_u": "ugt",
            "ge_s": "sge",
            "ge_u": "uge",
        }
        if type == "double":
            compare = {
                "eq": "oeq",
                "ne": "une",
                "lt": "olt",
                "le": "ole",
                "gt": "ogt",
                "ge": "oge",
            }
            if operation in compare:
                return self.boolean(
                    self.value("i1", f"fcmp {compare[operation]} double {a}, {b}")
                )
            if operation not in ("add", "sub", "mul", "div"):
                raise ValueError(f"unsupported numeric op {op}")
            return type, self.value(type, f"f{operation} double {a}, {b}")
        if operation in compares:
            return self.boolean(
                self.value("i1", f"icmp {compares[operation]} {type} {a}, {b}")
            )
        native = {
            "add": "add",
            "sub": "sub",
            "mul": "mul",
            "and": "and",
            "or": "or",
            "xor": "xor",
            "shl": "shl",
            "shr_s": "ashr",
            "shr_u": "lshr",
        }
        if operation not in native:
            raise ValueError(f"unsupported numeric op {op}")
        if operation in ("shl", "shr_s", "shr_u"):
            b = self.value(type, f"and {type} {b}, {31 if type == 'i32' else 63}")
        return type, self.value(type, f"{native[operation]} {type} {a}, {b}")

    def conversion(self, op, arg):
        source, value = self.emit(arg)
        conversions = {
            "i64.extend_i32_s": ("i64", "sext"),
            "i64.extend_i32_u": ("i64", "zext"),
            "i32.wrap_i64": ("i32", "trunc"),
            "f64.convert_i64_s": ("double", "sitofp"),
            "f64.convert_i32_s": ("double", "sitofp"),
            "f64.convert_i32_u": ("double", "uitofp"),
        }
        if op in conversions:
            type, instruction = conversions[op]
            return type, self.value(type, f"{instruction} {source} {value} to {type}")
        if op == "i64.trunc_f64_s":
            low = self.value("i1", f"fcmp oge double {value}, 0xC3E0000000000000")
            high = self.value("i1", f"fcmp olt double {value}, 0x43E0000000000000")
            self.guard(self.value("i1", f"and i1 {low}, {high}"))
            return "i64", self.value("i64", f"fptosi double {value} to i64")
        raise ValueError(f"unsupported conversion: {op}")

    # ---- Expression dispatch ----

    def emit(self, node):
        op, *args = node
        if op == "if":
            return self.structured_if(args)
        if op == "block":
            return self.structured_block(args)
        if op == "br":
            values = [self.emit(arg) for arg in args[1:]]
            self.branch(
                self.target(args[0]),
                self.tuple(values)
                if len(values) > 1
                else values[0]
                if values
                else None,
            )
            return None
        if op == "tuple.make":
            return self.tuple([self.emit(arg) for arg in args])
        if op == "tuple.extract":
            type, value = self.emit(args[2])
            field_type = type[2:-2].split(", ")[int(args[1])]
            return field_type, self.value(
                field_type, f"extractvalue {type} {value}, {args[1]}"
            )
        if op == "ref.func":
            function = self.module.functions[args[0]]
            if [t for _, t in function["params"]] != ["i64"] or function[
                "result"
            ] != "i64":
                raise ValueError("prototype function references require i64 -> i64")
            self.module.continuation_entries.add(args[0])
            return "i64", f"ptrtoint (ptr @{named('cont_entry_', args[0])} to i64)"
        if op == "cont.new":
            self.continuation_type(args[0])
            _, entry = self.emit(args[1])
            return "i64", self.value("i64", f"call i64 @native_cont_new(i64 {entry})")
        if op == "resume":
            return self.resume(args)
        if op == "suspend":
            _, payload = self.emit(args[1])
            return "i64", self.value(
                "i64",
                f"call i64 @native_cont_suspend(i32 {self.module.tags[args[0]]}, i64 {payload})",
            )
        if op == "unreachable":
            self.trap()
            return None
        if op == "nop":
            return None
        if op == "drop":
            self.emit(args[0])
            return None
        if op == "return":
            value = self.emit(args[0]) if args else None
            self.finish(f"ret {value[0]} {value[1]}" if value else "ret void")
            return None
        if op == "local.get":
            type, pointer = self.locals[args[0]]
            return type, self.value(type, f"load {type}, ptr {pointer}, align 8")
        if op in ("local.set", "local.tee"):
            type, pointer = self.locals[args[0]]
            value = self.emit(args[1])
            if value[0] != type:
                raise ValueError("local store type mismatch")
            self.line(f"store {type} {value[1]}, ptr {pointer}, align 8")
            return value if op == "local.tee" else None
        if op == "global.get":
            type, _ = self.module.globals[args[0]]
            return type, self.value(
                type, f"load {type}, ptr @{named('global_', args[0])}, align 8"
            )
        if op == "global.set":
            type, _ = self.module.globals[args[0]]
            value = self.emit(args[1])
            self.line(
                f"store {type} {value[1]}, ptr @{named('global_', args[0])}, align 8"
            )
            return None
        if op in ("call", "return_call"):
            imported = args[0] in self.module.imports
            callee = (self.module.imports if imported else self.module.functions)[
                args[0]
            ]
            operands = [self.emit(arg) for arg in args[1:]]
            if [value[0] for value in operands] != [
                type for _, type in callee["params"]
            ]:
                raise ValueError("call signature mismatch")
            type = callee["result"]
            symbol = callee["symbol"] if imported else named("fn_", args[0])
            instruction = "call" if op == "call" else "musttail call"
            if op == "return_call" and (
                imported
                or [t for _, t in callee["params"]]
                != [t for _, t in self.signature["params"]]
                or callee["result"] != self.signature["result"]
            ):
                raise ValueError(
                    "prototype musttail requires matching internal signatures"
                )
            call = (
                f"{instruction} {'' if imported else 'fastcc '}{type} @{symbol}("
                + ", ".join(f"{t} {v}" for t, v in operands)
                + ")"
            )
            result = (type, self.value(type, call)) if type != "void" else None
            if type == "void":
                self.line(call)
            if op == "return_call":
                self.finish(f"ret {type} {result[1]}" if result else "ret void")
                return None
            return result
        if op.endswith(".const"):
            type = llvm_type(op.split(".")[0])
            if type == "double":
                value = (
                    float.fromhex(args[0])
                    if "0x" in args[0].lower()
                    else float(args[0])
                )
                return type, "0x" + struct.pack(">d", value).hex().upper()
            return type, str(int(args[0], 0))
        if op == "ref.null":
            return "i64", "0"
        if op == "ref.i31":
            _, value = self.emit(args[0])
            shift = self.value("i32", f"shl i32 {value}, 1")
            tagged = self.value("i32", f"or i32 {shift}, 1")
            return "i64", self.value("i64", f"sext i32 {tagged} to i64")
        if op in ("i31.get_s", "i31.get_u"):
            _, value = self.emit(args[0])
            self.guard(self.value("i1", f"icmp ne i64 {value}, 0"))
            tagged = self.value("i32", f"trunc i64 {value} to i32")
            instruction = "ashr" if op.endswith("_s") else "lshr"
            return "i32", self.value("i32", f"{instruction} i32 {tagged}, 1")
        if op in ("ref.test", "ref.cast"):
            _, value = self.emit(args[1])
            condition = self.reference_test(args[0], value)
            if op == "ref.test":
                return self.boolean(condition)
            self.guard(condition)
            return "i64", value
        if op == "ref.eq":
            left, right = [self.emit(arg)[1] for arg in args]
            return self.boolean(self.value("i1", f"icmp eq i64 {left}, {right}"))
        if op == "ref.is_null":
            _, value = self.emit(args[0])
            return self.boolean(self.value("i1", f"icmp eq i64 {value}, 0"))
        if op == "struct.new":
            return self.new_struct(args[0], args[1:])
        if op in ("struct.get", "struct.set"):
            object = self.emit(args[2])[1]
            index = int(args[1])
            # Wasm evaluates both operands before the store's null trap.
            value = self.emit(args[3]) if op == "struct.set" else None
            type, pointer = self.struct_slot(args[0], index, object)
            if op == "struct.get":
                return type, self.value(type, f"load {type}, ptr {pointer}, align 8")
            self.line(f"store {type} {value[1]}, ptr {pointer}, align 8")
            return None
        if op in ("i32.eqz", "i64.eqz"):
            type, value = self.emit(args[0])
            return self.boolean(self.value("i1", f"icmp eq {type} {value}, 0"))
        if op.startswith(("i32.", "i64.", "f64.")):
            return (
                self.binary(op, args)
                if len(args) == 2
                else self.conversion(op, args[0])
            )
        raise ValueError(f"unsupported instruction: {op}")


# ---- Module emission ----


def definition(module, signature):
    emitter = Function(module, signature)
    result = emitter.sequence(signature["body"])
    if emitter.block is not None:
        if signature["result"] == "void":
            emitter.finish("ret void")
        elif result and result[0] == signature["result"]:
            emitter.finish(f"ret {result[0]} {result[1]}")
        else:
            raise ValueError("function result mismatch")
    params = ", ".join(
        f"{type} %arg{i}" for i, (_, type) in enumerate(signature["params"])
    )
    return (
        f"define internal fastcc {signature['result']} @{named('fn_', signature['name'])}({params}) {{\n"
        + "\n".join(emitter.lines)
        + "\n}"
    )


def emit_module(module):
    out = [
        'target triple = "x86_64-unknown-linux-gnu"',
        "declare void @GC_init()",
        "declare void @GC_set_all_interior_pointers(i32)",
        "declare noalias ptr @GC_malloc(i64)",
        "declare void @llvm.trap() cold noreturn nounwind",
    ]
    if module.continuations:
        out.extend(
            [
                "declare i64 @native_cont_new(i64)",
                "declare void @native_cont_resume(i64, i64, i64, ptr)",
                "declare i64 @native_cont_suspend(i32, i64)",
            ]
        )
    for function in module.imports.values():
        out.append(
            f"declare {function['result']} @{function['symbol']}("
            + ", ".join(t for _, t in function["params"])
            + ")"
        )
    for name, (type, _) in module.globals.items():
        out.append(
            f"@{named('global_', name)} = internal global {type} "
            + ("0.0" if type == "double" else "0")
            + ", align 8"
        )
    initializer = {
        "name": "init",
        "params": [],
        "locals": [],
        "result": "void",
        "body": [],
    }
    init = Function(module, initializer)
    # LLVM may retain an interior field pointer across an allocating operand.
    # BDWGC must recognize it as a root for its enclosing fixed-layout object.
    init.line("call void @GC_set_all_interior_pointers(i32 1)")
    init.line("call void @GC_init()")
    for name, (type, node) in module.globals.items():
        value = init.emit(node)
        init.line(f"store {type} {value[1]}, ptr @{named('global_', name)}, align 8")
    init.finish("ret void")
    out.append("define void @wasm_init() {\n" + "\n".join(init.lines) + "\n}")
    out.extend(definition(module, function) for function in module.functions.values())
    for name in sorted(module.continuation_entries):
        out.append(
            f"define internal i64 @{named('cont_entry_', name)}(i64 %input) {{\nentry:\n  %result = call fastcc i64 @{named('fn_', name)}(i64 %input)\n  ret i64 %result\n}}"
        )
    for export, target in module.exports:
        if target[0] == "func":
            function = module.functions[target[1]]
            type = function["result"]
            params = ", ".join(
                f"{t} %arg{i}" for i, (_, t) in enumerate(function["params"])
            )
            call = f"call fastcc {type} @{named('fn_', target[1])}({params})"
            body = (
                f"  %result = {call}\n  ret {type} %result"
                if type != "void"
                else f"  {call}\n  ret void"
            )
            out.append(
                f"define {type} @{named('wasm_export_', export)}({params}) {{\nentry:\n{body}\n}}"
            )
        elif target[0] == "global":
            type = module.globals[target[1]][0]
            out.append(
                f"define {type} @{named('wasm_global_', export)}() {{\nentry:\n  %value = load {type}, ptr @{named('global_', target[1])}\n  ret {type} %value\n}}"
            )
        elif target[0] != "memory":
            raise ValueError("unsupported export")
    return "\n\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()
    source = Path(args.input)
    if source.read_bytes()[:4] != b"\0asm":
        raise ValueError("translator input must be an actual Wasm binary")
    wat = subprocess.check_output(
        [os.environ.get("WASM_DIS", shutil.which("wasm-dis") or BINARYEN), str(source)],
        text=True,
    )
    Path(args.output).write_text(emit_module(Module(parse(wat))))


if __name__ == "__main__":
    main()
