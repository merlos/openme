#!/usr/bin/env python3

import socket
import ssl
import subprocess
import daemon
import logging
import logging.handlers
import re

import config

def handle_client_connection(conn, addr):
    # Receive data from the client
    if config.DEBUG:
        print(f"Connection from {addr[0]}")
    data = conn.recv(1024).decode().strip()

    if data == "OPEN ME":
        # Get the IP address of the connecting client
        ip_address = addr[0]
    elif data.startswith("OPEN "):
        # Extract the IP address from the command
        ip_address = data[5:].strip()

        # Validate the IP address format (IPv4)
        if not validate_ip_address(ip_address):
            # Log an error message for invalid IP address format
            logger.error(f"Invalid IP address format: {ip_address}")
            # Close the connection
            conn.close()
            return
    else:
        # Log an error message for unknown command
        logger.error(f"Unknown command from ip_address {addr[0]} data: {data}")
        # Close the connection
        conn.close()
        return

    # Add a rule to iptables to allow incoming connections from the specified IP address
    for port in config.OPEN_PORTS:
        # we open both
        open_tcp_port = ['iptables', '-A', 'INPUT', '-p', 'tcp', '-s', ip_address, '--dport', str(port), '-j', 'ACCEPT']
        open_udp_port = ['iptables', '-A', 'INPUT', '-p', 'udp', '-s', ip_address, '--dport', str(port), '-j', 'ACCEPT']
        if config.DEBUG:
            open_tcp_port_s = ' '.join(open_tcp_port)
            open_udp_port_s = ' '.join(open_udp_port)
            logger.info(open_tcp_port_s)
            logger.info(open_udp_port_s)
        else:
            subprocess.run(open_tcp_port)
            subprocess.run(open_udp_port)

    # Log a confirmation message
    logger.info(f"openmed: Port opened for {ip_address}")

    # Close the connection
    conn.close()

def validate_ip_address(ip_address):
    # Validate the IP address format using regular expression
    ip_regex = r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
    return bool(re.match(ip_regex, ip_address))

def main():
    print("main")
 
    # Create a socket object
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    # Bind the socket to a specific IP address and port
    server_socket.bind(('0.0.0.0', config.LISTENING_PORT))

    # Enable SSL/TLS with the certificate and key files
    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(certfile=config.CERT_FILE, keyfile=config.KEY_FILE)

    # Set the CA certificate file for client certificate verification
    ssl_context.verify_mode = ssl.CERT_REQUIRED
    ssl_context.load_verify_locations(cafile=config.CA_CERT_FILE)

    # Listen for incoming SSL/TLS connections
    ssl_server_socket = ssl_context.wrap_socket(server_socket, server_side=True)

    # Listen for incoming connections
    ssl_server_socket.listen(1)

    while True:
        # Accept a connection
        conn, addr = ssl_server_socket.accept()

        # Handle the client connection in a separate function
        handle_client_connection(conn, addr)

# Create a logger instance
logger = logging.getLogger('openme_logger')
logger.setLevel(logging.INFO)

# Create a syslog handler and set its level
#syslog_handler = logging.handlers.SysLogHandler(address='/dev/log')
#syslog_handler.setLevel(logging.INFO)

# Create a formatter and set it for the handler
#formatter = logging.Formatter('%(name)s: %(message)s')
#syslog_handler.setFormatter(formatter)

# Add the handler to the logger
#logger.addHandler(syslog_handler)

def run_as_daemon():
    #print("daemon")
    #with daemon.DaemonContext():
    #    print("pre-maon")
        main()

if __name__ == "__main__":
     run_as_daemon()