define internal tailcc i32 @f.24(i64 %arg0, i64 %arg1, i64 %arg2, i32 %arg3, i32 %arg4, i32 %arg5, i32 %arg6, i32 %arg7, i32 %arg8, i32 %arg9, i64 %arg10) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i64, align 8
  %slot4 = alloca i32, align 8
  %slot5 = alloca i32, align 8
  %slot6 = alloca i32, align 8
  %slot7 = alloca i32, align 8
  %slot8 = alloca i32, align 8
  %slot9 = alloca i32, align 8
  %slot10 = alloca i32, align 8
  %slot11 = alloca i64, align 8
  %slot12 = alloca i64, align 8
  %slot13 = alloca i32, align 8
  %slot18 = alloca i32, align 8
  %slot19 = alloca i32, align 8
  %slot25 = alloca i32, align 8
  %slot204 = alloca i32, align 8
  %slot224 = alloca i32, align 8
  %roots = alloca { ptr, i64, i64, [7 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 7)
  store i64 %arg0, ptr %slot1, align 1
  store i64 %arg1, ptr %slot2, align 1
  %v3 = getelementptr i64, ptr %roots, i64 3
  store i64 %arg2, ptr %v3, align 1
  store i32 %arg3, ptr %slot4, align 1
  store i32 %arg4, ptr %slot5, align 1
  store i32 %arg5, ptr %slot6, align 1
  store i32 %arg6, ptr %slot7, align 1
  store i32 %arg7, ptr %slot8, align 1
  store i32 %arg8, ptr %slot9, align 1
  store i32 %arg9, ptr %slot10, align 1
  store i64 %arg10, ptr %slot11, align 1
  store i64 0, ptr %slot12, align 1
  store i32 0, ptr %slot13, align 1
  %v14 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v14, align 1
  %v15 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v15, align 1
  %v16 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v16, align 1
  %v17 = getelementptr i64, ptr %roots, i64 7
  store i64 0, ptr %v17, align 1
  store i32 0, ptr %slot18, align 1
  %v21 = load i64, ptr %slot1, align 1
  %v22 = load i64, ptr %slot11, align 1
  %v23 = icmp eq i64 %v21, %v22
  %v24 = zext i1 %v23 to i32
  %v29 = icmp ne i32 %v24, 0
  br i1 %v29, label %then28, label %else27
then28:
  store i32 0, ptr %slot25, align 1
  br label %block26
else27:
  %v30 = load i32, ptr %slot6, align 1
  %v31 = icmp eq i32 %v30, 0
  %v32 = zext i1 %v31 to i32
  %v36 = icmp ne i32 %v32, 0
  br i1 %v36, label %then35, label %else34
then35:
  call void @native_trap()
  unreachable
else34:
  br label %block33
block33:
  %v37 = load i32, ptr %slot4, align 1
  %v38 = icmp eq i32 %v37, 0
  %v39 = zext i1 %v38 to i32
  %v43 = icmp ne i32 %v39, 0
  br i1 %v43, label %then42, label %else41
then42:
  call void @native_trap()
  unreachable
else41:
  br label %block40
block40:
  %v44 = load i64, ptr %v3, align 1
  %v45 = icmp ne i64 %v44, 0
  br i1 %v45, label %ok47, label %trap46
trap46:
  call void @native_trap()
  unreachable
ok47:
  %v48 = inttoptr i64 %v44 to ptr
  %v49 = getelementptr i64, ptr %v48, i64 2
  %v50 = load i64, ptr %v49, align 1
  %v51 = load i64, ptr %slot2, align 1
  %v52 = load i64, ptr %v3, align 1
  %v53 = icmp ne i64 %v52, 0
  br i1 %v53, label %ok55, label %trap54
trap54:
  call void @native_trap()
  unreachable
ok55:
  %v56 = inttoptr i64 %v52 to ptr
  %v57 = getelementptr i64, ptr %v56, i64 1
  %v58 = load i64, ptr %v57, align 1
  %v59 = icmp ne i64 %v58, 0
  br i1 %v59, label %ok61, label %trap60
trap60:
  call void @native_trap()
  unreachable
ok61:
  %v62 = inttoptr i64 %v58 to ptr
  %v63 = getelementptr i64, ptr %v62, i64 1
  %v64 = load ptr, ptr %v63, align 1
  %v65 = getelementptr i64, ptr %roots, i64 8
  store i64 %v50, ptr %v65, align 1
  %v66 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v66, align 1
  %v67 = call tailcc i64 %v64(i64 %v50, i64 %v51)
  store i64 %v67, ptr %slot12, align 1
  %v68 = load i32, ptr @g.8, align 1
  %v69 = icmp eq i32 %v68, 0
  %v70 = zext i1 %v69 to i32
  %v74 = icmp ne i32 %v70, 0
  br i1 %v74, label %then73, label %else72
then73:
  call void @native_trap()
  unreachable
else72:
  br label %block71
block71:
  %v75 = load i64, ptr @g.7, align 1
  %v76 = icmp ne i64 %v75, 0
  br i1 %v76, label %ok78, label %trap77
trap77:
  call void @native_trap()
  unreachable
ok78:
  %v79 = load i64, ptr %slot12, align 1
  %v80 = icmp ugt i64 %v79, 4294967295
  %v81 = zext i1 %v80 to i32
  %v85 = icmp ne i32 %v81, 0
  br i1 %v85, label %then84, label %else83
then84:
  call void @native_trap()
  unreachable
else83:
  br label %block82
block82:
  %v86 = load i64, ptr %v3, align 1
  %v87 = load i32, ptr %slot4, align 1
  %v88 = load i64, ptr %slot12, align 1
  %v89 = load i64, ptr %slot12, align 1
  %v90 = trunc i64 %v89 to i32
  %v91 = getelementptr i64, ptr %roots, i64 8
  store i64 %v86, ptr %v91, align 1
  %v92 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v92, align 1
  %v93 = zext i32 0 to i64
  %v94 = call i64 @native_array_new(i64 87, i32 %v90, i64 %v93)
  %v95 = getelementptr i64, ptr %roots, i64 8
  store i64 %v94, ptr %v95, align 1
  %v96 = getelementptr i64, ptr %roots, i64 9
  store i64 %v86, ptr %v96, align 1
  %v97 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v97, align 1
  %v98 = call i64 @native_alloc(i64 16)
  %v99 = icmp ne i64 %v98, 0
  br i1 %v99, label %ok101, label %trap100
trap100:
  call void @native_trap()
  unreachable
ok101:
  %v102 = inttoptr i64 %v98 to ptr
  %v103 = getelementptr i64, ptr %v102, i64 0
  store i64 94, ptr %v103, align 1
  %v104 = icmp ne i64 %v98, 0
  br i1 %v104, label %ok106, label %trap105
trap105:
  call void @native_trap()
  unreachable
ok106:
  %v107 = inttoptr i64 %v98 to ptr
  %v108 = getelementptr i64, ptr %v107, i64 1
  store i64 %v94, ptr %v108, align 1
  %v109 = getelementptr i64, ptr %roots, i64 8
  store i64 %v86, ptr %v109, align 1
  %v110 = getelementptr i64, ptr %roots, i64 9
  store i64 %v98, ptr %v110, align 1
  %v111 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v111, align 1
  %v112 = call tailcc i64 @f.23(i64 %v86, i32 %v87, i64 %v88, i64 %v98, i32 0, i32 1, i64 0)
  store i64 %v112, ptr %v14, align 1
  %v113 = load i32, ptr @g.30, align 1
  %v114 = icmp eq i32 %v113, 0
  %v115 = zext i1 %v114 to i32
  %v119 = icmp ne i32 %v115, 0
  br i1 %v119, label %then118, label %else117
then118:
  call void @native_trap()
  unreachable
else117:
  br label %block116
block116:
  %v120 = load i64, ptr @g.29, align 1
  %v121 = icmp ne i64 %v120, 0
  br i1 %v121, label %ok123, label %trap122
trap122:
  call void @native_trap()
  unreachable
ok123:
  %v124 = load i32, ptr @g.42, align 1
  %v125 = icmp eq i32 %v124, 0
  %v126 = zext i1 %v125 to i32
  %v130 = icmp ne i32 %v126, 0
  br i1 %v130, label %then129, label %else128
then129:
  call void @native_trap()
  unreachable
else128:
  br label %block127
block127:
  %v131 = load i64, ptr @g.41, align 1
  %v132 = icmp ne i64 %v131, 0
  br i1 %v132, label %ok134, label %trap133
trap133:
  call void @native_trap()
  unreachable
ok134:
  %v135 = load i32, ptr %slot8, align 1
  %v136 = icmp eq i32 %v135, 0
  %v137 = zext i1 %v136 to i32
  %v141 = icmp ne i32 %v137, 0
  br i1 %v141, label %then140, label %else139
then140:
  call void @native_trap()
  unreachable
else139:
  br label %block138
block138:
  %v142 = load i32, ptr @g.28, align 1
  %v143 = icmp eq i32 %v142, 0
  %v144 = zext i1 %v143 to i32
  %v148 = icmp ne i32 %v144, 0
  br i1 %v148, label %then147, label %else146
then147:
  call void @native_trap()
  unreachable
else146:
  br label %block145
block145:
  %v149 = load i64, ptr @g.27, align 1
  %v150 = icmp ne i64 %v149, 0
  br i1 %v150, label %ok152, label %trap151
trap151:
  call void @native_trap()
  unreachable
ok152:
  %v153 = load i64, ptr %v14, align 1
  %v154 = load i64, ptr %v14, align 1
  %v155 = icmp ne i64 %v154, 0
  br i1 %v155, label %ok157, label %trap156
trap156:
  call void @native_trap()
  unreachable
ok157:
  %v158 = inttoptr i64 %v154 to ptr
  %v159 = getelementptr i64, ptr %v158, i64 1
  %v160 = load i64, ptr %v159, align 1
  %v161 = call i32 @native_array_length(i64 %v160)
  %v162 = zext i32 %v161 to i64
  %v163 = getelementptr i64, ptr %roots, i64 8
  store i64 %v153, ptr %v163, align 1
  %v164 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v164, align 1
  %v165 = call tailcc i64 @f.5(i64 %v153, i64 %v162)
  store i64 %v165, ptr %v16, align 1
  %v166 = getelementptr i64, ptr %roots, i64 8
  store i64 %v165, ptr %v166, align 1
  %v167 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v167, align 1
  %v168 = call tailcc i64 @f.16(i64 %v165)
  store i64 %v168, ptr %v15, align 1
  %v169 = load i32, ptr @g.28, align 1
  %v170 = icmp eq i32 %v169, 0
  %v171 = zext i1 %v170 to i32
  %v175 = icmp ne i32 %v171, 0
  br i1 %v175, label %then174, label %else173
then174:
  call void @native_trap()
  unreachable
else173:
  br label %block172
block172:
  %v176 = load i64, ptr @g.27, align 1
  %v177 = icmp ne i64 %v176, 0
  br i1 %v177, label %ok179, label %trap178
trap178:
  call void @native_trap()
  unreachable
ok179:
  %v180 = load i64, ptr %v15, align 1
  %v181 = load i64, ptr %v15, align 1
  %v182 = icmp ne i64 %v181, 0
  br i1 %v182, label %ok184, label %trap183
trap183:
  call void @native_trap()
  unreachable
ok184:
  %v185 = inttoptr i64 %v181 to ptr
  %v186 = getelementptr i64, ptr %v185, i64 1
  %v187 = load i64, ptr %v186, align 1
  %v188 = call i32 @native_array_length(i64 %v187)
  %v189 = zext i32 %v188 to i64
  %v190 = getelementptr i64, ptr %roots, i64 8
  store i64 %v180, ptr %v190, align 1
  %v191 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v191, align 1
  %v192 = call tailcc i64 @f.5(i64 %v180, i64 %v189)
  store i64 %v192, ptr %v17, align 1
  %v193 = load i32, ptr @g.6, align 1
  %v194 = icmp eq i32 %v193, 0
  %v195 = zext i1 %v194 to i32
  %v199 = icmp ne i32 %v195, 0
  br i1 %v199, label %then198, label %else197
then198:
  call void @native_trap()
  unreachable
else197:
  br label %block196
block196:
  %v200 = load i64, ptr @g.5, align 1
  %v201 = icmp ne i64 %v200, 0
  br i1 %v201, label %ok203, label %trap202
trap202:
  call void @native_trap()
  unreachable
ok203:
  %v206 = load i64, ptr %v16, align 1
  %v207 = icmp ne i64 %v206, 0
  br i1 %v207, label %ok209, label %trap208
trap208:
  call void @native_trap()
  unreachable
ok209:
  %v210 = inttoptr i64 %v206 to ptr
  %v211 = getelementptr i64, ptr %v210, i64 2
  %v212 = load i32, ptr %v211, align 1
  %v213 = zext i32 %v212 to i64
  %v214 = load i64, ptr %v17, align 1
  %v215 = icmp ne i64 %v214, 0
  br i1 %v215, label %ok217, label %trap216
trap216:
  call void @native_trap()
  unreachable
ok217:
  %v218 = inttoptr i64 %v214 to ptr
  %v219 = getelementptr i64, ptr %v218, i64 2
  %v220 = load i32, ptr %v219, align 1
  %v221 = zext i32 %v220 to i64
  %v222 = icmp eq i64 %v213, %v221
  %v223 = zext i1 %v222 to i32
  %v228 = icmp ne i32 %v223, 0
  br i1 %v228, label %then227, label %else226
then227:
  %v229 = load i64, ptr %v16, align 1
  %v230 = load i64, ptr %v17, align 1
  %v231 = getelementptr i64, ptr %roots, i64 8
  store i64 %v229, ptr %v231, align 1
  %v232 = getelementptr i64, ptr %roots, i64 9
  store i64 %v230, ptr %v232, align 1
  %v233 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v233, align 1
  %v234 = call tailcc i32 @f.4(i64 %v229, i64 %v230, i32 0, i32 1, i64 0)
  store i32 %v234, ptr %slot224, align 1
  br label %block225
else226:
  store i32 0, ptr %slot224, align 1
  br label %block225
block225:
  %v235 = load i32, ptr %slot224, align 1
  store i32 %v235, ptr %slot18, align 1
  %v236 = load i32, ptr @g.58, align 1
  %v237 = icmp eq i32 %v236, 0
  %v238 = zext i1 %v237 to i32
  %v242 = icmp ne i32 %v238, 0
  br i1 %v242, label %then241, label %else240
then241:
  call void @native_trap()
  unreachable
else240:
  br label %block239
block239:
  %v243 = load i64, ptr @g.57, align 1
  %v244 = icmp ne i64 %v243, 0
  br i1 %v244, label %ok246, label %trap245
trap245:
  call void @native_trap()
  unreachable
ok246:
  %v247 = load i32, ptr %slot18, align 1
  store i32 %v247, ptr %slot204, align 1
  br label %block205
block205:
  %v248 = load i32, ptr %slot204, align 1
  %v249 = getelementptr i64, ptr %roots, i64 2
  store i64 5, ptr %v249, align 1
  call tailcc void @f.19(i32 %v248)
  %v250 = load i32, ptr %slot10, align 1
  %v251 = icmp eq i32 %v250, 0
  %v252 = zext i1 %v251 to i32
  %v256 = icmp ne i32 %v252, 0
  br i1 %v256, label %then255, label %else254
then255:
  call void @native_trap()
  unreachable
else254:
  br label %block253
block253:
  %v257 = load i64, ptr %slot1, align 1
  %v258 = load i64, ptr %slot2, align 1
  %v259 = load i64, ptr %v3, align 1
  %v260 = load i32, ptr %slot4, align 1
  %v261 = load i32, ptr %slot5, align 1
  %v262 = load i32, ptr %slot6, align 1
  %v263 = load i32, ptr %slot7, align 1
  %v264 = load i32, ptr %slot8, align 1
  %v265 = load i32, ptr %slot9, align 1
  %v266 = load i32, ptr %slot10, align 1
  %v267 = load i64, ptr %slot11, align 1
  %v268 = add i64 %v267, 1
  call void @native_roots_leave(ptr %roots)
  %v269 = tail call tailcc i32 @f.24(i64 %v257, i64 %v258, i64 %v259, i32 %v260, i32 %v261, i32 %v262, i32 %v263, i32 %v264, i32 %v265, i32 %v266, i64 %v268)
  ret i32 %v269
block26:
  %v270 = load i32, ptr %slot25, align 1
  store i32 %v270, ptr %slot19, align 1
  br label %return20
return20:
  %v271 = load i32, ptr %slot19, align 1
  call void @native_roots_leave(ptr %roots)
  ret i32 %v271
}
