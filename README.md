# MarkDown Mac

A native, minimalist Markdown editor for macOS built with SwiftUI and CodeMirror.

## Features
- **Visual "Rich" Editor**: Headers, bold, and italic text are styled in-place (WYSIWYG feel).
- **Native UI**: Native Sidebar, Toolbar, and Search.
- **Image Support**: Paste images or drag files directly. Base64 strings are auto-converted to files.
- **Mermaid Diagrams**: Support for flowcharts and graphs.

## Running the App
1. Open `MarkDown Mac.xcodeproj` in Xcode.
2. Select the `MarkDown Mac` scheme.
3. Press **Run** (Cmd+R).

## Troubleshooting Logs
When running from Xcode, you may see system logs in the console. **These are normal and safely ignored**:

- `AFIsDeviceGreymatterEligible ...`: Related to macOS Sequoia's Apple Intelligence (Siri) checks.
- `Unable to create bundle at URL ((null))`: A harmless warning during WebKit initialization in debug mode.
- `IconRendering ... invalid format`: Internal macOS rendering log.

As long as the app launches and you can type, **the app is working correctly**.

## Project Structure
- `ContentView.swift`: Main UI (Sidebar, Toolbar, Editor container).
- `HybridMarkdownEditor.swift`: The bridge between Swift and the Web Editor.
- `WebResources/app.js`: The Editor logic (CodeMirror, Markdown-it, Mermaid).
- `NoteManager.swift`: Handles file saving/loading in your Documents folder.
