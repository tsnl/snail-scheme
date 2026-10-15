define internal tailcc i64 @f.89(i64 %arg0, i32 %arg1, i32 %arg2, i64 %arg3, i64 %arg4) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i32, align 8
  %slot3 = alloca i32, align 8
  %slot4 = alloca i64, align 8
  %slot6 = alloca i64, align 8
  %slot7 = alloca i64, align 8
  %slot8 = alloca i64, align 8
  %slot14 = alloca i64, align 8
  %slot43 = alloca i64, align 8
  %slot106 = alloca i32, align 8
  %roots = alloca { ptr, i64, i64, [3 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 3)
  store i64 %arg0, ptr %slot1, align 1
  store i32 %arg1, ptr %slot2, align 1
  store i32 %arg2, ptr %slot3, align 1
  store i64 %arg3, ptr %slot4, align 1
  %v5 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg4, ptr %v5, align 1
  store i64 0, ptr %slot6, align 1
  store i64 0, ptr %slot7, align 1
  %v10 = load i64, ptr %slot1, align 1
  %v11 = load i64, ptr %slot4, align 1
  %v12 = icmp sgt i64 %v10, %v11
  %v13 = zext i1 %v12 to i32
  %v18 = icmp ne i32 %v13, 0
  br i1 %v18, label %then17, label %else16
then17:
  %v19 = load i32, ptr @g.74, align 1
  %v20 = icmp eq i32 %v19, 0
  %v21 = zext i1 %v20 to i32
  %v25 = icmp ne i32 %v21, 0
  br i1 %v25, label %then24, label %else23
then24:
  call void @native_trap()
  unreachable
else23:
  br label %block22
block22:
  %v26 = load i32, ptr @g.33, align 1
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
  %v33 = load i64, ptr @g.32, align 1
  %v34 = icmp ne i64 %v33, 0
  br i1 %v34, label %ok36, label %trap35
trap35:
  call void @native_trap()
  unreachable
ok36:
  %v37 = inttoptr i64 %v33 to ptr
  %v38 = getelementptr i64, ptr %v37, i64 2
  %v39 = load i64, ptr %v38, align 1
  %v40 = load i64, ptr @g.73, align 1
  %v41 = getelementptr i64, ptr %roots, i64 2
  store i64 1, ptr %v41, align 1
  %v42 = call tailcc i64 @f.2(i64 %v40)
  %v45 = load i32, ptr @g.76, align 1
  %v46 = icmp eq i32 %v45, 0
  %v47 = zext i1 %v46 to i32
  %v51 = icmp ne i32 %v47, 0
  br i1 %v51, label %then50, label %else49
then50:
  call void @native_trap()
  unreachable
else49:
  br label %block48
block48:
  %v52 = load i32, ptr @g.33, align 1
  %v53 = icmp eq i32 %v52, 0
  %v54 = zext i1 %v53 to i32
  %v58 = icmp ne i32 %v54, 0
  br i1 %v58, label %then57, label %else56
then57:
  call void @native_trap()
  unreachable
else56:
  br label %block55
block55:
  %v59 = load i64, ptr @g.32, align 1
  %v60 = icmp ne i64 %v59, 0
  br i1 %v60, label %ok62, label %trap61
trap61:
  call void @native_trap()
  unreachable
ok62:
  %v63 = inttoptr i64 %v59 to ptr
  %v64 = getelementptr i64, ptr %v63, i64 2
  %v65 = load i64, ptr %v64, align 1
  %v66 = load i64, ptr @g.75, align 1
  %v67 = getelementptr i64, ptr %roots, i64 2
  store i64 1, ptr %v67, align 1
  %v68 = call tailcc i64 @f.2(i64 %v66)
  store i64 %v68, ptr %slot7, align 1
  %v69 = load i32, ptr @g.70, align 1
  %v70 = icmp eq i32 %v69, 0
  %v71 = zext i1 %v70 to i32
  %v75 = icmp ne i32 %v71, 0
  br i1 %v75, label %then74, label %else73
then74:
  call void @native_trap()
  unreachable
else73:
  br label %block72
block72:
  %v76 = load i64, ptr @g.69, align 1
  %v77 = icmp ne i64 %v76, 0
  br i1 %v77, label %ok79, label %trap78
trap78:
  call void @native_trap()
  unreachable
ok79:
  %v80 = load i64, ptr %slot7, align 1
  store i64 %v80, ptr %slot43, align 1
  br label %block44
block44:
  %v81 = load i64, ptr %slot43, align 1
  %v82 = getelementptr i64, ptr %roots, i64 2
  store i64 1, ptr %v82, align 1
  %v83 = call tailcc i64 @f.69(i64 %v42, i64 %v81)
  store i64 %v83, ptr %v5, align 1
  %v84 = load i32, ptr %slot3, align 1
  %v85 = icmp eq i32 %v84, 0
  %v86 = zext i1 %v85 to i32
  %v90 = icmp ne i32 %v86, 0
  br i1 %v90, label %then89, label %else88
then89:
  call void @native_trap()
  unreachable
else88:
  br label %block87
block87:
  %v91 = load i64, ptr %slot1, align 1
  %v92 = load i32, ptr %slot2, align 1
  %v93 = load i32, ptr %slot3, align 1
  %v94 = load i64, ptr %slot4, align 1
  %v95 = add i64 %v94, 1
  %v96 = load i64, ptr %v5, align 1
  call void @native_roots_leave(ptr %roots)
  %v97 = tail call tailcc i64 @f.89(i64 %v91, i32 %v92, i32 %v93, i64 %v95, i64 %v96)
  ret i64 %v97
else16:
  %v98 = load i32, ptr @g.78, align 1
  %v99 = icmp eq i32 %v98, 0
  %v100 = zext i1 %v99 to i32
  %v104 = icmp ne i32 %v100, 0
  br i1 %v104, label %then103, label %else102
then103:
  call void @native_trap()
  unreachable
else102:
  br label %block101
block101:
  %v105 = load i32, ptr @g.77, align 1
  %v110 = icmp ne i32 %v105, 0
  br i1 %v110, label %then109, label %else108
then109:
  store i32 0, ptr %slot106, align 1
  br label %block107
else108:
  %v111 = load i32, ptr @g.144, align 1
  %v112 = icmp eq i32 %v111, 0
  %v113 = zext i1 %v112 to i32
  %v117 = icmp ne i32 %v113, 0
  br i1 %v117, label %then116, label %else115
then116:
  call void @native_trap()
  unreachable
else115:
  br label %block114
block114:
  %v118 = load i32, ptr @g.62, align 1
  %v119 = icmp eq i32 %v118, 0
  %v120 = zext i1 %v119 to i32
  %v124 = icmp ne i32 %v120, 0
  br i1 %v124, label %then123, label %else122
then123:
  call void @native_trap()
  unreachable
else122:
  br label %block121
block121:
  %v125 = load i64, ptr @g.61, align 1
  %v126 = icmp ne i64 %v125, 0
  br i1 %v126, label %ok128, label %trap127
trap127:
  call void @native_trap()
  unreachable
ok128:
  %v129 = load i64, ptr %v5, align 1
  %v130 = load i64, ptr @g.143, align 1
  %v131 = getelementptr i64, ptr %roots, i64 4
  store i64 %v129, ptr %v131, align 1
  %v132 = getelementptr i64, ptr %roots, i64 5
  store i64 %v130, ptr %v132, align 1
  %v133 = getelementptr i64, ptr %roots, i64 2
  store i64 3, ptr %v133, align 1
  %v134 = call tailcc i32 @f.13(i64 %v129, i64 %v130)
  store i32 %v134, ptr %slot106, align 1
  br label %block107
block107:
  %v135 = load i32, ptr %slot106, align 1
  %v136 = icmp ne i32 %v135, 0
  %v137 = zext i1 %v136 to i32
  %v138 = zext i32 %v137 to i64
  store i64 %v138, ptr %slot14, align 1
  br label %block15
block15:
  %v139 = load i64, ptr %slot14, align 1
  store i64 %v139, ptr %slot8, align 1
  br label %return9
return9:
  %v140 = load i64, ptr %slot8, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v140
}
