# iptables-wrappers

This repository consists of wrapper scripts to help with using
iptables in containers.

## Background

As of iptables 1.8, there are two iptables modes: "legacy", using the
kernel iptables API as with iptables 1.6 and earlier, and "nft", which
translates the iptables command-line API into the kernel nftables API.
These modes are implemented by separate binaries, and by default
/usr/sbin/iptables, /usr/sbin/iptables-save, etc, will be symlinks to
one or the other set of binaries.

Mixing the two modes within a single network namespace will (in
general) not work and should be avoided. This means that processes
that run in containers but that make iptables changes in the host
network namespace need to be careful to use the same mode as the host
itself is configured to use. These wrappers are designed to make that
easier.

## Building a container image that uses iptables

When building a container image that needs to run iptables in the host
network namespace, install iptables normally, copy the
[iptables-wrapper-installer.sh](./iptables-wrapper-installer.sh)
script into some location in your container, and run it to have it set
up run-time autodetection. eg:

    RUN apt-get update && apt-get install -y iptables
    # or, eg, on Fedora:
    # RUN dnf install -y iptables iptables-nft

    COPY iptables-wrapper-installer.sh /root
    # Passing "--delete" makes it delete itself when it's done
    RUN /root/iptables-wrapper-installer.sh --delete

The other software in the container can then just run "iptables",
"iptables-save", etc, normally. This will give them the wrapper
script, which will select the correct underlying iptables mode
automatically.
