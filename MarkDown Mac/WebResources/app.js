// Initialize Markdown-it
// Initialize Markdown-It with plugins
const md = window.markdownit({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function (str, lang) {
        if (lang && hljs.getLanguage(lang)) {
            try {
                return hljs.highlight(str, { language: lang }).value;
            } catch (__) { }
        }
        return ''; // use external default escaping
    }
})
    .use(window.markdownitEmoji)
    .use(window.markdownitSub)
    .use(window.markdownitSup)
    .use(window.markdownitFootnote);
// .use(window.markdownitKatex); // Still commenting out KaTeX as I didn't download configs fully properly yet via single file. Core plugins are safe.

// Initialize Mermaid
mermaid.initialize({
    startOnLoad: false,
    theme: document.body.classList.contains('theme-dark') ? 'dark' : 'default',
    securityLevel: 'loose'
});

// Editor Initialization
const editor = CodeMirror(document.getElementById("editor"), {
    mode: "markdown",
    theme: document.body.classList.contains('theme-dark') ? "dracula" : "xq-light",
    lineNumbers: false,
    lineWrapping: true,
    styleActiveLine: true,
    autoCloseBrackets: true,
    placeholder: "Type your markdown here... (Drag & Drop images supported)",
    viewportMargin: Infinity,
    extraKeys: {
        "Enter": "newlineAndIndentContinueMarkdownList"
    }
});

// Custom List Continuation Handling (Fallback/Polyfill)
editor.addKeyMap({
    "Enter": function (cm) {
        var doc = cm.getDoc();
        var cursor = doc.getCursor();
        var line = doc.getLine(cursor.line);
        var listRegex = /^(\s*)([*+-]|\d+\.)(\s+)/;
        var match = line.match(listRegex);

        if (match) {
            if (line.trim() === match[0].trim()) {
                doc.replaceRange("", { line: cursor.line, ch: 0 }, { line: cursor.line, ch: line.length });
                return;
            }
            var indent = match[1];
            var bullet = match[2];
            if (!isNaN(parseInt(bullet))) {
                var num = parseInt(bullet);
                bullet = (num + 1) + ".";
            }
            cm.replaceSelection("\n" + indent + bullet + " ");
        } else {
            cm.execCommand("newlineAndIndent");
        }
    }
});


// Editor Change Handler (Sync to Swift)
editor.on("change", function () {
    const content = editor.getValue();
    updatePreview(content);
    scanForImages(content); // Auto-process Base64
    renderInlineImages();   // Update Image Widgets

    // Send to Swift
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.textDidChange) {
        window.webkit.messageHandlers.textDidChange.postMessage(content);
    }
});

// Inline Image Widgets
let currentWidgets = [];
let currentMarks = [];

function renderInlineImages() {
    // Clear old widgets/marks to prevent duplicates
    currentMarks.forEach(m => m.clear());
    currentMarks = [];

    const doc = editor.getDoc();
    const lineCount = doc.lineCount();
    const regex = /!\[(.*?)\]\((.*?)\)/g;

    for (let i = 0; i < lineCount; i++) {
        const lineText = doc.getLine(i);
        let match;

        while ((match = regex.exec(lineText)) !== null) {
            const startCh = match.index;
            const endCh = match.index + match[0].length;
            const altText = match[1];
            const src = match[2];

            // Create Visual Widget
            const wrapper = document.createElement('div');
            wrapper.className = 'inline-image-wrapper';
            wrapper.style.display = 'inline-block';
            wrapper.style.position = 'relative';
            wrapper.contentEditable = false; // Prevent cursor getting stuck inside

            const img = document.createElement('img');
            img.src = src;
            img.alt = altText;
            img.className = 'inline-editor-image';
            img.style.maxWidth = '100%';
            img.style.borderRadius = '8px';

            // Delete Button (X)
            const deleteBtn = document.createElement('div');
            deleteBtn.innerHTML = '×';
            deleteBtn.className = 'image-delete-btn';
            deleteBtn.onclick = (e) => {
                e.stopPropagation();
                // Remove the markdown text
                const from = { line: i, ch: startCh };
                const to = { line: i, ch: endCh };
                doc.replaceRange("", from, to);
            };

            // Resize Handle
            const resizeHandle = document.createElement('div');
            resizeHandle.className = 'resize-handle';

            wrapper.appendChild(img);
            wrapper.appendChild(deleteBtn);
            wrapper.appendChild(resizeHandle);

            // Replace Markdown with Widget
            const mark = doc.markText(
                { line: i, ch: startCh },
                { line: i, ch: endCh },
                {
                    replacedWith: wrapper, // This is the key "Native" Feature
                    atomic: true, // Treat as one character
                    selectLeft: false,
                    selectRight: false
                }
            );
            currentMarks.push(mark);
        }
    }
    // No editor.refresh() needed here often, but good for measure
}

