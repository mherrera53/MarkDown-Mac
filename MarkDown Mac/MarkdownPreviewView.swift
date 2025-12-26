import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let imagesDirectory: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Enable developer tools for debugging
        #if DEBUG
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(from: markdown)
        
        // Prevent redundant loads
        if let currentHTML = context.coordinator.lastHTML, currentHTML == html {
            return
        }
        
        context.coordinator.lastHTML = html
        
        // Use resourceURL to allow loading local web resources
        if let resourceURL = Bundle.main.resourceURL {
            webView.loadHTMLString(html, baseURL: resourceURL)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var lastHTML: String?
    }
    
    private func generateHTML(from markdown: String) -> String {
        let convertedMarkdown = convertMarkdownToHTML(markdown)
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link href="https://fonts.googleapis.com/css2?family=Kalam:wght@300;400;700&display=swap" rel="stylesheet">
            <style>
                :root {
                    color-scheme: light dark;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    padding: 20px;
                    margin: 0;
                    color: var(--text-color);
                    background-color: transparent !important;
                }
                
                @media (prefers-color-scheme: light) {
                    :root {
                        --text-color: #24292e;
                        --bg-color: transparent;
                        --border-color: #e1e4e8;
                        --code-bg: #f6f8fa;
                    }
                }
                
                @media (prefers-color-scheme: dark) {
                    :root {
                        --text-color: #c9d1d9;
                        --bg-color: transparent;
                        --border-color: #30363d;
                        --code-bg: #161b22;
                    }
                }
                
                .mermaid {
                    background: transparent !important;
                    display: block;
                    margin: 20px 0;
                    min-height: 50px;
                    text-align: center;
                    visibility: hidden; /* Hide until rendered */
                    font-family: 'Kalam', cursive !important;
                }
                
                .mermaid text {
                    font-family: 'Kalam', cursive !important;
                }
                
                .mermaid[data-processed="true"] {
                    visibility: visible;
                }
                
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                
                h1 {
                    font-size: 2em;
                    border-bottom: 1px solid var(--border-color);
                    padding-bottom: 0.3em;
                }
                
                h2 {
                    font-size: 1.5em;
                    border-bottom: 1px solid var(--border-color);
                    padding-bottom: 0.3em;
                }
                
                p {
                    margin-top: 0;
                    margin-bottom: 16px;
                }
                
                /* Checklists */
                .has-checklist {
                    list-style-type: none;
                    padding-left: 0;
                    margin-bottom: 16px;
                }
                
                .checklist-item {
                    display: flex;
                    align-items: flex-start;
                    margin-bottom: 6px;
                    line-height: 1.4;
                }
                
                .checklist-item input[type="checkbox"] {
                    margin: 4px 10px 0 0;
                    cursor: default;
                    accent-color: #0969da;
                    width: 1.2em;
                    height: 1.2em;
                    flex-shrink: 0;
                }
                
                ul, ol {
                    padding-left: 2em;
                    margin-bottom: 16px;
                }
                
                code {
                    padding: 0.2em 0.4em;
                    font-size: 85%;
                    background-color: var(--code-bg);
                    border-radius: 6px;
                    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
                }
                
                pre {
                    padding: 16px;
                    overflow: auto;
                    font-size: 85%;
                    background-color: var(--code-bg);
                    border-radius: 6px;
                    margin-bottom: 16px;
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 8px;
                    margin: 16px 0;
                }
            </style>
        </head>
        <body>
            <div id="content">
                \(convertedMarkdown)
            </div>
            
            <script src="WebResources/lib/mermaid/mermaid.min.js"></script>
            <script>
                function initMermaid() {
                    try {
                        if (typeof mermaid !== 'undefined') {
                            mermaid.initialize({
                                startOnLoad: false,
                                theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral',
                                securityLevel: 'loose',
                                look: 'handDrawn',
                                fontFamily: 'Kalam'
                            });
                            mermaid.run({
                                querySelector: '.mermaid'
                            }).catch(err => {
                                console.error('Mermaid render error:', err);
                            });
                        } else {
                            console.error('Mermaid library not found');
                        }
                    } catch (e) {
                        console.error('initMermaid error:', e);
                    }
                }
                
                // Wait for both script and DOM
                if (document.readyState === 'complete') {
                    initMermaid();
                } else {
                    window.addEventListener('load', initMermaid);
                }
                
                // Backup trigger
                setTimeout(initMermaid, 500);
            </script>
        </body>
        </html>
        """
    }
    
    private func convertMarkdownToHTML(_ markdown: String) -> String {
        var html = markdown
        
        // 1. Protect Mermaid blocks
        var mermaidBlocks: [String] = []
        let mermaidPattern = "```mermaid[\\s\\n]*?([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: mermaidPattern, options: []) {
            let nsString = html as NSString
            let results = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for result in results.reversed() {
                let blockRange = result.range(at: 1)
                let fullRange = result.range(at: 0)
                let content = nsString.substring(with: blockRange)
                mermaidBlocks.insert(content, at: 0)
                
                let placeholder = "<!--MERMAID_PLACEHOLDER_\(mermaidBlocks.count - 1)-->"
                html = (html as NSString).replacingCharacters(in: fullRange, with: placeholder)
            }
        }
        
        // Basic Markdown transformations (simplified for speed/parsing safety)
        
        // Headers (prioritize longer hashes)
        html = html.replacingOccurrences(of: "######\\s+(.+)", with: "<h6>$1</h6>", options: .regularExpression)
        html = html.replacingOccurrences(of: "#####\\s+(.+)", with: "<h5>$1</h5>", options: .regularExpression)
        html = html.replacingOccurrences(of: "####\\s+(.+)", with: "<h4>$1</h4>", options: .regularExpression)
        html = html.replacingOccurrences(of: "###\\s+(.+)", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "##\\s+(.+)", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "#\\s+(.+)", with: "<h1>$1</h1>", options: .regularExpression)
        
        // Bold/Italic
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        
        // Images/Links
        html = html.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\(([^\\)]*)\\)", with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
        html = html.replacingOccurrences(of: "\\[([^\\]]*)\\]\\(([^\\)]*)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        
        // Code
        html = html.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        html = html.replacingOccurrences(of: "```([\\s\\S]*?)```", with: "<pre><code>$1</code></pre>", options: .regularExpression)
        
        // Structural Line-by-Line Processing
        let lines = html.components(separatedBy: .newlines)
        var resultHtml = ""
        var inChecklist = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Checklist Item detection
            // Note: We use raw string check because we haven't transformed them yet in convertMarkdownToHTML
            let isUnchecked = trimmed.hasPrefix("- [ ]")
            let isChecked = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
            
            if isUnchecked || isChecked {
                if !inChecklist {
                    resultHtml += "<ul class=\"has-checklist\">"
                    inChecklist = true
                }
                
                let content = trimmed.replacingCharacters(in: ..<trimmed.index(trimmed.startIndex, offsetBy: 5), with: "")
                let input = isChecked ? "<input type=\"checkbox\" checked disabled>" : "<input type=\"checkbox\" disabled>"
                resultHtml += "<li class=\"checklist-item\">\(input) \(content)</li>"
                continue
            }
            
            // Not a checklist item
            if inChecklist {
                resultHtml += "</ul>"
                inChecklist = false
            }
            
            if trimmed.isEmpty {
                resultHtml += "<br>"
            } else if trimmed.hasPrefix("<h") || trimmed.hasPrefix("<pre") || trimmed.hasPrefix("<div") || trimmed.hasPrefix("<!--") {
                resultHtml += line
            } else {
                resultHtml += "<p>\(line)</p>"
            }
        }
        
        if inChecklist {
            resultHtml += "</ul>"
        }
        
        html = resultHtml
        
        // Restore Mermaid with the correct class
        for (index, content) in mermaidBlocks.enumerated() {
            let placeholder = "<!--MERMAID_PLACEHOLDER_\(index)-->"
            let div = "<div class=\"mermaid\">\(content)</div>"
            html = html.replacingOccurrences(of: placeholder, with: div)
        }
        
        return html
    }
}
