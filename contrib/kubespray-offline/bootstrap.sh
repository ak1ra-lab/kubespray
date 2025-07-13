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
    sha256sum -c "${kubespray_offline_archive}.sha256"
    rm -f "${kubespray_offline_archive}".0*

    # 解压离线安装包
    tar -xf "${kubespray_offline_archive}" -C "${working_dir}"

    # 设置 nerdctl 并拉起 nginx 与 registry 容器
    cd "${working_dir}" || return
    if command -v nerdctl >/dev/null 2>&1; then
        # load registry and nginx images
        find resources/nginx/images/ -type f -name '*.tar' -print0 | while IFS= read -r -d '' image; do
            test -f "${image}" && nerdctl image load -i "${image}"
        done

        # start registry and nginx containers
        nerdctl compose -f compose.yaml up -d
    else
        bash -x setup.sh
    fi

    # 设置 Python 3 venv 并安装依赖
    cd "${working_dir}/src" || return
    test -d venv || python3 -m venv venv
    # shellcheck disable=SC1091
    . venv/bin/activate
    python3 -m pip install -r requirements.txt

    # 把 inventory/offline/group_vars/all/offline.yml
    # 中的 `registry_host` 和 `files_repo` 项修改为 kubespray node IP
    kubespray_node="$(ip route get 1 | awk 'NR==1 {print $(NF-2)}')"
    sed -i \
        -e '/^registry_host/s/127.0.0.1/'"${kubespray_node}"'/' \
        -e '/^files_repo/s/127.0.0.1/'"${kubespray_node}"'/' \
        inventory/offline/group_vars/all/offline.yml
}

main "$@"
