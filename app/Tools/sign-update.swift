// Signs a release disk image for the in-app updater (Ed25519).
//
//   UPDATE_SIGNING_KEY=<base64 private key> swift app/Tools/sign-update.swift build/ScreenPulse.dmg
//       prints the signature (base64) for ScreenPulse.dmg.sig
//   UPDATE_SIGNING_KEY=<…> swift app/Tools/sign-update.swift --public
//       prints the matching public key, which must equal AppInfo.updatePublicKey
import Foundation
import CryptoKit

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

guard let raw = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty else { fail("UPDATE_SIGNING_KEY is not set") }
guard let keyData = Data(base64Encoded: raw), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
else { fail("UPDATE_SIGNING_KEY is not a base64 Ed25519 private key") }

let args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first else { fail("usage: sign-update.swift <file> | --public") }
if first == "--public" {
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else {
    guard let data = FileManager.default.contents(atPath: first) else { fail("cannot read \(first)") }
    guard let sig = try? key.signature(for: data) else { fail("signing failed") }
    print(sig.base64EncodedString())
}
