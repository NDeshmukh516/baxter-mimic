/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's main view controller.
*/

import UIKit
import RealityKit
import SceneKit
import ARKit
import Combine
import AVFoundation
import Vision
import RBSManager

// Global Variables
var temp = simd_float4x4()
var left_End = simd_float4x4()
var right_End = simd_float4x4()
var vectorString = String()
var actionString = String()
var memory = [Float64()]
var record = false

// Global booleans for displaying transfrom matricies
var displayLeft = false
var displayLeftArm = false
var displayLeftShoulder = false

// Logging Global Variables for transform matricies
var Hand = ""
var Arm = ""
var Shoulder = ""
var tempString = ""

// Gesture Information
var thumbTip: CGPoint?
var indexTip: CGPoint?
var middleTip: CGPoint?
var currentFrame: ARFrame?

// Global array of RPY angles - DEPRECATED
var angles = [Float()]

// Global variables for quaternion data display - DEPRECATED
var or_x = Float()
var or_y = Float()
var or_z = Float()
var or_w = Float()

// Global variables for end effector quaternion data to be published
var data_x = Float64()
var data_y = Float64()
var data_z = Float64()

class ViewController: UIViewController, ARSessionDelegate, RBSManagerDelegate, UIColorPickerViewControllerDelegate {
    
    // Gesture Information
    private var cameraView: CameraView { view as! CameraView }
    @IBOutlet var overlayView: OverlayView!
    
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var cameraFeedSession: AVCaptureSession?
    private var handPoseRequest = VNDetectHumanHandPoseRequest()

    private let drawOverlay = CAShapeLayer()
    private let drawPath = UIBezierPath()
    private var evidenceBuffer = [HandGestureProcessor.PointsPair]()
    private var lastDrawPoint: CGPoint?
    private var isFirstSegment = true
    private var lastObservationTimestamp = Date()

    private var gestureProcessor = HandGestureProcessor()
    // -------------------------------------------------------------

    // Instantiate Second View Controller
    let firstChildVC = FirstChildVC()
    
    // Storyboard Items
    @IBOutlet var Recording_Label: UILabel!
    @IBOutlet var Playing_Label: UILabel!
    @IBOutlet var arView: ARView!
    @IBOutlet var toolbar: UIToolbar!
    @IBOutlet var LiveView: UIVisualEffectView!
    @IBOutlet var PlayView: UIVisualEffectView!
    @IBOutlet weak var ConfidenceLabel: UILabel!
    var connectButton: UIBarButtonItem?
    var hostButton: UIBarButtonItem?
    var hideButton: UIBarButtonItem?
    var flexibleToolbarSpace: UIBarButtonItem?
    var hideSwitch = false
    
    var badTimer = 0
    
    // Sending message timer
    var controlTimer: Timer?
    
    // RBSManager Items
    var baxterManager: RBSManager?
    var leftJointPublisher: RBSPublisher?
    var rightJointPublisher: RBSPublisher?
    var gesturePublisher: RBSPublisher?
    var actionSubscriber: RBSSubscriber?
    var action_data: StringMessage!
    var AngleArray = Float32MultiArrayMessage()
    var PrevAngleArray_l = Float32MultiArrayMessage()
    var PrevAngleArray_r = Float32MultiArrayMessage()
    var gestureResult = StringMessage()
    
    // User settings
    var socketHost: String?
    
    // RBSManager Functinos
    func manager(_ manager: RBSManager, threwError error: Error) {
        if (manager.connected == false) {
        }
        print(error.localizedDescription)
    }
    
    func managerDidConnect(_ manager: RBSManager) {
        updateToolbarItems()
    }
    
    func manager(_ manager: RBSManager, didDisconnect error: Error?) {
        updateToolbarItems()
        print(error?.localizedDescription ?? "connection did disconnect")
    }
    
