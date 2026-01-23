import SwiftUI
import Combine
import ImageIO

// MARK: - 图片缓存管理器
final class ImageCache {
    static let shared = ImageCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.neteasemusic.imagecache", qos: .utility)
    
    private init() {
        // 设置内存缓存限制
        cache.countLimit = 150
        cache.totalCostLimit = 80 * 1024 * 1024  // 80MB
        
        // 设置磁盘缓存目录
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")
        
        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        clearMemoryCache()
    }
    
    // MARK: - 内存缓存
    func getFromMemory(_ url: URL, targetSize: CGSize? = nil) -> UIImage? {
        let key = cacheKey(for: url, targetSize: targetSize)
        return cache.object(forKey: key as NSString)
    }
    
    func saveToMemory(_ image: UIImage, for url: URL, targetSize: CGSize? = nil) {
        let key = cacheKey(for: url, targetSize: targetSize)
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    private func cacheKey(for url: URL, targetSize: CGSize?) -> String {
        if let size = targetSize {
            return "\(url.absoluteString)_\(Int(size.width))x\(Int(size.height))"
        }
        return url.absoluteString
    }
    
    // MARK: - 磁盘缓存
    func getFromDisk(_ url: URL, targetSize: CGSize? = nil) -> UIImage? {
        let filePath = diskCachePath(for: url)
        guard let data = try? Data(contentsOf: filePath) else {
            return nil
        }
        
        // 如果指定了目标尺寸，进行下采样
        let image: UIImage?
        if let size = targetSize {
            image = downsample(data: data, to: size)
        } else {
            image = UIImage(data: data)
        }
        
        // 同时加载到内存缓存
        if let img = image {
            saveToMemory(img, for: url, targetSize: targetSize)
        }
        return image
    }
    
    func saveToDisk(_ data: Data, for url: URL) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let filePath = self.diskCachePath(for: url)
            try? data.write(to: filePath)
        }
    }
    
    private func diskCachePath(for url: URL) -> URL {
        let fileName = url.absoluteString.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(200)
        return cacheDirectory.appendingPathComponent(String(fileName))
    }
    
    // MARK: - 图片下采样（减少内存占用）
    func downsample(data: Data, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return UIImage(data: data)
        }
        
        let scale = UIScreen.main.scale
        let maxDimension = max(targetSize.width, targetSize.height) * scale
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return UIImage(data: data)
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - 清理缓存
    func clearMemoryCache() {
        cache.removeAllObjects()
    }
    
    func clearDiskCache() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectory)
            try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - 缓存大小
    func diskCacheSize() -> Int64 {
        var size: Int64 = 0
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }
}

// MARK: - 缓存图片加载器
final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    
    private var cancellable: AnyCancellable?
    private let cache = ImageCache.shared
    private var targetSize: CGSize?
    
    func load(from url: URL, targetSize: CGSize? = nil) {
        self.targetSize = targetSize
        
        // 1. 先检查内存缓存
        if let cached = cache.getFromMemory(url, targetSize: targetSize) {
            self.image = cached
            return
        }
        
        // 2. 检查磁盘缓存（在后台线程）
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let cached = self.cache.getFromDisk(url, targetSize: targetSize) {
                DispatchQueue.main.async {
                    self.image = cached
                }
                return
            }
            
            // 3. 网络加载
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            self.cancellable = URLSession.shared.dataTaskPublisher(for: url)
                .subscribe(on: DispatchQueue.global(qos: .userInitiated))
                .map { [weak self] data, _ -> UIImage? in
                    guard let self = self else { return nil }
                    // 保存原始数据到磁盘
                    self.cache.saveToDisk(data, for: url)
                    // 下采样后返回
                    if let size = self.targetSize {
                        return self.cache.downsample(data: data, to: size)
                    }
                    return UIImage(data: data)
                }
                .replaceError(with: nil)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] loadedImage in
                    guard let self = self else { return }
                    self.isLoading = false
                    if let image = loadedImage {
                        self.cache.saveToMemory(image, for: url, targetSize: self.targetSize)
                        self.image = image
                    }
                }
        }
    }
    
    func cancel() {
        cancellable?.cancel()
    }
}

// MARK: - 缓存异步图片视图
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @StateObject private var loader = CachedImageLoader()
    
    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            if let url = url {
                loader.load(from: url, targetSize: targetSize)
            }
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

// MARK: - 便捷初始化器
extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(url: url, content: content, placeholder: { ProgressView() })
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?) {
        self.init(url: url, content: { $0 }, placeholder: { ProgressView() })
    }
}
