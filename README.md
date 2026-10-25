### fixes added by this fork:

- menu bar automatically updates when connecting to an external display
- minor math fix for rendering on custom resolution
- (attempt) wallpaper replace logic fix for macos 14 Sonoma for Disabled Transparency mode
- fix for menu bar not displaying when switching desktops on Disabled Transparency mode

<i>tested on macos 14 Sonoma 13.3-inch display (should support 15 Sequoia as well)</i>

# Clear Menu Bar

> Make the macOS menu bar transparent.

<p align="center"><img src="ClearMenuBar/Assets.xcassets/AppIcon.appiconset/Clear Menu Bar-256.png" width="128"></p>

<p align="center"><img src="Images/Screenshot.png"></p>

## Features

- Supports single wallpaper or multiple wallpapers from a folder;
- Supports light and dark mode.

## Feature Support

|                                                                         | Reduce Transparency **Off** | Reduce Transparency **On** |
|-------------------------------------------------------------------------|-----------------------------|----------------------------|
| Single Wallpaper (JPG or PNG image)                                     | ✅                          | ✅                         |
| Multiple Wallpapers from a Folder (JPG or PNG images)                   | ❌                          | ✅                         |
| Dynamic or Motion Wallpapers (Light/Dark mode or video support)         | ❌                          | ❌                         |

## Requirements

- Requires macOS 14 Sonoma or later.
- The Reduce Transparency option may need to be enabled in the Accessibility section of System Settings for this application to work as expected.
- The wallpaper needs to be set with the "Fill Screen" option.
- The wallpaper needs to be a static image. This app will not work with dynamic or aerial wallpapers.

## Contributing

Pull requests are welcome.

## License
[GNU General Public License](https://github.com/zorth64/ClearMenuBar/blob/master/LICENSE)
