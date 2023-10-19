#!/bin/sh

# Check if the user is root (superuser)
if [[ $EUID -eq 0 ]]; then
  echo "This script cannot not be run as root."
  exit 1
fi

if [ -d "easyrsa" ]; then
    echo "Error: easyrsa folder exists. Remove it before proceeding (rm -rf easyrsa)"
    exit 2
fi

mkdir easyrsa
cd easyrsa

# Version of easyrsa to download
version="3.1.5"

echo Getting easy-rsa $version into the ./easyrsa folder
easy_rsa_url="https://github.com/OpenVPN/easy-rsa/releases/download/v$version/EasyRSA-$version.tgz"
echo "Downloading $easy_rsa_url"
curl -O -L $easy_rsa_url

tar -xzvf EasyRSA-$version.tgz 
mv ./EasyRSA-$version/* .
rmdir ./EasyRSA-$version
echo `pwd`
echo Initializing the public key infrastructure
./easyrsa init-pki

echo Building the certificate authority
./easyrsa build-ca


export EASYRSA_CERT_EXPIRE=9999

echo Generating server certificate server
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa show-cert server

echo Generating the Diffie Hellman parameters
./easyrsa gen-dh

echo Copying server files to certs folder...
cp ./pki/ca.crt ../certs/
cp ./pki/issued/server.crt ../certs/
cp ./pki/private/server.key ../certs/
cp ./pki/dh.pem ../certs/

cd ..
echo Generating client certicicate...
./add_cert.sh client

