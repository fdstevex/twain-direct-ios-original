//
//  ImageReceiver.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-30.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import Foundation

extension Notification.Name {
    static let scannedImagesUpdatedNotification = Notification.Name("scannedImagesUpdatedNotification")
    static let sessionUpdatedNotification = Notification.Name("sessionUpdatedNotification")
    static let didFinishCapturingNotification = Notification.Name("didFinishCapturingNotification")
}

/**
 Simple class that accepts images from SessionDelegate and stores them on disk, then
 broadcasts a notification to let the UI know to refresh.
 */
class ImageReceiver : SessionDelegate {
    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
    
    func session(_ session: Session, didReceive file: URL, metadata: Data) {
        log.info("Moving to \(docsDir)")
        try? FileManager.default.moveItem(at: file, to: docsDir.appendingPathComponent(file.lastPathComponent))
        NotificationCenter.default.post(name: .scannedImagesUpdatedNotification, object: self)
    }
    
    func session(_ session: Session, didChangeState newState: Session.State) {
        log.info("sessionDidChangeState \(newState)")
        NotificationCenter.default.post(name: .sessionUpdatedNotification, object: self)
    }
    
    func session(_ session: Session, didChangeStatus newStatus: Session.StatusDetected, success: Bool) {
        log.info("sessionDidChangeStatus \(newStatus) success=\(success)")
        NotificationCenter.default.post(name: .sessionUpdatedNotification, object: self)
    }
    
    func sessionDidFinishCapturing(_ session: Session) {
        log.info("sessionDidFinishCapturing")
        NotificationCenter.default.post(name: .didFinishCapturingNotification, object: self)
        
        session.closeSession { (result) in
            // Sent session close
        }
    }
}
