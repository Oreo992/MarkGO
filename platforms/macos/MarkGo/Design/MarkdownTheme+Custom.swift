import SwiftUI
import MarkdownUI
import AppKit
import WebKit

extension Theme {
    /// Reading theme aligned with the iOS app: editorial paper background,
    /// quiet code blocks, and Chinese-aware spacing.
    static let custom = Theme.reader(mode: .clear, scale: 1.0)

    /// Returns a copy of the editorial reading theme whose body font scales
    /// uniformly. MarkdownUI ignores SwiftUI's `.font` modifier on
    /// `Markdown` views, so we have to bake the size into the theme.
    static func scaled(_ factor: CGFloat) -> Theme {
        .reader(mode: .clear, scale: factor)
    }

    static func reader(
        mode: ReadingMode,
        scale factor: CGFloat,
        includeCodeCopy: Bool = true,
        renderMermaid: Bool = true
    ) -> Theme {
        let accent = mode.accent
        let bodySize: CGFloat = {
            switch mode {
            case .report: 16.5
            case .paper, .lesson: 17.5
            default: 16.5
            }
        }()
        let paragraphBottom: Double = {
            switch mode {
            case .report: 24
            case .lesson: 20
            case .cards: 14
            default: 18
            }
        }()

        return Theme()
        .text {
            ForegroundColor(Color(red: 0.12, green: 0.13, blue: 0.13))
            BackgroundColor(.clear)
            FontSize(bodySize * factor)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(accent)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(Color(red: 0.47, green: 0.22, blue: 0.13))
            BackgroundColor(Color(red: 0.92, green: 0.89, blue: 0.82))
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(mode == .report ? 0.44 : 0.34))
                .markdownMargin(top: 0, bottom: paragraphBottom)
        }
        .heading1 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: mode == .report ? 20 : 12, bottom: mode == .report ? 30 : 22)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(mode == .cards ? 1.72 : 2.10))
                }
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: mode == .report ? 14 : 10) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.12))
                    .markdownTextStyle {
                        FontWeight(mode == .report ? .bold : .semibold)
                        FontSize(.em(mode == .report ? 1.60 : 1.52))
                    }

                Rectangle()
                    .fill(accent.opacity(mode == .report ? 0.44 : 0.32))
                    .frame(width: mode == .report ? 76 : 44, height: mode == .report ? 3 : 2)
            }
            .markdownMargin(top: mode == .report ? 38 : 28, bottom: mode == .report ? 24 : 16)
        }
        .heading3 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.14))
                .markdownMargin(top: 22, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.18))
                }
        }
        .heading4 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 18, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                }
        }
        .heading5 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.94))
                }
        }
        .heading6 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.86))
                    ForegroundColor(.secondary)
                }
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 14) {
                Capsule()
                    .fill(accent)
                    .frame(width: 4)

                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(Color(red: 0.30, green: 0.31, blue: 0.30))
                    }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                accent.opacity(mode == .report ? 0.075 : 0.10),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 4, bottom: mode == .report ? 24 : 18)
        }
        .codeBlock { configuration in
            if renderMermaid && isMermaidLanguage(configuration.language) {
                MermaidBlockView(source: configuration.content, accent: accent)
                    .markdownMargin(top: 2, bottom: mode == .report ? 28 : 20)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(configuration.language?.uppercased() ?? "CODE")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(accent)
                        Spacer()
                        if includeCodeCopy {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(configuration.content, forType: .string)
                            } label: {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(accent.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    ScrollView(.horizontal) {
                        configuration.label
                            .fixedSize(horizontal: false, vertical: true)
                            .relativeLineSpacing(.em(0.30))
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                                FontSize(.em(mode == .report ? 0.82 : 0.86))
                                ForegroundColor(Color(red: 0.17, green: 0.19, blue: 0.19))
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 16)
                    }
                }
                .background(
                    Color(red: 0.90, green: 0.88, blue: 0.82).opacity(mode == .report ? 0.72 : 1),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.20), lineWidth: 1)
                )
                .markdownMargin(top: 2, bottom: mode == .report ? 28 : 20)
            }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.18))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .imageScale(.small)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color(red: 0.76, green: 0.72, blue: 0.64).opacity(0.7)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(
                        Color(red: 0.99, green: 0.98, blue: 0.95),
                        Color(red: 0.94, green: 0.92, blue: 0.86)
                    )
                )
                .markdownMargin(top: 0, bottom: 20)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .relativeLineSpacing(.em(0.24))
        }
        .thematicBreak {
            Rectangle()
                .fill(accent.opacity(0.22))
                .frame(height: 1)
                .markdownMargin(top: 26, bottom: 26)
        }
    }
}

func isMermaidLanguage(_ language: String?) -> Bool {
    guard let language else { return false }
    let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "mermaid" || normalized == "mmd"
}

private struct MermaidBlockView: View {
    let source: String
    let accent: Color

    @State private var height: CGFloat = 260
    @State private var zoom: CGFloat = 1.0

