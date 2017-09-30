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
    
    var session: Session?
    var imageReceiver: ImageReceiver?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }
    
    @IBAction func didTapStart(_ sender: Any) {
        guard let url = URL(string: "http://DESKTOP-48KEF92.local:34034/") else {
            return
        }
        let scanner = ScannerInfo(url: url, fqdn: "DESKTOP-48KEF92.local", txtDict: [String:String]())
        session = Session(scanner: scanner)
        
        imageReceiver = ImageReceiver()
        session?.delegate = imageReceiver
        
        session?.open { result in
            switch (result) {
            case .Success:
                log.info("Success")
                self.sendTask()
            case .Failure(let error):
                log.info("Failure: \(String(describing:error))")
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
}
