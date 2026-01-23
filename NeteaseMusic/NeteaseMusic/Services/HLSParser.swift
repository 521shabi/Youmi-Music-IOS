//
//  HLSParser.swift
//  NeteaseMusic
//
//  Created by Claude Code on 2026-01-23.
//  统一的HLS解析器，整合所有HLS m3u8解析逻辑
//

import Foundation

// 注意：HLSVariant 结构体已在 PlayerView.swift 中定义
// 为了避免冲突，这里不重复定义，直接使用全局的 HLSVariant

// 为 HLSVariant 添加扩展，提供 aspectRatio 属性
extension HLSVariant {
    var aspectRatio: Double {
        Double(width) / Double(height)
    }
}

/// 变体选择策略
enum HLSVariantSelectionStrategy {
    /// 偏好特定宽高比（如3:4用于锁屏动画封面）
    case preferAspectRatio(width: Int, height: Int, maxPixels: Int?)
    /// 选择最高质量（最高分辨率和带宽）
    case highestQuality(maxPixels: Int?)
    /// 选择最低带宽（节省流量）
    case lowestBandwidth
}

/// 统一的HLS解析器
class HLSParser {
    static let shared = HLSParser()

    private init() {}

    // MARK: - Public API

    /// 从master m3u8中选择最佳变体
    /// - Parameters:
    ///   - masterText: master m3u8文本内容
    ///   - baseUrl: master m3u8的URL，用于解析相对路径
    ///   - strategy: 变体选择策略
    /// - Returns: 选中的变体URL，如果解析失败返回nil
    func selectVariant(
        from masterText: String,
        baseUrl: String,
        strategy: HLSVariantSelectionStrategy
    ) -> String? {
        let variants = parseVariants(from: masterText)
        guard !variants.isEmpty else { return nil }

        guard let selectedVariant = selectBestVariant(from: variants, strategy: strategy) else {
            return nil
        }

        return resolveUrl(selectedVariant.url, baseUrl: baseUrl)
    }

