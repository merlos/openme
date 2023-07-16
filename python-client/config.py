
# Define the default values for server and port
DEFAULT_SERVER = "localhost"
DEFAULT_PORT = 54154 # SALSA

CLIENT_CERT='/etc/openme/client.crt'
CLIENT_KEY='/etc/openme/client.key'
CA_CERT='/etc/openme/ca.crt'

# If debug is set to True, then it uses the certs in cert
DEBUG = True

if DEBUG:
    CLIENT_CERT='../certs/client.crt'
    CLIENT_KEY='../certs/client.key'
    CA_CERT='../certs/ca.crt'
