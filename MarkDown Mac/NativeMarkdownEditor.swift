import SwiftUI
import AppKit

struct NativeMarkDownEditor: NSViewRepresentable {
    @Binding var text: String
    var onSaveImage: ((NSImage) -> URL?)?
    var isFocusMode: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        // Configure text view
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.textContainer?.lineFragmentPadding = 16
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.allowsUndo = true
        
        // Enable image pasting
        textView.isEditable = true
        textView.importsGraphics = true
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Update text if different
        if textView.string != text {
            textView.string = text
        }
        
        // Update appearance based on focus mode
        let padding: CGFloat = isFocusMode ? 80 : 16
        textView.textContainer?.lineFragmentPadding = padding
        textView.textContainerInset = NSSize(width: padding, height: isFocusMode ? 40 : 16)
        
        // Store context for image handling
        context.coordinator.onSaveImage = onSaveImage
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMarkDownEditor
        var onSaveImage: ((NSImage) -> URL?)?
        
        init(_ parent: NativeMarkDownEditor) {
            self.parent = parent
            self.onSaveImage = parent.onSaveImage
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Update binding
            DispatchQueue.main.async {
                self.parent.text = textView.string
            }
        }
        
        // Handle image pasting
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Check if we're pasting
            if let pasteboard = NSPasteboard.general.pasteboardItems?.first {
                // Check for image
                if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
                   let image = NSImage(data: imageData) {
                    handleImagePaste(image, in: textView, at: affectedCharRange.location)
                    return false
                }
            }
            return true
        }
        
        private func handleImagePaste(_ image: NSImage, in textView: NSTextView, at location: Int) {
            guard let saveImage = onSaveImage else { return }
            
            // Save the image
            if let imageURL = saveImage(image) {
                // Insert markdown image syntax
                let imageName = imageURL.lastPathComponent
                let markdownImage = "![Image](\(imageName))\n"
                
                // Insert at cursor position
                if let textStorage = textView.textStorage {
                    textStorage.beginEditing()
                    textStorage.replaceCharacters(in: NSRange(location: location, length: 0), with: markdownImage)
                    textStorage.endEditing()
                    
                    // Update parent
                    DispatchQueue.main.async {
                        self.parent.text = textView.string
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced Text View with Image Support

class MarkdownTextView: NSTextView {
    var onImagePaste: ((NSImage) -> Void)?
    
    override func paste(_ sender: Any?) {
        // Check for images in pasteboard
        let pasteboard = NSPasteboard.general
        
        if let image = NSImage(pasteboard: pasteboard) {
            onImagePaste?(image)
        } else {
            super.paste(sender)
        }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Accept image drops
        if sender.draggingPasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            return .copy
        }
        return super.draggingEntered(sender)
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Handle image drops
        if let image = NSImage(pasteboard: sender.draggingPasteboard) {
            onImagePaste?(image)
            return true
        }
        return super.performDragOperation(sender)
    }
}
