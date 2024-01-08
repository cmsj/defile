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

func routes(_ app: Application) throws {
    // Root page - nobody needs this, so just return something useless
    app.get { req async throws in
        try await req.view.render("index", ["title": "Defile"])
    }

    // Serve downloads to valid UIDs
    app.get("download", ":uid") { req async -> String in
        guard let uid = req.parameters.get("uid") else {
            return "UID missing"
        }
        // TODO: Check UID is valid, read the file, send it to the client
        return "Downloading \(uid)"
    }

    // Display login page
    app.get("login") { req async throws in
        try await req.view.render("login")
    }
    // Handle logout
    app.get("logout") { req async throws in
        req.session.destroy()
        return req.redirect(to: "/")
    }

    // Define a route context for pages that require being logged-in
    let redirectMiddleware = User.redirectMiddleware { req -> String in
        print("User not logged in, redirecting to login page")
        return "/login?authRequired=true&next=\(req.url.path)"
    }
    let protected = app.grouped([
        User.credentialsAuthenticator(),
        redirectMiddleware
    ])

    protected.post("login", use: loginPostHandler)

    protected.get("admin") { req async throws -> Response in
        let user = try req.auth.require(User.self)
        return try await req
            .view
            .render("admin", ["username": user.username])
            .encodeResponse(for: req)
    }
}
