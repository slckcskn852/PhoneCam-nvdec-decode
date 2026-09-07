import Foundation
import Network
import Combine

final class ReceiverBrowser: ObservableObject {
    struct Computer: Identifiable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { String(describing: endpoint) }
    }
    @Published var computers: [Computer] = []
    @Published var message = "Keep PhoneCam Receiver open on your computer."
    private var browser: NWBrowser?
    func start() {
        stop()
        message = "Searching your home network… If your computer does not appear, enter its PC code."
        let browser = NWBrowser(for: .bonjour(type: "_phonecam._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self = self, self.browser === browser else { return }
            self.computers = results.compactMap { result in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Computer(name: name, endpoint: result.endpoint)
            }.sorted { $0.name < $1.name }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self = self, self.browser === browser else { return }
            if case .waiting = state { self.message = "Allow local-network access in Settings, or enter the PC code." }
            if case .failed = state { self.message = "Search unavailable. Enter the PC code shown on your computer." }
        }
        browser.start(queue: .main)
    }
    func stop() { browser?.cancel(); browser = nil; computers = [] }
}

/// A PC code is an IPv4 address with a typo checksum, not an authentication secret.
enum ReceiverAddress {
    static func parse(_ input: String) -> (host: String, port: UInt16)? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 253 else { return nil }
        let code = text.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        if text.uppercased().hasPrefix("PC-") || (code.hasPrefix("PC") && code.count == 10 && !text.contains(".")) {
            guard code.count == 10 else { return nil }
            let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
            var value: UInt64 = 0
            for char in code.dropFirst(2) {
                guard let digit = alphabet.firstIndex(of: char) else { return nil }
                value = (value << 5) | UInt64(digit)
            }
            let ip = value >> 8
            var crc: UInt8 = 0x5a
            for shift in [24, 16, 8, 0] {
                crc ^= UInt8((ip >> shift) & 255)
                for _ in 0..<8 { crc = (crc &<< 1) ^ (crc & 128 != 0 ? 7 : 0) }
            }
            guard crc == UInt8(value & 255) else { return nil }
            return ([24,16,8,0].map { String((ip >> $0) & 255) }.joined(separator: "."), 47823)
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let host = parts.first, !host.isEmpty,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        let port = parts.count == 2 ? UInt16(parts[1]) : UInt16(47823)
        guard let port = port, port > 0 else { return nil }
        return (String(host), port)
    }
}
