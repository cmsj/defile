//
//  IPSourceMiddleware.swift
//
//
//  Created by Chris Jones on 09/01/2024.
//

import Vapor

private struct CIDR {
    // Lots of inspiration for this struct comes from https://stackoverflow.com/a/52260818
    let net: String
    let prefix: Int

    init?(_ cidr: String) {
        let parts = cidr.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count != 2 {
            return nil
        }
        self.net = String(parts[0])
        guard let prefix = Int(parts[1]) else {
            return nil
        }
        self.prefix = prefix
    }

    private func convertIpToInt(_ ip: String) -> Int? {
        var result = 0.0
        let ipAddressArray = ip.components(separatedBy: ".").compactMap { Double($0) }
        guard ipAddressArray.count == 4 else { return nil }
        for (index, element) in ipAddressArray.enumerated() {
            result += element * pow(256, Double(3 - index))
        }

        let resultInt = Int(result)
        if resultInt <= 0 {
            return nil
        }
        return resultInt
    }

    func contains(_ ip: String) -> Bool? {
        guard let ipInt = convertIpToInt(ip) else { return nil }
        guard let netInt = convertIpToInt(net) else { return nil }
        let broadcastInt = netInt + Int(pow(2, Double(32-prefix))) - 1

        print("contains: \(net)/\(prefix), \(ip) :: ipInt: \(ipInt), netInt: \(netInt), broadcastInt: \(broadcastInt)")
        return ipInt >= netInt && ipInt <= broadcastInt
    }
}

struct IPSourceMiddleware: AsyncMiddleware {
    let useRemoteAddress: Bool
    let useForwarded: Bool
    let allowedCIDRs: [String]

    init(useRemoteAddress: Bool = false, useForwarded: Bool = false, allowedCIDRs: [String]) {
        self.useRemoteAddress = useRemoteAddress
        self.useForwarded = useForwarded
        self.allowedCIDRs = allowedCIDRs
    }

    func respond(to request: Vapor.Request, chainingTo next: Vapor.AsyncResponder) async throws -> Vapor.Response {
        let allowedRanges = allowedCIDRs.compactMap { CIDR($0) }

        var allowed: Bool = false

        if (useRemoteAddress) {
            if let remoteIP = request.remoteAddress?.ipAddress {
                for range in allowedRanges {
                    guard let result = range.contains(remoteIP) else { continue }
                    if result {
                        print("Allowing request from \(remoteIP)")
                        allowed = true
                        break
                    }
                }
            }
        }

        if (useForwarded) {
            for forward in request.headers.forwarded {
                print("Checking forwarded for: \(forward.for ?? "")")
                for range in allowedRanges {
                    guard let result = range.contains(forward.for ?? "") else { continue }
                    if result {
                        print("Allowing request forwarded for \(forward.for ?? "Unknown")")
                        allowed = true
                        break
                    }
                }
            }
        }

        if allowed {
            return try await next.respond(to: request)
        } else {
            print("Blocking request from invalid IP: \(request.remoteAddress?.ipAddress ?? "Unknown")")
            throw Abort(.unauthorized)
        }
    }

}
