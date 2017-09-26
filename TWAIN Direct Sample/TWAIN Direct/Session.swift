//
//  Session.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-22.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import Foundation

/**
 This class manages a session with a TWAIN Direct scanner.
 */

protocol SessionDelegate: class {
    func session(_ session: Session, didReceive file: URL, metadata: [String: Any])
    func session(_ session: Session, didChangeState newState:Session.State)
    func session(_ session: Session, didChangeStatus newStatus:Session.StatusDetected, success: Bool)
    func sessionDidFinishCapturing(_ session: Session)
}

enum AsyncResult {
    case Success
    case Failure(Error?)
}

enum AsyncResponse<T> {
    case Success(T)
    case Failure(Error?)
}

struct InfoExResponse : Decodable {
    enum CodingKeys: String, CodingKey {
        case type
        case version
        case description
        case api
        case manufacturer
        case model
        case privetToken = "x-privet-token"
    }
    var type: String
    var version: String?
    var description: String?
    var api: [String]?
    var manufacturer: String?
    var model: String?
    var privetToken: String
}

class Session {
    enum BlockStatus {
        // Ready to download
        case ready
        // Currently downloading
        case downloading
        // Downloaded, but waiting for more parts
        case waiting
        // Delivered to the client, and deleted
        case completed
    }

    public enum State {
        case noSession
        case ready
        case capturing
        case closed
        case draining
    }
    
    public enum StatusDetected {
        case nominal
        case coverOpen
        case foldedCorner
        case imageError
        case misfeed
        case multifed
        case paperJam
        case noMedia
        case staple
    }
    
    private var privetToken: String?
    private var sessionID: String?
    private var sessionRevision: Int?
    private var infoExResult: [String:String]?
    
    var scanner: ScannerInfo
    weak var delegate: SessionDelegate?
    
    init(scanner:ScannerInfo) {
        self.scanner = scanner
    }

    // Get a Privet token, and open a session with the scanner
    func open(completion: @escaping (AsyncResult)->()) {
        guard let url = URL(string: "/privet/infoex", relativeTo: scanner.url) else {
            return
        }
        var request = URLRequest(url:url)
        request.addValue("", forHTTPHeaderField: "X-Privet-Token")
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let data = data else {
                // No response data
                completion(AsyncResult.Failure(nil))
                return
            }

            do {
                let jsonObj = try JSONDecoder().decode(InfoExResponse.self, from: data)
                log.info("\(jsonObj)")
                completion(AsyncResult.Success)
            } catch {
                completion(AsyncResult.Failure(error))
            }
        }
        task.resume()
    }

    func start() {
        
    }
    
}
