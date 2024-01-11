import NIOSSL
import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.sessions.configuration.cookieName = "defile"
    app.sessions.configuration.cookieFactory = { sessionID in
        var isSecure = false
        if let hasTLS = ProcessInfo.processInfo.environment["DEFILE_HAS_TLS"] {
            isSecure = (hasTLS == "true")
        }

        return HTTPCookies.Value.init(string: sessionID.string, isSecure: isSecure)
    }
    app.middleware.use(app.sessions.middleware)
    app.middleware.use(User.sessionAuthenticator())

    app.databases.use(DatabaseConfigurationFactory.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(User.CreateUserTable())
    app.migrations.add(User.SeedUserTable())
    app.migrations.add(Share.CreateShareTable())

    try await app.autoMigrate()

    app.views.use(.leaf)

    // register routes
    try routes(app)
}
