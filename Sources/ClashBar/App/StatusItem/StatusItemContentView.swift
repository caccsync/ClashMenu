import AppKit

final class StatusItemContentView: NSView {
    private enum BrandStatusIconTheme: Hashable {
        case light
        case dark
    }

    private let statusItemHorizontalPadding: CGFloat = 1
    private let iconSize: CGFloat = 24
    private let brandIconRenderSize: CGFloat = 24
    private let symbolPointSize: CGFloat = 20

    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleNone
        imageView.contentTintColor = NSColor.labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = true
        return imageView
    }()

    private var currentDisplay: MenuBarDisplay?
    private lazy var brandStatusIconImages: [BrandStatusIconTheme: NSImage] = Self.makeBrandStatusIconImages(
        size: brandIconRenderSize)
    private static let brandIconRenderScales: [CGFloat] = [1, 2, 3]

    var usesBrandIcon: Bool {
        self.brandStatusIconImages.isEmpty == false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        self.addSubview(self.iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.refreshBrandIconForCurrentAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.refreshBrandIconForCurrentAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        CGSize(width: self.requiredWidth, height: NSStatusBar.system.thickness)
    }

    var requiredWidth: CGFloat {
        self.statusItemHorizontalPadding * 2 + self.iconSize
    }

    func apply(display: MenuBarDisplay) {
        let previousSymbolName = self.currentDisplay?.symbolName

        self.currentDisplay = display

        if let brandIcon = self.currentBrandStatusIconImage {
            if self.iconView.image !== brandIcon {
                self.iconView.image = brandIcon
            }
            self.iconView.contentTintColor = nil
        } else {
            let symbolName = display.symbolName
            if self.iconView.image == nil || previousSymbolName != symbolName {
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ClashMenu")
                let config = NSImage.SymbolConfiguration(pointSize: self.symbolPointSize, weight: .semibold)
                self.iconView.image = image?.withSymbolConfiguration(config)
            }
            self.iconView.contentTintColor = NSColor.labelColor
        }

        self.iconView.isHidden = false
        self.needsLayout = true
    }

    override func layout() {
        super.layout()

        let totalHeight = bounds.height
        let centerY = floor(totalHeight / 2)
        let iconOriginX = floor(self.statusItemHorizontalPadding)

        self.iconView.frame = CGRect(
            x: iconOriginX,
            y: floor(centerY - self.iconSize / 2),
            width: self.iconSize,
            height: self.iconSize)
    }

    private var currentBrandStatusIconImage: NSImage? {
        let images = self.brandStatusIconImages
        guard images.isEmpty == false else { return nil }
        let theme = Self.brandStatusIconTheme(for: self.effectiveAppearance)
        return images[theme] ?? images.values.first
    }

    private func refreshBrandIconForCurrentAppearance() {
        guard let image = self.currentBrandStatusIconImage else { return }
        guard self.iconView.image !== image || self.iconView.contentTintColor != nil else { return }
        self.iconView.image = image
        self.iconView.contentTintColor = nil
        self.iconView.needsDisplay = true
        self.needsDisplay = true
    }

    private static func makeBrandStatusIconImages(size: CGFloat) -> [BrandStatusIconTheme: NSImage] {
        guard let source = BrandIcon.image else { return [:] }
        let targetSize = NSSize(width: size, height: size)
        var images: [BrandStatusIconTheme: NSImage] = [:]

        for theme in [BrandStatusIconTheme.light, .dark] {
            let rendered = NSImage(size: targetSize)
            let color = self.brandStatusIconColor(for: theme)

            for scale in Self.brandIconRenderScales {
                guard let representation = self.makeBrandStatusIconRepresentation(
                    source: source,
                    pointSize: targetSize,
                    scale: scale,
                    color: color)
                else {
                    continue
                }
                rendered.addRepresentation(representation)
            }

            guard rendered.representations.isEmpty == false else { continue }
            rendered.isTemplate = false
            images[theme] = rendered
        }

        return images
    }

    private static func makeBrandStatusIconRepresentation(
        source: NSImage,
        pointSize: NSSize,
        scale: CGFloat,
        color: NSColor) -> NSBitmapImageRep?
    {
        let pixelWidth = max(1, Int((pointSize.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((pointSize.height * scale).rounded(.up)))

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        else {
            return nil
        }

        representation.size = pointSize

        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: pointSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil)
        context.cgContext.setBlendMode(.sourceIn)
        context.cgContext.setFillColor((color.usingColorSpace(.deviceRGB) ?? color).cgColor)
        context.cgContext.fill(CGRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    private static func brandStatusIconTheme(for appearance: NSAppearance) -> BrandStatusIconTheme {
        let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        switch match {
        case .some(.darkAqua), .some(.vibrantDark):
            return BrandStatusIconTheme.dark
        default:
            return BrandStatusIconTheme.light
        }
    }

    private static func brandStatusIconColor(for theme: BrandStatusIconTheme) -> NSColor {
        let appearanceName: NSAppearance.Name = switch theme {
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }

        if let appearance = NSAppearance(named: appearanceName) {
            var resolved = NSColor.labelColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? NSColor.labelColor
            }
            return resolved
        }
        return NSColor.labelColor
    }
}
