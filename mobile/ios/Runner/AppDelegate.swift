import Flutter
import Speech
import SwiftUI
import UIKit
#if canImport(Translation)
import Translation
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "elite_dent/apple_translate",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      AppleNativeTranslate.handle(call: call, result: result)
    }
  }
}

enum AppleNativeTranslate {
  static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speechWarm":
      Self.speechWarm(call: call, result: result)
    case "translate":
      break
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    guard call.method == "translate" else { return }
    guard let args = call.arguments as? [String: Any],
      let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty,
      let source = args["source"] as? String,
      let target = args["target"] as? String
    else {
      result(FlutterError(code: "args", message: "Missing text to translate.", details: nil))
      return
    }
    if #available(iOS 18.0, *) {
      DispatchQueue.main.async {
        Self.translateIfSupported(
          text: text,
          source: source,
          target: target,
          result: result
        )
      }
    } else {
      result(
        FlutterError(
          code: "unsupported",
          message: "Apple Translate needs iPadOS 18 or later.",
          details: nil
        )
      )
    }
  }

  /// Kick Apple Speech for a locale. Returns immediately; never gates listen.
  private static func speechWarm(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    result(nil)
    guard let args = call.arguments as? [String: Any],
      let raw = (args["locale"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return }
    let id = raw.replacingOccurrences(of: "_", with: "-")
    DispatchQueue.global(qos: .utility).async {
      _ = SFSpeechRecognizer(locale: Locale(identifier: id))
    }
  }

  @available(iOS 18.0, *)
  private static func translateIfSupported(
    text: String,
    source: String,
    target: String,
    result: @escaping FlutterResult
  ) {
    #if canImport(Translation)
      Task { @MainActor in
        let src = Locale.Language(identifier: Self.bcp47(source))
        let dst = Locale.Language(identifier: Self.bcp47(target))
        let status = await LanguageAvailability().status(from: src, to: dst)
        if status == .unsupported {
          result(
            FlutterError(
              code: "unsupported",
              message: "Apple Translate does not support this language pair.",
              details: nil
            )
          )
          return
        }
        Self.present(text: text, source: src, target: dst, result: result)
      }
    #else
      result(
        FlutterError(
          code: "unsupported",
          message: "This Xcode SDK has no Apple Translation framework.",
          details: nil
        )
      )
    #endif
  }

  @available(iOS 18.0, *)
  private static func present(
    text: String,
    source: Locale.Language,
    target: Locale.Language,
    result: @escaping FlutterResult
  ) {
    #if canImport(Translation)
      guard let root = Self.rootViewController() else {
        result(
          FlutterError(
            code: "ui",
            message: "Apple Translate could not attach to the screen.",
            details: nil
          )
        )
        return
      }
      let box = TranslateHostBox()
      var answered = false
      let finish: (Any) -> Void = { value in
        guard !answered else { return }
        answered = true
        box.detach()
        result(value)
      }
      let host = UIHostingController(
        rootView: AppleTranslateHost(
          text: text,
          source: source,
          target: target,
          onFinish: { outcome in
            switch outcome {
            case .success(let translated):
              finish(translated)
            case .failure(let error):
              finish(
                FlutterError(
                  code: "apple",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        )
      )
      box.controller = host
      host.view.backgroundColor = .clear
      host.view.frame = root.view.bounds
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      root.addChild(host)
      root.view.addSubview(host.view)
      host.didMove(toParent: root)
    #else
      result(
        FlutterError(
          code: "unsupported",
          message: "This Xcode SDK has no Apple Translation framework.",
          details: nil
        )
      )
    #endif
  }

  private static func bcp47(_ code: String) -> String {
    switch code.lowercased() {
    case "zh":
      return "zh-Hans"
    case "no", "nb":
      return "nb"
    case "fa":
      return "fa"
    case "ku":
      return "ku"
    default:
      return code
    }
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
        return root
      }
    }
    return scenes.first?.windows.first?.rootViewController
  }
}

private final class TranslateHostBox {
  var controller: UIViewController?
  func detach() {
    controller?.willMove(toParent: nil)
    controller?.view.removeFromSuperview()
    controller?.removeFromParent()
    controller = nil
  }
}

#if canImport(Translation)
  @available(iOS 18.0, *)
  struct AppleTranslateHost: View {
    let text: String
    let source: Locale.Language
    let target: Locale.Language
    let onFinish: (Result<String, Error>) -> Void
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
      Color.clear
        .accessibilityHidden(true)
        .translationTask(configuration) { session in
          do {
            let response = try await session.translate(text)
            let translated = response.targetText.trimmingCharacters(
              in: .whitespacesAndNewlines
            )
            if translated.isEmpty {
              onFinish(
                .failure(
                  NSError(
                    domain: "AppleTranslate",
                    code: 1,
                    userInfo: [
                      NSLocalizedDescriptionKey: "Apple Translate returned empty text."
                    ]
                  )
                )
              )
            } else {
              onFinish(.success(translated))
            }
          } catch {
            onFinish(.failure(error))
          }
        }
        .onAppear {
          configuration = TranslationSession.Configuration(
            source: source,
            target: target
          )
        }
    }
  }
#endif
