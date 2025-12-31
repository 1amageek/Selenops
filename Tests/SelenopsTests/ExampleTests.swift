import Testing
import Foundation
@testable import Selenops

@Test("Example")
func example() async throws {
    let startURL = URL(string: "https://www.google.com/search?q=Locations%20suitable%20for%20autumn%20foliage%20season")!

    let executor = SampleExecutor(
        startUrl: startURL,
        wordToSearch: "Fall",
        maximumPagesToVisit: 10
    )

    await executor.run()
}

/// An actor that executes web crawling operations.
public actor SampleExecutor: CrawlerDelegate {
    private var visitedPages: Set<URL> = []
    private var pagesToVisit: Set<URL> = []
    private let startUrl: URL
    private let wordToSearch: String
    private let maximumPagesToVisit: Int
    private var matchCount: Int = 0

    public init(startUrl: URL, wordToSearch: String, maximumPagesToVisit: Int) {
        self.startUrl = startUrl
        self.wordToSearch = wordToSearch
        self.maximumPagesToVisit = maximumPagesToVisit
    }

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

        return FetchResult(content: html, html: html)
    }

    public func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Crawler.Decision {
        guard let startHost = startUrl.host, let urlHost = url.host else {
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
