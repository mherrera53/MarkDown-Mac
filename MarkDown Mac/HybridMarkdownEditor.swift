import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Native Editor Wrapper
struct NativeMarkDownEditor: NSViewRepresentable {
    @Binding var text: String
    var onSaveImage: ((NSImage) -> URL?)?
    var isFocusMode: Bool = false
    var showRawMarkdown: Bool = false // Toggle between WYSIWYG and raw
    var isCanvasMode: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        
        // Custom Text Storage for Markdown Highlighting
        let textStorage = MarkdownTextStorage()
        
        // Set images directory
        if onSaveImage != nil {
            // Get documents directory
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            textStorage.setImagesDirectory(documentsDir.appendingPathComponent("Images"))
        }
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let containerSize = CGSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: containerSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        let textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width, .height]
        textView.isRichText = true // Allow rich text for image rendering
        textView.font = isFocusMode ? NSFont.systemFont(ofSize: 16, weight: .regular) : NSFont.systemFont(ofSize: 14, weight: .regular)
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor.labelColor
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = isFocusMode ? NSSize(width: 40, height: 40) : NSSize(width: 20, height: 20)
        
        // Enable drag and drop for images
        textView.registerForDraggedTypes([.tiff, .png, .fileURL])
        
        scrollView.documentView = textView
        
        // Initial Text Set
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        
        // Store coordinator reference
        context.coordinator.textView = textView
        context.coordinator.textStorage = textStorage
        textView.imageHandler = context.coordinator
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            if textView.string != text {
                let selectedRanges = textView.selectedRanges
                textView.string = text
                textView.selectedRanges = selectedRanges
            }
            
            // Update padding for focus mode
            textView.textContainerInset = isFocusMode ? NSSize(width: 80, height: 40) : NSSize(width: 20, height: 20)
        }
        
        // Update coordinator's save handler
        context.coordinator.onSaveImage = onSaveImage
        
        // Dismiss popover if entering canvas mode
        if isCanvasMode {
            context.coordinator.dismissPopover()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate, ImagePasteHandler {
        var parent: NativeMarkDownEditor
        var onSaveImage: ((NSImage) -> URL?)?
        weak var textView: NSTextView?
        weak var textStorage: MarkdownTextStorage?
        
        // Formatting Popover
        private var popover: NSPopover?
        
        init(_ parent: NativeMarkDownEditor) {
            self.parent = parent
            self.onSaveImage = parent.onSaveImage
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Fix: Check for empty or whitespace-only selection
            let range = textView.selectedRange()
            if range.length > 0,
               let text = textView.string as NSString?,
               range.location + range.length <= text.length {
                
                let selectedString = text.substring(with: range)
                // Filter out just spaces/newlines
                if !selectedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showPopover(for: textView)
                } else {
                    popover?.close()
                }
            } else {
                popover?.close()
            }
        }
        
        func dismissPopover() {
            popover?.close()
        }
        
        private func showPopover(for textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            
            let selectionRectOnScreen = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard let window = textView.window else { return }
            let selectionRectInWindow = window.convertFromScreen(selectionRectOnScreen)
            let localRect = textView.convert(selectionRectInWindow, from: nil)
            
            if popover == nil {
                popover = NSPopover()
                popover?.behavior = .transient
                popover?.animates = true
                let controller = NSHostingController(rootView: FormattingToolbar(actionHandler: { [weak self] action in
                    self?.handleFormatAction(action)
                }))
                 // Force a size for the popover content
                controller.sizingOptions = .preferredContentSize
                popover?.contentViewController = controller
            }
             // Ensure popover content size is calculated
            popover?.contentSize = NSSize(width: 280, height: 44)
            
            popover?.show(relativeTo: localRect, of: textView, preferredEdge: .maxY)
        }
        
        private func handleFormatAction(_ action: FormatAction) {
            guard let textView = textView,
                  let textStorage = textView.textStorage as? MarkdownTextStorage else { return }
            
            let range = textView.selectedRange()
            guard range.length > 0 else { return }
            
            let fullText = textView.string as NSString
            let selectedText = fullText.substring(with: range)
            
            // Helper: Check if font at location has trait
            func hasTrait(_ trait: NSFontDescriptor.SymbolicTraits, at location: Int) -> Bool {
                guard location < fullText.length else { return false }
                if let font = textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont {
                    return font.fontDescriptor.symbolicTraits.contains(trait)
                }
                return false
            }
            
            switch action {
            case .bold:
                if hasTrait(.bold, at: range.location) {
                    // Start untoggling: Search outwards for **
                    // Expand search range slightly to be safe
                    let searchRange = NSRange(location: max(0, range.location - 20), length: min(fullText.length - (range.location - 20), range.length + 40))
                    
                    if let regex = try? NSRegularExpression(pattern: "\\*\\*.+?\\*\\*") {
                        let matches = regex.matches(in: fullText as String, options: [], range: searchRange)
                        // Find match containing our selection
                        if let match = matches.first(where: { NSIntersectionRange($0.range, range).length > 0 }) {
                             // Remove the stars
                            let newText = (fullText.substring(with: match.range) as NSString).replacingOccurrences(of: "**", with: "")
                            textStorage.replaceCharacters(in: match.range, with: newText)
                            self.parent.text = textView.string
                            return
                        }
                    }
                }
                // Fallback / Apply
                textStorage.replaceCharacters(in: range, with: "**\(selectedText)**")
                
            case .italic:
                if hasTrait(.italic, at: range.location) {
                     // Start untoggling: Search outwards for *
                    let searchRange = NSRange(location: max(0, range.location - 20), length: min(fullText.length - (range.location - 20), range.length + 40))
                    
                    if let regex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*).+?(?<!\\*)\\*(?!\\*)") {
                        let matches = regex.matches(in: fullText as String, options: [], range: searchRange)
                        if let match = matches.first(where: { NSIntersectionRange($0.range, range).length > 0 }) {
                             // Remove the stars
                            let newText = (fullText.substring(with: match.range) as NSString).replacingOccurrences(of: "*", with: "")
                            textStorage.replaceCharacters(in: match.range, with: newText)
                            self.parent.text = textView.string
                            return
                        }
                    }
                }
                // Fallback
                textStorage.replaceCharacters(in: range, with: "*\(selectedText)*")
                
            case .heading1, .heading2:
                // For headers, operate on the full Paragraph
                let lineRange = fullText.paragraphRange(for: range)
                let lineText = fullText.substring(with: lineRange)
                var newLineText = lineText
                
                // Clear existing headers
                if newLineText.hasPrefix("# ") { newLineText = String(newLineText.dropFirst(2)) }
                else if newLineText.hasPrefix("## ") { newLineText = String(newLineText.dropFirst(3)) }
                else if newLineText.hasPrefix("### ") { newLineText = String(newLineText.dropFirst(4)) }
                
                // Apply new header if it wasn't already that specific header (Toggle effect)
                if action == .heading1 && !lineText.hasPrefix("# ") {
                    newLineText = "# " + newLineText
                } else if action == .heading2 && !lineText.hasPrefix("## ") {
                    newLineText = "## " + newLineText
                }
                
                textStorage.replaceCharacters(in: lineRange, with: newLineText)
                
            case .link:
                 textStorage.replaceCharacters(in: range, with: "[\(selectedText)](url)")
                 
            case .code:
                 textStorage.replaceCharacters(in: range, with: "`\(selectedText)`")
            }
            
            // Final Sync
            self.parent.text = textView.string
        }
        
        // Handle image insertion
        func handleImagePaste(_ image: NSImage) {
            guard let textView = textView,
                  let saveImage = onSaveImage,
                  let imageURL = saveImage(image) else { return }
            
            let imageName = imageURL.lastPathComponent
            let markdownImage = "\n![Image](\(imageName))\n"
            
            // Insert at cursor position
            let selectedRange = textView.selectedRange()
            if let textStorage = textView.textStorage {
                textStorage.replaceCharacters(in: selectedRange, with: markdownImage)
                
                // Move cursor after inserted text
                let newLocation = selectedRange.location + (markdownImage as NSString).length
                textView.setSelectedRange(NSRange(location: newLocation, length: 0))
                
                // Update parent
                DispatchQueue.main.async {
                    self.parent.text = textView.string
                }
            }
        }
    }
}


