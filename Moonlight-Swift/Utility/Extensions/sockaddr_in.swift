//
//  sockaddr_in.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 07.03.2026.
//

import Foundation

extension Data {
    nonisolated
    func sockaddrFromData() -> sockaddr? {
        return self.withUnsafeBytes { rawBuf in
            guard rawBuf.count >= MemoryLayout<sockaddr>.size,
                  let base = rawBuf.baseAddress
            else { return nil }
            return base.assumingMemoryBound(to: sockaddr.self).pointee
        }
    }

    nonisolated
    func ipv4() -> sockaddr_in? {
        return self.withUnsafeBytes { rawBuf in
            guard rawBuf.count >= MemoryLayout<sockaddr_in>.size,
                  let base = rawBuf.baseAddress
            else { return nil }
            let sa = base.assumingMemoryBound(to: sockaddr.self).pointee
            guard sa.sa_family == sa_family_t(AF_INET) else { return nil }
            return base.assumingMemoryBound(to: sockaddr_in.self).pointee
        }
    }

    nonisolated
    func ipv6() -> sockaddr_in6? {
        return self.withUnsafeBytes { rawBuf in
            guard rawBuf.count >= MemoryLayout<sockaddr_in6>.size,
                  let base = rawBuf.baseAddress
            else { return nil }
            let sa = base.assumingMemoryBound(to: sockaddr.self).pointee
            guard sa.sa_family == sa_family_t(AF_INET6) else { return nil }
            return base.assumingMemoryBound(to: sockaddr_in6.self).pointee
        }
    }
}

extension sockaddr_in {
    /// Returns the IPv4 address as a string (e.g., "192.168.1.10")
    nonisolated
    func ipString() -> String? {
        var inAddr = self.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

        let result = withUnsafePointer(to: &inAddr) { ptr in
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                inet_ntop(AF_INET, ptr, bufPtr.baseAddress, socklen_t(INET_ADDRSTRLEN))
            }
        }

        if let cStr = result {
            return String(cString: cStr)
        } else {
            // inet_ntop failed; errno may contain the reason
            return nil
        }
    }

    /// Returns "ip:port" (e.g., "192.168.1.10:47984")
    nonisolated
    func ipPortString() -> String? {
        guard let ip = ipString() else { return nil }
        let port = Int(UInt16(bigEndian: sin_port)) // sin_port is network byte order
        return "\(ip):\(port)"
    }
}

extension sockaddr_in6 {
    nonisolated
    func ipString() -> String? {
        var inAddr = sin6_addr
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))

        let result = withUnsafePointer(to: &inAddr) { ptr in
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                inet_ntop(AF_INET6, ptr, bufPtr.baseAddress, socklen_t(INET6_ADDRSTRLEN))
            }
        }

        if let cStr = result {
            return String(cString: cStr)
        } else {
            return nil
        }
    }

    /// Returns "[ip]:port" for IPv6 (e.g., "[fe80::1]:47984")
    nonisolated
    func ipPortString() -> String? {
        guard let ip = ipString() else { return nil }
        let port = Int(UInt16(bigEndian: sin6_port))
        return "[\(ip)]:\(port)"
    }
}
