import Fluent
import Vapor
import Crypto

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
    let username: String
    let files: [File]
    let shares: [Share]
}

struct File: Encodable {
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
    print("loginPostHandler: redirecting to \(content.nextURL)")
    return req.redirect(to: nextURL)
}

struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let admin = routes.grouped("admin")

        // Define a route context for pages that require being logged-in
        let redirectMiddleware = User.redirectMiddleware { req -> String in
            print("[\(req.remoteAddress?.ipAddress ?? "Unknown IP")] User not logged in, redirecting to login page")
            return "/admin/login?authRequired=true&next=/admin"
        }
        let protected = admin.grouped([
            User.credentialsAuthenticator(),
            redirectMiddleware
        ])

        // /admin: root page
        protected.get { req async throws -> Response in
            let user = try req.auth.require(User.self)
            var files: [File] = []
            var shares: [Share] = []

            // Get all extant shares
            shares = try await Share.query(on: req.db).all()


            // Get all sharable files
            let fm = FileManager.default
            do {
                let items = try fm.contentsOfDirectory(atPath: "Private")
                for item in items {
                    files.append(File(filename: item))
                }
            } catch {
                // FIXME: This doesn't actually render anything in a client browser. Return a generic error page instead
                return try await HTTPStatus.internalServerError
                    .encodeResponse(for: req)
            }

            let context = AdminContext(username: user.username, files: files, shares: shares)

            return try await req
                .view
                .render("admin", context)
                .encodeResponse(for: req)
        }

        // /admin/login: Display login page
        admin.get("login") { req async throws in
            try await req.view.render("login")
        }

        // /admin/login: Receive login attempts
        protected.post("login", use: loginPostHandler)

        // /admin/logout: Handle logout
        admin.get("logout") { req async throws in
            req.session.destroy()
            return req.redirect(to: "/admin")
        }

        protected.post("createShare") { req async throws in
            let content = try req.content.decode(CreateShare.self)
            print("createShare: sharing \(content.filename)")
            let share = Share(filename: content.filename, uid: UUID())
            try await share.create(on: req.db)
            return req.redirect(to: "/admin")
        }

        protected.post("revokeShare") { req async throws in
            let content = try req.content.decode(RevokeShare.self)
            print("revokeShare: revoking \(content.uid)")
            let share = try await Share.query(on: req.db)
                .filter(\.$uid == content.uid)
                .first()

            if let share {
                try await share.delete(on: req.db)
            }

            return req.redirect(to: "/admin")
        }
    }
}
