#if VPHONE_CUSTOM_DISTRIBUTION && VPHONE_CUSTOM_LOCAL_IMAGES
import AppKit
import VPhoneDistribution

extension VPhoneDistributionModel {
    func chooseLocalImageDirectory() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择本地镜像目录"
        panel.message = "目录内放置完整镜像归档和 images.json 版本清单；不会上传或复制镜像。"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.present { url in
            self.localImageDirectory = url.path
            UserDefaults.standard.set(url.path, forKey: "distribution.localImageDirectory")
            self.reloadLocalImages()
        }
    }

    func reloadLocalImages() {
        guard !busy else { return }
        do {
            let folder = URL(fileURLWithPath: localImageDirectory, isDirectory: true)
            let values = try DistributionLocalImages.read(folder)
            localImages = values
            if !values.contains(where: { $0.id == selectedImageID }) { selectedImageID = values.first?.id ?? "" }
            error = ""
            status = "已读取本地目录的 \(values.count) 个镜像版本；尚未导入，不上传镜像。"
        } catch {
            localImages = []; selectedImageID = ""
            self.error = "本地镜像目录读取失败：" + error.localizedDescription
        }
    }
}
#endif
