# `ss-rtlib` = Snail-Scheme Run-time Library

This is a single C++ source file that can be statically linked at the IR level against generated Scheme LLVM IR.
This enables link-time optimizations like forced inlining, which we would not get with object-level linking.

This library is just a thin C-level wrapper around the C++ `snail-scheme` library.
