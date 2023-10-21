

"""
Default Configuration values
These are the default values if not set.

See config.py for the detailed description
"""
config = {}
config['BIND_ADDRESS'] = '0.0.0.0'
config['LISTENING_PORT'] = 54154 # SALSA 
config['PORTS'] = [{'port': 80, 'protocol': 'tcp'},{'port':443,'protocol':'tcp'}]
config['CERT_FILE'] = "../certs/server.crt"
config['KEY_FILE'] = "../certs/server.key"
config['CA_CERT_FILE'] = "../certs/ca.crt"
config['DEBUG']=True
