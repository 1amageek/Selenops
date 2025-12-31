import Foundation
import SwiftSoup

/// Errors that can occur during crawling
public enum CrawlerError: Error {
    case invalidResponse
    case httpError(Int)
    case invalidEncoding
    case parseError(Error)
}

/// Represents the result of fetching content from a URL.
public struct FetchResult: Sendable {
    /// The fetched content (HTML, Markdown, or other text format).
    public let content: String

    /// The original HTML content, if available. Used for link extraction.
    public let html: String?

    public init(content: String, html: String? = nil) {
        self.content = content
        self.html = html
    }
}

/// A protocol that receives crawler-related events and manages crawling data.
///
/// Implement this protocol to receive notifications about crawler events and manage the crawler's data storage.
/// The delegate is responsible for managing the URLs to visit and keeping track of visited URLs.
public protocol CrawlerDelegate: Actor {
    /// Fetches content from the specified URL.
    ///
    /// This method allows developers to customize how content is retrieved.
    /// For example, you can use Remark to convert HTML to Markdown, or use
    /// a custom fetching strategy for JavaScript-rendered pages.
    ///
    /// - Parameters:
    ///   - crawler: The crawler requesting the content.
    ///   - url: The URL to fetch content from.
    /// - Returns: A `FetchResult` containing the content and optionally the original HTML.
    /// - Throws: An error if the content cannot be fetched.
    func crawler(_ crawler: Crawler, fetchContentAt url: URL) async throws -> FetchResult

    /// Determines whether the crawler should visit the specified URL.
    ///
    /// - Parameters:
    ///   - crawler: The crawler requesting permission to visit.
    ///   - url: The URL to potentially visit.
    /// - Returns: `.visit` if the URL should be visited, or `.skip` with a reason if it should be skipped.
    func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Crawler.Decision

    /// Notifies the delegate that the crawler will visit the specified URL.
    ///
    /// - Parameters:
    ///   - crawler: The crawler that will perform the visit.
    ///   - url: The URL to be visited.
    func crawler(_ crawler: Crawler, willVisitUrl url: URL)

    /// Notifies the delegate that the crawler has finished its execution.
    ///
    /// - Parameter crawler: The crawler that finished execution.
    func crawlerDidFinish(_ crawler: Crawler) async

    /// Provides the next URL to be visited by the crawler.
    ///
    /// - Parameter crawler: The crawler requesting the next URL.
    /// - Returns: The next URL to visit, or `nil` if there are no more URLs to visit.
    func crawler(_ crawler: Crawler) async -> URL?

    /// Notifies the delegate that the crawler has fetched content at the specified URL.
    ///
    /// - Parameters:
    ///   - crawler: The crawler that fetched the content.
    ///   - url: The URL associated with the content.
    ///   - result: The fetch result containing the content.
    func crawler(_ crawler: Crawler, didFetchContent result: FetchResult, at url: URL) async

    /// Records that a URL has been visited by the crawler.
    ///
    /// - Parameters:
    ///   - crawler: The crawler that visited the URL.
    ///   - url: The URL that was visited.
    func crawler(_ crawler: Crawler, didVisit url: URL) async

    /// Adds new links discovered during crawling.
    ///
    /// - Parameters:
    ///   - crawler: The crawler that found the links.
    ///   - links: An array of `Link` objects containing URLs, titles, and optional scores.
    ///   - url: The URL of the page where the links were found.
    func crawler(_ crawler: Crawler, didFindLinks links: Set<Crawler.Link>, at url: URL) async

    /// Notifies the delegate that the crawler has skipped the specified URL.
    ///
    /// Called when `shouldVisitUrl` returns `false` or when the URL is determined to be invalid.
    ///
    /// - Parameters:
    ///   - crawler: The crawler that skipped the URL.
    ///   - url: The URL that was skipped.
    ///   - reason: The reason why the URL was skipped.
    func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async
}

/// A web crawler that searches for specific words across web pages.
///
/// `Crawler` performs web crawling operations starting from a specified URL,
/// looking for a specific word across web pages. It delegates data management
/// and storage operations to its delegate.
///
/// Example usage:
/// ```swift
/// let crawler = Crawler(delegate: myDelegate)
/// await crawler.start(url: URL(string: "https://example.com")!)
/// ```
public final class Crawler: Sendable {

    /// Represents the decision whether to crawl a URL or skip it.
    public enum Decision: Sendable {
        /// The URL should be visited
        case visit
        /// The URL should be skipped for the specified reason
        case skip(SkipReason)
    }

    /// Represents reasons why a URL might be skipped during crawling.
    public enum SkipReason: Sendable {
        /// The URL was invalid or malformed
        case invalidURL

        /// The URL points to an unsupported file type
        case unsupportedFileType

        /// The URL was skipped due to business logic rules
        /// - Parameter reason: A description of why the URL was skipped
        case businessLogic(String)

        /// The URL was skipped due to an error
        /// - Parameter error: The error that caused the skip
        case error(Error)
    }

    /// The delegate that receives crawler events and manages data
    private let delegate: any CrawlerDelegate

    /// Creates a new web crawler instance.
    ///
    /// - Parameter delegate: The delegate that handles content fetching and crawling events.
    public init(delegate: any CrawlerDelegate) {
        self.delegate = delegate
    }
    
