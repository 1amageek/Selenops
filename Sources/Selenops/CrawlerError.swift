import Foundation

/// Errors that can occur during crawling
public enum CrawlerError: Error {
    case invalidResponse
    case httpError(Int)
    case invalidEncoding
    case parseError(Error)
}
