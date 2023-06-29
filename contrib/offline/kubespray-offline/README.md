
# kubespray-offline

## Overview

本目录为使用 kubespray "半离线化"部署 Kubernetes 集群方案所需文件.

因为没有把操作系统软件源部分也"离线化", 因此称之为"半离线化", 待安装节点并不能全程断网安装. 但是除此之外, 使用 kubespray 过程中所需要的文件和镜像已经全部包含, 缺少的部分只是操作系统软件源, 想要完全"离线化"部署, 可以参考 [k8sli/kubeplay](https://github.com/k8sli/kubeplay) 项目, 本项目正是在这个项目启发下开发, 使用 GitHub Actions 来下载必要的文件.

项目相关文件如下,

* `.github/workflows/release.yaml`
    * GitHub Actions workflows
* `contrib/offline/download-offline-files.sh`
    * 这个脚本由 `.github/workflows/release.yaml` 所调用, 不直接由用户使用
    * 脚本首先执行 `contrib/offline/generate_list.sh` 脚本生成 `temp/files.list` 与 `temp/images.list`
    * 如果想手动执行这个脚本, 执行前必须有一个已经运行的 `docker.io/library/registry:2` 容器
* `contirb/offline/kubespray-offline`
    * 即本 README.md 所在目录
    * `contrib/offline/download-offline-files.sh` 执行后
        * 会创建 `resources/registry`, `resources/nginx` 目录, 包含下载的文件
        * 会下载 [ak1ra-lab/kubespray offline 分支](https://github.com/ak1ra-lab/kubespray/tree/offline)的代码
    * 打包后包含 `compose.yaml`, `nginx.conf`, `setup.sh` 等文件

打包后离线安装包的目录结构为,

```
kubespray-offline/
  kubespray-offline.tar.gz    ->    offline branch source code archive of kubespray
  resources/
    registry/                 ->    downloaded images from temp/images.list in registry:2 format
    nginx/files/              ->    downloaded files from temp/files.list
    nginx/images/             ->    extra images in docker-archive format
    nginx.conf                ->    nginx.conf for files server
    setup.sh                  ->    helper script to setup and start nginx, registry containers
```

## "半离线化"使用 kubespray 部署 Kubernetes 集群

准备一台部署用的 服务器/虚拟机, 推荐使用 Debian 11 (bullseye),

* 使用系统包管理器安装 `python3 python3-pip python3-venv jq`
* 这台服务器会用作 kubespray 的控制节点用于安装 Kubernetes 集群
* 托管离线资源的 nginx 与 registry 容器也会运行在这台服务器上
    * nginx 容器默认监听 8080 端口, registry 容器默认监听 5000 端口,
    * 要求这两个端口不能被占用, 因此最好在一台全新的服务器上操作

在 [ak1ra-lab/kubespray releases](https://github.com/ak1ra-lab/kubespray/releases) 页面下载离线安装包,

* 由于 GitHub Actions 对单文件大小的限制, 离线安装包被做成多个分卷,
    * 根据待安装集群节点的 CPU 架构下载对应架构的所有分卷, 目前支持 `amd64` 与 `arm64`
* 下载好后将所有分卷使用 `cat` 命令合并为一个文件
* 校验合并后文件的 `sha256sum`, 校验通过后解压离线安装包
* 切换到解压后的目录, 执行本目录下的 `setup.sh` 脚本,
    * 会解压安装 `nerdctl-full-*` 至 `/usr/local` 目录
    * 启动 `buildkit` 与 `containerd` 服务并设置开机启动
    * 使用 `nerdctl image load` 导入 nginx 与 registry 镜像
    * 使用 `nerdctl compose -f compose.yaml up -d` 启动 nginx 与 registry 服务

当前构建的最新版本可以通过 [GitHub Releases API](https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28#get-the-latest-release) 获取到, 可以按照下方命令下载离线安装包和进行初始设置, 也可以通过浏览器手动完成下载过程. 一般来说, 离线安装包只需要配置一次. 后续如有新安装集群需求, 只需要复制 kubespray 源码中 `inventory/sample-offline` 目录即可, 不需要重复执行这些设置,

```shell
mkdir kubespray && cd kubespray/
curl -s https://api.github.com/repos/ak1ra-lab/kubespray/releases/latest > releases_latest.json

arch=$(dpkg --print-architecture)
tag_name=$(jq -r .tag_name releases_latest.json)

wget -c $(jq -r .assets[].browser_download_url releases_latest.json | grep $arch)

cat kubespray-offline-${tag_name}-${arch}.tar.gz.0* > kubespray-offline-${tag_name}-${arch}.tar.gz
sha256sum -c kubespray-offline-${tag_name}-${arch}.tar.gz.sha256
rm -f kubespray-offline-${tag_name}-${arch}.tar.gz.0*

tar -xf kubespray-offline-${tag_name}-${arch}.tar.gz
cd kubespray-offline/ && bash -x setup.sh
```

设置完成后, 准备 kubespray 源码.

`kubespray-offline/kubespray-offline.tar.gz` 文件为一同打包的 offline 分支的 kubespray 源码, 不包含 git 历史提交记录, 可以直接使用这个, 也可以自行从 GitHub 克隆, 注意如果使用克隆的代码需要切换到 offline 分支, `inventory/sample-offline` 目录只存在于 offline 分支.

```shell
tar -xf kubespray-offline.tar.gz && cd kubespray-offline/

python3 -m venv venv && source venv/bin/activate
python3 -m pip install -r requirements.txt
```

规划好要部署的集群节点, 准备好安装 Kubernetes 的 服务器/虚拟机, 需要在各个节点上添加 kubespray 所在服务器的公钥, 即配置好免密登录.

修改 `inventory/sample-offline/group_vars/all/offline.yml` 中的 `registry_host` 和 `files_repo` 项中的 `127.0.0.1` 为 kubespray 所在节点的 IP, 如,

```shell
kubespray_ip=$(ip route get 1 | awk 'NR==1 {print $(NF-2)}')
sed -i \
    -e '/^registry_host/s/127.0.0.1/'${kubespray_ip}'/' \
    -e '/^files_repo/s/127.0.0.1/'${kubespray_ip}'/' \
    inventory/sample-offline/group_vars/all/offline.yml
```

以示例 `inventory/sample-offline` 为模板, 每创建一套集群需要复制一份 `inventory/sample-offline`, 根据实际需求修改 inventory 中配置, 比较重要的配置有,

* `group_vars/all/all.yml`
* `group_vars/all/containerd.yml`
* `group_vars/all/offline.yml`
* `group_vars/k8s_cluster/k8s-cluster.yml`

> `inventory/sample-offline` 相对于 kubespray 所提供的 `inventory/sample` 示例配置做了一些额外修改.

以新创建单集群 `k8s-alpha-test` 为例, 待安装节点为 `172.16.10.10`,

```shell
cp -r inventory/sample-offline inventory/k8s-alpha-test

export CONFIG_FILE=inventory/k8s-alpha-test/hosts.yaml
python3 contrib/inventory_builder/inventory.py k8s-alpha-test-node01,172.16.10.10

ansible-playbook cluster.yml \
    -i inventory/k8s-alpha-test/hosts.yaml \
    --become --become-user=root
```

之后等待集群安装完成即可.
