
# kubespray-offline

## Overview

本目录为使用 kubespray "半离线化"部署 Kubernetes 集群方案所需文件.

因为没有把操作系统软件源部分也"离线化", 因此称之为"半离线化", 因此待安装节点并不能全程断网安装. 但是除此之外, 使用 kubespray 过程中所需要的文件和镜像已经全部包含, 缺少的部分只是操作系统软件源, 想要完全"离线化"部署, 可以参考 [k8sli/kubeplay](https://github.com/k8sli/kubeplay) 项目, 本项目正是在这个项目启发下开发, 使用 GitHub Actions 来下载必要的文件.

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

打包后离线安装资源的目录结构,

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

* 使用系统包管理器安装 `python3 python3-pip python3-venv`
* 这台服务器会用作 kubespray 的控制节点用于安装 Kubernetes 集群
* 托管离线资源的 nginx 与 registry 容器也会运行在这台服务器上
    * nginx 容器默认监听 8080 端口, registry 容器默认监听 5000 端口,
    * 要求这两个端口不能被占用, 因此最好在一台全新的服务器上操作

在 [ak1ra-lab/kubespray releases](https://github.com/ak1ra-lab/kubespray/releases) 页面下载离线安装资源

* 由于 GitHub Actions 对单文件大小的限制, 离线安装资源被做成多个分卷, 根据待安装集群节点的 CPU 架构下载对应架构的所有分卷, 目前支持 `amd64` 与 `arm64`
* 下载好后将所有分卷使用 `cat` 命令合并为一个文件
* 校验合并后文件的 checksum, 校验通过后解压离线安装文件
* 切换到解压后的目录 `resources/`, 执行该目录下的 `setup.sh` 脚本,
    * 会解压安装 `nerdctl-full-*` 至 `/usr/local` 目录
    * 启动 `buildkit` 与 `containerd` 服务并设置开机启动
    * 使用 `nerdctl image load` 导入 nginx 与 registry 镜像
    * 使用 `nerdctl compose -f compose.yaml up -d` 启动 nginx 与 registry 服务

当前构建的版本为 `v2.22.1-r1`, 注意实际部署时不要直接复制粘贴下方命令, 一般来说, 离线安装资源包只需要配置一次,

```
mkdir kubespray && cd kubespray/

wget -c https://github.com/ak1ra-lab/kubespray/releases/download/v2.22.1-r1/kubespray-offline-v2.22.1-r1-amd64.tar.gz.{01,02,03,sha256}

cat kubespray-offline-v2.22.1-r1-amd64.tar.gz.{01,02,03} > kubespray-offline-v2.22.1-r1-amd64.tar.gz

sha256sum -c kubespray-offline-v2.22.1-r1-amd64.tar.gz.sha256
kubespray-offline-v2.22.1-r1-amd64.tar.gz: OK

tar -xf kubespray-offline-v2.22.1-r1-amd64.tar.gz

cd kubespray-offline/ && bash setup.sh
```

准备 kubespray 源码, `kubespray-offline/kubespray-offline.tar.gz` 文件为一同打包的 offline 分支的 kubespray 源码, 不包含 git 历史提交记录, 可以直接使用这个, 也可以从 GitHub 克隆, 注意如果克隆的话需要切换到 `offline` 分支, 不然之后会找不到 `inventory/sample-offline` 目录.

```
tar -xf kubespray-offline.tar.gz && cd kubespray-offline/

python3 -m venv venv && source venv/bin/activate
python3 -m pip install -r requirements.txt
```

规划好要部署的集群节点, 准备好安装 Kubernetes 的 服务器/虚拟机, 需要在各个节点上添加 kubespray 所在服务器的公钥, 即配置好免密登录.

修改 `inventory/sample-offline/group_vars/all/offline.yml` 中的 `registry_host` 和 `files_repo` 项中的 `127.0.0.1` 为 kubespray 所在节点的 IP, 如,

```
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

```
cp -r inventory/sample-offline inventory/k8s-alpha-test

export CONFIG_FILE=inventory/k8s-alpha-test/hosts.yaml
python3 contrib/inventory_builder/inventory.py k8s-alpha-test-node01,172.16.10.10

ansible-playbook cluster.yml \
    -i inventory/k8s-alpha-test/hosts.yaml \
    --become --become-user=root
```

之后等待集群安装完成即可.
