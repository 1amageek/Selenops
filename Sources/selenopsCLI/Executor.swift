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

    /// The word to search for during crawling
    private let wordToSearch: String

    /// Maximum number of pages to visit
    private let maximumPagesToVisit: Int

    /// Found matches count
    private var matchCount: Int = 0

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
        let crawler = Crawler(delegate: self)
        await crawler.start(url: startUrl)
    }

    // MARK: - CrawlerDelegate

    public func crawler(_ crawler: Crawler, fetchContentAt url: URL) async throws -> FetchResult {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CrawlerError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CrawlerError.httpError(httpResponse.statusCode)
        }

        let encoding = Crawler.detectEncoding(from: httpResponse, data: data)

        guard let html = String(data: data, encoding: encoding) else {
            throw CrawlerError.invalidEncoding
        }

        // Return HTML as both content and html for link extraction
        return FetchResult(content: html, html: html)
    }

    public func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Crawler.Decision {
        // 同じドメインのURLのみを許可する
        guard let startHost = startUrl.host,
              let urlHost = url.host else {
            return .skip(.invalidURL)
        }

        if urlHost != startHost {
            return .skip(.businessLogic("Different domain: \(urlHost)"))
        }

        if visitedPages.count >= maximumPagesToVisit {
            return .skip(.businessLogic("Maximum pages limit reached"))
        }

        if visitedPages.contains(url) {
            return .skip(.businessLogic("Already visited"))
        }

        return .visit
    }

    public func crawler(_ crawler: Crawler, willVisitUrl url: URL) {
        print("Fetching \(url) (\(visitedPages.count + 1)/\(maximumPagesToVisit))")
    }

    public func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async {
        print("⏭️ Skipped \(url): \(reason)")
    }

    public func crawlerDidFinish(_ crawler: Crawler) {
        print("🏁 Finished! Visited pages: \(visitedPages.count)")
        print("🔍 Found \(matchCount) pages containing '\(wordToSearch)'")
    }

    public func crawler(_ crawler: Crawler) async -> URL? {
        return pagesToVisit.popFirst()
    }

    public func crawler(_ crawler: Crawler, didVisit url: URL) async {
        visitedPages.insert(url)
    }

    public func crawler(_ crawler: Crawler, didFindLinks links: Set<Crawler.Link>, at url: URL) async {
        let newUrls = links.map(\.url).filter { url in
            !visitedPages.contains(url) && !pagesToVisit.contains(url)
        }
        pagesToVisit.formUnion(newUrls)
    }

    public func crawler(_ crawler: Crawler, didFetchContent result: FetchResult, at url: URL) async {
        if result.content.localizedCaseInsensitiveContains(wordToSearch) {
            matchCount += 1
            print("✨ Found '\(wordToSearch)' at: \(url.absoluteString)")
        }
    }
}
