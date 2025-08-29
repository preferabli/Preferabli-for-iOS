//
//  AppDelegate.swift
//  WineRingSDKTest
//
//  Created by Nicholas Bortolussi on 5/29/20.
//  Copyright © 2020 RingIT, Inc,. All rights reserved.
//

import UIKit
import PreferabliDataSDK

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Update with your own keys.
        let YOUR_INTEGRATION_ID_HERE : NSNumber = 6301
        Preferabli.initialize(client_interface: "YOUR_CLIENT_INTERFACE_HERE", integration_id: YOUR_INTEGRATION_ID_HERE, logging_enabled: true)
        
        return true
    }
}

