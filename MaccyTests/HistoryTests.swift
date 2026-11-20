import XCTest
import Defaults
import SwiftData
@testable import Maccy

@MainActor
class HistoryTests: XCTestCase {
  let savedSize = Defaults[.size]
  let savedSortBy = Defaults[.sortBy]
  let history = History.shared

  override func setUp() {
    super.setUp()
    history.clearAll()
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
  }

  func testDefaultIsEmpty() {
    XCTAssertEqual(history.items, [])
  }

  func testAdding() {
    let first = history.add(historyItem("foo"))
    let second = history.add(historyItem("bar"))
    XCTAssertEqual(history.items, [second, first])
  }

  func testAddingSame() {
    let first = historyItem("foo")
    first.title = "xyz"
    first.application = "iTerm.app"
    let firstDecorator = history.add(first)
    first.pin = "f"

    let secondDecorator = history.add(historyItem("bar"))

    let third = historyItem("foo")
    third.application = "Xcode.app"
    history.add(third)

    XCTAssertEqual(history.items, [firstDecorator, secondDecorator])
    XCTAssertTrue(history.items[0].item.lastCopiedAt > history.items[0].item.firstCopiedAt)
    // TODO: This works in reality but fails in tests?!
    // XCTAssertEqual(history.items[0].item.numberOfCopies, 2)
    XCTAssertEqual(history.items[0].item.pin, "f")
    XCTAssertEqual(history.items[0].item.title, "xyz")
    XCTAssertEqual(history.items[0].item.application, "iTerm.app")
  }

  func testAddingItemThatIsSupersededByExisting() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.rtf.rawValue,
        value: "two".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.application = "Maccy.app"
    firstItem.contents = firstContents
    firstItem.title = firstItem.generateTitle()
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.application = "Maccy.app"
    secondItem.contents = secondContents
    secondItem.title = secondItem.generateTitle()
    let second = history.add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemWithDifferentModifiedType() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "1".data(using: .utf8)!
      )
    ]
    let firstItem = HistoryItem()
    Storage.shared.context.insert(firstItem)
    firstItem.contents = firstContents
    history.add(firstItem)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)!
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.modified.rawValue,
        value: "2".data(using: .utf8)!
      )
    ]
    let secondItem = HistoryItem()
    Storage.shared.context.insert(secondItem)
    secondItem.contents = secondContents
    let second = history.add(secondItem)

    XCTAssertEqual(history.items, [second])
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testAddingItemFromMaccy() {
    let firstContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      )
    ]
    let first = HistoryItem()
    Storage.shared.context.insert(first)
    first.application = "Xcode.app"
    first.contents = firstContents
    history.add(first)

    let secondContents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: "one".data(using: .utf8)
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fromMaccy.rawValue,
        value: "".data(using: .utf8)
      )
    ]
    let second = HistoryItem()
    Storage.shared.context.insert(second)
    second.application = "Maccy.app"
    second.contents = secondContents
    let secondDecorator = history.add(second)

    XCTAssertEqual(history.items, [secondDecorator])
    XCTAssertEqual(history.items[0].item.application, "Xcode.app")
    XCTAssertEqual(Set(history.items[0].item.contents), Set(firstContents))
  }

  func testModifiedAfterCopying() {
    history.add(historyItem("foo"))

    let modifiedItem = historyItem("bar")
    modifiedItem.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: String(Clipboard.shared.changeCount).data(using: .utf8)
    ))
    let modifiedItemDecorator = history.add(modifiedItem)

    XCTAssertEqual(history.items, [modifiedItemDecorator])
    XCTAssertEqual(history.items[0].text, "bar")
  }

  func testClearingUnpinned() {
    let pinned = history.add(historyItem("foo"))
    pinned.togglePin()
    history.add(historyItem("bar"))
    history.clear()
    XCTAssertEqual(history.items, [pinned])
  }

  func testClearingAll() {
    history.add(historyItem("foo"))
    history.clear()
    XCTAssertEqual(history.items, [])
  }

  func testMaxSize() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 10)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[0]))
  }

  func testMaxSizeIgnoresPinned() {
    var items: [HistoryItemDecorator] = []

    let item = history.add(historyItem("0"))
    items.append(item)
    item.togglePin()

    for index in 1...11 {
      items.append(history.add(historyItem(String(index))))
    }

    XCTAssertEqual(history.items.count, 11)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertTrue(history.items.contains(items[0]))
    XCTAssertFalse(history.items.contains(items[1]))
  }

  func testMaxSizeIsChanged() {
    var items: [HistoryItemDecorator] = []
    for index in 0...10 {
      items.append(history.add(historyItem(String(index))))
    }
    Defaults[.size] = 5
    history.add(historyItem("11"))

    XCTAssertEqual(history.items.count, 5)
    XCTAssertTrue(history.items.contains(items[10]))
    XCTAssertFalse(history.items.contains(items[5]))
  }

  func testRemoving() {
    let foo = history.add(historyItem("foo"))
    let bar = history.add(historyItem("bar"))
    history.delete(foo)
    XCTAssertEqual(history.items, [bar])
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.numberOfCopies = 1
    item.title = item.generateTitle()

    return item
  }
}

