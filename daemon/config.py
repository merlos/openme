

LISTENING_PORT = 5414   # SALA de espera / waiting room
"""
Port the server will be listening
"""

OPEN_PORTS = [80,443]
"""
Array of ports that will be opened
"""




CERT_FILE = "/etc/openme/certificate.crt"
"""
Certificate of the server 
"""
KEY_FILE = "/etc/openme/private.key"
"""
Private key of the server certificate
"""

CA_CERT_FILE = "/etc/openme/ca_certificate.crt"
"""
Certification authority (CA) root certificate. Only clients that have connected
to the server using a certificate issued by this authority will go through.
"""