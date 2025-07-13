
# [kubespray/contrib/kubespray-offline at kubespray-offline · ak1ra-lab/kubespray](https://github.com/ak1ra-lab/kubespray/tree/kubespray-offline/contrib/kubespray-offline)

## Overview

本目录为使用 kubespray "半离线化"部署 Kubernetes 集群方案所需文件.

因为没有把操作系统软件源部分也"离线化", 因此称之为"半离线化", 待安装节点并不能全程断网安装. 但是除此之外, 使用 kubespray 过程中所需要的文件和镜像已经全部包含, 缺少的部分只是操作系统软件源, 想要完全"离线化"部署, 可以参考 [k8sli/kubeplay](https://github.com/k8sli/kubeplay) 项目, 本项目正是在这个项目启发下开发, 使用 GitHub Actions 来下载必要的文件.

项目相关文件如下,

* `.github/workflows/kubespray-offline-release.yaml`
    * GitHub Actions workflows
* `contrib/kubespray-offline/kubespray-offline-release.sh`
    * 这个脚本由 `.github/workflows/kubespray-offline-release.yaml` 所调用, 不直接由用户使用
    * 脚本首先执行 `contrib/offline/generate_list.sh` 脚本生成 `temp/files.list` 与 `temp/images.list`
    * 如果想手动执行这个脚本, 执行前必须有一个已经运行的 `docker.io/library/registry:2` 容器
* `contirb/kubespray-offline`
    * 即本 README.md 所在目录
    * `contrib/kubespray-offline/kubespray-offline-release.sh` 执行后
        * 会创建 `resources/registry`, `resources/nginx` 目录, 包含下载的文件
        * 会克隆 [ak1ra-lab/kubespray](https://github.com/ak1ra-lab/kubespray/tree/kubespray-offline) 的代码, 存放在 `src/` 目录下
    * 打包后包含 `compose.yaml`, `nginx.conf`, `setup.sh` 等文件

打包后离线安装包的目录结构为,

```
src/                        ->    source code of repo ak1ra-lab/kubespray
bootstrap.sh                ->    bootstrap script to setup kubespray deploy node
setup.sh                    ->    helper script to setup and start nginx, registry containers
nginx.conf                  ->    nginx.conf for files server
compose.yaml                ->    start nginx and registry containers
resources/
  registry/                 ->    downloaded images from temp/images.list in registry:2 format
  nginx/files/              ->    downloaded files from temp/files.list
  nginx/images/             ->    extra images in docker-archive format
  images.list               ->    copy of temp/images.list
  files.list                ->    copy of temp/files.list
```

## "半离线化"使用 kubespray 部署 Kubernetes 集群

### 设置 kubespray node

准备一台 服务器/虚拟机, 用作 kubespray node, 推荐使用 Debian 12 (bookworm),

* 使用系统包管理器安装 `python3 python3-pip python3-venv jq`
* 这台服务器会用作 kubespray node 也即 Ansible controller node, 用于安装 Kubernetes 集群
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
* 切换到 kubespray 源代码目录, 设置 Python venv 环境, 并 Python 相关依赖
* 对于这台 kubespray node, 可以把 [inventory/kubespray-offline/group_vars/all/offline.yml](https://github.com/ak1ra-lab/kubespray/blob/kubespray-offline/inventory/kubespray-offline/group_vars/all/offline.yml) 中的 `registry_host` 和 `files_repo` 项修改为本机 IP

一般来说, 离线安装包只需要配置一次.

后续如有新安装集群需求, 只需要复制 [inventory/kubespray-offline](https://github.com/ak1ra-lab/kubespray/tree/kubespray-offline/inventory/kubespray-offline) 目录作为基础 inventory 目录, 不需要重复执行设置 kubespray node.

本目录下的 [bootstrap.sh](https://github.com/ak1ra-lab/kubespray/blob/kubespray-offline/contrib/kubespray-offline/bootstrap.sh) 脚本描述了上述流程, 可以直接使用, 如:

```shell
wget -c https://raw.githubusercontent.com/ak1ra-lab/kubespray/kubespray-offline/contrib/kubespray-offline/bootstrap.sh
bash -x bootstrap.sh
```

### 使用 kubespray 安装 Kubernetes 集群

规划好要部署的集群节点, 准备好安装 Kubernetes 的 服务器/虚拟机, 需要在各个节点上添加 kubespray 所在服务器的公钥, 即配置好免密登录.

以示例 `inventory/offline` 目录为模板, 每次创建新集群都以这个目录为模板, 根据实际需求修改 inventory 中配置, 比较重要的配置有,

* `group_vars/all/all.yml`
* `group_vars/all/containerd.yml`
* `group_vars/all/offline.yml`
* `group_vars/k8s_cluster/k8s-cluster.yml`

> `inventory/offline` 相对于 kubespray 所提供的 `inventory/sample` 示例配置做了一些额外修改.

以新创建单节点集群 `k8s-alpha` 为例, 待安装节点为 `172.16.4.31`,

```shell
cp -r inventory/kubespray-offline inventory/k8s-alpha

export CONFIG_FILE=inventory/k8s-alpha/hosts.yaml
python3 contrib/inventory_builder/inventory.py k8s-alpha-node01,172.16.4.31

ansible-playbook -i inventory/k8s-alpha/hosts.yaml --become --become-user=root cluster.yml
```

之后等待集群安装完成即可.