// Image Processor: Scan for Base64 and upload
function scanForImages(content) {
    const regex = /!\[(.*?)\]\(data:image\/([a-zA-Z]+);base64,([^\)]+)\)/g;
    let match;

    // We strictly find one match at a time to avoid index drift issues during replacement
    if ((match = regex.exec(content)) !== null) {
        const fullMatch = match[0];
        const altText = match[1] || "Image";
        // const type = match[2]; // png, jpeg
        const base64 = match[3];
        const id = "img_auto_" + Date.now();

        // Immediate Replace with Placeholder
        const doc = editor.getDoc();
        const cursor = doc.getCursor();

        // We need to locate this string in the editor to replace it range-wise
        // A simple string replace on getValue() is easier but resets cursor.
        // Let's use the range replacement if possible, or just value replacement and try to keep cursor.

        // For stability, send to Swift first, then Swift calls replaceImagePlaceholder.
        // But we MUST remove the Base64 immediately or it lags the editor.

        const placeholder = `![Uploading ${altText}...](${id})`;
        const newValue = content.replace(fullMatch, placeholder);

        // Calculate new cursor?
        // Simple approach: Set Value, restore cursor (approximate)
        editor.setValue(newValue);
        editor.setCursor(cursor);

        // Send to Swift
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.saveImage) {
            window.webkit.messageHandlers.saveImage.postMessage({ base64: base64, id: id });
        }
    }
}

// Sync from Swift (Called by Native App)
window.updateContent = function (text) {
    if (text !== editor.getValue()) {
        const cursor = editor.getCursor();
        editor.setValue(text);
        editor.setCursor(cursor);
        renderInlineImages(); // Init images on load
        updatePreview(text);
    }
};

// Theme Sync (Called by Native App)
window.setTheme = function (themeName) {
    const body = document.body;
    if (themeName === 'dark') {
        body.classList.add('theme-dark');
        body.classList.remove('theme-light');
        editor.setOption("theme", "dracula");
        document.getElementById('hljs-theme').href = "lib/highlight/github-dark.min.css";
        mermaid.initialize({ startOnLoad: true, theme: 'dark' });
    } else {
        body.classList.add('theme-light');
        body.classList.remove('theme-dark');
        editor.setOption("theme", "xq-light");
        document.getElementById('hljs-theme').href = "lib/highlight/github.min.css"; // You might need to download github.min.css too if strictly local
        mermaid.initialize({ startOnLoad: true, theme: 'default' });
    }
    setTimeout(updatePreview, 100); // Re-render preview with new theme
};

// Native Image Handling (Paste & Drop)
function handleImageUpload(blob, doc, cursor) {
    // Read blob
    const reader = new FileReader();
    reader.onload = function (event) {
        const base64 = event.target.result.split(',')[1]; // Remove data:image... prefix
        const id = "img_" + Date.now();

        // Insert placeholder
        const placeholder = `![Uploading Image...](${id})`;
        doc.replaceRange(placeholder, cursor);

        // Send to Swift
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.saveImage) {
            window.webkit.messageHandlers.saveImage.postMessage({ base64: base64, id: id });
        } else {
            console.error("Swift Bridge 'saveImage' not found.");
        }
    };
    reader.readAsDataURL(blob);
}

// Improved Paste Handler
editor.on("paste", function (cm, event) {
    const items = (event.clipboardData || event.originalEvent.clipboardData).items;
    for (let index in items) {
        const item = items[index];
        if (item.kind === 'file' && item.type.match(/^image/)) {
            event.preventDefault();
            handleImageUpload(item.getAsFile(), cm.getDoc(), cm.getDoc().getCursor());
            return;
        }
    }
    // If we didn't handle it as a file, the default paste happens.
    // If the clipboard contained HTML that converts to Base64 image,
    // our scanForImages() will catch it on the next change event.
});

editor.on("drop", (cm, e) => {
    e.preventDefault();
    const files = e.dataTransfer.files;
    if (files && files.length > 0) {
        const file = files[0];
        if (file.type.startsWith("image/")) {
            // Calculate cursor position from drop coordinates
            const pos = cm.coordsChar({ left: e.clientX, top: e.clientY });
            handleImageUpload(file, cm.getDoc(), pos);
        }
    }
});

