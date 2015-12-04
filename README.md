# Deploy a dockerised web app over HTTPS with letsencrypt.

This repo uses docker-compose to deploy any dockerised web app over HTTPS. 

## How it works

When you bring up the service with ```docker-compose up```, docker compose starts an nginx reverse proxy, your app container, and the official letsencrypt container.

The proxy image's init script starts nginx in the initial config:

[Imgur](http://i.imgur.com/nHy2sEH.png)

```nginx
events { worker_connections 1024; }
http {
	server {
		listen 80;
		server_name ___my.example.com___;

		location /.well-known/acme-challenge {
			proxy_pass http://___LETSENCRYPT_IP___:___LETSENCRYPT_PORT___;
			proxy_set_header Host            $host;
			proxy_set_header X-Forwarded-For $remote_addr;
			proxy_set_header X-Forwarded-Proto https;
		}

		location / {
			proxy_pass http://___APPLICATION_IP___:___APPLICATION_PORT___;
			proxy_set_header Host            $host;
			proxy_set_header X-Forwarded-For $remote_addr;
		}

	}
}
```

The initial config allows letsencrypt's acme challenge to get to the letsencrypt container. The letsencrypt container runs in _standalone_ mode, connecting to letsencrypt.org to make the cert request and then waiting on port 80 for the acme-challenge. 

When letsencrypt issues the challenge request, the le client writes the certs to /etc/letsencrypt, which is a volume mounted to the nginx container. The nginx container's init script notices the certs appear, and loads a new config, setting up the https port forward.

[Imgur](http://i.imgur.com/iGOGUgn.png)

```nginx
events { worker_connections 1024; }
http {
	server {
		listen 80;
		server_name ___my.example.com___;

		location /.well-known/acme-challenge {
			proxy_pass http://___LETSENCRYPT_IP___:___LETSENCRYPT_PORT___;
			proxy_set_header Host            $host;
			proxy_set_header X-Forwarded-For $remote_addr;
			proxy_set_header X-Forwarded-Proto https;
		}

		location / {
			return         301 https://$server_name$request_uri;
		}

	}

	server {
		listen 443;
		server_name ___my.example.com___;

		ssl on;
		ssl_certificate /etc/letsencrypt/live/___my.example.com___/fullchain.pem;
		ssl_certificate_key /etc/letsencrypt/live/___my.example.com___/privkey.pem;
		ssl_session_timeout 5m;
		ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
		ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
		ssl_prefer_server_ciphers on;

		ssl_session_cache shared:SSL:10m;
		ssl_dhparam /etc/ssl/private/dhparams.pem;

		location /.well-known/acme-challenge {
			proxy_pass http://___LETSENCRYPT_HTTPS_IP___:___LETSENCRYPT_HTTPS_PORT___;
			proxy_set_header Host            $host;
			proxy_set_header X-Forwarded-For $remote_addr;
			proxy_set_header X-Forwarded-Proto https;
		}

		location / {
			proxy_pass http://___APPLICATION_IP___:___APPLICATION_PORT___;
			proxy_set_header Host            $host;
			proxy_set_header X-Forwarded-For $remote_addr;
		}
	}
}
```

The service is now running over https. The letsencrypt container exited - this is what we want.

## How to run it

You need a docker server running on the public internet, with a DNS entry pointing at it. If you dont have this, see part 1 of this blog entry.

```
git clone git@bitbucket.org:automationlogic/le-docker-compose.git
cd le-docker-compose
```

Open up docker-compose.yml, and change the two instances of ```www.yourdomain.co.uk``` with the dns name your docker server is running at. Then,

```
docker-compose  build
docker-compose  up
```

An example app is now running securely. Try it with your browser!


## Integrate your app

To use this with your own dockerised web server, edit docker-compose again.

Replace this section:

```
app:
  build: mock_server
  ports:
    - "80"
```

with 

```
app:
  build: yourimage
  ports:
    - "80"
```

and then run

```
docker-compose rm -f
docker-compose up
```

## Renew your certificate

Start the letsencrypt container with docker compose. The container starts, runs the acme process, and exits.

```
docker-compose run letsencrypt
```

Then, reload the nginx config

```
docker exec ledockercompose_nginx_1 nginx -s reload
```

Done.





