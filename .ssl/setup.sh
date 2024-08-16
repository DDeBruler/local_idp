#!/usr/bin/env bash

SSL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
APP_DIR="$(dirname "$SSL_DIR")"

# Generate an SSL signing certificate
if [ ! -f "${SSL_DIR}/idp-private-key.pem" ]; then
  openssl req \
    -x509 \
    -new \
    -newkey rsa:4096 \
    -nodes \
    -subj '/C=US/ST=Georgia/L=Atlanta/O=Dan DeBruler/CN=Test Identity Provider' \
    -keyout ${SSL_DIR}/idp-private-key.pem \
    -out ${SSL_DIR}/idp-public-cert.pem \
    -days 7300
fi

# Generate self-signed HTTPS certificate
if [ ! -f "${SSL_DIR}/localhost.crt" ]; then
  openssl req -new -config ${SSL_DIR}/local-req.cnf -keyout ${SSL_DIR}/localhost.key -out ${SSL_DIR}/localhost.csr
  openssl x509 -req -sha256 -days 7300 -extfile ${APP_DIR}/.ssl/v3.ext -in ${SSL_DIR}/localhost.csr -signkey ${SSL_DIR}/localhost.key -out ${SSL_DIR}/localhost.crt
fi

# Set up nginx proxy
if [ -d "/etc/nginx/sites-enabled" ]; then
  NGINX_SERVER_DIR=/etc/nginx/sites-enabled
  [ "$UID" -eq 0 ] || exec sudo "$0" "$@"
elif [ -d "/usr/local/etc/nginx/servers" ]; then
  NGINX_SERVER_DIR=/usr/local/etc/nginx/servers
else
  echo "Unable to identify nginx server directory"
  exit 1
fi
mkdir -p $NGINX_SERVER_DIR
cp $SSL_DIR/sso_idp.conf $NGINX_SERVER_DIR
perl -pi -e "s@\[REPLACE_ME\]@$APP_DIR@g" $NGINX_SERVER_DIR/sso_idp.conf


if ! grep -q "localsso.com" /etc/hosts; then
  sudo -- sh -c "echo '' >> /etc/hosts"
  sudo -- sh -c "echo '127.0.0.1 localsso.com' >> /etc/hosts"
fi
