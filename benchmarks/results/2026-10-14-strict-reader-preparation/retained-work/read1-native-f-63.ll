define internal tailcc i64 @f.63(i64 %arg0) {
entry:
  %slot6 = alloca i64, align 8
  %slot52 = alloca i64, align 8
  %slot61 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [8 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 8)
  %v1 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg0, ptr %v1, align 1
  %v2 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v2, align 1
  %v3 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v3, align 1
  %v4 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v4, align 1
  %v5 = getelementptr i64, ptr %roots, i64 7
  store i64 0, ptr %v5, align 1
  %v8 = load i64, ptr @g.27, align 1
  %v9 = icmp ne i64 %v8, 0
  br i1 %v9, label %ok11, label %trap10
trap10:
  call void @native_trap()
  unreachable
ok11:
  %v12 = load i32, ptr @g.22, align 1
  %v13 = icmp eq i32 %v12, 0
  %v14 = zext i1 %v13 to i32
  %v18 = icmp ne i32 %v14, 0
  br i1 %v18, label %then17, label %else16
then17:
  call void @native_trap()
  unreachable
else16:
  br label %block15
block15:
  %v19 = load i64, ptr @g.14, align 1
  %v20 = icmp ne i64 %v19, 0
  br i1 %v20, label %ok22, label %trap21
trap21:
  call void @native_trap()
  unreachable
ok22:
  %v23 = load i64, ptr %v1, align 1
  %v24 = getelementptr i64, ptr %roots, i64 8
  store i64 %v23, ptr %v24, align 1
  %v25 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v25, align 1
  %v26 = call tailcc i64 @f.40(i64 %v23)
  store i64 %v26, ptr %v3, align 1
  %v27 = load i32, ptr @g.30, align 1
  %v28 = icmp eq i32 %v27, 0
  %v29 = zext i1 %v28 to i32
  %v33 = icmp ne i32 %v29, 0
  br i1 %v33, label %then32, label %else31
then32:
  call void @native_trap()
  unreachable
else31:
  br label %block30
block30:
  %v34 = load i64, ptr @g.23, align 1
  %v35 = icmp ne i64 %v34, 0
  br i1 %v35, label %ok37, label %trap36
trap36:
  call void @native_trap()
  unreachable
ok37:
  %v38 = load i64, ptr %v1, align 1
  %v39 = load i64, ptr %v3, align 1
  %v40 = getelementptr i64, ptr %roots, i64 8
  store i64 %v38, ptr %v40, align 1
  %v41 = getelementptr i64, ptr %roots, i64 9
  store i64 %v39, ptr %v41, align 1
  %v42 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v42, align 1
  %v43 = call tailcc i64 @f.55(i64 %v38, i64 %v39)
  store i64 %v43, ptr %v2, align 1
  %v44 = icmp ne i64 %v43, 0
  br i1 %v44, label %ok46, label %trap45
trap45:
  call void @native_trap()
  unreachable
ok46:
  %v47 = inttoptr i64 %v43 to ptr
  %v48 = getelementptr i64, ptr %v47, i64 1
  %v49 = load i32, ptr %v48, align 1
  %v50 = icmp eq i32 %v49, 2
  %v51 = zext i1 %v50 to i32
  %v56 = icmp ne i32 %v51, 0
  br i1 %v56, label %then55, label %else54
then55:
  %v57 = load i64, ptr @g.31, align 1
  %v58 = icmp ne i64 %v57, 0
  br i1 %v58, label %ok60, label %trap59
trap59:
  call void @native_trap()
  unreachable
ok60:
  %v63 = load i64, ptr @g.70, align 1
  %v64 = load i64, ptr %v2, align 1
  %v65 = call i32 @native_ref_test(i64 %v64, i64 198, i32 0, i32 0)
  %v66 = icmp ne i32 %v65, 0
  br i1 %v66, label %ok68, label %trap67
trap67:
  call void @native_trap()
  unreachable
ok68:
  %v69 = icmp ne i64 %v64, 0
  br i1 %v69, label %ok71, label %trap70
trap70:
  call void @native_trap()
  unreachable
ok71:
  %v72 = inttoptr i64 %v64 to ptr
  %v73 = getelementptr i64, ptr %v72, i64 2
  %v74 = load i64, ptr %v73, align 1
  %v75 = getelementptr i64, ptr %roots, i64 8
  store i64 0, ptr %v75, align 1
  %v76 = getelementptr i64, ptr %roots, i64 9
  store i64 %v74, ptr %v76, align 1
  %v77 = getelementptr i64, ptr %roots, i64 10
  store i64 %v63, ptr %v77, align 1
  %v78 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v78, align 1
  %v79 = call i64 @native_alloc(i64 24)
  %v80 = icmp ne i64 %v79, 0
  br i1 %v80, label %ok82, label %trap81
trap81:
  call void @native_trap()
  unreachable
ok82:
  %v83 = inttoptr i64 %v79 to ptr
  %v84 = getelementptr i64, ptr %v83, i64 0
  store i64 346, ptr %v84, align 1
  %v85 = icmp ne i64 %v79, 0
  br i1 %v85, label %ok87, label %trap86
trap86:
  call void @native_trap()
  unreachable
ok87:
  %v88 = inttoptr i64 %v79 to ptr
  %v89 = getelementptr i64, ptr %v88, i64 1
  store i64 %v74, ptr %v89, align 1
  %v90 = icmp ne i64 %v79, 0
  br i1 %v90, label %ok92, label %trap91
trap91:
  call void @native_trap()
  unreachable
ok92:
  %v93 = inttoptr i64 %v79 to ptr
  %v94 = getelementptr i64, ptr %v93, i64 2
  store i64 0, ptr %v94, align 1
  %v95 = getelementptr i64, ptr %roots, i64 8
  store i64 %v79, ptr %v95, align 1
  %v96 = getelementptr i64, ptr %roots, i64 9
  store i64 %v63, ptr %v96, align 1
  %v97 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v97, align 1
  %v98 = call i64 @native_alloc(i64 24)
  %v99 = icmp ne i64 %v98, 0
  br i1 %v99, label %ok101, label %trap100
trap100:
  call void @native_trap()
  unreachable
ok101:
  %v102 = inttoptr i64 %v98 to ptr
  %v103 = getelementptr i64, ptr %v102, i64 0
  store i64 346, ptr %v103, align 1
  %v104 = icmp ne i64 %v98, 0
  br i1 %v104, label %ok106, label %trap105
trap105:
  call void @native_trap()
  unreachable
ok106:
  %v107 = inttoptr i64 %v98 to ptr
  %v108 = getelementptr i64, ptr %v107, i64 1
  store i64 %v63, ptr %v108, align 1
  %v109 = icmp ne i64 %v98, 0
  br i1 %v109, label %ok111, label %trap110
trap110:
  call void @native_trap()
  unreachable
ok111:
  %v112 = inttoptr i64 %v98 to ptr
  %v113 = getelementptr i64, ptr %v112, i64 2
  store i64 %v79, ptr %v113, align 1
  %v114 = getelementptr i64, ptr %roots, i64 8
  store i64 %v98, ptr %v114, align 1
  %v115 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v115, align 1
  %v116 = call tailcc i64 @f.24(i64 %v98)
  store i64 %v116, ptr %v5, align 1
  %v117 = load i64, ptr @g.20, align 1
  %v118 = icmp ne i64 %v117, 0
  br i1 %v118, label %ok120, label %trap119
trap119:
  call void @native_trap()
  unreachable
ok120:
  %v121 = load i64, ptr @g.7, align 1
  %v122 = icmp ne i64 %v121, 0
  br i1 %v122, label %ok124, label %trap123
trap123:
  call void @native_trap()
  unreachable
ok124:
  %v125 = load i64, ptr %v5, align 1
  store i64 %v125, ptr %slot61, align 1
  br label %block62
block62:
  %v126 = load i64, ptr %slot61, align 1
  %v127 = getelementptr i64, ptr %roots, i64 8
  store i64 %v126, ptr %v127, align 1
  %v128 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v128, align 1
  %v129 = call tailcc i32 @f.30(i64 %v126)
  %v130 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v130, align 1
  call tailcc void @f.8(i32 %v129)
  call void @native_trap()
  unreachable
else54:
  %v131 = load i64, ptr %v2, align 1
  %v132 = icmp ne i64 %v131, 0
  br i1 %v132, label %ok134, label %trap133
trap133:
  call void @native_trap()
  unreachable
ok134:
  %v135 = inttoptr i64 %v131 to ptr
  %v136 = getelementptr i64, ptr %v135, i64 1
  %v137 = load i32, ptr %v136, align 1
  %v138 = icmp eq i32 %v137, 1
  %v139 = zext i1 %v138 to i32
  %v143 = icmp ne i32 %v139, 0
  br i1 %v143, label %then142, label %else141
then142:
  %v144 = load i64, ptr %v2, align 1
  %v145 = call i32 @native_ref_test(i64 %v144, i64 202, i32 0, i32 0)
  %v146 = icmp ne i32 %v145, 0
  br i1 %v146, label %ok148, label %trap147
trap147:
  call void @native_trap()
  unreachable
ok148:
  br label %block140
else141:
  br label %block140
block140:
  %v149 = load i64, ptr %v2, align 1
  store i64 %v149, ptr %slot52, align 1
  br label %block53
block53:
  %v150 = load i64, ptr %slot52, align 1
  store i64 %v150, ptr %slot6, align 1
  br label %return7
return7:
  %v151 = load i64, ptr %slot6, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v151
}
