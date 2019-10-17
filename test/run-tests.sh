#!/bin/bash
#
# Copyright 2019 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

if podman -h &> /dev/null; then
    echo "Using podman"
    docker=podman
elif docker -h &> /dev/null; then
    if docker version &> /dev/null; then
	echo "Using docker"
	docker=docker
    else
	echo "Using 'sudo docker'"
	docker="sudo docker"
	# Get the password prompting out of the way now
	${docker} version > /dev/null
    fi
else
    echo "Could not find podman or docker" 1>&2
    exit 1
fi

cd $(dirname "$0")/..

function build() {
    build_tag=iptables-wrapper-test-$1
    dockerfile=Dockerfile.test-${1%%-*}
    shift

    ${docker} build --no-cache -q -t ${build_tag} -f test/${dockerfile} "$@" . > /dev/null
}

echo ""
echo "== debian buster (should fail)"
if build debian; then
    echo "debian buster build without buster-backports should have failed with iptables 1.8.2 compat error" 1>&2
    exit 1
fi

echo ""
echo "== debian buster with --no-sanity-check (should fail nft test)"
if ! build debian-nosanity --build-arg="INSTALL_ARGS=--no-sanity-check"; then
    echo "debian buster build with --no-sanity-check failed" 1>&2
    exit 1
fi
if ! ${docker} run --privileged iptables-wrapper-test-debian-nosanity /test.sh legacy; then
    echo "debian buster build without buster-backports failed legacy test" 1>&2
    exit 1
fi
if ${docker} run --privileged iptables-wrapper-test-debian-nosanity /test.sh nft; then
    echo "debian buster build without buster-backports should have failed nft test" 1>&2
    exit 1
fi

echo ""
echo "== debian buster with backports"
if ! build debian-backports --build-arg="REPO=buster-backports"; then
    echo "Debian buster build with buster-backports failed" 1>&2
    exit 1
fi
if ! ${docker} run --privileged iptables-wrapper-test-debian-backports /test.sh legacy; then
    echo "Debian buster build with buster-backports failed legacy test" 1>&2
    exit 1
fi
if ! ${docker} run --privileged iptables-wrapper-test-debian-backports /test.sh nft; then
    echo "Debian buster build with buster-backports failed nft test" 1>&2
    exit 1
fi

echo ""
echo "== Fedora 30 (should fail, for now)"
if build fedora; then
    echo "Fedora 30 build should have failed with iptables 1.8.2 compat error" 1>&2
    exit 1
fi

echo ""
echo "== Alpine"
if ! build alpine; then
    echo "Alpine build failed" 1>&2
    exit 1
fi
if ! ${docker} run --privileged iptables-wrapper-test-alpine /test.sh legacy; then
    echo "Alpine build failed legacy test" 1>&2
    exit 1
fi
if ! ${docker} run --privileged iptables-wrapper-test-alpine /test.sh nft; then
    echo "Alpine build failed nft test" 1>&2
    exit 1
fi

