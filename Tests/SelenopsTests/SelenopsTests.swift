import Testing
import Foundation
@testable import Selenops
import SwiftSoup

final class MockCrawlerDelegate: CrawlerDelegate, @unchecked Sendable {
    var urlsVisited: [URL] = []
    var urlsFoundWord: [URL] = []
    var didFinishCrawling = false
    
    func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) -> Bool { true }
    func crawler(_ crawler: Crawler, willVisitUrl url: URL) {
        urlsVisited.append(url)
    }
    func crawler(_ crawler: Crawler, didFindWordAt url: URL) {
        urlsFoundWord.append(url)
    }
    func crawlerDidFinish(_ crawler: Crawler) {
        didFinishCrawling = true
    }
}

@Test("Crawler visits pages and finds the search word")
func testCrawlerVisitsPagesAndFindsWord() async throws {
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
    let mockDelegate = MockCrawlerDelegate()
    
    let crawler = Crawler(
        startURL: startURL,
        maximumPagesToVisit: 2,
        wordToSearch: "searchWord"
    )
    
    await crawler.setDelegate(mockDelegate)
    
    await crawler.crawl()
    
    await crawler._injectHTMLContent(htmlContent, for: startURL)
    
    #expect(mockDelegate.urlsVisited.contains(startURL), "Start URL was not visited")
    #expect(mockDelegate.urlsFoundWord.contains(startURL), "Start URL did not contain the search word")
    #expect(mockDelegate.didFinishCrawling, "Crawler did not finish as expected")
}
