# README.md for contrib/kubespray-offline

## Overview

本目录适用于在"网络受限"环境下使用 kubespray 部署 Kubernetes 集群, 并不适用于完全离线的环境.

项目关键文件如下 (相对于 git repo 根目录),

- `.github/workflows/kubespray-offline-release.yaml`
  - GitHub Actions workflows
- `contrib/kubespray-offline/kubespray-offline-release.sh`
  - 这个脚本由 `.github/workflows/kubespray-offline-release.yaml` 所调用, 不直接由用户使用
  - 脚本首先执行 `contrib/offline/generate_list.sh` 脚本生成 `temp/files.list` 与 `temp/images.list`
  - 如果想手动执行这个脚本, 执行前必须有一个已经运行的 `docker.io/library/registry:2` 容器

打包后的压缩档目录结构为,

```
bootstrap.sh                ->    bootstrap script to setup kubespray deploy node
nginx.conf                  ->    nginx.conf for files server
compose.yaml                ->    start nginx and registry containers
resources/
  registry/                 ->    downloaded images from temp/images.list in registry:2 format
  nginx/files/              ->    downloaded files from temp/files.list
  nginx/images/             ->    extra images in docker-archive format
  images.list               ->    copy of temp/images.list
  files.list                ->    copy of temp/files.list
```

## Git branching

本项目基于 kubespray 上游的 release-xxx 分支 rebase 开辟了多个分支, 以 upstream/release-2.28 为例,

- offline-2.28/contrib 用于追踪 `contrib/kubespray-offline` 目录下的修改
- offline-2.28/inventory 用于追踪 `inventory/kubespray-offline` 目录下文件的修改
  - `inventory/kubespray-offline` 基于 `inventory/sample` 创建, 针对 offline 环境做了一些适配
  - 其中存在一些可能并不适用于您的环境的修改, 请批判性使用

二者均基于 upstream/release-2.28 分支 rebase, 因为本项目只相对于上游 release branch 做一些额外的 patch, 并没有本质更改, 因此在部署 Kubernetes 集群时可直接使用上游代码, 不过在创建 inventory 时建议参考本项目 offline-2.28/inventory 分支中 `inventory/kubespray-offline` 目录.

## Installation

### 设置 nginx 和 registry container

在 [ak1ra-lab/kubespray releases](https://github.com/ak1ra-lab/kubespray/releases) 页面下载压缩档,

- 由于 GitHub Actions 对单文件大小的限制, 离线安装包被做成多个分卷,
  - 根据待安装集群节点的 CPU 架构下载对应架构的所有分卷, 目前支持 `amd64`
- 下载好后将所有分卷使用 `cat` 命令合并为一个文件
  - `.sha256` 文件中包含合并后的压缩档的 SHA256 checksum, 下载后注意校验文件完整性
- 将合并后的压缩档解压到某个目录如 `/var/lib/kubespray`
- 使用其中的 compose.yaml 运行 nginx 和 registry container

一般来说, nginx 和 registry container 只需要配置一次.

### 使用 kubespray 安装 Kubernetes 集群

除部分细节外, 可直接参考 kubespray docs 完成部署.

- 准备用于安装 Kubernetes 的节点, 对服务器做必要的初始化, 规划节点角色
- 配置好 kubespray node 到各个节点的免密登录
- 以 `inventory/kubespray-offline` 目录为模板创建待部署集群的 inventory vars
  - `inventory/kubespray-offline` 目录位于本项目 offline-2.28/inventory 的分支
- 根据规划好的节点角色手动创建 ansible inventory
  - 如 inventory/awesome-cluster/hosts.yaml
- 替换 `group_vars/all/offline.yml` 中 `registry_host` 和 `files_repo` 为运行 nginx 和 registry container 的地址
  - 可以使用任意 container runtime, 如 nerdctl (containerd) 或 docker
  - kubespray node 可以与 `registry_host` 和 `files_repo` 不在同一台主机

以 `inventory/kubespray-offline` 目录为模板, 根据实际需求修改 inventory 中配置, 比较重要的配置有,

- `group_vars/all/all.yml`
- `group_vars/all/containerd.yml`
- `group_vars/all/offline.yml`
- `group_vars/k8s_cluster/k8s-cluster.yml`

以新创建单节点集群 `awesome-cluster` 为例,

```shell
# 下载 kubespray 代码
git clone https://github.com/ak1ra-lab/kubespray.git

# 切换到包含 inventory/kubespray-offline 目录的分支
git checkout offline-2.28/inventory

# 复制示例 ansible inventory 并做必要自定义
# 注意替换 `group_vars/all/offline.yml` 中 `registry_host` 和 `files_repo` 为运行 nginx 和 registry container 的地址
cp -r inventory/kubespray-offline inventory/awesome-cluster

# 手动创建 hosts.yaml 文件
vim inventory/awesome-cluster/hosts.yaml

# 创建 python3 venv 环境
python3 -m venv venv

# 激活 venv 并安装依赖
. venv/bin/activate
pip3 install -r requirements.txt

# 开始安装集群
ansible-playbook -i inventory/awesome-cluster/hosts.yaml cluster.yml -v -b
```

之后等待集群安装完成即可.
