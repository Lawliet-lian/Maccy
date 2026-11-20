import Foundation
import SwiftData

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: Int64(size))
  }

  private let url: URL

  init(url: URL? = nil) {
    self.url = url ?? URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
    var config = ModelConfiguration(url: self.url)

    #if DEBUG
    if url == nil, CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  func cleanupOrphanedContents() async throws {
    let container = self.container
    try await Task.detached(priority: .utility) {
      let context = ModelContext(container)
      try context.delete(model: HistoryItemContent.self, where: #Predicate { $0.item == nil })
      try context.save()
    }.value
  }
}
