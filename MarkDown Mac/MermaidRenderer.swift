import AppKit
import WebKit

class MermaidRenderer: NSObject {
    static let shared = MermaidRenderer()
    private var webView: WKWebView!
    private var completionHandlers: [String: (NSImage?) -> Void] = [:]
    
    private override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
        
        // Load Mermaid HTML template
        loadMermaidTemplate()
    }
    
    private func loadMermaidTemplate() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
            <link href="https://fonts.googleapis.com/css2?family=Kalam:wght@300;400;700&display=swap" rel="stylesheet">
            <style>
                body {
                    margin: 0;
                    padding: 20px;
                    background: transparent;
                    font-family: 'Kalam', cursive;
                }
                #diagram {
                    display: inline-block;
                }
                /* Ensure all Mermaid text uses the handwritten font */
                .mermaid text {
                    font-family: 'Kalam', cursive !important;
                }
            </style>
        </head>
        <body>
            <div id="diagram"></div>
            <script>
                mermaid.initialize({ 
                    startOnLoad: false,
                    theme: 'neutral',
                    securityLevel: 'loose',
                    look: 'handDrawn',
                    fontFamily: 'Kalam'
                });
                
                window.renderMermaid = async function(code, id) {
                    try {
                        const element = document.getElementById('diagram');
                        element.innerHTML = code;
                        
                        const { svg } = await mermaid.render('mermaid-' + id, code);
                        element.innerHTML = svg;
                        
                        // Wait for rendering
                        await new Promise(resolve => setTimeout(resolve, 100));
                        
                        // Get dimensions
                        const svgElement = element.querySelector('svg');
                        const width = svgElement.width.baseVal.value;
                        const height = svgElement.height.baseVal.value;
                        
                        window.webkit.messageHandlers.mermaidCallback.postMessage({
                            id: id,
                            success: true,
                            width: width,
                            height: height
                        });
                    } catch (error) {
                        window.webkit.messageHandlers.mermaidCallback.postMessage({
                            id: id,
                            success: false,
                            error: error.toString()
                        });
                    }
                }
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    func renderDiagram(_ mermaidCode: String, completion: @escaping (NSImage?) -> Void) {
        let id = UUID().uuidString
        completionHandlers[id] = completion
        
        // Add message handler if not already added
        if !webView.configuration.userContentController.userScripts.isEmpty {
            webView.configuration.userContentController.removeAllUserScripts()
        }
        
        webView.configuration.userContentController.add(self, name: "mermaidCallback")
        
        // Escape the mermaid code for JavaScript
        let escapedCode = mermaidCode
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        
        let script = "window.renderMermaid('\(escapedCode)', '\(id)');"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("Mermaid render error: \(error)")
                    completion(nil)
                    self.completionHandlers.removeValue(forKey: id)
                }
            }
        }
        
        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.completionHandlers[id] != nil {
                print("Mermaid render timeout")
                completion(nil)
                self.completionHandlers.removeValue(forKey: id)
            }
        }
    }
    
    private func captureWebViewAsImage(completion: @escaping (NSImage?) -> Void) {
        webView.takeSnapshot(with: nil) { image, error in
            if let error = error {
                print("Snapshot error: \(error)")
                completion(nil)
                return
            }
            completion(image)
        }
    }
}

extension MermaidRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Mermaid template loaded")
    }
}

extension MermaidRenderer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mermaidCallback",
              let dict = message.body as? [String: Any],
              let id = dict["id"] as? String,
              let success = dict["success"] as? Bool else {
            return
        }
        
        if success {
            // Capture the rendered diagram
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.captureWebViewAsImage { image in
                    if let handler = self.completionHandlers[id] {
                        handler(image)
                        self.completionHandlers.removeValue(forKey: id)
                    }
                }
            }
        } else {
            if let handler = completionHandlers[id] {
                handler(nil)
                completionHandlers.removeValue(forKey: id)
            }
        }
    }
}
