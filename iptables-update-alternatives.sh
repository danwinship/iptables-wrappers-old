#!/bin/sh

## iptables-update-alternatives.sh: detects which iptables mode is in
## use on this system and then updates the links in /usr/sbin
## accordingly.

# NOTE: This can only use POSIX /bin/sh features; the container image
# may not contain bash.
set -eu

if ! /usr/sbin/iptables-nft --version &> /dev/null; then
    echo "ERROR: iptables-nft is not installed" 1>&2
    exit 1
fi
if ! /usr/sbin/iptables-legacy --version &> /dev/null; then
    echo "ERROR: iptables-legacy is not installed" 1>&2
    exit 1
fi

num_legacy_lines=$(iptables-legacy-save 2>/dev/null | wc -l || echo 0)
num_nft_lines=$(iptables-nft-save 2>/dev/null | wc -l || echo 0)
if [ "${num_legacy_lines}" -gt "${num_nft_lines}" ]; then
    mode=legacy
else
    mode=nft
fi

if [ -x /usr/sbin/update-alternatives ]; then
    # Debian style
    update-alternatives --set iptables /usr/sbin/iptables-${mode}
    update-alternatives --set ip6tables /usr/sbin/ip6tables-${mode}
elif [ -x /usr/sbin/alternatives ]; then
    # Fedora/SUSE style
    alternatives --set iptables /usr/sbin/iptables-${mode}
else
    # No alternatives system
    for cmd in iptables iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
	rm -f /usr/sbin/${cmd}
	ln /usr/sbin/xtables-${mode}-multi /usr/sbin/${cmd}
    done
fi
