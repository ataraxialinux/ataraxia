# Welcome to Ataraxia GNU/Linux
Ataraxia GNU/Linux is an independent [Linux-based OS](https://www.kernel.org/) focusing on simplicity, security and privacy.

![Downloads](
https://img.shields.io/github/downloads/ataraxialinux/ataraxia/total.svg)

# Intro
Ataraxia GNU/Linux is a [Linux-based operating system](https://www.kernel.org/), it was made from scratch and it follows three main principles: security, privacy and simplicity. Ataraxia GNU/Linux tries to be an innovative OS and therefore uses latest technologies from the [GNU/Linux](https://www.gnu.org/gnu/linux-and-gnu.html) world. Ataraxia GNU/Linux is different from other distributions, for example it uses [musl libc](https://www.musl-libc.org/) as the standard C library, [LLVM](https://llvm.org/)/[Clang](https://clang.llvm.org/) toolchain as the default compiler, a significantly more secure SSL/TLS library called [LibreSSL](https://www.libressl.org/) and simple userland tools such as [Toybox](http://landley.net/toybox/about.html) and lobase ([OpenBSD](https://www.openbsd.org/) userland for Linux). Ataraxia GNU/Linux is oriented towards professional Linux users.

# Simplicity
Despite using systemd, Ataraxia GNU/Linux is adhering a KISS (Keep It Simple Stupid) principle. It replaces mainstream components with simpler alternatives which do not sacrifice user experience. musl libc, toybox and lobase are just a few of them! Our code is simple and understandable that means it's easier to audit and/or fork.

# Security
Like other popular distributions, Ataraxia GNU/Linux was compiled with PIC, PIE, SSP. However, Ataraxia GNU/Linux configures software to be more secure and it tries to decrease attack surface. Kernel is configured for better security, without compromise. Ataraxia GNU/Linux will provide new mitigations and security features like Control Flow Integrity (CFI), fork of PaX patchset.

# Privacy
Ataraxia GNU/Linux does not collect any form of data and it does not allow proprietary software in its repositories. Proprietary software is known as a main tool to violate user's privacy. Furthermore, Ataraxia GNU/Linux developers are patching software to avoid any data collection.

If you want to get help or advice, please, check out our [IRC](ircs://chat.freenode.net:6697/#ataraxialinux), [Telegram](https://t.me/ataraxialinux), [Matrix](https://matrix.to/#/#ataraxialinux:matrix.org), [Reddit](https://www.reddit.com/r/ataraxialinux/) and [Discord](https://discord.gg/sCQGvzz).

Also, you can help us with finances. Check out our [Patreon page](https://www.patreon.com/ataraxialinux)
and Ethereum wallet: 0xE72931051e4aDB1c79bbAcad1E1427B2D4eD0D01

[GitLab repository](https://gitlab.com/ataraxialinux/ataraxia)
[GitHub repository](https://github.com/ataraxialinux/ataraxia)

## Documentation
* [About the build system](docs/aboutbuildsystem.md)
* [Bootstrapping](docs/bootstrapping.md)
* [Supported platforms](docs/platforms.md)
* [Roadmap](docs/roadmap.md)

See the ./docs/ folder.

## Stargazers over time
[![Stargazers over time](https://starchart.cc/ataraxialinux/ataraxia.svg)](https://starchart.cc/ataraxialinux/ataraxia)
