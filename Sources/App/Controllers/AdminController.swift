import Fluent
import Vapor

struct LoginPageInfo: Content {
    var nextURL: String
}

func loginPostHandler(_ req: Request) async throws -> Response {
    if req.auth.has(User.self) {
        let content = try req.content.decode(LoginPageInfo.self)
        let nextURL = content.nextURL
        print("loginPostHandler: redirecting to \(content.nextURL)")
        return req.redirect(to: nextURL)
    } else {
        return try await req
            .view
            .render("login")
            .encodeResponse(for: req)
    }
}

struct AdminController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let admin = routes.grouped("admin")

        // Define a route context for pages that require being logged-in
        let redirectMiddleware = User.redirectMiddleware { req -> String in
            print("User not logged in, redirecting to login page")
            return "/admin/login?authRequired=true&next=\(req.url.path)"
        }
        let protected = admin.grouped([
            User.credentialsAuthenticator(),
            redirectMiddleware
        ])

        // /admin: root page
        protected.get { req async throws -> Response in
            let user = try req.auth.require(User.self)
            return try await req
                .view
                .render("admin", ["username": user.username])
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
            return req.redirect(to: "/")
        }
    }
}
