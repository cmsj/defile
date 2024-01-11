//
//  SeedUserTable.swift
//
//
//  Created by Chris Jones on 06/01/2024.
//

import Foundation
import Fluent
import Vapor

extension User {
    struct SeedUserTable: AsyncMigration {
        var name: String { "SeedUserTable"}
        var adminUsername: String { "admin" }
        var defaultAdminPassword: String {
            do {
                return try Bcrypt.hash("admin")
            } catch {
                return ""
            }
        }

        func prepare(on database: Database) async throws {
            // Create our default admin user
            let admin = User(username: adminUsername, password: defaultAdminPassword)
            try await admin.save(on: database)
        }

        func revert(on database: Database) async throws {
            try await User.query(on: database)
                .filter(\.$username == adminUsername)
                .delete()
        }
    }
}

