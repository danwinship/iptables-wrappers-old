#!/bin/sh

# NOTE: This can only use POSIX /bin/sh features; the container image
# may not contain bash.
set -eu

case "$1" in
    --install)
	# Build-time setup: replace iptables binaries with wrappers

	# Ensure dependencies are installed
	if ! /usr/sbin/iptables-nft --version &> /dev/null; then
	    echo "ERROR: iptables-nft is not installed" 1>&2
	    exit 1
	fi
	if ! /usr/sbin/iptables-legacy --version &> /dev/null; then
	    echo "ERROR: iptables-legacy is not installed" 1>&2
	    exit 1
	fi

	# Create the wrapper
	rm -f /usr/sbin/iptables
	cat > /usr/sbin/iptables <<EOF
#!/bin/sh

set -eu

cmd=$(basename "$0")

cache_file="/var/run/iptables-mode"
mode=$(cat "${cache_file}" 2>/dev/null || /bin/true)

case ${mode:-} in
    nft|legacy)
        ;;
    *)
        # Because of how iptables works, there isn't really any solution
        # that's much faster than this
        legacy_lines=$(iptables-legacy-save 2>/dev/null | wc -l || echo 0)
        nft_lines=$(iptables-nft-save 2>/dev/null | wc -l || echo 0)
        if [ "${legacy_lines}" -lt "${nft_lines}" ]; then
            mode=nft
        else
            mode=legacy
        fi
        (umask 0222; echo -n "${mode}" > "${cache_file}" || /bin/true) 2>/dev/null
        ;;
esac

exec "xtables-${mode}-multi" "${cmd}" "$@"
EOF

	# Link the wrapper
	for cmd in iptables-save iptables-restore ip6tables ip6tables-save ip6tables-restore; do
	    rm -f /usr/sbin/$cmd
	    ln /usr/sbin/$cmd /usr/sbin/iptables
	done

	exit 0
	;;

    --detect)
	# Run-time setup: replace iptables binaries with correct links

	# Because of how iptables works, there isn't really any solution
	# that's much faster than this
	legacy_lines=$(iptables-legacy-save 2>/dev/null | wc -l || echo 0)
	nft_lines=$(iptables-nft-save 2>/dev/null | wc -l || echo 0)
	if [ "${legacy_lines}" -lt "${nft_lines}" ]; then
	    mode=nft
	else
	    mode=legacy
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

	exit 0
	;;

    *)
	echo "Usage: $0 [ --install | --detect ]" 1>&2
	exit 1
	;;

esac
