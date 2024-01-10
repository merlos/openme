# openme

[Work in progress]

Openme is a python script that runs a daemon that is able to open a predefined list of TCP/UDP ports in a GNU/Linux box through IP tables.

The goal is to minimize the attack surface with the premise that a service is only available to authenticated IPs and the firewall prevents others to enter. 

# How does it work?

There is one main service that acts as a doorman. If you have a valid authentication it opens you the door to the other services.  nstead of keeping all services open to the whole internet and preventing the access through authorization, the idea is that you only open those ports to particular IPs that are authenticated by a digital certificate.

Note that this is an already resolved problem. You can achieve the same by setting up a Virtual Private Network (VPN), such as OpenVPN, Wireguard.

This is just a learning coding exercise to think about how to apply information security practices and secure coding in a relatively simple scenario.


The typical setup scenarios are:

```
Home server
[Your client] <---> (the Internet) <--->[Router (NAT)] <----> [ GNU/Linux with services]

Cloud Server 
[Your client] <---> (the Internet) <--->[GNU/Linux with services]
```

# Setup

1. Clone the repo

```sh
git clone https://github.com/merlos/openme
cd openme
```

2. Setup the Certificate Authority. 

Openme uses certificates to authenticate and encrypt the requests. For that, you need a certificate authority (CA), in this case it's ok to have a self-signed CA.  If you already have a CA or you want to better control this part, then go to the advanced configuration, otherwise, there I provide some scripts that make easier creating the certs.

So, first, to setup the certificate authority and create one certificate for the server and another for the client. Use this script:

```sh
./setup_ca.sh
```
You will be prompted to:

1. Fill the certificate authority (CA) key passphrase. You'll be requested this password each time you add a new certificate. So, don't forget it.

2. Name your certificate autority. You can use whatever name you want. 

3. Type the CA password. To create the _server_ and _client_ certificates you'll be prompted to fill the password.

If you get stuck and you need to restart the CA, just remove the `easyrsa` folder using 

```sh
rm -rf easyrsa
```

The `setup_ca.sh` uses [easyrsa](https://github.com/OpenVPN/easy-rsa) behind the scenes, and it will create two folders:
1.  `easyrsa`, here is where your certificate authority resides (you should keep the contents of the folder) and,
2. `certs`, where all the generated certificates will be copied for your convenience.

The certificates created have an expiry time of more than **27 years**.

## Running the server
Ok. Now you have all ready to go.

```sh
cd daemon
pip install -r requirementst.xt
./openmed
```

## Running the client

Install requirements:

```sh
cd python-client
pip install -r requirements.txt
```

If the daemon is running on localhost:
```sh
./openme.py
```

If the dameon is running in another IP
```sh 
./openme.py -s server_ip_or_name

#Examples:

./openme.py -s 192.168.1.1
./openme.py -s openme.domain.com
```

By default, the server will open the IP address of the client. But you can also open it to guests

```sh
./openme.py --server 192.168.1.1 --port 54154 --ip-address 10.10.1.1
```

## Server Config options

See the file `daemon/config.yaml`

# Tests

In the python packages it uses `unittest` as testing framework. It also uses `coverage.py` 

To run the tests in the daemon:

```sh
cd daemon
coverage run -m unittest discover
```

To run the tests in the python-client

```sh
cd pyhton-client
coverage run -m unittest discover
```

## OPENME protocol specification

The exchange of messages between the client and the server is very simple. It is a text protocol that is served under an encrypted connection. 

# Authentication 
The server checks that the connection is stablished from a client that holds a certificate of a particular certificate authority. Otherwise it cancels the connection.

### Client Commands

Once the secure and authenticated connection is stablished between the client and the server, the client can send the following commands:

```
OPENME 
```
Opens the ports for the IP address of the client that runs the command. 

```
OPENME <ip4-address>
```
Opens the ports for the specified address

```
MEOPEN
```
Closes the ports for the client IP address.

```
MEOPEN <ip4-address>
```
Closes ports for the specified IP addres.

## Server responses

Currently, the server can respond either success or failure. 

```
OK
```
The command succeeded.

```
KO
```
The command did not succeed.


## TODOs / Limistations 

There are some stuff the implementation does not support yet or I need to think about

* Create a mobile application. It would be interesting to research if this could be securely implemented using a PWA. How could the data securely saved in the browser?
* Prevent that an IP address is kept open forever. If a client runs a OPENME but never runs the MEOPEN the IP remains open forever. This is is a very likely escenario for a mobile client which may change from wifi to a mobile network. Maybe client needs to send heartbeats (which may be problematic in mobile apps)
* Certificate revocation. If a client certificate is revoked, The server does not check it.
* Server authentication. The client should also know it is connecting to the right server. In code is by setting the context (`context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)`). 
* Think test performance of DoS attack.
* Test fuzzing
* Logging and monitoring

## LICENSE

Openme. Copyright (C) 2023-2024 @merlos

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.
