# iptables-wrappers

This repository consists of wrapper scripts to help with using
iptables in containers.

## Background

As of iptables 1.8, the iptables command line clients come in two
different versions/modes: "legacy", which uses the kernel iptables API
just like iptables 1.6 and earlier did, and "nft", which translates
the iptables command-line API into the kernel nftables API.

Because they connect to two different subsystems in the kernel, you
cannot mix and match between them; in particular, if you are adding a
new rule that needs to run either before or after some existing rules
(such as the system firewall rules), then you need to create your rule
with the same iptables mode as the other rules were created with,
since otherwise the ordering may not be what you expect. (eg, if you
*prepend* a rule using the nft-based client, it will still run *after*
all rules that were added with the legacy iptables client.)

In particular, this means that if you create a container image that
will make changes to iptables rules in the host network namespace, and
you want that container to be able to work on any host, then you need
to figure out at run time which mode the host is using, and then also
use that mode yourself. This wrapper is designed to do that for you.

### Additional iptables-nft 1.8.0-1.8.2 compatibility problems

In addition to the general problem of needing to use the right mode,
there is a second problem with iptables 1.8, which is that the first
few releases (1.8.0, 1.8.1, and 1.8.2) had bugs in nft mode that made
them not work with kubelet and some other programs. In particular:

  - Some commands did not exit with success or failure in exactly the
    same situations as the legacy clients. Eg, with the legacy
    clients, `iptables -F CHAIN` would exit with an error if the chain
    did not exist, but with the nft-based clients up to 1.8.2, it
    would exit with success.

  - In some cases it was possible to add a rule with `iptables -A` but
    then have `iptables -C` claim that the rule did not exist. (This
    led to kubelet repeatedly creating more and more copies of the
    same rule, thinking it had not been created yet.)

iptables 1.8.3 fixes these compatibility problems, but has a slightly
different problem, which is that `iptables-nft` will get stuck in an
infinite loop if it can't load the kernel `nf_tables` module. The
wrapper script has code to deal with this.

All currently-known problems will be fixed in iptables 1.8.4.

## iptables-wrapper

The `iptables-wrapper-installer.sh` script in this repo will install
an `iptables-wrapper` script alongside `iptables-legacy` and
`iptables-nft` in `/usr/sbin` (or `/sbin`), and adjust the symlinks on
`iptables`, `iptables-save`, etc, to point to the wrapper.

(Because of the known bugs, `iptables-wrapper-installer.sh` will
refuse to install the wrappers into a container with iptables earlier
than 1.8.2. If you really know what you're doing you can pass
`--no-sanity-check` to install anyway. Because it can work around the
bugs in 1.8.3, the installer will allow you to install with iptables
1.8.3.)

The first time the wrapper is run, it will figure out which mode the
system is using, update the `iptables`, `iptables-save`, etc, links to
point to either the nft or legacy copies of iptables as appropriate,
and then exec the appropriate binary. After that first call, the
wrapper will not be used again; future calls to iptables will go
directly to the correct underlying binary.

## Building a container image that uses iptables

When building a container image that needs to run iptables in the host
network namespace, install iptables 1.8.3 or later in the container
using whatever tools you normally would. Then copy the
[`iptables-wrapper-installer.sh`](./iptables-wrapper-installer.sh)
script into your container, and run it to have it set up run-time
autodetection.

Some distro-specific examples:

- Alpine Linux

      FROM alpine:3.10

      RUN apk add --no-cache iptables
      COPY iptables-wrapper-installer.sh /
      RUN /iptables-wrapper-installer.sh

- Debian GNU/Linux

  Debian stable (buster) ships iptables 1.8.2, but iptables 1.8.3 is
  available in buster-backports, so you should install it from there:

      FROM debian:buster

      RUN echo deb http://deb.debian.org/debian buster-backports main >> /etc/apt/sources.list; \
          apt-get update; \
          apt-get -t buster-backports -y --no-install-recommends install iptables

      COPY iptables-wrapper-installer.sh /
      RUN /iptables-wrapper-installer.sh

- Fedora

  At the moment, Fedora 30 still ships iptables 1.8.2. This should
  eventually be fixed. For now, if you are shipping a container image
  that you know is not affected by the compatibility bugs, you can
  pass `--no-sanity-check` to the installer to make it not check the
  iptables version:

      FROM fedora:30

      RUN dnf install -y iptables iptables-nft

      COPY iptables-wrapper-installer.sh /
      RUN /iptables-wrapper-installer.sh --no-sanity-check

- RHEL / CentOS

  RHEL/CentOS 7 ship iptables 1.4, which does not support nft mode.
  RHEL/CentOS 8 ship a hacked version of iptables 1.8 that *only*
  supports nft mode. Therefore, neither can be used as a basis for a
  portable iptables-using container image.
