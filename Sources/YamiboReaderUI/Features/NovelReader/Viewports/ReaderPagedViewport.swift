import SwiftUI

#if os(iOS)
import UIKit

final class ReaderPagedViewportCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}
#endif
