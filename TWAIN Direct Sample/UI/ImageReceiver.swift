//
//  ImageReceiver.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-30.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import Foundation

/**
 Simple class that accepts images from SessionDelegate and stores them on disk, then
 broadcasts a notification to let the UI know to refresh.
 */
class ImageReceiver : SessionDelegate {
    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
    
    func session(_ session: Session, didReceive file: URL, metadata: Data) {
        log.info("Moving to \(docsDir)")
        try? FileManager.default.moveItem(at: file, to: docsDir.appendingPathComponent(file.lastPathComponent))
    }
    
    func session(_ session: Session, didChangeState newState: Session.State) {
        log.info("sessionDidChangeState \(newState)")
    }
    
    func session(_ session: Session, didChangeStatus newStatus: Session.StatusDetected, success: Bool) {
        log.info("sessionDidChangeStatus \(newStatus) success=\(success)")
    }
    
    func sessionDidFinishCapturing(_ session: Session) {
        log.info("sessionDidFinishCapturing")
    }
}
