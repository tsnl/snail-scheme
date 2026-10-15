define internal tailcc i64 @f.87(i64 %arg0, i64 %arg1) {
entry:
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %slot10 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [1 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 1)
  %v1 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg0, ptr %v1, align 1
  store i64 %arg1, ptr %slot2, align 1
  store i64 0, ptr %slot3, align 1
  store i64 0, ptr %slot4, align 1
  %v7 = load i64, ptr %slot2, align 1
  %v8 = icmp sle i64 %v7, 0
  %v9 = zext i1 %v8 to i32
  %v14 = icmp ne i32 %v9, 0
  br i1 %v14, label %then13, label %else12
then13:
  %v15 = load i32, ptr @g.78, align 1
  %v16 = icmp eq i32 %v15, 0
  %v17 = zext i1 %v16 to i32
  %v21 = icmp ne i32 %v17, 0
  br i1 %v21, label %then20, label %else19
then20:
  call void @native_trap()
  unreachable
else19:
  br label %block18
block18:
  %v22 = load i32, ptr @g.77, align 1
  %v23 = icmp ne i32 %v22, 0
  %v24 = zext i1 %v23 to i32
  %v25 = zext i32 %v24 to i64
  store i64 %v25, ptr %slot10, align 1
  br label %block11
else12:
  %v26 = load i32, ptr @g.74, align 1
  %v27 = icmp eq i32 %v26, 0
  %v28 = zext i1 %v27 to i32
  %v32 = icmp ne i32 %v28, 0
  br i1 %v32, label %then31, label %else30
then31:
  call void @native_trap()
  unreachable
else30:
  br label %block29
block29:
  %v33 = load i32, ptr @g.33, align 1
  %v34 = icmp eq i32 %v33, 0
  %v35 = zext i1 %v34 to i32
  %v39 = icmp ne i32 %v35, 0
  br i1 %v39, label %then38, label %else37
then38:
  call void @native_trap()
  unreachable
else37:
  br label %block36
block36:
  %v40 = load i64, ptr @g.32, align 1
  %v41 = icmp ne i64 %v40, 0
  br i1 %v41, label %ok43, label %trap42
trap42:
  call void @native_trap()
  unreachable
ok43:
  %v44 = inttoptr i64 %v40 to ptr
  %v45 = getelementptr i64, ptr %v44, i64 2
  %v46 = load i64, ptr %v45, align 1
  %v47 = load i64, ptr @g.73, align 1
  %v48 = getelementptr i64, ptr %roots, i64 2
  store i64 1, ptr %v48, align 1
  %v49 = call tailcc i64 @f.2(i64 %v47)
  store i64 %v49, ptr %slot3, align 1
  %v50 = load i32, ptr @g.76, align 1
  %v51 = icmp eq i32 %v50, 0
  %v52 = zext i1 %v51 to i32
  %v56 = icmp ne i32 %v52, 0
  br i1 %v56, label %then55, label %else54
then55:
  call void @native_trap()
  unreachable
else54:
  br label %block53
block53:
  %v57 = load i32, ptr @g.33, align 1
  %v58 = icmp eq i32 %v57, 0
  %v59 = zext i1 %v58 to i32
  %v63 = icmp ne i32 %v59, 0
  br i1 %v63, label %then62, label %else61
then62:
  call void @native_trap()
  unreachable
else61:
  br label %block60
block60:
  %v64 = load i64, ptr @g.32, align 1
  %v65 = icmp ne i64 %v64, 0
  br i1 %v65, label %ok67, label %trap66
trap66:
  call void @native_trap()
  unreachable
ok67:
  %v68 = inttoptr i64 %v64 to ptr
  %v69 = getelementptr i64, ptr %v68, i64 2
  %v70 = load i64, ptr %v69, align 1
  %v71 = load i64, ptr @g.75, align 1
  %v72 = getelementptr i64, ptr %roots, i64 2
  store i64 1, ptr %v72, align 1
  %v73 = call tailcc i64 @f.2(i64 %v71)
  store i64 %v73, ptr %slot4, align 1
  %v74 = load i32, ptr @g.70, align 1
  %v75 = icmp eq i32 %v74, 0
  %v76 = zext i1 %v75 to i32
  %v80 = icmp ne i32 %v76, 0
  br i1 %v80, label %then79, label %else78
then79:
  call void @native_trap()
  unreachable
else78:
  br label %block77
block77:
  %v81 = load i64, ptr @g.69, align 1
  %v82 = icmp ne i64 %v81, 0
  br i1 %v82, label %ok84, label %trap83
trap83:
  call void @native_trap()
  unreachable
ok84:
  %v85 = load i64, ptr %slot2, align 1
  %v86 = load i64, ptr %slot3, align 1
  %v87 = load i64, ptr %slot4, align 1
  %v88 = getelementptr i64, ptr %roots, i64 2
  store i64 1, ptr %v88, align 1
  %v89 = call tailcc i64 @f.69(i64 %v86, i64 %v87)
  call void @native_roots_leave(ptr %roots)
  %v90 = tail call tailcc i64 @f.89(i64 %v85, i32 0, i32 1, i64 1, i64 %v89)
  ret i64 %v90
block11:
  %v91 = load i64, ptr %slot10, align 1
  store i64 %v91, ptr %slot5, align 1
  br label %return6
return6:
  %v92 = load i64, ptr %slot5, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v92
}
