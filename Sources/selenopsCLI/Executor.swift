import Foundation
import Selenops
import os

/// Executes web crawling operations.
public final class Executor: CrawlerDelegate, Sendable {

    private struct State {
        var visitedPages: Set<URL> = []
        var pagesToVisit: Set<URL> = []
        var matchCount: Int = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let startUrl: URL
    private let wordToSearch: String
    private let maximumPagesToVisit: Int

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

    public func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) async -> Crawler.Decision {
        guard let startHost = startUrl.host, let urlHost = url.host else {
            return .skip(.invalidURL)
        }

        if urlHost != startHost {
            return .skip(.businessLogic("Different domain: \(urlHost)"))
        }

        return state.withLock { state in
            if state.visitedPages.count >= maximumPagesToVisit {
                return .skip(.businessLogic("Maximum pages limit reached"))
            }

            if state.visitedPages.contains(url) {
                return .skip(.businessLogic("Already visited"))
            }

            return .visit
        }
    }

    public func crawler(_ crawler: Crawler, willVisitUrl url: URL) async {
        let count = state.withLock { $0.visitedPages.count }
        print("Fetching \(url) (\(count + 1)/\(maximumPagesToVisit))")
    }

    public func crawler(_ crawler: Crawler, visit url: URL) async throws {
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

        // Check for word match
        if html.localizedCaseInsensitiveContains(wordToSearch) {
            state.withLock { $0.matchCount += 1 }
            print("✨ Found '\(wordToSearch)' at: \(url.absoluteString)")
        }

        // Parse links
        await crawler.parseLinks(from: html, at: url)
    }

    public func crawler(_ crawler: Crawler, didVisit url: URL) async {
        _ = state.withLock { $0.visitedPages.insert(url) }
    }

    public func crawler(_ crawler: Crawler, didFindLinks links: Set<Crawler.Link>, at url: URL) async {
        state.withLock { state in
            let newUrls = links.map(\.url).filter { url in
                !state.visitedPages.contains(url) && !state.pagesToVisit.contains(url)
            }
            state.pagesToVisit.formUnion(newUrls)
        }
    }

    public func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async {
        print("⏭️ Skipped \(url): \(reason)")
    }

    public func crawler(_ crawler: Crawler) async -> URL? {
        return state.withLock { $0.pagesToVisit.popFirst() }
    }

    public func crawlerDidFinish(_ crawler: Crawler) async {
        let (visited, matches) = state.withLock { ($0.visitedPages.count, $0.matchCount) }
        print("🏁 Finished! Visited pages: \(visited)")
        print("🔍 Found \(matches) pages containing '\(wordToSearch)'")
    }
}
