import SwiftUI
import WebKit

/// In-app single-photo view for a specific aircraft registration via planespotters.net.
///
/// URLSession is blocked by Cloudflare (HTTP 403) due to iOS TLS fingerprint differences.
/// WKWebView uses WebKit's full browser stack, passing all Cloudflare bot checks.
/// A local HTML page runs JS fetch() to retrieve the first photo and render it inline.
///
/// Pre-warming WKWebView in the background doesn't work on iOS — the OS immediately kills
/// WebContent processes that aren't attached to a visible view. Instead we delay adding
/// the WKWebView by 350ms so the sheet slide-in animation plays first, then show a
/// ProgressView while WebKit initialises and the JS fetch completes.
struct AircraftPhotoView: View {
    let registration: String

    @Environment(\.dismiss) private var dismiss
    @State private var showWebView = false
    @State private var htmlReady = false

    var body: some View {
        NavigationStack {
            ZStack {
                if showWebView {
                    PhotoWebView(registration: registration, htmlReady: $htmlReady)
                        .ignoresSafeArea(edges: .bottom)
                        .opacity(htmlReady ? 1 : 0)
                }

                if !htmlReady {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.easeIn(duration: 0.2), value: htmlReady)
            .navigationTitle(registration)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            // Let the sheet slide-in animation finish before WebKit cold-starts.
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                showWebView = true
            }
        }
    }
}

// MARK: - WKWebView wrapper

private struct PhotoWebView: UIViewRepresentable {
    let registration: String
    @Binding var htmlReady: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(htmlReady: $htmlReady)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: URL(string: "https://api.planespotters.net")!)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var htmlReady: Bool
        init(htmlReady: Binding<Bool>) { _htmlReady = htmlReady }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            htmlReady = true
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            htmlReady = true
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            htmlReady = true
        }
    }

    private var html: String {
        let encoded = registration
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? registration
        let safeReg = registration.replacingOccurrences(of: "'", with: "\\'")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, sans-serif;
            background: transparent;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            min-height: 100svh;
            padding: 20px;
            color: #888;
        }
        img {
            max-width: 100%;
            border-radius: 10px;
            display: block;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
        }
        .credit { margin-top: 10px; font-size: 12px; text-align: center; }
        .message { font-size: 15px; text-align: center; }
        </style>
        </head>
        <body>
        <p class="message">Loading…</p>
        <script>
        fetch('/pub/photos/reg/\(encoded)')
          .then(function(r) { return r.json(); })
          .then(function(data) {
            document.body.innerHTML = '';
            var photos = data.photos;
            if (!photos || !photos.length) {
              document.body.innerHTML = '<p class="message">No photos found for \(safeReg)</p>';
              return;
            }
            var p = photos[0];
            var src = (p.thumbnail_large && p.thumbnail_large.src)
                   || (p.thumbnail && p.thumbnail.src);
            if (!src) {
              document.body.innerHTML = '<p class="message">No photos found for \(safeReg)</p>';
              return;
            }
            var wrap = document.createElement('div');
            var img = document.createElement('img');
            img.src = src;
            wrap.appendChild(img);
            if (p.photographer) {
              var credit = document.createElement('p');
              credit.className = 'credit';
              credit.textContent = 'Photo by ' + p.photographer + ' · planespotters.net';
              wrap.appendChild(credit);
            }
            document.body.appendChild(wrap);
          })
          .catch(function() {
            document.body.innerHTML = '<p class="message">Failed to load photo</p>';
          });
        </script>
        </body>
        </html>
        """
    }
}
