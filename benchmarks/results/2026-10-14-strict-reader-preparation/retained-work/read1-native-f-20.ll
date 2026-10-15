define internal tailcc i32 @f.20() {
entry:
  %roots = alloca { ptr, i64, i64, [0 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 0)
  %v1 = getelementptr i64, ptr %roots, i64 2
  store i64 0, ptr %v1, align 1
  %v2 = call i32 @"barrier"()
  call void @native_roots_leave(ptr %roots)
  ret i32 %v2
}
