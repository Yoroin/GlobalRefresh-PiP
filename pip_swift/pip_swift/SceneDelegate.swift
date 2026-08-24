//
//  SceneDelegate.swift
//  pip_swift
//
//  Created by 无夜之星辰 on 2021/5/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MainTabBarController()
        AppAppearancePreference.apply(to: window)
        self.window = window
        window.makeKeyAndVisible()

        handleShortcutURLContexts(connectionOptions.urlContexts)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        print("sceneDidBecomeActive")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        print("sceneDidEnterBackground")
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handleShortcutURLContexts(URLContexts)
    }

    private func handleShortcutURLContexts(_ URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            if PiPShortcutActionCenter.request(from: context.url) {
                (window?.rootViewController as? MainTabBarController)?
                    .handleExternalShortcutRequest(reason: "URL快捷指令")
                break
            }
        }
    }

}
