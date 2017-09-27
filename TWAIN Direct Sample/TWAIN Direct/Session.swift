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

enum SessionError : Error {
    case missingInfoExResponse
    case unableToCreateRequest
    case missingAPIInInfoExResponse
    case createSessionFailed(code: String?)
    case closeSessionFailed(code: String?)
    case missingSessionID
    case invalidJSON
    case startCapturingFailed(response: StartCapturingResponse)
}

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

struct CloseSessionRequest : Codable {
    var kind = "twainlocalscanner"
    var commandId = UUID().uuidString
    var method = "closeSession"
    var params: CloseSessionParams
    
    init(sessionId: String) {
        params = CloseSessionParams(sessionId: sessionId)
    }
    
    struct CloseSessionParams : Codable {
        var sessionId: String
    }
}

struct SendTaskRequest : Encodable {
    var kind = "twainlocalscanner"
    var commandId = UUID().uuidString
    var method = "sendTask"
    var params: SendTaskParams
    
    init(sessionId: String, task: [String:Any]) {
        params = SendTaskParams(sessionId: sessionId)
    }
    
    struct SendTaskParams : Encodable {
        var sessionId: String
        
        enum SendTaskParamsKeys: String, CodingKey {
            case sessionId
        }
    }
}

struct SendTaskResponse : Codable {
    var kind: String
    var commandId: String
    var method: String
    var results: CommandResult
}

struct CreateSessionRequest : Codable {
    var kind = "twainlocalscanner"
    var commandId = UUID().uuidString
    var method = "createSession"
}

struct SessionStatus : Codable {
    var success: Bool
    var detected: Session.StatusDetected?
}

struct SessionResponse: Codable {
    var sessionId: String
    var revision: Int

    var doneCapturing: Bool?
    var imageBlocks: [Int]?
    var imageBlocksDrained: Bool?

    var state: Session.State
    var status: SessionStatus
}

struct CommandResult: Codable {
    var success: Bool
    var session: SessionResponse?
    var code: String?
}

struct StartCapturingRequest : Codable {
    var kind = "twainlocalscanner"
    var commandId = UUID().uuidString
    var method = "startCapturing"
    
    var params: StartCapturingParams
    
    init(sessionId: String) {
        params = StartCapturingParams(sessionId: sessionId)
    }
    
    struct StartCapturingParams : Codable {
        var sessionId: String
    }

}

struct StartCapturingResponse : Codable {
    var kind: String
    var commandId: String
    var method: String
    var results: CommandResult
}

struct CreateSessionResponse : Codable {
    var kind: String
    var commandId: String
    var method: String
    var results: CommandResult
}

struct CloseSessionResponse : Codable {
    var kind: String
    var commandId: String
    var method: String
    var results: CommandResult
}

class Session {
    enum BlockStatus: String, Codable {
        // Ready to download
        case ready
        // Currently downloading
        case downloading
        // Downloaded, but waiting for more parts
        case waiting
        // Delivered to the client, and deleted
        case completed
    }

    public enum State: String, Codable {
        case noSession
        case ready
        case capturing
        case closed
        case draining
    }
    
    public enum StatusDetected: String, Codable {
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
    
