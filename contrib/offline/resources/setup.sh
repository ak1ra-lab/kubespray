#! /bin/bash
# helper script to setup and start nginx, registry containers

function setup() {
    # install nerdctl-full-*
    tar -xf $(find . -type f -name 'nerdctl-full-*.tar.gz' | sort -r --version-sort | head -n1) -C /usr/local

    # start and enable buildkit
    systemctl enable buildkit.service containerd.service
    systemctl restart buildkit.service containerd.service

    # load registry and nginx images
    test -f nginx/images/registry.tar && nerdctl image load -i nginx/images/registry.tar
    test -f nginx/images/nginx.tar && nerdctl image load -i nginx/images/nginx.tar

    # start registry and nginx containers
    nerdctl compose -f compose.yaml up -d
}

setup $@
