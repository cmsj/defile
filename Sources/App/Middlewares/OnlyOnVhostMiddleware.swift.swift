//
//  File.swift
//  
//
//  Created by Chris Jones on 10/01/2024.
//

import Vapor

struct OnlyOnVhostMiddleware: AsyncMiddleware {
    let vhost: String

    func respond(to request: Vapor.Request, chainingTo next: Vapor.AsyncResponder) async throws -> Vapor.Response {
        if let forwardHost = request.headers.forwarded.first?.host {
            if forwardHost == vhost {
                request.logger.debug("Allowing vhost \(forwardHost)")
                return try await next.respond(to: request)
            } else {
                request.logger.warning("Blocking request for invalid vhost: \(forwardHost)")
                throw Abort(.unauthorized)
            }
        }
        request.logger.warning("Blocking request with no forwarding host")
        throw Abort(.unauthorized)
    }
    

}