    private var sessionID: String?
    private var sessionRevision: Int?
    private var infoExResponse: InfoExResponse?
    
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
                let infoExResponse = try JSONDecoder().decode(InfoExResponse.self, from: data)
                log.info("\(infoExResponse)")
                self.infoExResponse = infoExResponse
                self.createSession(completion: completion)
            } catch {
                completion(AsyncResult.Failure(error))
            }
        }
        task.resume()
    }

    func createURLRequest(method: String) -> URLRequest? {
        guard let infoExResponse = infoExResponse else {
            return nil
        }
        
        guard let api = infoExResponse.api?.first else {
            return nil
        }
        
        guard let url = URL(string: api, relativeTo: scanner.url) else {
            return nil
        }
        
        var request = URLRequest(url:url)
        request.setValue(infoExResponse.privetToken, forHTTPHeaderField: "X-Privet-Token")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.httpMethod = method
        return request
    }
    
    func createSession(completion: @escaping (AsyncResult)->()) {
        guard var request = createURLRequest(method: "POST") else {
            // This shouldn't fail, but just in case
            completion(.Failure(SessionError.unableToCreateRequest))
            return
        }
        
        let createSessionRequest = CreateSessionRequest()
        request.httpBody = try? JSONEncoder().encode(createSessionRequest)
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let data = data else {
                // No response data
                completion(AsyncResult.Failure(nil))
                return
            }
            
            do {
                let createSessionResponse = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
                if (!createSessionResponse.results.success) {
                    let error = SessionError.createSessionFailed(code:createSessionResponse.results.code)
                    completion(AsyncResult.Failure(error))
                    return
                }
                self.sessionID = createSessionResponse.results.session?.sessionId
                if (self.sessionID == nil) {
                    let error = SessionError.missingSessionID
                    completion(AsyncResult.Failure(error))
                    return
                }
                
                
                completion(AsyncResult.Success)
            } catch {
                completion(AsyncResult.Failure(error))
            }
        }
        task.resume()
    }
    
    
    func closeSession(completion: @escaping (AsyncResult)->()) {
        guard var request = createURLRequest(method: "POST"), let sessionID = sessionID else {
            // This shouldn't fail, but just in case
            completion(.Failure(SessionError.unableToCreateRequest))
            return
        }

        let body = CloseSessionRequest(sessionId: sessionID)
        request.httpBody = try? JSONEncoder().encode(body)
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let data = data else {
                // No response data
                completion(AsyncResult.Failure(nil))
                return
            }
            
            do {
                let closeSessionResponse = try JSONDecoder().decode(CloseSessionResponse.self, from: data)
                if (!closeSessionResponse.results.success) {
                    completion(AsyncResult.Failure(SessionError.closeSessionFailed(code:closeSessionResponse.results.code)))
                }
                completion(AsyncResult.Success)
            } catch {
                completion(AsyncResult.Failure(error))
            }
        }
        task.resume()
    }
    
    func sendTask(_ task: [String:Any], completion: @escaping (AsyncResult)->()) {
        guard var request = createURLRequest(method: "POST"), let sessionID = sessionID else {
            // This shouldn't fail, but just in case
            completion(.Failure(SessionError.unableToCreateRequest))
            return
        }
        
        // Get JSON for the basic request
        let body = SendTaskRequest(sessionId: sessionID, task: task)
        guard let jsonEncodedBody = try? JSONEncoder().encode(body) else {
            completion(AsyncResult.Failure(SessionError.invalidJSON))
            return
        }

        // Convert to dictionary
        guard var dict = try? JSONSerialization.jsonObject(with: jsonEncodedBody, options: []) as! [String:Any] else {
            completion(AsyncResult.Failure(SessionError.invalidJSON))
            return
        }

        var paramsDict = dict["params"] as! [String:Any]
        paramsDict["task"] = task
        dict["params"] = paramsDict
        guard let mergedBody = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            completion(AsyncResult.Failure(SessionError.invalidJSON))
            return
        }

        request.httpBody = mergedBody
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let data = data else {
                // No response data
                completion(AsyncResult.Failure(nil))
                return
            }
            
            do {
                let sendTaskResponse = try JSONDecoder().decode(SendTaskResponse.self, from: data)
                if (!sendTaskResponse.results.success) {
                    completion(AsyncResult.Failure(SessionError.closeSessionFailed(code:sendTaskResponse.results.code)))
                }
                completion(AsyncResult.Success)
            } catch {
                completion(AsyncResult.Failure(error))
            }
        }
        task.resume()
    }
    
    func startCapturing(completion: @escaping (AsyncResponse<StartCapturingResponse>)->()) {
        guard var request = createURLRequest(method: "POST"), let sessionID = sessionID else {
            // This shouldn't fail, but just in case
            completion(.Failure(SessionError.unableToCreateRequest))
            return
        }
        
        request.httpBody = try? JSONEncoder().encode(StartCapturingRequest(sessionId: sessionID))

        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let data = data else {
                // No response data
                completion(.Failure(nil))
                return
            }
            
            do {
                let startCapturingResponse = try JSONDecoder().decode(StartCapturingResponse.self, from: data)
                if (!startCapturingResponse.results.success) {
                    completion(AsyncResponse.Failure(SessionError.startCapturingFailed(response:startCapturingResponse)))
                }
                completion(.Success(startCapturingResponse))
            } catch {
                completion(.Failure(error))
            }
        }
        task.resume()
    }
}
