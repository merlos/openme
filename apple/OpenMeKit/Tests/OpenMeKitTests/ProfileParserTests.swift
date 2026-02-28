import XCTest
@testable import OpenMeKit

/// Unit tests for ``ClientConfigParser`` — the lightweight YAML profile parser.
///
/// The config format is specified at
/// https://openme.merlos.org/docs/configuration/client.html
final class ProfileParserTests: XCTestCase {

    // MARK: - Round-trip

    func testParseSingleProfile() throws {
        let yaml = """
        profiles:
          home:
            server_host: "10.0.0.1"
            server_udp_port: 54154
            server_pubkey: "d2ZMSEFLenp5LzFkU3Q1WU4weUNGVzJ5MFRLaGtYUHJmTWprbEJrZEdnNWtNPQ=="
            private_key: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            public_key: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
            post_knock: ""
        """
        let profiles = try ClientConfigParser.parse(yaml: yaml)
        XCTAssertEqual(profiles.count, 1)
        let p = try XCTUnwrap(profiles["home"])
        XCTAssertEqual(p.name, "home")
        XCTAssertEqual(p.serverHost, "10.0.0.1")
        XCTAssertEqual(p.serverUDPPort, 54154)
    }

    func testParseMultipleProfiles() throws {
        let yaml = """
        profiles:
          home:
            server_host: "10.0.0.1"
            server_udp_port: 54154
            server_pubkey: "abc="
            private_key: "xyz="
            public_key: "pub="
            post_knock: ""
          work:
            server_host: "work.example.com"
            server_udp_port: 7777
            server_pubkey: "def="
            private_key: "uvw="
            public_key: "qrs="
            post_knock: "open ssh://work.example.com"
        """
        let profiles = try ClientConfigParser.parse(yaml: yaml)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertNotNil(profiles["home"])
        XCTAssertNotNil(profiles["work"])
        XCTAssertEqual(profiles["work"]?.serverUDPPort, 7777)
    }

    func testDefaultUDPPort() throws {
        // When server_udp_port is omitted, the parser should default to 54154
        let yaml = """
        profiles:
          minimal:
            server_host: "1.2.3.4"
            server_pubkey: "abc="
            private_key: "xyz="
            public_key: "pub="
            post_knock: ""
        """
        let profiles = try ClientConfigParser.parse(yaml: yaml)
        XCTAssertEqual(profiles["minimal"]?.serverUDPPort, 54154)
    }

    func testEmptyYamlThrows() {
        XCTAssertThrowsError(try ClientConfigParser.parse(yaml: ""),
                             "Parsing empty YAML should throw noProfilesFound") { err in
            guard let parserErr = err as? ClientConfigParser.ParserError,
                  case .noProfilesFound = parserErr else {
                XCTFail("Expected ClientConfigParser.ParserError.noProfilesFound, got \(err)")
                return
            }
        }
    }

    func testSerializeContainsProfileData() throws {
        let profile = Profile(
            name: "test",
            serverHost: "1.2.3.4",
            serverUDPPort: 54154,
            serverPubKey: "abc=",
            privateKey: "def=",
            publicKey: "ghi=",
            postKnock: ""
        )
        let yaml = ClientConfigParser.serialize(profiles: ["test": profile])
        XCTAssertTrue(yaml.contains("test:"),  "Serialised YAML must include profile name key")
        XCTAssertTrue(yaml.contains("1.2.3.4"), "Serialised YAML must include server host")
        XCTAssertTrue(yaml.contains("54154"),   "Serialised YAML must include UDP port")
    }
}
