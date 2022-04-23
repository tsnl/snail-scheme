# `ss-stdlib` = Snail-Scheme Standard Library

This is a single (and our first) extension library for Snail-Scheme.

Every extension library must expose a single `SsrtReq_exportAll` function with the same signature as LLVM IR.

This ensures we can compile 