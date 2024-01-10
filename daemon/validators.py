"""
Format validators

A set of validators that ensure that the format.
Each validator returns a tuple that is composed by 
a boolean indicating if the  passsed parameter is ok or not, 
and a text message indicating what is the issue.
"""
import os
import re
import OpenSSL.crypto
import logging

# Setup logging
logger = logging.getLogger(__name__)



class InvalidPortNumber(Exception):
    """
    Custom exception class for invalid port numbers.
    
    Args:
        message (str, optional): Custom error message. Defaults to "Invalid port number".
    """
    def __init__(self, message="Invalid port number"):
        self.message = message
        super().__init__(self.message)


class InvalidProtocol(Exception):
    """
    Custom exception class for invalid protocols.
    
    Args:
        message (str, optional): Custom error message. Defaults to "Invalid protocol".
    """
    def __init__(self, message="Invalid protocol"):
        self.message = message
        super().__init__(self.message)


class InvalidCertificateError(Exception):
    """
    Custom exception class for invalid certificate files.
    
    Args:
        message (str, optional): Custom error message. Defaults to "Invalid certificate file".
    """
    def __init__(self, message="Invalid certificate file"):
        self.message = message
        super().__init__(self.message)


def is_valid_ip4_address(ip_address):
    """Validate an IPv4 address

    Args:
        ip_address (string): IPv4 address to validate. Example: "192.168.1.1"

    Returns:
        bool: True if it is a valid address   
    """
    # Validate the IP address format using regular expression
    ip_regex= r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$'
    return bool(re.match(ip_regex, ip_address))


def is_valid_port_number(port_number):
    """
    Validates if the given number is a valid TCP or UDP port number (between 1 and 65535).
    
    Args:
        port_number (int): The port number to validate.
        
    Returns:
        bool: True if the port number is valid, False otherwise.
    """
    return 0 < port_number <= 65535


def is_valid_protocol(protocol):
    """
    Validates if a given protocol is 'tcp' or 'udp'.
    
    Args:
        protocol (str): Protocol to be validated.
    
    Returns:
        bool: True if the protocol is valid, False otherwise.
    """
    return protocol.lower() in ['tcp', 'udp']


def validate_ports(ports_list):
    """
    Validates a list of port information dictionaries.
    
    Args:
        ports_list (list): List of dictionaries containing 'port' and 'protocol' keys.
    
    Returns:
        str: Success message if all ports are valid.
    
    Raises:
        InvalidPortNumber: If a port number is invalid or missing.
        InvalidProtocol: If a protocol is invalid or missing.
    """
    for port_info in ports_list:
        port = port_info.get('port')
        protocol = port_info.get('protocol')

        if port is None or not is_valid_port_number(port):
            raise InvalidPortNumber(f"Invalid port number: {port}")

        if protocol is None or not is_valid_protocol(protocol):
            raise InvalidProtocol(f"Invalid protocol: {protocol}")

    return True


def validate_cert_file(cert_file):
    """
    Checks if the given certificate file format is valid.

    Args:
        cert_file (str): Path to the certificate file.

    Raises:
        InvalidCertificateError: If the certificate file is not valid.

    Returns:
        bool: True if the certificate file is valid, False otherwise.
    """
    try:
        if os.path.exists(cert_file):
            with open(cert_file, 'rt') as f:
                cert_data = f.read()
                OpenSSL.crypto.load_certificate(OpenSSL.crypto.FILETYPE_PEM, cert_data)
            return True
        else:
            raise InvalidCertificateError("Certificate file not found.")
    except Exception as e:
        raise InvalidCertificateError("Invalid certificate file: {}".format(str(e)))


class InvalidKeyError(Exception):
    """
    Custom exception class for invalid key files.
    
    Args:
        message (str, optional): Custom error message. Defaults to "Invalid key file".
    """
    def __init__(self, message="Invalid key file"):
        self.message = message
        super().__init__(self.message)


def validate_key_file(key_file):
    """
    Checks if the given key file is valid.

    Args:
        key_file (str): Path to the key file.

    Raises:
        InvalidKeyError: If the key file is not valid.

    Returns:
        bool: True if the key file is valid, False otherwise.
    """
    try:
        if os.path.exists(key_file):
            with open(key_file, 'rt') as f:
                key_data = f.read()
                OpenSSL.crypto.load_privatekey(OpenSSL.crypto.FILETYPE_PEM, key_data)
            return True
        else:
            raise InvalidKeyError("Key file not found.")
    except Exception as e:
        raise InvalidKeyError("Invalid key file: {}".format(str(e)))



def validate_config(config):
    """
    Ensures that config parameters that appear are correct.
    """
    logger.debug(f'validate_config: {config}')
    #BIND_ADDRESS  is a valid ip4 address
    if hasattr(config, 'BIND_ADDRESS') and not is_valid_ip4_address(config.BIND_ADDRESS):
        raise RuntimeError("config: BIND_ADDRESS is not a valid IP address. Use something like 0.0.0.0 or 192.168.1.1")
    
    #LISTENING_PORT  is between 1 and 65535 
    if hasattr(config, 'LISTENING_PORT') and not is_valid_port_number(config.LISTENING_PORT):
        raise RuntimeError("Config: LISTENING_PORT is invalid. Port number must be between 1 and 65535")
    
    #PORTS are between 1 and 65535 and protocol is tcp or udp f.i [(80,'tcp'),(443,'tcp')]
    if hasattr(config,'PORTS'):
        validate_ports(config.PORTS)
    
    # CERT_FILE exists and has the correct format
    if hasattr(config,'CERT_FILE'):
        validate_cert_file(config.CERT_FILE)

    # KEY_FILE  exists and has a valid format 
    if hasattr(config,'KEY_FILE'):
        validate_key_file(config.KEY_FILE)

    # CA_CERT_FILE exists and has a valid format
    if hasattr(config,'CA_CERT_FILE'):
        validate_cert_file(config.CA_CERT_FILE)