    private let minimumScale: CGFloat = 0.55
    private let maximumScale: CGFloat = 2.4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MERMAID")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(accent)
                Spacer()
                Button {
                    adjustZoom(-0.15)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.caption.weight(.bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .disabled(zoom <= minimumScale)
                .help("缩小 Mermaid 图")

                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.caption2.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .frame(width: 42)

                Button {
                    adjustZoom(0.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption.weight(.bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .disabled(zoom >= maximumScale)
                .help("放大 Mermaid 图")

                Button {
                    zoom = 1.0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .help("重置 Mermaid 缩放")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(source, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            MermaidWebView(source: source, zoom: zoom, height: $height)
                .frame(minHeight: 180, idealHeight: height, maxHeight: height)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
        .background(
            Color(red: 0.96, green: 0.955, blue: 0.925),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.20), lineWidth: 1)
        )
    }

    private func adjustZoom(_ delta: CGFloat) {
        zoom = min(maximumScale, max(minimumScale, zoom + delta))
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let zoom: CGFloat
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "markgo")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.source = source
        context.coordinator.zoom = zoom
        webView.loadHTMLString(htmlDocument(for: source), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.source != source {
            context.coordinator.source = source
            context.coordinator.zoom = zoom
            webView.loadHTMLString(htmlDocument(for: source), baseURL: nil)
            return
        }

        guard context.coordinator.zoom != zoom else { return }
        context.coordinator.zoom = zoom
        let jsZoom = String(format: "%.3f", Double(zoom))
        webView.evaluateJavaScript("setZoom(\(jsZoom));", completionHandler: nil)
    }

    private func htmlDocument(for source: String) -> String {
        let encodedSource = jsonString(source)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light; }
        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
          font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
          color: #1d2324;
          overflow: auto;
        }
        body { padding: 12px; box-sizing: border-box; }
        #diagram {
          display: inline-block;
          min-width: 100%;
          transform-origin: top center;
          transition: transform 120ms ease;
          will-change: transform;
        }
        svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        pre {
          white-space: pre-wrap;
          word-break: break-word;
          margin: 0;
          padding: 14px 16px;
          border-radius: 12px;
          background: rgba(180, 80, 50, 0.10);
          color: #7a3526;
          font: 13px ui-monospace, "SF Mono", Menlo, monospace;
          line-height: 1.55;
        }
        </style>
        </head>
        <body>
        <div id="diagram"></div>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <script>
        const source = \(encodedSource);
        var currentZoom = 1;

        function postHeight() {
          const diagram = document.getElementById("diagram");
          const bounds = diagram ? diagram.getBoundingClientRect() : document.documentElement.getBoundingClientRect();
          const height = Math.max(180, Math.ceil(bounds.height + 24));
          window.webkit.messageHandlers.markgo.postMessage({ type: "height", height });
        }

        async function renderDiagram() {
          try {
            mermaid.initialize({
              startOnLoad: false,
              securityLevel: "strict",
              theme: "base",
              themeVariables: {
                fontFamily: "-apple-system, BlinkMacSystemFont, PingFang SC, sans-serif",
                primaryColor: "#e7f7f4",
                primaryTextColor: "#1d2324",
                primaryBorderColor: "#18b7ad",
                lineColor: "#18b7ad",
                secondaryColor: "#fff7ea",
                tertiaryColor: "#f6efe4"
              }
            });
            const result = await mermaid.render(makeDiagramId(), source);
            document.getElementById("diagram").innerHTML = result.svg;
            requestAnimationFrame(postHeight);
            setTimeout(postHeight, 120);
          } catch (error) {
            document.body.innerHTML = "<pre>Mermaid parse error\\n\\n" + escapeText(String(error)) + "\\n\\n" + escapeText(source) + "</pre>";
            requestAnimationFrame(postHeight);
          }
        }

        function escapeText(value) {
          return value
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
        }

        function makeDiagramId() {
          return "markgo-mermaid-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1000000).toString(36);
        }

        function setZoom(value) {
          currentZoom = Math.max(0.55, Math.min(2.4, Number(value) || 1));
          const diagram = document.getElementById("diagram");
          if (!diagram) return;
          diagram.style.transform = "scale(" + currentZoom + ")";
          requestAnimationFrame(postHeight);
          setTimeout(postHeight, 120);
        }

        window.addEventListener("load", async function() {
          await renderDiagram();
          setZoom(\(String(format: "%.3f", Double(zoom))));
        });
        </script>
        </body>
        </html>
        """
    }

    private func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
        let encoded = String(data: data, encoding: .utf8) ?? #""""#
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var source = ""
        var zoom: CGFloat = 1.0
        private var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any],
                  payload["type"] as? String == "height",
                  let rawHeight = payload["height"] as? Double else { return }

            DispatchQueue.main.async {
                self.height.wrappedValue = min(900, max(180, CGFloat(rawHeight)))
            }
        }
    }
}
