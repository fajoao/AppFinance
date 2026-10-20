import Foundation
import CryptoKit

/// PIN próprio e opcional do app (4 a 6 números). Só guardamos sal + hash iterado, nunca o PIN.
/// Um PIN curto tem poucas combinações: a proteção real vem do Keychain (onde o hash fica) e do bloqueio
/// progressivo após tentativas erradas. Quem tem acesso ao aparelho desbloqueado ainda pode usar o código do aparelho.
struct PinRecord: Codable, Equatable, Sendable {
    var salt: Data
    var hash: Data
    var rounds: Int
}

enum PinLock {
    static let minLength = 4
    static let maxLength = 6
    static let freeAttempts = 5
    static let defaultRounds = 20_000
    static let keychainKey = "financeapp.pin.v1"

    static func isValidFormat(_ pin: String) -> Bool {
        (minLength...maxLength).contains(pin.count) && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func derive(pin: String, salt: Data, rounds: Int) -> Data {
        var digest = Data(SHA256.hash(data: salt + Data(pin.utf8)))
        for _ in 1..<max(rounds, 1) { digest = Data(SHA256.hash(data: digest + salt)) }
        return digest
    }

    static func makeRecord(pin: String, rounds: Int = defaultRounds, salt: Data? = nil) -> PinRecord {
        let s = salt ?? Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        return PinRecord(salt: s, hash: derive(pin: pin, salt: s, rounds: rounds), rounds: rounds)
    }

    static func verify(pin: String, record: PinRecord) -> Bool {
        let candidate = derive(pin: pin, salt: record.salt, rounds: record.rounds)
        guard candidate.count == record.hash.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(candidate, record.hash) { diff |= a ^ b }   // comparação em tempo constante
        return diff == 0
    }

    /// Espera depois de `failedAttempts` erros seguidos: 0 até 4; depois 30 s, 60 s, 120 s... no máximo 15 min.
    static func lockoutSeconds(failedAttempts: Int) -> TimeInterval {
        guard failedAttempts >= freeAttempts else { return 0 }
        let doublings = min(failedAttempts - freeAttempts, 5)
        return min(30 * pow(2, Double(doublings)), 900)
    }
}

enum PinResult: Equatable, Sendable {
    case ok
    case wrong(remainingFreeAttempts: Int)
    case locked(until: Date)
    case notSet
}
