## FIXME: CMake integration broken

# Environment variable arguments:
# - CLANG_PATH: filepath to `clang.exe` on Windows, `clang` on *nix
# - SNAIL_SCHEME_LIBRARY_FILEPATH

clang=${CLANG_PATH}
includes=-I../../inc/
cflags=-S -emit-llvm -std=c++20
sources=${SNAIL_SCHEME_LIBRARY_FILEPATH} ss-stdlib.cc

## Phony targets
#

.PHONY: all clean

all: ss-stdlib.x86_64.ll snail_scheme_library_reference.txt
# all: snail_scheme_library_reference.txt
# all: ss-stdlib.x86_64.ll

clean:
	rm ss-stdlib.x86_64.ll snail_scheme_library_reference.txt

## Real targets
#

ss-stdlib.x86_64.ll: $(sources) snail_scheme_library_reference.txt
	echo \${SNAIL_SCHEME_LIBRARY_FILEPATH}
	$(clang) $(cflags) -target x86_64-pc-windows-msvc $(sources) $(includes) -o ss-stdlib.x86_64.ll

snail_scheme_library_reference.txt:
	echo "INFO: Using compiled snail-scheme at ${SNAIL_SCHEME_LIBRARY_FILEPATH}" > snail_scheme_library_reference.txt
