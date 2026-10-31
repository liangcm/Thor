# Thor

Open the right application ASAP.

![Screenshots](./screenshot_list.png)

Thor is an OS X application that allows you to open other application immediately just by a shortcut. And it's available in [Mac App Store](https://apps.apple.com/cn/app/thor/id1120999687?l=en&mt=12)! Feel free to enjoy the increased efficiency.

![Screenshots](./screenshot_settings.png)

## Build from source

* Xcode 13.1 or later
* [CocoaPods](https://cocoapods.org/)

Thor uses [Cocoapods](https://cocoapods.org/) as dependency manager, follow the instructions below to build all dependencies.

```
git clone https://github.com/gbammc/Thor.git
cd /path/to/Thor
pod install
```

## Download

[Click here to download the latest release.](https://github.com/gbammc/Thor/releases)

## Thanks

The UI idea is from [Pomodoro One](http://rinik.net/pomodoro/) and thanks to the great work of [MASShortcut](https://github.com/shpakovski/MASShortcut) !

## License

#### The MIT License (MIT)


Copyright (c) 2014 – 2024 Alvin Zhu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.




## Thor+ window layouts

- Control + grave (the key left of 1, shown as · on some Chinese keyboards): maximize the focused window.
- Control + 1: left half of the current display.
- Control + 2: right half of the current display.
- Control + T: show or hide the Thor+ settings window (default for new installations).

Window changes animate over 0.24 seconds with ease-in/ease-out. Repeated shortcuts
retarget from the current frame; the macOS Reduce Motion setting is respected.

These actions appear in the shortcut list and can be reassigned or cleared. Existing
assignments are preserved on first launch. Accessibility permission is required.
The display containing the largest portion of the window is used; menu bar and Dock
space are excluded. Native full-screen windows must first leave full screen, and
applications may enforce their own minimum window sizes. Quit Magnet to release its
shortcuts before using these actions.

Local build with Xcode 27:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace Thor.xcworkspace -scheme Thor -configuration Release \
  -derivedDataPath /private/tmp/ThorPlus-window-build \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 build
```