    // Host button to input ROS-Bridge Server IP and Port - xxx.xxx.x.xxx:9090
    @IBAction func onHostButton() {
        // change the host used by the websocket
        let alertController = UIAlertController(title: "Enter socket host", message: "IP or name of ROS master", preferredStyle: UIAlertController.Style.alert)
        alertController.addTextField { (textField : UITextField) -> Void in
            textField.placeholder = "Host"
            textField.text = self.socketHost
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel) { (result : UIAlertAction) -> Void in
        }
        let okAction = UIAlertAction(title: "OK", style: UIAlertAction.Style.default) { (result : UIAlertAction) -> Void in
            if let textField = alertController.textFields?.first {
                self.socketHost = textField.text
                self.saveSettings()
            }
        }
        alertController.addAction(cancelAction)
        alertController.addAction(okAction)
        self.present(alertController, animated: true, completion: nil)
    }
    
    // Connect Button to connect to ROS-Bridge Server
    @IBAction func onConnectButton() {
        if baxterManager?.connected == true {
            baxterManager?.disconnect()
            connectButton!.title = "Connect"
        } else {
            if socketHost != nil {
                // the manager will produce a delegate error if the socket host is invalid
                baxterManager?.connect(address: socketHost!)
                updateButtonStates()
            } else {
                // print log error
                print("Missing socket host value --> use host button")
            }
        }
    }
    
    @IBAction func onHideButton() {
        hideSwitch = !hideSwitch
        if (hideSwitch) {
            hideButton!.title = "Un-Hide"
            ConfidenceLabel.isHidden = true
            ArmAngle.isHidden = true
            ForearmAngle.isHidden = true
            HandAngle.isHidden = true
            ShoulderAngle.isHidden = true
            HandAngleW1.isHidden = true
        }
        else {
            hideButton!.title = "Hide"
            ConfidenceLabel.isHidden = false
            ArmAngle.isHidden = false
            ForearmAngle.isHidden = false
            HandAngle.isHidden = false
            ShoulderAngle.isHidden = false
            HandAngleW1.isHidden = false
        }
    }
    
    // Update Button displays within the toolbars
    func updateButtonStates() {
        if baxterManager?.connected == true {
            connectButton!.title = "Disconnect"
        }
    }
    
    // Update Top Toolbar Items
    func updateToolbarItems() {
        if baxterManager?.connected == true {
            toolbar.setItems([connectButton!, flexibleToolbarSpace!, hideButton!], animated: true)
            updateButtonStates()
        } else {
            toolbar.setItems([connectButton!, flexibleToolbarSpace!, hideButton!, flexibleToolbarSpace!, hostButton!], animated: true)
        }
    }
    
    // Initialize second viewcontroller used to display data
    func addFirstChild() {
        addChild(firstChildVC)
        view.addSubview(firstChildVC.view)
        firstChildVC.didMove(toParent: self)
        firstChildVC.view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        setFirstChildVCConstraints()
    }

