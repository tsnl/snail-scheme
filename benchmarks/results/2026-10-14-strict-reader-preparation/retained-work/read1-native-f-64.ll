define internal tailcc i64 @f.64(i64 %arg0, i32 %arg1, i32 %arg2, i64 %arg3, i64 %arg4, i64 %arg5) {
entry:
  %slot2 = alloca i32, align 8
  %slot3 = alloca i32, align 8
  %slot6 = alloca i64, align 8
  %slot7 = alloca i32, align 8
  %slot9 = alloca i64, align 8
  %slot22 = alloca i32, align 8
  %slot45 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [5 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 5)
  %v1 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg0, ptr %v1, align 1
  store i32 %arg1, ptr %slot2, align 1
  store i32 %arg2, ptr %slot3, align 1
  %v4 = getelementptr i64, ptr %roots, i64 4
  store i64 %arg3, ptr %v4, align 1
  %v5 = getelementptr i64, ptr %roots, i64 5
  store i64 %arg4, ptr %v5, align 1
  store i64 %arg5, ptr %slot6, align 1
  store i32 0, ptr %slot7, align 1
  %v8 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v8, align 1
  %v11 = load i64, ptr @g.49, align 1
  %v12 = icmp ne i64 %v11, 0
  br i1 %v12, label %ok14, label %trap13
trap13:
  call void @native_trap()
  unreachable
ok14:
  %v15 = load i64, ptr %v4, align 1
  %v16 = icmp ne i64 %v15, 0
  br i1 %v16, label %ok18, label %trap17
trap17:
  call void @native_trap()
  unreachable
ok18:
  %v19 = inttoptr i64 %v15 to ptr
  %v20 = getelementptr i64, ptr %v19, i64 1
  %v21 = load i32, ptr %v20, align 1
  store i32 %v21, ptr %slot7, align 1
  %v26 = icmp ne i32 %v21, 0
  br i1 %v26, label %then25, label %else24
then25:
  %v27 = load i32, ptr %slot7, align 1
  %v28 = icmp eq i32 %v27, 1
  %v29 = zext i1 %v28 to i32
  %v33 = icmp ne i32 %v29, 0
  br i1 %v33, label %then32, label %else31
then32:
  %v34 = load i64, ptr %v4, align 1
  %v35 = call i32 @native_ref_test(i64 %v34, i64 202, i32 0, i32 0)
  %v36 = icmp ne i32 %v35, 0
  br i1 %v36, label %ok38, label %trap37
trap37:
  call void @native_trap()
  unreachable
ok38:
  br label %block30
else31:
  %v39 = load i64, ptr %v4, align 1
  %v40 = call i32 @native_ref_test(i64 %v39, i64 198, i32 0, i32 0)
  %v41 = icmp ne i32 %v40, 0
  br i1 %v41, label %ok43, label %trap42
trap42:
  call void @native_trap()
  unreachable
ok43:
  br label %block30
block30:
  store i32 0, ptr %slot22, align 1
  br label %block23
else24:
  store i32 1, ptr %slot22, align 1
  br label %block23
block23:
  %v44 = load i32, ptr %slot22, align 1
  %v49 = icmp ne i32 %v44, 0
  br i1 %v49, label %then48, label %else47
then48:
  %v50 = load i64, ptr %v5, align 1
  store i64 %v50, ptr %slot45, align 1
  br label %block46
else47:
  %v51 = load i64, ptr @g.19, align 1
  %v52 = icmp ne i64 %v51, 0
  br i1 %v52, label %ok54, label %trap53
trap53:
  call void @native_trap()
  unreachable
ok54:
  %v55 = load i64, ptr %v1, align 1
  %v56 = getelementptr i64, ptr %roots, i64 7
  store i64 %v55, ptr %v56, align 1
  %v57 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v57, align 1
  %v58 = call tailcc i64 @f.63(i64 %v55)
  store i64 %v58, ptr %v8, align 1
  %v59 = load i64, ptr @g.21, align 1
  %v60 = icmp ne i64 %v59, 0
  br i1 %v60, label %ok62, label %trap61
trap61:
  call void @native_trap()
  unreachable
ok62:
  %v63 = load i64, ptr %v4, align 1
  %v64 = getelementptr i64, ptr %roots, i64 7
  store i64 %v63, ptr %v64, align 1
  %v65 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v65, align 1
  %v66 = call tailcc i64 @f.39(i64 %v63)
  store i64 %v66, ptr %v5, align 1
  %v67 = load i32, ptr %slot3, align 1
  %v68 = icmp eq i32 %v67, 0
  %v69 = zext i1 %v68 to i32
  %v73 = icmp ne i32 %v69, 0
  br i1 %v73, label %then72, label %else71
then72:
  call void @native_trap()
  unreachable
else71:
  br label %block70
block70:
  %v74 = load i64, ptr %v1, align 1
  %v75 = load i32, ptr %slot2, align 1
  %v76 = load i32, ptr %slot3, align 1
  %v77 = load i64, ptr %v8, align 1
  %v78 = load i64, ptr %v5, align 1
  %v79 = load i64, ptr %slot6, align 1
  %v80 = add i64 %v79, 1
  call void @native_roots_leave(ptr %roots)
  %v81 = tail call tailcc i64 @f.64(i64 %v74, i32 %v75, i32 %v76, i64 %v77, i64 %v78, i64 %v80)
  ret i64 %v81
block46:
  %v82 = load i64, ptr %slot45, align 1
  store i64 %v82, ptr %slot9, align 1
  br label %return10
return10:
  %v83 = load i64, ptr %slot9, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v83
}
