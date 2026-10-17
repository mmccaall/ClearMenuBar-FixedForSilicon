//
//  AppDelegate.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    
    @IBOutlet weak var menu: NSMenu?
    
    var preferencesWindow: NSWindow?
        
    var menuBarWindowController: MenuBarWindowController?
    var shadowWindowController: ShadowWindowController?

    override init() {
        super.init()
        
        Dependencies.setup()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let menuBarWindow = MenuBarWindow(
            contentRect: NSRect(x: 0,
                                y: NSScreen.main!.frame.height - NSScreen.main!.menuBarHeight,
                                width: NSScreen.main!.frame.width,
                                height: NSScreen.main!.menuBarHeight),
            styleMask: [
            ],
            backing: .buffered, defer: false)
        
        self.menuBarWindowController = MenuBarWindowController(window: menuBarWindow)
        self.menuBarWindowController?.showWindow(self)
        
        let shadowWindow = ShadowWindow(
            contentRect: NSRect(x: 0,
                                y: NSScreen.main!.frame.height - (NSScreen.main!.menuBarHeight + 80),
                                width: NSScreen.main!.frame.width,
                                height: 80),
            styleMask: [
           ],
            backing: .buffered, defer: false
        )
        
        self.shadowWindowController = ShadowWindowController(window: shadowWindow)
        self.shadowWindowController?.showWindow(self)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func screenParametersChanged() {
        // Debounce: macOS can fire this several times in quick succession.
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(repositionWindows),
                                               object: nil)
        perform(#selector(repositionWindows), with: nil, afterDelay: 0.5)
    }
    
    @objc private func repositionWindows() {
        // 1. Tear down the old windows
        menuBarWindowController?.close()
        shadowWindowController?.close()
        menuBarWindowController = nil
        shadowWindowController = nil
        
        // 2. Run the exact same setup code from applicationDidFinishLaunching
        let screen = NSScreen.main ?? NSScreen.screens.first!
        
        let menuBarWindow = MenuBarWindow(
            contentRect: NSRect(x: 0, y: screen.frame.height - screen.menuBarHeight, width: screen.frame.width, height: screen.menuBarHeight),
            styleMask: [], backing: .buffered, defer: false
        )
        
        self.menuBarWindowController = MenuBarWindowController(window: menuBarWindow)
        self.menuBarWindowController?.showWindow(self)
        
        let shadowWindow = ShadowWindow(
            contentRect: NSRect(x: 0, y: screen.frame.height - (screen.menuBarHeight + 80), width: screen.frame.width, height: 80),
            styleMask: [], backing: .buffered, defer: false
        )
        
        self.shadowWindowController = ShadowWindowController(window: shadowWindow)
        self.shadowWindowController?.showWindow(self)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil) {
            
            var config = NSImage.SymbolConfiguration(textStyle: .body,
                                                     scale: .medium)
            config = config.applying(.init(pointSize: 15.0, weight: NSFont.Weight.regular))
            statusItem?.button?.image = image.withSymbolConfiguration(config)
        }
        
        if let menu = menu {
            statusItem?.menu = menu
        }
    }
    
    @IBAction func preferences(_ sender: Any?) {
        if (preferencesWindow == nil) {
            let preferencesView = PreferencesView()
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 570, height: 210),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            preferencesWindow?.level = .floating
            preferencesWindow?.collectionBehavior = .canJoinAllSpaces
            preferencesWindow?.center()
            preferencesWindow?.title = "Clear Menu Bar Settings"
            preferencesWindow?.isReleasedWhenClosed = false
            preferencesWindow?.miniaturize(nil)
            preferencesWindow?.zoom(nil)
            preferencesWindow?.contentView = NSHostingView(rootView: preferencesView)
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}
