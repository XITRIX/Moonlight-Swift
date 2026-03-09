//
//  Utils.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 08.03.2026.
//

import Foundation

class Utils: NSObject {
    @objc
    static func isActiveNetworkVPN() -> Bool {
        // TODO: Implement
        return false
    }

    static func randomBytes(_ length: Int) -> Data {
        var bytes: [UInt8] = .init(repeating: 0, count: length)
        arc4random_buf(&bytes, length)
        return .init(bytes: bytes, count: length)
    }

    static func hexToBytes(_ hex: String) -> Data {
        let chars = Array(hex.utf8)
        var data = Data(capacity: chars.count / 2)

        var i = 0
        while i + 1 < chars.count {
            let hi = chars[i]
            let lo = chars[i + 1]
            let byteString = String(bytes: [hi, lo], encoding: .utf8)!
            let byte = UInt8(byteString, radix: 16)!
            data.append(byte)

            i += 2
        }

        return data
    }

    static func bytesToHex(_ data: Data) -> String {
        var hex: String = ""
        for i in data {
            hex += String(format: "%02x", i)
        }
        return hex
    }

    @objc
    static func addressPortStringToAddress(_ addressPort: String) -> String {
        let (success, addressRange, _) = parseAddressPortString(addressPort)
        guard success, let addressRange else {
            return addressPort
        }

        return addressPort.substring(with: addressRange)
    }

    static func addressPortStringToPort(_ addressPort: String) -> UInt16 {
        let (success, _, portRange) = parseAddressPortString(addressPort)
        guard success,
              let portRange,
              let result = UInt16(addressPort.substring(with: portRange))
        else {
            return 47989
        }

        return result
    }

    static func addressAndPortToAddressPortString(_ address: String, port: UInt16) -> String {
        if address.contains(":") {
            // IPv6 addresses require escaping
            return String(format: "[%@]:%u", address, port)
        } else {
            return String(format: "%@:%u", address, port)
        }
    }
}

private extension Utils {
    static func parseAddressPortString(_ addressPort: String) -> (success: Bool, address: Range<String.Index>?, port: Range<String.Index>?) {
        guard addressPort.contains(":") else {
            // If there's no port or IPv6 separator, the whole thing is an address
            return (true, addressPort.startIndex..<addressPort.endIndex, nil)
        }

        let locationOfOpeningBracket = addressPort.firstIndex(of: "[")
        let locationOfClosingBracket = addressPort.firstIndex(of: "]")

        let addressRange: Range<String.Index>

        if locationOfOpeningBracket != nil || locationOfClosingBracket != nil {
            // If we have brackets, it's an IPv6 address
            guard
                let open = locationOfOpeningBracket,
                let close = locationOfClosingBracket,
                close >= open
            else {
                // Invalid address format
                return (false, nil, nil)
            }

            // Cut at the brackets
            let start = addressPort.index(after: open)
            addressRange = start..<close
        } else {
            // It's an IPv4 address, so just cut at the port separator
            guard let colon = addressPort.firstIndex(of: ":") else {
                return (true, addressPort.startIndex..<addressPort.endIndex, nil)
            }
            addressRange = addressPort.startIndex..<colon
        }

        let remainingStart = addressRange.upperBound
        let remainingRange = remainingStart..<addressPort.endIndex

        let portRange: Range<String.Index>?
        if let separator = addressPort[remainingRange].firstIndex(of: ":") {
            let portStart = addressPort.index(after: separator)
            portRange = portStart..<addressPort.endIndex
        } else {
            portRange = nil
        }

        return (true, addressRange, portRange)
    }
}

extension String {
    func trim() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
