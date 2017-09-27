//
//  BlockDownloader.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-27.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import Foundation

enum BlockStatus: String, Codable {
    // Ready to download
    case readyToDownload
    // Currently downloading
    case downloading
    // Downloaded, but waiting for more parts
    case waitingForMoreParts
    // Delivered to the client, and deleted
    case completed
}

struct ReadImageBlockRequest : Encodable {
    var kind = "twainlocalscanner"
    var commandId = UUID().uuidString
    var method = "readImageBlock"
    var params: ReadImageBlockParams
    
    init(sessionId: String, imageBlockNum: Int) {
        params = ReadImageBlockParams(sessionId: sessionId, imageBlockNum: imageBlockNum, withMetadata: true)
    }
    
    struct ReadImageBlockParams : Encodable {
        var sessionId: String
        var imageBlockNum: Int
        var withMetadata: Bool
    }
}

struct ReadImageBlockResponse : Codable {
    var commandId: String
    var kind: String
    var method: String
    var results: ReadImageBlockResults
    
    struct ReadImageBlockResults : Codable {
        var success: Bool
        var session: SessionResponse
        var metadata: ImageMetadata
    }
    
    struct SessionEvent : Codable {
        var event: String
        var session: SessionResponse
    }
    
    struct ImageMetadata: Codable {
        var image: ImageInfo
        var address: ImageAddress
    }
    
    struct ImageInfo : Codable {
        var pixelOffsetX: Int
        var pixelOfsetY: Int
        var pixelFormat: String
        var pixelWidth: Int
        var pixelHeight: Int
        var compression: String
        var resolution: Int
    }
    
    enum MoreParts: String, Codable {
        case lastPartInFile
        case lastPartInFileMorePartsPending
        case morePartsPending
    }
    
    struct ImageAddress : Codable {
        var moreParts: MoreParts
        var sheetNumber: Int
        var imageNumber: Int
        var imagePart: Int
        var pixelFormatName: String
        var source: String
        var sourceName: String
        var streamName: String
    }
}

/**
 Managed by a Session, the BlockDownloader keeps track of the blocks that are available,
 and manages downloading, re-assembling and delivering them to the client application.
 */
class BlockDownloader {
    let lock = NSRecursiveLock()
    
    // Block numbers <= this value have been downloaded, assembled, and delivered
    // to the application.
    var highestBlockCompleted = 0

    // Maximum number of blocks we can be downloading at once
    var windowSize = 3

    // Blocks that the scanner has indicated are ready, and our current status.
    var blockStatus = [Int:BlockStatus]()

    // Updated as downloads are queued and complete
    var activeDownloadCount = 0
    
    // The session this downloader is working with
    weak var session: Session?

    init(session: Session) {
        self.session = session
    }
    
    func enqueueBlocks(_ blocks: [Int]) {
        lock.lock()
        defer { lock.unlock() }
        
        for block in blocks {
            if (blockStatus[block] == nil) {
                blockStatus[block] = .readyToDownload
            }
        }
        
        download()
    }
    
    // This function starts a download if:
    // - we're not already downloading
    func download() {
        lock.lock()
        defer { lock.unlock() }
        
        guard let session = session,
            let sessionID = session.sessionID else {
            // No session, can't download
            return
        }
        
        if (activeDownloadCount > windowSize) {
            // Can't start any more downloads right now
            return
        }
        
        // Find the lowest block number that's not already downloading
        var blockToDownload:Int?
        for blockNum in blockStatus.keys.sorted() {
            if blockStatus[blockNum] == .readyToDownload {
                // Found one
                blockToDownload = blockNum
                break
            }
        }
        
        guard let blockNum = blockToDownload else {
            // Nothing ready to download
            return
        }
        
        guard var request = session.createURLRequest(method: "POST") else {
            return
        }
        
        let body = ReadImageBlockRequest(sessionId: sessionID, imageBlockNum: blockNum)
        request.httpBody = try? JSONEncoder().encode(body)
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            log.info("Well, we got a block")
            log.info("Now the fun starts")
        }

        task.resume()
        
        // Mark this block as downloading
        blockStatus[blockNum] = .downloading
        activeDownloadCount = activeDownloadCount + 1
    }

    // Check for images that we hae all the required parts of to delier
    // a file to the app. Assemble, if required, deliver, and delete the parts.
    func deliverCompletedBlocks() {
        
    }
    
}

