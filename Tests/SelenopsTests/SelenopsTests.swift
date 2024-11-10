import Testing
import Foundation
@testable import Selenops
import SwiftSoup

// テスト用のHTMLコンテンツ注入機能
extension Crawler {
    private static var injectedContent: [URL: String] = [:]
    private static var session: URLSession = .shared
    
    actor TestHelper {
        static func injectHTMLContent(_ content: String, for url: URL) {
            injectedContent[url] = content
        }
        
        static func getInjectedContent(for url: URL) -> String? {
            return injectedContent[url]
        }
        
        static func clearInjectedContent() {
            injectedContent.removeAll()
        }
        
        static func setURLSession(_ session: URLSession) {
            Crawler.session = session
        }
    }
    
    func injectHTMLContent(_ content: String, for url: URL) async {
        await TestHelper.injectHTMLContent(content, for: url)
    }
    
    func setupForTesting() async {
        await TestHelper.setURLSession(.mock)
    }
}

extension URLSession {
    static let mock: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }()
}

class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    func startLoading() async {
        guard let url = request.url,
              let content = await Crawler.TestHelper.getInjectedContent(for: url),
              let data = content.data(using: .utf8) else {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html"]
        )!
        
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}

final actor MockCrawlerDelegate: CrawlerDelegate {
    var visitedPages: Set<URL> = []
    var pagesToVisit: Set<URL> = []
    var urlsFoundWord: [URL] = []
    var urlsSkipped: [(URL, Crawler.SkipReason)] = []
    var didFinishCrawling = false
    let wordToSearch: String
    let maximumPagesToVisit: Int
    let startUrl: URL
    
    init(startUrl: URL, wordToSearch: String, maximumPagesToVisit: Int) {
        self.startUrl = startUrl
        self.wordToSearch = wordToSearch
        self.maximumPagesToVisit = maximumPagesToVisit
    }
    
    func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Crawler.Decision {
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
    
    func crawler(_ crawler: Crawler, willVisitUrl url: URL) {}
    
    func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async {
        urlsSkipped.append((url, reason))
    }
    
    func crawler(_ crawler: Crawler) async -> URL? {
        return pagesToVisit.popFirst()
    }
    
    func crawler(_ crawler: Crawler, didFetchContent content: String, at url: URL) async {
        if content.localizedCaseInsensitiveContains(wordToSearch) {
            urlsFoundWord.append(url)
        }
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
    
    func crawlerDidFinish(_ crawler: Crawler) {
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
    
    let crawler = Crawler()
    await crawler.setupForTesting()
    await crawler.setDelegate(mockDelegate)
    await crawler.injectHTMLContent(htmlContent, for: startURL)
    await crawler.start(url: startURL)
    
    #expect(await mockDelegate.visitedPages.contains(startURL), "Start URL was not visited")
    #expect(await mockDelegate.urlsFoundWord.contains(startURL), "Search word was not found")
    #expect(await mockDelegate.didFinishCrawling, "Crawler did not finish")
    
    await Crawler.TestHelper.clearInjectedContent()
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
    
    let crawler = Crawler()
    await crawler.setupForTesting()
    await crawler.setDelegate(mockDelegate)
    await crawler.injectHTMLContent(htmlContent, for: startURL)
    await crawler.start(url: startURL)
    
    let visitedPages = await mockDelegate.visitedPages
    #expect(visitedPages.count <= 2, "Crawler exceeded maximum pages limit")
    #expect(visitedPages.contains(startURL), "Start URL was not visited")
    #expect(await mockDelegate.didFinishCrawling, "Crawler did not finish")
    
    await Crawler.TestHelper.clearInjectedContent()
}

@Test("Crawler skips different domain URLs")
func testCrawlerSkipsDifferentDomain() async throws {
    let startURL = URL(string: "https://example.com")!
    let htmlContent = """
    <html><body>
        <p>Test page</p>
        <a href="https://different.com">Different domain</a>
    </body></html>
    """
    
    let mockDelegate = MockCrawlerDelegate(
        startUrl: startURL,
        wordToSearch: "searchWord",
        maximumPagesToVisit: 5
    )
    
    let crawler = Crawler()
    await crawler.setupForTesting()
    await crawler.setDelegate(mockDelegate)
    await crawler.injectHTMLContent(htmlContent, for: startURL)
    await crawler.start(url: startURL)
    
    let skippedURLs = await mockDelegate.urlsSkipped
    let skippedDifferentDomain = skippedURLs.contains { url, reason in
        if case .businessLogic(let message) = reason {
            return message.contains("Different domain")
        }
        return false
    }
    
    #expect(skippedDifferentDomain, "Crawler did not skip different domain")
    #expect(await mockDelegate.didFinishCrawling, "Crawler did not finish")
    
    await Crawler.TestHelper.clearInjectedContent()
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
    
    let crawler = Crawler()
    await crawler.setupForTesting()
    await crawler.setDelegate(mockDelegate)
    await crawler.injectHTMLContent(htmlContent, for: startURL)
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
    
    await Crawler.TestHelper.clearInjectedContent()
}
