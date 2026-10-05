import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let window = (scene as? UIWindowScene)?.windows.first {
      Self.hideFromCapture(window)
    }
  }

  /// iOS has no screenshot-block API. Re-parenting the window layer under a
  /// secure text field's layer makes screenshots, screen recordings and
  /// mirroring capture black while the app looks normal on-device.
  /// ponytail: relies on UIKit layer structure; re-verify on new iOS majors.
  private static func hideFromCapture(_ window: UIWindow) {
    let field = UITextField()
    field.isSecureTextEntry = true
    window.addSubview(field)
    field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    window.layer.superlayer?.addSublayer(field.layer)
    field.layer.sublayers?.last?.addSublayer(window.layer)
  }
}