    // Configure second viewcontroller used to display data
    func setFirstChildVCConstraints() {
        firstChildVC.view.translatesAutoresizingMaskIntoConstraints = false
        firstChildVC.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20).isActive = true
        firstChildVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20).isActive = true
        firstChildVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20).isActive = true
        firstChildVC.view.heightAnchor.constraint(equalToConstant: 200).isActive = true
    }
    
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [0, 0, 0] // Offset the character if wanted
    let characterAnchor = AnchorEntity()
    
    // On App startup, create ROS manager and display all buttons and toolbars
    override func viewDidLoad() {
        
        // Create second mini view controller
        super.viewDidLoad()
//        addFirstChild()
        
        // Gesture Information
        drawOverlay.frame = view.layer.bounds
        drawOverlay.lineWidth = 5
        drawOverlay.strokeColor = #colorLiteral(red: 0.6, green: 0.1, blue: 0.3, alpha: 1).cgColor
        drawOverlay.fillColor = #colorLiteral(red: 0.9999018312, green: 1, blue: 0.9998798966, alpha: 0).cgColor
        drawOverlay.lineCap = .round
        view.layer.addSublayer(drawOverlay)
        // This sample app detects one hand only.
        handPoseRequest.maximumHandCount = 1
        // Add state change handler to hand gesture processor.
        gestureProcessor.didChangeStateClosure = { [weak self] state in
            self?.handleGestureStateChange(state: state)
        }
        // Add double tap gesture recognizer for clearing the draw path.
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        recognizer.numberOfTouchesRequired = 1
        recognizer.numberOfTapsRequired = 2
        view.addGestureRecognizer(recognizer)
        // -----------------------------------------------
        
        // Background color indicators for rostopic labels
        LiveView.backgroundColor = UIColor.clear
        PlayView.backgroundColor = UIColor.clear
        LiveView.layer.cornerRadius = 13
        PlayView.layer.cornerRadius = 13
        LiveView.clipsToBounds = true
        PlayView.clipsToBounds = true
        
        // Define RBSManager
        baxterManager = RBSManager.sharedManager()
        baxterManager?.delegate = self
        
        // Load settings to retrieve stored host data
        loadSettings()
        
        hostButton = UIBarButtonItem(title: "Host", style: .plain, target: self, action: #selector(onHostButton))
        connectButton = UIBarButtonItem(title: "Connect", style: .plain, target: self, action: #selector(onConnectButton))
        hideButton = UIBarButtonItem(title: "Hide", style: .plain, target: self, action: #selector(onHideButton))
        flexibleToolbarSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
        toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
        updateToolbarItems()
        
        // Create Publishers and Subscribers
        leftJointPublisher = baxterManager?.addPublisher(topic: "robot/ios/commands/left", messageType: "std_msgs/Float32MultiArray", messageClass: Float32MultiArrayMessage.self)
        rightJointPublisher = baxterManager?.addPublisher(topic: "robot/ios/commands/right", messageType: "std_msgs/Float32MultiArray", messageClass: Float32MultiArrayMessage.self)
        gesturePublisher = baxterManager?.addPublisher(topic: "robot/gestures", messageType: "std_msgs/String", messageClass: StringMessage.self)
        
        actionSubscriber = baxterManager?.addSubscriber(topic: "robot/connection_server", messageClass: StringMessage.self, response: { (message) -> (Void) in
            self.action_data = message as? StringMessage
            self.updateWithMessage(self.action_data)
        })
        actionSubscriber?.messageType = "std_msgs/String"
        
        // Create memory for baxer angle array data
        PrevAngleArray_l.data = [0, 0, 0, 0, 0]
        PrevAngleArray_r.data = [0, 0, 0, 0, 0]
    }
    
    // Subscriber Callback to update labels if Recording or Playing Actions
    func updateWithMessage(_ message: StringMessage) {
        actionString = message.data!
        if actionString == "Playing" {
            Playing_Label!.text = "Sending"
            Recording_Label!.textColor = UIColor.white
            Recording_Label.backgroundColor = UIColor.clear
            PlayView.backgroundColor = UIColor.blue.withAlphaComponent(0.7)
            record = true
        }
        else {
            Playing_Label!.text = "Not Sending"
            Recording_Label!.textColor = UIColor.white
            Recording_Label.backgroundColor = UIColor.clear
            PlayView.backgroundColor = UIColor.clear
            record = false
        }
    }

    
    // Load settings for the host button
    func loadSettings() {
        let defaults = UserDefaults.standard
        socketHost = defaults.string(forKey: "socket_host")
    }
    
    // Save settings for the host button
    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(socketHost, forKey: "socket_host")
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // On first app load with ARKIT initialing, execute.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        arView.session.delegate = self
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }

        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)
        
        arView.scene.addAnchor(characterAnchor)
        
        
        // Asynchronously load the 3D character.
        var cancellable: AnyCancellable? = nil
        cancellable = Entity.loadBodyTrackedAsync(named: "character/robot").sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Error: Unable to load model: \(error.localizedDescription)")
                }
                cancellable?.cancel()
        }, receiveValue: { (character: Entity) in
            if let character = character as? BodyTrackedEntity {
                // Scale the character to human size
                character.scale = [1, 1, 1]
                self.character = character
                cancellable?.cancel()
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })
        
    }
    
    
    // Gesture Recognition Helper Functions
    func processPoints(thumbTip: CGPoint?, indexTip: CGPoint?) {
        // Check that we have both points.
        guard let thumbPoint = thumbTip, let indexPoint = indexTip else {
            // If there were no observations for more than 2 seconds reset gesture processor.
            if Date().timeIntervalSince(lastObservationTimestamp) > 2 {
                gestureProcessor.reset()
            }
            overlayView.showPoints([], color: .clear)
            return
        }
        
        let transform = CGAffineTransform.identity
            .scaledBy(x: 1, y: -1)
            .translatedBy(x: 0, y: -arView.frame.height)
            .scaledBy(x: arView.frame.width, y: arView.frame.height)

        // Convert points from Vision coordinates to UIKit pixel locations.
        let thumbPointConverted = thumbPoint.applying(transform)
        let indexPointConverted = indexPoint.applying(transform)
        
//        print(thumbPoint)
//        print("----------------------------------")
//        print(thumbPointConverted)
//        print("----------------------------------")

        // Process new points
        gestureProcessor.processPointsPair((thumbPointConverted, indexPointConverted))
    }

    func processPoints2(thumbTip: CGPoint?, middleTip: CGPoint?) {
        // Check that we have both points.
        guard let thumbPoint = thumbTip, let middlePoint = middleTip else {
            // If there were no observations for more than 2 seconds reset gesture processor.
            if Date().timeIntervalSince(lastObservationTimestamp) > 2 {
                gestureProcessor.reset()
            }
            overlayView.showPoints([], color: .clear)
            return
        }
        
        let transform = CGAffineTransform.identity
            .scaledBy(x: 1, y: -1)
            .translatedBy(x: 0, y: -arView.frame.height)
            .scaledBy(x: arView.frame.width, y: arView.frame.height)

        // Convert points from Vision coordinates to UIKit pixel locations.
        let thumbPointConverted = thumbPoint.applying(transform)
        let middlePointConverted = middlePoint.applying(transform)

        // Process new points
        gestureProcessor.processPointsPair2((thumbPointConverted, middlePointConverted))
    }

    private func handleGestureStateChange(state: HandGestureProcessor.State) {
        let pointsPair = gestureProcessor.lastProcessedPointsPair
        let pointsPair2 = gestureProcessor.lastProcessedPointsPair2
        var tipsColor: UIColor
        switch state {
        case .possiblePinch, .possibleApart:
            tipsColor = .orange
            ConfidenceLabel.text = "Possible"
        case .pinched:
            tipsColor = .green
            ConfidenceLabel.text = "Pinched"
            gestureResult.data = "Close"
            Recording_Label!.text = "Closed"
            Recording_Label!.textColor = UIColor.white
            Recording_Label.backgroundColor = UIColor.clear
            LiveView.backgroundColor = UIColor.cyan.withAlphaComponent(0.7)
            
            gesturePublisher?.publish(gestureResult)
        case .apart, .unknown:
            tipsColor = .red
            ConfidenceLabel.text = "Apart"
            gestureResult.data = "Open"
            Recording_Label!.text = "Open"
            Recording_Label!.textColor = UIColor.white
            Recording_Label.backgroundColor = UIColor.clear
            LiveView.backgroundColor = UIColor.clear
            gesturePublisher?.publish(gestureResult)
        }
        overlayView.showPoints([pointsPair.thumbTip, pointsPair.middleTip, pointsPair2.indexTip], color: tipsColor)
    }
    @IBAction func handleGesture(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }
    }
    
    @IBOutlet weak var ArmAngle: UILabel!
    @IBOutlet weak var ForearmAngle: UILabel!
    @IBOutlet weak var HandAngle: UILabel!
    @IBOutlet weak var ShoulderAngle: UILabel!
    @IBOutlet weak var HandAngleW1: UILabel!
    
    // Calculate Angle of Center Joint given 3 joint locations
    private func calculateAngle(Joint_A: SCNVector3, Joint_B: SCNVector3, Joint_C: SCNVector3) -> Float32 {
        let radians = atan2(Joint_C.y - Joint_B.y, Joint_C.x - Joint_B.x) - atan2(Joint_A.y - Joint_B.y, Joint_A.x - Joint_B.x)
        var angle = abs(radians * 180/Float.pi)
        if angle > 180.0 {
            angle = 360 - angle
        }
        return angle
    }
    
    private func tanyz(jointPos: SCNVector3) -> Float32 {
        let radians = atan2(jointPos.y, jointPos.z)
        return radians
    }
    
    private func tanxz(jointPos: SCNVector3) -> Float32 {
        let radians = atan2(jointPos.x, jointPos.z)
        return radians
    }
    
    private func tanzx(jointPos: SCNVector3) -> Float32 {
        let radians = atan2(jointPos.z, jointPos.x)
        return radians
    }
    
    // New Gesture Configuration
    // -------------------------------------------------------------
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        if badTimer > 6 {
            badTimer = 0
            
            // Get the capture image (which is a cvPixelBuffer) from the current ARFrame
            let cvpixelBuffer : CVPixelBuffer? = (frame.capturedImage)
            if cvpixelBuffer == nil {return}
            
            var info = CMSampleTimingInfo()
            info.presentationTimeStamp = CMTime.zero
            info.duration = CMTime.invalid
            info.decodeTimeStamp = CMTime.invalid
            var formatDesc: CMFormatDescription? = nil
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: cvpixelBuffer!, formatDescriptionOut: &formatDesc)
            var sampleBuffer: CMSampleBuffer? = nil

            CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                            imageBuffer: cvpixelBuffer!,
            formatDescription: formatDesc!,
            sampleTiming: &info,
            sampleBufferOut: &sampleBuffer);
            
            // Conduct Gesture Recognition
            if let sampleBuffer = sampleBuffer {
                let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
                do {
                    try handler.perform([handPoseRequest])
                    guard let observation = handPoseRequest.results?.first else {return}
                    
                    // Get points for thumb and index finger and middle finger.
                    let thumbPoints = try observation.recognizedPoints(.thumb)
                    let middleFingerPoints = try observation.recognizedPoints(.middleFinger)
                    let indexFingerPoints = try observation.recognizedPoints(.indexFinger)
                    
                    // Look for tip points.
                    guard let thumbTipPoint = thumbPoints[.thumbTip], let middleTipPoint = middleFingerPoints[.middleTip], let indexTipPoint = indexFingerPoints[.indexTip] else {
                        return
                    }
                    
                    // Ignore low confidence points.
                    guard thumbTipPoint.confidence > 0.2 && middleTipPoint.confidence > 0.2 else {
                        return
                    }
                    
                    guard thumbTipPoint.confidence > 0.2 && indexTipPoint.confidence > 0.2 else {
                        return
                    }
                    
                    // Convert points from Vision coordinates to UIKit coordinates (Pixels). (Flip X and Y)
                    thumbTip = CGPoint(x: thumbTipPoint.location.y, y: 1 - thumbTipPoint.location.x)
                    middleTip = CGPoint(x: middleTipPoint.location.y, y: 1 - middleTipPoint.location.x)
                    indexTip = CGPoint(x: indexTipPoint.location.y, y: 1 - indexTipPoint.location.x)
                    
            
            } catch {
                return
                }
            }
            
            defer {
                DispatchQueue.main.async {
                    // Process and Convert Points
                    self.processPoints(thumbTip: thumbTip, indexTip: indexTip)
                    self.processPoints2(thumbTip: thumbTip, middleTip: middleTip)
                }
            }
            sampleBuffer = nil
        }
        else {
            badTimer = badTimer + 1
        }
    }
    
    // Initialize ARKIT Session
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
            
            // Update the position of the character anchor's position.
            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
            characterAnchor.position = bodyPosition + characterOffset
            // Also copy over the rotation of the body anchor, because the skeleton's pose
            // in the world is relative to the body anchor's rotation.
            characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
            
            // Gather all relevant universal transforms(Relative to Hip joint)
            left_End = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "left_handIndexEnd_joint"))!
            right_End = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "right_handIndexEnd_joint"))!
            
            let leftHand = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "left_hand_joint"))
            let leftArm = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "left_arm_joint"))
            let leftForearm = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "left_forearm_joint"))
            let leftShoulder = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "left_shoulder_1_joint"))
            let leftHandIndex = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "left_handIndexEnd_joint"))
            let rightHand = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "right_hand_joint"))
            let rightArm = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "right_arm_joint"))
            let rightForearm = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "right_forearm_joint"))
            let rightShoulder = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "right_shoulder_1_joint"))
            let rightHandIndex = bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: "right_handIndexEnd_joint"))
            
            // Convert to 4x4 Matricies
            let leftHandMatrix = SCNMatrix4(leftHand!)
            let leftArmMatrix = SCNMatrix4(leftArm!)
            let leftForearmMatrix = SCNMatrix4(leftForearm!)
            let leftShoulderMatrix = SCNMatrix4(leftShoulder!)
            let leftHandIndexMatrix = SCNMatrix4(leftHandIndex!)
            let rightHandMatrix = SCNMatrix4(rightHand!)
            let rightArmMatrix = SCNMatrix4(rightArm!)
            let rightForearmMatrix = SCNMatrix4(rightForearm!)
            let rightShoulderMatrix = SCNMatrix4(rightShoulder!)
            let rightHandIndexMatrix = SCNMatrix4(rightHandIndex!)
            
            // Get positional data
            let leftHandPosition = leftHandMatrix.position()
            let leftArmPosition = leftArmMatrix.position()
            let leftForearmPosition = leftForearmMatrix.position()
            let leftShoulderPosition = leftShoulderMatrix.position()
            let LeftHandIndexPosition = leftHandIndexMatrix.position()
            let rightHandPosition = rightHandMatrix.position()
            let rightArmPosition = rightArmMatrix.position()
            let rightForearmPosition = rightForearmMatrix.position()
            let rightShoulderPosition = rightShoulderMatrix.position()
            let rightHandIndexPosition = rightHandIndexMatrix.position()
            
