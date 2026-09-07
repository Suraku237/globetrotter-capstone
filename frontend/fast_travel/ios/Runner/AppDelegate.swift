import Flutter
import UIKit
import PushKit
import CallKit
import AVFAudio
import WebRTC
import flutter_callkit_incoming
import livekit_client

@main
@objc class AppDelegate: FlutterAppDelegate,
  PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private var voipRegistry: PKPushRegistry?
  private(set) var callEngine: FlutterEngine!
  private var runtimeChannel: FlutterMethodChannel?
  private var uiAttached = false
  private let discardedCalls = DiscardedCallProvider()
  private var answerTasks: [String: UIBackgroundTaskIdentifier] = [:]
  private var trackedCalls = Set<String>()
  private var pushChannel: FlutterMethodChannel?
  private let journalKey = "globetrotter.call_push.events"
  private var callKitAudioActive = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // One full Dart runtime owns authentication and media, including when
    // PushKit launches the process without creating a UIKit scene.
    let engine = FlutterEngine(
      name: "globetrotter-runtime", project: nil, allowHeadlessExecution: true)
    callEngine = engine
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    installChannels(engine)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes =
      UserDefaults.standard.bool(forKey: "flutter.call_push_enabled") ? [.voIP] : []
    voipRegistry = registry
    return launched
  }

  private func installChannels(_ engine: FlutterEngine) {
    let runtime = FlutterMethodChannel(
      name: "globetrotter/app_runtime", binaryMessenger: engine.binaryMessenger)
    runtime.setMethodCallHandler { [weak self] call, result in
      if call.method == "isUiAttached" {
        result(self?.uiAttached ?? false)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    runtimeChannel = runtime
    if let registrar = engine.registrar(forPlugin: "CallPushJournal") {
      let channel = FlutterMethodChannel(
        name: "globetrotter/call_push", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(nil); return }
        var journal = UserDefaults.standard.dictionary(forKey: self.journalKey) ?? [:]
        switch call.method {
        case "audioState":
          result(["callIds": self.nativeCallIDs(), "active": self.callKitAudioActive])
        case "takeError":
          result(UserDefaults.standard.string(forKey: "globetrotter.call_push.error"))
          UserDefaults.standard.removeObject(forKey: "globetrotter.call_push.error")
        case "syncAudioAvailability":
          guard let args = call.arguments as? [String: Any],
            let id = args["callId"] as? String,
            let usesCallKit = args["usesCallKit"] as? Bool else {
            result(FlutterError(code: "invalid_call", message: "Invalid audio call", details: nil))
            return
          }
          let ids = self.nativeCallIDs()
          guard UserDefaults.standard.bool(forKey: "flutter.call_push_enabled"),
            !UserDefaults.standard.bool(forKey: "flutter.call_push_suppressed_\(id)"),
            (usesCallKit ? ids.contains(id) : (ids.isEmpty && !self.callKitAudioActive)) else {
            result(FlutterError(
              code: "audio_call_changed", message: "The system call changed before audio was ready", details: nil))
            return
          }
          let available = usesCallKit ? self.callKitAudioActive : true
          LiveKitPlugin.setEngineAvailability(
            isInputAvailable: available, isOutputAvailable: available)
          result(nil)
        case "setEnabled":
          let enabled = call.arguments as? Bool == true
          self.voipRegistry?.desiredPushTypes = enabled ? [.voIP] : []
          if !enabled {
            LiveKitPlugin.setEngineAvailability(isInputAvailable: false, isOutputAvailable: false)
            for id in Array(self.answerTasks.keys) { self.finishAnswerTask(id) }
          }
          result(nil)
        case "runtimeConnected":
          if let id = call.arguments as? String { self.finishAnswerTask(id) }
          result(nil)
        case "pendingEvents":
          result(Array(journal.values))
        case "ackEvent":
          if let key = call.arguments as? String { journal.removeValue(forKey: key) }
          UserDefaults.standard.set(journal, forKey: self.journalKey)
          result(nil)
        case "clearEvents":
          UserDefaults.standard.removeObject(forKey: self.journalKey)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }

        func setUiAttached(_ attached: Bool) {
          uiAttached = attached
          runtimeChannel?.invokeMethod("uiStateChanged", arguments: attached)
        }

        private func reportRuntimeError(_ message: String) {
          UserDefaults.standard.set(message, forKey: "globetrotter.call_push.error")
          pushChannel?.invokeMethod("callError", arguments: message)
        }
      }
      pushChannel = channel
    }
  }

  func pushRegistry(
    _ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType, completion: @escaping () -> Void
  ) {
    let payloadData = payload.dictionaryPayload
    guard type == .voIP else { completion(); return }
    guard payloadData["type"] as? String == "incoming_call",
      let rawID = payloadData["call_id"] as? String,
      let uuid = UUID(uuidString: rawID),
      let kind = payloadData["kind"] as? String, ["voice", "video"].contains(kind),
      let rawExpiry = payloadData["expires_at"] as? String
    else { discardedCalls.reportAndEnd(completion: completion); return }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let expiry = formatter.date(from: rawExpiry) ?? ISO8601DateFormatter().date(from: rawExpiry)
    let id = uuid.uuidString.lowercased()
    guard let expiry = expiry, expiry > Date(),
      UserDefaults.standard.bool(forKey: "flutter.call_push_enabled"),
      !UserDefaults.standard.bool(forKey: "flutter.call_push_suppressed_\(id)"),
      !UserDefaults.standard.bool(forKey: "flutter.call_push_shown_\(id)"),
      let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance
    else { discardedCalls.reportAndEnd(completion: completion); return }
    if plugin.activeCalls().contains(where: { ($0["id"] as? String)?.lowercased() == id }) {
      discardedCalls.reportAndEnd(completion: completion)
      return
    }
    let data = flutter_callkit_incoming.Data(
      id: id, nameCaller: payloadData["caller_name"] as? String ?? "GlobeTrotter caller",
      handle: kind == "video" ? "Video call" : "Voice call", type: kind == "video" ? 1 : 0)
    data.appName = "GlobeTrotter"
    data.extra = [
      "type": "incoming_call", "call_id": id, "kind": kind, "expires_at": rawExpiry,
      "caller_name": data.nameCaller
    ]
    data.duration = max(1, Int(expiry.timeIntervalSinceNow * 1000))
    data.configureAudioSession = false
    data.audioSessionActive = false
    data.supportsHolding = false
    data.supportsDTMF = false
    data.maximumCallGroups = 1
    data.maximumCallsPerCallGroup = 1
    data.isShowMissedCallNotification = false
    // This gate is also retained by LiveKitPlugin before its engine/plugin
    // exists, which prevents capture during a cold PushKit wakeup.
    if !callKitAudioActive {
      LiveKitPlugin.setEngineAvailability(isInputAvailable: false, isOutputAvailable: false)
    }
    UserDefaults.standard.set(true, forKey: "flutter.call_push_shown_\(id)")
    trackedCalls.insert(id)
    // Complete only after CallKit's report callback, including its error path.
    plugin.showCallkitIncoming(data, fromPushKit: true, completion: completion)
  }

  private func record(_ action: String, call: Call) {
    let id = call.data.uuid.lowercased()
    guard UserDefaults.standard.bool(forKey: "flutter.call_push_enabled"),
      !UserDefaults.standard.bool(forKey: "flutter.call_push_suppressed_\(id)") else { return }
    var journal = UserDefaults.standard.dictionary(forKey: journalKey) ?? [:]
    let key = "\(id):\(action)"
    journal[key] = ["key": key, "id": id, "action": action]
    UserDefaults.standard.set(journal, forKey: journalKey)
    pushChannel?.invokeMethod(
      action == "decline" ? "callEnded" : "eventsAvailable",
      arguments: action == "decline" ? id : nil)
  }

  private func nativeCallIDs() -> [String] {
    return (SwiftFlutterCallkitIncomingPlugin.sharedInstance?.activeCalls() ?? [])
      .compactMap { ($0["id"] as? String)?.lowercased() }
      .filter { !discardedCalls.contains($0) }
  }

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    let id = call.data.uuid.lowercased()
    trackedCalls.insert(id)
    guard UserDefaults.standard.bool(forKey: "flutter.call_push_enabled"),
      !UserDefaults.standard.bool(forKey: "flutter.call_push_suppressed_\(id)") else {
      action.fail()
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(call.data)
      return
    }
    if !uiAttached && AVAudioSession.sharedInstance().recordPermission != .granted {
      record("decline", call: call)
      reportRuntimeError(
        "Unlock the app and allow microphone access before answering on the lock screen.")
      action.fail()
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(call.data)
      return
    }
    let rtcSession = RTCAudioSession.sharedInstance()
    rtcSession.lockForConfiguration()
    do {
      // Configure only after an explicit answer. CallKit activates the session
      // after fulfillment; Dart selects LiveKit's externalCallSystem mode
      // before connecting the room.
      try AVAudioSession.sharedInstance().setCategory(
        .playAndRecord,
        mode: call.data.type > 0 ? .videoChat : .voiceChat,
        options: [.allowBluetooth, .allowBluetoothA2DP])
      rtcSession.unlockForConfiguration()
    } catch {
      rtcSession.unlockForConfiguration()
      record("decline", call: call)
      action.fail()
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(call.data)
      return
    }
    record("accept", call: call)
    UserDefaults.standard.set(true, forKey: "flutter.call_push_local_accept_\(id)")
    if answerTasks[id] == nil {
      answerTasks[id] = UIApplication.shared.beginBackgroundTask(withName: "Answer call") { [weak self] in
        guard let self = self else { return }
        self.record("decline", call: call)
        self.reportRuntimeError("Call setup timed out. Unlock the app and try again.")
        LiveKitPlugin.setEngineAvailability(isInputAvailable: false, isOutputAvailable: false)
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(call.data)
        self.finishAnswerTask(id)
      }
    }
    // The already-running authenticated Dart runtime accepts and connects
    // without a frame, Navigator, FlutterViewController, or camera.
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    trackedCalls.remove(call.data.uuid.lowercased())
    finishAnswerTask(call.data.uuid.lowercased())
    record("decline", call: call)
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    trackedCalls.remove(call.data.uuid.lowercased())
    finishAnswerTask(call.data.uuid.lowercased())
    record("decline", call: call)
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    trackedCalls.remove(call.data.uuid.lowercased())
    finishAnswerTask(call.data.uuid.lowercased())
    record("decline", call: call)
  }

  private func finishAnswerTask(_ id: String) {
    if let task = answerTasks.removeValue(forKey: id), task != .invalid {
      UIApplication.shared.endBackgroundTask(task)
    }
  }

  func providerDidReset() {
    callKitAudioActive = false
    LiveKitPlugin.setEngineAvailability(isInputAvailable: false, isOutputAvailable: false)
    var journal = UserDefaults.standard.dictionary(forKey: journalKey) ?? [:]
    for id in trackedCalls {
      let key = "\(id):decline"
      journal[key] = ["key": key, "id": id, "action": "decline"]
      pushChannel?.invokeMethod("callEnded", arguments: id)
    }
    UserDefaults.standard.set(journal, forKey: journalKey)
    trackedCalls.removeAll()
    for id in Array(answerTasks.keys) { finishAnswerTask(id) }
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    guard UserDefaults.standard.bool(forKey: "flutter.call_push_enabled") else {
      LiveKitPlugin.setEngineAvailability(isInputAvailable: false, isOutputAvailable: false)
      return
    }
    callKitAudioActive = true
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    LiveKitPlugin.setEngineAvailability(isInputAvailable: true, isOutputAvailable: true)
  }

  // Apple requires a CallKit report for every delivered VoIP push, even one
  // invalidated by logout, expiry or deduplication. A separate provider avoids
  // replacing the legitimate call/plugin's current data with a synthetic call.
  private final class DiscardedCallProvider: NSObject, CXProviderDelegate {
    private let provider: CXProvider
    private var ids = Set<String>()

    override init() {
      let configuration = CXProviderConfiguration(localizedName: "GlobeTrotter")
      configuration.supportedHandleTypes = [.generic]
      configuration.supportsVideo = false
      configuration.includesCallsInRecents = false
      provider = CXProvider(configuration: configuration)
      super.init()
      provider.setDelegate(self, queue: .main)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func reportAndEnd(completion: @escaping () -> Void) {
      let id = UUID()
      ids.insert(id.uuidString.lowercased())
      let update = CXCallUpdate()
      update.remoteHandle = CXHandle(type: .generic, value: "Call unavailable")
      update.localizedCallerName = "Call unavailable"
      update.hasVideo = false
      provider.reportNewIncomingCall(with: id, update: update) { [self] error in
        if error == nil {
          provider.reportCall(with: id, endedAt: Date(), reason: .failed)
        }
        completion()
      }
    }

    func providerDidReset(_ provider: CXProvider) {}

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
      action.fail()
      provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .failed)
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
      action.fulfill()
    }
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    callKitAudioActive = false
    LiveKitPlugin.setEngineAvailability(isInputAvailable: false, isOutputAvailable: false)
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
  }
}
