//
//  SwiftWebInput.swift
//
//  Created by Sulaiman Ghori on 6/20/24.
//

import Combine
import SwiftUI
import WebKit

public struct SwiftWebInputView: View {
    @ObservedObject private(set) var webInputViewModel: WebInputViewModel
    private let onSubmit: () -> Void
    private let inputPlaceholder: String
    private let minTextHeight: CGFloat
    private let maxTextHeight: CGFloat

    public init(
        webInputViewModel: WebInputViewModel,
        onSubmit: @escaping () -> Void,
        inputPlaceholder: String,
        minTextHeight: CGFloat = 40,
        maxTextHeight: CGFloat = 300
    ) {
        self._webInputViewModel = ObservedObject(wrappedValue: webInputViewModel)
        self.onSubmit = onSubmit
        self.inputPlaceholder = inputPlaceholder
        self.minTextHeight = minTextHeight
        self.maxTextHeight = maxTextHeight
    }

    public var body: some View {
        let _ = Self._printChanges()
        WebInputViewRepresentable(
            webInputViewModel: webInputViewModel,
            onSubmit: onSubmit,
            inputPlaceholder: inputPlaceholder
        )
        .frame(height: max(minTextHeight, min(webInputViewModel.height, maxTextHeight)))
    }

    // Test Helpers
    #if DEBUG
        @MainActor public func getWebInputViewModelForTesting() -> WebInputViewModel {
            return webInputViewModel
        }

        public func getInputPlaceholderForTesting() -> String {
            return inputPlaceholder
        }
    #endif
}

public final class WebInputViewModel: ObservableObject {
    // The text content of the chat field
    @Published public var text: String = ""

    /// The height of the text field.
    @Published public var height: CGFloat = 52

    public init() {}

    func clearText() {
        self.text = ""
    }
}

struct WebInputViewRepresentable: NSViewRepresentable {
    private var webInputViewModel: WebInputViewModel
    private var onSubmit: () -> Void
    private var inputPlaceholder: String

    init(
        webInputViewModel: WebInputViewModel, onSubmit: @escaping () -> Void,
        inputPlaceholder: String
    ) {
        self.webInputViewModel = webInputViewModel
        self.onSubmit = onSubmit
        self.inputPlaceholder = inputPlaceholder
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = CustomWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Set transparent background
        webView.setValue(false, forKey: "drawsBackground")

        // Add user script message handlers
        let contentController = webView.configuration.userContentController
        contentController.add(context.coordinator, name: "textChanged")
        contentController.add(context.coordinator, name: "heightChanged")
        contentController.add(context.coordinator, name: "submit")

        webView.loadHTMLString(htmlContent, baseURL: nil)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context _: Context) {
        nsView.evaluateJavaScript(
            "updateEditorContent(`\(webInputViewModel.text.replacingOccurrences(of: "`", with: "\\`"))`)",
            completionHandler: nil)
    }

    @MainActor private func setFocus(_ webView: WKWebView) {
        webView.evaluateJavaScript(
            "document.getElementById('editor').focus();", completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, @preconcurrency WKScriptMessageHandler, WKUIDelegate {
        var parent: WebInputViewRepresentable
        var cancellables = Set<AnyCancellable>()

        init(_ parent: WebInputViewRepresentable) {
            self.parent = parent
        }

        @MainActor func userContentController(
            _: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "textChanged":
                if let text = message.body as? String {
                    self.parent.webInputViewModel.text = text
                }
            case "heightChanged":
                if let height = message.body as? CGFloat {
                    self.parent.webInputViewModel.height = height
                }
            case "submit":
                self.parent.onSubmit()
            default:
                break
            }
        }
    }

    private var htmlContent: String {
        // Fetch the system's accent color
        let accentColor = NSColor.controlAccentColor.usingColorSpace(.deviceRGB)
        let accentColorStr = String(
            format: "rgba(%d, %d, %d, %.2f)", Int(accentColor!.redComponent * 255.0),
            Int(accentColor!.greenComponent * 255.0), Int(accentColor!.blueComponent * 255.0),
            accentColor!.alphaComponent)

        // Escape the placeholder text to prevent HTML injection
        let placeholderText = (inputPlaceholder)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")

        return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
                <style>
                    :root {
                        color-scheme: light dark !important;
                    }

                    body, html {
                        margin: 0;
                        padding: 0;
                        height: 100%;
                        background-color: transparent;
                        color: -apple-system-label;
                        font-family: system-ui;
                        font-size: 11pt;
                        line-height: 1.5;
                    }

                    body::-webkit-scrollbar {
                        display: none !important;
                    }

                    #editor {
                        min-height: 20px;
                        padding: 10px;
                        outline: none;
                        word-wrap: break-word;
                        overflow-y: hidden;
                        background-color: transparent;
                        white-space: pre-wrap;
                    }
                    #editor:empty:before {
                        content: attr(placeholder);
                        color: gray;
                        pointer-events: none;
                    }
                    input, textarea, div[contenteditable] {
                        caret-color: \(accentColorStr);
                    }
                </style>
            </head>
            <body>
                <div id="editor" contenteditable="true" placeholder="\(placeholderText)"></div>
                <script>
                const editor = document.getElementById('editor');
                let lastHeight = 0;

