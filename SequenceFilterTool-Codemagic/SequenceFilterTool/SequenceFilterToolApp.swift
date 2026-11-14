import SwiftUI
import UIKit
import UserNotifications
import Security
import Compression

enum SequenceFilterTheme {
    static let backgroundHex = "#FFFFFF"
    static let background = Color.white
    static let groupedBackground = Color(red: 247.0 / 255.0, green: 248.0 / 255.0, blue: 252.0 / 255.0)
    static let surface = Color.white
    static let textPrimary = Color(red: 25.0 / 255.0, green: 34.0 / 255.0, blue: 53.0 / 255.0)
    static let textSecondary = Color(red: 80.0 / 255.0, green: 94.0 / 255.0, blue: 119.0 / 255.0)
    static let uiBackground = UIColor.white
    static let uiGroupedBackground = UIColor(red: 247.0 / 255.0, green: 248.0 / 255.0, blue: 252.0 / 255.0, alpha: 1)
    static let uiTextPrimary = UIColor(red: 25.0 / 255.0, green: 34.0 / 255.0, blue: 53.0 / 255.0, alpha: 1)
    static let uiTextSecondary = UIColor(red: 80.0 / 255.0, green: 94.0 / 255.0, blue: 119.0 / 255.0, alpha: 1)
    static let accentHex = "#7C3AED"
    static let accent = Color(red: 124.0 / 255.0, green: 58.0 / 255.0, blue: 237.0 / 255.0)
    static let uiAccent = UIColor(red: 124.0 / 255.0, green: 58.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)

    static let inputAccent = Color(red: 39.0 / 255.0, green: 110.0 / 255.0, blue: 241.0 / 255.0)
    static let scoreAccent = Color(red: 18.0 / 255.0, green: 151.0 / 255.0, blue: 103.0 / 255.0)
    static let conditionsAccent = Color(red: 224.0 / 255.0, green: 111.0 / 255.0, blue: 24.0 / 255.0)
    static let queryAccent = Color(red: 94.0 / 255.0, green: 78.0 / 255.0, blue: 214.0 / 255.0)
    static let prizeAccent = Color(red: 211.0 / 255.0, green: 63.0 / 255.0, blue: 119.0 / 255.0)

    static func configureGlobalAppearance() {
        UITableView.appearance().backgroundColor = uiGroupedBackground
        UITableViewCell.appearance().backgroundColor = uiBackground
        UICollectionView.appearance().backgroundColor = uiGroupedBackground
        UICollectionViewCell.appearance().backgroundColor = uiBackground

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = uiBackground
        navigationAppearance.shadowColor = .clear
        navigationAppearance.titleTextAttributes = [.foregroundColor: uiTextPrimary]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: uiTextPrimary]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = uiAccent

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = uiBackground
        tabAppearance.shadowColor = .clear
        for itemAppearance in [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.normal.iconColor = uiTextSecondary
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: uiTextSecondary]
            itemAppearance.selected.iconColor = uiAccent
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: uiAccent]
        }
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = uiAccent
        UITabBar.appearance().unselectedItemTintColor = uiTextSecondary
    }
}

private struct SequenceFilterModuleAccentKey: EnvironmentKey {
    static let defaultValue = SequenceFilterTheme.accent
}

extension EnvironmentValues {
    var sequenceFilterModuleAccent: Color {
        get { self[SequenceFilterModuleAccentKey.self] }
        set { self[SequenceFilterModuleAccentKey.self] = newValue }
    }
}

