//
//  StyledTextKitRenderer.swift
//  StyledTextKit
//
//  Created by Ryan Nystrom on 12/13/17.
//  Copyright © 2017 Ryan Nystrom. All rights reserved.
//

import UIKit

public final class StyledTextRenderer {

    internal let layoutManager: NSLayoutManager
    internal let textContainer: NSTextContainer
    
    public let scale: CGFloat
    public let inset: UIEdgeInsets
    public let string: StyledTextString
    public let backgroundColor: UIColor?

    private var map = [UIContentSizeCategory: NSTextStorage]()
    private var lock = os_unfair_lock_s()
    private var contentSizeCategory: UIContentSizeCategory

    internal static let globalSizeCache = LRUCache<StyledTextRenderCacheKey, CGSize>(
        maxSize: 1000, // CGSize cache size always 1, treat as item count
        compaction: .default,
        clearOnWarning: true
    )

    internal static let globalBitmapCache = LRUCache<StyledTextRenderCacheKey, CGImage>(
        maxSize: 1024 * 1024 * 20, // 20mb
        compaction: .default,
        clearOnWarning: true
    )

    internal let sizeCache: LRUCache<StyledTextRenderCacheKey, CGSize>
    internal let bitmapCache: LRUCache<StyledTextRenderCacheKey, CGImage>

    public convenience init(
        string: StyledTextString,
        contentSizeCategory: UIContentSizeCategory,
        inset: UIEdgeInsets = .zero,
        backgroundColor: UIColor? = nil,
        layoutManager: NSLayoutManager = NSLayoutManager(),
        scale: CGFloat = StyledTextScreenScale,
        maximumNumberOfLines: Int = 0
        ) {
        self.init(
            string: string,
            contentSizeCategory: contentSizeCategory,
            inset: inset,
            backgroundColor: backgroundColor,
            layoutManager: layoutManager,
            scale: scale,
            maximumNumberOfLines: maximumNumberOfLines,
            sizeCache: nil,
            bitmapCache: nil
        )
    }

    internal init(
        string: StyledTextString,
        contentSizeCategory: UIContentSizeCategory,
        inset: UIEdgeInsets,
        backgroundColor: UIColor?,
        layoutManager: NSLayoutManager,
        scale: CGFloat,
        maximumNumberOfLines: Int,
        sizeCache: LRUCache<StyledTextRenderCacheKey, CGSize>?,
        bitmapCache: LRUCache<StyledTextRenderCacheKey, CGImage>?
        ) {
        self.string = string
        self.contentSizeCategory = contentSizeCategory
        self.inset = inset
        self.backgroundColor = backgroundColor
        self.scale = scale
        self.sizeCache = sizeCache ?? StyledTextRenderer.globalSizeCache
        self.bitmapCache = bitmapCache ?? StyledTextRenderer.globalBitmapCache

        textContainer = NSTextContainer()
        textContainer.exclusionPaths = []
        textContainer.maximumNumberOfLines = maximumNumberOfLines
        textContainer.lineFragmentPadding = 0

        self.layoutManager = layoutManager
        layoutManager.allowsNonContiguousLayout = false
        layoutManager.hyphenationFactor = 0
        layoutManager.showsInvisibleCharacters = false
        layoutManager.showsControlCharacters = false
        layoutManager.usesFontLeading = true
        layoutManager.addTextContainer(textContainer)
    }

    internal var storage: NSTextStorage {
        if let storage = map[contentSizeCategory] {
            return storage
        }
        let storage = NSTextStorage(attributedString: string.render(contentSizeCategory: contentSizeCategory))
        storage.addLayoutManager(layoutManager)
        map[contentSizeCategory] = storage
        return storage
    }

    // not thread safe
    private func _size(_ key: StyledTextRenderCacheKey) -> CGSize {
        if let cached = sizeCache[key] {
            // always update the container to requested size
            textContainer.size = cached
            return cached
        }
        let insetWidth = max(key.width - inset.left - inset.right, 0)
        let size = layoutManager.size(textContainer: textContainer, width: insetWidth, scale: scale)
        sizeCache[key] = size
        return size
    }

    public func size(in width: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _size(StyledTextRenderCacheKey(width: width, attributedText: storage, backgroundColor: backgroundColor, maximumNumberOfLines: textContainer.maximumNumberOfLines))
    }

    public func viewSize(in width: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        return size(in: width).resized(inset: inset)
    }

    public func cachedRender(for width: CGFloat) -> (image: CGImage?, size: CGSize?) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let key = StyledTextRenderCacheKey(
            width: width,
            attributedText: storage,
            backgroundColor: backgroundColor,
            maximumNumberOfLines: 0
        )
        return (bitmapCache[key], sizeCache[key])
    }

    public func render(for width: CGFloat) -> (image: CGImage?, size: CGSize) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let key = StyledTextRenderCacheKey(width: width, attributedText: storage, backgroundColor: backgroundColor, maximumNumberOfLines: textContainer.maximumNumberOfLines)
        let size = _size(key)
        let cache = bitmapCache
        if let cached = cache[key] {
            return (cached, size)
        }

        let contents = layoutManager.render(
            size: size,
            textContainer: textContainer,
            scale: scale,
            backgroundColor: backgroundColor
        )
        cache[key] = contents
        return (contents, size)
    }

    public func attributes(at point: CGPoint) -> (attributes: NSAttributedStringAttributesType, index: Int)? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        var fractionDistance: CGFloat = 1.0
        let index = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fractionDistance
        )
        if index != NSNotFound,
            fractionDistance < 1.0,
            let attributes = layoutManager.textStorage?.attributes(at: index, effectiveRange: nil) as? NSAttributedStringAttributesType {
            return (attributes, index)
        }
        return nil
    }

    public enum WarmOption {
        case size
        case bitmap
    }

    public func warm(
        _ option: WarmOption = .size,
        width: CGFloat
        ) -> StyledTextRenderer {
        switch option {
        case .size: let _ = size(in: width)
        case .bitmap: let _ = render(for: width)
        }
        return self
    }

    @discardableResult
    public func clearCaches() -> StyledTextRenderer {
        sizeCache.clear()
        bitmapCache.clear()
        return self
    }
}
