//
//  ShoppingReminderApp.swift
//  ShoppingReminder
//
//  Created by 南部 司真 on 2026/04/15.
//

import SwiftUI

@main
struct ShoppingReminderApp: App {
    @StateObject private var supabase = SupabaseService.shared
    
    var body: some Scene {
        WindowGroup {
            if supabase.currentUser != nil {
                GroupListView()
                    .onAppear {
                        NotificationManager.shared.requestAuthorization()
                        Task {
                            await NotificationManager.shared.syncAllNotifications()
                        }
                    }
            } else {
                LoginView()
            }
        }
    }
}
