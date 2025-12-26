import Foundation
import Combine
import AppKit
import UserNotifications
import SwiftUI

// MARK: - Note Model
class Note: ObservableObject, Identifiable, Hashable, Equatable {
    let id: UUID
    @Published var url: URL
    
    init(id: UUID, url: URL) {
        self.id = id
        self.url = url
    }
    var title: String {
        url.deletingPathExtension().lastPathComponent
    }
    
    var modifiedDate: Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date.distantPast
    }
    
    var createdDate: Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? Date.distantPast
    }
    
    // Note Lifetime properties
    var isPinned: Bool {
        get {
            UserDefaults.standard.bool(forKey: "pinned_\(id.uuidString)")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "pinned_\(id.uuidString)")
        }
    }
    
    var isArchived: Bool {
        get {
            UserDefaults.standard.bool(forKey: "archived_\(id.uuidString)")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "archived_\(id.uuidString)")
        }
    }
    
    var deathDate: Date? {
        get {
            guard let interval = UserDefaults.standard.object(forKey: "deathDate_\(id.uuidString)") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
        set {
            if let date = newValue {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "deathDate_\(id.uuidString)")
            } else {
                UserDefaults.standard.removeObject(forKey: "deathDate_\(id.uuidString)")
            }
        }
    }
    
    var daysUntilDeath: Int? {
        guard let deathDate = deathDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: deathDate).day
    }
    
    var isExpired: Bool {
        guard let deathDate = deathDate else { return false }
        return Date() > deathDate
    }
    
    // Conformance for List selection
    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

class NoteManager: ObservableObject {
    @Published var notes: [Note] = []
    var lifetimeManager: NoteLifetimeManager?
    
    var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    var imagesDirectory: URL {
        documentsDirectory.appendingPathComponent("Images")
    }
    
    init() {
        loadNotes()
        lifetimeManager = NoteLifetimeManager(noteManager: self)
        
        if notes.isEmpty {
            _ = createNote(withTitle: "Welcome.md", content: """
            # Welcome to Minimal Markdown
            
            This is a powerful note-taking app with:
            
            ## Features
            - **Rich Markdown Support** with syntax highlighting
            - **Drawing & Annotations** with canvas mode
            - **Focus Mode** for distraction-free writing
            - **Mermaid Diagrams** rendered inline
            - **Export to PDF** and image formats
            - **Smart Search** across all notes
            
            ## Mermaid Diagram Example
            
            ```mermaid
            graph TD
                A[Start] --> B{Is it working?}
                B -->|Yes| C[Great!]
                B -->|No| D[Debug]
                D --> A
                C --> E[End]
            ```
            
            ## Getting Started
            
            1. Create new notes with the + button
            2. Toggle drawing mode with the pencil icon
            3. Use markdown formatting for beautiful notes
            4. Paste images directly with Cmd+V
            
            ### Markdown Examples
            
            **Bold text** and *italic text*
            
            `inline code` for technical terms
            
            [Links](https://apple.com) work too!
            
            Start writing your thoughts here...
            """)
        }
    }
    
