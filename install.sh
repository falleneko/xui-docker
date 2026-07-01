#!/bin/bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install -y docker-ce docker-compose-plugin openssl
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
cd /opt
sudo mkdir vlpanel
sudo chown $USER:$USER vlpanel
cd vlpanel
mkdir certs
cd certs
openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
  -keyout privkey.pem \
  -out cert.pem \
  -subj "/C=EU/ST=BG/L=Burgas/O=VlPanel/OU=VlPanel/CN=server"
cd ..
cat << EOF > docker-compose.yaml
services:
  3xui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: xui
    restart: unless-stopped
    volumes:
      - ./db:/etc/x-ui
      - ./logs:/var/log/xray
      - ./cert:/root/cert
    environment:
      XUI_ENABLE_FAIL2BAN: "true"
    tty: true
    ports:
      - "29160-29170:29160-29170"
    networks:
      - vpn-net
  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "443:443"
    volumes:
      - ./nginx/:/etc/nginx/conf.d
      - ./cert:/etc/nginx/cert:ro
    networks:
      - vpn-net
networks:
  vpn-net:
    driver: bridge
EOF
mkdir nginx
cat << EOF > nginx/srv.conf
server {
    listen 443 ssl;
 
    ssl_certificate     /etc/nginx/cert/cert.pem;
    ssl_certificate_key /etc/nginx/cert/privkey.pem;
 
    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_ciphers               HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache         shared:SSL:10m;
    ssl_session_timeout       10m;
 
    location / {
        proxy_pass         http://3xui:2053; 
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /vlsub/ {
        proxy_pass         http://3xui:2096;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

}
 
server {
    listen 80;
    return 301 https://$host$request_uri;
}
EOF
docker compose up -d
