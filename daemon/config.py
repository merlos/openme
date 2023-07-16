

LISTENING_PORT = 54154 # SALSA 
"""
Port the server will be listening. Defaults 54154 (SALSA)
"""

OPEN_PORTS = [80,443]
"""
Array of ports that will be opened
"""

#CERT_FILE = "/etc/openme/certificate.crt"
CERT_FILE = "../certs/openme.crt"
"""
Certificate of the server 
"""
#KEY_FILE = "/etc/openme/private.key"
KEY_FILE = "./openme.key"
"""
Private key of the server certificate
"""

#CA_CERT_FILE = "/etc/openme/ca.crt"
CA_CERT_FILE = "./ca.crt"
"""
Certification authority (CA) root certificate. Only clients that have connected
to the server using a certificate issued by this authority will go through.
"""