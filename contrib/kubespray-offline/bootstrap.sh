#!/bin/bash
# bootstrap script to setup kubespray deploy node
set -e -o pipefail

working_dir="${working_dir:-/var/lib/kubespray}"
test -d "${working_dir}" || mkdir -p "${working_dir}"
downloads_dir="${downloads_dir:-${HOME}/downloads/kubespray}"
test -d "${downloads_dir}" || mkdir -p "${downloads_dir}"

main() {
    # 获取最新 releases 信息
    latest_release="${downloads_dir}/latest_release.json"
    curl -s https://api.github.com/repos/ak1ra-lab/kubespray/releases/latest >"${latest_release}"

    arch="$(dpkg --print-architecture)"
    tag_name="$(jq -r '.tag_name' "${latest_release}")"
    kubespray_offline_archive="kubespray-offline-${tag_name}-${arch}.tar.gz"

    cd "${downloads_dir}" || return
    if [ ! -f "${kubespray_offline_archive}" ]; then
        mapfile -t browser_download_urls < <(
            jq -r '.assets[].browser_download_url | select(. | test("'"${arch}"'"))' "${latest_release}"
        )
        # 下载离线安装包分卷
        wget -c "${browser_download_urls[@]}"
        # 合并离线安装包
        cat "${kubespray_offline_archive}".0* >"${kubespray_offline_archive}"
    fi

    # 校验 SHA256
    if ! sha256sum -c "${kubespray_offline_archive}.sha256"; then
        exit 1
    fi

    # 解压离线安装包
    tar -xf "${kubespray_offline_archive}" -C "${working_dir}"

    # get runtime command
    if command -v nerdctl >/dev/null 2>&1; then
        runtime="nerdctl"
    elif command -v docker >/dev/null 2>&1; then
        runtime="docker"
    else
        echo "No supported container runtime found"
        exit 1
    fi

    # 载入 nginx 与 registry 镜像并拉起容器
    cd "${working_dir}" || return
    if command -v "${runtime}" >/dev/null 2>&1; then
        # load registry and nginx images
        find resources/nginx/images/ -type f -name '*.tar' -print0 | while IFS= read -r -d '' image; do
            test -f "${image}" && "${runtime}" image load -i "${image}"
        done

        # start registry and nginx containers
        "${runtime}" compose -f compose.yaml up -d
    fi
}

main "$@"