//                let masterList = bodyAnchor.skeleton.jointModelTransforms
//                let masterNames = bodyAnchor.skeleton.definition.jointNames
//                let parentIndecis = bodyAnchor.skeleton.definition.parentIndices
            
            // Left Shoulder Pitch
            var leftArmAngle = calculateAngle(Joint_A: leftShoulderPosition, Joint_B: leftArmPosition, Joint_C: leftForearmPosition)
            leftArmAngle = abs(leftArmAngle - 90.0)
            if leftForearmPosition.y > leftShoulderPosition.y {
                leftArmAngle = 180.0 - leftArmAngle
            }
            let S1 = String(format: "%.2f", leftArmAngle)
            ArmAngle.text = "S1 : " + S1
            
            // Right Shoulder Pitch
            var rightArmAngle = calculateAngle(Joint_A: rightShoulderPosition, Joint_B: rightArmPosition, Joint_C: rightForearmPosition)
            rightArmAngle = abs(rightArmAngle - 90.0)
            if rightForearmPosition.y > rightShoulderPosition.y {
                rightArmAngle = 180.0 - rightArmAngle
            }
            
            // Left Elbow Pitch
            let leftForearmAngle = calculateAngle(Joint_A: leftArmPosition, Joint_B: leftForearmPosition, Joint_C: leftHandPosition)
            let E1 = String(format: "%.2f", leftForearmAngle)
            ForearmAngle.text = "E1 : " + E1
            
            // Right Elbow Pitch
            let rightForearmAngle = calculateAngle(Joint_A: rightArmPosition, Joint_B: rightForearmPosition, Joint_C: rightHandPosition)
            
            // Left Elbow Twist
            var jointPositionZ = leftHandPosition.z - leftForearmPosition.z
            var jointPositionY = leftHandPosition.y - leftForearmPosition.y
            var jointPosition = SCNVector3(0, jointPositionY, jointPositionZ)
            var leftElbowTwist = tanyz(jointPos: jointPosition)
            leftElbowTwist = (leftElbowTwist * 180.0/Float.pi) + 90.0
            let E0 = String(format: "%.2f", leftElbowTwist)
            HandAngle.text = "E0 : " + E0
            
            // Right Elbow Twist
            jointPositionZ = rightHandPosition.z - rightForearmPosition.z
            jointPositionY = rightHandPosition.y - rightForearmPosition.y
            jointPosition = SCNVector3(0, jointPositionY, jointPositionZ)
            var rightElbowTwist = tanyz(jointPos: jointPosition)
            rightElbowTwist = (rightElbowTwist * 180.0/Float.pi) + 90.0
            
            // Left Shoulder Twist
            jointPositionZ = leftForearmPosition.z - leftArmPosition.z
            var jointPositionX = leftForearmPosition.x - leftArmPosition.x
            jointPosition = SCNVector3(jointPositionX, 0, jointPositionZ)
            var leftShoulderTwist = tanxz(jointPos: jointPosition)
            leftShoulderTwist = (leftShoulderTwist * 180.0/Float.pi)
            let S0 = String(format: "%.2f", leftShoulderTwist)
            ShoulderAngle.text = "S0 : " + S0
            
            // Right Shoulder Twist
            jointPositionZ = rightForearmPosition.z - rightArmPosition.z
            jointPositionX = rightForearmPosition.x - rightArmPosition.x
            jointPosition = SCNVector3(jointPositionX, 0, jointPositionZ)
            var rightShoulderTwist = tanxz(jointPos: jointPosition)
            rightShoulderTwist = (rightShoulderTwist * 180.0/Float.pi)
            
            // Left Hand Pitch
            jointPositionZ = LeftHandIndexPosition.z - leftHandPosition.z
            jointPositionX = LeftHandIndexPosition.x - leftHandPosition.x
            jointPosition = SCNVector3(jointPositionX, 0, jointPositionZ)
            var leftHandAngle = tanzx(jointPos: jointPosition)
            leftHandAngle = (leftHandAngle * 180.0/Float.pi)
            let W1 = String(format: "%.2f", leftHandAngle)
            HandAngleW1.text = "W1 : " + W1
            
            // Right Hand Pitch
            jointPositionZ = rightHandIndexPosition.z - rightHandPosition.z
            jointPositionX = rightHandIndexPosition.x - rightHandPosition.x
            jointPosition = SCNVector3(jointPositionX, 0, jointPositionZ)
            var rightHandAngle = tanzx(jointPos: jointPosition)
            rightHandAngle = (rightHandAngle * 180.0/Float.pi)
            
            // Publish all angles to baxter left and right arms
            AngleArray.data = [leftShoulderTwist, leftArmAngle, leftElbowTwist, leftForearmAngle, leftHandAngle]
            
            
            print(AngleArray.data)
            if record == false {
                leftJointPublisher?.publish(AngleArray)
            }
