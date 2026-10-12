import SwiftUI

/// 접근성 글자 크기에서는 고정 높이 대신 최소 높이만 적용해 글자가 잘리지 않게 한다.
struct DetailRowHeight: ViewModifier {
    var height: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.frame(maxWidth: .infinity, minHeight: height, alignment: .center)
        } else {
            content.frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .center)
        }
    }
}

extension View {
    func detailListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}
