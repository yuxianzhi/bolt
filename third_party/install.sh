#!/bin/bash

script_name=$0
compiler_arch="arm_gnu"
build_threads="8"

print_help() {
    cat <<EOF
Usage: ${script_name} [OPTION]...
Build third party library.

Mandatory arguments to long options are mandatory for short options too.
  -h, --help                 display this help and exit.
  -c, --compiler <arm_llvm|arm_gnu|arm_himix100|arm_ndkv7|x86_gnu|x86_ndk|arm_ios>  use to set compiler(default: arm_gnu).
  -t, --threads              use parallel build(default: 8).
EOF
    exit 1;
}

TEMP=`getopt -o c:ht: --long compiler:help,threads: \
     -n ${script_name} -- "$@"`
if [ $? != 0 ] ; then echo "[ERROR] terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true ; do
    case "$1" in
        -c|--compiler)
            compiler_arch=$2
            echo "[INFO] build library for '${compiler_arch}'" ;
            shift 2 ;;
        -t|--threads)
            build_threads=$2
            echo "[INFO] '${build_threads}' threads parallel to build" ;
            shift 2 ;;
        -h|--help)
            print_help ;
            shift ;;
        --) shift ;
            break ;;
        *) echo "[ERROR]" ; exit 1 ;;
    esac
done

exeIsValid(){
    if type $1 &> /dev/null;
    then
        return 1
    else
        return 0
    fi
}

exeIsValid wget
if [ $? == 0 ] ; then
    echo "[ERROR] please install wget tools and set shell environment PATH to find it"
    exit 1
fi

exeIsValid git
if [ $? == 0 ] ; then
    echo "[ERROR] please install git tools and set shell environment PATH to find it"
    exit 1
fi

exeIsValid unzip
if [ $? == 0 ] ; then
    echo "[ERROR] please install unzip tools and set shell environment PATH to find it"
    exit 1
fi

exeIsValid tar
if [ $? == 0 ] ; then
    echo "[ERROR] please install tar tools and set shell environment PATH to find it"
    exit 1
fi

configure_flags=""
dynamic_library_suffix="so"
if [ "${compiler_arch}" == "arm_llvm" ] ; then
    exeIsValid aarch64-linux-android21-clang && exeIsValid aarch64-linux-android21-clang++
    if [ $? == 0 ] ; then
        echo "[ERROR] please install android ndk aarch64-linux-android21-clang++ compiler and set shell environment PATH to find it"
        exit 1
    fi
    export CC=aarch64-linux-android21-clang
    export CXX=aarch64-linux-android21-clang++
    export AR=aarch64-linux-android-ar
    configure_flags="--host=arm-linux --enable-neon "
fi
if [ "${compiler_arch}" == "arm_gnu" ] ; then
    exeIsValid aarch64-linux-gnu-gcc && exeIsValid aarch64-linux-gnu-g++
    if [ $? == 0 ] ; then
        echo "[ERROR] please install GNU gcc ARM compiler and set shell environment PATH to find it"
        exit 1
    fi
    export CC=aarch64-linux-gnu-gcc
    export CXX=aarch64-linux-gnu-g++
    export AR=aarch64-linux-gnu-ar
    configure_flags="--host=arm-linux "
fi
if [ "${compiler_arch}" == "arm_himix100" ] ; then
    exeIsValid arm-himix100-linux-gcc && exeIsValid arm-himix100-linux-g++
    if [ $? == 0 ] ; then
        echo "[ERROR] please install Himix100 GNU gcc ARM compiler and set shell environment PATH to find it"
        exit 1
    fi
    export CC=arm-himix100-linux-gcc
    export CXX=arm-himix100-linux-g++
    export AR=arm-himix100-linux-ar
    configure_flags="--host=arm-linux "
