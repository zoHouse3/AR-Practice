//
//  ViewController.swift
//  AR Practice
//
//  Created by Eric Barnes - iOS on 12/27/23.
//

// TODO: Create button to retry session, instead of repeatedly asking to restart session in popup
// TODO: Show markers indicating different food spots . Test in geotracking enabled area

import UIKit
import ARKit
import RealityKit

class ViewController: UIViewController {
    @IBOutlet weak var arView: ARView!
    @IBOutlet weak var trackingLbl: UILabel!
    @IBOutlet weak var toastLbl: UILabel!
    @IBOutlet weak var restartBtn: UIButton!
    
    let coachingOverlay = ARCoachingOverlayView()
    let locationManager = CLLocationManager()
    
    var geoAnchors: [GeoAnchorWithData] = []
    
    var isGeoTrackingLocalized: Bool {
        if let status = arView.session.currentFrame?.geoTrackingStatus, status.state == .localized {
            return true
        }
        return false
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        // Set this view controller as the session's delegate.
        arView.session.delegate = self
        
        // Enable coaching.
        setupCoachingOverlay()
        
        // Set this view controller as the Core Location manager delegate.
        locationManager.delegate = self
        
        // Disable automatic configuration and set up geotracking
        arView.automaticallyConfigureSession = false
                
        // Run a new AR Session.
        restartSession()
                
        // Add tap gesture recognizers
        arView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTapOnARView(_:))))
    }
    
    func addGeoAnchor(at worldPosition: SIMD3<Float>) {
        arView.session.getGeoLocation(forPoint: worldPosition) { (location, altitude, error) in
            if let error = error {
                self.alertUser(withTitle: "Cannot add geo anchor",
                               message: "An error occurred while translating ARKit coordinates to geo coordinates: \(error.localizedDescription)")
                return
            }
            self.addGeoAnchor(at: location, altitude: altitude)
        }
    }
    
    func addGeoAnchor(at location: CLLocationCoordinate2D, altitude: CLLocationDistance? = nil) {
        var geoAnchor: ARGeoAnchor!
        if let altitude = altitude {
            geoAnchor = ARGeoAnchor(coordinate: location, altitude: altitude)
        } else {
            geoAnchor = ARGeoAnchor(coordinate: location)
        }
        
        addGeoAnchor(geoAnchor)
    }
    
    func addGeoAnchor(_ geoAnchor: ARGeoAnchor) {
        
        // Don't add a geo anchor if Core Location isn't sure yet where the user is.
        guard isGeoTrackingLocalized else {
            alertUser(withTitle: "Cannot add geo anchor", message: "Unable to add geo anchor because geotracking has not yet localized.")
            return
        }
        arView.session.add(anchor: geoAnchor)
    }

    func restartSession() {
        // Check geo-tracking location-based availability.
        ARGeoTrackingConfiguration.checkAvailability { [weak self] (available, error) in
            if !available {
                let errorDescription = error?.localizedDescription ?? ""
                let recommendation = "Please try again in an area where geotracking is supported."
//                let restartSession = UIAlertAction(title: "Restart Session", style: .default) { (_) in
//                    self.restartSession()
//                }
                let ok = UIAlertAction(title: "Ok", style: .default)
                self?.alertUser(withTitle: "Geotracking unavailable",
                               message: "\(errorDescription)\n\(recommendation)",
                               actions: [ok])
            } else {
                self?.restartBtn.isHidden = true
            }
        }
        
        // Re-run the ARKit session.
        let geoTrackingConfig = ARGeoTrackingConfiguration()
        geoTrackingConfig.planeDetection = [.horizontal]
        arView.session.run(geoTrackingConfig, options: .removeExistingAnchors)
        geoAnchors.removeAll()
        
        arView.scene.anchors.removeAll()
        
        trackingLbl.text = ""
        
        showToast("Running new AR session")
    }
    
    @IBAction func restartBtnTapped(_ sender: UIButton) {
        restartSession()
    }
    
    @objc func handleTapOnARView(_ sender: UITapGestureRecognizer) {
        let point = sender.location(in: view)
        
        // Perform ARKit raycast on tap location
        if let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
            addGeoAnchor(at: result.worldTransform.translation)
        } else {
            showToast("No raycast result.\nTry pointing at a different area\nor move closer to a surface.")
        }
    }
}

extension ViewController: GPXParserDelegate {
    func parseGPXFile(with url: URL) {
        guard let parser = GPXParser(contentsOf: url) else {
            showToast("Unable to open GPX file.")
            return
        }
        
        parser.delegate = self
        parser.parse()
    }
    
    func parser(_ parser: GPXParser, didFinishParsingFileWithAnchors anchors: [ARGeoAnchor]) {
        // Don't add geo anchors if geotracking isn't sure yet where the user is.
        guard isGeoTrackingLocalized else {
            alertUser(withTitle: "Cannot add geo anchor(s)", message: "Unable to add geo anchor(s) because geotracking has not yet localized.")
            return
        }
        
        if anchors.isEmpty {
            alertUser(withTitle: "No anchors added", message: "GPX file does not contain anchors or is invalid.")
            return
        }
        
        for anchor in anchors {
            addGeoAnchor(anchor)
        }
        
        showToast("\(anchors.count) anchor(s) added.")

    }
}

extension ViewController: ARSessionDelegate {
    
}

extension ViewController {
    func alertUser(withTitle title: String, message: String, actions: [UIAlertAction]? = nil) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            if let actions = actions {
                actions.forEach { alert.addAction($0) }
            } else {
                alert.addAction(UIAlertAction(title: "OK", style: .default))
            }
            self.present(alert, animated: true)
        }
    }
    
    func showToast(_ message: String, duration: TimeInterval = 2) {
        DispatchQueue.main.async {
            self.toastLbl.numberOfLines = message.components(separatedBy: "\n").count
            self.toastLbl.text = message
            self.toastLbl.isHidden = false
            
            // use tag to tell if label has been updated
            let tag = self.toastLbl.tag + 1
            self.toastLbl.tag = tag
            
            if duration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    // Do not hide if showToast is called again, before this block kicks in.
                    if self.toastLbl.tag == tag {
                        self.toastLbl.isHidden = true
                    }
                }
            }
        }
    }

}

extension ViewController: ARCoachingOverlayViewDelegate {
    
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        hideUIForCoaching(true)
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        hideUIForCoaching(false)
    }

    func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        restartSession()
    }

    // Sets up the coaching view.
    func setupCoachingOverlay() {
        coachingOverlay.delegate = self
        arView.addSubview(coachingOverlay)
        coachingOverlay.goal = .geoTracking // goal of overlay is to coach user for best geo tracking xp
        coachingOverlay.session = arView.session // ar session that overlay uses to provide coaching
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coachingOverlay.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
            coachingOverlay.centerYAnchor.constraint(equalTo: arView.centerYAnchor),
            coachingOverlay.widthAnchor.constraint(equalTo: arView.widthAnchor),
            coachingOverlay.heightAnchor.constraint(equalTo: arView.heightAnchor)
            ])
    }
    
    func hideUIForCoaching(_ active: Bool) {
        trackingLbl.isHidden = active
    }
}

extension ViewController: CLLocationManagerDelegate {
    
}
