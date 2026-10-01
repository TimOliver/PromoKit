//
//  PromoFileManager.swift
//
//  Copyright 2024-2025 Timothy Oliver. All rights reserved.
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

    /// The file manager used for all file operations. Override in tests to provide a mock.
    public static var fileManager = FileManager.default

    /// The root URL of the app's resource directory, used as the base path when scanning for icons.
    /// Defaults to `Bundle.main.resourceURL`. Tests can assign a temp directory to exercise the
    /// icon lookup logic against a synthetic file set; restore the original value afterwards.
    public static var resourceURL: URL? = Bundle.main.resourceURL

    /// Finds the smallest app icon that meets the requested point size, or the largest available fallback.
    /// - Parameter named: The name of the app icon to search for (eg "AppIcon" for matching "AppIcon76x76@2x.png")
    /// - Parameter dimension: The desired size in points. Equal point sizes prefer the higher display scale.
    /// - Returns: The selected icon's URL, or nil if no supported filename is found.
    public static func urlForAppIcon(named iconName: String, targetDimension dimension: Int = 128) -> URL? {
        guard let resourcePath = resourceURL?.path,
              let contents = try? fileManager.contentsOfDirectory(atPath: resourcePath),
              !contents.isEmpty else { return nil }

        // Save the file name and extracted sizing data
        var appIcon = (name: "", size: 0, scale: 0)

        // Loop through all the files to find the one that is most appropriate
        for fileName in contents {
            // Skip files that don't start with our icon name
            guard fileName.hasPrefix(iconName) else { continue }

            // Remove the icon name from a filename such as `AppIcon76x76@2x.png`.
            let droppedName = String(fileName.dropFirst(iconName.count))

            // Extract the point size and display scale from `76x76@2x.png`.
            guard let sizeString = droppedName.components(separatedBy: "x").first, let size = Int(sizeString),
                  let scaleString = droppedName.components(separatedBy: "@").last?.components(separatedBy: "x").first, let scale = Int(scaleString)
            else { continue }

            guard size > 0, scale > 0 else { continue }

            // Prefer the smallest icon that meets the requested size. If none
            // does, use the largest available icon, independent of file order.
            let preferred: Bool
            if appIcon.size == 0 {
                preferred = true
            } else if size == appIcon.size {
                preferred = scale > appIcon.scale
            } else if size >= dimension {
                preferred = appIcon.size < dimension || size < appIcon.size
            } else {
                preferred = appIcon.size < dimension && size > appIcon.size
            }
            if preferred { appIcon = (name: fileName, size: size, scale: scale) }
        }

        guard !appIcon.name.isEmpty else { return nil }
        return resourceURL?.appendingPathComponent(appIcon.name)
    }
}
