#!/bin/sh
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

set -eu

INSTALLER="iptables-wrapper-installer.sh"
WRAPPER="/usr/sbin/iptables-wrapper"

trap "test -e ${INSTALLER}.test && rm ${INSTALLER}.test" EXIT

# Verify installer gets removed after invocation
#
cp "${INSTALLER}" "${INSTALLER}.test"
sh "${INSTALLER}.test" --no-sanity-check
! test -e "${INSTALLER}"

# verify installer sets up wrappers correctly
#
cp "${INSTALLER}" "${INSTALLER}.test"
sh "${INSTALLER}.test" --no-sanity-check
for cmd in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
    test -h "/usr/sbin/${cmd}"
    test "$(readlink -f /usr/sbin/${cmd})" = "${WRAPPER}"
done

# verify variant is properly chosen
#
for chosen in legacy nft; do
    cp "${INSTALLER}" "${INSTALLER}.test"
    sh "${INSTALLER}.test" --no-sanity-check
    iptables-legacy -F
    iptables-nft -F
    iptables-${chosen} -A INPUT -j ACCEPT
    iptables -L > /dev/null
    test -h /usr/sbin/iptables
    test "$(readlink -f /usr/sbin/iptables)" = "/usr/sbin/xtables-${chosen}-multi"
done

# verify -nft wins in case of tie
#
cp "${INSTALLER}" "${INSTALLER}.test"
sh "${INSTALLER}.test" --no-sanity-check
iptables-legacy -F
iptables-nft -F
iptables-legacy -A INPUT -j ACCEPT
iptables-nft -A INPUT -j ACCEPT
iptables -L > /dev/null
test -h /usr/sbin/iptables
test "$(readlink -f /usr/sbin/iptables)" = "/usr/sbin/xtables-nft-multi"
