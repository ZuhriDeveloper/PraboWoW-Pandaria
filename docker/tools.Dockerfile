# =============================================================================
# prabowow-pandaria-tools -- extractor data client dalam container.
#
# Kenapa ada: mem-build mapextractor/vmap4extractor/mmaps_generator secara
# native di Windows menuntut Boost 1.91 + OpenSSL 4.0.1 + CMake 4.1.2 + VS2022
# terpasang di mesin -- rantai dependency yang persis kita hindari dengan
# memakai Docker untuk server. skyfire-deps sudah punya semuanya, jadi tools
# ikut dibangun di sana dan dijalankan sebagai container.
#
# Pemakaian (lihat deploy/docker-compose.tools.yml):
#   client  di-bind mount READ-ONLY  -> /client
#   output  ke named volume (bukan bind mount) -> /out
#
# Output sengaja ke volume: menulis ~20 GB mmaps ke bind mount Windows lewat
# Docker Desktop lambat sekali. Volume hidup di dalam VM WSL2 dan cepat; data
# lalu dikirim ke VPS langsung dari container dengan rsync, tanpa pernah
# melewati filesystem Windows.
# =============================================================================

ARG DEPS_IMAGE=ghcr.io/zuhrideveloper/skyfire-deps:boost1.91.0-ossl4.0.0

# -----------------------------------------------------------------------------
FROM ${DEPS_IMAGE} AS builder

ARG CORE_REPO=https://github.com/ZuhriDeveloper/Prabowow-PandaCore.git
ARG CORE_REF=main

WORKDIR /src
RUN set -eux; \
    git init .; \
    git remote add origin "${CORE_REPO}"; \
    git fetch --depth 1 origin "${CORE_REF}"; \
    git checkout FETCH_HEAD

# Kebalikan dari docker/Dockerfile: di sini TOOLS=ON dan servernya yang tidak
# diperlukan. SCRIPTS=OFF memangkas bagian terbesar dari waktu compile.
RUN set -eux; \
    cmake -S /src -B /build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=gcc-14 \
        -DCMAKE_CXX_COMPILER=g++-14 \
        -DCMAKE_INSTALL_PREFIX=/opt/skyfire \
        -DCONF_DIR=/opt/skyfire/etc \
        -DTOOLS=ON \
        -DSERVERS=OFF \
        -DSCRIPTS=OFF \
        -DMODULES=OFF \
        -DAUTH_SERVER=OFF \
        -DPACKET_LOG_SERVER=OFF \
        -DSKYFIRE_BUILD_TESTS=OFF \
        -DBOOST_ROOT="${BOOST_ROOT}" \
        -DOPENSSL_ROOT_DIR="${OPENSSL_ROOT_DIR}"; \
    cmake --build /build --parallel "$(nproc)" \
        --target mapextractor vmap4extractor vmap4assembler mmaps_generator; \
    mkdir -p /opt/skyfire/bin; \
    for t in mapextractor vmap4extractor vmap4assembler mmaps_generator; do \
        cp "$(find /build -type f -name "$t" -perm -u+x | head -1)" /opt/skyfire/bin/; \
    done

# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        libbz2-1.0 \
        libstdc++6 \
        openssh-client \
        rsync \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/lib/x86_64-linux-gnu/libstdc++.so.6* /usr/lib/x86_64-linux-gnu/
COPY --from=builder /opt/skyfire/bin /opt/skyfire/bin
COPY docker/entrypoint/extract-client-data.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/extract-client-data.sh

RUN set -eux; \
    for t in mapextractor vmap4extractor vmap4assembler mmaps_generator; do \
        test -x "/opt/skyfire/bin/$t"; \
        ! ldd "/opt/skyfire/bin/$t" | grep "not found"; \
    done

ENV PATH=/opt/skyfire/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CLIENT_DIR=/client \
    OUTPUT_DIR=/out

WORKDIR /out
ENTRYPOINT ["/usr/local/bin/extract-client-data.sh"]
