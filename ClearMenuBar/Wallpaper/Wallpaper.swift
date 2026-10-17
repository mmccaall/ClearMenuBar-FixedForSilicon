//
//  Wallpaper.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import AppKit
import OSLog

public enum Wallpaper {
    public enum Screen {
        case all
        case main
        case index(Int)
        case nsScreens([NSScreen])
        
        fileprivate var nsScreens: [NSScreen] {
            switch self {
            case .all:
                return NSScreen.screens
            case .main:
                guard let mainScreen = NSScreen.main else {
                    return []
                }
                
                return [mainScreen]
            case .index(let index):
                guard let screen = NSScreen.screens[safe: index] else {
                    return []
                }
                
                return [screen]
            case .nsScreens(let nsScreens):
                return nsScreens
            }
        }
    }
    
    public enum Scale: String, CaseIterable {
        case auto
        case fill
        case fit
        case stretch
        case center
    }
    
    public static func getLastWallpaperURL() -> URL? {
        // 1. Find the PID of the wallpaper extension process
        let pgrepTask = Process()
        pgrepTask.launchPath = "/usr/bin/pgrep"
        pgrepTask.arguments = ["WallpaperImageExtension"]
        
        let pgrepPipe = Pipe()
        pgrepTask.standardOutput = pgrepPipe
        pgrepTask.launch()
        
        let pgrepData = pgrepPipe.fileHandleForReading.readDataToEndOfFile()
        guard let pidString = String(data: pgrepData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !pidString.isEmpty else {
            return nil // Process not found
        }
        
        // 2. Run lsof on that PID to find open image files
        let lsofTask = Process()
        lsofTask.launchPath = "/usr/sbin/lsof"
        lsofTask.arguments = ["-Fn", "-p", pidString] // -Fn gives machine-readable output
        
        let lsofPipe = Pipe()
        lsofTask.standardOutput = lsofPipe
        lsofTask.launch()
        
        let lsofData = lsofPipe.fileHandleForReading.readDataToEndOfFile()
        guard let lsofOutput = String(data: lsofData, encoding: .utf8) else {
            return nil
        }
        
        // 3. Parse the output for image files
        // lsof -Fn outputs lines like "n/path/to/file.png"
        let lines = lsofOutput.components(separatedBy: .newlines)
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "tiff"]
        
        for line in lines {
            guard line.hasPrefix("n/") else { continue }
            let path = String(line.dropFirst()) // Remove the "n" prefix
            let url = URL(fileURLWithPath: path)
            
            if imageExtensions.contains(url.pathExtension.lowercased()) {
                return url
            }
        }
        
        return nil
    }
    
    public static func getCurrentWallpaperURL() -> URL? {
        // Fast refresh path: use lsof directly, no log scraping, no tail.
        return getLastWallpaperURL()
    }
    
    /**
     Get the current wallpapers.
     */
    public static func get(screen: Screen = .all) -> [URL?] {
        let wallpaperURLs = screen.nsScreens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        return wallpaperURLs.map { url in
            if #available(macOS 26, *) {
                return url
            } else {
                if (url.isDirectory) {
                    return getLastWallpaperURL()
                } else {
                    return url
                }
            }
        }
    }
    
    public static func getCurrent(screen: Screen = .all) -> [URL?] {
        let wallpaperURLs = screen.nsScreens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        return wallpaperURLs.map { url in
            if #available(macOS 26, *) {
                return url
            } else {
                if (url.isDirectory) {
                    return getCurrentWallpaperURL()
                } else {
                    return url
                }
            }
        }
    }
    
    public static func isWallpaperFromADirectory(screen: Screen = .all) -> [Bool?] {
        let wallpaperURLs = screen.nsScreens.compactMap{ NSWorkspace.shared.desktopImageURL(for: $0) }
        
        return wallpaperURLs.map { $0.isDirectory }
    }
    
    /**
    Set an image URL as wallpaper.
    */
    public static func set(
        _ image: URL,
        screen: Screen = .all,
        scale: Scale = .auto,
        fillColor: NSColor? = nil
    ) throws {
        try validateFile(image)

        var options = [NSWorkspace.DesktopImageOptionKey: Any]()

        switch scale {
        case .auto:
            break
        case .fill:
            options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
            options[.allowClipping] = true
        case .fit:
            options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
            options[.allowClipping] = false
        case .stretch:
            options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
            options[.allowClipping] = true
        case .center:
            options[.imageScaling] = NSImageScaling.scaleNone.rawValue
            options[.allowClipping] = false
        }

        options[.fillColor] = fillColor

        for nsScreen in screen.nsScreens {
            try NSWorkspace.shared.setDesktopImageURL(image, for: nsScreen, options: options)
        }
    }
    
    private static func validateFile(_ url: URL) throws {
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NSError(
                domain: "WallpaperError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The file doesn't exist."]
            )
        }

        if !isDirectory.boolValue {
            guard (try? url.checkResourceIsReachable()) == true else {
                throw NSError(
                    domain: "WallpaperError",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The file exists but is not accessible."]
                )
            }
        }
    }
    
    public static func applicationSupportDirectory() -> URL? {
        let fileManager = FileManager.default
        
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
         
        let appFolder = baseURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.zorth64.ClearMenuBar")
            
        if !fileManager.fileExists(atPath: appFolder.path) {
            try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }
        
        return appFolder
    }
    
    public static func generateToken() -> String {
        String((0..<6).compactMap { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement() })
    }
    
    public static func saveWallpaper(_ image: NSImage) -> URL? {
        guard let directory = applicationSupportDirectory() else { return nil }
        guard let data = image.pngData() else { return nil }
       
        let token = generateToken()
        let filename = "Managed by Clear Menu Bar (\(token)).png"
        let fileURL = directory.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving image: ", error)
            return nil
        }
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmap.representation(using: .png, properties: [:])
    }
}
