# Selenops
<p align="center">
    <img src="logo.png" width="580" max-width="90%" alt="Selenops logo" />
    <br/>
    <img src="https://img.shields.io/badge/swift-6.0-orange.svg" />
    <a href="https://swift.org/package-manager">
        <img src="https://img.shields.io/badge/swiftpm-compatible-brightgreen.svg?style=flat" alt="Swift Package Manager" />
    </a>
     <img src="https://img.shields.io/badge/platforms-macOS+iOS+iPadOS+tvOS+watchOS-brightgreen.svg?style=flat" alt="MacOS + iOS + iPadOS + tvOS + watchOS"/>
    <a href="https://twitter.com/zntfdr">
        <img src="https://img.shields.io/badge/twitter-@zntfdr-blue.svg?style=flat" alt="Twitter: @zntfdr" />
    </a>
</p>

Welcome to **Selenops**, a Swift Web Crawler.

Selenops is a lightweight, Swift-based web crawler that efficiently searches for specific words across web pages. Built with Swift Concurrency, it provides a safe and performant way to crawl websites.

## Features

- ✨ Built with Swift Concurrency (async/await)
- 🔍 Efficient word search across web pages
- 🛡️ Safe concurrent operations with Actor model
- 🎯 Domain-specific crawling
- 📊 Progress tracking
- 🔌 Extensible delegate pattern for data management
- 📱 Command-line interface tool included

## Requirements

- Swift 6.0+
- iOS 18.0+
- macOS 15.0+

## Installation

### Swift Package Manager

Add Selenops as a dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/Selenops.git", from: "1.0.0")
]
```

### Command Line Tool

To install the command-line tool:

1. Clone the repository
2. Run `swift build -c release`
3. The binary will be located at `.build/release/selenops-cli`

You can install it globally by copying it to your path:
```bash
sudo cp .build/release/selenops-cli /usr/local/bin/selenops
```

## Usage

### As a Library

```swift
import Selenops

// Create an executor
let executor = Executor(
    startUrl: URL(string: "https://example.com")!,
    wordToSearch: "swift",
    maximumPagesToVisit: 100
)

// Start crawling
await executor.run()
```

### Command Line Interface

```bash
# Basic usage
selenops-cli crawl --url https://example.com --word swift --max-pages 100

# Show help
selenops-cli --help
```

### Custom Implementation

You can create your own crawler delegate by conforming to the `CrawlerDelegate` protocol:

```swift
import Selenops

actor MyCrawlerDelegate: CrawlerDelegate {
    private var visitedPages: Set<URL> = []
    private var pagesToVisit: Set<URL> = []
    let startUrl: URL
    let maximumPagesToVisit: Int

    init(startUrl: URL, maximumPagesToVisit: Int) {
        self.startUrl = startUrl
        self.maximumPagesToVisit = maximumPagesToVisit
    }

    func crawler(_ crawler: Crawler, shouldVisitUrl url: URL) async -> Crawler.Decision {
        guard let startHost = startUrl.host, let urlHost = url.host else {
            return .skip(.invalidURL)
        }

        if urlHost != startHost {
            return .skip(.businessLogic("Different domain"))
        }

        if visitedPages.count >= maximumPagesToVisit {
            return .skip(.businessLogic("Maximum pages limit reached"))
        }

        if visitedPages.contains(url) {
            return .skip(.businessLogic("Already visited"))
        }

        return .visit
    }

    func crawler(_ crawler: Crawler, willVisitUrl url: URL) async {
        print("Visiting: \(url)")
    }

    func crawler(_ crawler: Crawler, visit url: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CrawlerError.invalidResponse
        }

        let encoding = Crawler.detectEncoding(from: httpResponse, data: data)
        guard let html = String(data: data, encoding: encoding) else {
            throw CrawlerError.invalidEncoding
        }

        // Process your content here
        // ...

        // Parse and collect links
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
        print("Skipped \(url): \(reason)")
    }

    func crawler(_ crawler: Crawler) async -> URL? {
        return pagesToVisit.popFirst()
    }

    func crawlerDidFinish(_ crawler: Crawler) async {
        print("Finished! Visited \(visitedPages.count) pages")
    }
}