//                if (angleChangeS0_l > 3 || angleChangeS1_l > 3 || angleChangeE0_l > 3 || angleChangeE1_l > 3 || angleChangeW1_l > 3) {
//                    leftJointPublisher?.publish(AngleArray)
//                    PrevAngleArray_l = AngleArray
//                }
            
            AngleArray.data = [rightShoulderTwist, rightArmAngle, rightElbowTwist, rightForearmAngle, rightHandAngle]
            
//                if (angleChangeS0_r > 3 || angleChangeS1_r > 3 || angleChangeE0_r > 3 || angleChangeE1_r > 3 || angleChangeW1_r > 3) {
//                    rightJointPublisher?.publish(AngleArray)
//                    PrevAngleArray_r = AngleArray
//                }
            if record == false {
                rightJointPublisher?.publish(AngleArray)
            }
                        
            
            if let character = character, character.parent == nil {
                // Attach the character to its anchor as soon as
                // 1. the body anchor was detected and
                // 2. the character was loaded.
                characterAnchor.addChild(character)
                
            }
        }
    }
}

// Joint Angle Calculations Helpers
extension SCNVector3 {
    
    init(_ vec: SCNVector3) {
        self.init()
        self.x = vec.x
        self.y = vec.y
        self.z = vec.z
    }
    
    /**
     * Returns the length (magnitude) of the vector described by the SCNVector3
     */
    func length() -> Float {
        return sqrt(x*x + y*y + z*z)
    }
    
    ///Get angle in radian
    static func angleBetween(_ v1: SCNVector3, _ v2: SCNVector3) -> Float {
        let cosinus = SCNVector3.dotProduct(left: v1, right: v2) / v1.length() / v2.length()
        let angle = acos(cosinus)
        return angle
    }

    /// Computes the dot product between two SCNVector3 vectors
    static func dotProduct(left: SCNVector3, right: SCNVector3) -> Float {
        return left.x * right.x + left.y * right.y + left.z * right.z
    }
}

extension SCNMatrix4 {
    
    // Extract XYZ data to a vector
    func position() -> SCNVector3 {
        let position = SCNVector3Make(self.m41, self.m42, self.m43)
        return position
    }
}
