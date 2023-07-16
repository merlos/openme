import argparse
import ssl
import socket

import config

# Parse command-line arguments
parser = argparse.ArgumentParser()
parser.add_argument("-s", "--server", default=config.DEFAULT_SERVER, help="Server address")
parser.add_argument("-p", "--port", type=int, default=config.DEFAULT_PORT, help="Server port")
parser.add_argument("-i", "--ip-address", help="Open ports to this IP address (default: your IP)")
args = parser.parse_args()

# Connect to the server using SSL
#context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
context.load_cert_chain(certfile=config.CLIENT_CERT, keyfile=config.CLIENT_KEY)
context.load_verify_locations(cafile=config.CA_CERT)

with socket.create_connection((args.server, args.port)) as sock:
    with context.wrap_socket(sock, server_hostname=args.server) as secure_sock:
        # Send the appropriate message based on the presence of IP address
        message = "OPEN ME" if args.ip_address is None else f"OPEN {args.ip_address}"
        secure_sock.sendall(message.encode())