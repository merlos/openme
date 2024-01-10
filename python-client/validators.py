import re 

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

