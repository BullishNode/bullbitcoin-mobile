import CoreMotion
import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var entropyMotionChannel: FlutterEventChannel?
  private var entropyMotionHandler: EntropyMotionStreamHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let handler = EntropyMotionStreamHandler()
      let channel = FlutterEventChannel(
        name: "com.bullbitcoin.mobile/entropy_motion",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setStreamHandler(handler)
      entropyMotionHandler = handler
      entropyMotionChannel = channel
    }

    // workmanager_apple spawns a separate FlutterEngine per background task
    // (see BackgroundWorker.swift in workmanager_apple). Plugins registered
    // against `self` above only attach to the main app's engine — the BG
    // engine starts with an empty plugin registry. Without this callback,
    // every platform-channel call from tasksHandler (shared_preferences,
    // flutter_secure_storage, drift, lwk, etc.) fails with `channel-error`
    // "Unable to establish connection on channel: ...". Registering the
    // generated registrant against the BG engine makes all plugins usable
    // in the BG isolate.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.bullbitcoin.mobile.bitcoin-sync-id",
      frequency: NSNumber(value: 20 * 60)
    )
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.bullbitcoin.mobile.liquid-sync-id",
      frequency: NSNumber(value: 20 * 60)
    )
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.bullbitcoin.mobile.swaps-sync-id",
      frequency: NSNumber(value: 20 * 60)
    )
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.bullbitcoin.mobile.logs-prune-id",
      frequency: NSNumber(value: 20 * 60)
    )
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class EntropyMotionStreamHandler: NSObject, FlutterStreamHandler {
  private let manager = CMMotionManager()
  private let operationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.bullbitcoin.mobile.entropy-motion"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInteractive
    return queue
  }()
  private var eventSink: FlutterEventSink?
  private var sequence: Int64 = 0

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    stopUpdates()
    eventSink = events
    sequence = 0
    manager.accelerometerUpdateInterval = 0.01
    manager.gyroUpdateInterval = 0.01

    var started = false
    if manager.isAccelerometerAvailable {
      started = true
      manager.startAccelerometerUpdates(to: operationQueue) { [weak self] data, _ in
        guard let self, let data else { return }
        self.emit(
          source: 0,
          sensorTimestamp: data.timestamp,
          x: data.acceleration.x,
          y: data.acceleration.y,
          z: data.acceleration.z,
          accuracy: 0
        )
      }
    }
    if manager.isGyroAvailable {
      started = true
      manager.startGyroUpdates(to: operationQueue) { [weak self] data, _ in
        guard let self, let data else { return }
        self.emit(
          source: 1,
          sensorTimestamp: data.timestamp,
          x: data.rotationRate.x,
          y: data.rotationRate.y,
          z: data.rotationRate.z,
          accuracy: 0
        )
      }
    }

    if !started {
      stopUpdates()
      return FlutterError(
        code: "motion_unavailable",
        message: "No accelerometer or gyroscope is available",
        details: nil
      )
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopUpdates()
    return nil
  }

  private func emit(
    source: Int,
    sensorTimestamp: TimeInterval,
    x: Double,
    y: Double,
    z: Double,
    accuracy: Int
  ) {
    guard sensorTimestamp.isFinite, x.isFinite, y.isFinite, z.isFinite else {
      return
    }
    let sampleSequence = sequence
    sequence += 1
    let sensorTimestampNanos = Int64(max(0, sensorTimestamp * 1_000_000_000))
    let arrivalTimestampNanos = Int64(
      clamping: DispatchTime.now().uptimeNanoseconds
    )
    let sample: [Any] = [
      source,
      sampleSequence,
      sensorTimestampNanos,
      arrivalTimestampNanos,
      x,
      y,
      z,
      accuracy,
    ]
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(sample)
    }
  }

  private func stopUpdates() {
    manager.stopAccelerometerUpdates()
    manager.stopGyroUpdates()
    eventSink = nil
  }
}
