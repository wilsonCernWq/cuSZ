cmake_minimum_required(VERSION 3.18)

project(cusz_asap CUDA CXX)
set(CMAKE_CUDA_STANDARD 14)
set(CMAKE_CXX_STANDARD 14)

## uncomment for pre-Turing
# set(CMAKE_CUDA_ARCHITECTURES 60 62 70 72)
## uncomment for V100
# set(CMAKE_CUDA_ARCHITECTURES 70)
## uncomment for Turing
set(CMAKE_CUDA_ARCHITECTURES 75)
## uncmoment for Ampere
# set(CMAKE_CUDA_ARCHITECTURES 80 86)
## uncmoment for A100
# set(CMAKE_CUDA_ARCHITECTURES 80)

enable_language(CUDA)

include_directories(${CMAKE_SOURCE_DIR}/../src)

set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --extended-lambda --expt-relaxed-constexpr -Wno-deprecated-declarations")

set(LIB_TYPE SHARED)

add_library(minimalhuff ${LIB_TYPE} ../src/wrapper/huffman_coarse.cu ../src/wrapper/huffman_parbook.cu)
target_link_libraries(minimalhuff -lcusparse)
set_target_properties(minimalhuff PROPERTIES CUDA_SEPARABLE_COMPILATION ON)

add_executable(test-huffcoarse src/ex_api_huffcoarse.cu)
target_link_libraries(test-huffcoarse minimalhuff)


add_library(minimalcsr ${LIB_TYPE} ../src/wrapper/csr11.cu)
target_link_libraries(minimalcsr -lcusparse)

add_executable(test-csr src/ex_api_csr11.cu)
target_link_libraries(test-csr minimalcsr)


add_library(minimalpq ${LIB_TYPE} ../src/wrapper/extrap_lorenzo.cu)
add_executable(test-pqlorenzo src/ex_api_pqlorenzo.cu)
target_link_libraries(test-pqlorenzo minimalpq -lcusparse)

add_library(interp ${LIB_TYPE} ../src/wrapper/interp_spline3.cu)
# add_library(spcompressor ${LIB_TYPE} ../src/sp_path.cu)
add_executable(test-spline3 src/ex_api_spline3.cu)
target_link_libraries(test-spline3 
	interp 
	# spcompressor 
	minimalcsr 
	-lcusparse)