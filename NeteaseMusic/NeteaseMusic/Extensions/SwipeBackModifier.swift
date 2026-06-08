import SwiftUI
import UIKit

// MARK: - 滑动返回手势修饰器
/// 用于在隐藏导航栏时恢复系统滑动返回手势
struct SwipeBackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(SwipeBackHelper())
    }
}

// MARK: - UIKit 辅助视图
/// 通过 UIKit 恢复系统级滑动返回手势
struct SwipeBackHelper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackViewController {
        SwipeBackViewController()
    }
    
    func updateUIViewController(_ uiViewController: SwipeBackViewController, context: Context) {}
}

class SwipeBackViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // 恢复导航控制器的滑动返回手势
        if let nav = navigationController {
            nav.interactivePopGestureRecognizer?.isEnabled = true
            nav.interactivePopGestureRecognizer?.delegate = self
        }
    }
}

extension SwipeBackViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 只在有多于一个视图控制器时启用
        return navigationController?.viewControllers.count ?? 0 > 1
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 允许与其他手势同时识别
        return true
    }
}

// MARK: - View 扩展
extension View {
    /// 启用滑动返回手势（用于隐藏导航栏的页面）
    func enableSwipeBack() -> some View {
        modifier(SwipeBackModifier())
    }

    /// iOS 16/17 兼容的 onChange，支持新旧两个值
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self.onChange(of: value) { [value] newValue in
                action(value, newValue)
            }
        }
    }
}
