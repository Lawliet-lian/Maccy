import AppKit
import Defaults
import Foundation
import Settings

@Observable
class AppState: Sendable {
  static let shared = AppState()

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer

  var scrollTarget: UUID?
  var selection: UUID? {
    didSet {
      selectWithoutScrolling(selection)
      scrollTarget = selection
    }
  }

  func selectWithoutScrolling(_ item: UUID?) {
    history.selectedItem = nil
    footer.selectedItem = nil

    if let item = history.items.first(where: { $0.id == item }) {
      history.selectedItem = item
    } else if let item = footer.items.first(where: { $0.id == item }) {
      footer.selectedItem = item
    }
  }

  /// 记录鼠标最近一次真正悬停到的历史记录项。
  /// 手动关闭图片预览时，需要回到这里，方便继续沿着刚才的鼠标位置往后浏览。
  var lastHoveredHistorySelection: UUID?
  /// 记录鼠标当前正停留在哪一条历史项上。
  /// 这个状态和 `lastHoveredHistorySelection` 不同：
  /// - `lastHoveredHistorySelection` 用来做“关闭预览后回到上一次位置”
  /// - `currentHoveredHistorySelection` 用来判断“现在是不是鼠标明确选中了某条历史项”
  ///   这样搜索框按回车时，就不会因为默认高亮了第一条结果而误触发复制。
  var currentHoveredHistorySelection: UUID?
  var hoverSelectionWhileKeyboardNavigating: UUID?
  var isKeyboardNavigating: Bool = true {
    didSet {
      if let hoverSelection = hoverSelectionWhileKeyboardNavigating {
        hoverSelectionWhileKeyboardNavigating = nil
        selection = hoverSelection
      }
    }
  }

  /// 手动关闭预览并恢复列表选中时，需要跳过下一次“选中即自动预览”。
  /// 否则刚刚关闭的预览会因为重新选中同一项而立刻再次弹出。
  private var suppressPreviewAutoOpenOnNextSelection = false

  /// 统一处理列表 hover：
  /// 1. 历史记录项需要额外记录“鼠标最近停留位置”和“当前是否真的还停在这条上”；
  /// 2. 鼠标导航时立即切换选中；
  /// 3. 键盘导航时只暂存，等切回鼠标导航后再应用。
  func handleHoverSelection(_ id: UUID, hovering: Bool) {
    if history.items.contains(where: { $0.id == id }) {
      if hovering {
        lastHoveredHistorySelection = id
        currentHoveredHistorySelection = id

        if !isKeyboardNavigating {
          selectWithoutScrolling(id)
        } else {
          hoverSelectionWhileKeyboardNavigating = id
        }
      } else if currentHoveredHistorySelection == id {
        currentHoveredHistorySelection = nil
      }

      return
    }

    guard footer.items.contains(where: { $0.id == id }) else {
      return
    }

    if hovering {
      /// 鼠标进入 footer 时，说明当前不再是“历史项鼠标选中”语境，
      /// 需要清掉历史 hover 标记，避免影响回车对搜索框的判断。
      currentHoveredHistorySelection = nil

      if !isKeyboardNavigating {
        selectWithoutScrolling(id)
      } else {
        hoverSelectionWhileKeyboardNavigating = id
      }
    }
  }

  /// 供 `HistoryItemDecorator` 在选中切换时查询：
  /// 如果这里返回 `true`，说明这次选中是为了恢复列表位置，不应该自动重新打开预览。
  func consumePreviewAutoOpenSuppression() -> Bool {
    if suppressPreviewAutoOpenOnNextSelection {
      suppressPreviewAutoOpenOnNextSelection = false
      return true
    }

    return false
  }

  /// 只有在鼠标当前明确停在某条历史项上时，才把回车解释成“选择当前历史项”。
  /// 这样搜索框获得焦点时，默认高亮的第一条结果不会被误当成用户真的想选中的项。
  private var hasExplicitMouseHistorySelection: Bool {
    guard !isKeyboardNavigating,
          let selectedItem = history.selectedItem else {
      return false
    }

    return currentHoveredHistorySelection == selectedItem.id
  }

  /// 搜索框获得焦点时，回车是否应该执行“复制并关闭列表”。
  /// - 鼠标当前明确停在某条历史项上：允许回车直接选择这条记录。
  /// - 否则：把回车留给搜索输入本身，不触发列表选择。
  func shouldHandleReturn(searchFocused: Bool) -> Bool {
    guard searchFocused else {
      return true
    }

    return hasExplicitMouseHistorySelection
  }

