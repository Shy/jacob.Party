import Foundation
import Crypto

// Private key from vapid-key-generator
let privateKeyBase64 = "d6rEVhpy2KLk7uvDHnt0Pp2yvm1LOUTkciF6vIv+iyc="

guard let privateKeyData = Data(base64Encoded: privateKeyBase64) else {
    print("Failed to decode private key")
    exit(1)
}

do {
    let privateKey = try P256.Signing.PrivateKey(rawRepresentation: privateKeyData)
    let publicKey = privateKey.publicKey

    // Add 0x04 prefix for uncompressed format (required by Web Push API)
    var uncompressedKey = Data([0x04])
    uncompressedKey.append(publicKey.rawRepresentation)
    let publicKeyBase64 = uncompressedKey.base64EncodedString()

    print("VAPID_PRIVATE_KEY=\(privateKeyBase64)")
    print("VAPID_PUBLIC_KEY=\(publicKeyBase64)")
} catch {
    print("Error: \(error)")
    exit(1)
}
