#! /bin/bash
# helper script to setup and start nginx, registry containers

function setup() {
    # install nerdctl-full-*
    tar -xf $(find . -type f -name 'nerdctl-full-*.tar.gz' | sort -r --version-sort | head -n1) -C /usr/local

    # start and enable buildkit
    systemctl enable buildkit.service containerd.service
    systemctl restart buildkit.service containerd.service

    # load registry and nginx images
    for image in $(find resources/nginx/images/ -type f -name '*.tar'); do
        test -f $image && nerdctl image load -i $image
    done

    # start registry and nginx containers
    nerdctl compose -f compose.yaml up -d
}

setup $@
