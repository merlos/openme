import unittest
from validators import validate_ip4_address


class TestValidateIP4Address(unittest.TestCase):

    def test_valid_ip_addresses(self):
        self.assertTrue(validate_ip4_address("192.168.1.1"))
        self.assertTrue(validate_ip4_address("0.0.0.0"))
        self.assertTrue(validate_ip4_address("255.255.255.255"))
        self.assertTrue(validate_ip4_address("127.0.0.1"))

    def test_invalid_ip_addresses(self):
        self.assertFalse(validate_ip4_address("256.256.256.256"))  # Each octet must be between 0 and 255
        self.assertFalse(validate_ip4_address("192.168.1.256"))    # Octet value greater than 255
        self.assertFalse(validate_ip4_address("192.168.1"))         # Incomplete IP address
        self.assertFalse(validate_ip4_address("192.168.1.1.1"))     # Extra octet
        self.assertFalse(validate_ip4_address("192.168.1.-1"))      # Negative value in octet
        self.assertFalse(validate_ip4_address("192.168.1.01"))      # Leading zero in octet
        self.assertFalse(validate_ip4_address("192..168.1.1"))      # Two dots
        self.assertFalse(validate_ip4_address("%192.168.1.1"))      # Weird char

if __name__ == '__main__':
    unittest.main()