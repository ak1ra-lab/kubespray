#!/bin/bash
# This script is used by GitHub Actions
# Before running this script, you should have a running registry:2 container

set -ex -o pipefail

# download files
download_files_list() {
    if [ ! -f "${files_list}" ]; then
        echo "${files_list} should exist, run contrib/offline/generate_list.sh first."
        exit 1
    fi

    # append nerdctl-full-*.tar.gz
    nerdctl_full_url="$(grep 'containerd/nerdctl' "${files_list}" | sed 's/nerdctl-/nerdctl-full-/')"
    echo "${nerdctl_full_url}" >>"${files_list}"

    test -d "${files_dir}" || mkdir -p "${files_dir}"
    echo "==== download_files_list ===="
    tee "${resources_dir}/files.list" <"${files_list}"
    wget \
        --quiet --continue --force-directories \
        --directory-prefix="${files_dir}" --input-file="${files_list}"
}

download_images_list() {
    if [ ! -f "${images_list}" ]; then
        echo "${images_list} should exist, run contrib/offline/generate_list.sh first."
        exit 1
    fi

    test -d "${images_dir}" || mkdir -p "${images_dir}"
    echo "==== download_images_list ===="
    tee "${resources_dir}/images.list" <"${images_list}"
    # registry:2 raise level=fatal error msg when writing manifest (Image manifest version 2, schema 1)
    mapfile -t images < <(sed -r '/quay\.io\/external_storage\/(cephfs|rbd)-provisioner/d' "${images_list}")
    # mapfile -t images < <(cat "${images_list}")
    for image in "${images[@]}"; do
        echo "skopeo copy docker://${image} docker://${registry_addr}/${image}"
        skopeo --command-timeout=60s --override-arch="${arch}" --override-os=linux \
            copy --retry-times=5 --dest-tls-verify=false \
            "docker://${image}" "docker://${registry_addr}/${image}"
        sleep 5
    done

    test -d "${images_dir}/registry" && rm -rf "${images_dir}/registry"
    # we don't need this step if GitHub Actions services volumes works
    # ref: https://github.com/orgs/community/discussions/42127#discussioncomment-7591609
    docker cp -a "${registry_name}:/var/lib/registry" "${images_dir}"
}

download_extra_images() {
    test -d "${extra_images_dir}" || mkdir -p "${extra_images_dir}"
    skopeo copy "docker://${extra_nginx_image}" "docker-archive:${extra_images_dir}/nginx.tar:${extra_nginx_image}"
    skopeo copy "docker://${extra_registry_image}" "docker-archive:${extra_images_dir}/registry.tar:${extra_registry_image}"
}

gen_compose_yaml() {
    cat >"${working_dir}/compose.yaml" <<EOF
---

services:
  nginx:
    image: ${extra_nginx_image}
    container_name: nginx
    restart: always
    volumes:
      - ./resources/nginx:/usr/share/nginx
      - ./nginx.conf:/etc/nginx/nginx.conf
    ports:
      - 8080:8080

  registry:
    image: ${extra_registry_image}
    container_name: registry
    restart: always
    volumes:
      - ./resources/registry:/var/lib/registry
    ports:
      - 5000:5000
EOF
}

make_archive_and_split() {
    cd "${working_dir}" || return

    tar -czf "${kubespray_archive_dir}/${kubespray_archive}" .

    cd "${kubespray_archive_dir}" || return
    sha256sum "${kubespray_archive}" | tee "${kubespray_archive}.sha256"

    # Each file included in a release must be under 2 GB.
    # There is no limit on the total size of a release, nor bandwidth usage.
    if [ "$(stat --format=%s "${kubespray_archive}")" -ge 2000000000 ]; then
        split --numeric-suffixes=1 --bytes=1GiB "${kubespray_archive}" "${kubespray_archive}."
        rm -f "${kubespray_archive}"
    fi
}

main() {
    script_dir="$(dirname "$(readlink -f "$0")")"
    # contrib/offline/generate_list.sh
    offline_temp_dir="${script_dir}/../offline/temp"

    arch="${arch:-amd64}"
    registry_name="${registry_name:-registry}"
    registry_addr="${registry_addr:-127.0.0.1:5000}"

    kubespray_archive="${kubespray_archive:-kubespray-offline.tar.gz}"
    kubespray_archive_dir="${kubespray_archive_dir:-/tmp}"

    working_dir="${working_dir:-${script_dir}}"
    resources_dir="${working_dir}/resources"
    test -d "${resources_dir}" || mkdir -p "${resources_dir}"

    files_list="${files_list:-"${offline_temp_dir}/files.list"}"
    files_dir="${resources_dir}/nginx/files"

    # docker registry http api v2
    images_list="${images_list:-"${offline_temp_dir}/images.list"}"
    images_dir="${resources_dir}"

    # extra images
    extra_nginx_version="${extra_nginx_version:-1.29}"
    extra_registry_version="${extra_registry_version:-2}"
    extra_nginx_image="docker.io/library/nginx:${extra_nginx_version}"
    extra_registry_image="docker.io/library/registry:${extra_registry_version}"
    extra_images_dir="${resources_dir}/nginx/images"

    download_files_list
    download_images_list
    download_extra_images
    gen_compose_yaml
    make_archive_and_split
}

main "$@"
