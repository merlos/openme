import CryptoKit
import Foundation
import Security

/// Generates Ed25519 key pairs and stores them in the iOS Keychain.
///
/// The private key is protected with device biometrics so it can only be read
/// after a successful Face ID / Touch ID / passcode prompt.  Set
/// `syncToiCloud = true` to tag the item with `kSecAttrSynchronizable` so it
/// syncs across the user's Apple devices via iCloud Keychain.
enum SecureEnclaveKeyGen {

    struct KeyPair {
        let privateKeyBase64: String
        let publicKeyBase64: String
    }

    /// Generates a new Curve25519 signing key pair, stores the private key in
    /// the Keychain and returns both keys as Base64 strings.
    static func generateAndStore(
        profileName: String,
        syncToiCloud: Bool = false
    ) throws -> KeyPair {
        let privateKey = Curve25519.Signing.PrivateKey()
        let privateRaw = privateKey.rawRepresentation        // 32 bytes seed
        let publicRaw  = privateKey.publicKey.rawRepresentation

        try KeychainStore.storePrivateKey(
            privateRaw,
            account: profileName,
            syncToiCloud: syncToiCloud
        )

        return KeyPair(
            privateKeyBase64: privateRaw.base64EncodedString(),
            publicKeyBase64:  publicRaw.base64EncodedString()
        )
    }

    /// Loads the raw private key seed for a profile from the Keychain.
    static func loadPrivateKey(profileName: String) throws -> Data {
        try KeychainStore.loadPrivateKey(account: profileName)
    }

    /// Removes the Keychain item for a profile.
    static func deleteKey(profileName: String) throws {
        try KeychainStore.deletePrivateKey(account: profileName)
    }
}
