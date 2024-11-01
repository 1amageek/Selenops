import Foundation
import Selenops


/// An actor that executes web crawling operations.
public actor Executor: CrawlerDelegate {

    /// The number of pages visited
    private var visitedPages: Set<URL> = []
    
    /// Pages to visit
    private var pagesToVisit: Set<URL> = []
    
    /// The starting URL for crawling
    private let startUrl: URL
    
    /// The word to search for
    private let wordToSearch: String
    
    /// Maximum number of pages to visit
    private let maximumPagesToVisit: Int
    
    /// Creates a new Executor instance.
    ///
    /// - Parameters:
    ///   - startUrl: The URL where crawling will begin.
    ///   - wordToSearch: The word to search for during crawling.
    ///   - maximumPagesToVisit: The maximum number of pages to visit.
    public init(
        startUrl: URL,
        wordToSearch: String,
        maximumPagesToVisit: Int
    ) {
        self.startUrl = startUrl
        self.wordToSearch = wordToSearch
        self.maximumPagesToVisit = maximumPagesToVisit
    }
    
    /// Starts the crawling process.
    public func run() async {
        let crawler = Crawler()
        
        await crawler.setDelegate(self)
        await crawler.start(url: startUrl)
    }
    
    // MARK: - CrawlerDelegate
    
    public func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Bool {
        // 同じドメインのURLのみを許可する
        guard let startHost = startUrl.host,
              let urlHost = url.host else {
            return false
        }
        return urlHost == startHost
    }
    
    public func crawler(_ crawler: Crawler, willVisitUrl url: URL) {
        print("Fetching \(url) (\(visitedPages.count + 1)/\(maximumPagesToVisit))")
    }
    
    public func crawler(_ crawler: Crawler, didFindWordAt url: URL) {
        print("✅ Word found at: \(url.absoluteString)")
    }
    
    public func crawlerDidFinish(_ crawler: Crawler) {
        print("🏁 Finished! Visited pages: \(visitedPages.count)")
        exit(EXIT_SUCCESS)
    }
    
    public func crawler(_ crawler: Crawler) async -> URL? {
        if visitedPages.count >= maximumPagesToVisit {
            return nil
        }
        return pagesToVisit.popFirst()
    }
    
    public func crawler(_ crawler: Crawler, didVisit url: URL) async {
        visitedPages.insert(url)
    }
    
    public func crawler(_ crawler: Crawler, didFind urls: [URL]) async {
        pagesToVisit.formUnion(urls)
    }
    
    public func crawler(_ crawler: Crawler, hasVisited url: URL) async -> Bool {
        return visitedPages.contains(url)
    }
    
    public func crawlerVisitedPagesCount(_ crawler: Crawler) async -> Int {
        return visitedPages.count
    }
    
    public func crawler(_ crawler: Crawler, didFetchContent content: String, at url: URL) async {
        
    }
    
    public func crawler(_ crawler: Crawler, didFindLinks links: Set<Link>, at url: URL) async {
        self.pagesToVisit = Set(links.map({ $0.url }))
    }
}
