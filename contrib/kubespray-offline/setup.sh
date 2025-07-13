#!/bin/bash
# helper script to setup and start nginx, registry containers
set -e -o pipefail

main() {
    # install nerdctl-full-*
    tar -xf "$(find . -type f -name 'nerdctl-full-*.tar.gz' | sort -r --version-sort | head -n1)" -C /usr/local

    # start and enable buildkit
    systemctl enable buildkit.service containerd.service
    systemctl start buildkit.service containerd.service

    # load registry and nginx images
    find resources/nginx/images/ -type f -name '*.tar' -print0 | while IFS= read -r -d '' image; do
        test -f "${image}" && nerdctl image load -i "${image}"
    done

    # start registry and nginx containers
    nerdctl compose -f compose.yaml up -d
}

main "$@"
