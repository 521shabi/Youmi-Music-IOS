import SwiftUI

// MARK: - 单个字的变色视图
struct KaraokeWordView: View {
    let word: YrcWord
    let currentTime: Double
    let highlightColor: Color
    let normalColor: Color
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    
    private var progress: Double {
        word.progress(at: currentTime)
    }
    
    var body: some View {
        // 底层：未高亮文字
        Text(word.text)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundColor(normalColor)
            .overlay(alignment: .leading) {
                // 顶层：高亮文字（使用 mask 实现部分显示）
                GeometryReader { geo in
                    Text(word.text)
                        .font(.system(size: fontSize, weight: fontWeight))
                        .foregroundColor(highlightColor)
                        .mask(
                            Rectangle()
                                .frame(width: geo.size.width * progress)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .animation(.linear(duration: 0.08), value: progress)
                        )
                }
            }
    }
}

// MARK: - 一行歌词视图（逐字变色）
struct KaraokeLineView: View {
    let line: YrcLine
    let currentTime: Double
    let isCurrent: Bool
    let showTranslation: Bool
    
    private var highlightColor: Color {
        isCurrent ? .white : .white.opacity(0.5)
    }
    
    private var normalColor: Color {
        isCurrent ? .white.opacity(0.5) : .white.opacity(0.3)
    }
    
    private var fontSize: CGFloat {
        isCurrent ? 26 : 20
    }
    
    private var fontWeight: Font.Weight {
        isCurrent ? .bold : .medium
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 逐字歌词行 - 使用自动换行布局
            FlowLayout(spacing: 0) {
                ForEach(line.words) { word in
                    KaraokeWordView(
                        word: word,
                        currentTime: currentTime,
                        highlightColor: highlightColor,
                        normalColor: normalColor,
                        fontSize: fontSize,
                        fontWeight: fontWeight
                    )
                }
            }
            .shadow(color: isCurrent ? .black.opacity(0.3) : .clear, radius: 8, x: 0, y: 2)
            
            // 翻译
            if showTranslation, let translation = line.translation {
                Text(translation)
                    .font(.system(size: isCurrent ? 16 : 14, weight: .regular))
                    .foregroundColor(isCurrent ? .white.opacity(0.8) : .white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - 自动换行布局（居中对齐）
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews, forPlacement: false)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(bounds.size), subviews: subviews, forPlacement: true)
        
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews, forPlacement: Bool) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        let maxWidth = proposal.width ?? .infinity
        var sizes: [CGSize] = []
        
        // 第一次遍历：计算每个元素大小和每行信息
        for subview in subviews {
            sizes.append(subview.sizeThatFits(.unspecified))
        }
        
        // 计算每行的元素和宽度
        var lines: [(startIndex: Int, endIndex: Int, width: CGFloat, height: CGFloat)] = []
        var currentLineStart = 0
        var currentX: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for (index, size) in sizes.enumerated() {
            if currentX + size.width > maxWidth && currentX > 0 {
                // 保存当前行
                lines.append((currentLineStart, index - 1, currentX - spacing, lineHeight))
                currentLineStart = index
                currentX = 0
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        // 保存最后一行
        if currentLineStart < sizes.count {
            lines.append((currentLineStart, sizes.count - 1, currentX - spacing, lineHeight))
        }
        
        // 第二次遍历：计算居中位置
        var positions: [CGPoint] = Array(repeating: .zero, count: sizes.count)
        var currentY: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for line in lines {
            // 计算居中偏移
            let offsetX = forPlacement ? (maxWidth - line.width) / 2 : 0
            var x = offsetX
            
            for i in line.startIndex...line.endIndex {
                positions[i] = CGPoint(x: x, y: currentY)
                x += sizes[i].width + spacing
            }
            
            totalWidth = max(totalWidth, line.width)
            currentY += line.height + spacing
        }
        
        let totalHeight = currentY - spacing
        return (CGSize(width: forPlacement ? maxWidth : totalWidth, height: max(0, totalHeight)), positions, sizes)
    }
}

// MARK: - 完整歌词滚动视图
struct KaraokeLyricsView: View {
    let lines: [YrcLine]
    let currentTime: Double
    let showTranslation: Bool
    let hasTranslation: Bool
    let onToggleTranslation: () -> Void
    let onSeek: (Double) -> Void
    
    @State private var currentLineIndex: Int = 0
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // 翻译开关
                if hasTranslation {
                    HStack {
                        Spacer()
                        Button(action: onToggleTranslation) {
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.system(size: 12))
                                Text(showTranslation ? "翻译" : "原文")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(showTranslation ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(showTranslation ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                            )
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 60)
                    }
                }
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 24) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            let isCurrent = index == currentLineIndex
                            let distance = abs(index - currentLineIndex)
                            
                            KaraokeLineView(
                                line: line,
                                currentTime: currentTime,
                                isCurrent: isCurrent,
                                showTranslation: showTranslation
                            )
                            .scaleEffect(isCurrent ? 1.03 : 1.0)
                            .blur(radius: distance > 4 ? 1.5 : 0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentLineIndex)
                            .id(index)
                            .onTapGesture {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                onSeek(line.startTime)
                            }
                        }
                    }
                    .padding(.vertical, hasTranslation ? 120 : 180)
                    .padding(.horizontal, 24)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.12),
                            .init(color: .white, location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: currentLineIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .onChange(of: currentTime) { _, newTime in
            updateCurrentLineIndex(time: newTime)
        }
        .onAppear {
            updateCurrentLineIndex(time: currentTime)
        }
    }
    
    private func updateCurrentLineIndex(time: Double) {
        for (index, line) in lines.enumerated().reversed() {
            if time >= line.startTime {
                if currentLineIndex != index {
                    currentLineIndex = index
                }
                break
            }
        }
    }
}

// MARK: - 当前歌词预览（底部显示，逐字变色版）
struct KaraokePreviewView: View {
    let line: YrcLine?
    let currentTime: Double
    
    var body: some View {
        if let line = line {
            HStack(spacing: 0) {
                ForEach(line.words) { word in
                    KaraokeWordView(
                        word: word,
                        currentTime: currentTime,
                        highlightColor: .white,
                        normalColor: .white.opacity(0.5),
                        fontSize: 15,
                        fontWeight: .regular
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            // 模拟单个字的变色
            KaraokeWordView(
                word: YrcWord(startTime: 0, duration: 1, text: "测"),
                currentTime: 0.5,
                highlightColor: .white,
                normalColor: .gray,
                fontSize: 30,
                fontWeight: .bold
            )
            .frame(height: 40)
        }
    }
}
