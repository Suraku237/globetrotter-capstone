import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let app = UIApplication.shared.delegate as? AppDelegate else { return }
    let sceneWindow = UIWindow(windowScene: windowScene)
    // Reuse the headless runtime. Never instantiate an implicit second engine.
    sceneWindow.rootViewController = app.callEngine.viewController ??
      FlutterViewController(engine: app.callEngine, nibName: nil, bundle: nil)
    window = sceneWindow
    app.window = sceneWindow
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    sceneWindow.makeKeyAndVisible()
    app.setUiAttached(true)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.setUiAttached(true)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.setUiAttached(false)
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidDisconnect(_ scene: UIScene) {
    super.sceneDidDisconnect(scene)
    guard let app = UIApplication.shared.delegate as? AppDelegate else { return }
    app.setUiAttached(false)
    app.callEngine.viewController = nil
    window?.rootViewController = nil
    window = nil
    app.window = nil
  }
}
