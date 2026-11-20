import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator

  @Environment(AppState.self) private var appState
  @Default(.imageMaxHeight) private var imageMaxHeight

  var body: some View {
    ListItemView(
      id: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage ?? ColorImage.from(item.title),
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected
    ) {
      Text(verbatim: item.title)
    }
    .onTapGesture {
      appState.history.select(item)
    }
    .task(id: imageMaxHeight) {
      let previousSize = item.thumbnailImage?.size
      item.loadThumbnail()
      if previousSize != item.thumbnailImage?.size {
        appState.popup.needsResize = true
      }
    }
    .popover(isPresented: $item.showPreview, arrowEdge: .trailing) {
      PreviewItemView(item: item)
    }
  }
}
