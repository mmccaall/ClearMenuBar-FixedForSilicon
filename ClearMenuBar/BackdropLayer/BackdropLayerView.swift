//
//  BackdropLayerView.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import SwiftUI
import QuartzCore
import Swinject
import Combine

public class BackdropLayerView: NSVisualEffectView {
    
    private var appState: AppState = Container.main.resolve(AppState.self)!
    
    private var gradient: CAGradientLayer? = nil
    private var backdrop: CABackdropLayer? = nil
    private var tint: CALayer? = nil
    private var container: CALayer? = nil
    
    private var wallpaper: CALayer? = nil
    private var wallpaperContainer: CALayer? = nil
    
    private var currentWallpaperPath: URL?
    
    private var timer: Timer?
    
    private var transitionDuration: CFTimeInterval = 2.0
    
    private var screenDidWakeObserver: NSObjectProtocol?
    private var screenUnlockedObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    
    private var disposables = Set<AnyCancellable>()
    
    private var wallpaperPollTimer: Timer?
    private var lastSeenWallpaperPath: String?

    private var cachedMenuBarCrop: NSImage?
    private var cachedMenuBarCropPath: String?

    private var isSwitchingSpaces = false

    public final class BlendGroup {
        
        /// The notification posted upon deinit of a `BlendGroup`.
        fileprivate static let removedNotification = Notification.Name("BackdropView.BlendGroup.deinit")
        
        /// The internal value used for `CABackdropLayer.groupName`.
        fileprivate let value = UUID().uuidString
        
        /// Create a new `BlendGroup`.
        public init() {}
        
        deinit {
            
            // Alert all `BackdropView`s that we're about to be removed.
            // The `BackdropView` will figure out if it needs to update itself.
            NotificationCenter.default.post(name: BlendGroup.removedNotification,
                                            object: nil, userInfo: ["value": self.value])
        }
        
        /// The `global` BlendGroup, if it is desired that all backdrops share
        /// the same blending group through the layer tree (window).
        public static let global = BlendGroup()
        
        /// The default internal value used for `CABackdropLayer.groupName`.
        /// This is to be used if no `BlendGroup` is set on the `BackdropView`.
        fileprivate static func `default`() -> String {
            return UUID().uuidString
        }
    }
    
    public var effect: OverlayEffect = .clear {
        didSet {
            self.tint?.backgroundColor = self.effect.tintColor().cgColor
        }
    }
    
    public var exposureFactor: CGFloat {
        get { return self.wallpaper?.value(forKeyPath: "filters.exposureAdjust.inputEV") as? CGFloat ?? 0 }
        set {
            self.wallpaper?.setValue(newValue, forKeyPath: "filters.exposureAdjust.inputEV")
        }
    }
    
    public weak var blendingGroup: BlendGroup? = nil {
        didSet {
            self.backdrop?.groupName = self.blendingGroup?.value ?? BlendGroup.default()
        }
    }
    
    public override var blendingMode: NSVisualEffectView.BlendingMode {
        get { return self.window?.contentView == self ? .behindWindow : .withinWindow }
        set { }
    }
    
    /// Always `.appearanceBased`; use `effect` instead.
    public override var material: NSVisualEffectView.Material {
        get { return .appearanceBased }
        set { }
    }
    
    public override var state: NSVisualEffectView.State {
        get { return self._state }
        set { self._state = newValue }
    }
    