    /// 解析master m3u8，提取所有变体信息
    /// - Parameter text: m3u8文本内容
    /// - Returns: 变体数组
    func parseVariants(from text: String) -> [HLSVariant] {
        let lines = text.components(separatedBy: "\n")
        var variants: [HLSVariant] = []

        for i in 0..<lines.count {
            let line = lines[i]
            
            // 支持两种格式：#EXT-X-STREAM-INF 和 #EXT-X-I-FRAME-STREAM-INF
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                guard i + 1 < lines.count else { continue }
                let urlLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                guard !urlLine.isEmpty && !urlLine.hasPrefix("#") else { continue }

                // 提取带宽
                guard let bandwidth = extractBandwidth(from: line) else { continue }
                // 提取分辨率
                guard let resolution = extractResolution(from: line) else { continue }

                let variant = HLSVariant(
                    bandwidth: bandwidth,
                    width: resolution.width,
                    height: resolution.height,
                    url: urlLine
                )
                variants.append(variant)
            } else if line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") {
                // I-FRAME 流：URI 在同一行
                guard let bandwidth = extractBandwidth(from: line),
                      let resolution = extractResolution(from: line),
                      let uri = extractURI(from: line) else { continue }
                
                let variant = HLSVariant(
                    bandwidth: bandwidth,
                    width: resolution.width,
                    height: resolution.height,
                    url: uri
                )
                variants.append(variant)
            }
        }

        return variants
    }

    /// 从变体m3u8中提取所有TS片段URL
    /// - Parameters:
    ///   - text: 变体m3u8文本内容
    ///   - baseUrl: 变体m3u8的URL，用于解析相对路径
    /// - Returns: TS片段URL数组
    func extractTSUrls(from text: String, baseUrl: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var tsUrls: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                let fullUrl = resolveUrl(trimmed, baseUrl: baseUrl)
                tsUrls.append(fullUrl)
            }
        }

        return tsUrls
    }

    /// 将相对URL解析为绝对URL
    /// - Parameters:
    ///   - path: 相对或绝对路径
    ///   - baseUrl: 基础URL
    /// - Returns: 绝对URL
    func resolveUrl(_ path: String, baseUrl: String) -> String {
        // 如果已经是绝对URL，直接返回
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }

        // 解析相对路径
        guard let base = URL(string: baseUrl) else { return path }
        let baseDir = base.deletingLastPathComponent()
        return baseDir.appendingPathComponent(path).absoluteString
    }

    // MARK: - Private Helpers

    /// 从#EXT-X-STREAM-INF行中提取带宽
    private func extractBandwidth(from line: String) -> Int? {
        guard let match = line.range(of: "BANDWIDTH=(\\d+)", options: .regularExpression) else {
            return nil
        }
        let bwStr = String(line[match]).replacingOccurrences(of: "BANDWIDTH=", with: "")
        return Int(bwStr)
    }

    /// 从#EXT-X-STREAM-INF行中提取分辨率
    private func extractResolution(from line: String) -> (width: Int, height: Int)? {
        guard let match = line.range(of: "RESOLUTION=(\\d+)x(\\d+)", options: .regularExpression) else {
            return nil
        }
        let resStr = String(line[match]).replacingOccurrences(of: "RESOLUTION=", with: "")
        let parts = resStr.split(separator: "x")

        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else {
            return nil
        }

        return (width: width, height: height)
    }
    
    /// 从 I-FRAME 行中提取 URI
    private func extractURI(from line: String) -> String? {
        guard let match = line.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) else {
            return nil
        }
        let uriStr = String(line[match])
        // 移除 URI=" 和 结尾的 "
        let cleanUri = uriStr.replacingOccurrences(of: "URI=\"", with: "").replacingOccurrences(of: "\"", with: "")
        return cleanUri
    }

    /// 根据策略选择最佳变体
    private func selectBestVariant(
        from variants: [HLSVariant],
        strategy: HLSVariantSelectionStrategy
    ) -> HLSVariant? {
        switch strategy {
        case .preferAspectRatio(let targetWidth, let targetHeight, let maxPixels):
            return selectByAspectRatio(
                from: variants,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                maxPixels: maxPixels
            )

        case .highestQuality(let maxPixels):
            return selectHighestQuality(from: variants, maxPixels: maxPixels)

        case .lowestBandwidth:
            return variants.min { $0.bandwidth < $1.bandwidth }
        }
    }

    /// 选择偏好宽高比的变体
    private func selectByAspectRatio(
        from variants: [HLSVariant],
        targetWidth: Int,
        targetHeight: Int,
        maxPixels: Int?
    ) -> HLSVariant? {
        let targetRatio = Double(targetWidth) / Double(targetHeight)
        let tolerance = 0.1

        // 首先尝试找到匹配目标宽高比的变体
        var bestMatch: HLSVariant?
        var bestMatchPixels = 0

        for variant in variants {
            if abs(variant.aspectRatio - targetRatio) < tolerance {
                // 检查像素限制
                if let maxPixels = maxPixels, variant.pixelCount > maxPixels {
                    continue
                }

                // 选择像素最高的
                if variant.pixelCount > bestMatchPixels {
                    bestMatchPixels = variant.pixelCount
                    bestMatch = variant
                }
            }
        }

        if let match = bestMatch {
            #if DEBUG
            print(" HLSParser: 选择 \(match.width)x\(match.height) 变体（目标宽高比 \(targetWidth):\(targetHeight)）")
            #endif
            return match
        }

        // 如果没找到匹配的，尝试1:1正方形作为备选
        let squareRatio = 1.0
        var bestSquare: HLSVariant?
        var bestSquarePixels = 0

        for variant in variants {
            if abs(variant.aspectRatio - squareRatio) < tolerance {
                if let maxPixels = maxPixels, variant.pixelCount > maxPixels {
                    continue
                }

                if variant.pixelCount > bestSquarePixels {
                    bestSquarePixels = variant.pixelCount
                    bestSquare = variant
                }
            }
        }

        if let square = bestSquare {
            #if DEBUG
            print(" HLSParser: 选择 \(square.width)x\(square.height) 正方形变体（无目标宽高比可用）")
            #endif
            return square
        }

        // 如果都没找到，返回第一个变体
        #if DEBUG
        if let first = variants.first {
            print(" HLSParser: 选择第一个变体 \(first.width)x\(first.height)（无匹配宽高比）")
        }
        #endif
        return variants.first
    }

    /// 选择最高质量的变体
    private func selectHighestQuality(
        from variants: [HLSVariant],
        maxPixels: Int?
    ) -> HLSVariant? {
        var filteredVariants = variants

        // 应用像素限制
        if let maxPixels = maxPixels {
            filteredVariants = variants.filter { $0.pixelCount <= maxPixels }
        }

        // 如果过滤后没有变体，使用原始列表
        if filteredVariants.isEmpty {
            filteredVariants = variants
        }

        // 选择像素最高的，如果像素相同则选择带宽最高的
        let best = filteredVariants.max { a, b in
            if a.pixelCount != b.pixelCount {
                return a.pixelCount < b.pixelCount
            }
            return a.bandwidth < b.bandwidth
        }

        #if DEBUG
        if let best = best {
            print(" HLSParser: 选择最高质量变体 \(best.width)x\(best.height) @ \(best.bandwidth/1000000)Mbps")
        }
        #endif

        return best
    }
}
