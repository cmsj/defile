import Fluent
import Vapor

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

    // Register our admin area
    try app.register(collection: AdminController())
}
