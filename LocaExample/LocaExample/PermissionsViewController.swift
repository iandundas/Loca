//
//  ViewController.swift
//  LocaExample
//
//  Created by Ian Dundas on 24/11/2016.
//  Copyright © 2016 Tacks. All rights reserved.
//

import UIKit
import ReactiveKit
import Loca

class PermissionsViewController: UIViewController {

    private let authProvider = LocationAuthorizationProvider()
    
    let stream = PushStream<Void>()
    
    @IBAction func tappedPermission(sender: AnyObject) {
        authProvider.authorize().observe { [weak self] event in
            guard let strongSelf = self else {return}
            
            switch(event){
            case .Completed:
                strongSelf.performSegueWithIdentifier("ShowLocation", sender: nil)
            case .Failure(_):
                print("failed")
            default:break;
            }
        }.disposeIn(rBag)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        //
        guard let destination = segue.destinationViewController as? LocationsViewController else {return}
        guard let locationProvider = LocationProvider() else {return}
        
        destination.locationProvider = locationProvider
    }

}

