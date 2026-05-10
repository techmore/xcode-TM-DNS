//
//  xcode_TM_DNSTests.swift
//  xcode-TM-DNSTests
//
//  Created by techmore on 5/9/26.
//

import Foundation
import Testing
@testable import TM_DNS

struct xcode_TM_DNSTests {

    @Test func apiURLPreservesQueryString() async throws {
        let baseURL = URL(string: "http://127.0.0.1:8080")!
        let url = TMDNSService.apiURL(baseURL: baseURL, path: "/api/hosts/4?hours=24")
        #expect(url.absoluteString == "http://127.0.0.1:8080/api/hosts/4?hours=24")
    }

}
