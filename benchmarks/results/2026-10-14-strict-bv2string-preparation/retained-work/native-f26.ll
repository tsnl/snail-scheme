define internal tailcc i64 @f.26(i64 %arg0, i32 %arg1, i32 %arg2, i64 %arg3, i64 %arg4) {
entry:
  %slot1 = alloca i64, align 8
  %slot2 = alloca i32, align 8
  %slot3 = alloca i32, align 8
  %slot4 = alloca i64, align 8
  %slot5 = alloca i64, align 8
  %slot12 = alloca i32, align 8
  %slot13 = alloca i32, align 8
  %slot14 = alloca i64, align 8
  %slot20 = alloca i64, align 8
  %slot46 = alloca i64, align 8
  %slot70 = alloca i64, align 8
  %slot381 = alloca i32, align 8
  %slot401 = alloca i32, align 8
  %slot460 = alloca i64, align 8
  %slot474 = alloca i64, align 8
  %slot488 = alloca i64, align 8
  %slot502 = alloca i64, align 8
  %slot516 = alloca i64, align 8
  %slot530 = alloca i64, align 8
  %slot544 = alloca i64, align 8
  %slot558 = alloca i64, align 8
  %slot572 = alloca i64, align 8
  %slot586 = alloca i64, align 8
  %slot600 = alloca i64, align 8
  %slot614 = alloca i64, align 8
  %slot628 = alloca i64, align 8
  %slot642 = alloca i64, align 8
  %slot656 = alloca i64, align 8
  %slot670 = alloca i64, align 8
  %slot684 = alloca i64, align 8
  %slot698 = alloca i64, align 8
  %slot712 = alloca i64, align 8
  %slot726 = alloca i64, align 8
  %slot740 = alloca i64, align 8
  %slot754 = alloca i64, align 8
  %slot768 = alloca i64, align 8
  %slot782 = alloca i64, align 8
  %slot838 = alloca i32, align 8
  %roots = alloca { ptr, i64, i64, [13 x i64] }, align 8
  call void @native_roots_enter(ptr %roots, i64 13)
  store i64 %arg0, ptr %slot1, align 1
  store i32 %arg1, ptr %slot2, align 1
  store i32 %arg2, ptr %slot3, align 1
  store i64 %arg3, ptr %slot4, align 1
  store i64 %arg4, ptr %slot5, align 1
  %v6 = getelementptr i64, ptr %roots, i64 3
  store i64 0, ptr %v6, align 1
  %v7 = getelementptr i64, ptr %roots, i64 4
  store i64 0, ptr %v7, align 1
  %v8 = getelementptr i64, ptr %roots, i64 5
  store i64 0, ptr %v8, align 1
  %v9 = getelementptr i64, ptr %roots, i64 6
  store i64 0, ptr %v9, align 1
  %v10 = getelementptr i64, ptr %roots, i64 7
  store i64 0, ptr %v10, align 1
  %v11 = getelementptr i64, ptr %roots, i64 8
  store i64 0, ptr %v11, align 1
  store i32 0, ptr %slot12, align 1
  store i32 0, ptr %slot13, align 1
  %v16 = load i64, ptr %slot1, align 1
  %v17 = load i64, ptr %slot4, align 1
  %v18 = icmp sgt i64 %v16, %v17
  %v19 = zext i1 %v18 to i32
  %v24 = icmp ne i32 %v19, 0
  br i1 %v24, label %then23, label %else22
then23:
  %v25 = load i32, ptr @g.62, align 1
  %v26 = icmp eq i32 %v25, 0
  %v27 = zext i1 %v26 to i32
  %v31 = icmp ne i32 %v27, 0
  br i1 %v31, label %then30, label %else29
then30:
  call void @native_trap()
  unreachable
else29:
  br label %block28
block28:
  %v32 = load i32, ptr @g.54, align 1
  %v33 = icmp eq i32 %v32, 0
  %v34 = zext i1 %v33 to i32
  %v38 = icmp ne i32 %v34, 0
  br i1 %v38, label %then37, label %else36
then37:
  call void @native_trap()
  unreachable
else36:
  br label %block35
block35:
  %v39 = load i64, ptr @g.53, align 1
  %v40 = icmp ne i64 %v39, 0
  br i1 %v40, label %ok42, label %trap41
trap41:
  call void @native_trap()
  unreachable
ok42:
  %v43 = load i64, ptr @g.61, align 1
  %v44 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v44, align 1
  %v45 = call tailcc i64 @f.1(i64 %v43)
  %v48 = load i32, ptr @g.64, align 1
  %v49 = icmp eq i32 %v48, 0
  %v50 = zext i1 %v49 to i32
  %v54 = icmp ne i32 %v50, 0
  br i1 %v54, label %then53, label %else52
then53:
  call void @native_trap()
  unreachable
else52:
  br label %block51
block51:
  %v55 = load i32, ptr @g.54, align 1
  %v56 = icmp eq i32 %v55, 0
  %v57 = zext i1 %v56 to i32
  %v61 = icmp ne i32 %v57, 0
  br i1 %v61, label %then60, label %else59
then60:
  call void @native_trap()
  unreachable
else59:
  br label %block58
block58:
  %v62 = load i64, ptr @g.53, align 1
  %v63 = icmp ne i64 %v62, 0
  br i1 %v63, label %ok65, label %trap64
trap64:
  call void @native_trap()
  unreachable
ok65:
  %v66 = load i64, ptr @g.63, align 1
  %v67 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v67, align 1
  %v68 = call tailcc i64 @f.1(i64 %v66)
  store i64 %v68, ptr %slot46, align 1
  br label %block47
block47:
  %v69 = load i64, ptr %slot46, align 1
  %v72 = load i32, ptr @g.60, align 1
  %v73 = icmp eq i32 %v72, 0
  %v74 = zext i1 %v73 to i32
  %v78 = icmp ne i32 %v74, 0
  br i1 %v78, label %then77, label %else76
then77:
  call void @native_trap()
  unreachable
else76:
  br label %block75
block75:
  %v79 = load i64, ptr @g.59, align 1
  %v80 = icmp ne i64 %v79, 0
  br i1 %v80, label %ok82, label %trap81
trap81:
  call void @native_trap()
  unreachable
ok82:
  %v83 = getelementptr i64, ptr %roots, i64 9
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v83, align 1
  %v84 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v84, align 1
  %v85 = call i64 @native_alloc(i64 8)
  %v86 = icmp ne i64 %v85, 0
  br i1 %v86, label %ok88, label %trap87
trap87:
  call void @native_trap()
  unreachable
ok88:
  %v89 = inttoptr i64 %v85 to ptr
  %v90 = getelementptr i64, ptr %v89, i64 0
  store i64 30, ptr %v90, align 1
  %v91 = getelementptr i64, ptr %roots, i64 9
  store i64 %v85, ptr %v91, align 1
  %v92 = getelementptr i64, ptr %roots, i64 10
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v92, align 1
  %v93 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v93, align 1
  %v94 = call i64 @native_alloc(i64 16)
  %v95 = icmp ne i64 %v94, 0
  br i1 %v95, label %ok97, label %trap96
trap96:
  call void @native_trap()
  unreachable
ok97:
  %v98 = inttoptr i64 %v94 to ptr
  %v99 = getelementptr i64, ptr %v98, i64 0
  store i64 42, ptr %v99, align 1
  %v100 = icmp ne i64 %v94, 0
  br i1 %v100, label %ok102, label %trap101
trap101:
  call void @native_trap()
  unreachable
ok102:
  %v103 = inttoptr i64 %v94 to ptr
  %v104 = getelementptr i64, ptr %v103, i64 1
  store i64 1, ptr %v104, align 1
  %v105 = getelementptr i64, ptr %roots, i64 9
  store i64 %v94, ptr %v105, align 1
  %v106 = getelementptr i64, ptr %roots, i64 10
  store i64 %v85, ptr %v106, align 1
  %v107 = getelementptr i64, ptr %roots, i64 11
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v107, align 1
  %v108 = getelementptr i64, ptr %roots, i64 2
  store i64 9, ptr %v108, align 1
  %v109 = call i64 @native_alloc(i64 16)
  %v110 = icmp ne i64 %v109, 0
  br i1 %v110, label %ok112, label %trap111
trap111:
  call void @native_trap()
  unreachable
ok112:
  %v113 = inttoptr i64 %v109 to ptr
  %v114 = getelementptr i64, ptr %v113, i64 0
  store i64 38, ptr %v114, align 1
  %v115 = icmp ne i64 %v109, 0
  br i1 %v115, label %ok117, label %trap116
trap116:
  call void @native_trap()
  unreachable
ok117:
  %v118 = inttoptr i64 %v109 to ptr
  %v119 = getelementptr i64, ptr %v118, i64 1
  store i64 %v94, ptr %v119, align 1
  %v120 = getelementptr i64, ptr %roots, i64 9
  store i64 %v109, ptr %v120, align 1
  %v121 = getelementptr i64, ptr %roots, i64 10
  store i64 %v85, ptr %v121, align 1
  %v122 = getelementptr i64, ptr %roots, i64 11
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v122, align 1
  %v123 = getelementptr i64, ptr %roots, i64 2
  store i64 9, ptr %v123, align 1
  %v124 = call i64 @native_alloc(i64 16)
  %v125 = icmp ne i64 %v124, 0
  br i1 %v125, label %ok127, label %trap126
trap126:
  call void @native_trap()
  unreachable
ok127:
  %v128 = inttoptr i64 %v124 to ptr
  %v129 = getelementptr i64, ptr %v128, i64 0
  store i64 34, ptr %v129, align 1
  %v130 = icmp ne i64 %v124, 0
  br i1 %v130, label %ok132, label %trap131
trap131:
  call void @native_trap()
  unreachable
ok132:
  %v133 = inttoptr i64 %v124 to ptr
  %v134 = getelementptr i64, ptr %v133, i64 1
  store i64 701, ptr %v134, align 1
  %v135 = getelementptr i64, ptr %roots, i64 9
  store i64 %v124, ptr %v135, align 1
  %v136 = getelementptr i64, ptr %roots, i64 10
  store i64 %v109, ptr %v136, align 1
  %v137 = getelementptr i64, ptr %roots, i64 11
  store i64 %v85, ptr %v137, align 1
  %v138 = getelementptr i64, ptr %roots, i64 12
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v138, align 1
  %v139 = getelementptr i64, ptr %roots, i64 2
  store i64 10, ptr %v139, align 1
  %v140 = call i64 @native_alloc(i64 16)
  %v141 = icmp ne i64 %v140, 0
  br i1 %v141, label %ok143, label %trap142
trap142:
  call void @native_trap()
  unreachable
ok143:
  %v144 = inttoptr i64 %v140 to ptr
  %v145 = getelementptr i64, ptr %v144, i64 0
  store i64 34, ptr %v145, align 1
  %v146 = icmp ne i64 %v140, 0
  br i1 %v146, label %ok148, label %trap147
trap147:
  call void @native_trap()
  unreachable
ok148:
  %v149 = inttoptr i64 %v140 to ptr
  %v150 = getelementptr i64, ptr %v149, i64 1
  store i64 743483, ptr %v150, align 1
  %v151 = getelementptr i64, ptr %roots, i64 9
  store i64 %v140, ptr %v151, align 1
  %v152 = getelementptr i64, ptr %roots, i64 10
  store i64 %v124, ptr %v152, align 1
  %v153 = getelementptr i64, ptr %roots, i64 11
  store i64 %v109, ptr %v153, align 1
  %v154 = getelementptr i64, ptr %roots, i64 12
  store i64 %v85, ptr %v154, align 1
  %v155 = getelementptr i64, ptr %roots, i64 13
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v155, align 1
  %v156 = getelementptr i64, ptr %roots, i64 2
  store i64 11, ptr %v156, align 1
  %v157 = call i64 @native_alloc(i64 16)
  %v158 = icmp ne i64 %v157, 0
  br i1 %v158, label %ok160, label %trap159
trap159:
  call void @native_trap()
  unreachable
ok160:
  %v161 = inttoptr i64 %v157 to ptr
  %v162 = getelementptr i64, ptr %v161, i64 0
  store i64 34, ptr %v162, align 1
  %v163 = icmp ne i64 %v157, 0
  br i1 %v163, label %ok165, label %trap164
trap164:
  call void @native_trap()
  unreachable
ok165:
  %v166 = inttoptr i64 %v157 to ptr
  %v167 = getelementptr i64, ptr %v166, i64 1
  store i64 524287, ptr %v167, align 1
  %v168 = getelementptr i64, ptr %roots, i64 9
  store i64 %v157, ptr %v168, align 1
  %v169 = getelementptr i64, ptr %roots, i64 10
  store i64 %v140, ptr %v169, align 1
  %v170 = getelementptr i64, ptr %roots, i64 11
  store i64 %v124, ptr %v170, align 1
  %v171 = getelementptr i64, ptr %roots, i64 12
  store i64 %v109, ptr %v171, align 1
  %v172 = getelementptr i64, ptr %roots, i64 13
  store i64 %v85, ptr %v172, align 1
  %v173 = getelementptr i64, ptr %roots, i64 14
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v173, align 1
  %v174 = getelementptr i64, ptr %roots, i64 2
  store i64 12, ptr %v174, align 1
  %v175 = call i64 @native_alloc(i64 8)
  %v176 = icmp ne i64 %v175, 0
  br i1 %v176, label %ok178, label %trap177
trap177:
  call void @native_trap()
  unreachable
ok178:
  %v179 = inttoptr i64 %v175 to ptr
  %v180 = getelementptr i64, ptr %v179, i64 0
  store i64 30, ptr %v180, align 1
  %v181 = getelementptr i64, ptr %roots, i64 9
  store i64 %v175, ptr %v181, align 1
  %v182 = getelementptr i64, ptr %roots, i64 10
  store i64 %v157, ptr %v182, align 1
  %v183 = getelementptr i64, ptr %roots, i64 11
  store i64 %v140, ptr %v183, align 1
  %v184 = getelementptr i64, ptr %roots, i64 12
  store i64 %v124, ptr %v184, align 1
  %v185 = getelementptr i64, ptr %roots, i64 13
  store i64 %v109, ptr %v185, align 1
  %v186 = getelementptr i64, ptr %roots, i64 14
  store i64 %v85, ptr %v186, align 1
  %v187 = getelementptr i64, ptr %roots, i64 15
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v187, align 1
  %v188 = getelementptr i64, ptr %roots, i64 2
  store i64 13, ptr %v188, align 1
  %v189 = call i64 @native_alloc(i64 56)
  %v190 = icmp ne i64 %v189, 0
  br i1 %v190, label %ok192, label %trap191
trap191:
  call void @native_trap()
  unreachable
ok192:
  %v193 = inttoptr i64 %v189 to ptr
  %v194 = getelementptr i64, ptr %v193, i64 0
  store i64 26, ptr %v194, align 1
  %v195 = icmp ne i64 %v189, 0
  br i1 %v195, label %ok197, label %trap196
trap196:
  call void @native_trap()
  unreachable
ok197:
  %v198 = inttoptr i64 %v189 to ptr
  %v199 = getelementptr i64, ptr %v198, i64 1
  store i64 %v85, ptr %v199, align 1
  %v200 = icmp ne i64 %v189, 0
  br i1 %v200, label %ok202, label %trap201
trap201:
  call void @native_trap()
  unreachable
ok202:
  %v203 = inttoptr i64 %v189 to ptr
  %v204 = getelementptr i64, ptr %v203, i64 2
  store i64 %v109, ptr %v204, align 1
  %v205 = icmp ne i64 %v189, 0
  br i1 %v205, label %ok207, label %trap206
trap206:
  call void @native_trap()
  unreachable
ok207:
  %v208 = inttoptr i64 %v189 to ptr
  %v209 = getelementptr i64, ptr %v208, i64 3
  store i64 %v124, ptr %v209, align 1
  %v210 = icmp ne i64 %v189, 0
  br i1 %v210, label %ok212, label %trap211
trap211:
  call void @native_trap()
  unreachable
ok212:
  %v213 = inttoptr i64 %v189 to ptr
  %v214 = getelementptr i64, ptr %v213, i64 4
  store i64 %v140, ptr %v214, align 1
  %v215 = icmp ne i64 %v189, 0
  br i1 %v215, label %ok217, label %trap216
trap216:
  call void @native_trap()
  unreachable
ok217:
  %v218 = inttoptr i64 %v189 to ptr
  %v219 = getelementptr i64, ptr %v218, i64 5
  store i64 %v157, ptr %v219, align 1
  %v220 = icmp ne i64 %v189, 0
  br i1 %v220, label %ok222, label %trap221
trap221:
  call void @native_trap()
  unreachable
ok222:
  %v223 = inttoptr i64 %v189 to ptr
  %v224 = getelementptr i64, ptr %v223, i64 6
  store i64 %v175, ptr %v224, align 1
  %v225 = getelementptr i64, ptr %roots, i64 9
  store i64 %v189, ptr %v225, align 1
  %v226 = getelementptr i64, ptr %roots, i64 10
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v226, align 1
  %v227 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v227, align 1
  %v228 = call i64 @native_alloc(i64 24)
  %v229 = icmp ne i64 %v228, 0
  br i1 %v229, label %ok231, label %trap230
trap230:
  call void @native_trap()
  unreachable
ok231:
  %v232 = inttoptr i64 %v228 to ptr
  %v233 = getelementptr i64, ptr %v232, i64 0
  store i64 194, ptr %v233, align 1
  %v234 = icmp ne i64 %v228, 0
  br i1 %v234, label %ok236, label %trap235
trap235:
  call void @native_trap()
  unreachable
ok236:
  %v237 = inttoptr i64 %v228 to ptr
  %v238 = getelementptr i64, ptr %v237, i64 1
  store i64 ptrtoint (ptr @ref.21 to i64), ptr %v238, align 1
  %v239 = icmp ne i64 %v228, 0
  br i1 %v239, label %ok241, label %trap240
trap240:
  call void @native_trap()
  unreachable
ok241:
  %v242 = inttoptr i64 %v228 to ptr
  %v243 = getelementptr i64, ptr %v242, i64 2
  store i64 %v189, ptr %v243, align 1
  store i64 %v228, ptr %v7, align 1
  %v244 = icmp ne i64 %v228, 0
  br i1 %v244, label %ok246, label %trap245
trap245:
  call void @native_trap()
  unreachable
ok246:
  %v247 = inttoptr i64 %v228 to ptr
  %v248 = getelementptr i64, ptr %v247, i64 2
  %v249 = load i64, ptr %v248, align 1
  %v250 = getelementptr i64, ptr %roots, i64 9
  store i64 %v249, ptr %v250, align 1
  %v251 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v251, align 1
  %v252 = call tailcc i64 @f.21(i64 %v249, i64 10)
  store i64 %v252, ptr %slot5, align 1
  %v253 = load i32, ptr @g.8, align 1
  %v254 = icmp eq i32 %v253, 0
  %v255 = zext i1 %v254 to i32
  %v259 = icmp ne i32 %v255, 0
  br i1 %v259, label %then258, label %else257
then258:
  call void @native_trap()
  unreachable
else257:
  br label %block256
block256:
  %v260 = load i64, ptr @g.7, align 1
  %v261 = icmp ne i64 %v260, 0
  br i1 %v261, label %ok263, label %trap262
trap262:
  call void @native_trap()
  unreachable
ok263:
  %v264 = load i64, ptr %slot5, align 1
  %v265 = icmp ugt i64 %v264, 4294967295
  %v266 = zext i1 %v265 to i32
  %v270 = icmp ne i32 %v266, 0
  br i1 %v270, label %then269, label %else268
then269:
  call void @native_trap()
  unreachable
else268:
  br label %block267
block267:
  %v271 = load i64, ptr %v7, align 1
  %v272 = load i64, ptr %slot5, align 1
  %v273 = load i64, ptr %slot5, align 1
  %v274 = trunc i64 %v273 to i32
  %v275 = getelementptr i64, ptr %roots, i64 9
  store i64 %v271, ptr %v275, align 1
  %v276 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v276, align 1
  %v277 = zext i32 0 to i64
  %v278 = call i64 @native_array_new(i64 87, i32 %v274, i64 %v277)
  %v279 = getelementptr i64, ptr %roots, i64 9
  store i64 %v278, ptr %v279, align 1
  %v280 = getelementptr i64, ptr %roots, i64 10
  store i64 %v271, ptr %v280, align 1
  %v281 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v281, align 1
  %v282 = call i64 @native_alloc(i64 16)
  %v283 = icmp ne i64 %v282, 0
  br i1 %v283, label %ok285, label %trap284
trap284:
  call void @native_trap()
  unreachable
ok285:
  %v286 = inttoptr i64 %v282 to ptr
  %v287 = getelementptr i64, ptr %v286, i64 0
  store i64 94, ptr %v287, align 1
  %v288 = icmp ne i64 %v282, 0
  br i1 %v288, label %ok290, label %trap289
trap289:
  call void @native_trap()
  unreachable
ok290:
  %v291 = inttoptr i64 %v282 to ptr
  %v292 = getelementptr i64, ptr %v291, i64 1
  store i64 %v278, ptr %v292, align 1
  %v293 = getelementptr i64, ptr %roots, i64 9
  store i64 %v271, ptr %v293, align 1
  %v294 = getelementptr i64, ptr %roots, i64 10
  store i64 %v282, ptr %v294, align 1
  %v295 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v295, align 1
  %v296 = call tailcc i64 @f.23(i64 %v271, i32 1, i64 %v272, i64 %v282, i32 0, i32 1, i64 0)
  store i64 %v296, ptr %v8, align 1
  %v297 = load i32, ptr @g.30, align 1
  %v298 = icmp eq i32 %v297, 0
  %v299 = zext i1 %v298 to i32
  %v303 = icmp ne i32 %v299, 0
  br i1 %v303, label %then302, label %else301
then302:
  call void @native_trap()
  unreachable
else301:
  br label %block300
block300:
  %v304 = load i64, ptr @g.29, align 1
  %v305 = icmp ne i64 %v304, 0
  br i1 %v305, label %ok307, label %trap306
trap306:
  call void @native_trap()
  unreachable
ok307:
  %v308 = load i32, ptr @g.42, align 1
  %v309 = icmp eq i32 %v308, 0
  %v310 = zext i1 %v309 to i32
  %v314 = icmp ne i32 %v310, 0
  br i1 %v314, label %then313, label %else312
then313:
  call void @native_trap()
  unreachable
else312:
  br label %block311
block311:
  %v315 = load i64, ptr @g.41, align 1
  %v316 = icmp ne i64 %v315, 0
  br i1 %v316, label %ok318, label %trap317
trap317:
  call void @native_trap()
  unreachable
ok318:
  %v319 = load i32, ptr @g.28, align 1
  %v320 = icmp eq i32 %v319, 0
  %v321 = zext i1 %v320 to i32
  %v325 = icmp ne i32 %v321, 0
  br i1 %v325, label %then324, label %else323
then324:
  call void @native_trap()
  unreachable
else323:
  br label %block322
block322:
  %v326 = load i64, ptr @g.27, align 1
  %v327 = icmp ne i64 %v326, 0
  br i1 %v327, label %ok329, label %trap328
trap328:
  call void @native_trap()
  unreachable
ok329:
  %v330 = load i64, ptr %v8, align 1
  %v331 = load i64, ptr %v8, align 1
  %v332 = icmp ne i64 %v331, 0
  br i1 %v332, label %ok334, label %trap333
trap333:
  call void @native_trap()
  unreachable
ok334:
  %v335 = inttoptr i64 %v331 to ptr
  %v336 = getelementptr i64, ptr %v335, i64 1
  %v337 = load i64, ptr %v336, align 1
  %v338 = call i32 @native_array_length(i64 %v337)
  %v339 = zext i32 %v338 to i64
  %v340 = getelementptr i64, ptr %roots, i64 9
  store i64 %v330, ptr %v340, align 1
  %v341 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v341, align 1
  %v342 = call tailcc i64 @f.5(i64 %v330, i64 %v339)
  store i64 %v342, ptr %v10, align 1
  %v343 = getelementptr i64, ptr %roots, i64 9
  store i64 %v342, ptr %v343, align 1
  %v344 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v344, align 1
  %v345 = call tailcc i64 @f.16(i64 %v342)
  store i64 %v345, ptr %v9, align 1
  %v346 = load i32, ptr @g.28, align 1
  %v347 = icmp eq i32 %v346, 0
  %v348 = zext i1 %v347 to i32
  %v352 = icmp ne i32 %v348, 0
  br i1 %v352, label %then351, label %else350
then351:
  call void @native_trap()
  unreachable
else350:
  br label %block349
block349:
  %v353 = load i64, ptr @g.27, align 1
  %v354 = icmp ne i64 %v353, 0
  br i1 %v354, label %ok356, label %trap355
trap355:
  call void @native_trap()
  unreachable
ok356:
  %v357 = load i64, ptr %v9, align 1
  %v358 = load i64, ptr %v9, align 1
  %v359 = icmp ne i64 %v358, 0
  br i1 %v359, label %ok361, label %trap360
trap360:
  call void @native_trap()
  unreachable
ok361:
  %v362 = inttoptr i64 %v358 to ptr
  %v363 = getelementptr i64, ptr %v362, i64 1
  %v364 = load i64, ptr %v363, align 1
  %v365 = call i32 @native_array_length(i64 %v364)
  %v366 = zext i32 %v365 to i64
  %v367 = getelementptr i64, ptr %roots, i64 9
  store i64 %v357, ptr %v367, align 1
  %v368 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v368, align 1
  %v369 = call tailcc i64 @f.5(i64 %v357, i64 %v366)
  store i64 %v369, ptr %v11, align 1
  %v370 = load i32, ptr @g.6, align 1
  %v371 = icmp eq i32 %v370, 0
  %v372 = zext i1 %v371 to i32
  %v376 = icmp ne i32 %v372, 0
  br i1 %v376, label %then375, label %else374
then375:
  call void @native_trap()
  unreachable
else374:
  br label %block373
block373:
  %v377 = load i64, ptr @g.5, align 1
  %v378 = icmp ne i64 %v377, 0
  br i1 %v378, label %ok380, label %trap379
trap379:
  call void @native_trap()
  unreachable
ok380:
  %v383 = load i64, ptr %v10, align 1
  %v384 = icmp ne i64 %v383, 0
  br i1 %v384, label %ok386, label %trap385
trap385:
  call void @native_trap()
  unreachable
ok386:
  %v387 = inttoptr i64 %v383 to ptr
  %v388 = getelementptr i64, ptr %v387, i64 2
  %v389 = load i32, ptr %v388, align 1
  %v390 = zext i32 %v389 to i64
  %v391 = load i64, ptr %v11, align 1
  %v392 = icmp ne i64 %v391, 0
  br i1 %v392, label %ok394, label %trap393
trap393:
  call void @native_trap()
  unreachable
ok394:
  %v395 = inttoptr i64 %v391 to ptr
  %v396 = getelementptr i64, ptr %v395, i64 2
  %v397 = load i32, ptr %v396, align 1
  %v398 = zext i32 %v397 to i64
  %v399 = icmp eq i64 %v390, %v398
  %v400 = zext i1 %v399 to i32
  %v405 = icmp ne i32 %v400, 0
  br i1 %v405, label %then404, label %else403
then404:
  %v406 = load i64, ptr %v10, align 1
  %v407 = load i64, ptr %v11, align 1
  %v408 = getelementptr i64, ptr %roots, i64 9
  store i64 %v406, ptr %v408, align 1
  %v409 = getelementptr i64, ptr %roots, i64 10
  store i64 %v407, ptr %v409, align 1
  %v410 = getelementptr i64, ptr %roots, i64 2
  store i64 8, ptr %v410, align 1
  %v411 = call tailcc i32 @f.4(i64 %v406, i64 %v407, i32 0, i32 1, i64 0)
  store i32 %v411, ptr %slot401, align 1
  br label %block402
else403:
  store i32 0, ptr %slot401, align 1
  br label %block402
block402:
  %v412 = load i32, ptr %slot401, align 1
  store i32 %v412, ptr %slot13, align 1
  %v413 = load i32, ptr @g.58, align 1
  %v414 = icmp eq i32 %v413, 0
  %v415 = zext i1 %v414 to i32
  %v419 = icmp ne i32 %v415, 0
  br i1 %v419, label %then418, label %else417
then418:
  call void @native_trap()
  unreachable
else417:
  br label %block416
block416:
  %v420 = load i64, ptr @g.57, align 1
  %v421 = icmp ne i64 %v420, 0
  br i1 %v421, label %ok423, label %trap422
trap422:
  call void @native_trap()
  unreachable
ok423:
  %v424 = load i32, ptr %slot13, align 1
  store i32 %v424, ptr %slot381, align 1
  br label %block382
block382:
  %v425 = load i32, ptr %slot381, align 1
  %v426 = getelementptr i64, ptr %roots, i64 2
  store i64 6, ptr %v426, align 1
  call tailcc void @f.19(i32 %v425)
  %v427 = load i64, ptr %v7, align 1
  store i64 %v427, ptr %slot70, align 1
  br label %block71
block71:
  %v428 = load i64, ptr %slot70, align 1
  %v429 = getelementptr i64, ptr %roots, i64 9
  store i64 %v428, ptr %v429, align 1
  %v430 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v430, align 1
  %v431 = call tailcc i32 @f.24(i64 %v45, i64 %v69, i64 %v428, i32 1, i32 0, i32 1, i32 0, i32 1, i32 0, i32 1, i64 0)
  %v432 = load i32, ptr @g.56, align 1
  %v433 = icmp eq i32 %v432, 0
  %v434 = zext i1 %v433 to i32
  %v438 = icmp ne i32 %v434, 0
  br i1 %v438, label %then437, label %else436
then437:
  call void @native_trap()
  unreachable
else436:
  br label %block435
block435:
  %v439 = load i64, ptr @g.55, align 1
  %v440 = icmp ne i64 %v439, 0
  br i1 %v440, label %ok442, label %trap441
trap441:
  call void @native_trap()
  unreachable
ok442:
  %v443 = inttoptr i64 %v439 to ptr
  %v444 = getelementptr i64, ptr %v443, i64 1
  %v445 = load i64, ptr %v444, align 1
  store i64 %v445, ptr %v6, align 1
  %v446 = load i32, ptr @g.44, align 1
  %v447 = icmp eq i32 %v446, 0
  %v448 = zext i1 %v447 to i32
  %v452 = icmp ne i32 %v448, 0
  br i1 %v452, label %then451, label %else450
then451:
  call void @native_trap()
  unreachable
else450:
  br label %block449
block449:
  %v453 = load i64, ptr @g.43, align 1
  %v454 = icmp ne i64 %v453, 0
  br i1 %v454, label %ok456, label %trap455
trap455:
  call void @native_trap()
  unreachable
ok456:
  %v457 = load i64, ptr %v6, align 1
  %v458 = icmp eq i64 %v457, 0
  %v459 = zext i1 %v458 to i32
  %v464 = icmp ne i32 %v459, 0
  br i1 %v464, label %then463, label %else462
then463:
  store i64 0, ptr %slot460, align 1
  br label %block461
else462:
  %v465 = load i64, ptr %v6, align 1
  %v466 = icmp ne i64 %v465, 0
  br i1 %v466, label %ok468, label %trap467
trap467:
  call void @native_trap()
  unreachable
ok468:
  %v469 = inttoptr i64 %v465 to ptr
  %v470 = getelementptr i64, ptr %v469, i64 1
  %v471 = load i64, ptr %v470, align 1
  store i64 %v471, ptr %v6, align 1
  %v472 = icmp eq i64 %v471, 0
  %v473 = zext i1 %v472 to i32
  %v478 = icmp ne i32 %v473, 0
  br i1 %v478, label %then477, label %else476
then477:
  store i64 1, ptr %slot474, align 1
  br label %block475
else476:
  %v479 = load i64, ptr %v6, align 1
  %v480 = icmp ne i64 %v479, 0
  br i1 %v480, label %ok482, label %trap481
trap481:
  call void @native_trap()
  unreachable
ok482:
  %v483 = inttoptr i64 %v479 to ptr
  %v484 = getelementptr i64, ptr %v483, i64 1
  %v485 = load i64, ptr %v484, align 1
  store i64 %v485, ptr %v6, align 1
  %v486 = icmp eq i64 %v485, 0
  %v487 = zext i1 %v486 to i32
  %v492 = icmp ne i32 %v487, 0
  br i1 %v492, label %then491, label %else490
then491:
  store i64 2, ptr %slot488, align 1
  br label %block489
else490:
  %v493 = load i64, ptr %v6, align 1
  %v494 = icmp ne i64 %v493, 0
  br i1 %v494, label %ok496, label %trap495
trap495:
  call void @native_trap()
  unreachable
ok496:
  %v497 = inttoptr i64 %v493 to ptr
  %v498 = getelementptr i64, ptr %v497, i64 1
  %v499 = load i64, ptr %v498, align 1
  store i64 %v499, ptr %v6, align 1
  %v500 = icmp eq i64 %v499, 0
  %v501 = zext i1 %v500 to i32
  %v506 = icmp ne i32 %v501, 0
  br i1 %v506, label %then505, label %else504
then505:
  store i64 3, ptr %slot502, align 1
  br label %block503
else504:
  %v507 = load i64, ptr %v6, align 1
  %v508 = icmp ne i64 %v507, 0
  br i1 %v508, label %ok510, label %trap509
trap509:
  call void @native_trap()
  unreachable
ok510:
  %v511 = inttoptr i64 %v507 to ptr
  %v512 = getelementptr i64, ptr %v511, i64 1
  %v513 = load i64, ptr %v512, align 1
  store i64 %v513, ptr %v6, align 1
  %v514 = icmp eq i64 %v513, 0
  %v515 = zext i1 %v514 to i32
  %v520 = icmp ne i32 %v515, 0
  br i1 %v520, label %then519, label %else518
then519:
  store i64 4, ptr %slot516, align 1
  br label %block517
else518:
  %v521 = load i64, ptr %v6, align 1
  %v522 = icmp ne i64 %v521, 0
  br i1 %v522, label %ok524, label %trap523
trap523:
  call void @native_trap()
  unreachable
ok524:
  %v525 = inttoptr i64 %v521 to ptr
  %v526 = getelementptr i64, ptr %v525, i64 1
  %v527 = load i64, ptr %v526, align 1
  store i64 %v527, ptr %v6, align 1
  %v528 = icmp eq i64 %v527, 0
  %v529 = zext i1 %v528 to i32
  %v534 = icmp ne i32 %v529, 0
  br i1 %v534, label %then533, label %else532
then533:
  store i64 5, ptr %slot530, align 1
  br label %block531
else532:
  %v535 = load i64, ptr %v6, align 1
  %v536 = icmp ne i64 %v535, 0
  br i1 %v536, label %ok538, label %trap537
trap537:
  call void @native_trap()
  unreachable
ok538:
  %v539 = inttoptr i64 %v535 to ptr
  %v540 = getelementptr i64, ptr %v539, i64 1
  %v541 = load i64, ptr %v540, align 1
  store i64 %v541, ptr %v6, align 1
  %v542 = icmp eq i64 %v541, 0
  %v543 = zext i1 %v542 to i32
  %v548 = icmp ne i32 %v543, 0
  br i1 %v548, label %then547, label %else546
then547:
  store i64 6, ptr %slot544, align 1
  br label %block545
else546:
  %v549 = load i64, ptr %v6, align 1
  %v550 = icmp ne i64 %v549, 0
  br i1 %v550, label %ok552, label %trap551
trap551:
  call void @native_trap()
  unreachable
ok552:
  %v553 = inttoptr i64 %v549 to ptr
  %v554 = getelementptr i64, ptr %v553, i64 1
  %v555 = load i64, ptr %v554, align 1
  store i64 %v555, ptr %v6, align 1
  %v556 = icmp eq i64 %v555, 0
  %v557 = zext i1 %v556 to i32
  %v562 = icmp ne i32 %v557, 0
  br i1 %v562, label %then561, label %else560
then561:
  store i64 7, ptr %slot558, align 1
  br label %block559
else560:
  %v563 = load i64, ptr %v6, align 1
  %v564 = icmp ne i64 %v563, 0
  br i1 %v564, label %ok566, label %trap565
trap565:
  call void @native_trap()
  unreachable
ok566:
  %v567 = inttoptr i64 %v563 to ptr
  %v568 = getelementptr i64, ptr %v567, i64 1
  %v569 = load i64, ptr %v568, align 1
  store i64 %v569, ptr %v6, align 1
  %v570 = icmp eq i64 %v569, 0
  %v571 = zext i1 %v570 to i32
  %v576 = icmp ne i32 %v571, 0
  br i1 %v576, label %then575, label %else574
then575:
  store i64 8, ptr %slot572, align 1
  br label %block573
else574:
  %v577 = load i64, ptr %v6, align 1
  %v578 = icmp ne i64 %v577, 0
  br i1 %v578, label %ok580, label %trap579
trap579:
  call void @native_trap()
  unreachable
ok580:
  %v581 = inttoptr i64 %v577 to ptr
  %v582 = getelementptr i64, ptr %v581, i64 1
  %v583 = load i64, ptr %v582, align 1
  store i64 %v583, ptr %v6, align 1
  %v584 = icmp eq i64 %v583, 0
  %v585 = zext i1 %v584 to i32
  %v590 = icmp ne i32 %v585, 0
  br i1 %v590, label %then589, label %else588
then589:
  store i64 9, ptr %slot586, align 1
  br label %block587
else588:
  %v591 = load i64, ptr %v6, align 1
  %v592 = icmp ne i64 %v591, 0
  br i1 %v592, label %ok594, label %trap593
trap593:
  call void @native_trap()
  unreachable
ok594:
  %v595 = inttoptr i64 %v591 to ptr
  %v596 = getelementptr i64, ptr %v595, i64 1
  %v597 = load i64, ptr %v596, align 1
  store i64 %v597, ptr %v6, align 1
  %v598 = icmp eq i64 %v597, 0
  %v599 = zext i1 %v598 to i32
  %v604 = icmp ne i32 %v599, 0
  br i1 %v604, label %then603, label %else602
then603:
  store i64 10, ptr %slot600, align 1
  br label %block601
else602:
  %v605 = load i64, ptr %v6, align 1
  %v606 = icmp ne i64 %v605, 0
  br i1 %v606, label %ok608, label %trap607
trap607:
  call void @native_trap()
  unreachable
ok608:
  %v609 = inttoptr i64 %v605 to ptr
  %v610 = getelementptr i64, ptr %v609, i64 1
  %v611 = load i64, ptr %v610, align 1
  store i64 %v611, ptr %v6, align 1
  %v612 = icmp eq i64 %v611, 0
  %v613 = zext i1 %v612 to i32
  %v618 = icmp ne i32 %v613, 0
  br i1 %v618, label %then617, label %else616
then617:
  store i64 11, ptr %slot614, align 1
  br label %block615
else616:
  %v619 = load i64, ptr %v6, align 1
  %v620 = icmp ne i64 %v619, 0
  br i1 %v620, label %ok622, label %trap621
trap621:
  call void @native_trap()
  unreachable
ok622:
  %v623 = inttoptr i64 %v619 to ptr
  %v624 = getelementptr i64, ptr %v623, i64 1
  %v625 = load i64, ptr %v624, align 1
  store i64 %v625, ptr %v6, align 1
  %v626 = icmp eq i64 %v625, 0
  %v627 = zext i1 %v626 to i32
  %v632 = icmp ne i32 %v627, 0
  br i1 %v632, label %then631, label %else630
then631:
  store i64 12, ptr %slot628, align 1
  br label %block629
else630:
  %v633 = load i64, ptr %v6, align 1
  %v634 = icmp ne i64 %v633, 0
  br i1 %v634, label %ok636, label %trap635
trap635:
  call void @native_trap()
  unreachable
ok636:
  %v637 = inttoptr i64 %v633 to ptr
  %v638 = getelementptr i64, ptr %v637, i64 1
  %v639 = load i64, ptr %v638, align 1
  store i64 %v639, ptr %v6, align 1
  %v640 = icmp eq i64 %v639, 0
  %v641 = zext i1 %v640 to i32
  %v646 = icmp ne i32 %v641, 0
  br i1 %v646, label %then645, label %else644
then645:
  store i64 13, ptr %slot642, align 1
  br label %block643
else644:
  %v647 = load i64, ptr %v6, align 1
  %v648 = icmp ne i64 %v647, 0
  br i1 %v648, label %ok650, label %trap649
trap649:
  call void @native_trap()
  unreachable
ok650:
  %v651 = inttoptr i64 %v647 to ptr
  %v652 = getelementptr i64, ptr %v651, i64 1
  %v653 = load i64, ptr %v652, align 1
  store i64 %v653, ptr %v6, align 1
  %v654 = icmp eq i64 %v653, 0
  %v655 = zext i1 %v654 to i32
  %v660 = icmp ne i32 %v655, 0
  br i1 %v660, label %then659, label %else658
then659:
  store i64 14, ptr %slot656, align 1
  br label %block657
else658:
  %v661 = load i64, ptr %v6, align 1
  %v662 = icmp ne i64 %v661, 0
  br i1 %v662, label %ok664, label %trap663
trap663:
  call void @native_trap()
  unreachable
ok664:
  %v665 = inttoptr i64 %v661 to ptr
  %v666 = getelementptr i64, ptr %v665, i64 1
  %v667 = load i64, ptr %v666, align 1
  store i64 %v667, ptr %v6, align 1
  %v668 = icmp eq i64 %v667, 0
  %v669 = zext i1 %v668 to i32
  %v674 = icmp ne i32 %v669, 0
  br i1 %v674, label %then673, label %else672
then673:
  store i64 15, ptr %slot670, align 1
  br label %block671
else672:
  %v675 = load i64, ptr %v6, align 1
  %v676 = icmp ne i64 %v675, 0
  br i1 %v676, label %ok678, label %trap677
trap677:
  call void @native_trap()
  unreachable
ok678:
  %v679 = inttoptr i64 %v675 to ptr
  %v680 = getelementptr i64, ptr %v679, i64 1
  %v681 = load i64, ptr %v680, align 1
  store i64 %v681, ptr %v6, align 1
  %v682 = icmp eq i64 %v681, 0
  %v683 = zext i1 %v682 to i32
  %v688 = icmp ne i32 %v683, 0
  br i1 %v688, label %then687, label %else686
then687:
  store i64 16, ptr %slot684, align 1
  br label %block685
else686:
  %v689 = load i64, ptr %v6, align 1
  %v690 = icmp ne i64 %v689, 0
  br i1 %v690, label %ok692, label %trap691
trap691:
  call void @native_trap()
  unreachable
ok692:
  %v693 = inttoptr i64 %v689 to ptr
  %v694 = getelementptr i64, ptr %v693, i64 1
  %v695 = load i64, ptr %v694, align 1
  store i64 %v695, ptr %v6, align 1
  %v696 = icmp eq i64 %v695, 0
  %v697 = zext i1 %v696 to i32
  %v702 = icmp ne i32 %v697, 0
  br i1 %v702, label %then701, label %else700
then701:
  store i64 17, ptr %slot698, align 1
  br label %block699
else700:
  %v703 = load i64, ptr %v6, align 1
  %v704 = icmp ne i64 %v703, 0
  br i1 %v704, label %ok706, label %trap705
trap705:
  call void @native_trap()
  unreachable
ok706:
  %v707 = inttoptr i64 %v703 to ptr
  %v708 = getelementptr i64, ptr %v707, i64 1
  %v709 = load i64, ptr %v708, align 1
  store i64 %v709, ptr %v6, align 1
  %v710 = icmp eq i64 %v709, 0
  %v711 = zext i1 %v710 to i32
  %v716 = icmp ne i32 %v711, 0
  br i1 %v716, label %then715, label %else714
then715:
  store i64 18, ptr %slot712, align 1
  br label %block713
else714:
  %v717 = load i64, ptr %v6, align 1
  %v718 = icmp ne i64 %v717, 0
  br i1 %v718, label %ok720, label %trap719
trap719:
  call void @native_trap()
  unreachable
ok720:
  %v721 = inttoptr i64 %v717 to ptr
  %v722 = getelementptr i64, ptr %v721, i64 1
  %v723 = load i64, ptr %v722, align 1
  store i64 %v723, ptr %v6, align 1
  %v724 = icmp eq i64 %v723, 0
  %v725 = zext i1 %v724 to i32
  %v730 = icmp ne i32 %v725, 0
  br i1 %v730, label %then729, label %else728
then729:
  store i64 19, ptr %slot726, align 1
  br label %block727
else728:
  %v731 = load i64, ptr %v6, align 1
  %v732 = icmp ne i64 %v731, 0
  br i1 %v732, label %ok734, label %trap733
trap733:
  call void @native_trap()
  unreachable
ok734:
  %v735 = inttoptr i64 %v731 to ptr
  %v736 = getelementptr i64, ptr %v735, i64 1
  %v737 = load i64, ptr %v736, align 1
  store i64 %v737, ptr %v6, align 1
  %v738 = icmp eq i64 %v737, 0
  %v739 = zext i1 %v738 to i32
  %v744 = icmp ne i32 %v739, 0
  br i1 %v744, label %then743, label %else742
then743:
  store i64 20, ptr %slot740, align 1
  br label %block741
else742:
  %v745 = load i64, ptr %v6, align 1
  %v746 = icmp ne i64 %v745, 0
  br i1 %v746, label %ok748, label %trap747
trap747:
  call void @native_trap()
  unreachable
ok748:
  %v749 = inttoptr i64 %v745 to ptr
  %v750 = getelementptr i64, ptr %v749, i64 1
  %v751 = load i64, ptr %v750, align 1
  store i64 %v751, ptr %v6, align 1
  %v752 = icmp eq i64 %v751, 0
  %v753 = zext i1 %v752 to i32
  %v758 = icmp ne i32 %v753, 0
  br i1 %v758, label %then757, label %else756
then757:
  store i64 21, ptr %slot754, align 1
  br label %block755
else756:
  %v759 = load i64, ptr %v6, align 1
  %v760 = icmp ne i64 %v759, 0
  br i1 %v760, label %ok762, label %trap761
trap761:
  call void @native_trap()
  unreachable
ok762:
  %v763 = inttoptr i64 %v759 to ptr
  %v764 = getelementptr i64, ptr %v763, i64 1
  %v765 = load i64, ptr %v764, align 1
  store i64 %v765, ptr %v6, align 1
  %v766 = icmp eq i64 %v765, 0
  %v767 = zext i1 %v766 to i32
  %v772 = icmp ne i32 %v767, 0
  br i1 %v772, label %then771, label %else770
then771:
  store i64 22, ptr %slot768, align 1
  br label %block769
else770:
  %v773 = load i64, ptr %v6, align 1
  %v774 = icmp ne i64 %v773, 0
  br i1 %v774, label %ok776, label %trap775
trap775:
  call void @native_trap()
  unreachable
ok776:
  %v777 = inttoptr i64 %v773 to ptr
  %v778 = getelementptr i64, ptr %v777, i64 1
  %v779 = load i64, ptr %v778, align 1
  store i64 %v779, ptr %v6, align 1
  %v780 = icmp eq i64 %v779, 0
  %v781 = zext i1 %v780 to i32
  %v786 = icmp ne i32 %v781, 0
  br i1 %v786, label %then785, label %else784
then785:
  store i64 23, ptr %slot782, align 1
  br label %block783
else784:
  %v787 = load i64, ptr %v6, align 1
  %v788 = icmp ne i64 %v787, 0
  br i1 %v788, label %ok790, label %trap789
trap789:
  call void @native_trap()
  unreachable
ok790:
  %v791 = inttoptr i64 %v787 to ptr
  %v792 = getelementptr i64, ptr %v791, i64 1
  %v793 = load i64, ptr %v792, align 1
  %v794 = getelementptr i64, ptr %roots, i64 9
  store i64 %v793, ptr %v794, align 1
  %v795 = getelementptr i64, ptr %roots, i64 2
  store i64 7, ptr %v795, align 1
  %v796 = call tailcc i64 @f.27(i32 0, i32 1, i64 %v793, i64 24)
  store i64 %v796, ptr %slot782, align 1
  br label %block783
block783:
  %v797 = load i64, ptr %slot782, align 1
  store i64 %v797, ptr %slot768, align 1
  br label %block769
block769:
  %v798 = load i64, ptr %slot768, align 1
  store i64 %v798, ptr %slot754, align 1
  br label %block755
block755:
  %v799 = load i64, ptr %slot754, align 1
  store i64 %v799, ptr %slot740, align 1
  br label %block741
block741:
  %v800 = load i64, ptr %slot740, align 1
  store i64 %v800, ptr %slot726, align 1
  br label %block727
block727:
  %v801 = load i64, ptr %slot726, align 1
  store i64 %v801, ptr %slot712, align 1
  br label %block713
block713:
  %v802 = load i64, ptr %slot712, align 1
  store i64 %v802, ptr %slot698, align 1
  br label %block699
block699:
  %v803 = load i64, ptr %slot698, align 1
  store i64 %v803, ptr %slot684, align 1
  br label %block685
block685:
  %v804 = load i64, ptr %slot684, align 1
  store i64 %v804, ptr %slot670, align 1
  br label %block671
block671:
  %v805 = load i64, ptr %slot670, align 1
  store i64 %v805, ptr %slot656, align 1
  br label %block657
block657:
  %v806 = load i64, ptr %slot656, align 1
  store i64 %v806, ptr %slot642, align 1
  br label %block643
block643:
  %v807 = load i64, ptr %slot642, align 1
  store i64 %v807, ptr %slot628, align 1
  br label %block629
block629:
  %v808 = load i64, ptr %slot628, align 1
  store i64 %v808, ptr %slot614, align 1
  br label %block615
block615:
  %v809 = load i64, ptr %slot614, align 1
  store i64 %v809, ptr %slot600, align 1
  br label %block601
block601:
  %v810 = load i64, ptr %slot600, align 1
  store i64 %v810, ptr %slot586, align 1
  br label %block587
block587:
  %v811 = load i64, ptr %slot586, align 1
  store i64 %v811, ptr %slot572, align 1
  br label %block573
block573:
  %v812 = load i64, ptr %slot572, align 1
  store i64 %v812, ptr %slot558, align 1
  br label %block559
block559:
  %v813 = load i64, ptr %slot558, align 1
  store i64 %v813, ptr %slot544, align 1
  br label %block545
block545:
  %v814 = load i64, ptr %slot544, align 1
  store i64 %v814, ptr %slot530, align 1
  br label %block531
block531:
  %v815 = load i64, ptr %slot530, align 1
  store i64 %v815, ptr %slot516, align 1
  br label %block517
block517:
  %v816 = load i64, ptr %slot516, align 1
  store i64 %v816, ptr %slot502, align 1
  br label %block503
block503:
  %v817 = load i64, ptr %slot502, align 1
  store i64 %v817, ptr %slot488, align 1
  br label %block489
block489:
  %v818 = load i64, ptr %slot488, align 1
  store i64 %v818, ptr %slot474, align 1
  br label %block475
block475:
  %v819 = load i64, ptr %slot474, align 1
  store i64 %v819, ptr %slot460, align 1
  br label %block461
block461:
  %v820 = load i64, ptr %slot460, align 1
  store i64 %v820, ptr %slot5, align 1
  %v821 = load i32, ptr %slot3, align 1
  %v822 = icmp eq i32 %v821, 0
  %v823 = zext i1 %v822 to i32
  %v827 = icmp ne i32 %v823, 0
  br i1 %v827, label %then826, label %else825
then826:
  call void @native_trap()
  unreachable
else825:
  br label %block824
block824:
  %v828 = load i64, ptr %slot1, align 1
  %v829 = load i32, ptr %slot2, align 1
  %v830 = load i32, ptr %slot3, align 1
  %v831 = load i64, ptr %slot4, align 1
  %v832 = add i64 %v831, 1
  %v833 = load i64, ptr %slot5, align 1
  call void @native_roots_leave(ptr %roots)
  %v834 = tail call tailcc i64 @f.26(i64 %v828, i32 %v829, i32 %v830, i64 %v832, i64 %v833)
  ret i64 %v834
else22:
  %v835 = load i64, ptr %slot4, align 1
  %v836 = icmp sgt i64 %v835, 0
  %v837 = zext i1 %v836 to i32
  %v842 = icmp ne i32 %v837, 0
  br i1 %v842, label %then841, label %else840
then841:
  %v843 = load i32, ptr @g.66, align 1
  %v844 = icmp eq i32 %v843, 0
  %v845 = zext i1 %v844 to i32
  %v849 = icmp ne i32 %v845, 0
  br i1 %v849, label %then848, label %else847
then848:
  call void @native_trap()
  unreachable
else847:
  br label %block846
block846:
  %v850 = load i64, ptr @g.65, align 1
  %v851 = load i64, ptr %slot5, align 1
  %v852 = icmp eq i64 %v850, %v851
  %v853 = zext i1 %v852 to i32
  store i32 %v853, ptr %slot838, align 1
  br label %block839
else840:
  store i32 0, ptr %slot838, align 1
  br label %block839
block839:
  %v854 = load i32, ptr %slot838, align 1
  %v855 = icmp ne i32 %v854, 0
  %v856 = zext i1 %v855 to i32
  %v857 = zext i32 %v856 to i64
  store i64 %v857, ptr %slot20, align 1
  br label %block21
block21:
  %v858 = load i64, ptr %slot20, align 1
  store i64 %v858, ptr %slot14, align 1
  br label %return15
return15:
  %v859 = load i64, ptr %slot14, align 1
  call void @native_roots_leave(ptr %roots)
  ret i64 %v859
}