                function updateHeight() {
                    const newHeight = editor.scrollHeight;
                    if (newHeight !== lastHeight) {
                        lastHeight = newHeight;
                        webkit.messageHandlers.heightChanged.postMessage(newHeight);
                    }
                }

                function updateEditorContent(content) {
                    if (editor.innerText !== content) {
                        editor.innerText = content;
                        updateHeight();
                        placeCaretAtEnd();
                    }
                }

                function placeCaretAtEnd() {
                    const range = document.createRange();
                    const selection = window.getSelection();
                    range.selectNodeContents(editor);
                    range.collapse(false);
                    selection.removeAllRanges();
                    selection.addRange(range);
                    editor.focus();
                }

                function resetEditor() {
                    editor.innerText = '';
                    updateHeight();
                }

                editor.addEventListener('input', function() {
                    if (editor.innerHTML === '<br>') {
                        editor.innerHTML = '';
                    }
                    webkit.messageHandlers.textChanged.postMessage(editor.innerText);
                    updateHeight();
                });

                editor.addEventListener('paste', function(e) {
                    e.preventDefault();
                    const text = e.clipboardData.getData('text/plain');
                    document.execCommand('insertText', false, text);
                    webkit.messageHandlers.textChanged.postMessage(editor.innerText);
                    updateHeight();
                });

                editor.addEventListener('keydown', function(e) {
                    if (e.key === 'Enter') {
                        e.preventDefault(); // Prevent default more aggressively
                        if (!e.shiftKey) {
                            webkit.messageHandlers.submit.postMessage('');
                            resetEditor();
                        } else {
                            document.execCommand('insertLineBreak');
                            updateHeight();
                        }
                    }
                });

                // Ensure editor always has content
                editor.addEventListener('blur', function() {
                    if (editor.innerHTML === '') {
                        editor.innerHTML = '<br>';
                    }
                });

                new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                        if (mutation.type === 'childList') {
                            const br = editor.querySelector('br');
                            if (br && br.parentNode === editor) {
                                br.remove();
                            }
                        }
                    });
                    updateHeight();
                }).observe(editor, {
                    attributes: true,
                    childList: true,
                    subtree: true,
                    characterData: true
                });

                updateHeight();
                </script>
            </body>
            </html>
            """
    }

    class CustomWebView: WKWebView {
        override var intrinsicContentSize: CGSize {
            .init(width: super.intrinsicContentSize.width, height: .zero)
        }

        override func scrollWheel(with event: NSEvent) {
            super.scrollWheel(with: event)
            nextResponder?.scrollWheel(with: event)
        }

        override func willOpenMenu(_ menu: NSMenu, with _: NSEvent) {
            menu.items.removeAll { $0.identifier == .init("WKMenuItemIdentifierReload") }
        }

        // Command forwarding
        override func flagsChanged(with event: NSEvent) {
            super.flagsChanged(with: event)

            // Forward the event to the window
            if let window = self.window {
                window.flagsChanged(with: event)
            }

            // Post notification for command key state
            NotificationCenter.default.post(
                name: .commandKeyPressed, object: nil,
                userInfo: ["isPressed": event.modifierFlags.contains(.command)])
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command) {
                NotificationCenter.default.post(
                    name: .commandKeyPressed, object: nil, userInfo: ["isPressed": false])

                // Forward the event to the window
                if let window = self.window {
                    window.flagsChanged(with: event)
                }

                switch event.charactersIgnoringModifiers {
                case "x":
                    if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                        return true
                    }
                case "c":
                    if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                        return true
                    }
                case "v":
                    if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                        return true
                    }
                case "a":
                    if NSApp.sendAction(
                        #selector(NSStandardKeyBindingResponding.selectAll(_:)), to: nil, from: self
                    ) {
                        return true
                    }
                default:
                    break
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification, object: nil)
        }

        @objc private func windowDidBecomeKey() {
            self.evaluateJavaScript(
                "document.getElementById('editor').focus();", completionHandler: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

extension Notification.Name {
    static let commandKeyPressed = Notification.Name("commandKeyPressed")
}
