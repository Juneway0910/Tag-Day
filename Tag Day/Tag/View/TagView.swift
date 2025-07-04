//
//  TagView.swift
//  Tag Day
//
//  Created by Ci Zi on 2025/6/16.
//

import UIKit

class TagView: UIView {
    var tagLayer = TagLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.addSublayer(tagLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if !tagLayer.frame.equalTo(bounds) {
            tagLayer.frame = bounds
        }
    }
    
    func update(tag: Tag, count: Int = 1) {
        let isDark: Bool
        switch overrideUserInterfaceStyle {
        case .unspecified:
            isDark = traitCollection.userInterfaceStyle == .dark
        case .light:
            isDark = false
        case .dark:
            isDark = true
        @unknown default:
            fatalError()
        }
        tagLayer.update(title: tag.title, count: count, tagColor: tag.getColorString(isDark: isDark), textColor: tag.getTitleColorString(isDark: isDark), isDark: isDark)
    }
}

class TagLayer: CALayer {
    // MARK: - Properties
    struct DisplayInfo: Equatable, Hashable {
        var title: String
        var count: Int
        var tagColor: String
        var textColor: String
        var boundWidth: CGFloat
        var isDark: Bool
    }
    
    private(set) var displayInfo: DisplayInfo? {
        didSet {
            if oldValue != displayInfo {
                setNeedsDisplay()
            } else {
                print("no changes")
            }
        }
    }
    
    private struct SharedCache {
        struct RenderInfo: Hashable {
            var line: CTLine
            var point: CGPoint
        }
        
        enum CacheKey: Hashable {
            case title(DisplayInfo)
            case count(DisplayInfo)
        }
        
        static var renderInfos: [CacheKey: RenderInfo] = [:]
        static let cacheQueue = DispatchQueue(label: "com.zizicic.tag.TagLayer.cache", qos: .userInteractive, attributes: .concurrent)
    }
    
    private let defaultLabelInset: CGFloat = 2.0
    private let countLabelWidth: CGFloat = 14.0
    private let textFontSize: CGFloat = 12.0
    private let countFontSize: CGFloat = 10.0
    private let minimumScaleFactor: CGFloat = 0.5
    private var tagColor: UIColor = AppColor.paper
    private var textColor: UIColor = AppColor.text
    
    // MARK: - Initialization
    override init() {
        super.init()
        setup()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        masksToBounds = true
        cornerRadius = 3.0
        contentsScale = UIScreen.main.scale
        backgroundColor = UIColor.clear.cgColor
        needsDisplayOnBoundsChange = true
        drawsAsynchronously = true
    }
    
    // MARK: - Update Content
    func update(title: String, count: Int = 1, tagColor: String, textColor: String, isDark: Bool) {
        displayInfo = DisplayInfo(title: title, count: count, tagColor: tagColor, textColor: textColor, boundWidth: bounds.width, isDark: isDark)
    }
    
    // MARK: - Drawing
    override func draw(in ctx: CGContext) {
        super.draw(in: ctx)
        
        displayInfo?.boundWidth = bounds.width
        guard let displayInfo = displayInfo else { return }
        guard let tagColor = UIColor(hex: displayInfo.tagColor) else { return }
        guard let textColor = UIColor(hex: displayInfo.textColor) else { return }
        self.tagColor = tagColor
        self.textColor = textColor
        
        // 绘制背景
        ctx.setFillColor(tagColor.cgColor)
        ctx.fill(bounds)
        
        // 保存上下文状态
        ctx.saveGState()
        defer { ctx.restoreGState() }
        
        // 翻转坐标系
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1.0, y: -1.0)
        
        let count = displayInfo.count
        let titleKey = SharedCache.CacheKey.title(displayInfo)
        
        if let titleRenderInfo = SharedCache.cacheQueue.sync(execute: {
            SharedCache.renderInfos[titleKey]
        }) {
            render(for: titleRenderInfo, context: ctx)
        } else {
            // 绘制主文本
            if let attributedString = getAttributedString() {
                let textRect = count > 1 ?
                    CGRect(x: defaultLabelInset, y: 0,
                          width: bounds.width - countLabelWidth - defaultLabelInset,
                          height: bounds.height) :
                    CGRect(x: defaultLabelInset, y: 0,
                          width: bounds.width - 2 * defaultLabelInset,
                          height: bounds.height)
                
                let (resultLine, resultPoint) = drawScaledText(attributedString: attributedString, in: textRect, context: ctx)
                SharedCache.cacheQueue.async(flags: .barrier) {
                    let newRenderInfo = SharedCache.RenderInfo(line: resultLine, point: resultPoint)
                    SharedCache.renderInfos[titleKey] = newRenderInfo
                }
            }
        }
        
