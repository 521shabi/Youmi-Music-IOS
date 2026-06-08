//
//  LyricWidgetBundle.swift
//  LyricWidget
//
//  Created by 世界选择难题 on 2026/1/26.
//

import WidgetKit
import SwiftUI

@main
struct LyricWidgetBundle: WidgetBundle {
    var body: some Widget {
        // 灵动岛歌词 Live Activity
        LyricLiveActivityWidget()

        // 主屏幕歌词小组件
        LyricHomeWidget()
    }
}
