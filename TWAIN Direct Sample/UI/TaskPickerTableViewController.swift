//
//  TaskPickerTableViewController.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-25.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import UIKit

class TaskPickerTableViewController: UITableViewController {

    @IBOutlet weak var selectedTaskLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let taskName = UserDefaults.standard.string(forKey: "taskName") ?? NSLocalizedString("No task selected", comment: "User has not picked a task yet")
        selectedTaskLabel.text = taskName
    }

}
