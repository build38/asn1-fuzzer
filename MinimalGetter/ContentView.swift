import SwiftUI
import ASN1Kit

// Seedable Random Number Generator (Xorshift algorithm)
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    // Initialize with a seed
    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEF : seed // Ensure seed is non-zero
    }
    
    // Generate a random UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

public class DataScanner {
    private let data: Data
    private(set) var position: Int = 0

    public init(data: Data) {
        self.data = data
    }

    public func scan(distance: Int) -> Data? {
        guard position + distance <= data.count else { return nil }
        let scannedData = data.subdata(in: position..<position + distance)
        position += distance
        return scannedData
    }
}

func parseASN1Object(from scanner: inout DataScanner) throws -> ASN1Object {
    guard let tagByte = scanner.scan(distance: 1)?[0] else {
        throw ASN1Error.malformedEncoding("Insufficient data to determine tag")
    }

    // Determine tag type from the first byte
    let tag: ASN1DecodedTag = try {
        if tagByte & 0xC0 == 0xC0 {
            return .privateTag(UInt(tagByte & 0x1F))
        } else if tagByte & 0x80 == 0x80 {
            return .taggedTag(UInt(tagByte & 0x1F))
        } else if tagByte & 0x40 == 0x40 {
            return .applicationTag(UInt(tagByte & 0x1F))
        } else {
            guard let universalTag = ASN1Tag(rawValue: tagByte & 0x1F) else {
                throw ASN1Error.malformedEncoding("Invalid universal tag: \(tagByte & 0x1F)")
            }
            return .universal(universalTag)
        }
    }()

    guard let lengthByte = scanner.scan(distance: 1)?[0] else {
        throw ASN1Error.malformedEncoding("Insufficient data to decode length")
    }

    if tagByte & 0x20 == 0 {
        // Fill up to 7 bytes
        let bytes = lengthByte & 0x07
        guard let value = scanner.scan(distance: Int(bytes)) else {
            throw ASN1Error.malformedEncoding("Insufficient data for primitive value")
        }
        return create(tag: tag, data: .primitive(value))
    }

    // Populate up to 3 child items
    let count = lengthByte & 0x03
    var children = [ASN1Object]()
    for _ in 0..<count {
        let child = try parseASN1Object(from: &scanner)
        children.append(child)
    }

    return create(tag: tag, data: .constructed(children))
}


// Usage Example
var seededGenerator = SeededRandomNumberGenerator(seed: 10819)

struct ContentView: View {

    @State private var dynamicText = "Restarted"
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(dynamicText)
        }
        .padding()
        .onReceive(timer) { _ in
            dynamicText = getString()
        }
    }

    func dump(s: String) {
        FileHandle.standardOutput.write(s.data(using: .utf8)!)
    }
    func generateRandomData(length: Int) -> Data {
        return Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &seededGenerator) })
    }
    func hexStringToData(hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        return stride(from: 0, to: hex.count, by: 2).compactMap {
            UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)], radix: 16)
        }.reduce(into: Data(), { $0.append($1) })
    }

    func getString() -> String {
        for _ in 1...5000 {
            let input = generateRandomData(length: 64)
            var scanner = DataScanner(data: input)

            do {
                let str = input.map { String(format: "%02x", $0) }.joined()
                dump(s: "\n\(str)")
                let obj = try parseASN1Object(from: &scanner)
                let data = try obj.serialize()
                let decoded = try ASN1Decoder.decode(asn1: data)
                let data_decoded = try decoded.serialize()
                if (data == data_decoded) {
                    dump(s: " == ")
                } else {
                    dump(s: " != ")
                }
                dump(s: decoded.data.debugDescription)
                if (data != data_decoded) {
                    dump(s: "\n" + data.map { String(format: "%02x", $0) }.joined())
                    dump(s: "\n" + data_decoded.map { String(format: "%02x", $0) }.joined())
                }
            } catch {
                dump(s: " \(error)")
            }
        }
        return String(Int.random(in: 300...400))
    }
}

#Preview {
    ContentView()
}
