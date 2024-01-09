//
//  Share.swift
//
//
//  Created by Chris Jones on 08/01/2024.
//

import Foundation
import Fluent
import Vapor

final class Share: Model {
    static let schema = "shares"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "filename")
    var filename: String

    @Field(key: "uid")
    var uid: UUID

    @Timestamp(key: "createdAt", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, filename: String, uid: UUID) {
        self.id = id
        self.filename = filename
        self.uid = uid
    }
}