fi
if [ "${compiler_arch}" == "arm_ndkv7" ] ; then
    exeIsValid armv7a-linux-androideabi16-clang && exeIsValid armv7a-linux-androideabi16-clang++
    if [ $? == 0 ] ; then
        echo "[ERROR] please install android ndk armv7a-linux-androideabi19-clang++ compiler and set shell environment PATH to find it"
        exit 1
    fi
    export CC=armv7a-linux-androideabi16-clang
    export CXX=armv7a-linux-androideabi16-clang++
    export AR=arm-linux-androideabi-ar
    configure_flags="--host=arm-linux "
fi
if [ "${compiler_arch}" == "x86_gnu" ] ; then
    exeIsValid gcc && exeIsValid g++
    if [ $? == 0 ] ; then
        echo "[ERROR] please install x86 gnu compiler and set shell environment PATH to find it"
        exit 1
    fi
    export CC=gcc
    export CXX=g++
    export AR=ar
fi
if [ "${compiler_arch}" == "x86_ndk" ] ; then
    exeIsValid x86_64-linux-android21-clang && exeIsValid x86_64-linux-android21-clang++
    if [ $? == 0 ] ; then
        echo "[ERROR] please install android ndk x86_64-linux-android21-clang++ compiler and set shell environment PATH to find it"
        exit 1
    fi
    export CC=x86_64-linux-android21-clang
    export CXX=x86_64-linux-android21-clang++
    export AR=x86_64-linux-android-ar
    configure_flags="--host=x86-linux"
fi
if [ "${compiler_arch}" == "arm_ios" ] ; then
    exeIsValid arm-apple-darwin11-clang && exeIsValid arm-apple-darwin11-clang++
    if [ $? == 0 ] ; then
        echo "[ERROR] please install ios arm-apple-darwin11-clang++ compiler and set shell environment PATH to find it"
        exit 1
    fi
    export CC=arm-apple-darwin11-clang
    export CXX=arm-apple-darwin11-clang++
    export AR=arm-apple-darwin11-ar
    configure_flags="--host=arm-apple-darwin11 "
    dynamic_library_suffix="dylib"
fi

script_abs=$(readlink -f "$0")
script_dir=$(dirname $script_abs)
current_dir=${PWD}

if [ ! -d "${script_dir}/sources" ]; then
    mkdir ${script_dir}/sources
fi

rm -rf ${script_dir}/${compiler_arch}
mkdir ${script_dir}/${compiler_arch}
env_file="${script_dir}/${compiler_arch}.sh"
PROTOC_ROOT=${script_dir}/${compiler_arch}/protoc
Protobuf_ROOT=${script_dir}/${compiler_arch}/protobuf
FlatBuffers_ROOT=${script_dir}/${compiler_arch}/flatbuffers
TFLite_ROOT=${script_dir}/${compiler_arch}/tflite
OpenCL_ROOT=${script_dir}/${compiler_arch}/opencl
JPEG_ROOT=${script_dir}/${compiler_arch}/jpeg
FFTW_ROOT=${script_dir}/${compiler_arch}/fftw
JSONCPP_ROOT=${script_dir}/${compiler_arch}/jsoncpp

# download prebuilt protoc
echo "[INFO] install protoc in ${script_dir}..."
rm -rf ${PROTOC_ROOT}
mkdir ${PROTOC_ROOT}
cd ${PROTOC_ROOT}
if [ ! -f "${script_dir}/sources/protoc-3.1.0-linux-x86_64.zip" ]; then
    wget https://github.com/protocolbuffers/protobuf/releases/download/v3.1.0/protoc-3.1.0-linux-x86_64.zip || exit 1
    cp protoc-3.1.0-linux-x86_64.zip ${script_dir}/sources/
else
    cp ${script_dir}/sources/protoc-3.1.0-linux-x86_64.zip .
fi
unzip protoc-3.1.0-linux-x86_64.zip
rm protoc-3.1.0-linux-x86_64.zip
export PATH=${PROTOC_ROOT}/bin:$PATH

