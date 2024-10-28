//
//  PromoFileManager.swift
//
//  Copyright 2024 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation

public class PromoFileManager {

    /// Convenienice property for accessing this app's default file manager object
    public static var fileManager = FileManager.default

    /// Convenience property for accessing this app's main bundle
    public static var mainBundle: Bundle = Bundle.main

    /// The resource path, which is the root directory of the app package contents
    public static var resourceURL: URL? { mainBundle.resourceURL }

    /// Locates the largest available version of an app icon, closest to the desired size.
    /// - Parameter named: The name of the app icon to search for (eg "AppIcon" for matching "AppIcon76x76@2x.png")
    /// - Parameter dimension: The desired size in points. The icon with the closest largest to this value will be used
    /// - Returns: The absolute URL to the largest icon
    public static func urlForAppIcon(named iconName: String, targetDimension dimension: Int = 128) -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: resourceURL?.path ?? ""),
              !contents.isEmpty else { return nil }

        // Save the file name and extracted sizing data
        var appIcon = (name: "", size: 0, scale: 0)

        // Loop through all the files to find the one that is most appropriate
        for fileName in contents {
            // Skip files that don't start with our icon name
            guard fileName.hasPrefix(iconName) else { continue }

            // Assuming we have a file formatted like `AppIcon67x67@2x.png`, drop the 'AppIcon' part first
            let droppedName = String(fileName.dropFirst(iconName.count))

            // We should now have a string like `67x67@2x.png`. Let's extract the first `67`, and the `2x`
            guard let sizeString = droppedName.components(separatedBy: "x").first, let size = Int(sizeString),
                  let scaleString = droppedName.components(separatedBy: "@").last?.components(separatedBy: "x").first, let scale = Int(scaleString)
            else { continue }

            // We have two goals here. To find the app icon with a larger dimension that what was requested.
            // But failing that, the largest one we have available.

            // If we're a smaller value than the dimension, but we're bigger than the last saved value, save.
            // Or, if we're bigger than the dimension, and we're smaller than the last saved value (if it's not 0), also save.
            if (size < dimension && size >= appIcon.size) ||
                (size > dimension && (appIcon.size == 0 || size <= appIcon.size)) {
                if size == appIcon.size, appIcon.scale > scale { continue } // If the sizes match, upgrade to the highest scale
                appIcon = (name: fileName, size: size, scale: scale)
            }
        }

        guard !appIcon.name.isEmpty else { return nil }
        return mainBundle.resourceURL?.appendingPathComponent(appIcon.name)
    }
}
