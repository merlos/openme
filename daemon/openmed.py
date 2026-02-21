#!/usr/bin/env python3
import os
import socket
import ssl
import subprocess
import traceback
import argparse

import daemon
import logging
import logging.handlers
import re
import yaml
from types import SimpleNamespace

from defaults import config as default_config
from validators import is_valid_ip4_address
from validators import is_valid_port_number
from validators import InvalidPortNumber
from validators import validate_config

config = SimpleNamespace(**default_config)


def debug(message):
    """
    Displays messages through the std output when config.DEBUG is true
    """
    global config

    if config.DEBUG:
        logging.debug(message)

def merge_configs(default_config, config_overwrites=[]):
    """
        Merges default values for config with the configuration overwrites.
        Then converts the dictionaries into a namespace so that the dictionary can
        be accessed using the dot notation, that is, instead of config['BIND_ADDRESS'] 
        use config.BIND_ADDRESS.
    """
    default_config.update(config_overwrites)
    return SimpleNamespace(**default_config)


def generate_iptables_command(ip_address, port, protocol, action):
    """
    Creates the iptables binary command.

    Validates ip_address, port, protocol, and action before building the command.
    """
    if not is_valid_ip4_address(ip_address):
        raise ValueError(f"Invalid IP address: {ip_address}")

    if not is_valid_port_number(port):
        raise InvalidPortNumber(f"Invalid port number: {port}")

    if protocol not in ["tcp", "udp"]:
        return "Invalid protocol. Supported protocols are tcp and udp."

    if action not in ["add", "remove"]:
        return "Invalid action. Supported actions are add and remove."

    if action == "add":
        command = f"iptables -A openme -p {protocol} --dport {port} -s {ip_address} -j ACCEPT"
    elif action == "remove":
        command = f"iptables -D openme -p {protocol} --dport {port} -s {ip_address} -j ACCEPT"
    
    return command

def open_ports(ip_address, ports=None):
    """
    Opens the ports calling iptables.

    ports: list of dicts with 'port' and 'protocol' keys (defaults to config.PORTS)
    """
    if ports is None:
        ports = config.PORTS
    for port_info in ports:
        port = port_info['port']
        protocol = port_info['protocol']
        command = generate_iptables_command(ip_address, port, protocol, "add")
        if config.DEBUG:
            debug(command)
        else:
            subprocess.run(command.split())


def close_ports(ip_address, ports=None):
    """
    Closes the ports calling iptables.

    ports: list of dicts with 'port' and 'protocol' keys (defaults to config.PORTS)
    """
    if ports is None:
        ports = config.PORTS
    for port_info in ports:
        port = port_info['port']
        protocol = port_info['protocol']
        command = generate_iptables_command(ip_address, port, protocol, "remove")
        if config.DEBUG:
            debug(command)
        else:
            subprocess.run(command.split())


def handle_client_connection(conn, addr):
    # Receive data from the client
    debug(f"Connection received from {addr[0]}")
    data = conn.recv(1024).decode().strip()
    # Valid commands
    #
    # OPEN ME
    # OPEN <IPv4 address>      # Example: OPEN 192.168.1.1
    # MEOPEN
    # MEOPEN <IPv4 address>    # Example MEOPEN 10.1.1.0
    #
    if data == "OPEN ME":
        # Get the IP address of the connecting client
        ip_address = addr[0]
        open_ports(ip_address)

    elif data.startswith("OPEN "):
        # Extract the IP address from the command
        ip_address = data[5:].strip()
        # Validate the IP address format (IPv4)
        if not is_valid_ip4_address(ip_address):
            # Log an error message for invalid IP address format
            logger.error(f"Invalid IP address format: {ip_address}")
            # Close the connection
            conn.sendall("KO".encode())
            conn.close()
            return
        open_ports(ip_address)

    elif data == "MEOPEN":
        debug("MEOPEN")
        ip_address = addr[0]
        close_ports(ip_address)
    
    elif data.startswith("MEOPEN "):
        debug("MEOPEN IP")
        # Extract the IP address from the command
        ip_address = data[7:].strip()
        # Validate the IP address format (IPv4)
        if not is_valid_ip4_address(ip_address):
            # Log an error message for invalid IP address format
            logger.error(f"Invalid IP address format: {ip_address}")
            # Close the connection
            conn.sendall("KO".encode())
            conn.close()
            return
        close_ports(ip_address)
    else:
        # Log an error message for unknown command
        logger.error(f"Unknown command from ip_address {addr[0]} data: {data}")
        conn.sendall("KO".encode())
        # Close the connection
        conn.close()
        return

    # Log a confirmation message
    logger.info(f"openmed: Ports opened for {ip_address}")
    conn.sendall("OK".encode())
    # Close the connection
    conn.close()


