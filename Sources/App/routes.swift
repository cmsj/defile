import Fluent
import Vapor

func routes(_ app: Application) throws {
    // Root page - nobody needs this, so just return something useless
    app.get { req async throws in
        try await req.view.render("index", ["title": "Defile"])
    }

    // Serve downloads to valid UIDs
    app.get("download", ":uid") { req async throws -> Response in
        guard let uidString = req.parameters.get("uid") else {
            return try await req
                .view
                .render("index", ["error": "UID missing"])
                .encodeResponse(for: req)
        }

        guard let uid = UUID(uuidString: uidString) else {
            return try await req
                .view
                .render("index", ["error": "UID malformed"])
                .encodeResponse(for: req)
        }

        let share = try await Share.query(on: req.db)
            .filter(\.$uid == uid)
            .first()

        if let share {
            print("Valid uid: \(uid) for file \(share.filename)")
            let response = req.fileio.streamFile(at: app.directory.workingDirectory + "Private/\(share.filename)") { result in
                switch result {
                case .success():
                    print("Download complete for \(uid) of file \(share.filename)")
                    Task {
                        do {
                            try await share.delete(on: req.db)
                            print("Share deleted for \(uid) of file \(share.filename)")
                        } catch {
                            print("Unable to await share deletion for \(uid) of \(share.filename)")
                        }
                    }
                case .failure(let error):
                    print("Download failed for \(uid) of file \(share.filename): \(error)")
                }
            }
            response.headers.add(name: "content-disposition", value: "attachment; filename=\"\(share.filename)\"")
            return response
        }

        return try await req
            .view
            .render("index", ["error": "UID not found"])
            .encodeResponse(for: req)
    }

    // Register our admin area
    try app.register(collection: AdminController())
}
