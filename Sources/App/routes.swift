import Fluent
import Vapor

func loginPostHandler(_ req: Request) async throws -> Response {
    if req.auth.has(User.self) {
        let nextURL = req.parameters.get("next") ?? "/admin" // FIXME: next isn't working here
        print("loginPostHandler: nextURL: \(nextURL)")
        return req.redirect(to: nextURL)
    } else {
        return try await req
            .view
            .render("login")
            .encodeResponse(for: req)
    }
}

func routes(_ app: Application) throws {
    // Root page - nobody needs this, so just return something useless
    app.get { req async throws in
        try await req.view.render("index", ["title": "Defile"])
    }

    // Display login page
    app.get("login") { req async throws in
        try await req.view.render("login")
    }

    let redirectMiddleware = User.redirectMiddleware { req -> String in
        print("User not logged in, redirecting to login page")
        return "/login?authRequired=true&next=\(req.url.path)"
    }
    let protected = app.grouped([
        User.credentialsAuthenticator(),
        redirectMiddleware
    ])

    protected.post("login", use: loginPostHandler)

    protected.get("admin") { req async throws -> String in
        do {
            let user = try req.auth.require(User.self)
            return "Welcome \(user.username)"
        } catch is Abort {
            return "Unauthorized"
        } catch {
            throw Abort(.internalServerError)
        }
    }

    app.get("download", ":uid") { req async -> String in
        guard let uid = req.parameters.get("uid") else {
            return "UID missing"
        }
        return "Downloading \(uid)"
    }
//    try app.register(collection: TodoController())
}