// MARK: - Markdown Syntax Highlighting Engine with WYSIWYG Rendering
class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private var imagesDirectory: URL?
    var showRawMarkdown: Bool = false // Control WYSIWYG vs Raw mode
    
    override var string: String {
        return backingStore.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        return backingStore.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    override func processEditing() {
        performReplacementsForRange(range: (string as NSString).paragraphRange(for: editedRange))
        super.processEditing()
    }
    
    func setImagesDirectory(_ directory: URL) {
        imagesDirectory = directory
    }
    
    // Core WYSIWYG Rendering Logic
    private func performReplacementsForRange(range: NSRange) {
        // Base attributes
        let baseFont = NSFont.systemFont(ofSize: 14, weight: .regular)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]
        
        backingStore.setAttributes(baseAttributes, range: range)
        
        // If raw mode, just apply syntax highlighting without hiding markers
        if showRawMarkdown {
            applyRawSyntaxHighlighting(in: range)
            return
        }
        
        let fullString = string as NSString
        
        // WYSIWYG Mode - Hide markers and render
        // 1. Headers
        renderHeaders(in: range, fullString: fullString)
        
        // 2. Lists (unordered)
        renderUnorderedLists(in: range, fullString: fullString)
        
        // 3. Lists (ordered)
        renderOrderedLists(in: range, fullString: fullString)
        
        // 4. Checklists/Tasks
        renderChecklists(in: range, fullString: fullString)
        
        // 5. Blockquotes
        renderBlockquotes(in: range, fullString: fullString)
        
        // 6. Bold
        renderBold(in: range, fullString: fullString)
        
        // 7. Italic
        renderItalic(in: range, fullString: fullString)
        
        // 8. Strikethrough
        renderStrikethrough(in: range, fullString: fullString)
        
        // 9. Inline Code
        renderInlineCode(in: range, fullString: fullString)
        
        // 10. Links
        renderLinks(in: range, fullString: fullString)
        
        // 11. Horizontal rules
        renderHorizontalRules(in: range, fullString: fullString)
        
        // 12. Images
        renderImages(in: range, fullString: fullString)

        // 5. Blockquotes
        renderBlockquotes(in: range, fullString: fullString)
    }
    
    private func applyRawSyntaxHighlighting(in range: NSRange) {
        _ = string as NSString
        
        // Just colorize syntax without hiding
        // Headers
        let headerPattern = "^(#{1,6})\\s+"
        processPattern(headerPattern, range: range) { match, _ in
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
        }
        
        // Bold/Italic markers
        let boldPattern = "(\\*\\*|__)"
        processPattern(boldPattern, range: range) { match, _ in
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.systemRed, range: match.range)
        }
        
        // Links
        let linkPattern = "\\[([^\\]]*)\\]\\(([^\\)]*)\\)"
        processPattern(linkPattern, range: range) { match, _ in
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
        }
    }
    
        private func renderImages(in range: NSRange, fullString: NSString) {
            let imagePattern = "!\\[([^\\]]*)\\]\\(([^\\)]*)\\)"
            var matches: [(NSRange, String)] = []
            
            // 1. Collect all matches first
            processPattern(imagePattern, range: range) { match, _ in
                guard match.numberOfRanges >= 3 else { return }
                
                let fullRange = match.range
                let imagePathRange = match.range(at: 2)
                let imagePath = fullString.substring(with: imagePathRange)
                
                matches.append((fullRange, imagePath))
            }
            
            // 2. Apply in reverse order to preserve indices
            for (fullRange, imagePath) in matches.reversed() {
                // Try to load the image
                if let imagesDir = self.imagesDirectory {
                    // Check for both encoded (URL) and decoded path
                    let imageURL = imagesDir.appendingPathComponent(imagePath)
                    
                    if let image = NSImage(contentsOf: imageURL) {
                        // Resize image to fit width (Logic simplified for performance)
                        // Using a max width of 550 for editor comfort
                        let maxWidth: CGFloat = 550
                        var newSize = image.size
                        if image.size.width > maxWidth {
                            let ratio = maxWidth / image.size.width
                            newSize = NSSize(width: maxWidth, height: image.size.height * ratio)
                        }
                        
                        let resizedImage = NSImage(size: newSize)
                        resizedImage.lockFocus()
                        image.draw(in: NSRect(origin: .zero, size: newSize))
                        resizedImage.unlockFocus()
                        
                        // Create text attachment
                        let attachment = NSTextAttachment()
                        attachment.image = resizedImage
                        attachment.bounds = NSRect(origin: .zero, size: newSize)
                        
                        // Replace the markdown syntax with the image
                        let attachmentString = NSAttributedString(attachment: attachment)
                        
                        // Ensure we are replacing the range in the CURRENT backing store
                        // Since we iterate reversed, fullRange should still be valid relative to start
                        if fullRange.location + fullRange.length <= self.backingStore.length {
                            self.backingStore.replaceCharacters(in: fullRange, with: attachmentString)
                        }
                    }
                }
            }
        }
    
    private func renderBlockquotes(in range: NSRange, fullString: NSString) {
        let quotePattern = "^> (.*)$"
        processPattern(quotePattern, range: range) { match, _ in
            guard match.numberOfRanges >= 2 else { return }
            
            let fullRange = match.range
            let textRange = match.range(at: 1)
            let arrowRange = NSRange(location: fullRange.location, length: 2) // "> "
            
            // Hide the arrow
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: arrowRange)
            // self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: arrowRange) // Keep visible but dim? Or hide? Standard MD hides.
            
            // Style the text
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: textRange)
            
            // Italic
            if let currentFont = self.backingStore.attribute(.font, at: textRange.location, effectiveRange: nil) as? NSFont {
                 let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                 self.backingStore.addAttribute(.font, value: italicFont, range: textRange)
            }
            
            // Paragraph Indent
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 20
            paragraphStyle.firstLineHeadIndent = 20
            self.backingStore.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        }
    }
    
    private func renderHeaders(in range: NSRange, fullString: NSString) {
        let headerPattern = "^(#{1,6})\\s+(.+)$"
        processPattern(headerPattern, range: range) { match, _ in
            guard match.numberOfRanges >= 3 else { return }
            
            _ = match.range // Full range not needed
            let hashRange = match.range(at: 1)
            let textRange = match.range(at: 2)
            
            let level = hashRange.length
            
            // Font sizes like Minimal.app - clean and proportional
            let fontSize: CGFloat = [32, 28, 24, 20, 18, 16][min(level - 1, 5)]
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            
            // Hide the # symbols by making them tiny and same color as background
            self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: hashRange)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: hashRange)
            
            // Style the header text - BLACK like Minimal.app, not blue
            self.backingStore.addAttribute(.font, value: font, range: textRange)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.labelColor, range: textRange)
            
            // Add subtle underline for H1 and H2 (like Minimal.app)
            if level <= 2 {
                // Add some space after the text for the line
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.paragraphSpacing = 8
                self.backingStore.addAttribute(.paragraphStyle, value: paragraphStyle, range: textRange)
                
                // Add a subtle border bottom effect by using underline
                self.backingStore.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                self.backingStore.addAttribute(.underlineColor, value: NSColor.separatorColor, range: textRange)
            }
        }
    }
    
    private func renderBold(in range: NSRange, fullString: NSString) {
        let boldPattern = "\\*\\*(.+?)\\*\\*"
        processPattern(boldPattern, range: range) { match, _ in
            guard match.numberOfRanges >= 2 else { return }
            
            let fullRange = match.range
            
            if let currentFont = self.backingStore.attribute(.font, at: fullRange.location, effectiveRange: nil) as? NSFont {
                let boldFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                self.backingStore.addAttribute(.font, value: boldFont, range: fullRange)
                
                // Hide the ** markers
                let startMarker = NSRange(location: fullRange.location, length: 2)
                let endMarker = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
                
                self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: startMarker)
                self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: endMarker)
                self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: startMarker)
                self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: endMarker)
            }
        }
    }
    
    private func renderItalic(in range: NSRange, fullString: NSString) {
        let italicPattern = "(?<!\\*)\\*(?!\\*)(.+?)\\*(?!\\*)"
        processPattern(italicPattern, range: range) { match, _ in
            guard match.numberOfRanges >= 2 else { return }
            
            let fullRange = match.range
            
            if let currentFont = self.backingStore.attribute(.font, at: fullRange.location, effectiveRange: nil) as? NSFont {
                let italicFont = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                self.backingStore.addAttribute(.font, value: italicFont, range: fullRange)
                
                // Hide the * markers
                let startMarker = NSRange(location: fullRange.location, length: 1)
                let endMarker = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
                
                self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: startMarker)
                self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: endMarker)
                self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: startMarker)
                self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: endMarker)
            }
        }
    }
    
    private func renderInlineCode(in range: NSRange, fullString: NSString) {
        let codePattern = "`([^`]+)`"
        processPattern(codePattern, range: range) { match, _ in
            let fullRange = match.range
            
            let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            self.backingStore.addAttribute(.font, value: codeFont, range: fullRange)
            self.backingStore.addAttribute(.backgroundColor, value: NSColor.systemGray.withAlphaComponent(0.2), range: fullRange)
            
            // Hide the ` markers
            let startMarker = NSRange(location: fullRange.location, length: 1)
            let endMarker = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            
            self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: startMarker)
            self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: endMarker)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: startMarker)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: endMarker)
        }
    }
    
    private func renderLinks(in range: NSRange, fullString: NSString) {
        let linkPattern = "\\[([^\\]]*)\\]\\(([^\\)]*)\\)"
        processPattern(linkPattern, range: range) { match, _ in
            guard match.numberOfRanges >= 3 else { return }
            
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            
            // Style link text - subtle blue like Minimal.app
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            self.backingStore.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            self.backingStore.addAttribute(.underlineColor, value: NSColor.linkColor.withAlphaComponent(0.5), range: textRange)
            
            // Make it clickable
            if let url = URL(string: fullString.substring(with: urlRange)) {
                self.backingStore.addAttribute(.link, value: url, range: textRange)
            }
            
            // Hide the markdown syntax
            let bracketsAndParens = [
                NSRange(location: match.range.location, length: 1), // [
                NSRange(location: textRange.location + textRange.length, length: 2), // ](
                NSRange(location: urlRange.location + urlRange.length, length: 1) // )
            ]
            
            for markerRange in bracketsAndParens {
                self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: markerRange)
                self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: markerRange)
            }
            
            // Hide URL
            self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: urlRange)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.textBackgroundColor, range: urlRange)
        }
    }
                  
    private func renderUnorderedLists(in range: NSRange, fullString: NSString) {
        let pattern = "^(\\s*)([-*+])\\s+(.+)$"
        processPattern(pattern, range: range) { match, _ in
            guard match.numberOfRanges >= 4 else { return }
            
            let fullRange = match.range
            let indentRange = match.range(at: 1)
            let bulletRange = match.range(at: 2)
            
            // Indent based on depth (spaces)
            let paragraphStyle = NSMutableParagraphStyle()
            let indentLength = indentRange.length
            let depth = indentLength / 2
            paragraphStyle.headIndent = CGFloat(20 + (depth * 20))
            paragraphStyle.firstLineHeadIndent = CGFloat(depth * 20)
            
            self.backingStore.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            
            // Color bullet
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: bulletRange)
            self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .bold), range: bulletRange)
        }
    }
    
    private func renderOrderedLists(in range: NSRange, fullString: NSString) {
        let pattern = "^(\\s*)(\\d+\\.)\\s+(.+)$"
        processPattern(pattern, range: range) { match, _ in
            guard match.numberOfRanges >= 4 else { return }
            
            let fullRange = match.range
            let indentRange = match.range(at: 1)
            let numberRange = match.range(at: 2)
            
            let paragraphStyle = NSMutableParagraphStyle()
            let indentLength = indentRange.length
            let depth = indentLength / 2
            paragraphStyle.headIndent = CGFloat(20 + (depth * 20))
            paragraphStyle.firstLineHeadIndent = CGFloat(depth * 20)
            
            self.backingStore.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: numberRange)
        }
    }
    
    private func renderChecklists(in range: NSRange, fullString: NSString) {
        let pattern = "^(\\s*)- \\[( |x|X)\\] (.*)$"
        processPattern(pattern, range: range) { match, _ in
            guard match.numberOfRanges >= 4 else { return }
            
            let checkRange = NSRange(location: match.range.location + match.range(at: 1).length, length: 5) // "- [x]"
            let stateRange = match.range(at: 2) // " " or "x"
            let textRange = match.range(at: 3)
            
            let isChecked = fullString.substring(with: stateRange).lowercased() == "x"
            
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: checkRange)
            
            if isChecked {
                self.backingStore.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                self.backingStore.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: textRange)
            }
        }
    }
    
    private func renderStrikethrough(in range: NSRange, fullString: NSString) {
        let pattern = "~~(.*?)~~"
        processPattern(pattern, range: range) { match, _ in
            guard match.numberOfRanges >= 2 else { return }
            let fullRange = match.range
            let textRange = match.range(at: 1)
            
            self.backingStore.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: textRange)
            
            // Hide tildes
            let startTilde = NSRange(location: fullRange.location, length: 2)
            let endTilde = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.clear, range: startTilde)
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.clear, range: endTilde)
            self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: startTilde)
            self.backingStore.addAttribute(.font, value: NSFont.systemFont(ofSize: 1), range: endTilde)
        }
    }
    
    private func renderHorizontalRules(in range: NSRange, fullString: NSString) {
        let pattern = "^(---|_{3,}|\\*{3,})$"
        processPattern(pattern, range: range) { match, _ in
            let fullRange = match.range
            self.backingStore.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: fullRange)
            self.backingStore.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.thick.rawValue, range: fullRange)
        }
    }

    private func processPattern(_ pattern: String, range: NSRange, handler: (NSTextCheckingResult, NSRegularExpression.MatchingFlags) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        
        regex.enumerateMatches(in: string, options: [], range: range) { match, flags, stop in
            if let match = match {
                handler(match, flags)
            }
        }
    }
}