    func loadNotes() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey])
            // Filter for .md files
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" }
            
            self.notes = mdFiles.map { url in
                Note(id: UUID(), url: url)
            }.sorted { $0.modifiedDate > $1.modifiedDate }
            
        } catch {
            print("Error loading notes: \(error)")
        }
    }
    
    func createNote(withTitle title: String? = nil, content: String? = nil) -> Note? {
        let fileName = title ?? "Untitled \(Date().formatted(date: .numeric, time: .omitted)).md"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        let initialContent = content ?? "# New Note\n\nStart writing..."
        
        do {
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            let newNote = Note(id: UUID(), url: fileURL)
            loadNotes() // Refresh list
            return newNote
        } catch {
            print("Error creating note: \(error)")
            return nil
        }
    }
    
    func deleteNote(_ note: Note) {
        do {
            try FileManager.default.removeItem(at: note.url)
            // Also delete associated drawing file
            let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
            try? FileManager.default.removeItem(at: drawingURL)
            loadNotes()
        } catch {
            print("Error deleting note: \(error)")
        }
    }
    
    func renameNote(_ note: Note, to newName: String) {
        var sanitizedName = newName
        if !sanitizedName.hasSuffix(".md") {
            sanitizedName += ".md"
        }
        
        let newURL = note.url.deletingLastPathComponent().appendingPathComponent(sanitizedName)
        
        do {
            try FileManager.default.moveItem(at: note.url, to: newURL)
            
            // Also rename drawing file if it exists
            let oldDrawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
            let newDrawingURL = newURL.deletingPathExtension().appendingPathExtension("drawing")
            
            if FileManager.default.fileExists(atPath: oldDrawingURL.path) {
                try? FileManager.default.moveItem(at: oldDrawingURL, to: newDrawingURL)
            }
            
            loadNotes()
        } catch {
            print("Error renaming note: \(error)")
        }
    }
    
    func saveNote(note: Note, content: String) {
        do {
            try content.write(to: note.url, atomically: true, encoding: .utf8)
            // Update modified date
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        } catch {
            print("Error saving note: \(error)")
        }
    }
    
    func saveImage(_ image: NSImage) -> URL? {
        let imagesDir = documentsDirectory.appendingPathComponent("Images")
        
        // Ensure Images directory exists
        if !FileManager.default.fileExists(atPath: imagesDir.path) {
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
        
        let fileName = "\(UUID().uuidString).png"
        let fileURL = imagesDir.appendingPathComponent(fileName)
        
        // Convert NSImage to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("Error converting image to PNG")
            return nil
        }
        
        do {
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving image: \(error)")
            return nil
        }
    }
    
    func loadContent(for note: Note) -> String {
        do {
            return try String(contentsOf: note.url, encoding: .utf8)
        } catch {
            print("Error reading content: \(error)")
            return "# Error loading content"
        }
    }
    
    func hasDrawing(for note: Note) -> Bool {
        let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
        return FileManager.default.fileExists(atPath: drawingURL.path)
    }
    
    func saveDrawingData(_ data: Data, for note: Note) {
        let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
        do {
            try data.write(to: drawingURL)
            // Update modified date of the note to reflect drawing changes
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: note.url.path)
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        } catch {
            print("Error saving drawing data: \(error)")
        }
    }
    
    func loadDrawingData(for note: Note) -> Data? {
        let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
        return try? Data(contentsOf: drawingURL)
    }
    
    func exportToPDF(note: Note, to url: URL) {
        let content = loadContent(for: note)
        
        // 1. Setup Markdown Storage to process the styling
        let textStorage = MarkdownTextStorage()
        textStorage.setImagesDirectory(imagesDirectory)
        
        // 2. Setup standard text system
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let containerSize = CGSize(width: 550, height: CGFloat.greatestFiniteMagnitude) // Standard A4-ish width minus margins
        let textContainer = NSTextContainer(size: containerSize)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        // 3. Create generic TextView for rendering
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.textContainer = textContainer
        textView.backgroundColor = .white // PDF should usually be white
        
        // 4. Set Content triggers parsing in MarkdownTextStorage
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: content)
        
        // 5. Force layout
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        textView.frame = NSRect(x: 0, y: 0, width: 612, height: max(usedRect.height + 100, 792))
        
        // 6. Generate PDF
        let data = textView.dataWithPDF(inside: textView.bounds)
        try? data.write(to: url)
    }
}

// MARK: - Note Lifetime Configuration
struct NoteLifetimeConfig {
    var isEnabled: Bool
    var durationInDays: Int
    var notificationEnabled: Bool
    
    static let `default` = NoteLifetimeConfig(
        isEnabled: false,
        durationInDays: 7,
        notificationEnabled: true
    )
}

// MARK: - Note Lifetime Manager
class NoteLifetimeManager: ObservableObject {
    @Published var config: NoteLifetimeConfig
    @Published var archivedNotes: [Note] = []
    
    private let noteManager: NoteManager
    private var notificationTimer: Timer?
    
    init(noteManager: NoteManager) {
        self.noteManager = noteManager
        self.config = Self.loadConfig()
        
        loadArchivedNotes()
        setupNotifications()
        startExpirationCheck()
    }
    
