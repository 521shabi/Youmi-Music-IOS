import SwiftUI

// MARK: - 评论视图
struct CommentView: View {
    let trackId: Int
    let trackName: String
    
    @Environment(\.dismiss) var dismiss
    @State private var hotComments: [Comment] = []
    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var offset = 0
    @State private var hasMore = true
    @State private var totalCount = 0
    
    private let musicService = MusicService.shared
    private let pageSize = 20
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if hotComments.isEmpty && comments.isEmpty {
                    emptyView
                } else {
                    commentList
                }
            }
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("评论")
                            .font(.system(size: 16, weight: .semibold))
                        if totalCount > 0 {
                            Text("\(totalCount)条")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            await loadComments()
        }
    }
    
    // MARK: - 加载中视图
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("加载评论中...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 空视图
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.gray, .gray.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                )
            
            Text("暂无评论")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("快来抢沙发吧")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - 评论列表
    private var commentList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // 歌曲信息
                HStack {
                    Text(trackName)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // 热门评论
                if !hotComments.isEmpty {
                    commentSection(title: "热门评论", comments: hotComments, showDivider: !comments.isEmpty)
                }
                
                // 最新评论
                if !comments.isEmpty {
                    commentSection(title: "最新评论", comments: comments, showDivider: false)
                }
                
                // 加载更多
                if hasMore {
                    loadMoreButton
                }
                
                Spacer(minLength: 80)
            }
        }
        .refreshable {
            offset = 0
            await loadComments()
        }
    }
    
    // MARK: - 评论区域
    private func commentSection(title: String, comments: [Comment], showDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                if title == "热门评论" {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemGroupedBackground))
            
            // 评论列表
            ForEach(comments) { comment in
                CommentRow(comment: comment)
                
                if comment.id != comments.last?.id {
                    Divider()
                        .padding(.leading, 62)
                }
            }
            
            if showDivider {
                Rectangle()
                    .fill(Color(.systemGroupedBackground))
                    .frame(height: 8)
            }
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - 加载更多按钮
    private var loadMoreButton: some View {
        Button(action: {
            Task {
                await loadMoreComments()
            }
        }) {
            HStack {
                if isLoadingMore {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("加载更多评论")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .disabled(isLoadingMore)
    }
    
    // MARK: - 加载评论
    private func loadComments() async {
        isLoading = true
        
        do {
            let response = try await musicService.getComments(id: trackId, limit: pageSize, offset: 0)
            await MainActor.run {
                hotComments = response.hotComments ?? []
                comments = response.comments ?? []
                totalCount = response.total ?? 0
                hasMore = response.more ?? false
                offset = pageSize
                isLoading = false
            }
        } catch {
            print("Load comments error: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    // MARK: - 加载更多
    private func loadMoreComments() async {
        guard !isLoadingMore, hasMore else { return }
        
        isLoadingMore = true
        
        do {
            let response = try await musicService.getComments(id: trackId, limit: pageSize, offset: offset)
            await MainActor.run {
                comments.append(contentsOf: response.comments ?? [])
                hasMore = response.more ?? false
                offset += pageSize
                isLoadingMore = false
            }
        } catch {
            print("Load more comments error: \(error)")
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
}

// MARK: - 评论行
struct CommentRow: View {
    let comment: Comment
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 头像
            CachedAsyncImage(url: URL(string: comment.user.avatarUrl ?? ""), targetSize: CGSize(width: 38, height: 38)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    )
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 8) {
                // 用户信息
                HStack {
                    Text(comment.user.nickname)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // 点赞
                    HStack(spacing: 4) {
                        Image(systemName: "heart")
                            .font(.system(size: 12))
                        if !comment.likedCountText.isEmpty {
                            Text(comment.likedCountText)
                                .font(.system(size: 11))
                        }
                    }
                    .foregroundColor(.secondary)
                }
                
                // 评论内容
                Text(comment.content)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                
                // 被回复的评论
                if let replies = comment.beReplied, let firstReply = replies.first {
                    HStack(alignment: .top, spacing: 0) {
                        Text("@\(firstReply.user.nickname): ")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                        Text(firstReply.content)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                
                // 时间和位置
                HStack(spacing: 8) {
                    Text(comment.timeText)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    
                    if let location = comment.ipLocation?.location {
                        Text(location)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    CommentView(trackId: 1901371647, trackName: "测试歌曲")
}
