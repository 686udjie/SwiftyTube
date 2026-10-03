//
//  ServiceTests.swift
//  SwiftyTubeTests
//
//  Created by 686udjie on 03/10/2026.
//

import Testing

@testable import SwiftyTube

@Suite("YouTubeService")
struct ServiceTests {
    @Test("Music and YouTube use different hosts")
    func hosts() {
        #expect(YouTubeService.music.baseURL.absoluteString == "https://music.youtube.com/youtubei/v1/")
        #expect(YouTubeService.youtube.baseURL.absoluteString == "https://www.youtube.com/youtubei/v1/")
        #expect(YouTubeService.music.origin == "https://music.youtube.com")
        #expect(YouTubeService.youtube.origin == "https://www.youtube.com")
    }
}
