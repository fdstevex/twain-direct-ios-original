//
//  MainTableTableViewController.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-22.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import UIKit

class MainTableTableViewController: UITableViewController {

    @IBOutlet var startButton: UIButton!
    @IBOutlet var pauseButton: UIButton!
    @IBOutlet var stopButton: UIButton!
    @IBOutlet weak var selectedScannerLabel: UILabel!
    @IBOutlet weak var selectedTaskLabel: UILabel!
    @IBOutlet weak var sessionStatusLabel: UILabel!
    @IBOutlet weak var scannedImagesLabel: UILabel!
    
    var session: Session?
    var imageReceiver: ImageReceiver?
    var lastImageNameReceived = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.estimatedRowHeight = 44
        
        NotificationCenter.default.addObserver(forName:.scannedImagesUpdatedNotification, object: nil, queue: OperationQueue.main) { notification in
            if let data = notification.object as? ImagesUpdatedNotificationData {
                self.lastImageNameReceived = data.url.lastPathComponent
                self.updateStatusLabel()
                self.updateScannedImagesLabel()
            }
        }

        NotificationCenter.default.addObserver(forName:.sessionUpdatedNotification, object: nil, queue: OperationQueue.main) { (_) in
            self.updateStatusLabel()
        }

        NotificationCenter.default.addObserver(forName:.didFinishCapturingNotification, object: nil, queue: OperationQueue.main) { (_) in
            log.info("didFinishCapturingNotification")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateLabels()
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    @IBAction func didTapStart(_ sender: Any) {
        guard let scannerJSON = UserDefaults.standard.string(forKey: "scanner") else {
            return
        }
        
        var scannerInfo: ScannerInfo!
        do {
            scannerInfo = try JSONDecoder().decode(ScannerInfo.self, from: (scannerJSON.data(using: .utf8))!)
        } catch {
            log.error("Failed deserializing scannerInfo: \(error)")
            return
        }
        
        let scanner = ScannerInfo(url: scannerInfo.url, fqdn: scannerInfo.fqdn, txtDict: [String:String]())
        session = Session(scanner: scanner)
        
        imageReceiver = ImageReceiver()
        session?.delegate = imageReceiver
        
        session?.open { result in
            switch (result) {
            case .Success:
                log.info("didTapStart openSession success")
                self.sendTask()
            case .Failure(let error):
                log.info("didTapStart open session failure: \(String(describing:error))")
            }
        }
    }
    
    // Called from didTapStart when the session open succeeds
    func sendTask() {
        let data = "{\"actions\": [ { \"action\": \"configure\" } ] }".data(using: .utf8)
        let taskObj = try? JSONSerialization.jsonObject(with: data!, options: []) as! [String:Any]
        
        session?.sendTask(taskObj!) { result in
            switch (result) {
            case .Success:
                log.info("sendTask completed successfully")
                self.startCapturing()
                break;
            case .Failure(let error):
                log.info("sendTask Failure: \(String(describing:error))")
                break;
            }
        }
    }

    // Called from sendTask when the task has been successfully sent
    func startCapturing() {
        session?.startCapturing(completion: { (response) in
            switch (response) {
            case .Success(let result):
                log.info("startCapture succeeded: \(result)")
                
            case .Failure(let error):
                log.info("startCapture failed; \(String(describing:error))")
            }
        })
    }

    // temporary test method
    func closeSession() {
        session?.closeSession(completion: { (result) in
            switch (result) {
            case .Success:
                log.info("Session closed")
            case .Failure(let error):
                log.error("Close failed, error=\(String(describing:error))")
            }
        })
    }

    @IBAction func didTapPause(_ sender: Any) {
        closeSession()
    }
    
    @IBAction func didTapStop(_ sender: Any) {
    }

    func updateLabels() {
        updateScannerInfoLabel()
        updateTaskLabel()
        updateStatusLabel()
        updateScannedImagesLabel()
    }
    
    func updateScannerInfoLabel() {
        var label = "No scanner selected."
        defer {
            selectedScannerLabel.text = label
        }
        
        if let scannerJSON = UserDefaults.standard.string(forKey: "scanner") {
            do {
                let scannerInfo = try JSONDecoder().decode(ScannerInfo.self, from: (scannerJSON.data(using: .utf8))!)
                if let scannerName = scannerInfo.friendlyName {
                    label = scannerName
                }
            } catch {
                log.error("Error deserializing scannerInfo: \(String(describing:error))")
            }
        }
    }
    
    func updateTaskLabel() {
        var label = "No task selected."
        defer {
            selectedTaskLabel.text = label
        }
        
        if let taskName = UserDefaults.standard.string(forKey: "taskName") {
            label = taskName
        }
    }
    
    func updateScannedImagesLabel() {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
        let files = try? FileManager.default.contentsOfDirectory(atPath: docsURL.path)
        let count = files?.count ?? 0

        if (count == 1) {
            scannedImagesLabel.text = "1 scanned image"
        } else {
            scannedImagesLabel.text = "\(count) scanned images"
        }
    }
    
    func updateStatusLabel() {
        let state = self.session?.sessionState?.rawValue
        var text = (state ?? "no session")
        text = text + "\n\(lastImageNameReceived)"
        self.sessionStatusLabel.text = text
        
    }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
}