// Use your custom delegate
let delegate = MyCrawlerDelegate(
    startUrl: URL(string: "https://example.com")!,
    maximumPagesToVisit: 100
)
let crawler = Crawler(delegate: delegate)
await crawler.start(url: URL(string: "https://example.com")!)
```

## Features

### Domain-Specific Crawling

By default, Selenops only crawls URLs within the same domain as the start URL. This behavior can be customized by implementing your own `shouldVisitUrl` logic in the delegate.

### Progress Tracking

Selenops provides detailed progress tracking through its delegate methods:

```swift
func crawler(_ crawler: Crawler, willVisitUrl url: URL) async {
    print("Currently visiting: \(url)")
}

func crawler(_ crawler: Crawler, didSkip url: URL, reason: Crawler.SkipReason) async {
    print("Skipped \(url): \(reason)")
}

func crawlerDidFinish(_ crawler: Crawler) async {
    print("Crawling completed")
}
```

### Data Management

The delegate pattern allows for flexible data storage solutions:

- In-memory storage
- Database storage
- Distributed storage
- Custom storage solutions

## API Reference

### CrawlerDelegate Protocol

The `CrawlerDelegate` protocol defines the interface for receiving crawler events:

| Method | Description |
|--------|-------------|
| `shouldVisitUrl(_:)` | Determines whether to visit a URL. Returns `Crawler.Decision` |
| `willVisitUrl(_:)` | Called before visiting a URL |
| `visit(_:)` | Fetches and processes content for a URL |
| `didVisit(_:)` | Called after successfully visiting a URL |
| `didFindLinks(_:at:)` | Called when links are extracted from a page |
| `didSkip(_:reason:)` | Called when a URL is skipped |
| `crawler(_:)` | Provides the next URL to visit |
| `crawlerDidFinish(_:)` | Called when crawling is complete |

### Crawler.Decision

Controls whether a URL should be visited:

```swift
public enum Decision: Sendable {
    case visit                    // URL should be visited
    case skip(SkipReason)         // URL should be skipped
}
```

### Crawler.SkipReason

Describes why a URL was skipped:

```swift
public enum SkipReason: Sendable {
    case invalidURL               // URL was invalid or malformed
    case unsupportedFileType      // URL points to an unsupported file type
    case businessLogic(String)    // Skipped due to business logic rules
    case error(Error)             // Skipped due to an error
}
```

### Crawler.Link

Represents a discovered link:

```swift
public struct Link: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var score: Double?   // Relevance score (optional)
}
```

### Utility Methods

- `Crawler.detectEncoding(from:data:)` - Detects character encoding from HTTP response
- `crawler.parseLinks(from:at:)` - Parses HTML and extracts links (call from `visit`)

## Dependencies

- [SwiftSoup](https://github.com/scinfu/SwiftSoup) - HTML Parser
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser) - Command-line interface support

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Selenops is available under the MIT license. See the LICENSE file for more info.

## Why "Selenops"?

Selenops is named after a genus of spiders known for their speed and agility. Like its namesake, this crawler is designed to be fast and efficient in navigating web content.

## Credits

Selenops was built by [Federico Zanetello](https://twitter.com/zntfdr) as an [example of a Swift script][selenopsArticle].
[@1amageek](https://github.com/1amageek)

## Contributions and Support

All users are welcome and encouraged to become active participants in the project continued development — by fixing any bug that they encounter, or by improving the documentation wherever it’s found to be lacking.

If you'd like to make a change, please [open a Pull Request](https://github.com/zntfdr/Selenops/pull/new), even if it just contains a draft of the changes you’re planning, or a test that reproduces an issue.

Thank you and please enjoy using **Selenops**!

[selenopsArticle]: https://www.fivestars.blog/code/build-web-crawler-swift.html
