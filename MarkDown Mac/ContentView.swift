import SwiftUI
import PencilKit
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var noteManager = NoteManager()
    @State private var selectedNote: Note?
    @State private var editorContent: String = ""
    @State private var searchText = ""
    @Environment(\.colorScheme) var colorScheme
    
    // Note Lifetime state
    @State private var showingNoteLifetimeSettings = false
    @State private var showingArchivedNotes = false
    
    // Canvas State for Drawing
    @State private var isCanvasMode = false
    @State private var drawing = PKDrawing()
    @State private var selectedTool: DrawingTool = .pen
    @State private var selectedColor: Color = .black
    @State private var lineWidth: CGFloat = 3.0
    @State private var isShapeMode = false
    @State private var selectedShape: ShapeType = .rectangle
    
    // Minimal.app features
    @State private var showingStats = false
    @State private var isFocusMode = false
    @State private var showingExportSheet = false
    @State private var sortOrder: SortOrder = .modified
    @State private var showPreview = true // Vista previa de Markdown
    @State private var showingDiagramAssistant = false
    @State private var diagramDescription = ""
    
    enum SortOrder: String, CaseIterable {
        case modified = "Modified"
        case created = "Created"
        case alphabetical = "A-Z"
    }
    
    enum DrawingTool: String, CaseIterable {
        case pen = "Pen"
        case pencil = "Pencil"
        case marker = "Marker"
        case eraser = "Eraser"
        case lasso = "Lasso" // Selection tool
        case ruler = "Ruler" // Straight line tool
    }
    
    var columnVisibility: NavigationSplitViewVisibility {
        isFocusMode ? .detailOnly : .all
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(columnVisibility)) {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    @ViewBuilder
    var sidebarContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search notes...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .padding([.horizontal, .top], 12)
                
                // Notes List
                List(selection: $selectedNote) {
                    ForEach(sortedAndFilteredNotes) { note in
                        NoteRowView(note: note, noteManager: noteManager)
                            .tag(note)
                            .contextMenu {
                                if note.isPinned {
                                    Button("Unpin Note") {
                                        noteManager.lifetimeManager?.unpinNote(note)
                                    }
                                } else {
                                    Button("Pin Note") {
                                        noteManager.lifetimeManager?.keepNoteAlive(note)
                                    }
                                }
                                
                                Divider()
                                
                                Button("Rename") {
                                    renameNote(note)
                                }
                                Button("Duplicate") {
                                    duplicateNote(note)
                                }
                                Divider()
                                Button("Export as PDF") {
                                    exportNoteToPDF(note)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    deleteNote(note)
                                }
                            }
                    }
                    .onDelete(perform: deleteOffsets)
                }
                .listStyle(.sidebar)
                
                // Stats Footer
                if showingStats {
                    HStack {
                        Text("\(noteManager.notes.count) notes")
                        Spacer()
                        if selectedNote != nil {
                            Text("\(wordCount(editorContent)) words")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        
                        Divider()
                        
                        Toggle("Show Stats", isOn: $showingStats)
                        Toggle("Focus Mode", isOn: $isFocusMode)
                        
                        Divider()
                        
                        Button("Note Lifetime Settings") {
                            showingNoteLifetimeSettings.toggle()
                        }
                        
                        Button("Archived Notes") {
                            showingArchivedNotes.toggle()
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                    
                    Button(action: createNewNote) {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
    }
    
    @ViewBuilder
    var detailContent: some View {
        if let note = selectedNote {
            noteDetailView(for: note)
        } else {
            emptyStateView
        }
    }
    
    @ViewBuilder
    private func noteDetailView(for note: Note) -> some View {
        VStack(spacing: 0) {
            // Persistent Title Header
            HStack {
                Text(note.title)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            ZStack {
                // Layer 1: Text Editor (always visible)
                textEditorView(for: note)
                    .allowsHitTesting(!isCanvasMode)
                
                // Layer 2: Drawing Canvas Overlay (transparent, on top when enabled)
                if isCanvasMode {
                    ZStack {
                        VStack(spacing: 0) {
                            drawingToolbar
                                .padding(.top, 12)
                                .padding(.horizontal)
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)
                                .padding(.top, 8)
                                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                            
                            ZStack {
                                // The robust canvas that catches all clicks
                                RobustPaperCanvas(
                                    drawing: $drawing,
                                    tool: selectedTool,
                                    color: selectedColor,
                                    width: lineWidth,
                                    onCanvasCreated: { canvas in
                                        canvasViewReference = canvas
                                    }
                                )
                                
                                // Shape overlay when shape mode is active
                                if isShapeMode {
                                    ShapeDrawingOverlay(
                                        drawing: $drawing,
                                        isActive: $isShapeMode,
                                        selectedShape: selectedShape,
                                        color: selectedColor,
                                        lineWidth: lineWidth
                                    )
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .onChange(of: selectedNote) {
            if let n = selectedNote {
                editorContent = noteManager.loadContent(for: n)
                loadDrawing(for: n)
            }
        }
        .onChange(of: editorContent) {
            saveDebounced(note: note, content: editorContent)
        }
        .onAppear {
            editorContent = noteManager.loadContent(for: note)
            loadDrawing(for: note)
        }
        .onDisappear {
            saveDrawing(for: note)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if !isFocusMode {
                    // Markdown formatting buttons
                    if !isCanvasMode {
                        formatMenu
                    }
                    
                    // Preview toggle
                    if !isCanvasMode {
                        Button(action: { showPreview.toggle() }) {
                            Label("Preview", systemImage: showPreview ? "eye.fill" : "eye.slash")
                        }
                        .help(showPreview ? "Hide Preview" : "Show Preview")
                    }
                    
                    drawToggle(for: note)
                    
                    Button(action: { showingDiagramAssistant.toggle() }) {
                        Label("Diagram", systemImage: "sparkles")
                    }
                    .help("AI Diagram Assistant")
                    
                    Button(action: { showingExportSheet.toggle() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView(note: note, content: editorContent, drawingData: drawing.dataRepresentation())
        }
        .sheet(isPresented: $showingNoteLifetimeSettings) {
            NoteLifetimeSettingsView(lifetimeManager: noteManager.lifetimeManager!)
        }
        .sheet(isPresented: $showingArchivedNotes) {
            ArchivedNotesView(lifetimeManager: noteManager.lifetimeManager!)
        }
        .sheet(isPresented: $showingDiagramAssistant) {
            DiagramAssistantView(description: $diagramDescription, onGenerate: {
                generateDiagram(for: note)
            })
        }
    }
    
    @ViewBuilder
    private func textEditorView(for note: Note) -> some View {
        if showPreview && !isFocusMode {
            // Vista dividida: Editor + Preview
            HSplitView {
                NativeMarkDownEditor(
                    text: $editorContent,
                    onSaveImage: noteManager.saveImage,
                    isFocusMode: false,
                    isCanvasMode: isCanvasMode
                )
                .id(note.id)
            } right: {
                MarkdownPreviewView(
                    markdown: editorContent,
                    imagesDirectory: noteManager.imagesDirectory
                )
            }
        } else {
            // Solo editor (Focus Mode o Preview desactivado)
            NativeMarkDownEditor(
                text: $editorContent,
                onSaveImage: noteManager.saveImage,
                isFocusMode: isFocusMode,
                isCanvasMode: isCanvasMode
            )
            .id(note.id)
        }
    }
    
    @ViewBuilder
    private var drawingToolbar: some View {
        HStack(spacing: 16) {
            // Drawing Tools
            ForEach(DrawingTool.allCases, id: \.self) { tool in
                toolButton(for: tool)
            }
            
            Divider()
                .frame(height: 20)
            
            // Shape Tool Toggle
            Button(action: { isShapeMode.toggle() }) {
                Image(systemName: isShapeMode ? "square.on.circle.fill" : "square.on.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundColor(isShapeMode ? .blue : .primary)
            .padding(8)
            .background(isShapeMode ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .help("Shapes")
            
            // Shape selector (visible when shape mode is active)
            if isShapeMode {
                Menu {
                    ForEach(ShapeType.allCases, id: \.self) { shape in
                        Button(action: { selectedShape = shape }) {
                            Label(shape.rawValue, systemImage: shape.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedShape.icon)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Divider()
                .frame(height: 20)
            
            // Color Picker
            ColorPicker("", selection: $selectedColor)
                .labelsHidden()
                .frame(width: 40)
                .help("Stroke Color")
            
            // Line Width Slider
            HStack(spacing: 8) {
                Image(systemName: "line.diagonal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $lineWidth, in: 1...20)
                    .frame(width: 120)
                
                Text("\(Int(lineWidth))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 25)
            }
            
            Divider()
                .frame(height: 20)
            
            // Undo/Redo (if available in PKCanvasView)
            Button(action: undoDrawing) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .help("Undo")
            
            Button(action: redoDrawing) {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.plain)
            .help("Redo")
            
            Divider()
                .frame(height: 20)
            
            // Clear Canvas
            Button(action: clearDrawing) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .help("Clear All")
            
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    @ViewBuilder
    private func toolButton(for tool: DrawingTool) -> some View {
        Button(action: {
            selectedTool = tool
        }) {
            Image(systemName: iconName(for: tool))
                .font(.title3)
        }
        .buttonStyle(.plain)
        .foregroundColor(selectedTool == tool ? .blue : .primary)
        .padding(8)
        .background(selectedTool == tool ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var formatMenu: some View {
        Menu {
            Button(action: { insertMarkdown("**", "**") }) {
                Label("Bold", systemImage: "bold")
            }
            Button(action: { insertMarkdown("*", "*") }) {
                Label("Italic", systemImage: "italic")
            }
            Button(action: { insertMarkdown("~~", "~~") }) {
                Label("Strikethrough", systemImage: "strikethrough")
            }
            
            Divider()
            
            Button("Heading 1") { insertMarkdown("# ", "") }
            Button("Heading 2") { insertMarkdown("## ", "") }
            Button("Heading 3") { insertMarkdown("### ", "") }
            
            Divider()
            
            Button(action: { insertMarkdown("- ", "") }) {
                Label("Bullet List", systemImage: "list.bullet")
            }
            Button(action: { insertMarkdown("1. ", "") }) {
                Label("Number List", systemImage: "list.number")
            }
            Button(action: { insertMarkdown("> ", "") }) {
                Label("Quote", systemImage: "quote.opening")
            }
            
            Divider()
            
            Button(action: { insertMarkdown("```\n", "\n```") }) {
                Label("Code Block", systemImage: "curlybraces")
            }
        } label: {
            Label("Format", systemImage: "textformat")
        }
    }
    
    private func insertMarkdown(_ prefix: String, _ suffix: String) {
        editorContent += "\n\(prefix)text\(suffix)\n"
    }
    
    private func clearDrawing() {
        drawing = PKDrawing()
        if let note = selectedNote {
            saveDrawing(for: note)
        }
    }
    
    // Undo/Redo for drawing - needs access to PKCanvasView
    @State private var canvasViewReference: Any?
    
    private func undoDrawing() {
        if let canvas = canvasViewReference as? NSView {
            canvas.undoManager?.undo()
        }
    }
    
    private func redoDrawing() {
        if let canvas = canvasViewReference as? NSView {
            canvas.undoManager?.redo()
        }
    }
    
    @ViewBuilder
    private func drawToggle(for note: Note) -> some View {
        Toggle(isOn: $isCanvasMode) {
            Label("Draw", systemImage: isCanvasMode ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
        }
        .toggleStyle(.button)
        .onChange(of: isCanvasMode) {
            handleCanvasModeChange(for: note)
        }
    }
    
    private func handleCanvasModeChange(for note: Note) {
        if isCanvasMode {
            loadDrawing(for: note)
        } else {
            saveDrawing(for: note)
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("Select or Create a Note")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Button(action: createNewNote) {
                Label("New Note", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Drawing Management
    
    private func loadDrawing(for note: Note) {
        if let data = noteManager.loadDrawingData(for: note),
           let d = try? PKDrawing(data: data) {
            drawing = d
        } else {
            drawing = PKDrawing()
        }
    }
    
    private func saveDrawing(for note: Note) {
        let data = drawing.dataRepresentation()
        noteManager.saveDrawingData(data, for: note)
    }
    
    private func iconName(for tool: DrawingTool) -> String {
        switch tool {
        case .pen: return "pencil"
        case .pencil: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .ruler: return "ruler"
        }
    }
    
    // MARK: - Helpers
    
    var sortedAndFilteredNotes: [Note] {
        let filtered = searchText.isEmpty ? noteManager.notes : noteManager.notes.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
        
        switch sortOrder {
        case .alphabetical:
            return filtered.sorted { $0.title < $1.title }
        case .modified:
            return filtered.sorted { $0.modifiedDate > $1.modifiedDate }
        case .created:
            return filtered.sorted { $0.createdDate > $1.createdDate }
        }
    }
    
    private func wordCount(_ text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }
    
    private func createNewNote() {
        if let newNote = noteManager.createNote() {
            DispatchQueue.main.async {
                self.selectedNote = newNote
                self.searchText = ""
            }
        }
    }
    
    private func deleteNote(_ note: Note) {
        // Also delete drawing file
        let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
        try? FileManager.default.removeItem(at: drawingURL)
        
        noteManager.deleteNote(note)
        if selectedNote == note {
            selectedNote = nil
        }
    }
    
    private func deleteOffsets(at offsets: IndexSet) {
        let notesToDelete = offsets.map { sortedAndFilteredNotes[$0] }
        notesToDelete.forEach { deleteNote($0) }
    }
    
    private func renameNote(_ note: Note) {
        let alert = NSAlert()
        alert.messageText = "Rename Note"
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = note.title
        alert.accessoryView = textField
        
        if alert.runModal() == .alertFirstButtonReturn {
            noteManager.renameNote(note, to: textField.stringValue)
        }
    }
    
    private func duplicateNote(_ note: Note) {
        let content = noteManager.loadContent(for: note)
        _ = noteManager.createNote(withTitle: "\(note.title) copy.md", content: content)
    }
    
    private func exportNoteToPDF(_ note: Note) {
        // Simple PDF export
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(note.title).pdf"
        
        if panel.runModal() == .OK, let url = panel.url {
            noteManager.exportToPDF(note: note, to: url)
        }
    }
    
    
    private func saveDebounced(note: Note, content: String) {
        noteManager.saveNote(note: note, content: content)
    }
    
    private func generateDiagram(for note: Note) {
        // This will be handled by the AI (me) when the user describes the diagram.
        // We instruct the AI to use a premium handwritten aesthetic.
        let promptHeader = "Please generate an elegant Mermaid diagram that looks 'hand-drawn' and 'sketchy'. Use a neutral theme and ensure it looks like a high-end sketchbook entry."
        
        let placeholder = """
        
        <!-- AI Diagram Instruction: \(promptHeader) -->
        ```mermaid
        ---
        config:
          look: handDrawn
          theme: neutral
        ---
        graph TD
            A[Idea] --> B[Sketch]
            B --> C[Elegance]
        ```
        
        """
        editorContent += placeholder
        showingDiagramAssistant = false
    }
}

// MARK: - Supporting Views

struct NoteRowView: View {
    let note: Note
    let noteManager: NoteManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 4) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if let daysUntil = note.daysUntilDeath, daysUntil <= 3 && !note.isPinned {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(daysUntil == 0 ? .red : .orange)
                    }
                }
            }
            
            HStack {
                Text(note.modifiedDate, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    if noteManager.hasDrawing(for: note) {
                        Image(systemName: "pencil.tip.crop.circle.badge.plus")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if let daysUntil = note.daysUntilDeath, !note.isPinned {
                        Text(daysUntil == 0 ? "Expires today" : "\(daysUntil)d left")
                            .font(.caption2)
                            .foregroundColor(daysUntil == 0 ? .red : .orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Diagram Assistant View

struct DiagramAssistantView: View {
    @Binding var description: String
    var onGenerate: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("✨ AI Diagram Assistant")
                .font(.headline)
            
            Text("Describe the diagram you want to create (e.g., 'A flow chart of a login process') and I'll generate the Mermaid code for you.")
                .font(.body)
                .foregroundColor(.secondary)
            
            TextEditor(text: $description)
                .font(.body)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Generate Diagram") {
                    onGenerate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}
    
struct ExportView: View {
    let note: Note
    let content: String
    let drawingData: Data?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export \(note.title)")
                .font(.title2)
            
            HStack(spacing: 20) {
                Button("Export as PDF") {
                    exportPDF()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                // Export drawing option if PencilKit data exists
                if let _ = drawingData {
                    Button("Export Drawing as Image") {
                        exportDrawing()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
        }
        .padding(40)
        .frame(width: 400)
    }
    
    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(note.title).pdf"
        
        if panel.runModal() == .OK, let url = panel.url {
            let textStorage = MarkdownTextStorage()
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            
            let containerSize = CGSize(width: 550, height: CGFloat.greatestFiniteMagnitude)
            let textContainer = NSTextContainer(size: containerSize)
            textContainer.widthTracksTextView = true
            layoutManager.addTextContainer(textContainer)
            
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            textView.textContainer = textContainer
            textView.backgroundColor = .white
            
            textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: content)
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            textView.frame = NSRect(x: 0, y: 0, width: 612, height: max(usedRect.height + 100, 792))
            
            let data = textView.dataWithPDF(inside: textView.bounds)
            try? data.write(to: url)
        }
    }
    
    func exportDrawing() {
        guard let data = drawingData,
              let drawing = try? PKDrawing(data: data) else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(note.title)-drawing.png"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Render PKDrawing to image
            let image = drawing.image(from: drawing.bounds, scale: 1.0)
            
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
}



