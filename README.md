# openme
A simple python script to open a iptables port


# Setup

1. Clone the repo
```
git clone https://github.com/merlos/openme
cd openme
```

2. Setup the Certificate Authority. 

Openme uses certificates to authenticate and encrypt the requests. For that, you need a certificate authority (CA), in this case it's ok to have a self-signed CA.  If you already have a CA or you want to better control this part, then go to the advanced configuration, otherwise, there I provide some scripts that make easier creating the certs.

So, first, to setup the certificate authority and create one certificate for the server and another for the client. Use this script:

```shell
./setup_ca.sh
```
You will be prompted to :
1. Fill the certificate authority (CA) key passphrase. You'll be requested this password each time you add a new certificate. So, don't forget it.

2. Name your certificate autority. You can use whatever name you want. 

3. Type the CA password. To create the _server_ and _client_ certificates you'll be prompted to fill the password.

If you get stuck and you need to start again, just remove the `easyrsa` folder using 
```shell
rm -rf easyrsa
```

The `setup_ca.sh` uses [easyrsa](https://github.com/OpenVPN/easy-rsa) behind the scenes, and it will create two folders:
1.  `easyrsa`, here is where your certificate authority resides (you should keep the contents of the folder) and,
2. `certs`, where all the generated certificates will be copied for your convenience.

The certificates created have an expiry time of more than **27 years**.

## Running the server
Ok. Now you have all ready to go.

```
cd daemon
pip install -r requirementst.xt
./openmed
```

## Running the client

Install requirements:

```shell
cd python-client
pip install -r requirements.txt
```

If the daemon is running on localhost:
```shell
./openme.py
```


If the dameon is running in another IP
```shell 
./openme.py -s server_ip_or_name

#Examples:

./openme.py -s 192.168.1.1
./openme.py -s openme.domain.com
```


```shell
./openme.py --server 192.168.1.1 --port 54154 --ip-address 10.10.1.1
```

#By default


