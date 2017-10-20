//
//  BRLinkPlugin.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 3/10/16.
//  Copyright (c) 2016 breadwallet LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


// Updated by Farrukh Askari <farrukh.askari01@gmail.com> on 3:22 PM 17/4/17.

import Foundation
import SafariServices

@objc class BRLinkPlugin: NSObject, BRHTTPRouterPlugin, SFSafariViewControllerDelegate {
    var controller: UIViewController
    var hasBrowser = false
    
    init(fromViewController: UIViewController) {
        self.controller = fromViewController
        super.init()
    }
    
    func hook(_ router: BRHTTPRouter) {
        // opens any url that UIApplication.openURL can open
        // arg: "url" - the url to open
        router.get("/_open_url") { (request, match) -> BRHTTPResponse in
            if let encodedUrls = request.query["url"] , encodedUrls.count == 1 {
                if let decodedUrl = encodedUrls[0].removingPercentEncoding, let url = URL(string: decodedUrl) {
                    print("[BRLinkPlugin] /_open_url \(decodedUrl)")
                    UIApplication.shared.openURL(url)
                    return BRHTTPResponse(request: request, code: 204)
                }
            }
            return BRHTTPResponse(request: request, code: 400)
        }
        
        // opens the maps app for directions
        // arg: "address" - the destination address
        // arg: "from_point" - the origination point as a comma separated pair of floats - latitude,longitude
        router.get("/_open_maps") { (request, match) -> BRHTTPResponse in
            let invalidResp = BRHTTPResponse(request: request, code: 400)
            guard let toAddress = request.query["address"] , toAddress.count == 1 else {
                return invalidResp
            }
            guard let fromPoint = request.query["from_point"] , fromPoint.count == 1 else {
                return invalidResp
            }
            guard let url = URL(string: "http://maps.apple.com/?daddr=\(toAddress[0])&spn=\(fromPoint[0])") else {
                print("[BRLinkPlugin] /_open_maps unable to construct url")
                return invalidResp
            }
            UIApplication.shared.openURL(url)
            return BRHTTPResponse(request: request, code: 204)
        }
        
        // opens the in-app browser for the provided URL
        router.get("/_browser") { (request, _) -> BRHTTPResponse in
            if #available(iOS 9.0, *) {
                if self.hasBrowser {
                    return BRHTTPResponse(request: request, code: 409)
                }
                guard let toURL = request.query["url"], toURL.count == 1 else {
                    return BRHTTPResponse(request: request, code: 400)
                }
                guard let escapedToURL = toURL[0].removingPercentEncoding, let url = URL(string: escapedToURL) else {
                    return BRHTTPResponse(request: request, code: 400)
                }

                let safari = SFSafariViewController(url: url)
                safari.delegate = self
                self.hasBrowser = true
                DispatchQueue.main.async {
                    self.controller.present(safari, animated: true, completion: nil)
                }
                return BRHTTPResponse(request: request, code: 204)
            } else {
                // Fallback on earlier versions
                return BRHTTPResponse(request: request, code: 404)
            }
        }
    }
    
    @available(iOS 9.0, *)
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        hasBrowser = false
    }
}
