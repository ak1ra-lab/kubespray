#! /bin/bash
# bootstrap script to setup kubespray deploy node

bootstrap_dir=${bootstrap_dir:-/var/lib/kubespray}
test -d $bootstrap_dir || mkdir -p $bootstrap_dir

kubespray_offline_dir=${bootstrap_dir}/kubespray-offline

function bootstrap() {
    pushd $bootstrap_dir

    # 获取最新 releases 信息
    curl -s https://api.github.com/repos/ak1ra-lab/kubespray/releases/latest >releases_latest.json

    local arch=$(dpkg --print-architecture)
    local tag_name=$(jq -r .tag_name releases_latest.json)
    local kubespray_offline_archive="kubespray-offline-${tag_name}-${arch}.tar.gz"

    # 如果存在同名离线安装包, 可以认为目录下仍存在 .sha256 文件, 因此只需走一遍 SHA256 校验
    if [ ! -f "${kubespray_offline_archive}" ] || ! sha256sum -c ${kubespray_offline_archive}.sha256; then
        # 下载离线安装包分卷
        wget -c $(jq -r .assets[].browser_download_url releases_latest.json | grep $arch)

        # 合并离线安装包并校验其 SHA256
        cat ${kubespray_offline_archive}.0* >${kubespray_offline_archive}
        sha256sum -c ${kubespray_offline_archive}.sha256
        rm -f ${kubespray_offline_archive}.0*
    fi

    # 解压离线安装包
    test -d ${kubespray_offline_dir} || tar -xf ${kubespray_offline_archive}

    # 设置 nerdctl 并拉起 nginx 与 registry 容器
    pushd ${kubespray_offline_dir}
    if ! nerdctl compose -f compose.yaml ps; then
        bash -x setup.sh
    fi
    popd

    # 设置 Python 3 venv 并安装依赖
    pushd ${kubespray_offline_dir}/src
    test -d venv || python3 -m venv venv
    source venv/bin/activate
    python3 -m pip install -r requirements.txt

    # 把 inventory/offline/group_vars/all/offline.yml
    # 中的 `registry_host` 和 `files_repo` 项修改为 kubespray node IP
    local kubespray_node=$(ip route get 1 | awk 'NR==1 {print $(NF-2)}')
    sed -i \
        -e '/^registry_host/s/127.0.0.1/'${kubespray_node}'/' \
        -e '/^files_repo/s/127.0.0.1/'${kubespray_node}'/' \
        inventory/offline/group_vars/all/offline.yml
    popd

    popd
}

bootstrap $@