// Called by Swift after saving image
window.replaceImagePlaceholder = function (id, path) {
    const content = editor.getValue();
    const newMarkdown = `![Image](${path})`;
    const placeholder = `![Uploading Image...](${id})`;

    // Replace text
    const newValue = content.replace(placeholder, newMarkdown);
    if (newValue !== content) {
        const cursor = editor.getCursor();
        editor.setValue(newValue);
        editor.setCursor(cursor);
    }
};

// Initial Preview
updatePreview(editor.getValue());

// Single Preview Function
function updatePreview(markdown) {
    if (!markdown) return;

    // Render Markdown
    let result = md.render(markdown);

    // Post-process for Mermaid
    const mermaidBlocks = tempDiv.querySelectorAll('pre code.language-mermaid');
    mermaidBlocks.forEach((block) => {
        const graphDefinition = block.textContent;
        const pre = block.parentElement;
        const div = document.createElement('div');
        div.className = 'mermaid';
        div.textContent = graphDefinition;
        pre.replaceWith(div);
    });

    // Update DOM
    const previewDiv = document.getElementById('preview');
    previewDiv.innerHTML = tempDiv.innerHTML;

    // Highlight Code
    if (window.hljs) {
        previewDiv.querySelectorAll('pre code').forEach((block) => {
            if (!block.classList.contains('language-mermaid')) {
                hljs.highlightBlock(block);
            }
        });
    }

    // Initialize Mermaid
    if (window.mermaid) {
        try {
            mermaid.init(undefined, previewDiv.querySelectorAll('.mermaid'));
        } catch (e) { console.error("Mermaid Init Error:", e); }
    }
}

// Resizer Logic
const resizer = document.getElementById('resizer');
const editorPane = document.getElementById('editor-pane');

let isResizing = false;

resizer.addEventListener('mousedown', (e) => {
    isResizing = true;
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', () => {
        isResizing = false;
        document.removeEventListener('mousemove', handleMouseMove);
    });
});

function handleMouseMove(e) {
    if (!isResizing) return;
    const containerWidth = document.body.clientWidth;
    const newEditorWidth = (e.clientX / containerWidth) * 100;

    if (newEditorWidth > 10 && newEditorWidth < 90) {
        editorPane.style.flex = `0 0 ${newEditorWidth}%`;
    }
}

// Formatting Bridge
window.toggleFormat = function (type) {
    const doc = editor.getDoc();
    const cursor = doc.getCursor();
    const selection = doc.getSelection();

    if (type === 'bold') {
        if (selection) {
            doc.replaceSelection(`**${selection}**`);
        } else {
            doc.replaceRange('****', cursor);
            doc.setCursor({ line: cursor.line, ch: cursor.ch + 2 });
        }
    } else if (type === 'italic') {
        if (selection) {
            doc.replaceSelection(`*${selection}*`);
        } else {
            doc.replaceRange('**', cursor);
            doc.setCursor({ line: cursor.line, ch: cursor.ch + 1 });
        }
    } else if (type === 'heading') {
        const line = doc.getLine(cursor.line);
        if (line.startsWith('# ')) {
            doc.replaceRange('## ', { line: cursor.line, ch: 0 }, { line: cursor.line, ch: 2 });
        } else if (line.startsWith('## ')) {
            doc.replaceRange('### ', { line: cursor.line, ch: 0 }, { line: cursor.line, ch: 3 });
        } else if (line.startsWith('### ')) {
            doc.replaceRange('', { line: cursor.line, ch: 0 }, { line: cursor.line, ch: 4 });
        } else {
            doc.replaceRange('# ', { line: cursor.line, ch: 0 });
        }
    } else if (type === 'list') {
        const line = doc.getLine(cursor.line);
        if (line.startsWith('- ')) {
            doc.replaceRange('', { line: cursor.line, ch: 0 }, { line: cursor.line, ch: 2 });
        } else {
            doc.replaceRange('- ', { line: cursor.line, ch: 0 });
        }
    }
    editor.focus();
};

// View Mode & Canvas Toggle
let isCanvasMode = false;
let canvasSVG = null;
let isDrawing = false;
let currentPath = null;
let currentPoints = [];

window.setViewMode = function (mode) {
    if (mode === 'toggleCanvas') {
        toggleCanvasMode();
        return;
    }

    // ... existing preview logic ...
    const editorPane = document.getElementById('editor-pane');
    const previewPane = document.getElementById('preview-pane');

    if (mode === 'preview') {
        editorPane.style.display = 'none';
        previewPane.style.display = 'block';
        updatePreview(editor.getValue());
    } else {
        editorPane.style.display = 'flex';
        previewPane.style.display = 'none';
        editor.refresh();
        editor.focus();
    }
};

