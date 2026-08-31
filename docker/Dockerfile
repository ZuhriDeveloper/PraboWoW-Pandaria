# =============================================================================
# prabowow-pandaria-server -- image aplikasi (authserver + worldserver).
#
# Satu image, dua peran. Compose memilih lewat `command: ["worldserver"]`
# atau `["authserver"]` -- pola yang sama dengan stack PraboWoW Cataclysm.
#
# Multi-stage:
#   builder : compile core di atas skyfire-deps
#   runtime : ubuntu:24.04 slim, hanya binary + shared lib yang dipakai
#
# Core di-clone (bukan submodule) pada CORE_REF yang di-pin oleh CI, jadi
# rollback = ganti IMAGE_TAG di .env.
# =============================================================================

ARG DEPS_IMAGE=ghcr.io/zuhrideveloper/skyfire-deps:boost1.91.0-ossl4.0.0

# -----------------------------------------------------------------------------
FROM ${DEPS_IMAGE} AS builder

ARG CORE_REPO=https://github.com/ZuhriDeveloper/Prabowow-PandaCore.git
ARG CORE_REF=main
ARG BUILD_TYPE=Release

WORKDIR /src
RUN set -eux; \
    git init .; \
    git remote add origin "${CORE_REPO}"; \
    git fetch --depth 1 origin "${CORE_REF}"; \
    git checkout FETCH_HEAD; \
    git rev-parse HEAD > /src/.core-revision

# TOOLS=OFF: mapextractor/vmap4extractor/mmaps_generator dijalankan di PC lokal
# terhadap client WoW, bukan di server.
RUN set -eux; \
    cmake -S /src -B /build -G Ninja \
        -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
        -DCMAKE_C_COMPILER=gcc-14 \
        -DCMAKE_CXX_COMPILER=g++-14 \
        -DCMAKE_INSTALL_PREFIX=/opt/skyfire \
        -DCONF_DIR=/opt/skyfire/etc \
        -DTOOLS=OFF \
        -DPACKET_LOG_SERVER=OFF \
        -DUSE_COREPCH=ON \
        -DUSE_SCRIPTPCH=ON \
        -DSKYFIRE_BUILD_TESTS=OFF \
        -DAUTH_SERVER=ON \
        -DSCRIPTS=ON \
        -DBOOST_ROOT="${BOOST_ROOT}" \
        -DOPENSSL_ROOT_DIR="${OPENSSL_ROOT_DIR}"; \
    cmake --build /build --parallel "$(nproc)"; \
    cmake --install /build

# sql/ ikut ke image: dipakai DatabaseSetup (SqlPath) untuk menerapkan
# sql/updates/* otomatis tiap start.
RUN set -eux; \
    mkdir -p /opt/skyfire/sql; \
    cp -r /src/sql/. /opt/skyfire/sql/; \
    cp /src/.core-revision /opt/skyfire/.core-revision

# -----------------------------------------------------------------------------
FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gettext-base \
        gosu \
        libbz2-1.0 \
        libreadline8t64 \
        libstdc++6 \
        p7zip \
        tzdata \
        unzip \
        zlib1g \
    && (apt-get install -y --no-install-recommends libmysqlclient21 \
        || apt-get install -y --no-install-recommends libmariadb3) \
    && (apt-get install -y --no-install-recommends default-mysql-client \
        || apt-get install -y --no-install-recommends mariadb-client) \
    && rm -rf /var/lib/apt/lists/*

# libstdc++ dari GCC 14 di stage builder: core dibangun dengan -std=c++23.
COPY --from=builder /usr/lib/x86_64-linux-gnu/libstdc++.so.6* /usr/lib/x86_64-linux-gnu/

# OpenSSL 4 + modul legacy + openssl.cnf yang sudah mengaktifkannya.
COPY --from=builder /opt/openssl/lib64 /opt/openssl/lib64
COPY --from=builder /opt/openssl/ssl   /opt/openssl/ssl
COPY --from=builder /opt/openssl/bin/openssl /opt/openssl/bin/openssl

COPY --from=builder /opt/skyfire /opt/skyfire

# Override .conf di-BAKE ke image. Compose cukup mengoper env var; tidak ada
# file config yang perlu di-bind mount dari VPS.
COPY config/ /opt/skyfire/overrides/
COPY docker/entrypoint/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

ENV LD_LIBRARY_PATH=/opt/openssl/lib64 \
    OPENSSL_MODULES=/opt/openssl/lib64/ossl-modules \
    OPENSSL_CONF=/opt/openssl/ssl/openssl.cnf \
    PATH=/opt/skyfire/bin:/opt/openssl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Default untuk setiap ${VAR} di config/*.overrides.conf, supaya render-config
# tidak pernah menghasilkan nilai kosong kalau compose lupa mengoper satu var.
# Yang tidak punya default di sini (DB_PASSWORD, REALM_ADDRESS) memang harus
# gagal keras daripada diam-diam salah.
ENV DB_HOST=db \
    DB_PORT=3306 \
    DB_USER=skyfire \
    DB_AUTH=auth \
    DB_WORLD=world \
    DB_CHARACTERS=characters \
    REALM_ID=1 \
    REALM_PORT=8085 \
    AUTH_PORT=3724 \
    DATA_DIR_CONTAINER=/opt/skyfire/data \
    LOGS_DIR_CONTAINER=/opt/skyfire/logs \
    SQL_DIR_CONTAINER=/opt/skyfire/sql \
    WORLD_DUMP_CONTAINER=/opt/skyfire/tdb/world_database.sql \
    RATE_XP=1 \
    RATE_DROP_ITEM_COMMON=1 \
    RATE_DROP_ITEM_QUALITY=1 \
    RATE_DROP_ITEM_REFERENCED=1 \
    RATE_DROP_MONEY=1 \
    RATE_HONOR=1 \
    RATE_REPUTATION=1

# Smoke test saat build: legacy provider harus aktif (SRP6/GRUNT butuh ini)
# dan kedua binary harus ter-resolve penuh oleh dynamic linker.
RUN set -eux; \
    openssl list -providers | grep -q legacy; \
    ! ldd /opt/skyfire/bin/worldserver | grep "not found"; \
    ! ldd /opt/skyfire/bin/authserver  | grep "not found"

# uid/gid 1000 supaya cocok dengan `chown 1000:1000 /srv/prabowow` di
# vps-infra/scripts/bootstrap.sh. ubuntu:24.04 sudah memakai 1000 untuk user
# `ubuntu` bawaan, jadi user itu dihapus dulu.
RUN set -eux; \
    userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g 1000 skyfire; \
    useradd -u 1000 -g skyfire -d /opt/skyfire -s /usr/sbin/nologin skyfire; \
    mkdir -p /opt/skyfire/data /opt/skyfire/logs /opt/skyfire/etc /opt/skyfire/tdb; \
    chown -R skyfire:skyfire /opt/skyfire

WORKDIR /opt/skyfire
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["worldserver"]
