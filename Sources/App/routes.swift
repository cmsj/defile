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
            throw Abort(.notFound, reason: "UID missing")
        }

        guard let uid = UUID(uuidString: uidString) else {
            throw Abort(.badRequest, reason: "UID malformed")
        }

        let share = try await Share.query(on: req.db)
            .filter(\.$uid == uid)
            .first()

        if let share {
            req.logger.debug("Valid uid: \(uid) for file \(share.filename)")
            let response = req.fileio.streamFile(at: app.directory.workingDirectory + "Private/\(share.filename)") { result in
                switch result {
                case .success():
                    req.logger.info("Download complete for \(uid) of file \(share.filename)")
                    Task { // Required to call async db methods from this sync closure
                        do {
                            try await share.delete(on: req.db)
                            req.logger.info("Share deleted for \(uid) of file \(share.filename)")
                        } catch {
                            req.logger.error("Unable to await share deletion for \(uid) of \(share.filename)")
                        }
                    }
                case .failure(let error):
                    req.logger.error("Download failed for \(uid) of file \(share.filename): \(error)")
                }
            }
            response.headers.add(name: "content-disposition", value: "attachment; filename=\"\(share.filename)\"")
            return response
        }

        throw Abort(.notFound, reason: "UID not found")
    }

    // Register our admin area
    try app.register(collection: AdminController(env: app.environment))
}
