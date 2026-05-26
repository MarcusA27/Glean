import AppKit
import WebKit

/// First-run login + session loading. Reads the persisted WKWebView cookie store
/// (which survives launches by bundle id); if there's no live session, shows a
/// focusable login window. The island panel is never disturbed.
@MainActor
final class PinterestAuth: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var onComplete: (([StoredCookie]) -> Void)?
    private var captured = false

    /// Headlessly load an existing session, else present login.
    func loadSession(completion: @escaping ([StoredCookie]) -> Void) {
        onComplete = completion
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            MainActor.assumeIsolated {
                guard let self else { return }
                let stored = Self.pinterestCookies(from: cookies)
                if stored.contains(where: { $0.name == "_auth" && $0.value == "1" }) {
                    CookieStore.save(stored)
                    self.deliver(stored)
                } else {
                    self.presentLogin()
                }
            }
        }
    }

    /// Force a fresh login after the stored session is rejected: clear cookies so the
    /// webview can't silently resume the dead session, then present the login window.
    func relogin(completion: @escaping ([StoredCookie]) -> Void) {
        onComplete = completion
        captured = false
        CookieStore.clear()
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies],
                                                modifiedSince: .distantPast) { [weak self] in
            MainActor.assumeIsolated { self?.presentLogin() }
        }
    }

    private func presentLogin() {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 720))
        web.customUserAgent = PinterestClient.userAgent
        web.navigationDelegate = self
        webView = web

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Sign in to Pinterest"
        win.contentView = web
        win.center()
        win.isReleasedWhenClosed = false
        window = win

        NSApp.setActivationPolicy(.regular) // allow focus/typing during login
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        guard let url = URL(string: "https://www.pinterest.com/login/") else { return }
        web.load(URLRequest(url: url))
    }

    private func captureIfLoggedIn() {
        guard !captured, let web = webView else { return }
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            MainActor.assumeIsolated {
                guard let self, !self.captured else { return }
                let stored = Self.pinterestCookies(from: cookies)
                guard stored.contains(where: { $0.name == "_auth" && $0.value == "1" }) else { return }
                self.captured = true
                CookieStore.save(stored)
                self.window?.close()
                self.window = nil
                self.webView = nil
                NSApp.setActivationPolicy(.accessory)
                self.deliver(stored)
            }
        }
    }

    private func deliver(_ cookies: [StoredCookie]) {
        let callback = onComplete
        onComplete = nil
        callback?(cookies)
    }

    private static func pinterestCookies(from cookies: [HTTPCookie]) -> [StoredCookie] {
        cookies
            .filter { $0.domain.contains("pinterest.com") }
            .map { StoredCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path) }
    }
}

extension PinterestAuth: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureIfLoggedIn()
    }
}
