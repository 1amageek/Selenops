import Foundation
import SwiftSoup

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
            try await delegate.crawler(self, visit: url)
            await delegate.crawler(self, didVisit: url)
        } catch {
            await delegate.crawler(self, didSkip: url, reason: .error(error))
        }
    }

    /// Parses webpage content and extracts links.
    ///
    /// Call this method from your delegate's `visit` implementation to extract links from HTML.
    ///
    /// - Parameters:
    ///   - html: The HTML content to parse.
    ///   - url: The URL associated with the content.
    public func parseLinks(from html: String, at url: URL) async {
        do {
            let document = try SwiftSoup.parse(html, url.absoluteString)
            let anchorElements = try document.select("a").array()
            var links: Set<Link> = []

            for anchor in anchorElements {
                // Retrieve the href attribute and interpret it as a URL
                let href = try anchor.attr("href")
                guard let resolvedURL = URL(string: href, relativeTo: url)?.absoluteURL else { continue }

                // Skip non-HTTP(S) URLs (mailto:, javascript:, tel:, etc.)
                guard let scheme = resolvedURL.scheme?.lowercased(),
                      ["http", "https"].contains(scheme) else { continue }

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
