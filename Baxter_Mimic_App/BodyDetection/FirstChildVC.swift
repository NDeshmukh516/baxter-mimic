//
//  FirstChildVC.swift
//  BodyDetection
//
//  Created by Nikhil Deshmukh on 4/12/21.
//  Copyright © 2021 Apple. All rights reserved.
//

import UIKit
import SceneKit
let label = UILabel()
class FirstChildVC: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        label.text = "Welcome"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            //stick the top of the label to the top of its superview:
            label.topAnchor.constraint(equalTo: view.topAnchor),

            //stick the left of the label to the left of its superview
            //if the alphabet is left-to-right, or to the right of its
            //superview if the alphabet is right-to-left:
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),

            //stick the label's bottom to the bottom of its superview:
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        
    }
    func convert(log: simd_float4x4) -> String {
        var element = log[0][0]
        var stringElement = String(format: "%.2f", element)
        var final = ""
        
        for outer in 0...3 {
            for inner in 0...3 {
                element = log[outer][inner]
                stringElement = String(format: "%.2f", element)
                final += " \(stringElement)"
            }
            final += "\n"
        }
        return final
        
    }
    func updateLabelBlank() {
        label.text = ""
    }
    
    func updateLabel(send: String) {
        label.text = send
        label.numberOfLines = 0;
        label.sizeToFit()
        label.layoutIfNeeded()
    }
    
    
}
