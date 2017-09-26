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
        session?.open(completion: { result in
            switch (result) {
            case .Success:
                log.info("Success")
            case .Failure(let error):
                log.info("Failure: \(String(describing:error))")
            }
        })
    }
    
    @IBAction func ddTapPause(_ sender: Any) {
        
    }
    
    @IBAction func didTapStop(_ sender: Any) {
        
    }
}
