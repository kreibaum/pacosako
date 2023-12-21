# Setting up the server

If I need to set up a new server, this documentation should help me get started.

Things I have done:

- Setting up Ubuntu livepatch

```
$ sudo apt update
$ sudo apt install snapd
$ sudo snap install canonical-livepatch
$ sudo canonical-livepatch enable <token>
```

- create a pacosako user account with sudo previleges

```
$ adduser pacosako
$ usermod -aG sudo pacosako
```

- Make sure you can ssh in:

```
# Must be run on the client
$ ssh-keygen
$ ssh-add <path to the key>
$ ssh-copy-id -i <path to the key>
# Try it:
$ ssh pacosako@vm.example.com
```

- Disable ssh login for root and disable password login

See for example https://www.cyberciti.biz/faq/how-to-disable-ssh-password-login-on-linux/

- Disable password for sudo

https://askubuntu.com/questions/147241/execute-sudo-without-password

## Caddy setup

Make sure it is installed. I didn't write down how I did this.

# Storage space issues

[My Grafana dashboard](https://kreibaum.grafana.net/d/fc9d6a67-fd43-4045-83c2-fd79126809a3/pacoplay-a-peace-chess-variant-project?orgId=1&refresh=1d)
to monitor the server will show the current free disk space.

If the disk space is running low, I can investigate what is taking up space.

```sh
du -h --max-depth=2 | sort -hr | head -n 10
```

Here is an example of what I may find:

```
$ cd /
$ sudo du -h --max-depth=2 | sort -hr | head -n 10
7.3G	.
2.7G	./usr
2.6G	./var
1.9G	./usr/lib
1.5G	./snap
884M	./var/lib
864M	./var/log
856M	./var/cache
589M	./snap/core
495M	./snap/core22
```

Make sure to also run this in `~` as well. A lot of the big things in `/` are
probably not things I can do anything about. But in `~` I may find some big
files that I can delete.

You can also run `sudo apt autoremove`, that often gets rid of some stuff and
is easy to do.