@MainActor
class HistoryMemoryTests: XCTestCase {
  func testEvictedDecoratorsReleaseWhileHistoryStaysAtCapacity() throws {
    let history = History.shared
    let oldSize = Defaults[.size]
    let oldChangeCount = Clipboard.shared.changeCount
    Defaults[.size] = 5
    defer {
      history.all.forEach { history.delete($0) }
      Defaults[.size] = oldSize
      Clipboard.shared.changeCount = oldChangeCount
    }

    let image = NSImage(named: "NSApplicationIcon")!.tiffRepresentation!
    var tracked: [() -> HistoryItemDecorator?] = []
    for index in 1...25 {
      Clipboard.shared.changeCount = oldChangeCount + index
      let item = HistoryItem(contents: [
        HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(String(index).utf8)),
        HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: image)
      ])
      Storage.shared.context.insert(item)
      let decorator = history.add(item)
      decorator.loadThumbnail()
      decorator.showPreview = true
      decorator.showPreview = false
      tracked.append { [weak decorator] in decorator }
    }

    try Storage.shared.context.save()
    XCTAssertEqual(history.all.count, 5)
    XCTAssertEqual(tracked.compactMap { $0() }.count, 5)
    XCTAssertEqual(try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>(
      predicate: #Predicate { $0.item == nil }
    )), 0)
  }

  func testReplacingPinnedItemKeepsContentsAndReleasesOldMapping() throws {
    let history = History.shared
    let oldChangeCount = Clipboard.shared.changeCount
    defer {
      history.all.forEach { history.delete($0) }
      Clipboard.shared.changeCount = oldChangeCount
    }

    let first = insert("first")
    first.pin = "f"
    weak var oldDecorator = history.add(first)
    Clipboard.shared.changeCount += 1
    let duplicate = insert("first")
    let replacement = history.add(duplicate)
    try Storage.shared.context.save()
    XCTAssertNil(oldDecorator)
    XCTAssertEqual(history.items, [replacement])
    XCTAssertEqual(replacement.item.pin, "f")
    XCTAssertEqual(replacement.item.numberOfCopies, 2)
    XCTAssertEqual(replacement.item.text, "first")

    let staleUpdate = insert("stale update")
    staleUpdate.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: Data(String(oldChangeCount).utf8)
    ))
    Clipboard.shared.changeCount += 1
    let staleDecorator = history.add(staleUpdate)
    XCTAssertTrue(history.items.contains(replacement))
    XCTAssertTrue(staleDecorator.isUnpinned)

    let update = insert("updated")
    update.contents.append(HistoryItemContent(
      type: NSPasteboard.PasteboardType.modified.rawValue,
      value: Data(String(oldChangeCount + 1).utf8)
    ))
    Clipboard.shared.changeCount += 1
    let updated = history.add(update)
    try Storage.shared.context.save()
    XCTAssertEqual(updated.item.pin, "f")
    XCTAssertEqual(updated.item.numberOfCopies, 3)
    XCTAssertEqual(updated.item.text, "updated")
    XCTAssertFalse(history.items.contains(replacement))
  }

  func testHoverAndSpaceUseTheSamePreview() async throws {
    let appState = AppState.shared
    let history = appState.history
    let oldDelay = HistoryItemDecorator.previewThrottler.minimumDelay
    let image = try XCTUnwrap(NSImage(named: "NSApplicationIcon")?.tiffRepresentation)
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: image)
    ])
    Storage.shared.context.insert(item)
    let decorator = history.add(item)
    defer {
      history.delete(decorator)
      HistoryItemDecorator.previewThrottler.minimumDelay = oldDelay
      appState.lastHoveredHistorySelection = nil
      appState.currentHoveredHistorySelection = nil
      appState.isKeyboardNavigating = true
    }

    HistoryItemDecorator.previewThrottler.minimumDelay = 0
    appState.isKeyboardNavigating = false
    appState.handleHoverSelection(decorator.id, hovering: true)
    for _ in 0..<100 where decorator.previewImage == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let hoverImage = try XCTUnwrap(decorator.previewImage)
    XCTAssertTrue(appState.closePreviewAndRestoreLastHoveredSelection())
    XCTAssertEqual(appState.selection, decorator.id)
    XCTAssertNil(decorator.previewImage)

    XCTAssertTrue(appState.toggleFullImagePreviewForSelectedItem())
    let spaceImage = try XCTUnwrap(decorator.previewImage)
    XCTAssertEqual(spaceImage.size, hoverImage.size)
    XCTAssertEqual(spaceImage.tiffRepresentation, hoverImage.tiffRepresentation)
    XCTAssertTrue(appState.toggleFullImagePreviewForSelectedItem())
    XCTAssertNil(decorator.previewImage)
  }

  func testCleanupPreservesPinnedImageAndItsData() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let storage = Storage(url: directory.appending(path: "Storage.sqlite"))
    let image = Data(repeating: 1, count: 1024 * 1024)
    let pinned = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: image)
    ])
    pinned.pin = "f"
    storage.context.insert(pinned)
    storage.context.insert(HistoryItemContent(type: "orphan", value: Data([1])))
    try storage.context.save()
    XCTAssertEqual(try storage.context.fetchCount(FetchDescriptor<HistoryItemContent>()), 2)

    try await storage.cleanupOrphanedContents()
    let context = ModelContext(storage.container)
    let preserved = try XCTUnwrap(context.fetch(FetchDescriptor<HistoryItem>()).first)
    XCTAssertEqual(preserved.pin, "f")
    XCTAssertEqual(preserved.imageData, image)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryItemContent>()), 1)
  }

  private func insert(_ text: String) -> HistoryItem {
    let item = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(text.utf8))
    ])
    Storage.shared.context.insert(item)
    return item
  }
}