function toggleCanvasMode() {
    isCanvasMode = !isCanvasMode;
    const body = document.body;

    if (isCanvasMode) {
        body.classList.add('canvas-mode');
        // Initialize Canvas Layer if needed
        if (!canvasSVG) {
            initCanvasLayer();
        }
        canvasSVG.style.pointerEvents = 'auto';
        editor.setOption('readOnly', true); // Disable text editing while drawing
    } else {
        body.classList.remove('canvas-mode');
        if (canvasSVG) canvasSVG.style.pointerEvents = 'none';
        editor.setOption('readOnly', false);
    }
}

function initCanvasLayer() {
    // Create SVG Overlay
    const editorEl = document.getElementById('editor');
    canvasSVG = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    canvasSVG.id = 'drawing-layer';
    canvasSVG.style.position = 'absolute';
    canvasSVG.style.top = '0';
    canvasSVG.style.left = '0';
    canvasSVG.style.width = '100%';
    canvasSVG.style.height = '100%';
    canvasSVG.style.zIndex = '100'; // Above text
    canvasSVG.style.cursor = 'crosshair';
    canvasSVG.style.overflow = 'visible'; // Let strokes go anywhere

    editorEl.appendChild(canvasSVG);

    // Event Listeners for Drawing
    canvasSVG.addEventListener('mousedown', startDraw);
    canvasSVG.addEventListener('mousemove', draw);
    canvasSVG.addEventListener('mouseup', endDraw);

    // Allow pass-through interaction for Images?
    // We need to handle Image Dragging separately.
    setupImageInteraction();
}

// Canvas Undo Support
document.addEventListener('keydown', function (e) {
    if (isCanvasMode && (e.metaKey || e.ctrlKey) && e.key === 'z') {
        e.preventDefault();
        // Undo last stroke
        if (canvasSVG && canvasSVG.lastChild) {
            canvasSVG.removeChild(canvasSVG.lastChild);
        }
    }
});

function startDraw(e) {
    // Note: If clicking on a resize handle, do NOT draw.
    if (e.target.classList.contains('resize-handle')) return;

    if (!isCanvasMode) return;
    isDrawing = true;
    const pt = getCoords(e);
    currentPoints = [pt];

    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("stroke", "rgba(220, 50, 50, 0.9)"); // Red pencil
    path.setAttribute("stroke-width", "3");
    path.setAttribute("fill", "none");
    path.setAttribute("stroke-linecap", "round");
    path.setAttribute("stroke-linejoin", "round");

    canvasSVG.appendChild(path);
    currentPath = path;
}

function draw(e) {
    if (!isDrawing || !currentPath) return;
    const pt = getCoords(e);
    currentPoints.push(pt);

    // Simple polyline
    const d = currentPoints.reduce((acc, point, i) => {
        return acc + (i === 0 ? "M" : "L") + point.x + "," + point.y;
    }, "");

    currentPath.setAttribute("d", d);
}

// Persistence Logic
function getDrawingData() {
    if (!canvasSVG) return [];
    const paths = Array.from(canvasSVG.querySelectorAll('path')).map(p => p.getAttribute('d'));
    return paths;
}

function restoreDrawingData(paths) {
    if (!canvasSVG) initCanvasLayer();
    // Clear existing
    while (canvasSVG.firstChild) {
        canvasSVG.removeChild(canvasSVG.firstChild);
    }

    paths.forEach(d => {
        const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        path.setAttribute("stroke", "rgba(220, 50, 50, 0.9)");
        path.setAttribute("stroke-width", "3");
        path.setAttribute("fill", "none");
        path.setAttribute("stroke-linecap", "round");
        path.setAttribute("stroke-linejoin", "round");
        path.setAttribute("d", d);
        canvasSVG.appendChild(path);
    });
}

// Flag to prevent Echo Loops
let isRemoteUpdate = false;

