import Foundation
import SwiftSoup

/// A protocol that receives crawler-related events and manages crawling data.
///
/// Implement this protocol to receive notifications about crawler events and manage the crawler's data storage.
/// The delegate is responsible for managing the URLs to visit and keeping track of visited URLs.
public protocol CrawlerDelegate: Actor {
    /// Determines whether the crawler should visit the specified URL.
    ///
    /// - Parameters:
    ///   - crawler: The crawler requesting the visit.
    ///   - url: The URL to be visited.
    /// - Returns: `true` if the crawler should visit the URL, `false` otherwise.
    func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Bool
    
    /// Notifies the delegate that the crawler will visit the specified URL.
    ///
    /// - Parameters:
    ///   - crawler: The crawler that will perform the visit.
    ///   - url: The URL to be visited.
    func crawler(_ crawler: Crawler, willVisitUrl url: URL)
    
    /// Notifies the delegate that the crawler has finished its execution.
    ///
    /// - Parameter crawler: The crawler that finished execution.
    func crawlerDidFinish(_ crawler: Crawler)
    
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
    
    /// Checks if a URL has already been visited.
    ///
    /// - Parameters:
    ///   - crawler: The crawler making the check.
    ///   - url: The URL to check.
    /// - Returns: `true` if the URL has been visited, `false` otherwise.
    func crawler(_ crawler: Crawler, hasVisited url: URL) async -> Bool
    
    /// Provides the count of pages visited by the crawler.
    ///
    /// - Parameter crawler: The crawler requesting the count.
    /// - Returns: The number of pages visited.
    func crawlerVisitedPagesCount(_ crawler: Crawler) async -> Int
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
        
        if await delegate.crawler(self, shouldVisitUrl: url) {
            await visit(page: url)
        }
        
        while let pageToVisit = await delegate.crawler(self) {
            if await delegate.crawler(self, hasVisited: pageToVisit) {
                continue
            }
            
            if await delegate.crawler(self, shouldVisitUrl: pageToVisit) {
                await visit(page: pageToVisit)
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
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let webpage = String(data: data, encoding: .utf8) else {
                return
            }
            await delegate.crawler(self, didFetchContent: webpage, at: url)
            await parse(webpage, url: url)
            await delegate.crawler(self, didVisit: url)
        } catch {
            print("Error visiting \(url): \(error)")
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
                
                // Determine title based on priority: aria-label > link text > img alt > title attribute
                var title = try anchor.attr("aria-label").trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty { title = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                if title.isEmpty, let img = try anchor.select("img[alt]").first() {
                    title = try img.attr("alt").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if title.isEmpty { title = try anchor.attr("title").trimmingCharacters(in: .whitespacesAndNewlines) }
                
                // Skip link if title is empty
                if title.isEmpty { continue }
                let link = Link(url: normalizedURL, title: title, score: nil)
                links.insert(link)
            }
            
            // Notify the delegate with the extracted links
            await delegate?.crawler(self, didFindLinks: links, at: url)
            
        } catch {
            print("Error parsing \(url): \(error)")
        }
    }
}
