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
        var pixelOffsetY: Int
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

struct DownloadedBlockInfo {
    // Block number
    let blockNum: Int
    
    // JSON response as received
    let metadata: Data
    
    // Decoded JSON response
    let response: ReadImageBlockResponse
    
    // Where the PDF was saved
    let pdfPath: URL
}

/**
 Managed by a Session, the BlockDownloader keeps track of the blocks that are available,
 and manages downloading, re-assembling and delivering them to the client application.
 */
class BlockDownloader {
    let lock = NSRecursiveLock()
    
    // Block numbers <= this value have been downloaded, assembled, and delivered
    // to the application.
    var highestBlockCompleted = 1

    // Maximum number of blocks we can be downloading at once
    var windowSize = 3

    // Blocks that the scanner has indicated are ready, and our current status.
    var blockStatus = [Int:BlockStatus]()

    // Blocks that we've downloaded but not yet delivered
    var downloadedBlocks = [Int:DownloadedBlockInfo]()
    
    // Updated as downloads are queued and complete
    var activeDownloadCount = 0
    
    // The session this downloader is working with
    weak var session: Session?

    var tempFolder: URL
    
    init(session: Session) {
        
        self.session = session
        
        tempFolder = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TDScans.xxx")!
        try? FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true, attributes: nil)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: tempFolder)
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
        
        log.info("Starting download of block \(blockNum)")
        let body = ReadImageBlockRequest(sessionId: sessionID, imageBlockNum: blockNum)
        request.httpBody = try? JSONEncoder().encode(body)
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard let data = data, let urlResponse = response as? HTTPURLResponse else {
                // TODO error
                return
            }
            
            if urlResponse.mimeType != "multipart/mixed" {
                // TODO error
                return
            }
            
            guard let contentTypeHeader = urlResponse.allHeaderFields["Content-Type"] as? String else {
                // TODO error - no boundary
                return;
            }
            
            guard let range = contentTypeHeader.range(of: "boundary=") else {
                // TODO error - no boundary
                return;
            }

            let quotedBoundary = String(contentTypeHeader[range.upperBound...])
            let boundary = "--" + (quotedBoundary as NSString).trimmingCharacters(in: CharacterSet(charactersIn:"\"'"))
            
            var callbacks = multipart_parser_settings()
            let parser = multipart_parser_init(boundary, &callbacks)
            
            let tempPDF = self.tempFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
            
            class Context {
                var fieldName: String?
                var headers = [String:String]()
                var contentType = ""
                
                var json: Data?
                var pdf: Data?
                var current = Data()
                
                func partDataEnd() {
                    log.info("part data end, \(current.count) bytes");
                    
                    // Figure out where the body part should go
                    if let contentType = headers["content-type"] {
                        if contentType.starts(with: "application/json") {
                            json = current
                        } else if contentType.starts(with: "application/pdf") {
                            pdf = current
                        }
                    }
                    
                    current = Data()
                }
            }
            
            var context = Context()
            
            callbacks.on_header_field = { parser, ptr, count in
                let context = multipart_parser_get_data(parser)?.assumingMemoryBound(to: Context.self)
                let data = Data.init(bytes: ptr!, count: count)
                context?.pointee.fieldName = String(data:data, encoding: .utf8)
                return 0
            }
            
            callbacks.on_header_value = { parser, ptr, count in
                if let context = multipart_parser_get_data(parser)?.assumingMemoryBound(to: Context.self) {
                    if let fieldName = context.pointee.fieldName {
                        let data = Data.init(bytes: ptr!, count: count)
                        if let fieldValue = String(data:data, encoding: .utf8) {
                            context.pointee.headers[fieldName.lowercased()] = fieldValue
                            log.info("\(fieldName)=\(fieldValue)")
                        }
                    }
                }
                return 0
            }
            
            callbacks.on_part_data_begin = { parser in
                let context = multipart_parser_get_data(parser)?.assumingMemoryBound(to: Context.self)
                log.info("part begin");
                context?.pointee.headers.removeAll()
                return 0
            }
            
            callbacks.on_headers_complete = { parser in
                if let context = multipart_parser_get_data(parser)?.assumingMemoryBound(to: Context.self) {
                    log.info("headers complete")
                    context.pointee.current = Data()
                }
                
                return 0
            }
            
            callbacks.on_part_data_end = { parser in
                if let context = multipart_parser_get_data(parser)?.assumingMemoryBound(to: Context.self).pointee {
                    context.partDataEnd()
                }
                return 0
            }

            withUnsafeMutablePointer(to: &context, { (dataPtr) -> Void in
                multipart_parser_set_data(parser, dataPtr)
            })
            
            callbacks.on_part_data = { parser, ptr, count in
                let context = multipart_parser_get_data(parser)?.assumingMemoryBound(to: Context.self)
                ptr?.withMemoryRebound(to: UInt8.self, capacity: count, { (p) -> Void in
                    context?.pointee.current.append(p, count: count)
                })
                return 0
            }

            let _ = data.withUnsafeBytes {
                multipart_parser_execute(parser, UnsafePointer($0), data.count)
            }

            if (context.current.count > 0) {
                context.partDataEnd()
            }
            multipart_parser_free(parser)
            
            // Remove the trailing crlf that ends the body part
            context.pdf?.removeLast(2)
            
            if let pdf = context.pdf, let response = context.json {
                do {
                    let result = try JSONDecoder().decode(ReadImageBlockResponse.self, from: response)

                    if (!result.results.success) {
                        log.error("Failure downloading block: \(result)")
                        self.lock.lock()
                        self.blockStatus[blockNum] = .readyToDownload
                        self.lock.unlock()
                        return
                    }
                    
                    log.info("Writing PDF for block \(blockNum) to \(tempPDF)")
                    try? pdf.write(to: tempPDF)
                    
                    self.lock.lock()
                    
                    // There may not be more parts, but this signals to deliverCompletedBlocks that this
                    // part is all here.
                    self.blockStatus[blockNum] = .waitingForMoreParts
                    
                    // Release
                    session.releaseImageBlocks(from: blockNum, to: blockNum, completion: { (result) in
                        switch (result) {
                        case .Success:
                                log.info("Released image block \(blockNum)")
                                break;
                        case .Failure(let error):
                            log.error("Error releasing block \(blockNum): \(String(describing:error))")
                        }
                    })

                    self.downloadedBlocks[blockNum] = DownloadedBlockInfo(blockNum: blockNum, metadata: response, response: result, pdfPath: tempPDF)
                    
                    self.lock.unlock()
                    
                    self.deliverCompletedBlocks()
                } catch {
                    log.error("Error decoding response: \(error)")
                    self.lock.lock()
                    self.blockStatus[blockNum] = .readyToDownload
                    self.lock.unlock()
                    return
                }
            }
        }

        task.resume()

        // Mark this block as downloading
        blockStatus[blockNum] = .downloading
        activeDownloadCount = activeDownloadCount + 1
    }

    // Check for images that we hae all the required parts of to delier
    // a file to the app. Assemble, if required, deliver, and delete the parts.
    func deliverCompletedBlocks() {
        lock.lock()
        
        // First part,
        var partsToAssemble = 0
        var nextBlock = 0
        for blockNum in highestBlockCompleted... {
            guard let downloadedBlockInfo = downloadedBlocks[blockNum] else {
                // Missing piece, not ready to deliver
                lock.unlock()
                return
            }
            
            partsToAssemble = partsToAssemble + 1
            
            let metadata = downloadedBlockInfo.response.results.metadata
            if metadata.address.moreParts != .morePartsPending {
                // This is the last piece of this PDF, although there may be
                // more PDFs in the entire image.  We can deliver this.
                nextBlock = blockNum + 1
                break
            }
        }

        // Use the metadata from the first part to build the filename
        guard let firstMeta = downloadedBlocks[highestBlockCompleted] else {
            lock.unlock()
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmSS"
        let address = firstMeta.response.results.metadata.address
        let fileName = "\(formatter.string(from: Date()))-\(address.sheetNumber)-\(address.imageNumber)-\(address.imagePart).pdf"
        
        // Rename the first part
        let fm = FileManager.default
        let destURL = tempFolder.appendingPathComponent(fileName)
        try! fm.moveItem(at:firstMeta.pdfPath, to: destURL)
        
        // Concatenate subsequent parts
        
        // TODO
        
        // Deliver
        if let session = session {
            session.delegate?.session(session, didReceive: destURL, metadata: firstMeta.metadata)
        }
        
        highestBlockCompleted = nextBlock
    }
}

