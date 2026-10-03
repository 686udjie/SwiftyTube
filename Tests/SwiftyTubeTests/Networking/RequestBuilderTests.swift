//
//  RequestBuilderTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Testing

@testable import SwiftyTube

@Suite("RequestBuilder")
struct RequestBuilderTests {
    @Test("Search request carries client headers and JSON body")
    func searchRequest() {
        let request = RequestBuilder.buildRequest(
            config: .youtube,
            endpoint: "search",
            body: ["query": "test"],
            client: .web,
            auth: .guest
        )
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://www.youtube.com/youtubei/v1/search")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-YouTube-Client-Name") == "1")
        #expect(request.value(forHTTPHeaderField: "X-YouTube-Client-Version") == YouTubeClient.web.clientVersion)
        #expect(request.value(forHTTPHeaderField: "X-Origin") == "https://www.youtube.com")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == YouTubeClient.web.userAgent)
        #expect(request.httpBody != nil)
    }

    @Test("Music service routes to the music host")
    func musicRouting() {
        let request = RequestBuilder.buildRequest(
            config: .music,
            endpoint: "search",
            body: ["query": "test"],
            client: .webRemix,
            auth: .guest
        )
        #expect(request.url?.absoluteString == "https://music.youtube.com/youtubei/v1/search")
        #expect(request.value(forHTTPHeaderField: "X-Origin") == "https://music.youtube.com")
    }

    @Test("Visitor data header only when present")
    func visitorData() {
        var auth = AuthState.guest
        auth.visitorData = "visitor-123"
        let withVisitor = RequestBuilder.buildRequest(
            config: .youtube,
            endpoint: "search",
            body: [:],
            client: .web,
            auth: auth
        )
        #expect(withVisitor.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == "visitor-123")

        let withoutVisitor = RequestBuilder.buildRequest(
            config: .youtube,
            endpoint: "search",
            body: [:],
            client: .web,
            auth: .guest
        )
        #expect(withoutVisitor.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == nil)
    }

    @Test("Auth headers only for login-capable clients")
    func loginGating() {
        let signedIn = AuthState(cookies: ["SID": "abc"], sapisid: "sapisid-value")
        let loginClient = RequestBuilder.buildRequest(
            config: .youtube,
            endpoint: "search",
            body: [:],
            client: .web,
            auth: signedIn
        )
        #expect(loginClient.value(forHTTPHeaderField: "Cookie") == "SID=abc")
        #expect(loginClient.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)

        let noLogin = RequestBuilder.buildRequest(
            config: .youtube,
            endpoint: "player",
            body: [:],
            client: .iOS,
            auth: signedIn
        )
        #expect(noLogin.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(noLogin.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
