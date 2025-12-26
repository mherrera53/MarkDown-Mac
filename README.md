# MarkDown Mac

A powerful, native Markdown editor for macOS with integrated drawing capabilities. Built with SwiftUI, CodeMirror, and PencilKit.

## Overview

MarkDown Mac combines the power of a WYSIWYG Markdown editor with professional drawing tools, offering a unique note-taking experience similar to apps like Minimal.app but with additional features.

## Features

### Markdown Editor
- **WYSIWYG Editing**: Headers, bold, and italic text are styled in-place for a rich editing experience
- **Syntax Highlighting**: Code blocks with syntax highlighting support
- **Live Preview**: Real-time Markdown preview
- **Image Support**:
  - Drag & drop images directly into the editor
  - Paste images from clipboard
  - Automatic Base64 to file conversion
- **Mermaid Diagrams**: Support for flowcharts, sequence diagrams, and more
- **Export to PDF**: Save your notes as PDF documents

### Drawing Tools
Powered by PencilKit, the app includes professional drawing capabilities:

#### Basic Tools
- **Pen**: Fine, precise strokes
- **Pencil**: Smooth strokes with texture
- **Marker**: Thick, translucent strokes
- **Eraser**: Precise vector erasing
- **Lasso**: Select, move, and transform drawings
- **Ruler**: Straight line assistance mode

#### Shape Tools
Draw perfect geometric shapes:
- Rectangle
- Circle/Ellipse
- Triangle
- Arrow
- Line
- Star

All shapes support:
- Real-time preview while dragging
- Automatic conversion to PencilKit strokes
- Customizable color and stroke width
- Full undo/redo support

### Additional Features
- **Native macOS UI**: Sidebar, Toolbar, and Search using native controls
- **Undo/Redo**: Full support with keyboard shortcuts (⌘Z / ⌘⇧Z)
- **Color Picker**: Visual color selection for drawing tools
- **Stroke Width Control**: Adjustable line thickness with visual feedback
- **Note Management**: Organize your notes in the Documents folder
- **Tooltips**: Contextual help for all tools

## Requirements

- macOS 10.15 (Catalina) or later
- Xcode 12.0 or later (for building from source)

## Installation

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/mherrera53/MarkDown-Mac.git
cd MarkDown-Mac
```

2. Open the project in Xcode:
```bash
open "MarkDown Mac.xcodeproj"
```

3. Select the `MarkDown Mac` scheme

4. Build and run (⌘R)

## Usage

### Editing Markdown
1. Create a new note or select an existing one from the sidebar
2. Type your Markdown content in the editor
3. Use the toolbar for formatting options
4. Preview updates in real-time

### Drawing on Canvas
1. Click the **Draw** button to activate drawing mode
2. Select a drawing tool from the toolbar
3. Choose a color and stroke width
4. Draw directly on the canvas

#### Using Shapes
1. Click the shapes button (⬜ icon) in the toolbar
2. Select a shape from the dropdown menu
3. Drag on the canvas to draw the shape
4. Release to convert to a PencilKit stroke

#### Using Lasso Tool
1. Select the Lasso tool
2. Draw a circle around strokes to select them
3. Drag to move the selection
4. Pinch to scale (with trackpad)

#### Using Ruler
1. Select the Ruler tool
2. Draw lines - they will automatically straighten

## Project Structure

```
MarkDown Mac/
├── ContentView.swift              # Main UI (Sidebar, Toolbar, Editor)
├── HybridMarkdownEditor.swift     # Bridge between Swift and Web Editor
├── NativeMarkdownEditor.swift     # Native Markdown editing components
├── PaperMarkupView.swift         # PencilKit canvas wrapper
├── ShapeToolView.swift           # Geometric shapes implementation
├── NoteManager.swift             # File saving/loading logic
├── MarkdownPreviewView.swift     # Markdown preview renderer
├── MermaidRenderer.swift         # Mermaid diagram support
├── WebResources/
│   ├── index.html                # WebView HTML template
│   ├── app.js                    # CodeMirror and Markdown-it logic
│   ├── style.css                 # Editor styles
│   └── lib/                      # JavaScript libraries
│       ├── codemirror/           # CodeMirror editor
│       ├── markdown-it/          # Markdown parser
│       ├── highlight/            # Syntax highlighting
│       └── mermaid/              # Diagram rendering
```

## Technical Details

- **UI Framework**: SwiftUI
- **Editor**: CodeMirror 5
- **Markdown Parser**: markdown-it with plugins (emoji, footnotes, sub/sup)
- **Drawing Framework**: PencilKit
- **Syntax Highlighting**: highlight.js
- **Diagrams**: Mermaid.js
- **Web Bridge**: WKWebView

## Troubleshooting

### Common Console Messages

When running from Xcode, you may see system logs. **These are normal and can be safely ignored**:

- `AFIsDeviceGreymatterEligible ...`: macOS Sequoia's Apple Intelligence checks
- `Unable to create bundle at URL ((null))`: Harmless WebKit debug warning
- `IconRendering ... invalid format`: Internal macOS rendering log

**As long as the app launches and you can type/draw, everything is working correctly.**

### Build Issues

If you encounter build errors:
1. Clean the build folder (⌘⇧K)
2. Ensure you're running Xcode 12.0 or later
3. Verify macOS target is set to 10.15 or later
4. Check that all WebResources files are included in the bundle

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## Support the Project

If you find MarkDown Mac useful, consider supporting its development:

[![PayPal](https://img.shields.io/badge/PayPal-Donate-blue.svg?logo=paypal)](https://paypal.me/mario53128@live.com)

**PayPal**: mario53128@live.com

Your support helps maintain and improve MarkDown Mac!

---

## License

This project is available under the MIT License. See LICENSE file for details.

## Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Editor powered by [CodeMirror](https://codemirror.net/)
- Markdown parsing by [markdown-it](https://github.com/markdown-it/markdown-it)
- Diagrams by [Mermaid](https://mermaid-js.github.io/)
- Drawing capabilities by [PencilKit](https://developer.apple.com/documentation/pencilkit)

## Roadmap

Future enhancements under consideration:
- Text annotation tool for canvas
- Note templates library
- iCloud synchronization
- Additional export formats (HTML, DOCX, images)
- Custom themes
- Real-time collaboration

---

**Made with ❤️ for the macOS community**