# download and build protobuf
echo "[INFO] install protobuf in ${script_dir}..."
rm -rf ${Protobuf_ROOT}
mkdir ${Protobuf_ROOT}
cd ${Protobuf_ROOT}
if [ ! -f "${script_dir}/sources/v3.1.0.tar.gz" ]; then
    wget https://github.com/protocolbuffers/protobuf/archive/v3.1.0.tar.gz || exit 1
    cp v3.1.0.tar.gz ${script_dir}/sources/
else
    cp ${script_dir}/sources/v3.1.0.tar.gz .
fi
tar xzf v3.1.0.tar.gz
cd protobuf-3.1.0
if [ ! -f "./configure" ]; then
    ./autogen.sh || (echo "./autogen.sh failed for protobuf, If it is related to curl for download, you can add -k parameter for curl in autogen.sh"; exit 1) ;
fi
./configure ${configure_flags} --with-protoc=${PROTOC_ROOT}/bin/protoc\
            --prefix=${Protobuf_ROOT}
make -j${build_threads} || exit 1
make install -j${build_threads} || exit 1
cp ${PROTOC_ROOT}/bin/protoc ${Protobuf_ROOT}/bin
cd ..
rm -rf v3.1.0.tar.gz protobuf-3.1.0

# download flatbuffers header file
echo "[INFO] install flatbuffers in ${script_dir}..."
rm -rf ${FlatBuffers_ROOT}
mkdir ${FlatBuffers_ROOT}
cd ${FlatBuffers_ROOT}
if [ ! -d "${script_dir}/sources/flatbuffers" ]; then
    git init
    git remote add -f origin https://github.com/google/flatbuffers || exit 1
    git config core.sparsecheckout true
    echo "include" >> .git/info/sparse-checkout
    git pull origin master || exit 1
    rm -rf .git*
    cp -r ../flatbuffers ${script_dir}/sources/