    private var _state: NSVisualEffectView.State = .active {
        didSet {
            // Don't be called when `commonInit` hasn't finished.
            guard let _ = self.backdrop else { return }
            
        }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }
    
    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        self.commonInit()
    }

    private func commonInit() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.layer?.masksToBounds = true
        self.layer?.name = "view"
        
        self.tint = CALayer()
        self.tint?.name = "tint"
        
        self.wallpaperContainer = CALayer()
        self.wallpaperContainer!.name = "wallpaperContainer"
        
        self.wallpaper = CALayer()
        self.wallpaper!.name = "wallpaper"
        
        if let wallpaperPath = staticWallpaperWorkaroundPath {
            self.wallpaper?.contents = cropWallpaperBelowMenuBarArea(imagePath: wallpaperPath)
        } else if let windowID = getCurrentWallpaperWindowID() {
            // Dynamic wallpapers don't expose a usable image path. Keep the user's
            // experimental preference intact and fall back to the live Dock wallpaper.
            self.wallpaper?.contents = getWallpaperScreenshot(cgWindowID: windowID)
        }
        
        if let vibranceFilter = CIFilter(name: "CIVibrance") {
            vibranceFilter.name = "vibrance"
            self.wallpaper?.filters = [vibranceFilter]
        }
        if let colorControlsFilter = CIFilter(name: "CIColorControls") {
            colorControlsFilter.name = "colorControls"
            self.wallpaper!.filters?.append(colorControlsFilter)
        }
        if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
            exposureFilter.name = "exposureAdjust"
            self.wallpaper!.filters?.append(exposureFilter)
        }
        
        self.wallpaperContainer?.sublayers = [self.wallpaper!, self.tint!]
        self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
        
        // Essentially, tell the `NSVisualEffectView` to not do its job:
        super.state = .active
        super.blendingMode = .behindWindow
        super.material = .appearanceBased
        self.setValue(true, forKey: "clear") // internal material
        
        // Set up our backdrop view:
        self.backdrop = CABackdropLayer()
        self.backdrop!.masksToBounds = true
        self.backdrop!.name = "backdrop"