def start_listening(config):
    """Opens the listening port and starts 
    For more info: see mai(), defaults.py, and config.yaml
    Args:
        config (config): An openme config object that holds info such as port number, binding addres, certificate file paths...
    """

    # Create socket
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # Bind the socket to a specific IP address and port
    server_socket.bind((config.BIND_ADDRESS, config.LISTENING_PORT))

    # Enable SSL/TLS with the certificate and key files
    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(certfile=config.CERT_FILE, keyfile=config.KEY_FILE)

    # Set the CA certificate file for client certificate verification
    ssl_context.verify_mode = ssl.CERT_REQUIRED
    ssl_context.load_verify_locations(cafile=config.CA_CERT_FILE)

    # Listen for incoming SSL/TLS connections
    ssl_server_socket = ssl_context.wrap_socket(server_socket, server_side=True)

    # Disable strict hostname checking since the server cert may not have a hostname (or we may connect via IP)
    ssl_context.verify_flags &= ~ssl.VERIFY_X509_STRICT

    # Listen for incoming connections
    ssl_server_socket.listen(1)

    while True:
        try:
            # Accept a connection (TLS handshake happens here)
            conn, addr = ssl_server_socket.accept()
        except ssl.SSLError as e:
            logger.warning(f"TLS handshake failed: {e}")
            continue
        except Exception as e:
            logger.error(f"Unexpected accept() error: {e}")
            continue

        # Handle the client connection without killing the server loop
        try:
            handle_client_connection(conn, addr)
        except Exception as e:
            logger.error(f"Error handling client {addr}: {e}")
            debug(traceback.print_exc())
            try:
                conn.close()
            except Exception:
                pass


def run_as_daemon(config):
    print("daemon")
    with daemon.DaemonContext():
        print("run_as_daemon")

#
#  Setup Logger 
#

class OneLineExceptionFormatter(logging.Formatter):
    def formatException(self, exc_info):
        result = super().formatException(exc_info)
        return repr(result)
 
    def format(self, record):
        result = super().format(record)
        if record.exc_text:
            result = result.replace("\n", "")
        return result
 
handler = logging.StreamHandler()
formatter = OneLineExceptionFormatter(logging.BASIC_FORMAT)
handler.setFormatter(formatter)
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOGLEVEL", "INFO"))
logger.addHandler(handler)

DEFAULT_CONFIG_FILE = "./config.yaml"

def main():
    """Processese command line arguments, setsup logger, parses config file calls run_as_daemon()
    """   
    global config
    parser = argparse.ArgumentParser(description='Openme server')
    parser.add_argument('--daemon', '-d', action='store_true', help='Run as a daemon')
    parser.add_argument('--config-file', '-c', metavar='<config-file>', default=DEFAULT_CONFIG_FILE,
                        help='Specify config file (default: {})'.format(DEFAULT_CONFIG_FILE))
    
    args = parser.parse_args()
    
    #Load config file
    config_file = args.config_file
    if not os.path.exists(config_file):
        logger.error('Error: Config file "{}" not found. Using default config'.format(config_file))
    try: 
        # TODO - command line argument
        # Load yaml config    
        # Open the YAML file and load its contents
        with open(config_file, 'r') as yaml_file:
            # Load YAML data from the file
            user_config = yaml.safe_load(yaml_file)
            logger.info(user_config)  # Print the loaded YAML data
    
            # Merge config imported from defaults with user_config
            # this function also transfors config so that config['ATTRIBUTE'] can be
            # accessed as config.ATTRIBUTE
            config = merge_configs(default_config, user_config)

            # Validate config values are correct
            validate_config(config)

    except yaml.YAMLError as e:
        logger.error(f"Error in config ({config_file}):", e)
    except Exception as e:
        logger.error(f"Config Error {str(e)}")
        debug(traceback.print_exc())
        exit(1)

    # Run as daemon?
    if args.daemon:
        run_as_daemon(config)
    else:
        start_listening(config)

if __name__ == "__main__":
     main()