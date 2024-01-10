import argparse
import ssl
import socket
import requests

import config


import validators

def get_public_ip_details():
    """
    Get the public IP address and its details using the ipinfo.io API.
    
    Returns:
        tuple: A tuple containing public IP address (str) and its details (dict).
    """
    # Sending a GET request to ipinfo.io/ip to get the public IP address
    response1 = requests.get("https://ipinfo.io/ip")
    public_ip_address = response1.text.strip()

    # Ensure the ip address returned is an actual IP
    if not validators.is_valid_ip4_address(public_ip_address):
        raise AttributeError("Incorrect IP address format returned by ipinfo.io")
    
    # Sending a GET request to ipinfo.io/<public_ip_address> to get the details of the specified IP address
    response2 = requests.get(f"https://ipinfo.io/{public_ip_address}")
    ip_details = response2.json()

    return ip_details

def display_ip_details():
    """
    Get and display the public IP address and its details.
    """
    details = get_public_ip_details()
    print("IP Address:", details.get("ip"))
    print("City:", details.get("city"))
    print("Region:", details.get("region"))
    print("Country:", details.get("country"))
    print("Location:", details.get("loc"))


epilog='''Examples:

    Open ports for my ip address of the default server set in config.py
        python openme.py --openme 
        python openme.py -o

    Close ports for my ip address of the default server set in config.py
        python openme.py --meopen
        python openme.py -m

    Close ports for the ip 192.168.1.1 of the default server set in config.py
        python openme.py --miopen --ip-address 192.168.1.1
        python openme.py -m -i 192.168.1.1

    Open ports for me at the server 10.8.0.1:1980 
        python openme.py --server 10.8.0.1 --port 1980
        python openme.py -s 10.8.0.1 -p 1980

    Display my public ip info
        python openme.py --me
        python openme.py -e
'''

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Client for openme",
                                 epilog=epilog,
                                 formatter_class=argparse.RawDescriptionHelpFormatter
                                 )
parser.add_argument("-s", "--server", default=config.DEFAULT_SERVER, help="Server address")
parser.add_argument("-p", "--port", type=int, default=config.DEFAULT_PORT, help="Server port (default:54154)")
parser.add_argument("-i", "--ip-address", help="Open/Close ports to this IP address (default: MY current public IP)")
parser.add_argument("-o", "--openme", action="store_true", default=False, help="Open ports (aka openme)")
parser.add_argument("-m", "--miopen", action="store_true", default=False, help="Close ports (aka miopen)")
parser.add_argument("-e", "--me", action="store_true", default=False, help="Displays your current public IP info (uses ipinfo.io API)")

args = parser.parse_args()

# Connect to the server using SSL
# TODO
#context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)

# If none of these flags are set, display the help and leave
if not args.me or args.openme or args.miopen:
    parser.print_help()
    exit()

# Display ip info
if args.me:
    display_ip_details() 

# Open or close ports
if args.openme or args.miopen:
    # Load certs
    context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    context.load_cert_chain(certfile=config.CLIENT_CERT, keyfile=config.CLIENT_KEY)
    context.load_verify_locations(cafile=config.CA_CERT)

    with socket.create_connection((args.server, args.port)) as sock:
        with context.wrap_socket(sock, server_hostname=args.server) as secure_sock:
            if args.miopen:
                message = "MEOPEN" if args.ip_address is None else f"MIOPEN {args.ip_address}"
            else: 
                message = "OPEN ME" if args.ip_address is None else f"OPEN {args.ip_address}"
            secure_sock.sendall(message.encode())
            
            # Receive and handle server response
            response = secure_sock.recv(1024).decode()
            if response == "OK":
                print("Server response: OK")
            elif response == "KO":
                print("Server response: KO (error)")
            else:
                print("Unexpected server response:", response)        