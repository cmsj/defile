//
//  CreateUsers.swift
//
//
//  Created by Chris Jones on 05/01/2024.
//

import Foundation
import Fluent
import Vapor

extension User {
    struct CreateUserTable: AsyncMigration {
        var name: String { "CreateUserTable" }
        func prepare(on database: Database) async throws {
            try await database.schema("users")
                .id()
                .field("username", .string, .required)
                .field("password", .string, .required)
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema("users").delete()
        }
    }
}
