import Foundation
import Testing
@testable import LumenCore

struct YouTubeLinkTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=2",
        "https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0",
        "https://www.youtube.com/live/dQw4w9WgXcQ?feature=share",
        "  https://youtu.be/dQw4w9WgXcQ\n",
    ])
    func recognizesVideoLinks(_ text: String) throws {
        let link = try #require(YouTubeLink(string: text))
        #expect(link.videoId == "dQw4w9WgXcQ")
        #expect(!link.isShort)
        #expect(link.watchURL.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "https://www.youtube.com/playlist?list=PL123",
        "https://www.youtube.com/@channel",
        "https://vimeo.com/123456",
        "https://youtu.be/short",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
        "смотри https://youtu.be/dQw4w9WgXcQ",
        "ftp://youtube.com/watch?v=dQw4w9WgXcQ",
        "",
    ])
    func ignoresOtherText(_ text: String) {
        #expect(YouTubeLink(string: text) == nil)
    }

    @Test func shortsStayVertical() throws {
        let link = try #require(YouTubeLink(string: "https://youtube.com/shorts/abcdefghijk?feature=share"))
        #expect(link.isShort)
        #expect(link.aspect > 1)
        #expect(link.watchURL.absoluteString == "https://www.youtube.com/shorts/abcdefghijk")
    }

    @Test func startTimeInAnyForm() {
        #expect(YouTubeLink(string: "https://youtu.be/dQw4w9WgXcQ?t=90")?.start == 90)
        #expect(YouTubeLink(string: "https://youtu.be/dQw4w9WgXcQ?t=90s")?.start == 90)
        #expect(YouTubeLink(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s")?.start == 90)
        #expect(YouTubeLink(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1h2m3s")?.start == 3723)
        #expect(YouTubeLink(string: "https://www.youtube.com/embed/dQw4w9WgXcQ?start=42")?.start == 42)
        #expect(YouTubeLink(string: "https://youtu.be/dQw4w9WgXcQ#t=15")?.start == 15)
        #expect(YouTubeLink(string: "https://youtu.be/dQw4w9WgXcQ?t=abc")?.start == nil)
    }

    @Test func startSurvivesInStoredLinkAndPlayer() throws {
        let link = try #require(YouTubeLink(string: "https://youtu.be/dQw4w9WgXcQ?t=1m30s"))
        #expect(link.watchURL.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90s")
        #expect(YouTubeLink(string: link.watchURL.absoluteString) == link)
        #expect(link.startText == "1:30")

        let embed = link.embedURL(origin: "https://io.github.bradd06.lumen")
        let items = URLComponents(url: embed, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(embed.host() == "www.youtube-nocookie.com")
        #expect(embed.path() == "/embed/dQw4w9WgXcQ")
        #expect(items.contains(URLQueryItem(name: "start", value: "90")))
        #expect(items.contains(URLQueryItem(name: "origin", value: "https://io.github.bradd06.lumen")))
        #expect(items.contains(URLQueryItem(name: "playsinline", value: "1")))
    }

    @Test func videoTitleGoesToMarkdownExport() {
        let page = Page(title: "Лекция", sortKey: "a")
        let video = Block(
            pageId: page.id,
            type: .video,
            content: BlockContent(bookmark: WebBookmark(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "Урок 1")),
            sortKey: "a"
        )
        let markdown = PageExport(page: page, blocks: [video]).markdown()
        #expect(markdown.contains("▶️ [Урок 1](https://www.youtube.com/watch?v=dQw4w9WgXcQ)"))
    }
}
