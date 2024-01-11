import Fluent
import Vapor
import Crypto
import NIOCore
import NIOHTTP1
import NIOConcurrencyHelpers

struct LoginPageInfo: Content {
    var nextURL: String
}

struct CreateShare: Content {
    var filename: String
}

struct RevokeShare: Content {
    var uid: UUID
}

struct AdminContext: Encodable {
    let baseURL: String
    let username: String
    let files: [SharableFile]
    let shares: [Share]
}

struct SharableFile: Encodable {
    let filename: String
    var hash: String

    init(filename: String) {
        self.filename = filename
        self.hash = SHA256.hash(data: Data(filename.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}

func loginPostHandler(_ req: Request) async throws -> Response {
    let content = try req.content.decode(LoginPageInfo.self)
    let nextURL = content.nextURL
    req.logger.info("loginPostHandler: redirecting to \(content.nextURL)")
    return req.redirect(to: nextURL)
}

struct AdminController: RouteCollection {
    let env: Environment
    let baseURL: String

    init(env: Environment) {
        self.env = env

        if let baseURL = ProcessInfo.processInfo.environment["DEFILE_PUBLIC_URL"] {
            self.baseURL = baseURL
        } else {
            self.baseURL = ""
        }
    }

    func boot(routes: RoutesBuilder) throws {
        // Create a bare route group for not-logged-in admins
        let adminUnauthenticatedRoutes = routes.grouped("admin")

        // Declare some middleware containers for our various route groups
        var adminSessionMiddlewares: [Middleware] = []
        var adminLoginMiddlewares: [Middleware] = []

        // Create Middleware to redirect any admin requests that aren't logged in, to the login page
        let redirectMiddleware = User.redirectMiddleware { req -> String in
            req.logger.info("[\(req.remoteAddress?.ipAddress ?? "Unknown IP")] User not logged in, redirecting to login page")
            return "/admin/login?authRequired=true&next=/admin"
        }

        // Create Middleware to only allow requests made to a trusted vhost
        var onlyOnVhostMiddleware: Middleware? = nil
        if let vhost = ProcessInfo.processInfo.environment["DEFILE_ADMIN_VHOST"] {
            onlyOnVhostMiddleware = OnlyOnVhostMiddleware(vhost: vhost)
        }


        // Populate the middleware container for logged in admin routes
        if onlyOnVhostMiddleware != nil { adminSessionMiddlewares.append(onlyOnVhostMiddleware!)}
        adminSessionMiddlewares.append(User.sessionAuthenticator())
        adminSessionMiddlewares.append(redirectMiddleware)

        // Greate the route group for logged in admins
        let adminSessionRoutes = adminUnauthenticatedRoutes.grouped(adminSessionMiddlewares)


        // Populate the middleware container for admin login attempts
        if onlyOnVhostMiddleware != nil { adminLoginMiddlewares.append(onlyOnVhostMiddleware!) }
        adminLoginMiddlewares.append(User.credentialsAuthenticator())
        adminLoginMiddlewares.append(redirectMiddleware)

        // Create the route group for admin login attempts
        let adminLoginRoutes = adminUnauthenticatedRoutes.grouped(adminLoginMiddlewares)


        // /admin: root page
        adminSessionRoutes.get { req async throws -> Response in
            let user = try req.auth.require(User.self)
            var files: [SharableFile] = []
            var shares: [Share] = []

            // Get all extant shares
            shares = try await Share.query(on: req.db).all()

            // Get all sharable files
            let fm = FileManager.default
            do {
                let items = try fm.contentsOfDirectory(atPath: "Private")
                for item in items {
                    files.append(SharableFile(filename: item))
                }
            } catch {
                // FIXME: This doesn't actually render anything in a client browser. Return a generic error page instead
                return try await HTTPStatus.internalServerError
                    .encodeResponse(for: req)
            }

            let context = AdminContext(baseURL: self.baseURL, username: user.username, files: files, shares: shares)

            return try await req
                .view
                .render("admin", context)
                .encodeResponse(for: req)
        }

        // /admin/login: Display login page
        adminUnauthenticatedRoutes.get("login") { req async throws in
            try await req.view.render("login")
        }

        // /admin/login: Receive login attempts
        adminLoginRoutes.post("login", use: loginPostHandler)

        // /admin/logout: Handle logout
        adminSessionRoutes.get("logout") { req async throws in
            req.session.destroy()
            return req.redirect(to: "/admin")
        }

        adminSessionRoutes.post("createShare") { req async throws in
            let content = try req.content.decode(CreateShare.self)
            req.logger.info("createShare: sharing \(content.filename)")
            let share = Share(filename: content.filename, uid: UUID())
            try await share.create(on: req.db)
            return req.redirect(to: "/admin")
        }

        adminSessionRoutes.post("revokeShare") { req async throws in
            let content = try req.content.decode(RevokeShare.self)
            req.logger.info("revokeShare: revoking \(content.uid)")
            let share = try await Share.query(on: req.db)
                .filter(\.$uid == content.uid)
                .first()

            if let share {
                try await share.delete(on: req.db)
            }

            return req.redirect(to: "/admin")
        }

        adminSessionRoutes.on(.POST, "uploadFile", body: .stream) { req throws -> Response in
            enum BodyStreamWritingToDiskError: Error {
                case streamFailure(Error)
                case fileHandleClosedFailure(Error)
                case multipleFailures([BodyStreamWritingToDiskError])
            }

            guard let boundary = req.headers.contentType?.parameters["boundary"] else {
                throw Abort(.badRequest)
            }
            req.logger.info("multipart/form-data boundary: boundary")

            let parser = MultipartParser(boundary: boundary)
            var fileHandle: NIOFileHandle?

            parser.onHeader = { name, value in
                print("onHeader: \(name): \(value)")
                if name.lowercased() == "content-disposition" {
                    let header = HTTPHeaders(dictionaryLiteral: (name, value))

                    if let filename: String = header.contentDisposition?.filename {
                        let path = req.application.directory.workingDirectory + "/Private/\(filename)"
                        do {
                            fileHandle = try NIOFileHandle(path: path, mode: .write, flags: .allowFileCreation(posixMode: 0x744))
                            // I feel like we should be using req.application.fileio.openFile() but I don't know how to properly call an NIO future - it's supposed to be eventloop driven magic, but we can (and do) end up with onBody being called before the file has been opened, losing data.
                            //                        req.eventLoop.submit({
                            //                            return req.application.fileio.openFile(path: path, mode: .write, flags: .allowFileCreation(posixMode: 0x744), eventLoop: req.eventLoop)
                            //                                .flatMap { handle in
                            //                                    req.logger.info("onHeader opened file")
                            //                                    fileHandle = handle
                            //                                    return req.eventLoop.makeSucceededFuture(())
                            //                                }
                            //                        })
                        } catch {
                            req.logger.error("Unable to open \(path)")
                        }

                    }
                }
            }
            parser.onBody = { bytes in
                guard let fileHandle else {
                    // FIXME: This should error more thoughtfully, otherwise it will be called a *lot*
                    req.logger.error("multipart onBody call before fileHandle exists")
                    return
                }

                req.logger.info("Writing...")
                req.application.fileio.write(fileHandle: fileHandle, buffer: bytes, eventLoop: req.eventLoop)
            }
            parser.onPartComplete = {
                print("onPartComplete")
                guard let fileHandle else {
                    // FIXME: This should error somehow
                    req.logger.error("multipart onPartComplete call before fileHandle exists")
                    return
                }
                do {
                    try fileHandle.close()
                } catch {
                    // FIXME: This should error somehow
                    req.logger.error("unable to close fileHandle in onPartComplete")
                    return
                }
            }

            req.body.drain { part in
                switch part {
                case .buffer(let buffer):
                    print("Parsing...")
                    do {
                        try parser.execute(buffer)
                    } catch {
                        req.logger.error("Caught exception parsing buffer")
                    }
                case .error(let drainError):
                    req.logger.error("\(drainError.localizedDescription)")
                    return req.eventLoop.makeFailedFuture(drainError)
                case .end:
                    print("Body drained")
                }
                return req.eventLoop.makeSucceededFuture(())
            }
            return req.redirect(to: "/admin")
        }
    }
}