    // MARK: - Configuration
    static func loadConfig() -> NoteLifetimeConfig {
        let isEnabled = UserDefaults.standard.bool(forKey: "noteLifetimeEnabled")
        let durationInDays = UserDefaults.standard.integer(forKey: "noteLifetimeDuration")
        let notificationEnabled = UserDefaults.standard.bool(forKey: "noteLifetimeNotifications")
        
        return NoteLifetimeConfig(
            isEnabled: isEnabled,
            durationInDays: durationInDays > 0 ? durationInDays : 7,
            notificationEnabled: notificationEnabled
        )
    }
    
    func updateConfig(_ newConfig: NoteLifetimeConfig) {
        config = newConfig
        
        UserDefaults.standard.set(newConfig.isEnabled, forKey: "noteLifetimeEnabled")
        UserDefaults.standard.set(newConfig.durationInDays, forKey: "noteLifetimeDuration")
        UserDefaults.standard.set(newConfig.notificationEnabled, forKey: "noteLifetimeNotifications")
        
        if newConfig.isEnabled {
            scheduleDeathDatesForAllNotes()
        } else {
            clearAllDeathDates()
        }
    }
    
    // MARK: - Death Date Management
    func scheduleDeathDate(for note: Note) {
        guard config.isEnabled && !note.isPinned else {
            note.deathDate = nil
            return
        }
        
        let deathDate = Calendar.current.date(byAdding: .day, value: config.durationInDays, to: note.modifiedDate)
        note.deathDate = deathDate
        
        if config.notificationEnabled {
            scheduleNotification(for: note)
        }
    }
    
    func scheduleDeathDatesForAllNotes() {
        for note in noteManager.notes {
            scheduleDeathDate(for: note)
        }
    }
    
    func clearAllDeathDates() {
        for note in noteManager.notes {
            note.deathDate = nil
        }
    }
    
    func keepNoteAlive(_ note: Note) {
        note.isPinned = true
        note.deathDate = nil
        cancelNotification(for: note)
    }
    
    func unpinNote(_ note: Note) {
        note.isPinned = false
        scheduleDeathDate(for: note)
    }
    
    // MARK: - Archive Management
    func archiveExpiredNotes() {
        let expiredNotes = noteManager.notes.filter { $0.isExpired && !$0.isArchived }
        
        for note in expiredNotes {
            archiveNote(note)
        }
    }
    
    private func archiveNote(_ note: Note) {
        note.isArchived = true
        
        // Move to archived directory
        let archivedDir = noteManager.documentsDirectory.appendingPathComponent("Archived")
        try? FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)
        
        let archivedURL = archivedDir.appendingPathComponent(note.url.lastPathComponent)
        try? FileManager.default.moveItem(at: note.url, to: archivedURL)
        
        // Also move drawing if exists
        let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
        if FileManager.default.fileExists(atPath: drawingURL.path) {
            let archivedDrawingURL = archivedURL.deletingPathExtension().appendingPathExtension("drawing")
            try? FileManager.default.moveItem(at: drawingURL, to: archivedDrawingURL)
        }
        
        // Update note URL
        note.url = archivedURL
        
