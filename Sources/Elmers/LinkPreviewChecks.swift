#if DEBUG
import AppKit

/// Fetches a preview of `url` twice and checks that no cookie survives. Point it at a server on a real host name
/// (cookies from bare IP addresses are dropped anyway) that sets a cookie and logs whether the second request sent
/// it back; see the September 23 security notes in docs/HANDOFF.md.
@MainActor
enum LinkPreviewChecks {
    static func run(url: String) {
        let fetcher = LinkPreviewFetcher()
        fetcher.fetch(url) { first in
            fetcher.fetch(url) { second in
                let cookies = HTTPCookieStorage.shared.cookies ?? []
                guard cookies.isEmpty else { print("FAIL: \(cookies.count) cookie(s) kept after previews"); fflush(stdout); exit(1) }
                print("PASS: two previews fetched (titles: \(first.title ?? "none"), \(second.title ?? "none")) and no cookie kept"); fflush(stdout); exit(0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { print("FAIL: link preview timed out"); fflush(stdout); exit(1) }
    }
}
#endif