// MARK: - Image Paste Handler Protocol
protocol ImagePasteHandler: AnyObject {
    func handleImagePaste(_ image: NSImage)
}

// MARK: - Custom TextView with Image Support
class MarkdownTextView: NSTextView {
    weak var imageHandler: ImagePasteHandler?
    
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        
        // 1. Handle explicit image data (Copied from Preview/Browser)
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            imageHandler?.handleImagePaste(image)
            return
        }
        
        // 2. Handle File URLs (Copied from Finder)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in fileURLs {
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "bmp"]
                if imageExtensions.contains(url.pathExtension.lowercased()),
                   let image = NSImage(contentsOf: url) {
                    imageHandler?.handleImagePaste(image)
                    return // Only paste first image for now
                }
            }
        }
        
        super.paste(sender)
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        
        // Accept images
        if pasteboard.availableType(from: [.tiff, .png]) != nil {
            return .copy
        }
        
        // Accept file URLs (for image files)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in fileURLs {
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "bmp"]
                if imageExtensions.contains(url.pathExtension.lowercased()) {
                    return .copy
                }
            }
        }
        
        return super.draggingEntered(sender)
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        
        // Handle image data
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            imageHandler?.handleImagePaste(image)
            return true
        }
        
        // Handle file URLs
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in fileURLs {
                let imageExtensions = ["png", "jpg", "jpeg", "gif", "tiff", "bmp"]
                if imageExtensions.contains(url.pathExtension.lowercased()),
                   let image = NSImage(contentsOf: url) {
                    imageHandler?.handleImagePaste(image)
                    return true
                }
            }
        }
        
        return super.performDragOperation(sender)
    }
}



// MARK: - Floating Toolbar UI
enum FormatAction {
    case bold, italic, heading1, heading2, link, code
}

struct FormattingToolbar: View {
    var actionHandler: (FormatAction) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: { actionHandler(.bold) }) {
                Image(systemName: "bold")
            }
            Button(action: { actionHandler(.italic) }) {
                 Image(systemName: "italic")
            }
            Divider().frame(height: 16)
            Button(action: { actionHandler(.heading1) }) {
                 Text("H1").fontWeight(.bold)
            }
            Button(action: { actionHandler(.heading2) }) {
                 Text("H2").fontWeight(.bold)
            }
            Divider().frame(height: 16)
            Button(action: { actionHandler(.link) }) {
                 Image(systemName: "link")
            }
            Button(action: { actionHandler(.code) }) {
                 Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
        }
        .padding(8)
        .buttonStyle(.borderless) // Clean look
        .background(VisualEffectView(material: .popover, blendingMode: .withinWindow))
        .cornerRadius(8)
        .frame(minWidth: 200, minHeight: 40) // Hint for size
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
