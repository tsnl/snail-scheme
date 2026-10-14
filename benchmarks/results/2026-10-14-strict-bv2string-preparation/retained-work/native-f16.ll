define internal tailcc i64 @f.16(i64 %arg0) {
entry:
  %slot2 = alloca i64, align 8
  %slot3 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [4 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 4)
  %v1 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg0, ptr %v1, align 1
  store i64 0, ptr %slot2, align 1
  store i64 0, ptr %slot3, align 1
  %v4 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v4, align 1
  %v7 = load i32, ptr @g.40, align 1
  %v8 = icmp eq i32 %v7, 0
  %v9 = zext i1 %v8 to i32
  %v13 = icmp ne i32 %v9, 0
  br i1 %v13, label %then12, label %else11
then12:
  call void @native_trap()
  unreachable
else11:
  br label %block10
block10:
  %v14 = load i64, ptr @g.39, align 1
  %v15 = icmp ne i64 %v14, 0
  br i1 %v15, label %ok17, label %trap16
trap16:
  call void @native_trap()
  unreachable
ok17:
  %v18 = load i32, ptr @g.10, align 1
  %v19 = icmp eq i32 %v18, 0
  %v20 = zext i1 %v19 to i32
  %v24 = icmp ne i32 %v20, 0
  br i1 %v24, label %then23, label %else22
then23:
  call void @native_trap()
  unreachable
else22:
  br label %block21
block21:
  %v25 = load i64, ptr @g.9, align 1
  %v26 = icmp ne i64 %v25, 0
  br i1 %v26, label %ok28, label %trap27
trap27:
  call void @native_trap()
  unreachable
ok28:
  %v29 = load i64, ptr %v1, align 1
  %v30 = icmp ne i64 %v29, 0
  br i1 %v30, label %ok32, label %trap31
trap31:
  call void @native_trap()
  unreachable
ok32:
  %v33 = inttoptr i64 %v29 to ptr
  %v34 = getelementptr i64, ptr %v33, i64 2
  %v35 = load i32, ptr %v34, align 1
  %v36 = zext i32 %v35 to i64
  store i64 %v36, ptr %slot2, align 1
  %v37 = load i64, ptr %slot2, align 1
  %v38 = icmp sgt i64 %v36, %v37
  %v39 = zext i1 %v38 to i32
  %v43 = icmp ne i32 %v39, 0
  br i1 %v43, label %then42, label %else41
then42:
  call void @native_trap()
  unreachable
else41:
  br label %block40
block40:
  %v44 = load i32, ptr @g.34, align 1
  %v45 = icmp eq i32 %v44, 0
  %v46 = zext i1 %v45 to i32
  %v50 = icmp ne i32 %v46, 0
  br i1 %v50, label %then49, label %else48
then49:
  call void @native_trap()
  unreachable
else48:
  br label %block47
block47:
  %v51 = load i64, ptr @g.33, align 1
  %v52 = icmp ne i64 %v51, 0
  br i1 %v52, label %ok54, label %trap53
trap53:
  call void @native_trap()
  unreachable
ok54:
  %v55 = load i64, ptr %v1, align 1
  %v56 = load i64, ptr %slot2, align 1
  %v57 = getelementptr i64, ptr %roots, i64 5
  store i64 %v55, ptr %v57, align 1
  %v58 = getelementptr i64, ptr %roots, i64 2
  store i64 3, ptr %v58, align 1
  %v59 = call tailcc i64 @f.13(i64 %v55, i64 %v56, i32 0, i32 1, i64 0, i64 0)
  store i64 %v59, ptr %slot3, align 1
  %v60 = load i32, ptr @g.8, align 1
  %v61 = icmp eq i32 %v60, 0
  %v62 = zext i1 %v61 to i32
  %v66 = icmp ne i32 %v62, 0
  br i1 %v66, label %then65, label %else64
then65:
  call void @native_trap()
  unreachable
else64:
  br label %block63
block63:
  %v67 = load i64, ptr @g.7, align 1
  %v68 = icmp ne i64 %v67, 0
  br i1 %v68, label %ok70, label %trap69
trap69:
  call void @native_trap()
  unreachable
ok70:
  %v71 = load i64, ptr %slot3, align 1
  %v72 = icmp ugt i64 %v71, 4294967295
  %v73 = zext i1 %v72 to i32
  %v77 = icmp ne i32 %v73, 0
  br i1 %v77, label %then76, label %else75
then76:
  call void @native_trap()
  unreachable
else75:
  br label %block74
block74:
  %v78 = load i32, ptr @g.38, align 1
  %v79 = icmp eq i32 %v78, 0
  %v80 = zext i1 %v79 to i32
  %v84 = icmp ne i32 %v80, 0
  br i1 %v84, label %then83, label %else82
then83:
  call void @native_trap()
  unreachable
else82:
  br label %block81
block81:
  %v85 = load i64, ptr @g.37, align 1
  %v86 = icmp ne i64 %v85, 0
  br i1 %v86, label %ok88, label %trap87
trap87:
  call void @native_trap()
  unreachable
ok88:
  %v89 = load i64, ptr %slot3, align 1
  %v90 = trunc i64 %v89 to i32
  %v91 = getelementptr i64, ptr %roots, i64 2
  store i64 2, ptr %v91, align 1
  %v92 = zext i32 0 to i64
  %v93 = call i64 @native_array_new(i64 87, i32 %v90, i64 %v92)
  %v94 = getelementptr i64, ptr %roots, i64 5
  store i64 %v93, ptr %v94, align 1
  %v95 = getelementptr i64, ptr %roots, i64 2
  store i64 3, ptr %v95, align 1
  %v96 = call i64 @native_alloc(i64 16)
  %v97 = icmp ne i64 %v96, 0
  br i1 %v97, label %ok99, label %trap98
trap98:
  call void @native_trap()
  unreachable
ok99:
  %v100 = inttoptr i64 %v96 to ptr
  %v101 = getelementptr i64, ptr %v100, i64 0
  store i64 94, ptr %v101, align 1
  %v102 = icmp ne i64 %v96, 0
  br i1 %v102, label %ok104, label %trap103
trap103:
  call void @native_trap()
  unreachable
ok104:
  %v105 = inttoptr i64 %v96 to ptr
  %v106 = getelementptr i64, ptr %v105, i64 1
  store i64 %v93, ptr %v106, align 1
  store i64 %v96, ptr %v4, align 1
  %v107 = load i64, ptr %v1, align 1
  %v108 = load i64, ptr %slot2, align 1
  %v109 = getelementptr i64, ptr %roots, i64 5
  store i64 %v96, ptr %v109, align 1
  %v110 = getelementptr i64, ptr %roots, i64 6
  store i64 %v107, ptr %v110, align 1
  %v111 = getelementptr i64, ptr %roots, i64 2
  store i64 4, ptr %v111, align 1
  %v112 = call tailcc i32 @f.15(i64 %v96, i64 %v107, i64 %v108, i32 0, i32 1, i64 0, i64 0)
  %v113 = load i64, ptr %v4, align 1
  store i64 %v113, ptr %slot5, align 1
  br label %return6
return6:
  %v114 = load i64, ptr %slot5, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v114
}