        loadArchivedNotes()
        noteManager.loadNotes()
    }
    
    func restoreNote(_ note: Note) {
        note.isArchived = false
        note.deathDate = nil
        
        // Move back to main directory
        let restoredURL = noteManager.documentsDirectory.appendingPathComponent(note.url.lastPathComponent)
        try? FileManager.default.moveItem(at: note.url, to: restoredURL)
        
        // Also move drawing if exists
        let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
        if FileManager.default.fileExists(atPath: drawingURL.path) {
            let restoredDrawingURL = restoredURL.deletingPathExtension().appendingPathExtension("drawing")
            try? FileManager.default.moveItem(at: drawingURL, to: restoredDrawingURL)
        }
        
        // Update note URL
        note.url = restoredURL
        
        loadArchivedNotes()
        noteManager.loadNotes()
    }
    
    func permanentlyDeleteNote(_ note: Note) {
        try? FileManager.default.removeItem(at: note.url)
        
        // Also delete drawing if exists
        let drawingURL = note.url.deletingPathExtension().appendingPathExtension("drawing")
        try? FileManager.default.removeItem(at: drawingURL)
        
        loadArchivedNotes()
    }
    
    private func loadArchivedNotes() {
        let archivedDir = noteManager.documentsDirectory.appendingPathComponent("Archived")
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: archivedDir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey])
            let mdFiles = fileURLs.filter { $0.pathExtension == "md" }
            
            archivedNotes = mdFiles.map { url in
                let note = Note(id: UUID(), url: url)
                note.isArchived = true
                return note
            }.sorted { $0.modifiedDate > $1.modifiedDate }
            
        } catch {
            archivedNotes = []
        }
    }
    
    // MARK: - Notifications
    private func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }
    
    private func scheduleNotification(for note: Note) {
        guard let deathDate = note.deathDate else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Note Expiring Soon"
        content.body = "\"\(note.title)\" will expire in 24 hours. Keep it alive or let it go."
        content.sound = .default
        content.userInfo = ["noteId": note.id.uuidString]
        
        // Schedule 24 hours before death
        let notificationDate = Calendar.current.date(byAdding: .day, value: -1, to: deathDate) ?? deathDate
        
        if notificationDate > Date() {
            let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate), repeats: false)
            let request = UNNotificationRequest(identifier: "note_\(note.id.uuidString)", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    private func cancelNotification(for note: Note) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["note_\(note.id.uuidString)"])
    }
    
    // MARK: - Expiration Check Timer
    private func startExpirationCheck() {
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            self.archiveExpiredNotes()
        }
    }
    
    deinit {
        notificationTimer?.invalidate()
    }
}

// MARK: - Note Lifetime Views (Merged from NoteLifetimeViews.swift)

// MARK: - Note Lifetime Settings View
struct NoteLifetimeSettingsView: View {
    @ObservedObject var lifetimeManager: NoteLifetimeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Note Lifetime")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom)
            
            Text("Let notes die automatically to keep your notebook fresh and organized.")
                .font(.body)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 15) {
                Toggle("Enable Note Lifetime", isOn: Binding(
                    get: { lifetimeManager.config.isEnabled },
                    set: { newValue in
                        var newConfig = lifetimeManager.config
                        newConfig.isEnabled = newValue
                        lifetimeManager.updateConfig(newConfig)
                    }
                ))
                
                if lifetimeManager.config.isEnabled {
                    HStack {
                        Text("Duration:")
                        Spacer()
                        Picker("Days", selection: Binding(
                            get: { lifetimeManager.config.durationInDays },
                            set: { newValue in
                                var newConfig = lifetimeManager.config
                                newConfig.durationInDays = newValue
                                lifetimeManager.updateConfig(newConfig)
                            }
                        )) {
                            ForEach([1, 3, 7, 14, 30], id: \.self) { days in
                                Text("\(days) days").tag(days)
                            }
                        }
                        .frame(width: 100)
                    }
                    
                    Toggle("Send Notifications", isOn: Binding(
                        get: { lifetimeManager.config.notificationEnabled },
                        set: { newValue in
                            var newConfig = lifetimeManager.config
                            newConfig.notificationEnabled = newValue
                            lifetimeManager.updateConfig(newConfig)
                        }
                    ))
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 400, height: 300)
    }
}

// MARK: - Archived Notes View
struct ArchivedNotesView: View {
    @ObservedObject var lifetimeManager: NoteLifetimeManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Archived Notes")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom)
            
            if lifetimeManager.archivedNotes.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("No archived notes")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(lifetimeManager.archivedNotes) { note in
                    ArchivedNoteRowView(note: note, lifetimeManager: lifetimeManager)
                }
                .listStyle(.plain)
            }
            
            HStack {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 600, height: 500)
    }
}

// MARK: - Archived Note Row View
struct ArchivedNoteRowView: View {
    let note: Note
    @ObservedObject var lifetimeManager: NoteLifetimeManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("Archived \(note.modifiedDate, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("Restore") {
                    lifetimeManager.restoreNote(note)
                }
                .buttonStyle(.bordered)
                
                Button("Delete") {
                    lifetimeManager.permanentlyDeleteNote(note)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
