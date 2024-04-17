//
//  ViewController.swift
//  SwiftQRScanner
//
//  Created by vinodiOS on 12/05/2017.
//  Copyright (c) 2017 vinodiOS. All rights reserved.
//

import UIKit
import SwiftQRScanner

class ViewController: UIViewController {
    
    @IBOutlet weak var resultLabel: UILabel!

    
    @IBAction func scanQRCode(_ sender: Any) {
        self.resultLabel.text = ""
        
        //Simple QR Code Scanner
        let scanner = QRCodeScannerController()
        scanner.delegate = self
        self.present(scanner, animated: true, completion: nil)
    }
    
    @IBAction func scanQRCodeWithExtraOptions(_ sender: Any) {
        self.resultLabel.text = ""
        
        //Configuration for QR Code Scanner
        var configuration = QRScannerConfiguration()
        configuration.cameraImage = UIImage(named: "camera")
        configuration.flashOnImage = UIImage(named: "flash-on")
        configuration.galleryImage = UIImage(named: "photos")
        
        let scanner = QRCodeScannerController(qrScannerConfiguration: configuration)
        scanner.delegate = self
        self.present(scanner, animated: true, completion: nil)
    }
    
}

extension ViewController: QRScannerCodeDelegate {
    func qrScanner(_ controller: UIViewController, didScanQRCodeWithResult result: String) {
        self.resultLabel.text = "Result: \n \(result)"
        print("result:\(result)")
    }
    
    func qrScanner(_ controller: UIViewController, didFailWithError error: SwiftQRCodeScanner.QRCodeError) {
        print("error:\(error.localizedDescription)")
    }
    
    func qrScannerDidCancel(_ controller: UIViewController) {
        print("QR Controller did cancel")
    }
}

