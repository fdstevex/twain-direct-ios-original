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
    case delegateNotSet
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

struct CloseSessionResponse : Codable {
    var kind: String
    var commandId: String
    var method: String
    var results: CommandResult
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

struct WaitForEventsRequest : Encodable {
    var kind = "twainlocalscanner"
    var commandId = UUID().uuidString
    var method = "waitForEvents"
    var params: WaitForEventsParams
    
    init(sessionId: String, sessionRevision: Int) {
        params = WaitForEventsParams(sessionId: sessionId, sessionRevision: sessionRevision)
    }
    
    struct WaitForEventsParams : Encodable {
        var sessionId: String
        var sessionRevision: Int
    }
}

struct WaitForEventsResponse : Codable {
    var commandId: String
    var kind: String
    var method: String
    var results: WaitForEventsResults
    
    struct WaitForEventsResults : Codable {
        var success: Bool
        var events: [SessionEvent]
    }
    
    struct SessionEvent : Codable {
        var event: String
        var session: SessionResponse
    }
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

class Session {
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
    
    var sessionID: String?
    var sessionRevision = 0
    var shouldWaitForEvents = false
    var infoExResponse: InfoExResponse?

    var longPollSession: URLSession?
    var blockDownloader: BlockDownloader?

    let lock = NSRecursiveLock()
    
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
    
    // Create the session. If successful, starts the event listener.
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
                self.sessionRevision = 0
                if (self.sessionID == nil) {
                    // Expected the result to have a session since success was true
                    let error = SessionError.missingSessionID
                    completion(AsyncResult.Failure(error))
                    return
                }
                
                self.blockDownloader = BlockDownloader(session: self)
                
                self.shouldWaitForEvents = true
                self.waitForEvents();
                completion(AsyncResult.Success)
            } catch {
                completion(AsyncResult.Failure(error))
            }
        }
        task.resume()
    }
    
    // Start a waitForEvents call. There must be an active session. Will do nothing if
    // there's already a longPollSession.
    private func waitForEvents() {
        if (!self.shouldWaitForEvents) {
            return
        }
        
        lock.lock()
        defer {
            lock.unlock()
        }
        
        if (self.longPollSession == nil) {
            guard var urlRequest = createURLRequest(method: "POST") else {
                log.error("Unexpected: Can't poll because createURLRequest failed")
                return
            }

            guard let sessionID = sessionID else {
                log.error("Unexpected: waitForEvents, but there's no session")
                return
            }

                let body = WaitForEventsRequest(sessionId: sessionID, sessionRevision: sessionRevision)
                urlRequest.httpBody = try? JSONEncoder().encode(body)
            
            let task = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in

                self.lock.lock();
                defer {
                    self.lock.unlock();
                }

                // Clear the reference to this session so we can start a new one
                self.longPollSession = nil

                do {
                    guard let data = data else {
                        // No response data .. queue up another wait
                        self.waitForEvents()
                        return
                    }
                    
                    let response = try JSONDecoder().decode(WaitForEventsResponse.self, from: data)
                    if (!response.results.success) {
                        self.shouldWaitForEvents = false
                        log.error("waitForEvents reported failure")
                        return
                    }
                    
                    response.results.events.forEach { event in
                        if (event.session.revision < self.sessionRevision) {
                            // We've already processed this event
                            return
                        }

                        if event.session.doneCapturing ?? false &&
                            event.session.imageBlocksDrained ?? false {
                            // We're done capturing and all image blocks drained -
                            // No need to keep polling
                            self.shouldWaitForEvents = false
                        }
                        
                        if let imageBlocks = event.session.imageBlocks {
                            self.blockDownloader?.enqueueBlocks(imageBlocks)
                        }
                    }
                    
                    // Queue up another wait
                    self.waitForEvents()
                } catch {
                    log.error("TODO why \(error)")
                    return
                }
                
            }
            
            task.resume()
        }
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
    
    // sendTask takes a little more fiddling than usual because while we use Swift 4's
    // JSON Codable support for requests and responses elsewhere, in this case we need to
    // insert arbitrary JSON (the task), and there's no support for that.
    //
    // Instead, we prepare the request without the task JSON, use JSONEncoder to encode
    // that into JSON, and then decode that into a dictionary with JSONSerialization.
    // Then we can update that dictionary to include the task, and re-encode to JSON.
    //
    // Are there easier ways? Yes. Yes, there are.
    
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
