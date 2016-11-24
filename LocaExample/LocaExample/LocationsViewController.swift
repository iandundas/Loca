//
//  LocationsViewController.swift
//  LocaExample
//
//  Created by Ian Dundas on 24/11/2016.
//  Copyright © 2016 Tacks. All rights reserved.
//

import UIKit
import Loca
import ReactiveKit


class LocationsViewController: UIViewController{
    
    var locationProvider: LocationProvider? = nil
    
    @IBOutlet var stackView: UIStackView!
    @IBAction func didTapStart(sender: AnyObject) {
        start()
    }
    
    func start() {
        guard let locationProvider = locationProvider else {return}
        
        let operation = locationProvider.accurateLocationOperation(meterAccuracy: 40)
        operation
            .observeIn(Queue.main.context)
            .observe { [weak self] event in
            switch event {
            case let .Next(accuracy):
                self?.addMessage(accuracy.debugDescription)
                
            case let .Failure(error):
                self?.addMessage("Hit failure: \(error)")
                
            case .Completed:
                self?.addMessage("Completed.")
            }
        }.disposeIn(rBag)
    }
    
    func addMessage(message: String) {
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.sizeToFit()
        
        stackView.insertArrangedSubview(label, atIndex: 0)
    }
    
    
}
