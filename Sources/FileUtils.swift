import AppKit
import Foundation
import QuickLookThumbnailing

enum FileDateType {
    case modified
    case created
}

enum FileUtils {
    static func fileSize(at url: URL) -> String {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            if values.isDirectory == true {
                return "Folder"
            }

            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        } catch {
            return "Unknown Size"
        }
    }

    static func fileDate(at url: URL, type: FileDateType) -> Date? {
        do {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            switch type {
            case .modified:
                return values.contentModificationDate
            case .created:
                return values.creationDate
            }
        } catch {
            return nil
        }
    }

    static func fileThumbnail(at url: URL, size: CGSize) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        let semaphore = DispatchSemaphore(value: 0)
        var resultImage: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
            if let cgImage = thumbnail?.cgImage {
                resultImage = NSImage(cgImage: cgImage, size: NSSize(width: size.width, height: size.height))
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        return resultImage
    }

    static func appsForFile(at url: URL) -> [(name: String, url: URL)] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
            .map { appURL in
                let name = (try? appURL.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                    ?? appURL.deletingPathExtension().lastPathComponent
                return (name: name, url: appURL)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
