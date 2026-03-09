//
//  HttpResponse.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 10.03.2026.
//

import Foundation
import libxml2

let TAG_STATUS_CODE = "status_code";
let TAG_STATUS_MESSAGE = "status_message";

protocol Response: AnyObject {
    var statusCode: Int { get set }
    var statusMessage: String { get set }
    var data: Data { get set }

    func populateWithData(_ data: Data)
}

class HttpResponse: Response {
    var statusCode: Int = 0
    var statusMessage: String = ""
    var data: Data = .init()
    private var elements: [String: String] = [:]

    open func parseNode(_ node: UnsafeMutablePointer<_xmlNode>, docPtr: xmlDocPtr) {}
}

extension HttpResponse {
    func populateWithData(_ data: Data) {
        self.data = data
        parseData()
    }

    func getStringTag(_ tag: String) -> String? {
        elements[tag]
    }

    func getIntTag(_ tag: String) -> Int? {
        guard let stringValue = getStringTag(tag)
        else { return nil }

        return Int(stringValue)
    }

    var isStatusOk: Bool {
        statusCode == 200
    }

    func parseData() {
        elements = [:]

        let docPtr: xmlDocPtr? = data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Int8.self).baseAddress else {
                return nil
            }
            return xmlParseMemory(base, Int32(data.count))
        }

        guard let docPtr else {
            Log.e("An error occurred trying to parse xml.")
            return
        }
        defer {
            xmlFreeDoc(docPtr)
        }

        guard let root = xmlDocGetRootElement(docPtr) else {
            Log.e("No root XML element.")
            return
        }

        withXMLChar(TAG_STATUS_CODE) { tag in
            if let statusStr = xmlGetProp(root, tag) {
                defer { xmlFree(statusStr) }
                statusCode = Int(String(cString: UnsafePointer(statusStr))) ?? 0
            }
        }

        withXMLChar(TAG_STATUS_MESSAGE) { tag in
            if let statusMsgXml = xmlGetProp(root, tag) {
                defer { xmlFree(statusMsgXml) }
                statusMessage = String(cString: UnsafePointer(statusMsgXml))
            } else {
                statusMessage = "Server Error"
            }
        }

        if statusCode == -1 && statusMessage == "Invalid" {
            statusCode = 418
            statusMessage = "Missing audio capture device. Reinstalling GeForce Experience should resolve this error."
        }

        var node = root.pointee.children

        while let currentNode = node {
            let nodeVal = xmlNodeListGetString(docPtr, currentNode.pointee.children, 1)

            let value: String
            if let nodeVal {
                value = String(cString: UnsafePointer(nodeVal))
                xmlFree(nodeVal)
            } else {
                value = ""
            }

            let key = String(cString: UnsafePointer(currentNode.pointee.name))
            elements[key] = value

            parseNode(currentNode, docPtr: docPtr)

            node = currentNode.pointee.next
        }

        Log.d("Parsed XML data: \(elements)")
    }
}

private extension HttpResponse {
    func withXMLChar<Result>(_ string: String, _ body: (UnsafePointer<xmlChar>) -> Result) -> Result {
        return string.utf8CString.withUnsafeBufferPointer { buffer in
            let ptr = UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: xmlChar.self)
            return body(ptr)
        }
    }
}
