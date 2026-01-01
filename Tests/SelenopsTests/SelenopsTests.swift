import Testing
import Foundation
@testable import Selenops

/// Mock delegate for testing that stores injected HTML content
final actor MockCrawlerDelegate: CrawlerDelegate {
    var visitedPages: Set<URL> = []
    var pagesToVisit: Set<URL> = []
    var urlsFoundWord: [URL] = []
    var urlsSkipped: [(URL, Crawler.SkipReason)] = []
    var didFinishCrawling = false
    let wordToSearch: String
    let maximumPagesToVisit: Int
    let startUrl: URL

    /// Injected HTML content for testing
    private var injectedContent: [URL: String] = [:]

    init(startUrl: URL, wordToSearch: String, maximumPagesToVisit: Int) {
        self.startUrl = startUrl
        self.wordToSearch = wordToSearch
        self.maximumPagesToVisit = maximumPagesToVisit
    }

    /// Inject HTML content for a specific URL (for testing)
    func injectContent(_ content: String, for url: URL) {
        injectedContent[url] = content
    }

    func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) async -> Crawler.Decision {
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

    func crawler(_ crawler: Crawler, willVisitUrl url: URL) async {}

    func crawler(_ crawler: Crawler, visit url: URL) async throws {
        guard let html = injectedContent[url] else {
            throw CrawlerError.invalidResponse
        }

        // Check for word match
        if html.localizedCaseInsensitiveContains(wordToSearch) {
            urlsFoundWord.append(url)
        }

        // Parse links
        await crawler.parseLinks(from: html, at: url)
    }

    func crawler(_ crawler: Crawler, didVisit url: URL) async {
        visitedPages.insert(url)
    }

    func crawler(_ crawler: Crawler, didFindLinks links: Set<Crawler.Link>, at url: URL) async {
        let newUrls = links.map(\.url).filter { url in
            !visitedPages.contains(url) && !pagesToVisit.contains(url)
        }
        pagesToVisit.formUnion(newUrls)
    }

    func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async {
        urlsSkipped.append((url, reason))
    }

    func crawler(_ crawler: Crawler) async -> URL? {
        return pagesToVisit.popFirst()
    }

    func crawlerDidFinish(_ crawler: Crawler) async {
        didFinishCrawling = true
    }
}

@Test("Crawler finds search word in single page")
func testCrawlerFindSearchWord() async throws {
    let htmlContent = """
    <html>
    <head><title>Test Page</title></head>
    <body>
        <p>This page contains the word 'searchWord'.</p>
        <a href="https://example.com/page2">Next Page</a>
    </body>
    </html>
    """

    let startURL = URL(string: "https://example.com")!
    let mockDelegate = MockCrawlerDelegate(
        startUrl: startURL,
        wordToSearch: "searchWord",
        maximumPagesToVisit: 2
    )
    await mockDelegate.injectContent(htmlContent, for: startURL)

    let crawler = Crawler(delegate: mockDelegate)
    await crawler.start(url: startURL)

    #expect(await mockDelegate.visitedPages.contains(startURL), "Start URL was not visited")
    #expect(await mockDelegate.urlsFoundWord.contains(startURL), "Search word was not found")
    #expect(await mockDelegate.didFinishCrawling, "Crawler did not finish")
}

@Test("Crawler respects maximum pages limit")
func testCrawlerMaximumPagesLimit() async throws {
    let startURL = URL(string: "https://example.com")!
    let htmlContent = """
    <html><body>
        <p>Start page</p>
        <a href="https://example.com/page1">Page 1</a>
        <a href="https://example.com/page2">Page 2</a>
        <a href="https://example.com/page3">Page 3</a>
    </body></html>
    """

    let mockDelegate = MockCrawlerDelegate(
        startUrl: startURL,
        wordToSearch: "searchWord",
        maximumPagesToVisit: 2
    )
    await mockDelegate.injectContent(htmlContent, for: startURL)

    let crawler = Crawler(delegate: mockDelegate)
    await crawler.start(url: startURL)

    let visitedPages = await mockDelegate.visitedPages
    #expect(visitedPages.count <= 2, "Crawler exceeded maximum pages limit")
    #expect(visitedPages.contains(startURL), "Start URL was not visited")
    #expect(await mockDelegate.didFinishCrawling, "Crawler did not finish")
}

@Test("Crawler filters out different domain URLs during parsing")
func testCrawlerFiltersDifferentDomain() async throws {
    let startURL = URL(string: "https://example.com")!
    let htmlContent = """
    <html><body>
        <p>Test page</p>
        <a href="https://different.com">Different domain</a>
        <a href="https://example.com/page2">Same domain</a>
    </body></html>
    """

    let mockDelegate = MockCrawlerDelegate(
        startUrl: startURL,
        wordToSearch: "searchWord",
        maximumPagesToVisit: 5
    )
    await mockDelegate.injectContent(htmlContent, for: startURL)

    let crawler = Crawler(delegate: mockDelegate)
    await crawler.start(url: startURL)

    // Different domain links are filtered out during parsing, not via shouldVisit
    // Only same-domain links should be added to pagesToVisit
    let pagesToVisit = await mockDelegate.pagesToVisit
    let containsDifferentDomain = pagesToVisit.contains { $0.host == "different.com" }

    #expect(!containsDifferentDomain, "Different domain URL should be filtered out during parsing")
    #expect(await mockDelegate.didFinishCrawling, "Crawler did not finish")
}

@Test("Crawler skips previously visited URLs")
func testCrawlerSkipsVisitedURLs() async throws {
    let startURL = URL(string: "https://example.com")!
    let htmlContent = """
    <html><body>
        <p>Test page</p>
        <a href="https://example.com">Same URL</a>
    </body></html>
    """

    let mockDelegate = MockCrawlerDelegate(
        startUrl: startURL,
        wordToSearch: "searchWord",
        maximumPagesToVisit: 5
    )
    await mockDelegate.injectContent(htmlContent, for: startURL)

    let crawler = Crawler(delegate: mockDelegate)
    await crawler.start(url: startURL)

    let skippedURLs = await mockDelegate.urlsSkipped
    let skippedVisited = skippedURLs.contains { url, reason in
        if case .businessLogic(let message) = reason {
            return message == "Already visited"
        }
        return false
    }

    #expect(skippedVisited, "Crawler did not skip visited URL")
    #expect(await mockDelegate.didFinishCrawling, "Crawler did not finish")
}
