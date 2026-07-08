import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  var item: HistoryItemDecorator

  @Environment(AppState.self) private var appState

  /// 原图预览需要尽量保持 1:1 像素显示，但弹出的 popover 仍然不能无限大，
  /// 否则超大截图会直接冲出屏幕。
  /// 这里把可视区域限制在当前弹窗所在屏幕的可见区域内，
  /// 超出的部分交给双向滚动视图处理，这样既能看细节，也不会撑坏布局。
  private var originalImageViewportSize: CGSize {
    guard let image = item.item.image else {
      return .zero
    }

    let availableSize = HistoryItemDecorator.previewImageSize
    return CGSize(
      width: min(image.size.width, availableSize.width),
      height: min(image.size.height, availableSize.height)
    )
  }

  private var isShowingFullImagePreview: Bool {
    appState.isShowingFullImagePreview(for: item)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let image = item.item.image, isShowingFullImagePreview {
        ScrollView([.horizontal, .vertical]) {
          Image(nsImage: image)
            .frame(
              width: image.size.width,
              height: image.size.height,
              alignment: .topLeading
            )
        }
        .frame(
          width: originalImageViewportSize.width,
          height: originalImageViewportSize.height,
          alignment: .topLeading
        )
        .clipShape(.rect(cornerRadius: 5))
      } else if let image = item.previewImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .clipShape(.rect(cornerRadius: 5))
      } else {
        ScrollView {
          WrappingTextView {
            Text(item.text)
              .font(.body)
          }
        }
      }

      Divider()
        .padding(.vertical)

      if let application = item.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "PreviewItemView")
          Image(nsImage: item.applicationImage.nsImage)
            .resizable()
            .frame(width: 11, height: 11)
          Text(application)
        }
      }

      HStack(spacing: 3) {
        Text("FirstCopyTime", tableName: "PreviewItemView")
        Text(item.item.firstCopiedAt, style: .date)
        Text(item.item.firstCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("LastCopyTime", tableName: "PreviewItemView")
        Text(item.item.lastCopiedAt, style: .date)
        Text(item.item.lastCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("NumberOfCopies", tableName: "PreviewItemView")
        Text(String(item.item.numberOfCopies))
      }
      .padding(.bottom)

      if let pinKey = KeyboardShortcuts.Shortcut(name: .pin) {
        Text(
          NSLocalizedString("PinKey", tableName: "PreviewItemView", comment: "")
            .replacingOccurrences(of: "{pinKey}", with: pinKey.description)
        )
      }

      if let deleteKey = KeyboardShortcuts.Shortcut(name: .delete) {
        Text(
          NSLocalizedString("DeleteKey", tableName: "PreviewItemView", comment: "")
            .replacingOccurrences(of: "{deleteKey}", with: deleteKey.description)
        )
      }
    }
    .controlSize(.small)
    .padding()
  }
}
