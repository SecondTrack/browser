# Browser

**Read today's web on iOS 6 – with real TLS 1.3 and no JavaScript.**

Safari on iOS 6 fails on most sites today: its TLS is too old, and the pages are built for phones ten times faster. This browser fetches pages itself over modern TLS, throws away the scripts and renders the content as clean, readable text.

## How it works

- **Own network stack:** HTTP/1.1 on top of a bundled [mbedTLS 3.6](https://github.com/Mbed-TLS/mbedtls) with TLS 1.3. Certificates are always checked against a bundled CA list – no "continue anyway".
- **Own renderer:** an HTML-to-text parser that keeps headings, paragraphs, lists, quotes, code blocks, links and images, and drops scripts, styles, iframes, SVG and trackers entirely. Text is laid out with CoreText.
- **Images** load inline (up to 30 per page) and can be tapped to view.
- **Privacy:** cookies live in memory for the session only and are never written to disk. No history is stored.
- **Start page** with DuckDuckGo search (HTML version), Wikipedia and news.

## Limits

GET only – no forms, no logins, no JavaScript. Pages and images are capped at 3 MB. Think of it as a reader, not a full browser.

## Runs on

iOS 6.1.6 · jailbroken iPod touch 4

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: `.deb` from the [latest release](https://github.com/SecondTrack/browser/releases/latest), `dpkg -i`, then `uicache`.

Build it yourself with [Theos](https://theos.dev): `make package` (iOS 6.0+, armv7).

## License

GPL-3.0 – see [LICENSE](LICENSE). mbedTLS under `vendor/` keeps its own license.
Not affiliated with Apple. iPod is a trademark of Apple Inc.
