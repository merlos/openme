#!/bin/bash

# first argument is the name of the client
export EASYRSA_CERT_EXPIRE=9999

# Validate the number of arguments
if [[ $# -ne 1 ]]; then
  echo "Error: No spaces allowed in the client name"
  exit 1
fi

# Validate the first argument
if [[ -z $1 ]]; then
  echo "Usage: add_client client_name"
  exit 2
fi


if [[ ! $1 =~ ^[a-zA-Z0-9._\-]+$ ]]; then
  echo "The client name can only contain letters, numbers and the symbols - _ and ."
  exit 3
fi

echo "Creating client certificate..."
cd easyrsa
echo "Generating request..."
./easyrsa gen-req ${1} nopass
echo "Signing request..."
./easyrsa sign-req client ${1}

echo "Copying ./pki/private/${1}.key to ../certs/"
cp ./pki/private/${1}.key ../certs/
echo "Copying ./pki/issued/${1}.crt to ./certs/"
cp ./pki/issued/${1}.crt ../certs/
cd ..

echo "Done."