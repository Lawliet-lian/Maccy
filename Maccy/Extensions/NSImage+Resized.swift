import AppKit.NSImage

// Based on https://stackoverflow.com/questions/73062803/resizing-nsimage-keeping-aspect-ratio-reducing-the-image-size-while-trying-to-sc.
extension NSImage {
  func resized(to newSize: NSSize) -> NSImage {
    guard size.width > 0, size.height > 0 else { return self }
    let newSize = size.fitted(within: newSize)
    if newSize == size {
      return self
    }

    return NSImage(size: newSize, flipped: false) { destRect in
      if let context = NSGraphicsContext.current {
        context.imageInterpolation = .high
        self.draw(in: destRect, from: NSRect.zero, operation: .copy, fraction: 1)
      }

      return true
    }
  }
}

extension NSSize {
  func fitted(within bounds: NSSize) -> NSSize {
    let scale = min(1, bounds.width / width, bounds.height / height)
    return NSSize(width: width * scale, height: height * scale)
  }
}
