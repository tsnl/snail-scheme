define internal tailcc i64 @f.92(i64 %arg0) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [0 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 0)
  store i64 %arg0, ptr %slot1, align 1
  %v4 = load i32, ptr @g.34, align 1
  %v5 = icmp ne i32 %v4, 2
  %v6 = zext i1 %v5 to i32
  %v10 = icmp ne i32 %v6, 0
  br i1 %v10, label %then9, label %else8
then9:
  call void @native_trap()
  unreachable
else8:
  br label %block7
block7:
  %v11 = load i32, ptr @g.146, align 1
  %v12 = icmp eq i32 %v11, 0
  %v13 = zext i1 %v12 to i32
  %v17 = icmp ne i32 %v13, 0
  br i1 %v17, label %then16, label %else15
then16:
  call void @native_trap()
  unreachable
else15:
  br label %block14
block14:
  %v18 = load i64, ptr @g.145, align 1
  %v19 = icmp ne i64 %v18, 0
  br i1 %v19, label %ok21, label %trap20
trap20:
  call void @native_trap()
  unreachable
ok21:
  %v22 = inttoptr i64 %v18 to ptr
  %v23 = getelementptr i64, ptr %v22, i64 2
  %v24 = load i64, ptr %v23, align 1
  %v25 = load i64, ptr %slot1, align 1
  call void @native_roots_leave(ptr %roots)
  %v26 = tail call tailcc i64 @f.87(i64 %v24, i64 %v25)
  ret i64 %v26
}