        if count > 1 {
            let countKey = SharedCache.CacheKey.count(displayInfo)
            if let countRenderInfo = SharedCache.cacheQueue.sync(execute: {
                SharedCache.renderInfos[countKey]
            }) {
                render(for: countRenderInfo, context: ctx)
            } else {
                // 绘制计数文本
                if let countString = getCountAttributedString() {
                    let countRect = CGRect(x: bounds.width - countLabelWidth, y: 8,
                                          width: countLabelWidth, height: 12)
                    let (resultLine, resultPoint) = drawScaledText(attributedString: countString, in: countRect, context: ctx)
                    SharedCache.cacheQueue.async(flags: .barrier) {
                        let newRenderInfo = SharedCache.RenderInfo(line: resultLine, point: resultPoint)
                        SharedCache.renderInfos[countKey] = newRenderInfo
                    }
                }
            }
        }
    }
    
    private func render(for renderInfo: SharedCache.RenderInfo, context: CGContext) {
        let line = renderInfo.line
        context.textPosition = renderInfo.point
        CTLineDraw(line, context)
    }
    
    private func drawScaledText(attributedString: NSAttributedString, in rect: CGRect, context: CGContext) -> (CTLine, CGPoint) {
        // 获取原始字体
        let originalFont = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 12)
        let originalFontSize = originalFont.pointSize
        
        // 计算文本所需宽度
        let line = CTLineCreateWithAttributedString(attributedString)
        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        
        // 计算需要的缩放比例
        let availableWidth = rect.width
        let requiredScale = min(1.0, availableWidth / CGFloat(lineWidth))
        let scaleFactor = max(requiredScale, minimumScaleFactor)
        let scaledFontSize = originalFontSize * scaleFactor
        
        // 如果不需要缩放，直接绘制
        guard scaleFactor < 1.0 else {
            return drawSingleLineCentered(attributedString: attributedString, in: rect, context: context)
        }
        
        // 创建缩放后的属性字符串
        let scaledFont = originalFont.withSize(scaledFontSize)
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        mutableString.addAttribute(.font, value: scaledFont, range: NSRange(location: 0, length: mutableString.length))
        
        // 绘制缩放后的文本
        return drawSingleLineCentered(attributedString: mutableString, in: rect, context: context)
    }
    
    private func drawSingleLineCentered(attributedString: NSAttributedString, in rect: CGRect, context: CGContext) -> (CTLine, CGPoint) {
        let line = CTLineCreateWithAttributedString(attributedString)
        
        // 计算文本宽度
        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        
        // 获取字体metrics
        let font = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 12)
        let lineHeight = font.lineHeight
        let descender = font.descender
        
        // 计算绘制原点
        let textX = rect.minX + max(0, (rect.width - CGFloat(lineWidth)) / 2)
        let textY = rect.minY + (rect.height - lineHeight) / 2 - descender
        
        // 设置绘制位置
        context.textPosition = CGPoint(x: textX, y: textY)
        
        // 绘制文本
        CTLineDraw(line, context)
        
        return (line, CGPoint(x: textX, y: textY))
    }
    
    // MARK: - Text Attributes
    private func getAttributedString() -> NSAttributedString? {
        guard let displayInfo = displayInfo else { return nil }
        let font = UIFont.systemFont(ofSize: textFontSize, weight: .medium)
        let text = displayInfo.title
        guard text.count > 0 else { return nil }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor.cgColor
        ]
        
        let string = NSAttributedString(string: text, attributes: attributes)
        
        return string
    }
    
    private func getCountAttributedString() -> NSAttributedString? {
        guard let displayInfo = displayInfo else { return nil }
        let font = UIFont.systemFont(ofSize: countFontSize, weight: .semibold)
        let countText = "×\(displayInfo.count)"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor.cgColor
        ]
        
        let string = NSAttributedString(string: countText, attributes: attributes)
        
        return string
    }
}
