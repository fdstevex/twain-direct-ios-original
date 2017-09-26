//
//  AppDelegate.swift
//  TWAIN Direct Sample
//
//  Created by Steve Tibbett on 2017-09-21.
//  Copyright © 2017 Visioneer, Inc. All rights reserved.
//

import UIKit

let log = SwiftyBeaver.self

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        setupLogging()
        
        return true
    }

    func setupLogging() {
        let console = ConsoleDestination()
        console.format = "$DHH:mm:ss$d $L $M"
        console.asynchronously = false
        log.addDestination(console)
    }
}