    /// Starts the crawling process.
    ///
    /// This method initiates the crawling process from the `startURL`.
    /// The crawler will continue until either the maximum number of pages
    /// has been visited or there are no more pages to visit.
    public func start(url: URL) async {
        await crawl(url: url)
    }
    
    /// Performs the crawling operation.
    ///
    /// This method manages the main crawling loop, requesting URLs from the delegate
    /// and visiting pages until completion conditions are met.
    private func crawl(url: URL) async {
        switch await delegate.crawler(self, shouldVisitUrl: url) {
        case .visit:
            await visit(page: url)
        case .skip(let reason):
            await delegate.crawler(self, didSkip: url, reason: reason)
        }
        
        while let pageToVisit = await delegate.crawler(self) {
            switch await delegate.crawler(self, shouldVisitUrl: pageToVisit) {
            case .visit:
                await visit(page: pageToVisit)
            case .skip(let reason):
                await delegate.crawler(self, didSkip: pageToVisit, reason: reason)
                continue
            }
        }
        await delegate.crawlerDidFinish(self)
    }
    
    /// Visits a specific webpage.
    ///
    /// - Parameter url: The URL of the page to visit.
    private func visit(page url: URL) async {
        do {
            await delegate.crawler(self, willVisitUrl: url)

            // Delegate handles content fetching - allows custom strategies like Remark
            let result = try await delegate.crawler(self, fetchContentAt: url)

            await delegate.crawler(self, didFetchContent: result, at: url)

            // Use HTML for link extraction if available, otherwise use content
            let htmlForParsing = result.html ?? result.content
            await parse(htmlForParsing, url: url)

            await delegate.crawler(self, didVisit: url)
        } catch {
            await delegate.crawler(self, didSkip: url, reason: .error(error))
        }
    }
    
    /// Parses webpage content and extracts relevant information.
    ///
    /// - Parameters:
    ///   - webpage: The HTML content to parse.
    ///   - url: The URL associated with the content.
    private func parse(_ webpage: String, url: URL) async {
        do {
            let document = try SwiftSoup.parse(webpage, url.absoluteString)
            let anchorElements = try document.select("a").array()
            var links: Set<Link> = []
            
            // Get base host to use as a reference if needed
            let baseHost = url.host
            
            for anchor in anchorElements {
                // Retrieve the href attribute and interpret it as a URL
                let href = try anchor.attr("href")
                guard let resolvedURL = URL(string: href, relativeTo: url)?.absoluteURL else { continue }
                
                // If a base host is available, use it as a filter criterion
                if let resolvedHost = resolvedURL.host, let baseHost = baseHost, resolvedHost != baseHost {
                    continue
                }
                
                // Normalize the URL by removing fragments and query parameters
                var urlComponents = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: true)
                urlComponents?.fragment = nil
                urlComponents?.queryItems = nil

                guard let normalizedURL = urlComponents?.url else { continue }
                
                // Determine title based on priority: aria-label > img[alt] > title > text content > normalized URL
                var title = try anchor.attr("aria-label").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if title.isEmpty, let img = try anchor.select("img[alt]").first() {
                    title = try img.attr("alt").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if title.isEmpty {
                    title = try anchor.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if title.isEmpty {
                    title = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // If no title is found, use the normalized URL as the title
                if title.isEmpty {
                    title = normalizedURL.absoluteString
                }
                
                let link = Link(url: normalizedURL, title: title, score: nil)
                links.insert(link)
            }
            
            // Notify the delegate with the extracted links
            await delegate.crawler(self, didFindLinks: links, at: url)
            
        } catch {
            print("Error parsing \(url): \(error)")
        }
    }
    
    /// Detects the character encoding from HTTP response headers and HTML meta tags.
    ///
    /// This utility method can be used by delegates implementing custom content fetching.
    ///
    /// - Parameters:
    ///   - response: The HTTP response containing Content-Type header.
    ///   - data: The raw response data for meta tag inspection.
    /// - Returns: The detected `String.Encoding`, defaulting to `.utf8` if not detected.
    public static func detectEncoding(from response: HTTPURLResponse, data: Data) -> String.Encoding {
        // First, try to get encoding from Content-Type header
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           let charsetPart = contentType.components(separatedBy: "charset=").last {
            // Extract charset value, removing any trailing parameters (e.g., "; boundary=xxx")
            let charset = charsetPart
                .components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? ""
            switch charset.lowercased() {
            case "shift_jis", "shift-jis", "shiftjis":
                return .shiftJIS
            case "euc-jp":
                return .japaneseEUC
            case "iso-2022-jp":
                return .iso2022JP
            case "utf-8":
                return .utf8
            default:
                break
            }
        }
        
        // If Content-Type header doesn't specify encoding, try to detect from meta tags
        // Use isoLatin1 as it can decode any byte sequence without failing
        if let content = String(data: data, encoding: .isoLatin1),
           let metaCharset = content.range(of: "charset=", options: [.caseInsensitive]) {
            let startIndex = metaCharset.upperBound
            let endIndex = content[startIndex...].firstIndex(where: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }) ?? content.endIndex
            let charset = content[startIndex..<endIndex].lowercased()
            
            switch charset {
            case "shift_jis", "shift-jis", "shiftjis":
                return .shiftJIS
            case "euc-jp":
                return .japaneseEUC
            case "iso-2022-jp":
                return .iso2022JP
            case "utf-8":
                return .utf8
            default:
                break
            }
        }
        
        // Default to UTF-8 if no encoding is specified
        return .utf8
    }
}
