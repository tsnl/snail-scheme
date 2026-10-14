define internal tailcc void @f.3(i32 %arg0) {
entry:
  %roots = alloca { ptr, i64, i64, [0 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 0)
  %v1 = getelementptr i64, ptr %roots, i64 2
  store i64 0, ptr %v1, align 1
  call void @"snail:io/close"(i32 %arg0)
  call void @native_roots_leave(ptr %roots)
  ret void
}
