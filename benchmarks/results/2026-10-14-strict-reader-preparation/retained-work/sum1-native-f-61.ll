define internal tailcc i64 @f.61(i64 %arg0, i32 %arg1, i32 %arg2, i64 %arg3, i64 %arg4) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i32, align 8
  %slot3 = alloca i32, align 8
  %slot4 = alloca i64, align 8
  %slot6 = alloca double, align 8
  %slot7 = alloca i32, align 8
  %slot12 = alloca i64, align 8
  %slot18 = alloca i64, align 8
  %slot27 = alloca i64, align 8
  %slot200 = alloca double, align 8
  %roots = alloca { ptr, i64, i64, [6 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 6)
  store i64 %arg0, ptr %slot1, align 1
  store i32 %arg1, ptr %slot2, align 1
  store i32 %arg2, ptr %slot3, align 1
  store i64 %arg3, ptr %slot4, align 1
  %v5 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg4, ptr %v5, align 1
  store double 0.0, ptr %slot6, align 1
  store i32 0, ptr %slot7, align 1
  %v8 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v8, align 1
  %v9 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v9, align 1
  %v10 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v10, align 1
  %v11 = getelementptr i64, ptr %roots, i64 7
  store i64 0, ptr %v11, align 1
  %v14 = load i64, ptr %slot1, align 1
  %v15 = load i64, ptr %slot4, align 1
  %v16 = icmp sgt i64 %v14, %v15
  %v17 = zext i1 %v16 to i32
  %v22 = icmp ne i32 %v17, 0
  br i1 %v22, label %then21, label %else20
then21:
  %v23 = load i64, ptr @g.138, align 1
  %v24 = icmp ne i64 %v23, 0
  br i1 %v24, label %ok26, label %trap25
trap25:
  call void @native_trap()
  unreachable
ok26:
  %v29 = load i64, ptr @g.134, align 1
  %v30 = icmp ne i64 %v29, 0
  br i1 %v30, label %ok32, label %trap31
trap31:
  call void @native_trap()
  unreachable
ok32:
  store i64 %v29, ptr %v11, align 1
  %v33 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v33, align 1
  %v34 = call tailcc i32 @f.19()
  %v35 = icmp eq i32 %v34, 0
  %v36 = zext i1 %v35 to i32
  %v40 = icmp ne i32 %v36, 0
  br i1 %v40, label %then39, label %else38
then39:
  call void @native_trap()
  unreachable
else38:
  br label %block37
block37:
  %v41 = load i64, ptr @g.132, align 1
  %v42 = icmp ne i64 %v41, 0
  br i1 %v42, label %ok44, label %trap43
trap43:
  call void @native_trap()
  unreachable
ok44:
  %v45 = load i64, ptr @g.76, align 1
  %v46 = icmp ne i64 %v45, 0
  br i1 %v46, label %ok48, label %trap47
trap47:
  call void @native_trap()
  unreachable
ok48:
  %v49 = load i64, ptr @g.131, align 1
  %v50 = icmp ne i64 %v49, 0
  br i1 %v50, label %ok52, label %trap51
trap51:
  call void @native_trap()
  unreachable
ok52:
  %v53 = load i64, ptr @g.39, align 1
  %v54 = icmp ne i64 %v53, 0
  br i1 %v54, label %ok56, label %trap55
trap55:
  call void @native_trap()
  unreachable
ok56:
  %v57 = load i64, ptr @g.38, align 1
  %v58 = icmp ne i64 %v57, 0
  br i1 %v58, label %ok60, label %trap59
trap59:
  call void @native_trap()
  unreachable
ok60:
  %v61 = load i64, ptr %v11, align 1
  store i64 %v61, ptr %slot27, align 1
  br label %block28
block28:
  %v62 = load i64, ptr %slot27, align 1
  %v63 = getelementptr i64, ptr %roots, i64 8
  store i64 %v62, ptr %v63, align 1
  %v64 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v64, align 1
  %v65 = call tailcc i32 @f.27(i64 %v62)
  %v66 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v66, align 1
  %v67 = call tailcc i32 @f.2()
  %v68 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v68, align 1
  %v69 = call i64 @native_alloc(i64 16)
  %v70 = icmp ne i64 %v69, 0
  br i1 %v70, label %ok72, label %trap71
trap71:
  call void @native_trap()
  unreachable
ok72:
  %v73 = inttoptr i64 %v69 to ptr
  %v74 = getelementptr i64, ptr %v73, i64 0
  store i64 198, ptr %v74, align 1
  %v75 = icmp ne i64 %v69, 0
  br i1 %v75, label %ok77, label %trap76
trap76:
  call void @native_trap()
  unreachable
ok77:
  %v78 = inttoptr i64 %v69 to ptr
  %v79 = getelementptr i64, ptr %v78, i64 1
  store i32 %v67, ptr %v79, align 1
  %v80 = getelementptr i64, ptr %roots, i64 8
  store i64 %v69, ptr %v80, align 1
  %v81 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v81, align 1
  %v82 = call i64 @native_alloc(i64 16)
  %v83 = icmp ne i64 %v82, 0
  br i1 %v83, label %ok85, label %trap84
trap84:
  call void @native_trap()
  unreachable
ok85:
  %v86 = inttoptr i64 %v82 to ptr
  %v87 = getelementptr i64, ptr %v86, i64 0
  store i64 202, ptr %v87, align 1
  %v88 = icmp ne i64 %v82, 0
  br i1 %v88, label %ok90, label %trap89
trap89:
  call void @native_trap()
  unreachable
ok90:
  %v91 = inttoptr i64 %v82 to ptr
  %v92 = getelementptr i64, ptr %v91, i64 1
  store i64 %v69, ptr %v92, align 1
  store i64 %v82, ptr %v8, align 1
  %v93 = load i64, ptr @g.68, align 1
  %v94 = icmp ne i64 %v93, 0
  br i1 %v94, label %ok96, label %trap95
trap95:
  call void @native_trap()
  unreachable
ok96:
  %v97 = load i64, ptr %v8, align 1
  %v98 = getelementptr i64, ptr %roots, i64 8
  store i64 %v97, ptr %v98, align 1
  %v99 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v99, align 1
  %v100 = call tailcc double @f.60(i64 %v97, double 0.0)
  store double %v100, ptr %slot6, align 1
  %v101 = load i64, ptr @g.40, align 1
  %v102 = icmp ne i64 %v101, 0
  br i1 %v102, label %ok104, label %trap103
trap103:
  call void @native_trap()
  unreachable
ok104:
  %v105 = load i32, ptr @g.42, align 1
  %v106 = icmp eq i32 %v105, 0
  %v107 = zext i1 %v106 to i32
  %v111 = icmp ne i32 %v107, 0
  br i1 %v111, label %then110, label %else109
then110:
  call void @native_trap()
  unreachable
else109:
  br label %block108
block108:
  %v112 = load i64, ptr @g.41, align 1
  %v113 = icmp ne i64 %v112, 0
  br i1 %v113, label %ok115, label %trap114
trap114:
  call void @native_trap()
  unreachable
ok115:
  %v116 = load i64, ptr %v8, align 1
  %v117 = icmp ne i64 %v116, 0
  br i1 %v117, label %ok119, label %trap118
trap118:
  call void @native_trap()
  unreachable
ok119:
  %v120 = inttoptr i64 %v116 to ptr
  %v121 = getelementptr i64, ptr %v120, i64 1
  %v122 = load i64, ptr %v121, align 1
  store i64 %v122, ptr %v10, align 1
  %v123 = icmp ne i64 %v122, 0
  br i1 %v123, label %ok125, label %trap124
trap124:
  call void @native_trap()
  unreachable
ok125:
  %v126 = inttoptr i64 %v122 to ptr
  %v127 = getelementptr i64, ptr %v126, i64 1
  %v128 = load i32, ptr %v127, align 1
  store i32 %v128, ptr %slot7, align 1
  %v129 = icmp ne i32 %v128, -1
  %v130 = zext i1 %v129 to i32
  %v134 = icmp ne i32 %v130, 0
  br i1 %v134, label %then133, label %else132
then133:
  %v135 = load i64, ptr %v10, align 1
  %v136 = icmp ne i64 %v135, 0
  br i1 %v136, label %ok138, label %trap137
trap137:
  call void @native_trap()
  unreachable
ok138:
  %v139 = inttoptr i64 %v135 to ptr
  %v140 = getelementptr i64, ptr %v139, i64 1
  store i32 -1, ptr %v140, align 1
  %v141 = load i32, ptr %slot7, align 1
  %v142 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v142, align 1
  call tailcc void @f.3(i32 %v141)
  br label %block131
else132:
  br label %block131
block131:
  %v143 = load i32, ptr %slot3, align 1
  %v144 = icmp eq i32 %v143, 0
  %v145 = zext i1 %v144 to i32
  %v149 = icmp ne i32 %v145, 0
  br i1 %v149, label %then148, label %else147
then148:
  call void @native_trap()
  unreachable
else147:
  br label %block146
block146:
  %v150 = load i64, ptr %slot1, align 1
  %v151 = load i32, ptr %slot2, align 1
  %v152 = load i32, ptr %slot3, align 1
  %v153 = load i64, ptr %slot4, align 1
  %v154 = add i64 %v153, 1
  %v155 = load double, ptr %slot6, align 1
  %v156 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v156, align 1
  %v157 = call i64 @native_alloc(i64 24)
  %v158 = icmp ne i64 %v157, 0
  br i1 %v158, label %ok160, label %trap159
trap159:
  call void @native_trap()
  unreachable
ok160:
  %v161 = inttoptr i64 %v157 to ptr
  %v162 = getelementptr i64, ptr %v161, i64 0
  store i64 278, ptr %v162, align 1
  %v163 = icmp ne i64 %v157, 0
  br i1 %v163, label %ok165, label %trap164
trap164:
  call void @native_trap()
  unreachable
ok165:
  %v166 = inttoptr i64 %v157 to ptr
  %v167 = getelementptr i64, ptr %v166, i64 1
  store i32 1, ptr %v167, align 1
  %v168 = icmp ne i64 %v157, 0
  br i1 %v168, label %ok170, label %trap169
trap169:
  call void @native_trap()
  unreachable
ok170:
  %v171 = inttoptr i64 %v157 to ptr
  %v172 = getelementptr i64, ptr %v171, i64 2
  store double %v155, ptr %v172, align 1
  %v173 = getelementptr i64, ptr %roots, i64 8
  store i64 %v157, ptr %v173, align 1
  %v174 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v174, align 1
  %v175 = call i64 @native_alloc(i64 24)
  %v176 = icmp ne i64 %v175, 0
  br i1 %v176, label %ok178, label %trap177
trap177:
  call void @native_trap()
  unreachable
ok178:
  %v179 = inttoptr i64 %v175 to ptr
  %v180 = getelementptr i64, ptr %v179, i64 0
  store i64 238, ptr %v180, align 1
  %v181 = icmp ne i64 %v175, 0
  br i1 %v181, label %ok183, label %trap182
trap182:
  call void @native_trap()
  unreachable
ok183:
  %v184 = inttoptr i64 %v175 to ptr
  %v185 = getelementptr i64, ptr %v184, i64 1
  store i32 5, ptr %v185, align 1
  %v186 = icmp ne i64 %v175, 0
  br i1 %v186, label %ok188, label %trap187
trap187:
  call void @native_trap()
  unreachable
ok188:
  %v189 = inttoptr i64 %v175 to ptr
  %v190 = getelementptr i64, ptr %v189, i64 2
  store i64 %v157, ptr %v190, align 1
  call void @native_roots_leave(ptr %roots)
  %v191 = tail call tailcc i64 @f.61(i64 %v150, i32 %v151, i32 %v152, i64 %v154, i64 %v175)
  ret i64 %v191
else20:
  %v192 = load i64, ptr @g.35, align 1
  %v193 = icmp ne i64 %v192, 0
  br i1 %v193, label %ok195, label %trap194
trap194:
  call void @native_trap()
  unreachable
ok195:
  %v196 = load i64, ptr %v5, align 1
  %v197 = getelementptr i64, ptr %roots, i64 8
  store i64 %v196, ptr %v197, align 1
  %v198 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v198, align 1
  %v199 = call tailcc double @f.59(i64 %v196)
  %v202 = load i64, ptr @g.35, align 1
  %v203 = icmp ne i64 %v202, 0
  br i1 %v203, label %ok205, label %trap204
trap204:
  call void @native_trap()
  unreachable
ok205:
  %v206 = load i64, ptr @g.135, align 1
  %v207 = icmp ne i64 %v206, 0
  br i1 %v207, label %ok209, label %trap208
trap208:
  call void @native_trap()
  unreachable
ok209:
  %v210 = getelementptr i64, ptr %roots, i64 8
  store i64 %v206, ptr %v210, align 1
  %v211 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v211, align 1
  %v212 = call tailcc double @f.59(i64 %v206)
  store double %v212, ptr %slot200, align 1
  br label %block201
block201:
  %v213 = load double, ptr %slot200, align 1
  %v214 = fsub double %v199, %v213
  store double %v214, ptr %slot6, align 1
  %v215 = load i64, ptr @g.128, align 1
  %v216 = icmp ne i64 %v215, 0
  br i1 %v216, label %ok218, label %trap217
trap217:
  call void @native_trap()
  unreachable
ok218:
  %v219 = load double, ptr %slot6, align 1
  %v220 = fsub double 0.0, %v219
  %v221 = load double, ptr %slot6, align 1
  %v222 = load double, ptr %slot6, align 1
  %v223 = fcmp olt double %v222, 0.0
  %v224 = zext i1 %v223 to i32
  %v225 = icmp ne i32 %v224, 0
  %v226 = select i1 %v225, double %v220, double %v221
  %v227 = fcmp ole double %v226, 1.0e-09
  %v228 = zext i1 %v227 to i32
  %v229 = zext i32 %v228 to i64
  store i64 %v229, ptr %slot18, align 1
  br label %block19
block19:
  %v230 = load i64, ptr %slot18, align 1
  store i64 %v230, ptr %slot12, align 1
  br label %return13
return13:
  %v231 = load i64, ptr %slot12, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v231
}