  /// 鼠标停在图片项上时，空格键作为“预览开关”使用：
  /// - 如果当前图片预览已经打开，不管是不是原图模式，空格都直接关闭预览并恢复列表位置。
  /// - 如果当前没有打开预览，空格会立即打开原图 1:1 预览。
  /// - 非图片项：返回 false，让空格继续走默认输入行为，不干扰搜索框录入空格。
  @discardableResult
  func toggleFullImagePreviewForSelectedItem() -> Bool {
    guard let selectedItem = history.selectedItem,
          selectedItem.item.image != nil else {
      return false
    }

    if selectedItem.showPreview {
      return closePreviewAndRestoreLastHoveredSelection()
    }

    HistoryItemDecorator.previewThrottler.cancel()
    selectedItem.showPreview = true
    return true
  }

  /// 预览打开时，Esc 应优先关闭预览，而不是直接关闭整个窗口。
  /// 如果之前是鼠标 hover 触发的预览，则关闭后恢复到鼠标最近一次停留的历史项。
  @discardableResult
  func closePreviewAndRestoreLastHoveredSelection() -> Bool {
    guard let selectedItem = history.selectedItem,
          selectedItem.showPreview else {
      return false
    }

    HistoryItemDecorator.previewThrottler.cancel()
    selectedItem.showPreview = false

    guard let hoveredSelection = lastHoveredHistorySelection,
          history.items.contains(where: { $0.id == hoveredSelection && $0.isVisible }) else {
      return true
    }

    hoverSelectionWhileKeyboardNavigating = nil
    suppressPreviewAutoOpenOnNextSelection = true
    isKeyboardNavigating = false
    selection = hoveredSelection
    return true
  }

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init() {
    history = History.shared
    footer = Footer()
    popup = Popup()
  }

  @MainActor
  func select() {
    if let item = history.selectedItem, history.items.contains(item) {
      history.select(item)
    } else if let item = footer.selectedItem {
      if item.confirmation != nil {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  private func selectFromKeyboardNavigation(_ id: UUID?) {
    isKeyboardNavigating = true
    selection = id
  }

  func highlightFirst() {
    if let item = history.items.first(where: \.isVisible) {
      selectFromKeyboardNavigation(item.id)
    }
  }

  func highlightPrevious() {
    isKeyboardNavigating = true
    if let selectedItem = history.selectedItem {
      if let nextItem = history.items.filter(\.isVisible).item(before: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      }
    } else if let selectedItem = footer.selectedItem {
      if let nextItem = footer.items.filter(\.isVisible).item(before: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      } else if selectedItem == footer.items.first(where: \.isVisible),
                let nextItem = history.items.last(where: \.isVisible) {
        selectFromKeyboardNavigation(nextItem.id)
      }
    }
  }

  func highlightNext() {
    if let selectedItem = history.selectedItem {
      if let nextItem = history.items.filter(\.isVisible).item(after: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      } else if selectedItem == history.items.filter(\.isVisible).last,
                let nextItem = footer.items.first(where: \.isVisible) {
        selectFromKeyboardNavigation(nextItem.id)
      }
    } else if let selectedItem = footer.selectedItem {
      if let nextItem = footer.items.filter(\.isVisible).item(after: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      }
    } else {
      selectFromKeyboardNavigation(footer.items.first(where: \.isVisible)?.id)
    }
  }

  func highlightLast() {
    if let selectedItem = history.selectedItem {
      if selectedItem == history.items.filter(\.isVisible).last,
         let nextItem = footer.items.first(where: \.isVisible) {
        selectFromKeyboardNavigation(nextItem.id)
      } else {
        selectFromKeyboardNavigation(history.items.last(where: \.isVisible)?.id)
      }
    } else if footer.selectedItem != nil {
      selectFromKeyboardNavigation(footer.items.last(where: \.isVisible)?.id)
    } else {
      selectFromKeyboardNavigation(footer.items.first(where: \.isVisible)?.id)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
            toolbarIcon: NSImage.externaldrive!
          ) {
            StorageSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
            toolbarIcon: NSImage.paintpalette!
          ) {
            AppearanceSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: NSLocalizedString("Title", tableName: "PinsSettings", comment: ""),
            toolbarIcon: NSImage.pincircle!
          ) {
            PinsSettingsPane()
              .environment(self)
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
            toolbarIcon: NSImage.nosign!
          ) {
            IgnoreSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
            toolbarIcon: NSImage.gearshape2!
          ) {
            AdvancedSettingsPane()
          }
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }
}
