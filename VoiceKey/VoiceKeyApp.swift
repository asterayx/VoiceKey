//
//  VoiceKeyApp.swift
//  VoiceKey
//
//  Created by Peng Chen on 28/3/26.
//
//  Main app entry point. Handles URL Scheme callbacks from the keyboard
//  extension to trigger recording.
//

import SwiftUI

@main
struct VoiceKeyApp: App {
    @State private var showVoiceInput = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .navigationDestination(isPresented: $showVoiceInput) {
                        VoiceInputView()
                    }
            }
            .onOpenURL { url in
                handleURL(url)
            }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "voicekey" else { return }

        switch url.host {
        case "record":
            showVoiceInput = true
        case "command":
            // M7: voice command editing — placeholder
            showVoiceInput = true
        default:
            break
        }
    }
}
