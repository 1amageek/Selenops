import Foundation
import SwiftSoup

/// Errors that can occur during crawling
public enum CrawlerError: Error {
    case invalidResponse
    case httpError(Int)
    case invalidEncoding
    case parseError(Error)
}

/// A protocol that receives crawler-related events and manages crawling data.
///
/// Implement this protocol to receive notifications about crawler events and manage the crawler's data storage.
/// The delegate is responsible for managing the URLs to visit and keeping track of visited URLs.
public protocol CrawlerDelegate: Actor {
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
    
    /// Notifies the delegate that the crawler has fetched raw content at the specified URL.
    ///
    /// - Parameters:
    ///   - crawler: The crawler that fetched the content.
    ///   - url: The URL associated with the content.
    ///   - content: The raw HTML content of the page.
    func crawler(_ crawler: Crawler, didFetchContent content: String, at url: URL) async
    
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
/// let crawler = Crawler(
///     startURL: URL(string: "https://example.com")!,
///     maximumPagesToVisit: 100,
///     wordToSearch: "example"
/// )
/// crawler.delegate = myDelegate
/// await crawler.start()
/// ```
public actor Crawler {
    
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
    public weak var delegate: (any CrawlerDelegate)?
    
    /// Creates a new web crawler instance.
    ///
    public init() {
        
    }
    
    /// Sets the delegate for receiving crawler events and managing crawling data.
    ///
    /// The delegate is responsible for managing URLs to visit and tracking visited URLs.
    /// It also receives notifications about crawler events such as finding the search word
    /// or completing the crawl operation.
    ///
    /// - Parameter delegate: The object that will act as the delegate for the crawler.
    ///                      Pass `nil` to remove the current delegate.
    public func setDelegate(_ delegate: (any CrawlerDelegate)?) {
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
        guard let delegate = delegate else { return }
        
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
        guard let delegate = delegate else { return }
        
        do {
            await delegate.crawler(self, willVisitUrl: url)
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await delegate.crawler(self, didSkip: url, reason: .error(CrawlerError.invalidResponse))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                await delegate.crawler(self, didSkip: url, reason: .error(CrawlerError.httpError(httpResponse.statusCode)))
                return
            }
            
            // Get encoding from Content-Type header
            let encoding = detectEncoding(from: httpResponse, data: data)
            
            guard let webpage = String(data: data, encoding: encoding) else {
                await delegate.crawler(self, didSkip: url, reason: .error(CrawlerError.invalidEncoding))
                return
            }
            
            await delegate.crawler(self, didFetchContent: webpage, at: url)
            await parse(webpage, url: url)
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
                urlComponents?.query = nil
                
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
            await delegate?.crawler(self, didFindLinks: links, at: url)
            
        } catch {
            print("Error parsing \(url): \(error)")
        }
    }
    
    // Detect encoding from Content-Type header and meta tags
    private func detectEncoding(from response: HTTPURLResponse, data: Data) -> String.Encoding {
        // First, try to get encoding from Content-Type header
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           let charset = contentType.components(separatedBy: "charset=").last?.trimmingCharacters(in: .whitespaces) {
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
        if let content = String(data: data, encoding: .ascii),
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