// Update Content (Sync from Swift)
window.updateContent = function (text) {
    // ... (drawing extraction logic) ... 
    // Format: <!-- DRAWING_DATA:["M...", "M..."] -->
    const drawingRegex = /<!-- DRAWING_DATA:(.*?) -->$/s;
    const match = text.match(drawingRegex);
    let cleanText = text;
    let drawingData = [];

    if (match) {
        try {
            drawingData = JSON.parse(match[1]);
            cleanText = text.replace(drawingRegex, '').trim();
        } catch (e) { console.error(e); }
    } else {
        if (canvasSVG) { while (canvasSVG.firstChild) { canvasSVG.removeChild(canvasSVG.firstChild); } }
    }

    if (cleanText !== editor.getValue()) {
        isRemoteUpdate = true; // Set flag
        const cursor = editor.getCursor();
        editor.setValue(cleanText);
        editor.setCursor(cursor);
        renderInlineImages();
        isRemoteUpdate = false; // Clear flag
    }

    // Always update preview/canvas
    updatePreview(cleanText, drawingData);
    restoreDrawingData(drawingData);
};

// ...

// Hook into Change
function notifyChange() {
    if (isRemoteUpdate) return; // SKIP if update came from Swift

    const content = editor.getValue();
    const paths = getDrawingData();
    let finalContent = content;
    if (paths.length > 0) {
        finalContent += `\n\n<!-- DRAWING_DATA:${JSON.stringify(paths)} -->`;
    }

    // ...
    // Update Drawing Live Preview
    if (document.getElementById('preview-pane').style.display === 'block') {
        updatePreview(content, paths);
    }

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.textDidChange) {
        window.webkit.messageHandlers.textDidChange.postMessage(finalContent);
    }
}

// Modify editor handlers
editor.on("change", function (cm, changeObj) {
    if (changeObj.origin === 'setValue' && isRemoteUpdate) return;

    const content = editor.getValue();
    // Only update expensive things if not remote? 
    // Actually we need to render images if Swift loaded text.
    // distinct handling in verify:

    if (!isRemoteUpdate) {
        updatePreview(content, getDrawingData());
        scanForImages(content);
        renderInlineImages();
        notifyChange();
    }
});

function endDraw() {
    isDrawing = false;
    currentPath = null;
    currentPoints = [];
    notifyChange(); // Save drawing immediately
}

function getCoords(e) {
    const rect = canvasSVG.getBoundingClientRect();
    return {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top + window.scrollY // Standard scroll
        // CodeMirror scroll? If inside CM, use CM coords.
    };
}

// Image Interaction (Drag/Resize)
function setupImageInteraction() {
    // Delegate events for images inside editor
    document.addEventListener('mousedown', function (e) {
        if (!isCanvasMode) return;

        let target = e.target;

        // Resize Handle Click?
        if (target.classList.contains('resize-handle')) {
            startResizeImage(e, target.parentElement); // Parent is wrapper
            return;
        }

        // Check if it's our wrapper or image
        if (target.tagName === 'IMG' && target.classList.contains('inline-editor-image')) {
            target = target.parentElement; // Wrapper
        }

        if (target.classList.contains('inline-image-wrapper')) {
            startDragImage(e, target);
        }
    });
}

function startResizeImage(e, wrapper) {
    e.preventDefault();
    e.stopPropagation();

    const startX = e.clientX;
    const startY = e.clientY;

    const img = wrapper.querySelector('img');
    const startWidth = img.clientWidth;
    const startHeight = img.clientHeight;

    function onMove(moveEvent) {
        moveEvent.preventDefault();
        const dx = moveEvent.clientX - startX;
        // Simple width resize
        const newWidth = startWidth + dx;
        if (newWidth > 50) { // Min width
            img.style.maxWidth = 'none'; // Unlock
            img.style.width = newWidth + 'px';
            wrapper.style.width = newWidth + 'px'; // Wrapper follows
        }
    }

    function onUp() {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
    }

    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
}


function startDragImage(e, el) {
    e.preventDefault();
    e.stopPropagation();

    let startX = e.clientX;
    let startY = e.clientY;

    // We need to make it absolute positioned if it isn't yet?
    // CM widgets are static. To move them "anywhere", we might need to detach them?
    // Or just use transform translate.

    function onMove(moveEvent) {
        const dx = moveEvent.clientX - startX;
        const dy = moveEvent.clientY - startY;

        // This moves relative to current flow position
        const currentTransform = el.style.transform || 'translate(0px, 0px)';
        // Parse current (naive)
        // Ideally tracking total delta
        el.style.transform = `translate(${dx}px, ${dy}px)`;
        // NOTE: This resets on re-render. Ideally we update Markdown meta-data/attributes.
    }

    function onUp() {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
    }

    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
}

// Bridge to Swift
window.exportPDF = () => {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.appBridge) {
        window.webkit.messageHandlers.appBridge.postMessage({ action: 'exportPDF' });
    } else {
        // Fallback or print
        window.print();
    }
};
