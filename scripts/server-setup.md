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

## Nginx setup

Make sure it is installed: `sudo apt install nginx`

Put the nginx config into /etc/nginx/sites-enabled

```
# Configuration for the pacoplay.com website

# Production server pacoplay.com
server {
    listen 80;
    listen [::]:80;

    server_name pacoplay.com;

    location /websocket {
        proxy_pass http://localhost:3012;
    }

    location / {
        proxy_pass http://localhost:8000;
    }
}

# Test server dev.pacoplay.com
server {
    listen 80;
    listen [::]:80;

    server_name dev.pacoplay.com;

    location /websocket {
        proxy_pass http://localhost:3011;
    }

    location / {
        proxy_pass http://localhost:8001;
    }
}
```

Restart nginx: `sudo service nginx restart`.

## Do the letsencrypt setup with certbot

https://certbot.eff.org/lets-encrypt/ubuntufocal-nginx

```
# Install certbot
sudo snap install --classic certbot

# link it into the path
sudo ln -s /snap/bin/certbot /usr/bin/certbot

# Request certificates
sudo certbot --nginx
```

You'll note that this updates the nginx configuration.
