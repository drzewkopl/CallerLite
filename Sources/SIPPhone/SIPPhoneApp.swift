import SwiftUI
import AppKit
import SIPPhoneCore

@main
struct SIPPhoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("CallerLite") {
            MainWindow()
                .environmentObject(model.contacts)
                .environmentObject(model.devices)
                .environmentObject(model.calls)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 700)
        .commands {
            CommandMenu("Anrufe") {
                Button("Simulierter eingehender Anruf") {
                    model.simulateIncomingCall()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(!model.calls.canSimulateIncoming)

                Divider()

                Button("Aktuellen Anruf beenden") {
                    model.calls.endActiveCall()
                }
                .keyboardShortcut(.cancelAction)
            }
            CommandMenu("Konto") {
                Button("Neu verbinden") {
                    model.reconnect()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.activate(ignoringOtherApps: true)
    }
}
