define internal tailcc i64 @f.65(i64 %arg0, i32 %arg1, i32 %arg2, i64 %arg3, i64 %arg4) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i32, align 8
  %slot3 = alloca i32, align 8
  %slot4 = alloca i64, align 8
  %slot11 = alloca i32, align 8
  %slot13 = alloca i64, align 8
  %slot19 = alloca i64, align 8
  %slot28 = alloca i64, align 8
  %slot109 = alloca i32, align 8
  %slot132 = alloca i64, align 8
  %roots = alloca { ptr, i64, i64, [10 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 10)
  store i64 %arg0, ptr %slot1, align 1
  store i32 %arg1, ptr %slot2, align 1
  store i32 %arg2, ptr %slot3, align 1
  store i64 %arg3, ptr %slot4, align 1
  %v5 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg4, ptr %v5, align 1
  %v6 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v6, align 1
  %v7 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v7, align 1
  %v8 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v8, align 1
  %v9 = getelementptr i64, ptr %roots, i64 7
  store i64 0, ptr %v9, align 1
  %v10 = getelementptr i64, ptr %roots, i64 8
  store i64 0, ptr %v10, align 1
  store i32 0, ptr %slot11, align 1
  %v12 = getelementptr i64, ptr %roots, i64 9
  store i64 0, ptr %v12, align 1
  %v15 = load i64, ptr %slot1, align 1
  %v16 = load i64, ptr %slot4, align 1
  %v17 = icmp sgt i64 %v15, %v16
  %v18 = zext i1 %v17 to i32
  %v23 = icmp ne i32 %v18, 0
  br i1 %v23, label %then22, label %else21
then22:
  %v24 = load i64, ptr @g.144, align 1
  %v25 = icmp ne i64 %v24, 0
  br i1 %v25, label %ok27, label %trap26
trap26:
  call void @native_trap()
  unreachable
ok27:
  %v30 = load i64, ptr @g.140, align 1
  %v31 = icmp ne i64 %v30, 0
  br i1 %v31, label %ok33, label %trap32
trap32:
  call void @native_trap()
  unreachable
ok33:
  store i64 %v30, ptr %v12, align 1
  %v34 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v34, align 1
  %v35 = call tailcc i32 @f.20()
  %v36 = icmp eq i32 %v35, 0
  %v37 = zext i1 %v36 to i32
  %v41 = icmp ne i32 %v37, 0
  br i1 %v41, label %then40, label %else39
then40:
  call void @native_trap()
  unreachable
else39:
  br label %block38
block38:
  %v42 = load i64, ptr @g.138, align 1
  %v43 = icmp ne i64 %v42, 0
  br i1 %v43, label %ok45, label %trap44
trap44:
  call void @native_trap()
  unreachable
ok45:
  %v46 = load i64, ptr @g.78, align 1
  %v47 = icmp ne i64 %v46, 0
  br i1 %v47, label %ok49, label %trap48
trap48:
  call void @native_trap()
  unreachable
ok49:
  %v50 = load i64, ptr @g.40, align 1
  %v51 = icmp ne i64 %v50, 0
  br i1 %v51, label %ok53, label %trap52
trap52:
  call void @native_trap()
  unreachable
ok53:
  %v54 = load i64, ptr @g.39, align 1
  %v55 = icmp ne i64 %v54, 0
  br i1 %v55, label %ok57, label %trap56
trap56:
  call void @native_trap()
  unreachable
ok57:
  %v58 = load i64, ptr %v12, align 1
  store i64 %v58, ptr %slot28, align 1
  br label %block29
block29:
  %v59 = load i64, ptr %slot28, align 1
  %v60 = getelementptr i64, ptr %roots, i64 10
  store i64 %v59, ptr %v60, align 1
  %v61 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v61, align 1
  %v62 = call tailcc i32 @f.28(i64 %v59)
  %v63 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v63, align 1
  %v64 = call tailcc i32 @f.2()
  %v65 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v65, align 1
  %v66 = call i64 @native_alloc(i64 16)
  %v67 = icmp ne i64 %v66, 0
  br i1 %v67, label %ok69, label %trap68
trap68:
  call void @native_trap()
  unreachable
ok69:
  %v70 = inttoptr i64 %v66 to ptr
  %v71 = getelementptr i64, ptr %v70, i64 0
  store i64 182, ptr %v71, align 1
  %v72 = icmp ne i64 %v66, 0
  br i1 %v72, label %ok74, label %trap73
trap73:
  call void @native_trap()
  unreachable
ok74:
  %v75 = inttoptr i64 %v66 to ptr
  %v76 = getelementptr i64, ptr %v75, i64 1
  store i32 %v64, ptr %v76, align 1
  %v77 = getelementptr i64, ptr %roots, i64 10
  store i64 %v66, ptr %v77, align 1
  %v78 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v78, align 1
  %v79 = call i64 @native_alloc(i64 16)
  %v80 = icmp ne i64 %v79, 0
  br i1 %v80, label %ok82, label %trap81
trap81:
  call void @native_trap()
  unreachable
ok82:
  %v83 = inttoptr i64 %v79 to ptr
  %v84 = getelementptr i64, ptr %v83, i64 0
  store i64 186, ptr %v84, align 1
  %v85 = icmp ne i64 %v79, 0
  br i1 %v85, label %ok87, label %trap86
trap86:
  call void @native_trap()
  unreachable
ok87:
  %v88 = inttoptr i64 %v79 to ptr
  %v89 = getelementptr i64, ptr %v88, i64 1
  store i64 %v66, ptr %v89, align 1
  store i64 %v79, ptr %v6, align 1
  %v90 = load i64, ptr @g.19, align 1
  %v91 = icmp ne i64 %v90, 0
  br i1 %v91, label %ok93, label %trap92
trap92:
  call void @native_trap()
  unreachable
ok93:
  %v94 = load i64, ptr %v6, align 1
  %v95 = getelementptr i64, ptr %roots, i64 10
  store i64 %v94, ptr %v95, align 1
  %v96 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v96, align 1
  %v97 = call tailcc i64 @f.63(i64 %v94)
  store i64 %v97, ptr %v7, align 1
  %v98 = load i64, ptr @g.49, align 1
  %v99 = icmp ne i64 %v98, 0
  br i1 %v99, label %ok101, label %trap100
trap100:
  call void @native_trap()
  unreachable
ok101:
  %v102 = load i64, ptr %v7, align 1
  %v103 = icmp ne i64 %v102, 0
  br i1 %v103, label %ok105, label %trap104
trap104:
  call void @native_trap()
  unreachable
ok105:
  %v106 = inttoptr i64 %v102 to ptr
  %v107 = getelementptr i64, ptr %v106, i64 1
  %v108 = load i32, ptr %v107, align 1
  store i32 %v108, ptr %slot11, align 1
  %v113 = icmp ne i32 %v108, 0
  br i1 %v113, label %then112, label %else111
then112:
  %v114 = load i32, ptr %slot11, align 1
  %v115 = icmp eq i32 %v114, 1
  %v116 = zext i1 %v115 to i32
  %v120 = icmp ne i32 %v116, 0
  br i1 %v120, label %then119, label %else118
then119:
  %v121 = load i64, ptr %v7, align 1
  %v122 = call i32 @native_ref_test(i64 %v121, i64 202, i32 0, i32 0)
  %v123 = icmp ne i32 %v122, 0
  br i1 %v123, label %ok125, label %trap124
trap124:
  call void @native_trap()
  unreachable
ok125:
  br label %block117
else118:
  %v126 = load i64, ptr %v7, align 1
  %v127 = call i32 @native_ref_test(i64 %v126, i64 198, i32 0, i32 0)
  %v128 = icmp ne i32 %v127, 0
  br i1 %v128, label %ok130, label %trap129
trap129:
  call void @native_trap()
  unreachable
ok130:
  br label %block117
block117:
  store i32 0, ptr %slot109, align 1
  br label %block110
else111:
  store i32 1, ptr %slot109, align 1
  br label %block110
block110:
  %v131 = load i32, ptr %slot109, align 1
  %v136 = icmp ne i32 %v131, 0
  br i1 %v136, label %then135, label %else134
then135:
  %v137 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v137, align 1
  %v138 = call i64 @native_alloc(i64 24)
  %v139 = icmp ne i64 %v138, 0
  br i1 %v139, label %ok141, label %trap140
trap140:
  call void @native_trap()
  unreachable
ok141:
  %v142 = inttoptr i64 %v138 to ptr
  %v143 = getelementptr i64, ptr %v142, i64 0
  store i64 270, ptr %v143, align 1
  %v144 = icmp ne i64 %v138, 0
  br i1 %v144, label %ok146, label %trap145
trap145:
  call void @native_trap()
  unreachable
ok146:
  %v147 = inttoptr i64 %v138 to ptr
  %v148 = getelementptr i64, ptr %v147, i64 1
  store i32 1, ptr %v148, align 1
  %v149 = icmp ne i64 %v138, 0
  br i1 %v149, label %ok151, label %trap150
trap150:
  call void @native_trap()
  unreachable
ok151:
  %v152 = inttoptr i64 %v138 to ptr
  %v153 = getelementptr i64, ptr %v152, i64 2
  store i32 0, ptr %v153, align 1
  store i64 %v138, ptr %slot132, align 1
  br label %block133
else134:
  %v154 = load i64, ptr @g.19, align 1
  %v155 = icmp ne i64 %v154, 0
  br i1 %v155, label %ok157, label %trap156
trap156:
  call void @native_trap()
  unreachable
ok157:
  %v158 = load i64, ptr %v6, align 1
  %v159 = getelementptr i64, ptr %roots, i64 10
  store i64 %v158, ptr %v159, align 1
  %v160 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v160, align 1
  %v161 = call tailcc i64 @f.63(i64 %v158)
  store i64 %v161, ptr %v8, align 1
  %v162 = load i64, ptr @g.21, align 1
  %v163 = icmp ne i64 %v162, 0
  br i1 %v163, label %ok165, label %trap164
trap164:
  call void @native_trap()
  unreachable
ok165:
  %v166 = load i64, ptr %v6, align 1
  %v167 = load i64, ptr %v8, align 1
  %v168 = load i64, ptr %v7, align 1
  %v169 = getelementptr i64, ptr %roots, i64 10
  store i64 %v167, ptr %v169, align 1
  %v170 = getelementptr i64, ptr %roots, i64 11
  store i64 %v166, ptr %v170, align 1
  %v171 = getelementptr i64, ptr %roots, i64 12
  store i64 %v168, ptr %v171, align 1
  %v172 = getelementptr i64, ptr %roots, i64 2
  store i64 10, ptr %v172, align 1
  %v173 = call tailcc i64 @f.39(i64 %v168)
  %v174 = getelementptr i64, ptr %roots, i64 10
  store i64 %v166, ptr %v174, align 1
  %v175 = getelementptr i64, ptr %roots, i64 11
  store i64 %v167, ptr %v175, align 1
  %v176 = getelementptr i64, ptr %roots, i64 12
  store i64 %v173, ptr %v176, align 1
  %v177 = getelementptr i64, ptr %roots, i64 2
  store i64 10, ptr %v177, align 1
  %v178 = call tailcc i64 @f.64(i64 %v166, i32 0, i32 1, i64 %v167, i64 %v173, i64 1)
  store i64 %v178, ptr %slot132, align 1
  br label %block133
block133:
  %v179 = load i64, ptr %slot132, align 1
  store i64 %v179, ptr %v5, align 1
  %v180 = load i64, ptr @g.41, align 1
  %v181 = icmp ne i64 %v180, 0
  br i1 %v181, label %ok183, label %trap182
trap182:
  call void @native_trap()
  unreachable
ok183:
  %v184 = load i32, ptr @g.43, align 1
  %v185 = icmp eq i32 %v184, 0
  %v186 = zext i1 %v185 to i32
  %v190 = icmp ne i32 %v186, 0
  br i1 %v190, label %then189, label %else188
then189:
  call void @native_trap()
  unreachable
else188:
  br label %block187
block187:
  %v191 = load i64, ptr @g.42, align 1
  %v192 = icmp ne i64 %v191, 0
  br i1 %v192, label %ok194, label %trap193
trap193:
  call void @native_trap()
  unreachable
ok194:
  %v195 = load i64, ptr %v6, align 1
  %v196 = icmp ne i64 %v195, 0
  br i1 %v196, label %ok198, label %trap197
trap197:
  call void @native_trap()
  unreachable
ok198:
  %v199 = inttoptr i64 %v195 to ptr
  %v200 = getelementptr i64, ptr %v199, i64 1
  %v201 = load i64, ptr %v200, align 1
  store i64 %v201, ptr %v10, align 1
  %v202 = icmp ne i64 %v201, 0
  br i1 %v202, label %ok204, label %trap203
trap203:
  call void @native_trap()
  unreachable
ok204:
  %v205 = inttoptr i64 %v201 to ptr
  %v206 = getelementptr i64, ptr %v205, i64 1
  %v207 = load i32, ptr %v206, align 1
  store i32 %v207, ptr %slot11, align 1
  %v208 = icmp ne i32 %v207, -1
  %v209 = zext i1 %v208 to i32
  %v213 = icmp ne i32 %v209, 0
  br i1 %v213, label %then212, label %else211
then212:
  %v214 = load i64, ptr %v10, align 1
  %v215 = icmp ne i64 %v214, 0
  br i1 %v215, label %ok217, label %trap216
trap216:
  call void @native_trap()
  unreachable
ok217:
  %v218 = inttoptr i64 %v214 to ptr
  %v219 = getelementptr i64, ptr %v218, i64 1
  store i32 -1, ptr %v219, align 1
  %v220 = load i32, ptr %slot11, align 1
  %v221 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v221, align 1
  call tailcc void @f.3(i32 %v220)
  br label %block210
else211:
  br label %block210
block210:
  %v222 = load i32, ptr %slot3, align 1
  %v223 = icmp eq i32 %v222, 0
  %v224 = zext i1 %v223 to i32
  %v228 = icmp ne i32 %v224, 0
  br i1 %v228, label %then227, label %else226
then227:
  call void @native_trap()
  unreachable
else226:
  br label %block225
block225:
  %v229 = load i64, ptr %slot1, align 1
  %v230 = load i32, ptr %slot2, align 1
  %v231 = load i32, ptr %slot3, align 1
  %v232 = load i64, ptr %slot4, align 1
  %v233 = add i64 %v232, 1
  %v234 = load i64, ptr %v5, align 1
  call void @native_roots_leave(ptr %roots)
  %v235 = tail call tailcc i64 @f.65(i64 %v229, i32 %v230, i32 %v231, i64 %v233, i64 %v234)
  ret i64 %v235
else21:
  %v236 = load i64, ptr @g.26, align 1
  %v237 = icmp ne i64 %v236, 0
  br i1 %v237, label %ok239, label %trap238
trap238:
  call void @native_trap()
  unreachable
ok239:
  %v240 = load i64, ptr %v5, align 1
  %v241 = load i64, ptr @g.141, align 1
  %v242 = icmp ne i64 %v241, 0
  br i1 %v242, label %ok244, label %trap243
trap243:
  call void @native_trap()
  unreachable
ok244:
  %v245 = getelementptr i64, ptr %roots, i64 10
  store i64 %v240, ptr %v245, align 1
  %v246 = getelementptr i64, ptr %roots, i64 11
  store i64 %v241, ptr %v246, align 1
  %v247 = getelementptr i64, ptr %roots, i64 2
  store i64 9, ptr %v247, align 1
  %v248 = call tailcc i32 @f.36(i64 %v240, i64 %v241)
  %v249 = icmp ne i32 %v248, 0
  %v250 = zext i1 %v249 to i32
  %v251 = zext i32 %v250 to i64
  store i64 %v251, ptr %slot19, align 1
  br label %block20
block20:
  %v252 = load i64, ptr %slot19, align 1
  store i64 %v252, ptr %slot13, align 1
  br label %return14
return14:
  %v253 = load i64, ptr %slot13, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v253
}
