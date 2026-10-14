define internal tailcc i32 @f.4(i64 %arg0, i64 %arg1, i32 %arg2, i32 %arg3, i64 %arg4) {
entry:
  %slot3 = alloca i32, align 8
  %slot4 = alloca i32, align 8
  %slot5 = alloca i64, align 8
  %slot6 = alloca i32, align 8
  %slot7 = alloca i32, align 8
  %slot20 = alloca i32, align 8
  %slot60 = alloca i64, align 8
  %slot97 = alloca i64, align 8
  %slot132 = alloca i32, align 8
  %roots = alloca { ptr, i64, i64, [2 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 0)
  %v1 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg0, ptr %v1, align 1
  %v2 = getelementptr i64, ptr %roots, i64 4
  store i64 %arg1, ptr %v2, align 1
  store i32 %arg2, ptr %slot3, align 1
  store i32 %arg3, ptr %slot4, align 1
  store i64 %arg4, ptr %slot5, align 1
  store i32 0, ptr %slot6, align 1
  %v9 = load i64, ptr %v1, align 1
  %v10 = icmp ne i64 %v9, 0
  br i1 %v10, label %ok12, label %trap11
trap11:
  call void @native_trap()
  unreachable
ok12:
  %v13 = inttoptr i64 %v9 to ptr
  %v14 = getelementptr i64, ptr %v13, i64 2
  %v15 = load i32, ptr %v14, align 1
  %v16 = zext i32 %v15 to i64
  %v17 = load i64, ptr %slot5, align 1
  %v18 = icmp eq i64 %v16, %v17
  %v19 = zext i1 %v18 to i32
  store i32 %v19, ptr %slot6, align 1
  %v24 = icmp ne i32 %v19, 0
  br i1 %v24, label %then23, label %else22
then23:
  %v25 = load i32, ptr %slot6, align 1
  store i32 %v25, ptr %slot20, align 1
  br label %block21
else22:
  %v26 = load i64, ptr %slot5, align 1
  %v27 = load i64, ptr %v1, align 1
  %v28 = icmp ne i64 %v27, 0
  br i1 %v28, label %ok30, label %trap29
trap29:
  call void @native_trap()
  unreachable
ok30:
  %v31 = inttoptr i64 %v27 to ptr
  %v32 = getelementptr i64, ptr %v31, i64 2
  %v33 = load i32, ptr %v32, align 1
  %v34 = zext i32 %v33 to i64
  %v35 = icmp uge i64 %v26, %v34
  %v36 = zext i1 %v35 to i32
  %v40 = icmp ne i32 %v36, 0
  br i1 %v40, label %then39, label %else38
then39:
  call void @native_trap()
  unreachable
else38:
  br label %block37
block37:
  %v41 = load i64, ptr %slot5, align 1
  %v42 = load i64, ptr %v2, align 1
  %v43 = icmp ne i64 %v42, 0
  br i1 %v43, label %ok45, label %trap44
trap44:
  call void @native_trap()
  unreachable
ok45:
  %v46 = inttoptr i64 %v42 to ptr
  %v47 = getelementptr i64, ptr %v46, i64 2
  %v48 = load i32, ptr %v47, align 1
  %v49 = zext i32 %v48 to i64
  %v50 = icmp uge i64 %v41, %v49
  %v51 = zext i1 %v50 to i32
  %v55 = icmp ne i32 %v51, 0
  br i1 %v55, label %then54, label %else53
then54:
  call void @native_trap()
  unreachable
else53:
  br label %block52
block52:
  %v56 = load i64, ptr %slot5, align 1
  %v57 = trunc i64 %v56 to i32
  store i32 %v57, ptr %slot6, align 1
  %v58 = icmp ult i32 %v57, 8192
  %v59 = zext i1 %v58 to i32
  %v64 = icmp ne i32 %v59, 0
  br i1 %v64, label %then63, label %else62
then63:
  %v65 = load i64, ptr %v2, align 1
  %v66 = icmp ne i64 %v65, 0
  br i1 %v66, label %ok68, label %trap67
trap67:
  call void @native_trap()
  unreachable
ok68:
  %v69 = inttoptr i64 %v65 to ptr
  %v70 = getelementptr i64, ptr %v69, i64 3
  %v71 = load i64, ptr %v70, align 1
  store i64 %v71, ptr %slot60, align 1
  br label %block61
else62:
  %v72 = load i64, ptr %v2, align 1
  %v73 = icmp ne i64 %v72, 0
  br i1 %v73, label %ok75, label %trap74
trap74:
  call void @native_trap()
  unreachable
ok75:
  %v76 = inttoptr i64 %v72 to ptr
  %v77 = getelementptr i64, ptr %v76, i64 4
  %v78 = load i64, ptr %v77, align 1
  %v79 = load i32, ptr %slot6, align 1
  %v80 = and i32 13, 31
  %v81 = lshr i32 %v79, %v80
  %v82 = sub i32 %v81, 1
  %v83 = call ptr @native_array_slot(i64 %v78, i32 %v82)
  %v84 = load i64, ptr %v83, align 1
  %v85 = icmp ne i64 %v84, 0
  br i1 %v85, label %ok87, label %trap86
trap86:
  call void @native_trap()
  unreachable
ok87:
  store i64 %v84, ptr %slot60, align 1
  br label %block61
block61:
  %v88 = load i64, ptr %slot60, align 1
  %v89 = load i32, ptr %slot6, align 1
  %v90 = and i32 %v89, 8191
  %v91 = call ptr @native_array_slot(i64 %v88, i32 %v90)
  %v92 = load i32, ptr %v91, align 1
  %v93 = load i64, ptr %slot5, align 1
  %v94 = trunc i64 %v93 to i32
  store i32 %v94, ptr %slot6, align 1
  %v95 = icmp ult i32 %v94, 8192
  %v96 = zext i1 %v95 to i32
  %v101 = icmp ne i32 %v96, 0
  br i1 %v101, label %then100, label %else99
then100:
  %v102 = load i64, ptr %v1, align 1
  %v103 = icmp ne i64 %v102, 0
  br i1 %v103, label %ok105, label %trap104
trap104:
  call void @native_trap()
  unreachable
ok105:
  %v106 = inttoptr i64 %v102 to ptr
  %v107 = getelementptr i64, ptr %v106, i64 3
  %v108 = load i64, ptr %v107, align 1
  store i64 %v108, ptr %slot97, align 1
  br label %block98
else99:
  %v109 = load i64, ptr %v1, align 1
  %v110 = icmp ne i64 %v109, 0
  br i1 %v110, label %ok112, label %trap111
trap111:
  call void @native_trap()
  unreachable
ok112:
  %v113 = inttoptr i64 %v109 to ptr
  %v114 = getelementptr i64, ptr %v113, i64 4
  %v115 = load i64, ptr %v114, align 1
  %v116 = load i32, ptr %slot6, align 1
  %v117 = and i32 13, 31
  %v118 = lshr i32 %v116, %v117
  %v119 = sub i32 %v118, 1
  %v120 = call ptr @native_array_slot(i64 %v115, i32 %v119)
  %v121 = load i64, ptr %v120, align 1
  %v122 = icmp ne i64 %v121, 0
  br i1 %v122, label %ok124, label %trap123
trap123:
  call void @native_trap()
  unreachable
ok124:
  store i64 %v121, ptr %slot97, align 1
  br label %block98
block98:
  %v125 = load i64, ptr %slot97, align 1
  %v126 = load i32, ptr %slot6, align 1
  %v127 = and i32 %v126, 8191
  %v128 = call ptr @native_array_slot(i64 %v125, i32 %v127)
  %v129 = load i32, ptr %v128, align 1
  %v130 = icmp eq i32 %v92, %v129
  %v131 = zext i1 %v130 to i32
  %v136 = icmp ne i32 %v131, 0
  br i1 %v136, label %then135, label %else134
then135:
  %v137 = load i32, ptr %slot4, align 1
  %v138 = icmp eq i32 %v137, 0
  %v139 = zext i1 %v138 to i32
  %v143 = icmp ne i32 %v139, 0
  br i1 %v143, label %then142, label %else141
then142:
  call void @native_trap()
  unreachable
else141:
  br label %block140
block140:
  %v144 = load i64, ptr %v1, align 1
  %v145 = load i64, ptr %v2, align 1
  %v146 = load i32, ptr %slot3, align 1
  %v147 = load i32, ptr %slot4, align 1
  %v148 = load i64, ptr %slot5, align 1
  %v149 = add i64 %v148, 1
  call void @native_roots_leave(ptr %roots)
  %v150 = tail call tailcc i32 @f.4(i64 %v144, i64 %v145, i32 %v146, i32 %v147, i64 %v149)
  ret i32 %v150
else134:
  store i32 0, ptr %slot132, align 1
  br label %block133
block133:
  %v151 = load i32, ptr %slot132, align 1
  store i32 %v151, ptr %slot20, align 1
  br label %block21
block21:
  %v152 = load i32, ptr %slot20, align 1
  store i32 %v152, ptr %slot7, align 1
  br label %return8
return8:
  %v153 = load i32, ptr %slot7, align 1
  call void @native_roots_leave(ptr %roots)
  ret i32 %v153
}
