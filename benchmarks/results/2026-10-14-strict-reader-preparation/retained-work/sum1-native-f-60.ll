define internal tailcc double @f.60(i64 %arg0, double %arg1) {
entry:
  %slot2 = alloca double, align 8
  %slot5 = alloca i32, align 8
  %slot6 = alloca double, align 8
  %slot8 = alloca double, align 8
  %slot29 = alloca i32, align 8
  %slot52 = alloca double, align 8
  %slot62 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [5 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 5)
  %v1 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg0, ptr %v1, align 1
  store double %arg1, ptr %slot2, align 1
  %v3 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v3, align 1
  %v4 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v4, align 1
  store i32 0, ptr %slot5, align 1
  store double 0.0, ptr %slot6, align 1
  %v7 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v7, align 1
  %v10 = load i64, ptr @g.29, align 1
  %v11 = icmp ne i64 %v10, 0
  br i1 %v11, label %ok13, label %trap12
trap12:
  call void @native_trap()
  unreachable
ok13:
  %v14 = load i64, ptr %v1, align 1
  %v15 = getelementptr i64, ptr %roots, i64 7
  store i64 %v14, ptr %v15, align 1
  %v16 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v16, align 1
  %v17 = call tailcc i64 @f.58(i64 %v14)
  store i64 %v17, ptr %v3, align 1
  %v18 = load i64, ptr @g.83, align 1
  %v19 = icmp ne i64 %v18, 0
  br i1 %v19, label %ok21, label %trap20
trap20:
  call void @native_trap()
  unreachable
ok21:
  %v22 = load i64, ptr %v3, align 1
  %v23 = icmp ne i64 %v22, 0
  br i1 %v23, label %ok25, label %trap24
trap24:
  call void @native_trap()
  unreachable
ok25:
  %v26 = inttoptr i64 %v22 to ptr
  %v27 = getelementptr i64, ptr %v26, i64 1
  %v28 = load i32, ptr %v27, align 1
  store i32 %v28, ptr %slot5, align 1
  %v33 = icmp ne i32 %v28, 0
  br i1 %v33, label %then32, label %else31
then32:
  %v34 = load i32, ptr %slot5, align 1
  %v35 = icmp eq i32 %v34, 1
  %v36 = zext i1 %v35 to i32
  %v40 = icmp ne i32 %v36, 0
  br i1 %v40, label %then39, label %else38
then39:
  %v41 = load i64, ptr %v3, align 1
  %v42 = call i32 @native_ref_test(i64 %v41, i64 218, i32 0, i32 0)
  %v43 = icmp ne i32 %v42, 0
  br i1 %v43, label %ok45, label %trap44
trap44:
  call void @native_trap()
  unreachable
ok45:
  br label %block37
else38:
  %v46 = load i64, ptr %v3, align 1
  %v47 = call i32 @native_ref_test(i64 %v46, i64 214, i32 0, i32 0)
  %v48 = icmp ne i32 %v47, 0
  br i1 %v48, label %ok50, label %trap49
trap49:
  call void @native_trap()
  unreachable
ok50:
  br label %block37
block37:
  store i32 0, ptr %slot29, align 1
  br label %block30
else31:
  store i32 1, ptr %slot29, align 1
  br label %block30
block30:
  %v51 = load i32, ptr %slot29, align 1
  %v56 = icmp ne i32 %v51, 0
  br i1 %v56, label %then55, label %else54
then55:
  %v57 = load double, ptr %slot2, align 1
  store double %v57, ptr %slot52, align 1
  br label %block53
else54:
  %v58 = load i64, ptr @g.24, align 1
  %v59 = icmp ne i64 %v58, 0
  br i1 %v59, label %ok61, label %trap60
trap60:
  call void @native_trap()
  unreachable
ok61:
  %v64 = load i64, ptr %v3, align 1
  %v65 = getelementptr i64, ptr %roots, i64 7
  store i64 %v64, ptr %v65, align 1
  %v66 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v66, align 1
  %v67 = call tailcc i64 @f.34(i64 %v64)
  store i64 %v67, ptr %v7, align 1
  %v68 = load i64, ptr @g.35, align 1
  %v69 = icmp ne i64 %v68, 0
  br i1 %v69, label %ok71, label %trap70
trap70:
  call void @native_trap()
  unreachable
ok71:
  %v72 = load i64, ptr %v7, align 1
  store i64 %v72, ptr %slot62, align 1
  br label %block63
block63:
  %v73 = load i64, ptr %slot62, align 1
  %v74 = getelementptr i64, ptr %roots, i64 7
  store i64 %v73, ptr %v74, align 1
  %v75 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v75, align 1
  %v76 = call tailcc double @f.59(i64 %v73)
  store double %v76, ptr %slot6, align 1
  %v77 = load i32, ptr @g.130, align 1
  %v78 = icmp eq i32 %v77, 0
  %v79 = zext i1 %v78 to i32
  %v83 = icmp ne i32 %v79, 0
  br i1 %v83, label %then82, label %else81
then82:
  call void @native_trap()
  unreachable
else81:
  br label %block80
block80:
  %v84 = load i64, ptr @g.68, align 1
  %v85 = icmp ne i64 %v84, 0
  br i1 %v85, label %ok87, label %trap86
trap86:
  call void @native_trap()
  unreachable
ok87:
  %v88 = load i64, ptr %v1, align 1
  %v89 = load double, ptr %slot6, align 1
  %v90 = load double, ptr %slot2, align 1
  %v91 = fadd double %v89, %v90
  call void @native_roots_leave(ptr %roots)
  %v92 = tail call tailcc double @f.60(i64 %v88, double %v91)
  ret double %v92
block53:
  %v93 = load double, ptr %slot52, align 1
  store double %v93, ptr %slot8, align 1
  br label %return9
return9:
  %v94 = load double, ptr %slot8, align 1
  call void @native_roots_leave(ptr %roots)
  ret double %v94
}
