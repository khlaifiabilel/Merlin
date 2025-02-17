# syntax=docker/dockerfile:1
ARG IMAGE=nvcr.io/nvidia/tensorflow:21.07-tf2-py3
FROM ${IMAGE} AS phase1
ENV CUDA_SHORT_VERSION=11.4

SHELL ["/bin/bash", "-c"]
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:/usr/local/lib:/repos/dist/lib

ENV DEBIAN_FRONTEND=noninteractive

ARG RELEASE=false
ARG RMM_VER=v21.08.00
ARG CUDF_VER=v21.08.01
ARG NVTAB_VER=vnightly
ARG HUGECTR_VER=v21.9
ARG SM="60;61;70;75;80"

ENV CUDA_HOME=/usr/local/cuda
ENV CUDA_PATH=$CUDA_HOME
ENV CUDA_CUDA_LIBRARY=${CUDA_HOME}/lib64/stubs
ENV PATH=${CUDA_HOME}/lib64/:${PATH}:${CUDA_HOME}/bin

# Build env variables for rmm
ENV INSTALL_PREFIX=/usr

RUN apt update -y --fix-missing && \
    apt upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        vim gdb git wget unzip tar \ 
        #python3.8-dev \
        zlib1g-dev lsb-release clang-format libboost-all-dev \
        openssl curl zip\
        libssl-dev \
        protobuf-compiler \
        numactl \
        libnuma-dev \
        libaio-dev \
        libibverbs-dev \
        slapd && \
      apt install -y --no-install-recommends software-properties-common && \
      add-apt-repository -y ppa:deadsnakes/ppa && \
      apt update -y --fix-missing

RUN pip install git+git://github.com/gevent/gevent.git@21.8.0#egg=gevent

RUN pip install 'notebook>=6.4.1' 'sqlparse>=0.4.2'
RUN ln -s /usr/local/nvm/versions/node/v15.12.0/bin/node /usr/bin/node
RUN /usr/local/nvm/versions/node/v15.12.0/bin/npm -g upgrade

# Install cmake
RUN apt remove --purge cmake -y && wget http://www.cmake.org/files/v3.21/cmake-3.21.1.tar.gz && \
    tar xf cmake-3.21.1.tar.gz && cd cmake-3.21.1 && ./configure && make && make install