struct PatternedActionButtonStyle: ButtonStyle {
    @Environment(\.sequenceFilterModuleAccent) private var moduleAccent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(isEnabled ? SequenceFilterTheme.textPrimary : SequenceFilterTheme.textSecondary.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [moduleAccent.opacity(isEnabled ? 0.16 : 0.06), moduleAccent.opacity(isEnabled ? 0.38 : 0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(alignment: .trailing) {
                        Image(systemName: "circle.grid.cross")
                            .font(.title2)
                            .foregroundStyle(moduleAccent.opacity(isEnabled ? 0.18 : 0.08))
                            .padding(.trailing, 10)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(moduleAccent.opacity(isEnabled ? 0.52 : 0.16), lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ColorfulOutlineButtonStyle: ButtonStyle {
    @Environment(\.sequenceFilterModuleAccent) private var moduleAccent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(isEnabled ? moduleAccent : SequenceFilterTheme.textSecondary.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(moduleAccent.opacity(isEnabled ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(moduleAccent.opacity(isEnabled ? 0.55 : 0.16), style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

extension View {
    func sequenceFilterModulePalette(_ accent: Color) -> some View {
        tint(accent)
            .environment(\.sequenceFilterModuleAccent, accent)
            .foregroundStyle(SequenceFilterTheme.textPrimary)
    }
}

/// UserDefaults 会在卸载时被系统删除。这里将所有 sequenceFilter.* 业务数据
/// 分块镜像到钥匙串，重装后首次启动再自动恢复。
enum DurableAppBackup {
    private struct Manifest: Codable {
        let version: Int
        let generation: String
        let chunkCount: Int
        let payloadSize: Int
        let savedAt: Date
        /// v1没有这三个字段；保持可选以便重装时继续读取旧备份。
        let storedSize: Int?
        let encoding: String?
        let payloadFingerprint: UInt64?
    }

    private static let version = 2
    /// 历史TXT通常有数MB。较大的分块配合LZFSE可把一次备份从约200次
    /// 钥匙串增删降到个位数，避免XS在场景切换时被看门狗终止。
    private static let chunkSize = 256 * 1024
    private static let lzfseEncoding = "lzfse"
    private static let backupLock = NSLock()
    private static let markerKey = "sequenceFilter.durableInstallMarker.v1"
    private static let manifestAccount = "manifest"
    /// 这些都是可由当前条件/赛果重建的派生结果，不进入钥匙串耐久备份。
    /// 否则重装后会把奖金和查询的旧缓存再次恢复。
    private static let excludedComputedCacheKeys: Set<String> = [
        "sequenceFilter.previousRun.v1",
        "sequenceFilter.globalFilterCountsCache.v1",
        "sequenceFilter.globalFilterConditionsSignature.v1",
        "sequenceFilter.globalABCDCache.v1",
        "sequenceFilter.globalPrizeLastSync.v1",
        "sequenceFilter.globalAnswerCacheSeedCompleted.v1"
    ]
    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "com.mengqingfeng.SequenceFilterTool") + ".durable-backup.v1"
    }

    @discardableResult
    static func restoreAfterReinstallIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: markerKey) { return false }
        defer { defaults.set(true, forKey: markerKey) }
        guard let manifestData = read(account: manifestAccount),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
              (1...version).contains(manifest.version),
              manifest.chunkCount > 0 else { return false }

        var storedPayload = Data()
        storedPayload.reserveCapacity(manifest.storedSize ?? manifest.payloadSize)
        for index in 0..<manifest.chunkCount {
            guard let chunk = read(account: chunkAccount(manifest.generation, index)) else { return false }
            storedPayload.append(chunk)
        }
        guard storedPayload.count == (manifest.storedSize ?? manifest.payloadSize) else { return false }
        let payload: Data
        if manifest.encoding == lzfseEncoding {
            guard let expanded = decompressLZFSE(storedPayload, expectedSize: manifest.payloadSize) else {
                return false
            }
            payload = expanded
        } else {
            payload = storedPayload
        }
        guard payload.count == manifest.payloadSize,
              let values = try? PropertyListSerialization.propertyList(from: payload, format: nil),
              let dictionary = values as? [String: Any] else { return false }
        for (key, value) in dictionary where key.hasPrefix("sequenceFilter.") && key != markerKey {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
        return !dictionary.isEmpty
    }

    @discardableResult
    static func backupNow(defaults: UserDefaults = .standard) -> Bool {
        // 输入保存和场景切换可能同时请求备份。绝不排队等待钥匙串，
        // 当前一轮完成后下一次输入变更还会重新调度。
        guard backupLock.try() else { return false }
        defer { backupLock.unlock() }
        let values = defaults.dictionaryRepresentation().filter {
            $0.key.hasPrefix("sequenceFilter.")
                && $0.key != markerKey
                && !excludedComputedCacheKeys.contains($0.key)
        }
        guard !values.isEmpty,
              let payload = try? PropertyListSerialization.data(
                fromPropertyList: values,
                format: .binary,
                options: 0
              ) else { return false }

        let oldManifest = read(account: manifestAccount).flatMap {
            try? JSONDecoder().decode(Manifest.self, from: $0)
        }
        let fingerprint = payloadFingerprint(payload)
        if oldManifest?.payloadSize == payload.count,
           oldManifest?.payloadFingerprint == fingerprint {
            return true
        }
        let compressed = compressLZFSE(payload)
        let storedPayload: Data
        let encoding: String?
        if let compressed, compressed.count < payload.count {
            storedPayload = compressed
            encoding = lzfseEncoding
        } else {
            storedPayload = payload
            encoding = nil
        }
        let generation = UUID().uuidString
        let chunks = stride(from: 0, to: storedPayload.count, by: chunkSize).map { offset in
            storedPayload.subdata(in: offset..<min(offset + chunkSize, storedPayload.count))
        }
        guard !chunks.isEmpty else { return false }
        for (index, chunk) in chunks.enumerated() {
            guard write(chunk, account: chunkAccount(generation, index)) else {
                deleteGeneration(generation, chunkCount: chunks.count)
                return false
            }
        }
        let manifest = Manifest(
            version: version,
            generation: generation,
            chunkCount: chunks.count,
            payloadSize: payload.count,
            savedAt: Date(),
            storedSize: storedPayload.count,
            encoding: encoding,
            payloadFingerprint: fingerprint
        )
        guard let manifestData = try? JSONEncoder().encode(manifest),
              write(manifestData, account: manifestAccount) else {
            deleteGeneration(generation, chunkCount: chunks.count)
            return false
        }
        if let oldManifest, oldManifest.generation != generation {
            deleteGeneration(oldManifest.generation, chunkCount: oldManifest.chunkCount)
        }
        return true
    }

    private static func payloadFingerprint(_ data: Data) -> UInt64 {
        // 稳定的FNV-1a；只用于跳过完全相同的备份，不参与安全判断。
        data.reduce(14_695_981_039_346_656_037) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private static func compressLZFSE(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        var destination = Data(count: data.count + 64 * 1024)
        let encodedCount = destination.withUnsafeMutableBytes { destinationBytes in
            data.withUnsafeBytes { sourceBytes in
                compression_encode_buffer(
                    destinationBytes.bindMemory(to: UInt8.self).baseAddress!,
                    destinationBytes.count,
                    sourceBytes.bindMemory(to: UInt8.self).baseAddress!,
                    sourceBytes.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard encodedCount > 0 else { return nil }
        destination.removeSubrange(encodedCount..<destination.count)
        return destination
    }

    private static func decompressLZFSE(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize >= 0 else { return nil }
        if expectedSize == 0 { return Data() }
        var destination = Data(count: expectedSize)
        let decodedCount = destination.withUnsafeMutableBytes { destinationBytes in
            data.withUnsafeBytes { sourceBytes in
                compression_decode_buffer(
                    destinationBytes.bindMemory(to: UInt8.self).baseAddress!,
                    destinationBytes.count,
                    sourceBytes.bindMemory(to: UInt8.self).baseAddress!,
                    sourceBytes.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        return decodedCount == expectedSize ? destination : nil
    }

    /// 只验证压缩格式本身，不接触钥匙串。
    static func compressedRoundTripForTesting(_ data: Data) -> Data? {
        guard let compressed = compressLZFSE(data) else { return nil }
        return decompressLZFSE(compressed, expectedSize: data.count)
    }

    private static func chunkAccount(_ generation: String, _ index: Int) -> String {
        "\(generation).chunk.\(index)"
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func write(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func deleteGeneration(_ generation: String, chunkCount: Int) {
        guard chunkCount > 0 else { return }
        for index in 0..<chunkCount { delete(account: chunkAccount(generation, index)) }
    }
}

enum SequenceFilterAlarmNotification {
    static let identifierPrefix = "sequenceFilter.seventh.alarm."
    static let categoryIdentifier = "SEQUENCE_FILTER_SEVENTH_ALARM"
    static let stopActionIdentifier = "SEQUENCE_FILTER_STOP_ALARM"
}

@MainActor
enum SequenceFilterPrivacyShield {
    private static let viewTag = 8_271_218

    static func setVisible(_ visible: Bool) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        for window in windows {
            if visible {
                if let existing = window.viewWithTag(viewTag) {
                    window.bringSubviewToFront(existing)
                    continue
                }

                let shield = UIView(frame: window.bounds)
                shield.tag = viewTag
                shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                shield.backgroundColor = SequenceFilterTheme.uiBackground
                shield.isUserInteractionEnabled = true
                shield.accessibilityViewIsModal = true
                shield.accessibilityLabel = "防窥保护中"

                let icon = UIImageView(image: UIImage(systemName: "eye.slash.fill"))
                icon.tintColor = SequenceFilterTheme.uiAccent
                icon.contentMode = .scaleAspectFit
                icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .semibold)

                let title = UILabel()
                title.text = "防窥保护中"
                title.textColor = .white
                title.font = .systemFont(ofSize: 20, weight: .bold)
                title.textAlignment = .center

                let detail = UILabel()
                detail.text = "返回 App 后自动恢复显示"
                detail.textColor = .white
                detail.font = .systemFont(ofSize: 13, weight: .medium)
                detail.textAlignment = .center

                let stack = UIStackView(arrangedSubviews: [icon, title, detail])
                stack.axis = .vertical
                stack.alignment = .center
                stack.spacing = 12
                stack.translatesAutoresizingMaskIntoConstraints = false
                shield.addSubview(stack)
                NSLayoutConstraint.activate([
                    icon.widthAnchor.constraint(equalToConstant: 60),
                    icon.heightAnchor.constraint(equalToConstant: 60),
                    stack.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
                    stack.centerYAnchor.constraint(equalTo: shield.centerYAnchor)
                ])

                window.addSubview(shield)
                window.bringSubviewToFront(shield)
            } else {
                window.viewWithTag(viewTag)?.removeFromSuperview()
            }
        }
    }

    static var isScreenCaptured: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map(\.screen)
            .contains(where: \.isCaptured)
    }
}

final class SequenceFilterNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        // 闹钟功能已移除；升级时只取消本应用旧闹钟，不碰其他通知。
        center.getPendingNotificationRequests { requests in
            let alarmIDs = requests.map(\.identifier).filter {
                $0.hasPrefix(SequenceFilterAlarmNotification.identifierPrefix)
                    || $0.hasPrefix("sequenceFilter.seventh.")
            }
            center.removePendingNotificationRequests(withIdentifiers: alarmIDs)
            center.removeDeliveredNotifications(withIdentifiers: alarmIDs)
        }
        center.setNotificationCategories([])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenCaptureStateChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Task { @MainActor in
            SequenceFilterPrivacyShield.setVisible(true)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            SequenceFilterPrivacyShield.setVisible(true)
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            SequenceFilterPrivacyShield.setVisible(SequenceFilterPrivacyShield.isScreenCaptured)
        }
    }

    @objc private func screenCaptureStateChanged() {
        Task { @MainActor in
            SequenceFilterPrivacyShield.setVisible(SequenceFilterPrivacyShield.isScreenCaptured)
        }
    }

}

/// A one-time local import, applied before ContentView reads any saved state.
/// The desktop prepares the merged payload and keeps both device backups.
enum DeviceDataMigration {
    static let payloadFilename = "device-data-migration.plist"
    static let receiptFilename = "device-data-migration-receipt.plist"
    private static let markerKey = "sequenceFilter.deviceDataMigration.completedID.v1"

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var hasPendingImport: Bool {
        FileManager.default.fileExists(atPath: documentsURL.appendingPathComponent(payloadFilename).path)
    }

    @discardableResult
    static func importIfPresent(directory: URL = documentsURL, defaults: UserDefaults = .standard,
                                domain: String = Bundle.main.bundleIdentifier ?? "com.mengqingfeng.SequenceFilterTool",
                                writeDurableBackup: Bool = true) throws -> Bool {
        let file = directory.appendingPathComponent(payloadFilename)
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let data = try Data(contentsOf: file)
        guard let envelope = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              envelope["version"] as? Int == 1,
              let id = envelope["id"] as? String, UUID(uuidString: id) != nil,
              let values = envelope["values"] as? [String: Any], !values.isEmpty,
              values.keys.allSatisfy({ $0.hasPrefix("sequenceFilter.") }),
              values[markerKey] == nil,
              let removeKeys = envelope["removeKeys"] as? [String],
              removeKeys.allSatisfy({ $0.hasPrefix("sequenceFilter.") && $0 != markerKey }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let importedFile = directory.appendingPathComponent("device-data-migration-imported-\(id).plist")
        if defaults.string(forKey: markerKey) == id {
            try? FileManager.default.moveItem(at: file, to: importedFile)
            return false
        }
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        let backupFile = directory.appendingPathComponent("device-data-migration-before-\(id).plist")
        try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
            .write(to: backupFile, options: .atomic)
        var merged = original.merging(values) { _, incoming in incoming }
        for key in removeKeys { merged.removeValue(forKey: key) }
        merged[markerKey] = id
        let affectedKeys = Set(values.keys).union(removeKeys).union([markerKey])
        do {
            // Apply each business key through the same API used by the app's
            // normal saves, retaining unrelated preference domain state.
            for key in affectedKeys where key != markerKey {
                if let value = merged[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            defaults.set(id, forKey: markerKey)
            guard defaults.synchronize(),
                  let written = defaults.persistentDomain(forName: domain),
                  NSDictionary(dictionary: written).isEqual(to: merged) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let receipt: [String: Any] = ["version": 1, "id": id, "completedAt": Date(),
                                        "importedKeyCount": values.count, "removedKeys": removeKeys,
                                        "backupFilename": backupFile.lastPathComponent]
            try PropertyListSerialization.data(fromPropertyList: receipt, format: .binary, options: 0)
                .write(to: directory.appendingPathComponent(receiptFilename), options: .atomic)
        } catch {
            for key in affectedKeys {
                if let value = original[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.synchronize()
            throw error
        }
        try? FileManager.default.moveItem(at: file, to: importedFile)
        if writeDurableBackup { _ = DurableAppBackup.backupNow(defaults: defaults) }
        return true
    }
}

private struct MigrationPreparedContentView: View {
    @State private var needsImport = DeviceDataMigration.hasPendingImport
    @State private var hasFailed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if !needsImport {
                ContentView()
            } else if hasFailed {
                VStack(spacing: 16) {
                    Text("数据恢复未完成，原有数据已保留。")
                    Button("重试恢复") { hasFailed = false; attempt += 1 }
                }.padding()
            } else {
                ProgressView("正在恢复数据…")
            }
        }
        .task(id: attempt) {
            guard needsImport else { return }
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try DeviceDataMigration.importIfPresent()
                }.value
                needsImport = false
            } catch {
                hasFailed = true
            }
        }
    }
}

@main
struct SequenceFilterToolApp: App {
    @UIApplicationDelegateAdaptor(SequenceFilterNotificationDelegate.self) private var notificationDelegate

    init() {
        SequenceFilterTheme.configureGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            MigrationPreparedContentView()
                .preferredColorScheme(.light)
                .tint(SequenceFilterTheme.accent)
                .foregroundStyle(SequenceFilterTheme.textPrimary)
                .background(SequenceFilterTheme.background.ignoresSafeArea())
        }
    }
}
