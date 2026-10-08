// iOS 27 refuses to launch apps built with its SDK unless they adopt the UIScene
// life cycle, which the Expo SDK 57 native template does not. This plugin
// declares a scene delegate and attaches the React Native window to the scene.
// Remove it once the project is on Expo SDK 58, whose template adopts scenes
// natively.
const { withAppDelegate, withInfoPlist } = require("expo/config-plugins");

const WINDOW_SETUP = /#if os\(iOS\) \|\| os\(tvOS\)\n\s*window = UIWindow\(frame: UIScreen\.main\.bounds\)\n[\s\S]*?#endif\n\n/;

// iOS restores the scene session saved by a previous install (older Expo build
// or the former Swift app) and then never instantiates the scene delegate, so
// the window is attached from the scene notification as well.
const SCENE_OBSERVER = `    NotificationCenter.default.addObserver(
      forName: UIScene.willConnectNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      MainActor.assumeIsolated {
        self?.startReactNative(in: notification.object as? UIScene)
      }
    }

`;

const LINKING_MARKER = "  // Linking API\n";

const START_IN_SCENE = `  func startReactNative(in scene: UIScene?) {
    guard window == nil, let windowScene = scene as? UIWindowScene, let factory = reactNativeFactory else {
      return
    }

    let window = UIWindow(windowScene: windowScene)
    self.window = window
    factory.startReactNative(withModuleName: "main", in: window, launchOptions: nil)
  }

`;

const SCENE_DELEGATE = `
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    let appDelegate = UIApplication.shared.delegate as? AppDelegate
    appDelegate?.startReactNative(in: scene)
    window = appDelegate?.window

    openURLs(connectionOptions.urlContexts)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    openURLs(URLContexts)
  }

  private func openURLs(_ contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      _ = RCTLinkingManager.application(UIApplication.shared, open: context.url, options: [:])
    }
  }
}
`;

module.exports = function withSceneLifecycle(config) {
  config = withInfoPlist(config, (config) => {
    config.modResults.UIApplicationSceneManifest = {
      UIApplicationSupportsMultipleScenes: false,
      UISceneConfigurations: {
        UIWindowSceneSessionRoleApplication: [
          {
            UISceneConfigurationName: "Default Configuration",
            UISceneDelegateClassName: "$(PRODUCT_MODULE_NAME).SceneDelegate",
          },
        ],
      },
    };
    return config;
  });

  return withAppDelegate(config, (config) => {
    const contents = config.modResults.contents;
    if (contents.includes("class SceneDelegate")) return config;
    if (!WINDOW_SETUP.test(contents) || !contents.includes(LINKING_MARKER)) {
      throw new Error("with-scene-lifecycle: unexpected AppDelegate template");
    }
    config.modResults.contents =
      contents
        .replace(WINDOW_SETUP, SCENE_OBSERVER)
        .replace(LINKING_MARKER, START_IN_SCENE + LINKING_MARKER) + SCENE_DELEGATE;
    return config;
  });
};
