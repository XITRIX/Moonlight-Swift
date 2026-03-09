//
//  AppListResponse.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 11.03.2026.
//

import Foundation
import libxml2

private let TAG_APP = "App";
private let TAG_APP_TITLE = "AppTitle";
private let TAG_APP_ID = "ID";
private let TAG_HDR_SUPPORTED = "IsHdrSupported";
private let TAG_APP_INSTALL_PATH = "AppInstallPath";

class AppListResponse: HttpResponse {
    init(host: TemporaryHost) {
        self.host = host
    }

    private let host: TemporaryHost
    private(set) var appList: [TemporaryApp]?

    override func parseNode(_ node: UnsafeMutablePointer<_xmlNode>, docPtr: xmlDocPtr) {
        if xmlNodeNameEquals(node.pointee.name, TAG_APP) {
            var appInfoNode = node.pointee.children

            var appName = ""
            var appId: String?
            var hdrSupported = "0"
            var appInstallPath: String?

            while let currentAppInfoNode = appInfoNode {
                if xmlNodeNameEquals(currentAppInfoNode.pointee.name, TAG_APP_TITLE) {
                    if let nodeVal = xmlNodeListGetString(docPtr, currentAppInfoNode.pointee.children, 1) {
                        appName = String(cString: UnsafePointer(nodeVal))
                        xmlFree(nodeVal)
                    }
                } else if xmlNodeNameEquals(currentAppInfoNode.pointee.name, TAG_APP_ID) {
                    if let nodeVal = xmlNodeListGetString(docPtr, currentAppInfoNode.pointee.children, 1) {
                        appId = String(cString: UnsafePointer(nodeVal))
                        xmlFree(nodeVal)
                    }
                } else if xmlNodeNameEquals(currentAppInfoNode.pointee.name, TAG_HDR_SUPPORTED) {
                    if let nodeVal = xmlNodeListGetString(docPtr, currentAppInfoNode.pointee.children, 1) {
                        hdrSupported = String(cString: UnsafePointer(nodeVal))
                        xmlFree(nodeVal)
                    }
                } else if xmlNodeNameEquals(currentAppInfoNode.pointee.name, TAG_APP_INSTALL_PATH) {
                    if let nodeVal = xmlNodeListGetString(docPtr, currentAppInfoNode.pointee.children, 1) {
                        appInstallPath = String(cString: UnsafePointer(nodeVal))
                        xmlFree(nodeVal)
                    }
                }

                appInfoNode = currentAppInfoNode.pointee.next
            }

            if let appId {
                let app = TemporaryApp(id: appId,
                                       name: appName,
                                       installPath: appInstallPath,
                                       hdrSupported: (Int(hdrSupported) ?? 0) != 0,
                                       host: host)

                if appList == nil { appList = [] }
                appList?.append(app)
            }
        }
    }
}

private extension AppListResponse {
    func xmlNodeNameEquals(_ nodeName: UnsafePointer<xmlChar>?, _ string: String) -> Bool {
        guard let nodeName else { return false }

        return string.utf8CString.withUnsafeBufferPointer { buffer in
            let strPtr = UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: xmlChar.self)
            return xmlStrcmp(nodeName, strPtr) == 0
        }
    }
}