else
    cp -r ${script_dir}/sources/flatbuffers/* .
fi

# download tensorflow-lite header file
echo "[INFO] install TFLite in ${script_dir}..."
rm -rf ${TFLite_ROOT}
mkdir ${TFLite_ROOT}
cd ${TFLite_ROOT}
if [ ! -d "${script_dir}/sources/tflite" ]; then
    mkdir include
    cd include
    git init
    git remote add -f origin https://github.com/tensorflow/tensorflow || exit 1
    git config core.sparsecheckout true
    echo "tensorflow/lite/schema/schema_generated.h" >> .git/info/sparse-checkout
    git pull origin master || exit 1
    rm -rf .git*
    cp -r ../../tflite ${script_dir}/sources/
else
    cp -r ${script_dir}/sources/tflite/* .
fi

# download and install OpenCL
if [ "${compiler_arch}" == "arm_llvm" ] ; then
    echo "[INFO] install opencl in ${script_dir}..."
    rm -rf ${OpenCL_ROOT}
    mkdir ${OpenCL_ROOT}
    cd ${OpenCL_ROOT}
    if [ ! -d "${script_dir}/sources/opencl" ]; then
        mkdir include
        cd include 
        git init
        git remote add -f origin https://github.com/KhronosGroup/OpenCL-Headers || exit 1
        git config core.sparsecheckout true
        echo "CL" >> .git/info/sparse-checkout
        git pull origin master || exit 1
        rm -rf .git*
        cd ..
    
        mkdir lib64
        android_device=`adb devices | head -n 2 | tail -n 1 | awk '{print $1}'`
        adb -s ${android_device} pull /vendor/lib64/libOpenCL.so lib64/
        adb -s ${android_device} pull /vendor/lib64/egl/libGLES_mali.so lib64/
        cp -r ../opencl ${script_dir}/sources/
    else
        cp -r ${script_dir}/sources/opencl/* .
    fi
fi

# download and build jpeg
echo "[INFO] install jpeg in ${script_dir}..."
rm -rf ${JPEG_ROOT}
mkdir ${JPEG_ROOT}
cd ${JPEG_ROOT}
if [ ! -f "${script_dir}/sources/jpegsrc.v9c.tar.gz" ]; then
    wget http://www.ijg.org/files/jpegsrc.v9c.tar.gz || exit 1
    cp jpegsrc.v9c.tar.gz ${script_dir}/sources/
else
    cp ${script_dir}/sources/jpegsrc.v9c.tar.gz .
fi
tar xzf jpegsrc.v9c.tar.gz
cd jpeg-9c
if [ ! -f "./configure" ]; then
    ./autogen.sh || (echo "./autogen.sh failed for libjpeg"; exit 1) ;
fi
./configure ${configure_flags} --prefix=${JPEG_ROOT}
make -j${build_threads} || exit 1
make install -j${build_threads} || exit 1
cd ..
rm -rf jpeg-9c jpegsrc.v9c.tar.gz

# download and build jsoncpp
echo "[INFO] install jsoncpp in ${script_dir}..."
rm -rf ${JSONCPP_ROOT}
mkdir ${JSONCPP_ROOT}
cd ${JSONCPP_ROOT}
if [ ! -f "${script_dir}/sources/jsoncpp-master.zip" ]; then
    wget https://github.com/open-source-parsers/jsoncpp/archive/master.zip || exit 1
    cp jsoncpp-master.zip ${script_dir}/sources/
else
    cp ${script_dir}/sources/jsoncpp-master.zip .
fi
unzip jsoncpp-master.zip
cd jsoncpp-master
cp -r include ${JSONCPP_ROOT}/
mkdir ${JSONCPP_ROOT}/lib
${CXX} -shared -fPIC src/lib_json/*.cpp -Iinclude -o ${JSONCPP_ROOT}/lib/libjsoncpp.${dynamic_library_suffix}
${CXX} -c src/lib_json/*.cpp -Iinclude
${AR} -crv ${JSONCPP_ROOT}/lib/libjsoncpp.a ./*.o
cd ..
rm -rf jsoncpp-master*

# download fftw
echo "[INFO] install fftw in ${script_dir}..."
rm -rf ${FFTW_ROOT}
mkdir ${FFTW_ROOT}
cd ${FFTW_ROOT}
if [ ! -f "${script_dir}/sources/fftw-3.3.8.tar.gz" ]; then
    wget http://www.fftw.org/fftw-3.3.8.tar.gz || exit 1
    cp fftw-3.3.8.tar.gz ${script_dir}/sources/
else
    cp -r ${script_dir}/sources/fftw-3.3.8.tar.gz .
fi
tar xzf fftw-3.3.8.tar.gz
cd fftw-3.3.8
./configure ${configure_flags} --enable-shared=yes --enable-single --enable-fma --prefix=${FFTW_ROOT}
make -j${build_threads} || exit 1
make install -j${build_threads} || exit 1
cd ..
rm -rf fftw-3.3.8 fftw-3.3.8.tar.gz

echo "[INFO] generate environment file to ${env_file}..."
echo "#!/bin/bash
export Protobuf_ROOT=${Protobuf_ROOT}
export FlatBuffers_ROOT=${FlatBuffers_ROOT}
export TFLite_ROOT=${TFLite_ROOT}
export OpenCL_ROOT=${OpenCL_ROOT}
export JPEG_ROOT=${JPEG_ROOT}
export JSONCPP_ROOT=${JSONCPP_ROOT}
export FFTW_ROOT=${FFTW_ROOT}
export PATH=\${Protobuf_ROOT}/bin:\$PATH
export LD_LIBRARY_PATH=\${Protobuf_ROOT}/lib:\${OpenCL_ROOT}/lib64:\${JPEG_ROOT}/lib:\${JSONCPP_ROOT}/lib:\${FFTW_ROOT}/lib:\$LD_LIBRARY_PATH
" > ${env_file}
chmod a+x ${env_file}
echo "[INFO] please source ${env_file} before use..."

cd ${current_dir}
