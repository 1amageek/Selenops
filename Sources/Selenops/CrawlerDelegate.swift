import Foundation

/// A protocol that receives crawler-related events and manages crawling data.
public protocol CrawlerDelegate: Sendable {

    /// Determines whether the crawler should visit the specified URL.
    func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) async -> Crawler.Decision

    /// Notifies the delegate that the crawler will visit the specified URL.
    func crawler(_ crawler: Crawler, willVisitUrl url: URL) async

    /// Visits the URL: fetches content and processes it.
    func crawler(_ crawler: Crawler, visit url: URL) async throws

    /// Records that a URL has been visited by the crawler.
    func crawler(_ crawler: Crawler, didVisit url: URL) async

    /// Adds new links discovered during crawling.
    func crawler(_ crawler: Crawler, didFindLinks links: Set<Crawler.Link>, at url: URL) async

    /// Notifies the delegate that the crawler has skipped the specified URL.
    func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async

    /// Provides the next URL to be visited by the crawler.
    func crawler(_ crawler: Crawler) async -> URL?

    /// Notifies the delegate that the crawler has finished its execution.
    func crawlerDidFinish(_ crawler: Crawler) async
}
