//
//  HttpRequest.swift
//  Moonlight-Swift
//
//  Created by Daniil Vinogradov on 10/03/2026.
//

import Foundation

class HttpRequest {
    var response: Response?
    var request: URLRequest?
    var fallbackError: Int?
    var fallbackRequest: URLRequest?

    init(for response: Response? = nil, with request: URLRequest?, fallbackError: Int? = nil, fallbackRequest: URLRequest? = nil) {
        self.response = response
        self.request = request
        self.fallbackError = fallbackError
        self.fallbackRequest = fallbackRequest
    }
}
