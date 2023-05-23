#! /bin/bash
# This script is used by GitHub Actions
# Before running this script, you should have a running registry:2 container
#   resources/
#     registry/    ->    temp/images.list
#     nginx/
#       files/     ->    temp/files.list
#       images/    ->    extra docker-archive tar ball

ARCH=${ARCH:-amd64}
REGISTRY_NAME="${REGISTRY_NAME:-registry}"
REGISTRY_ADDR="${REGISTRY_ADDR:-127.0.0.1:5000}"

OFFLINE_DIR=$(dirname "$(readlink -f \"$0\")")
TEMP_DIR="${OFFLINE_DIR}/temp"
RESOURCES_DIR="${OFFLINE_DIR}/resources"

FILES_LIST=${FILES_LIST:-"${TEMP_DIR}/files.list"}
OFFLINE_FILES_DIR="${RESOURCES_DIR}/nginx/files"

# Docker Registry HTTP API v2
IMAGES_LIST=${IMAGES_LIST:-"${TEMP_DIR}/images.list"}
OFFLINE_IMAGES_DIR="${RESOURCES_DIR}/"

# Extra images
EXTRA_NGINX_VERSION=${EXTRA_NGINX_VERSION:-1.25}
EXTRA_REGISTRY_VERSION=${EXTRA_REGISTRY_VERSION:-2.8}
EXTRA_NGINX_IMAGE="docker.io/library/nginx:${EXTRA_NGINX_VERSION}"
EXTRA_REGISTRY_IMAGE="docker.io/library/registry:${EXTRA_REGISTRY_VERSION}"
EXTRA_IMAGES_DIR="${RESOURCES_DIR}/nginx/images"

# download files
function download_files_list() {
    if [ ! -f "${FILES_LIST}" ]; then
        echo "${FILES_LIST} should exist, run ./generate_list.sh first."
        exit 1
    fi

    test -d "${OFFLINE_FILES_DIR}" || mkdir -p "${OFFLINE_FILES_DIR}"

    # append nerdctl-full-*.tar.gz
    if echo "${ARCH}" | grep -qE 'amd64|arm64'; then
        grep 'containerd/nerdctl' "${FILES_LIST}" |
            sed 's/nerdctl-/nerdctl-full-/' >>"${FILES_LIST}"
    fi

    echo "==== download_files_list ===="
    cat "${FILES_LIST}" && cp -v "${FILES_LIST}" "${RESOURCES_DIR}"
    wget -q -c -x -P "${OFFLINE_FILES_DIR}" -i "${FILES_LIST}"
}

function download_images_list() {
    if [ ! -f "${IMAGES_LIST}" ]; then
        echo "${IMAGES_LIST} should exist, run ./generate_list.sh first."
        exit 1
    fi

    test -d "${OFFLINE_IMAGES_DIR}" || mkdir -p "${OFFLINE_IMAGES_DIR}"

    echo "==== download_images_list ===="
    cat "${IMAGES_LIST}" && cp -v "${IMAGES_LIST}" "${RESOURCES_DIR}"
    for image in $(cat ${IMAGES_LIST}); do
        echo "skopeo copy docker://${image} docker://${REGISTRY_ADDR}/${image}"
        skopeo --override-arch=${ARCH} --override-os=linux \
            copy --retry-times=5 --dest-tls-verify=false \
            docker://${image} docker://${REGISTRY_ADDR}/${image}
        sleep 5
    done

    test -d "${OFFLINE_IMAGES_DIR}/registry" && rm -rf "${OFFLINE_IMAGES_DIR}/registry"
    docker cp -a "${REGISTRY_NAME}:/var/lib/registry" "${OFFLINE_IMAGES_DIR}"
}

function download_extra_images() {
    test -d "${EXTRA_IMAGES_DIR}" || mkdir -p "${EXTRA_IMAGES_DIR}"

    skopeo copy "docker://${EXTRA_NGINX_IMAGE}" "docker-archive:${EXTRA_IMAGES_DIR}/nginx.tar:${EXTRA_NGINX_IMAGE}"
    skopeo copy "docker://${EXTRA_REGISTRY_IMAGE}" "docker-archive:${EXTRA_IMAGES_DIR}/registry.tar:${EXTRA_REGISTRY_IMAGE}"
}

function gen_compose_yaml() {
    cat > ${RESOURCES_DIR}/compose.yaml<<EOF
---
version: '3'
services:
  nginx:
    image: ${EXTRA_NGINX_IMAGE}
    container_name: nginx
    restart: always
    volumes:
      - ./nginx:/usr/share/nginx
      - ./nginx.conf:/etc/nginx/nginx.conf
    ports:
      - 8080:8080

  registry:
    image: ${EXTRA_REGISTRY_IMAGE}
    container_name: registry
    restart: always
    volumes:
      - ./registry:/var/lib/registry
    ports:
      - 5000:5000
EOF
}

download_files_list
download_images_list
download_extra_images
gen_compose_yaml
