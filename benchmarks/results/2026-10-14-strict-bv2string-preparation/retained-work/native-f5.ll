define internal tailcc i64 @f.5(i64 %arg0, i64 %arg1) {
entry:
  %slot2 = alloca i64, align 8
  %slot3 = alloca i32, align 8
  %slot4 = alloca i32, align 8
  %slot5 = alloca i32, align 8
  %slot6 = alloca i32, align 8
  %slot7 = alloca i32, align 8
  %slot8 = alloca i64, align 8
  %slot11 = alloca i64, align 8
  %slot36 = alloca i32, align 8
  %roots = alloca { ptr, i64, i64, [5 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 5)
  %v1 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg0, ptr %v1, align 1
  store i64 %arg1, ptr %slot2, align 1
  store i32 0, ptr %slot3, align 1
  store i32 0, ptr %slot4, align 1
  store i32 0, ptr %slot5, align 1
  store i32 0, ptr %slot6, align 1
  store i32 0, ptr %slot7, align 1
  store i64 0, ptr %slot8, align 1
  %v9 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v9, align 1
  %v10 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v10, align 1
  %v13 = load i32, ptr @g.10, align 1
  %v14 = icmp eq i32 %v13, 0
  %v15 = zext i1 %v14 to i32
  %v19 = icmp ne i32 %v15, 0
  br i1 %v19, label %then18, label %else17
then18:
  call void @native_trap()
  unreachable
else17:
  br label %block16
block16:
  %v20 = load i64, ptr @g.9, align 1
  %v21 = icmp ne i64 %v20, 0
  br i1 %v21, label %ok23, label %trap22
trap22:
  call void @native_trap()
  unreachable
ok23:
  %v24 = load i64, ptr %v1, align 1
  %v25 = icmp ne i64 %v24, 0
  br i1 %v25, label %ok27, label %trap26
trap26:
  call void @native_trap()
  unreachable
ok27:
  %v28 = inttoptr i64 %v24 to ptr
  %v29 = getelementptr i64, ptr %v28, i64 1
  %v30 = load i64, ptr %v29, align 1
  %v31 = call i32 @native_array_length(i64 %v30)
  %v32 = zext i32 %v31 to i64
  store i64 %v32, ptr %slot8, align 1
  %v33 = load i64, ptr %slot2, align 1
  %v34 = icmp slt i64 %v33, 0
  %v35 = zext i1 %v34 to i32
  store i32 %v35, ptr %slot3, align 1
  %v40 = icmp ne i32 %v35, 0
  br i1 %v40, label %then39, label %else38
then39:
  %v41 = load i32, ptr %slot3, align 1
  store i32 %v41, ptr %slot36, align 1
  br label %block37
else38:
  %v42 = load i64, ptr %slot2, align 1
  %v43 = load i64, ptr %slot8, align 1
  %v44 = icmp sgt i64 %v42, %v43
  %v45 = zext i1 %v44 to i32
  store i32 %v45, ptr %slot36, align 1
  br label %block37
block37:
  %v46 = load i32, ptr %slot36, align 1
  %v50 = icmp ne i32 %v46, 0
  br i1 %v50, label %then49, label %else48
then49:
  call void @native_trap()
  unreachable
else48:
  br label %block47
block47:
  %v51 = load i32, ptr @g.24, align 1
  %v52 = icmp eq i32 %v51, 0
  %v53 = zext i1 %v52 to i32
  %v57 = icmp ne i32 %v53, 0
  br i1 %v57, label %then56, label %else55
then56:
  call void @native_trap()
  unreachable
else55:
  br label %block54
block54:
  %v58 = load i64, ptr @g.23, align 1
  %v59 = icmp ne i64 %v58, 0
  br i1 %v59, label %ok61, label %trap60
trap60:
  call void @native_trap()
  unreachable
ok61:
  %v62 = load i64, ptr %v1, align 1
  %v63 = load i64, ptr %slot2, align 1
  %v64 = getelementptr i64, ptr %roots, i64 6
  store i64 %v62, ptr %v64, align 1
  %v65 = getelementptr i64, ptr %roots, i64 2
  store i64 4, ptr %v65, align 1
  %v66 = call tailcc i64 @f.6(i64 %v62, i64 %v63, i32 0, i32 1, i64 0, i64 0)
  store i64 %v66, ptr %slot8, align 1
  %v67 = load i32, ptr @g.4, align 1
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
  %v74 = load i64, ptr @g.3, align 1
  %v75 = icmp ne i64 %v74, 0
  br i1 %v75, label %ok77, label %trap76
trap76:
  call void @native_trap()
  unreachable
ok77:
  %v78 = load i64, ptr %slot8, align 1
  %v79 = icmp ugt i64 %v78, 4294967294
  %v80 = zext i1 %v79 to i32
  %v84 = icmp ne i32 %v80, 0
  br i1 %v84, label %then83, label %else82
then83:
  call void @native_trap()
  unreachable
else82:
  br label %block81
block81:
  %v85 = load i64, ptr %slot8, align 1
  %v86 = trunc i64 %v85 to i32
  store i32 %v86, ptr %slot3, align 1
  %v87 = load i32, ptr %slot3, align 1
  %v88 = load i32, ptr %slot3, align 1
  %v89 = icmp uge i32 %v88, 8192
  %v90 = zext i1 %v89 to i32
  %v91 = icmp ne i32 %v90, 0
  %v92 = select i1 %v91, i32 8192, i32 %v87
  store i32 %v92, ptr %slot6, align 1
  %v93 = sub i32 %v86, %v92
  store i32 %v93, ptr %slot4, align 1
  %v97 = icmp ne i32 %v93, 0
  br i1 %v97, label %then96, label %else95
then96:
  %v98 = load i32, ptr %slot3, align 1
  %v99 = sub i32 %v98, 1
  %v100 = and i32 13, 31
  %v101 = lshr i32 %v99, %v100
  %v102 = getelementptr i64, ptr %roots, i64 2
  store i64 3, ptr %v102, align 1
  %v103 = call i64 @native_array_new(i64 107, i32 %v101, i64 0)
  store i64 %v103, ptr %v9, align 1
  br label %loop105
loop105:
  %v106 = load i64, ptr %v9, align 1
  %v107 = load i32, ptr %slot5, align 1
  %v108 = load i32, ptr %slot4, align 1
  %v109 = load i32, ptr %slot4, align 1
  %v110 = icmp uge i32 %v109, 8192
  %v111 = zext i1 %v110 to i32
  %v112 = icmp ne i32 %v111, 0
  %v113 = select i1 %v112, i32 8192, i32 %v108
  store i32 %v113, ptr %slot7, align 1
  %v114 = getelementptr i64, ptr %roots, i64 6
  store i64 %v106, ptr %v114, align 1
  %v115 = getelementptr i64, ptr %roots, i64 2
  store i64 4, ptr %v115, align 1
  %v116 = zext i32 0 to i64
  %v117 = call i64 @native_array_new(i64 219, i32 %v113, i64 %v116)
  %v118 = call ptr @native_array_slot(i64 %v106, i32 %v107)
  store i64 %v117, ptr %v118, align 1
  %v119 = load i32, ptr %slot5, align 1
  %v120 = add i32 %v119, 1
  store i32 %v120, ptr %slot5, align 1
  %v121 = load i32, ptr %slot4, align 1
  %v122 = load i32, ptr %slot7, align 1
  %v123 = sub i32 %v121, %v122
  store i32 %v123, ptr %slot4, align 1
  %v124 = icmp ne i32 %v123, 0
  br i1 %v124, label %loop105, label %next125
next125:
  br label %block104
block104:
  br label %block94
else95:
  br label %block94
block94:
  %v126 = load i32, ptr @g.26, align 1
  %v127 = icmp eq i32 %v126, 0
  %v128 = zext i1 %v127 to i32
  %v132 = icmp ne i32 %v128, 0
  br i1 %v132, label %then131, label %else130
then131:
  call void @native_trap()
  unreachable
else130:
  br label %block129
block129:
  %v133 = load i64, ptr @g.25, align 1
  %v134 = icmp ne i64 %v133, 0
  br i1 %v134, label %ok136, label %trap135
trap135:
  call void @native_trap()
  unreachable
ok136:
  %v137 = load i32, ptr %slot3, align 1
  %v138 = load i32, ptr %slot6, align 1
  %v139 = getelementptr i64, ptr %roots, i64 2
  store i64 3, ptr %v139, align 1
  %v140 = zext i32 0 to i64
  %v141 = call i64 @native_array_new(i64 219, i32 %v138, i64 %v140)
  %v142 = load i64, ptr %v9, align 1
  %v143 = getelementptr i64, ptr %roots, i64 6
  store i64 %v142, ptr %v143, align 1
  %v144 = getelementptr i64, ptr %roots, i64 7
  store i64 %v141, ptr %v144, align 1
  %v145 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v145, align 1
  %v146 = call i64 @native_alloc(i64 40)
  %v147 = icmp ne i64 %v146, 0
  br i1 %v147, label %ok149, label %trap148
trap148:
  call void @native_trap()
  unreachable
ok149:
  %v150 = inttoptr i64 %v146 to ptr
  %v151 = getelementptr i64, ptr %v150, i64 0
  store i64 214, ptr %v151, align 1
  %v152 = icmp ne i64 %v146, 0
  br i1 %v152, label %ok154, label %trap153
trap153:
  call void @native_trap()
  unreachable
ok154:
  %v155 = inttoptr i64 %v146 to ptr
  %v156 = getelementptr i64, ptr %v155, i64 1
  store i32 1, ptr %v156, align 1
  %v157 = icmp ne i64 %v146, 0
  br i1 %v157, label %ok159, label %trap158
trap158:
  call void @native_trap()
  unreachable
ok159:
  %v160 = inttoptr i64 %v146 to ptr
  %v161 = getelementptr i64, ptr %v160, i64 2
  store i32 %v137, ptr %v161, align 1
  %v162 = icmp ne i64 %v146, 0
  br i1 %v162, label %ok164, label %trap163
trap163:
  call void @native_trap()
  unreachable
ok164:
  %v165 = inttoptr i64 %v146 to ptr
  %v166 = getelementptr i64, ptr %v165, i64 3
  store i64 %v141, ptr %v166, align 1
  %v167 = icmp ne i64 %v146, 0
  br i1 %v167, label %ok169, label %trap168
trap168:
  call void @native_trap()
  unreachable
ok169:
  %v170 = inttoptr i64 %v146 to ptr
  %v171 = getelementptr i64, ptr %v170, i64 4
  store i64 %v142, ptr %v171, align 1
  store i64 %v146, ptr %v10, align 1
  %v172 = load i64, ptr %v1, align 1
  %v173 = load i64, ptr %slot2, align 1
  %v174 = getelementptr i64, ptr %roots, i64 6
  store i64 %v146, ptr %v174, align 1
  %v175 = getelementptr i64, ptr %roots, i64 7
  store i64 %v172, ptr %v175, align 1
  %v176 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v176, align 1
  %v177 = call tailcc i32 @f.11(i64 %v146, i64 %v172, i64 %v173, i32 0, i32 1, i64 0, i64 0)
  %v178 = load i64, ptr %v10, align 1
  store i64 %v178, ptr %slot11, align 1
  br label %return12
return12:
  %v179 = load i64, ptr %slot11, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v179
}