//        self.backdrop!.allowsGroupBlending = true
        self.backdrop!.allowsGroupOpacity = true
        self.backdrop!.allowsEdgeAntialiasing = false
        self.backdrop!.disablesOccludedBackdropBlurs = true
        self.backdrop!.ignoresOffscreenGroups = false
        self.backdrop!.allowsInPlaceFiltering = false
        self.backdrop!.setValue(1, forKey: "scale")
        self.backdrop!.setValue(0.1, forKey: "bleedAmount")
        self.backdrop!.windowServerAware = true
        
        if let brightnessFilter = CAFilter(type: kCAFilterColorBrightness) {
            brightnessFilter.name = "brightness"
            self.backdrop!.filters = [brightnessFilter]
        }
        
        if let contrastFilter = CAFilter(type: kCAFilterColorContrast) {
            contrastFilter.name = "contrast"
            self.backdrop!.filters?.append(contrastFilter)
        }
        
        if let invertFilter = CAFilter.init(type: kCAFilterColorInvert) {
            invertFilter.name = "invert"
            self.backdrop?.filters?.append(invertFilter)
        }
       
        if let hueRotateFilter = CAFilter.init(type: kCAFilterColorHueRotate) {
            hueRotateFilter.name = "hueRotate"
            hueRotateFilter.setValue(3.14, forKey: "inputAngle")
            self.backdrop!.filters?.append(hueRotateFilter)
        }
        
        self.gradient = CAGradientLayer()
        self.gradient?.name = "gradient"
        
        self.container = CALayer()
        self.container?.name = "container"
        self.container?.masksToBounds = true
        self.container?.allowsEdgeAntialiasing = true
        self.container?.sublayers = [self.backdrop!, self.wallpaperContainer!]
        
        self.layer?.insertSublayer(self.container!, at: 0)
        
        self._state = .active
        self.blendingMode = .behindWindow
        
        screenDidWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: OperationQueue.main) { _ in
                if self.staticWallpaperWorkaroundPath == nil,
                   let windowID = self.getCurrentWallpaperWindowID() {
                    self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
                }
            }
        
        screenUnlockedObserver = DistributedNotificationCenter.default.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            if self.staticWallpaperWorkaroundPath == nil,
               let path = self.getLastWallpaperImagePath(),
               self.currentWallpaperPath != path {
                self.currentWallpaperPath = path
                if let windowID = self.getCurrentWallpaperWindowID() {
                    self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
                }
            }
        }
       
        NotificationCenter.default.addObserver(self, selector: #selector(wallpaperChanged(_:)), name: .wallpaperChanged, object: nil)

        startWallpaperPolling()
        
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: OperationQueue.main) { _ in

                self.isSwitchingSpaces = true
                
                if self.staticWallpaperWorkaroundPath != nil {
                    // Disabled Transparency mode: force the compositor to re-sort
                    // window levels, otherwise the Dock's wallpaper window can sit
                    // above our statusBar-level overlay after space transitions.
                    DispatchQueue.main.async {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.layer?.isHidden = true
                        CATransaction.commit()

                        DispatchQueue.main.async {
                            CATransaction.begin()
                            CATransaction.setDisableActions(true)
                            self.layer?.isHidden = false
                            CATransaction.commit()

                            self.window?.level = NSWindow.Level.statusBar
                            self.window?.orderFrontRegardless()
                            self.isSwitchingSpaces = false
                        }
                    }
                } else if let windowID = self.getCurrentWallpaperWindowID() {
                    // Normal mode: refresh the wallpaper snapshot from the Dock.
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.0)
                    self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
                    CATransaction.commit()
                    
                    self.isSwitchingSpaces = false
                } else {
                    // Neither branch ran — reset the flag so polling isn't stuck.
                    self.isSwitchingSpaces = false
                }
            }
        
        bindAllowReduceTransparency()
    }

    private func startWallpaperPolling() {
        wallpaperPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard !self.isSwitchingSpaces else { return }
            
            DispatchQueue.global(qos: .utility).async {
                guard let currentPath = Wallpaper.getCurrent(screen: .main).compactMap({ $0 }).first else {
                    return
                }
                
                let normalizedPath = currentPath.resolvingSymlinksInPath().path
                
                DispatchQueue.main.async {
                    guard !self.isSwitchingSpaces else { return }
                    guard normalizedPath != self.lastSeenWallpaperPath else { return }
                    self.lastSeenWallpaperPath = normalizedPath
                    NotificationCenter.default.post(name: .wallpaperChanged, object: currentPath)
                }
            }
        }
    }
    
    public func refreshForScreenChange() {
        self.layout()
        self.viewDidChangeEffectiveAppearance()

        // // Clear the cache so it is forced to recalculate the crop for the NEW screen resolution
        // cachedMenuBarCrop = nil
        // cachedMenuBarCropPath = nil

        DispatchQueue.main.async {
            if let path = self.currentWallpaperPath {
                self.updateMenuBarBackground(path: path)
            } else if let windowID = self.getCurrentWallpaperWindowID() {
                self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
            }
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        let systemAppearance: NSAppearance = NSApplication.shared.effectiveAppearance
        
        if (systemAppearance.name == NSAppearance.Name.darkAqua) {
            self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterScreenBlendMode)
            self.effect = .darkShadow
            self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
            self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
        } else {
            self.wallpaperContainer!.compositingFilter = CAFilter.init(type: kCAFilterMultiplyBlendMode)
            self.effect = .lightShadow
        }
        
        if staticWallpaperWorkaroundPath != nil {
            self.backdrop!.setValue(0.0, forKeyPath: "filters.brightness.inputAmount")
            self.backdrop!.setValue(1.0, forKeyPath: "filters.contrast.inputAmount")
            if (systemAppearance.name != NSAppearance.Name.darkAqua) {
                self.backdrop!.setValue(true, forKeyPath: "filters.invert.enabled")
                self.backdrop!.setValue(true, forKeyPath: "filters.hueRotate.enabled")
            }
        } else {
            if (systemAppearance.name == NSAppearance.Name.darkAqua) {
                self.backdrop!.setValue(-0.063, forKeyPath: "filters.brightness.inputAmount")
                self.backdrop!.setValue(1.14, forKeyPath: "filters.contrast.inputAmount")
            } else {
                self.backdrop!.setValue(false, forKeyPath: "filters.invert.enabled")
                self.backdrop!.setValue(false, forKeyPath: "filters.hueRotate.enabled")
                self.backdrop!.setValue(0.0919, forKeyPath: "filters.brightness.inputAmount")
                self.backdrop!.setValue(1.166, forKeyPath: "filters.contrast.inputAmount")
            }
        }
    }
    
    @objc func wallpaperChanged(_ notification: NSNotification) {
        if let url = notification.object as? URL {
            
            guard url.isFileURL else { return }
            
            if let appDir = appState.appSupportDirectory {
                let normalizedURL = url.resolvingSymlinksInPath().standardizedFileURL
                let normalizedAppDir = appDir.resolvingSymlinksInPath().standardizedFileURL

                if normalizedURL.path.hasPrefix(normalizedAppDir.path) {
                    return
                }
            }
            
            if (self.currentWallpaperPath?.resolvingSymlinksInPath().path !=
                url.resolvingSymlinksInPath().path) {
                self.currentWallpaperPath = url
            } else {
                return
            }
            
            if (appState.allowReduceTransparencyToBeDisabled) {
                modifyImageAndSetAsWallpaper(path: url)
            }
            
            cachedMenuBarCrop = nil
            cachedMenuBarCropPath = nil

            updateMenuBarBackground(path: url)
        }
    }
    
    func updateMenuBarBackground(path: URL) {
        let normalizedPath = path.resolvingSymlinksInPath().path
        
        let croppedImage: NSImage?
        if cachedMenuBarCropPath == normalizedPath, let cached = cachedMenuBarCrop {
            croppedImage = cached
        } else {
            croppedImage = cropWallpaperBelowMenuBarArea(imagePath: path)
            cachedMenuBarCrop = croppedImage
            cachedMenuBarCropPath = normalizedPath
        }
        
        guard let image = croppedImage else { return }
        
        let isDirectory = (Wallpaper.isWallpaperFromADirectory(screen: .main).first ?? nil) ?? false
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(isDirectory ? self.transitionDuration : 0.0)
        self.wallpaper?.contents = image
        CATransaction.commit()
        
        if !isDirectory {
            appState.currentWallpaperPath = path
        }
    }
    
    func modifyImageAndSetAsWallpaper(path: URL) {
        appState.currentWallpaperPath = path
        if let modifiedWallpaper = self.addBlackRectangleToWallpaperOverMenuBarArea(imagePath: path),
           let modifiedWallpaperPath = Wallpaper.saveWallpaper(modifiedWallpaper) {
            do {
                try Wallpaper.set(modifiedWallpaperPath, screen: .main)
                if let oldURL = appState.modifiedWallpaperPath {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                appState.modifiedWallpaperPath = modifiedWallpaperPath
            } catch {
                print("Error while setting wallpaper.")
            }
        }
    }
    
    func getLastWallpaperImagePath() -> URL? {
        Wallpaper.get(screen: .main).compactMap { $0 }.first
    }
    
    func getCurrentWallpaperImagePath() -> URL? {
        Wallpaper.getCurrent(screen: .main).compactMap { $0 }.first
    }
    
    func cropWallpaperBelowMenuBarArea(imagePath: URL) -> NSImage? {
        guard let wallpaperImage = NSImage(contentsOf: imagePath) else {
            print("Error while obtaining the wallpaper image.")
            return nil
        }
        
        if let screenFrame = NSScreen.main?.frame, let wallpaperCGImage = wallpaperImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let screenWidth = screenFrame.width
            let screenHeight = screenFrame.height
            
            let screenProportion = screenWidth / screenHeight
            let wallpaperProportion = CGFloat(wallpaperCGImage.width) / CGFloat(wallpaperCGImage.height)
            
            var newWidth = Int(screenWidth)
            var newHeight = Int(screenHeight)
            var resizedCGImage: CGImage?
            let cropRect: CGRect
            var count = 3
            
            if wallpaperProportion >= screenProportion {
                newWidth = Int(screenHeight / CGFloat(wallpaperCGImage.height) * CGFloat(wallpaperCGImage.width))
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                
                while (count > 0 && resizedCGImage == nil) {
                    resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                    count -= 1
                }
                
                let xOffset = (CGFloat(newWidth) - screenWidth) / 2
                cropRect = CGRect(x: Int(xOffset), y: 0, width: Int(screenWidth), height: Int(NSScreen.main!.menuBarHeight))
            } else {
                newHeight = Int(screenWidth / CGFloat(wallpaperCGImage.width) * CGFloat(wallpaperCGImage.height))
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                
                while (count > 0 && resizedCGImage == nil) {
                    resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                    count -= 1
                }
                
                let yOffset = (CGFloat(newHeight) - screenHeight) / 2
                cropRect = CGRect(x: 0, y: Int(yOffset), width: Int(screenWidth), height: Int(NSScreen.main!.menuBarHeight))
            }
            
            var croppedCGImage = resizedCGImage?.cropping(to: cropRect)
            
            while croppedCGImage == nil {
                croppedCGImage = resizedCGImage?.cropping(to: cropRect)
            }

            let croppedImage = NSImage(cgImage: croppedCGImage!, size: NSSize(width: Int(screenWidth), height: Int(screenHeight)))
            
            return croppedImage
        }
        
        return nil
    }
    
    func addBlackRectangleToWallpaperOverMenuBarArea(imagePath: URL) -> NSImage? {
        guard let wallpaperImage = NSImage(contentsOf: imagePath) else {
            print("Error while obtaining the wallpaper image.")
            return nil
        }
        
        guard let screenFrame = NSScreen.main?.frame,
              let wallpaperCGImage = wallpaperImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let screenWidth = screenFrame.width
        let screenHeight = screenFrame.height
        
        let screenProportion = screenWidth / screenHeight
        let wallpaperProportion = CGFloat(wallpaperCGImage.width) / CGFloat(wallpaperCGImage.height)
        
        let menuBarHeight = NSScreen.main!.menuBarHeight
        var newWidth = Int(screenWidth)
        var newHeight = Int(screenHeight)
        var resizedCGImage: CGImage?
        var rect: CGRect
        var count = 3
        
        if wallpaperProportion >= screenProportion {
            newWidth = Int(screenHeight / CGFloat(wallpaperCGImage.height) * CGFloat(wallpaperCGImage.width))
            resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
            
            while (count > 0 && resizedCGImage == nil) {
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                count -= 1
            }
            
            let xOffset = (CGFloat(newWidth) - screenWidth) / 2
            
            rect = CGRect(
                x: xOffset,
                y: CGFloat(newHeight) - menuBarHeight + 1,
                width: screenWidth,
                height: NSScreen.main!.menuBarHeight
            )
            
        } else {
            newHeight = Int(screenWidth / CGFloat(wallpaperCGImage.width) * CGFloat(wallpaperCGImage.height))
            resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
            
            while (count > 0 && resizedCGImage == nil) {
                resizedCGImage = wallpaperCGImage.resize(width: newWidth, height: newHeight)
                count -= 1
            }
            
            let yOffset = (CGFloat(newHeight) - screenHeight) / 2
            
            rect = CGRect(
                x: 0,
                y: CGFloat(newHeight) - menuBarHeight - yOffset + 1,
                width: screenWidth,
                height: NSScreen.main!.menuBarHeight
            )
        }
        
        guard let finalImage = resizedCGImage else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: finalImage.width,
            height: finalImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(finalImage, in: CGRect(x: 0, y: 0, width: finalImage.width, height: finalImage.height))
        
        context.setFillColor(NSColor.black.cgColor)
        
        context.fill(rect)
        
        guard let newCGImage = context.makeImage() else { return nil }
        
        return NSImage(cgImage: newCGImage, size: NSSize(width: screenWidth, height: screenHeight))
    }
    
    private var staticWallpaperWorkaroundPath: URL? {
        guard appState.allowReduceTransparencyToBeDisabled,
              let path = appState.currentWallpaperPath,
              path.isFileURL,
              FileManager.default.fileExists(atPath: path.path),
              NSImage(contentsOf: path) != nil else {
            return nil
        }
        return path
    }

    private func getCurrentWallpaperWindowID() -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        
        for window in windowList {
            guard
                let cgWindowID = window[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier == "com.apple.dock",
                let windowName = window[kCGWindowName as String] as? String,
                windowName.hasPrefix("Wallpaper"),
                let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                boundsDict["Width"] ?? 0 == NSScreen.main!.frame.width,
                boundsDict["Height"] ?? 0 == NSScreen.main!.frame.height
            else {
                continue
            }
            
            return cgWindowID
        }

        return nil
    }
    
    private func getWallpaperScreenshot(cgWindowID: CGWindowID) -> CGImage? {
        let options: CGWindowListOption = [.optionAll, .optionIncludingWindow]
        guard let image = CGWindowListCreateImage(CGRect.init(x: 0, y: 0, width: NSScreen.main!.frame.width, height: NSScreen.main!.menuBarHeight), options, cgWindowID, .nominalResolution) else { return nil }
        return image
    }
    
    private func bindAllowReduceTransparency() {
        appState.$allowReduceTransparencyToBeDisabled
            .receive(on: DispatchQueue.main)
            .sink { allow in
                if allow {
                    if let wallpaperPath = self.staticWallpaperWorkaroundPath {
                        self.modifyImageAndSetAsWallpaper(path: wallpaperPath)
                    } else if let windowID = self.getCurrentWallpaperWindowID() {
                        self.wallpaper?.contents = self.getWallpaperScreenshot(cgWindowID: windowID)
                    }
                } else if Wallpaper.isWallpaperFromADirectory(screen: .main).compactMap({ $0 }).first == true,
                          let wallpaperPath = self.appState.currentWallpaperPath {
                    do {
                        try Wallpaper.set(wallpaperPath, screen: .main)
                    } catch {
                        print("Error while setting wallpaper.")
                    }
                }
                self.viewDidChangeEffectiveAppearance()
            }
            .store(in: &disposables)
    }
    
    /// Update sublayer `frame`.
    public override func layout() {
        super.layout()
        self.container!.frame = self.layer?.bounds ?? .zero
        self.backdrop!.frame = self.layer?.bounds.offsetBy(dx: 0, dy: 0) ?? .zero
        self.tint!.frame = self.layer?.bounds ?? .zero
        self.wallpaper!.frame = self.layer?.bounds.offsetBy(dx: 0, dy: 0) ?? .zero
        self.wallpaperContainer!.frame = self.layer?.bounds ?? .zero
        self.gradient!.frame = self.layer?.bounds ?? .zero
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = self.window?.backingScaleFactor ?? 1.0
        self.layer?.contentsScale = scale
        self.container!.contentsScale = scale
        self.backdrop!.contentsScale = scale
        self.tint!.contentsScale = scale
        self.wallpaper!.contentsScale = scale
        self.wallpaperContainer!.contentsScale = scale
    }
    
    deinit {
        if let observer = screenDidWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            screenDidWakeObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default.removeObserver(observer)
            screenUnlockedObserver = nil
        }
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
        wallpaperPollTimer?.invalidate()
        wallpaperPollTimer = nil
    }
}

extension CGImage {
    func resize(width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        let rep = NSBitmapImageRep(cgImage: self)

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Failed to create CGContext")
            return nil
        }

        context.interpolationQuality = .high

        context.draw(
            rep.cgImage!,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        return context.makeImage()
    }
}

extension Notification.Name {
    static let wallpaperChanged = Notification.Name("wallpaperChanged")
}
