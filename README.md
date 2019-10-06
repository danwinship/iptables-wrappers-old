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
network namespace, install iptables 1.8.3 or later using whatever
tools you normally would, copy the
`[iptables-wrapper-installer.sh](./iptables-wrapper-installer.sh)`
script into some location in your container, and run it to have it set
up run-time autodetection. eg:

- Debian buster

      # Install iptables from buster-backports to get 1.8.3
      RUN echo deb http://deb.debian.org/debian buster-backports main >> /etc/apt/sources.list; \
          apt-get update; \
          apt-get -t buster-backports -y --no-install-recommends install iptables
      COPY iptables-wrapper-installer.sh /root
      RUN /root/iptables-wrapper-installer.sh

- Fedora 29+

      RUN dnf install -y iptables iptables-nft
      COPY iptables-wrapper-installer.sh /root
      RUN /root/iptables-wrapper-installer.sh

`iptables-wrapper-installer.sh` will install new `iptables`,
`ip6tables`, `iptables-restore`, `ip6tables-restore`, `iptables-save`,
and `ip6tables-save` wrappers in `/usr/sbin`. Other software in the
container can then just run "`iptables`", "`iptables-save`", etc,
normally. The first time any of the wrappers runs, it will figure out
which mode the system is using and then update the links in
`/usr/sbin` to point to either the nft or legacy copies of iptables as
appropriate.
