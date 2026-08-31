# =============================================================================
# skyfire-deps -- base image berisi toolchain + dependency yang harus
# di-compile dari source karena tidak tersedia di apt Ubuntu 24.04.
#
# Image ini JARANG berubah. Build sekali, push ke registry, lalu dipakai
# berulang oleh core.Dockerfile. Membangunnya ulang setiap kali core berubah
# akan membuang 1-2 jam per build.
#
# Langkah di bawah adalah replikasi dari .github/workflows/ubuntu.yml milik
# repo core, yang sudah terbukti hijau di CI upstream.
# =============================================================================
FROM ubuntu:24.04 AS deps

ARG BOOST_VERSION=1.91.0
ARG BOOST_UNDERSCORE=1_91_0
ARG OPENSSL_VERSION=4.0.0
ARG DEBIAN_FRONTEND=noninteractive

ENV BOOST_ROOT=/opt/boost \
    OPENSSL_ROOT_DIR=/opt/openssl

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        ccache \
        cmake \
        git \
        gcc-14 \
        g++-14 \
        libbz2-dev \
        libreadline-dev \
        ninja-build \
        perl \
        pkg-config \
        wget \
        zlib1g-dev \
    && (apt-get install -y --no-install-recommends default-libmysqlclient-dev \
        || apt-get install -y --no-install-recommends libmysqlclient-dev) \
    && rm -rf /var/lib/apt/lists/*

# --- Boost (headers + CMake config) ------------------------------------------
# Core melakukan find_package(Boost 1.91.0 REQUIRED) dan meng-glob
# lib*/cmake/Boost-1.91.0, jadi --with-headers sudah cukup.
RUN set -eux; \
    cd /tmp; \
    wget -q "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_UNDERSCORE}.tar.gz"; \
    tar -xzf "boost_${BOOST_UNDERSCORE}.tar.gz"; \
    cd "boost_${BOOST_UNDERSCORE}"; \
    ./bootstrap.sh; \
    ./b2 install --prefix="${BOOST_ROOT}" --with-headers -j"$(nproc)"; \
    cd /; rm -rf /tmp/boost_*

# --- OpenSSL ------------------------------------------------------------------
# enable-legacy WAJIB: SRP6 pada handshake GRUNT (authserver) membutuhkan
# legacy provider. Tanpa ini core tetap compile, tapi login gagal saat runtime.
RUN set -eux; \
    cd /tmp; \
    wget -q "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"; \
    tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz"; \
    cd "openssl-${OPENSSL_VERSION}"; \
    ./Configure linux-x86_64 \
        --prefix="${OPENSSL_ROOT_DIR}" \
        --openssldir="${OPENSSL_ROOT_DIR}/ssl" \
        shared \
        enable-legacy; \
    make -j"$(nproc)"; \
    make install_sw install_ssldirs; \
    cd /; rm -rf /tmp/openssl-*

# Aktifkan legacy provider secara eksplisit di openssl.cnf. Build default
# menyertakan modulnya tapi tidak mengaktifkannya.
RUN set -eux; \
    conf="${OPENSSL_ROOT_DIR}/ssl/openssl.cnf"; \
    printf '\n%s\n' \
        '[openssl_init]' \
        'providers = provider_sect' \
        '' \
        '[provider_sect]' \
        'default = default_sect' \
        'legacy  = legacy_sect' \
        '' \
        '[default_sect]' \
        'activate = 1' \
        '' \
        '[legacy_sect]' \
        'activate = 1' \
        >> "$conf"; \
    OPENSSL_CONF="$conf" \
    OPENSSL_MODULES="${OPENSSL_ROOT_DIR}/lib64/ossl-modules" \
    LD_LIBRARY_PATH="${OPENSSL_ROOT_DIR}/lib64" \
        "${OPENSSL_ROOT_DIR}/bin/openssl" list -providers | grep -q legacy

ENV PATH="${OPENSSL_ROOT_DIR}/bin:${PATH}" \
    LD_LIBRARY_PATH="${OPENSSL_ROOT_DIR}/lib64" \
    OPENSSL_CONF="${OPENSSL_ROOT_DIR}/ssl/openssl.cnf" \
    OPENSSL_MODULES="${OPENSSL_ROOT_DIR}/lib64/ossl-modules" \
    CC=gcc-14 \
    CXX=g++-14
