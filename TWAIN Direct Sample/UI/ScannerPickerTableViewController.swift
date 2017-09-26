//
//  ScannerPickerTableViewController.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-25.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import UIKit

class ScannerPickerTableViewController: UITableViewController {

    var serviceDiscoverer: ServiceDiscoverer?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        serviceDiscoverer = ServiceDiscoverer(delegate: self)

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        serviceDiscoverer?.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        serviceDiscoverer?.stop()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source
}

extension ScannerPickerTableViewController : ServiceDiscovererDelegate {
    func discoverer(_ discoverer: ServiceDiscoverer, didDiscover scanners: [ScannerInfo]) {
        log.info("hi")
    }
}
