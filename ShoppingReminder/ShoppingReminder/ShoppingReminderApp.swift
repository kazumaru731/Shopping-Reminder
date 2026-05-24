//
//  ShoppingReminderApp.swift
//  ShoppingReminder
//
//  Created by 南部 司真 on 2026/04/15.
//

import SwiftUI

@main
struct ShoppingReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var supabase = SupabaseService.shared
    
    var body: some Scene {
        WindowGroup {
            SwiftUI.Group {
                if supabase.isInitializing {
                    // 起動時の初期化中（セッション確認中）はローディングを表示
                    VStack(spacing: 20) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        ProgressView("読み込み中...")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else if supabase.isPasswordRecovery {
                    PasswordUpdateView()
                } else if supabase.currentUser != nil {
                    GroupListView()
                        .onAppear {
                            NotificationManager.shared.requestPushPermission()
                            Task {
                                // ログイン完了のこのタイミングで、端末に保存されているトークンを確実にDBへ送信
                                if let token = UserDefaults.standard.string(forKey: "apns_device_token"),
                                   let deviceId = UIDevice.current.identifierForVendor?.uuidString {
                                    await SupabaseService.shared.savePushToken(token: token, deviceId: deviceId)
                                }
                                await NotificationManager.shared.syncAllNotifications()
                            }
                        }
                } else {
                    LoginView()
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .onAppear {
                NotificationManager.shared.requestPushPermission()
            }
            .onOpenURL { url in
                supabase.handleOpenURL(url)
            }
            .alert("エラー", isPresented: .init(
                get: { supabase.authError != nil },
                set: { if !$0 { supabase.authError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    supabase.authError = nil
                }
            } message: {
                if let error = supabase.authError {
                    Text(error)
                }
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.handleDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("DEBUG: Remote notification registration failed: \(error)")
        #endif
    }

    // アプリ起動中でも通知を表示するための設定
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    
    // バックグラウンドでプッシュ通知（他ユーザーの購入・変更）を受け取った際にローカル通知を再同期
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await NotificationManager.shared.syncAllNotifications()
            completionHandler(.newData)
        }
    }
}
