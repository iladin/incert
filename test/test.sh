#!/bin/bash

# Test script for incert
# Assumes incert is at "../incert" and docker is available

set -e
# nice debugging
set -x
export PS4='+${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): } '
cd "$(dirname "$0")"

export PATH=~/go/bin:$PATH

cleanup() { 
  docker rm -f $NGINX  cfssl 
#  docker rmi -f cfssl/cfssl cgr.dev/chainguard/nginx
  rm -rf selfsigned{.pem,-key.pem,.csr}
}

trap cleanup EXIT

# create self-signed cert
go install github.com/cloudflare/cfssl/cmd/...@latest
cfssl selfsign www.example.net csr.json | cfssljson -bare selfsigned
file selfsigned* || true # do not fail you if you don't have file for whatever reason

# Set appropriate permissions for the certificate key file
sudo chmod 644 selfsigned*

# Run nginx with private key and cert
docker run -p 8443:8443  \
  -v $PWD/nginx.default.conf:/etc/nginx/conf.d/nginx.default.conf \
  -v $PWD/selfsigned.pem:/etc/nginx/conf.d/cert.pem \
  -v $PWD/selfsigned-key.pem:/etc/nginx/conf.d/key.pem \
  --health-cmd='curl https://localhost:8443' \
  --health-interval=30s \
  --health-timeout=10s \
  --health-retries=3 \
  cgr.dev/chainguard/nginx &


# now create container with cert
IMAGE=ttl.sh/incert/test-default-$RANDOM:20m
go run ../main.go --ca-certs-file selfsigned.pem --image-url ${1:-cgr.dev/chainguard/curl:latest} --dest-image-url $IMAGE

# check insecure curl works
docker run --rm --network host --add-host example.com:127.0.0.1 cgr.dev/chainguard/curl:latest-dev -k https://example.com:8443

# try secure curl 
docker run --rm  --network host --add-host example.com:127.0.0.1 $IMAGE https://example.com:8443

# test using platform argument
IMAGE=ttl.sh/incert/test-arm64-default-$RANDOM:20m
export DOCKER_DEFAULT_PLATFORM=linux/arm64
docker buildx create --use || true # test fix 
go run ../main.go --ca-certs-file selfsigned.pem --image-url cgr.dev/chainguard/curl:latest --platform $DOCKER_DEFAULT_PLATFORM --dest-image-url $IMAGE
docker run --rm --network host --add-host example.com:127.0.0.1 $IMAGE https://example.com:8443
