//
//  SwiftWebInput.swift
//
//  Created by Sulaiman Khan Ghori on 6/20/24.
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
  private let textLengthForLargeTextFile: Int

  public init(
    webInputViewModel: WebInputViewModel,
    onSubmit: @escaping () -> Void,
    inputPlaceholder: String,
    minTextHeight: CGFloat = 40,
    maxTextHeight: CGFloat = 300,
    textLengthForLargeTextFile: Int = 2000
  ) {
    self._webInputViewModel = ObservedObject(wrappedValue: webInputViewModel)
    self.onSubmit = onSubmit
    self.inputPlaceholder = inputPlaceholder
    self.minTextHeight = minTextHeight
    self.maxTextHeight = maxTextHeight
    self.textLengthForLargeTextFile = textLengthForLargeTextFile
  }

  public var body: some View {
    // let _ = Self._printChanges()
    WebInputViewRepresentable(
      webInputViewModel: webInputViewModel,
      onSubmit: onSubmit,
      inputPlaceholder: inputPlaceholder,
      textLengthForLargeTextFile: textLengthForLargeTextFile
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

  // File handling properties
  @Published public var pastedFileURLs: [URL] = []
  @Published public var largeTextFileURL: URL?

  // Callbacks for event handling
  public var onFilePasted: (([URL]) -> Void)?

  // Focus handling
  @Published public var isFocused: Bool? = nil

  public init() {}

  func clearText() {
    self.text = ""
  }
}

struct WebInputViewRepresentable: NSViewRepresentable {
  private var webInputViewModel: WebInputViewModel
  private var onSubmit: () -> Void
  private var inputPlaceholder: String
  private var textLengthForLargeTextFile: Int

  init(
    webInputViewModel: WebInputViewModel, onSubmit: @escaping () -> Void,
    inputPlaceholder: String,
    textLengthForLargeTextFile: Int
  ) {
    self.webInputViewModel = webInputViewModel
    self.onSubmit = onSubmit
    self.inputPlaceholder = inputPlaceholder
    self.textLengthForLargeTextFile = textLengthForLargeTextFile
  }

  func makeNSView(context: Context) -> WKWebView {
    let webView = CustomWebView(webInputViewModel: webInputViewModel)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator

    // Set transparent background
    webView.setValue(false, forKey: "drawsBackground")

    // Add user script message handlers
    let contentController = webView.configuration.userContentController
    contentController.add(context.coordinator, name: "textChanged")
    contentController.add(context.coordinator, name: "heightChanged")
    contentController.add(context.coordinator, name: "submit")
    contentController.add(context.coordinator, name: "largeTextPasted")
    contentController.add(context.coordinator, name: "consoleLogHandler")
    contentController.add(context.coordinator, name: "filePasted")

    webView.loadHTMLString(htmlContent, baseURL: nil)

    return webView
  }

  func updateNSView(_ nsView: WKWebView, context _: Context) {
    nsView.evaluateJavaScript(
      "updateEditorContent(`\(webInputViewModel.text.replacingOccurrences(of: "`", with: "\\`"))`)",
      completionHandler: nil)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, WKNavigationDelegate, @preconcurrency WKScriptMessageHandler,
    WKUIDelegate
  {
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
        case "largeTextPasted":
          if let text = message.body as? String {
            do {
              let tempDir = FileManager.default.temporaryDirectory
              let fileURL = tempDir.appendingPathComponent(
                "pasted_text_\(UUID().uuidString).txt")
              try text.write(to: fileURL, atomically: true, encoding: .utf8)
              self.parent.webInputViewModel.largeTextFileURL = fileURL
              self.parent.webInputViewModel.onFilePasted?([fileURL])
              self.parent.webInputViewModel.pastedFileURLs.append(fileURL)
            } catch {
              print("Error writing large text to file: \(error)")
            }
          }
        case "consoleLogHandler":
          print("JS Console - SwiftWebInput: \(String(describing: message.body))")
        case "filePasted":
          let pasteboard = NSPasteboard.general
          // Read all pasteboard objects and print their classes for debugging purposes
          let pasteboardItems = pasteboard.pasteboardItems
          if let items = pasteboardItems {
            var extractedURLs: [URL] = []
            for item in items {
              for type in item.types {
                if let data = item.data(forType: type) {
                  // Attempt to extract URL from common file types
                  if type == .fileURL, let urlString = String(data: data, encoding: .utf8), let url = URL(string: urlString) {
                    extractedURLs.append(url)
                  } else if type == .png {
                    // Handle direct PNG data by saving to a temporary file
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent("pasted_image_\(UUID().uuidString).png")
                    do {
                      try data.write(to: fileURL)
                      extractedURLs.append(fileURL)
                    } catch {
                      print("Error saving PNG data to file: \(error)")
                    }
                  } else if type == .tiff {
                    // Handle TIFF data by saving to a temporary file
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent("pasted_image_\(UUID().uuidString).tiff")
                    do {
                      try data.write(to: fileURL)
                      extractedURLs.append(fileURL)
                    } catch {
                      print("Error saving TIFF data to file: \(error)")
                    }
                  } else if type == .pdf {
                    // Handle PDF data by saving to a temporary file
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent("pasted_image_\(UUID().uuidString).pdf")
                    do {
                      try data.write(to: fileURL)
                      extractedURLs.append(fileURL)
                    } catch {
                      print("Error saving PDF data to file: \(error)")
                    }
                  } else if type == .fileContents {
                    // Handle file URL data by saving to a temporary file
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent("pasted_file_\(UUID().uuidString).txt")
                    do {
                      try data.write(to: fileURL)
                      extractedURLs.append(fileURL)
                    } catch {
                      print("Error saving file contents to file: \(error)")
                    }
                  } else {
                    print("Pasteboard item type: \(type), no data available")
                  }
                }
              }
            }
            if !extractedURLs.isEmpty {
              self.parent.webInputViewModel.pastedFileURLs = extractedURLs
              self.parent.webInputViewModel.onFilePasted?(extractedURLs)
            } else if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
              self.parent.webInputViewModel.pastedFileURLs = fileURLs
              self.parent.webInputViewModel.onFilePasted?(fileURLs)
            }
          } else {
            print("No pasteboard items available")
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
              self.parent.webInputViewModel.pastedFileURLs = fileURLs
              self.parent.webInputViewModel.onFilePasted?(fileURLs)
            }
          }
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
                  pointer-events: none;
              }

              @media (prefers-color-scheme: light) {
                  #editor:empty:before {
                      color: rgba(0, 0, 0, 0.5);
                  }
              }

              @media (prefers-color-scheme: dark) {
                  #editor:empty:before {
                      color: rgba(255, 255, 255, 0.5);
                  }
              }
              input, textarea, div[contenteditable] {
                  caret-color: \(accentColorStr);
              }
          </style>
      </head>
      <body>
          <div id="editor" contenteditable="true" placeholder="\(placeholderText)" autocomplete="off" autocorrect="off" autocapitalize="off"></div>
          <script>
          (function() {
              const originalConsoleLog = console.log;
              console.log = function(...args) {
                  originalConsoleLog.apply(console, args);
                  if (window.webkit?.messageHandlers?.consoleLogHandler) {
                      window.webkit.messageHandlers.consoleLogHandler.postMessage(args.join(' '));
                  }
              };
          })();
          // Add debounce utility function
          function debounce(func, wait) {
              let timeout;
              return function executedFunction(...args) {
                  const later = () => {
                      clearTimeout(timeout);
                      func(...args);
                  };
                  clearTimeout(timeout);
                  timeout = setTimeout(later, wait);
              };
          }
          const editor = document.getElementById('editor');
          let lastHeight = 0;

          // Wrap updateHeight with debounce
          const debouncedUpdateHeight = debounce(updateHeight, 1);

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
                  debouncedUpdateHeight();
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
              debouncedUpdateHeight();
          }

          editor.addEventListener('input', function() {
              if (editor.innerHTML === '<br>') {
                  editor.innerHTML = '';
              }
              webkit.messageHandlers.textChanged.postMessage(editor.innerText);
              debouncedUpdateHeight();
          });

          editor.addEventListener('paste', function(e) {
              e.preventDefault();
              if (e.clipboardData.files && e.clipboardData.files.length > 0) {
                  webkit.messageHandlers.filePasted.postMessage('');
              } else {
                  const text = e.clipboardData.getData('text/plain').replace(/\t/g, '    ');
                  if (text.length > \(textLengthForLargeTextFile)) {
                      webkit.messageHandlers.largeTextPasted.postMessage(text);
                  } else {
                      document.execCommand('insertText', false, text);
                      webkit.messageHandlers.textChanged.postMessage(editor.innerText);
                      debouncedUpdateHeight();
                  }
              }
          });

          editor.addEventListener('keydown', function(e) {
              if (e.key === 'Enter') {
                  e.preventDefault(); // Prevent default more aggressively
                  if (!e.shiftKey) {
                      webkit.messageHandlers.submit.postMessage('');
                      resetEditor();
                  } else {
                      document.execCommand('insertLineBreak');
                      debouncedUpdateHeight();
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
              debouncedUpdateHeight();
          }).observe(editor, {
              attributes: true,
              childList: true,
              subtree: true,
              characterData: true
          });

          debouncedUpdateHeight();
          </script>
      </body>
      </html>
      """
  }

  class CustomWebView: WKWebView {
    weak var webInputViewModel: WebInputViewModel?
    private var cancellables = Set<AnyCancellable>()

    init(webInputViewModel: WebInputViewModel) {
      self.webInputViewModel = webInputViewModel
      super.init(frame: .zero, configuration: .init())
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
    }

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
      NotificationCenter.default.post(name: .commandKeyPressed, object: nil, userInfo: ["isPressed": event.modifierFlags.contains(.command)])
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
            let pasteboard = NSPasteboard.general
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)
              as? [URL],
              !fileURLs.isEmpty
            {
              webInputViewModel?.pastedFileURLs = fileURLs
              webInputViewModel?.onFilePasted?(fileURLs)
              return true
            } else if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
              return true
            }
            return false
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

      NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: nil)

      NotificationCenter.default.addObserver(self, selector: #selector(requestFocus), name: NSNotification.Name("RequestWebInputFocus"), object: nil)

      // Add observer for focus state changes from SwiftUI
      if let viewModel = webInputViewModel {
        viewModel.$isFocused.sink { [weak self] isFocused in
          if let isFocused = isFocused {
            if isFocused {
              self?.evaluateJavaScript("document.getElementById('editor').focus();", completionHandler: nil)
              Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                viewModel.isFocused = nil
              }
            }
          }
        }.store(in: &cancellables)
      }
    }

    @objc private func windowDidBecomeKey() {
      self.evaluateJavaScript("document.getElementById('editor').focus();", completionHandler: nil)
    }

    @objc private func requestFocus() {
      self.evaluateJavaScript("document.getElementById('editor').focus();", completionHandler: nil)
    }

    deinit {
      NotificationCenter.default.removeObserver(self)
    }
  }
}

extension Notification.Name {
  static let commandKeyPressed = Notification.Name("commandKeyPressed")
}
