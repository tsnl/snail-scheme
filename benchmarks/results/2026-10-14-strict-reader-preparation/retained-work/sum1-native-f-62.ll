define internal tailcc i64 @f.62(i64 %arg0) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [0 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 0)
  store i64 %arg0, ptr %slot1, align 1
  %v4 = load i32, ptr @g.22, align 1
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
  %v11 = load i32, ptr @g.140, align 1
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
  %v18 = load i64, ptr @g.139, align 1
  %v19 = icmp ne i64 %v18, 0
  br i1 %v19, label %ok21, label %trap20
trap20:
  call void @native_trap()
  unreachable
ok21:
  %v22 = load i64, ptr %slot1, align 1
  %v23 = getelementptr i64, ptr %roots, i64 2
  store i64 0, ptr %v23, align 1
  %v24 = call i64 @native_alloc(i64 16)
  %v25 = icmp ne i64 %v24, 0
  br i1 %v25, label %ok27, label %trap26
trap26:
  call void @native_trap()
  unreachable
ok27:
  %v28 = inttoptr i64 %v24 to ptr
  %v29 = getelementptr i64, ptr %v28, i64 0
  store i64 254, ptr %v29, align 1
  %v30 = icmp ne i64 %v24, 0
  br i1 %v30, label %ok32, label %trap31
trap31:
  call void @native_trap()
  unreachable
ok32:
  %v33 = inttoptr i64 %v24 to ptr
  %v34 = getelementptr i64, ptr %v33, i64 1
  store i32 1, ptr %v34, align 1
  call void @native_roots_leave(ptr %roots)
  %v35 = tail call tailcc i64 @f.61(i64 %v22, i32 0, i32 1, i64 0, i64 %v24)
  ret i64 %v35
}
