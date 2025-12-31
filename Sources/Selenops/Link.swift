//
//  Link.swift
//  Selenops
//
//  Created by Norikazu Muramoto on 2024/11/01.
//

import Foundation

extension Crawler {
    /// Represents a link containing a URL, title, and similarity score.
    public struct Link: Hashable, Sendable {
        /// The URL of the link.
        public var url: URL

        /// The title of the linked page.
        public var title: String

        /// The relevance score based on similarity.
        public var score: Double?

        public init(url: URL, title: String, score: Double? = nil) {
            self.url = url
            self.title = title
            self.score = score
        }

        // MARK: - Hashable

        /// Links are considered equal if they have the same URL.
        /// Title and score are metadata that may vary for the same destination.
        public func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }

        public static func == (lhs: Link, rhs: Link) -> Bool {
            lhs.url == rhs.url
        }
    }
}
