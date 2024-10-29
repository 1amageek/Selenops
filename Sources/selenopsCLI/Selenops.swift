import ArgumentParser
import Foundation

@main
struct Selenops: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "selenops",
        abstract: "Searches for the given word on the web.",
        version: "1.0.0"
    )
    
    @Option(
        name: [.short, .customLong("start")],
        help: "The starting page URL (must have http:// or https:// prefix)."
    )
    var startUrl: String
    
    @Option(
        name: [.short, .customLong("word")],
        help: "The word to look for."
    )
    var wordToSearch: String
    
    @Option(
        name: [.short, .customLong("max")],
        help: "The maximum number of pages to visit."
    )
    var maximumPagesToVisit: Int = 10
    
    mutating func run() async throws {

        guard let url = URL(string: startUrl) else {
            throw ValidationError("Invalid URL format")
        }
        
        print("✅ Searching for: \(wordToSearch)")
        print("✅ Starting from: \(url.absoluteString)")
        print("✅ Maximum number of pages to visit: \(maximumPagesToVisit)")
        
        let executor = Executor(
            startUrl: url,
            wordToSearch: wordToSearch,
            maximumPagesToVisit: maximumPagesToVisit
        )
        
        await executor.run()
    }
}

