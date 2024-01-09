//
//  CreateShareTable.swift
//
//
//  Created by Chris Jones on 08/01/2024.
//

import Foundation
import Fluent
import Vapor

extension Share {
    struct CreateShareTable: AsyncMigration {
        var name: String { "CreateShareTable" }
        func prepare(on database: Database) async throws {
            try await database.schema("shares")
                .id()
                .field("filename", .string, .required)
                .field("uid", .uuid, .required)
                .field("createdAt", .time)
                .create()
        }

        func revert(on database: Database) async throws {
            try await database.schema("shares").delete()
        }
    }
}
