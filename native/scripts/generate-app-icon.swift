#!/usr/bin/env swift

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let nativeURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let repositoryURL = nativeURL.deletingLastPathComponent()
let sourceURL = nativeURL.appending(path: "IconSources/AgentWorkspaceIcon.png")

let destinations: [(directory: URL, name: String, pixels: Int)] = [
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_16x16.png", 16),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_16x16@2x.png", 32),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_32x32.png", 32),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_32x32@2x.png", 64),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_128x128.png", 128),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_128x128@2x.png", 256),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_256x256.png", 256),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_256x256@2x.png", 512),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_512x512.png", 512),
    (nativeURL.appending(path: "IconSources/AppIcon.iconset"), "icon_512x512@2x.png", 1024),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_16x16.png", 16),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_16x16@2x.png", 32),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_32x32.png", 32),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_32x32@2x.png", 64),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_128x128.png", 128),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_128x128@2x.png", 256),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_256x256.png", 256),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_256x256@2x.png", 512),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_512x512.png", 512),
    (repositoryURL.appending(path: "assets/AppIcon.iconset"), "icon_512x512@2x.png", 1024),
]

guard
    let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fatalError("Cannot read icon source: \(sourceURL.path)")
}

func renderIcon(pixels: Int) -> CGImage {
    let scale = CGFloat(pixels) / 1024
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.addPath(CGPath(
        roundedRect: CGRect(x: 62 * scale, y: 62 * scale, width: 900 * scale, height: 900 * scale),
        cornerWidth: 200 * scale,
        cornerHeight: 200 * scale,
        transform: nil
    ))
    context.clip()
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "AppIconGenerator", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "AppIconGenerator", code: 2)
    }
}

let master = renderIcon(pixels: 1024)
try writePNG(master, to: nativeURL.appending(path: "IconSources/AppIcon-master.png"))
try writePNG(renderIcon(pixels: 64), to: nativeURL.appending(path: "IconSources/preview/AppIcon-64.png"))

for destination in destinations {
    try writePNG(renderIcon(pixels: destination.pixels), to: destination.directory.appending(path: destination.name))
}

print("Generated app icon assets.")
