#!/bin/sh

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

# NOTE: This can only use POSIX /bin/sh features; the container image
# may not contain bash.

set -eu

if [ "$#" -eq 0 ] || [ "$1" != "--no-sanity-check" ]; then
    # Ensure dependencies are installed
    if ! version=$(/usr/sbin/iptables-nft --version 2> /dev/null); then
        echo "ERROR: iptables-nft is not installed" 1>&2
        exit 1
    fi
    if ! /usr/sbin/iptables-legacy --version > /dev/null 2>&1; then
        echo "ERROR: iptables-legacy is not installed" 1>&2
        exit 1
    fi

    case "${version}" in
    *v1.8.[01]\ *)
        echo "ERROR: iptables 1.8.0 - 1.8.2 have compatibility bugs." 1>&2
        echo "       Upgrade to 1.8.3 or newer." 1>&2
        exit 1
        ;;

    *v1.8.2\ *)
        case $(rpm -q iptables || true) in
        *.el8.*)
            # RHEL 8 has iptables "v1.8.2" but it has the fixes backported from 1.8.3
            ;;
        *)
            echo "ERROR: iptables 1.8.0 - 1.8.2 have compatibility bugs." 1>&2
            echo "       Upgrade to 1.8.3 or newer." 1>&2
            exit 1
            ;;
        esac
        ;;

    *)
        # 1.8.3+ are OK
        ;;
    esac
fi

# Create the wrapper
rm -f /usr/sbin/iptables-wrapper
cat > /usr/sbin/iptables-wrapper <<'EOF'
#!/bin/sh

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

# NOTE: This can only use POSIX /bin/sh features; the container image
# may not contain bash.

set -eu

# Detect whether the base system is using iptables-legacy or
# iptables-nft. This assumes that some non-containerized process (eg
# kubelet) has already created some iptables rules.
num_legacy_lines=$( (iptables-legacy-save || true; ip6tables-legacy-save || true) 2>/dev/null | wc -l)
num_nft_lines=$( (iptables-nft-save || true; ip6tables-nft-save || true) 2>/dev/null | wc -l)
if [ "${num_legacy_lines}" -gt "${num_nft_lines}" ]; then
    mode=legacy
else
    mode=nft
fi

# Replace the wrapper scripts with the real binaries
if [ -x /usr/sbin/alternatives ]; then
    # Fedora/SUSE style
    alternatives --set iptables "/usr/sbin/iptables-${mode}" > /dev/null || failed=1
elif [ -x /usr/sbin/update-alternatives ]; then
    # Debian style
    update-alternatives --set iptables "/usr/sbin/iptables-${mode}" > /dev/null || failed=1
    update-alternatives --set ip6tables "/usr/sbin/ip6tables-${mode}" > /dev/null || failed=1
else
    # No alternatives system
    for cmd in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
        rm -f "/usr/sbin/${cmd}"
        ln -s "/usr/sbin/xtables-${mode}-multi" "/usr/sbin/${cmd}"
    done 2>/dev/null || failed=1
fi

if [ "${failed}" = 1 ]; then
    echo "Unable to redirect iptables binaries. (Are you running in an unprivileged pod?)" 1>&2
    # fake it, though this will probably also fail if they aren't root
    exec "/usr/sbin/xtables-${mode}-multi" "$0" "$@"
fi

# Now re-exec the original command with the newly-selected alternative
exec "$0" "$@"
EOF

# Link the wrapper
for cmd in iptables-wrapper-save iptables-wrapper-restore ip6tables-wrapper ip6tables-wrapper-save ip6tables-wrapper-restore; do
    rm -f "/usr/sbin/${cmd}"
    ln -s /usr/sbin/iptables-wrapper "/usr/sbin/${cmd}"
done

if [ -x /usr/sbin/alternatives ]; then
    # Fedora/SUSE style
    alternatives \
        --install /usr/sbin/iptables iptables /usr/sbin/iptables-wrapper 100 \
        --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-wrapper-restore \
        --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-wrapper-save \
        --slave /usr/sbin/ip6tables iptables /usr/sbin/ip6tables-wrapper \
        --slave /usr/sbin/ip6tables-restore iptables-restore /usr/sbin/ip6tables-wrapper-restore \
        --slave /usr/sbin/ip6tables-save iptables-save /usr/sbin/ip6tables-wrapper-save
elif [ -x /usr/sbin/update-alternatives ]; then
    # Debian style
    update-alternatives \
        --install /usr/sbin/iptables iptables /usr/sbin/iptables-wrapper 100 \
        --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-wrapper-restore \
        --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-wrapper-save
    update-alternatives \
        --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-wrapper 100 \
        --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-wrapper-restore \
        --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-wrapper-save
else
    # No alternatives system
    for cmd in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
        rm -f "/usr/sbin/${cmd}"
        ln -s /usr/sbin/iptables-wrapper "/usr/sbin/${cmd}"
    done
fi

# Cleanup
rm -f "$0"