# Install arrow from source
ENV ARROW_HOME=/usr/local
RUN git clone --branch apache-arrow-4.0.1 --recurse-submodules https://github.com/apache/arrow.git build-env && \
    pushd build-env && \
      export PARQUET_TEST_DATA="${PWD}/cpp/submodules/parquet-testing/data" && \
      export ARROW_TEST_DATA="${PWD}/testing/data" && \
      pip install -r python/requirements-build.txt && \
      mkdir cpp/release && \
      pushd cpp/release && \
        cmake -DCMAKE_INSTALL_PREFIX=${ARROW_HOME} \
              -DCMAKE_INSTALL_LIBDIR=lib \
              -DCMAKE_LIBRARY_PATH=${CUDA_CUDA_LIBRARY} \
              -DARROW_FLIGHT=ON \
              -DARROW_GANDIVA=OFF \
              -DARROW_ORC=ON \
              -DARROW_WITH_BZ2=ON \
              -DARROW_WITH_ZLIB=ON \
              -DARROW_WITH_ZSTD=ON \
              -DARROW_WITH_LZ4=ON \
              -DARROW_WITH_SNAPPY=ON \
              -DARROW_WITH_BROTLI=ON \
              -DARROW_PARQUET=ON \
              -DARROW_PYTHON=ON \
              -DARROW_PLASMA=ON \
              -DARROW_BUILD_TESTS=ON \
              -DARROW_CUDA=ON \
              -DARROW_DATASET=ON \
              .. && \
        make -j$(nproc) && \
        make install && \
      popd && \
      pushd python && \
        export PYARROW_WITH_PARQUET=ON && \
        export PYARROW_WITH_CUDA=ON && \
        export PYARROW_WITH_ORC=ON && \
        export PYARROW_WITH_DATASET=ON && \
        python setup.py build_ext --build-type=release bdist_wheel && \
        pip install dist/*.whl && \
      popd && \
    popd && \
    rm -rf build-env


FROM phase1 as phase2

ARG RELEASE=false
ARG RMM_VER=v21.08.00
ARG CUDF_VER=v21.08.01

# Install rmm from source
RUN git clone https://github.com/rapidsai/rmm.git build-env && cd build-env/ && \
    if [ "$RELEASE" == "true" ] && [ ${RMM_VER} != "vnightly" ] ; then git fetch --all --tags && git checkout tags/${RMM_VER}; else git checkout main; fi; \
    sed -i '/11.2/ a "11.4": "11.x",' python/setup.py && \
    cd ..; \
    pushd build-env && \
    ./build.sh librmm && \
    pip install python/. && \
    popd && \
    rm -rf build-env


# Build env for CUDF build
RUN git clone https://github.com/rapidsai/cudf.git build-env && cd build-env/ && \
    if [ "$RELEASE" == "true" ] && [ ${CUDF_VER} != "vnightly" ] ; then git fetch --all --tags && git checkout tags/${CUDF_VER}; else git checkout main; fi; \
    git submodule update --init --recursive && \
    cd .. && \
    pushd build-env && \
      export CUDF_HOME=${PWD} && \
      export CUDF_ROOT=${PWD}/cpp/build/ && \
      export CMAKE_LIBRARY_PATH=${CUDA_CUDA_LIBRARY} && \
      ./build.sh libcudf cudf dask_cudf && \
      protoc -I=python/cudf/cudf/utils/metadata --python_out=/usr/local/lib/python3.8/dist-packages/cudf/utils/metadata python/cudf/cudf/utils/metadata/orc_column_statistics.proto && \
    popd && \
    rm -rf build-env

FROM phase2 AS phase3

ARG RELEASE=false
ARG NVTAB_VER=vnightly

RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        vim gdb git wget unzip tar python3.8-dev \
        zlib1g-dev lsb-release clang-format libboost-all-dev \
        openssl curl zip\
       	slapd && \
    rm -rf /var/lib/apt/lists/*

ENV PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION='python'


RUN pip install pandas sklearn ortools nvtx-plugins pydot && \
    pip cache purge

# install ucx from source
RUN apt update; apt install -y libtool
RUN git clone https://github.com/openucx/ucx.git /repos/ucx;cd /repos/ucx; ./autogen.sh; mkdir build; cd build; ../contrib/configure-release --prefix=/usr; make; make install

RUN pip install pybind11
SHELL ["/bin/bash", "-c"]

# Install NVTabular
RUN git clone https://github.com/NVIDIA/NVTabular.git /nvtabular/ && \
    cd /nvtabular/; if [ "$RELEASE" == "true" ] && [ ${NVTAB_VER} != "vnightly" ] ; then git fetch --all --tags && git checkout tags/${NVTAB_VER}; else git checkout main; fi; \
    python setup.py develop --user;


RUN pip install pynvml pytest graphviz sklearn scipy matplotlib 
RUN pip install nvidia-pyindex; pip install tritonclient[all] grpcio-channelz
RUN pip install nvtx mpi4py cupy-cuda114 cachetools typing_extensions fastavro

RUN apt-get update; apt-get install -y graphviz

ENV LD_LIBRARY_PATH=/usr/local/hugectr/lib:$LD_LIBRARY_PATH \
    LIBRARY_PATH=/usr/local/hugectr/lib:$LIBRARY_PATH \
    PYTHONPATH=/usr/local/hugectr/lib:$PYTHONPATH

RUN git clone https://github.com/rapidsai/asvdb.git build-env && \
    pushd build-env && \
      python setup.py install && \
    popd && \
    rm -rf build-env

RUN pip install dask==2021.07.1 distributed==2021.07.1 dask[dataframe]==2021.07.1 dask-cuda
FROM phase3 as phase4

ARG RELEASE=false
ARG HUGECTR_VER=v21.9
ARG SM="60;61;70;75;80"
ARG USE_NVTX=OFF

RUN mkdir -p /usr/local/nvidia/lib64 && \
    ln -s /usr/local/cuda/lib64/libcusolver.so /usr/local/nvidia/lib64/libcusolver.so.10

RUN ln -s /usr/lib/x86_64-linux-gnu/libibverbs.so.1.11.32.1 /usr/lib/x86_64-linux-gnu/libibverbs.so

RUN git clone https://github.com/NVIDIA/HugeCTR.git build-env && \
    pushd build-env && \
      if [ "$RELEASE" == "true" ] && [ ${HUGECTR_VER} != "vnightly" ] ; then git fetch --all --tags && git checkout tags/${HUGECTR_VER}; else echo ${HUGECTR_VER} && git checkout ${HUGECTR_VER}-integration; fi && \
      cd sparse_operation_kit && \
      bash ./install.sh --SM=$SM --USE_NVTX=$USE_NVTX && \
    popd && \
    rm -rf build-env && \
    rm -rf /var/tmp/HugeCTR

RUN pip install pybind11
RUN pip install numba numpy --upgrade
SHELL ["/bin/bash", "-c"]

RUN echo $(du -h --max-depth=1 /)

HEALTHCHECK NONE
ENTRYPOINT []
CMD ["/bin/bash"]
