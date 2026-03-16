import AppKit
import OOTContent
import OOTCore
import OOTDataModel
import SwiftUI

struct GameplayHUDView: View {
    let runtime: GameRuntime

    @State
    private var displayedRupees: Int

    @State
    private var previousHealthUnits: Int

    @State
    private var heartDamageFlash = false

    @State
    private var art = GameplayHUDArtLibrary.empty

    @State
    private var heartFlashTask: Task<Void, Never>?

    init(runtime: GameRuntime) {
        self.runtime = runtime
        _displayedRupees = State(initialValue: runtime.hudState.rupees)
        _previousHealthUnits = State(initialValue: runtime.hudState.currentHealthUnits)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    HeartMeterView(
                        states: heartStates,
                        art: art,
                        shouldFlash: heartDamageFlash
                    )
                    MagicMeterView(
                        currentMagic: runtime.hudState.currentMagic,
                        maximumMagic: runtime.hudState.maximumMagic,
                        art: art
                    )
                    HUDCounterStrip(
                        rupees: displayedRupees,
                        smallKeyCount: runtime.hudState.smallKeyCount,
                        art: art
                    )
                }
                .padding(.top, 22)
                .padding(.leading, 22)

                VStack {
                    Spacer()

                    HStack(alignment: .bottom) {
                        BButtonView(
                            item: runtime.hudState.bButtonItem,
                            art: art
                        )

                        Spacer()

                        VStack(alignment: .trailing, spacing: 14) {
                            SceneMinimapView(runtime: runtime)
                                .frame(width: min(geometry.size.width * 0.24, 168))
                                .frame(height: min(geometry.size.width * 0.24, 168))

                            AButtonView(label: runtime.gameplayHUDActionLabel)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .allowsHitTesting(false)
        .opacity(hudOpacity)
        .animation(.easeInOut(duration: 0.2), value: hudOpacity)
        .task {
            art = GameplayHUDArtLibrary.load(contentLoader: runtime.contentLoader)
        }
        .onDisappear {
            heartFlashTask?.cancel()
            heartFlashTask = nil
        }
        .onChange(of: runtime.hudState.rupees, initial: false) { _, newValue in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                displayedRupees = newValue
            }
        }
        .onChange(of: runtime.hudState.currentHealthUnits, initial: false) { _, newValue in
            if newValue < previousHealthUnits {
                triggerHeartDamageFlash()
            }
            previousHealthUnits = newValue
        }
    }
}

private extension GameplayHUDView {
    var heartStates: [HUDHeartState] {
        let maximumContainers = min(20, max(1, (runtime.hudState.maximumHealthUnits + 1) / 2))
        return (0..<maximumContainers).map { index in
            let remainingUnits = runtime.hudState.currentHealthUnits - (index * 2)
            if remainingUnits >= 2 {
                return .full
            }
            if remainingUnits == 1 {
                return .half
            }
            return .empty
        }
    }

    var hudOpacity: Double {
        if runtime.activeMessagePresentation != nil {
            return 0.38
        }
        if runtime.playState?.transitionEffect != nil {
            return 0.5
        }
        return 1
    }

    func triggerHeartDamageFlash() {
        heartFlashTask?.cancel()
        heartFlashTask = Task {
            for _ in 0..<3 {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        heartDamageFlash = true
                    }
                }
                try? await Task.sleep(for: .milliseconds(120))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        heartDamageFlash = false
                    }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }
}

private enum HUDHeartState {
    case full
    case half
    case empty
}

private struct HeartMeterView: View {
    let states: [HUDHeartState]
    let art: GameplayHUDArtLibrary
    let shouldFlash: Bool

    var body: some View {
        let rows = stride(from: 0, to: states.count, by: 10).map {
            Array(states[$0..<min($0 + 10, states.count)])
        }

        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, state in
                        HeartGlyphView(
                            state: state,
                            image: art.heart,
                            shouldFlash: shouldFlash
                        )
                    }
                }
            }
        }
    }
}

private struct HeartGlyphView: View {
    let state: HUDHeartState
    let image: NSImage?
    let shouldFlash: Bool

    var body: some View {
        ZStack {
            heartShape(color: .black.opacity(0.6))

            switch state {
            case .full:
                heartShape(color: shouldFlash ? Color(red: 1.0, green: 0.88, blue: 0.42) : Color(red: 0.95, green: 0.15, blue: 0.18))
            case .half:
                heartShape(color: Color(red: 0.38, green: 0.08, blue: 0.12))
                heartShape(color: shouldFlash ? Color(red: 1.0, green: 0.88, blue: 0.42) : Color(red: 0.95, green: 0.15, blue: 0.18))
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: 9)
                    }
            case .empty:
                heartShape(color: Color(red: 0.28, green: 0.06, blue: 0.08))
            }
        }
        .frame(width: 18, height: 18)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }

    @ViewBuilder
    private func heartShape(color: Color) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .renderingMode(.template)
                .foregroundStyle(color)
        } else {
            Image(systemName: "heart.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
        }
    }
}

private struct MagicMeterView: View {
    let currentMagic: Int
    let maximumMagic: Int
    let art: GameplayHUDArtLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let magic = art.magic {
                    Image(nsImage: magic)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 16, height: 16)
                }
                Text("Magic")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.6))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.24, green: 0.95, blue: 0.38), Color(red: 0.04, green: 0.53, blue: 0.18)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 128 * magicFraction)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .frame(width: 128, height: 12)
        }
    }

    private var magicFraction: CGFloat {
        guard maximumMagic > 0 else {
            return 0
        }
        return CGFloat(currentMagic) / CGFloat(maximumMagic)
    }
}

private struct HUDCounterStrip: View {
    let rupees: Int
    let smallKeyCount: Int?
    let art: GameplayHUDArtLibrary

    var body: some View {
        HStack(spacing: 14) {
            CounterChip(
                title: "Rupees",
                value: String(format: "%03d", rupees),
                tint: Color(red: 0.3, green: 0.93, blue: 0.44),
                icon: art.rupee
            )

            if let smallKeyCount {
                CounterChip(
                    title: "Keys",
                    value: "\(smallKeyCount)",
                    tint: Color(red: 0.88, green: 0.89, blue: 0.94),
                    icon: nil
                )
            }
        }
    }
}

private struct CounterChip: View {
    let title: String
    let value: String
    let tint: Color
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: title == "Keys" ? "key.fill" : "diamond.fill")
                    .font(.system(size: 11, weight: .bold))
            }

            Text(value)
                .contentTransition(.numericText())
                .font(.system(size: 14, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct BButtonView: View {
    let item: GameplayHUDButtonItem
    let art: GameplayHUDArtLibrary

    var body: some View {
        HUDButtonOrb(
            letter: "B",
            label: item.actionLabel,
            fill: Color(red: 0.86, green: 0.28, blue: 0.12),
            icon: art.image(for: item),
            fallbackSymbol: fallbackSymbol
        )
    }

    private var fallbackSymbol: String {
        switch item {
        case .sword:
            return "figure.fencing"
        case .shield:
            return "shield.fill"
        case .slingshot:
            return "scope"
        case .bow:
            return "arrow.up.forward"
        case .bomb:
            return "circle.hexagongrid.fill"
        case .boomerang:
            return "arrow.triangle.2.circlepath"
        case .ocarina:
            return "music.note"
        case .none:
            return "circle.fill"
        }
    }
}

private struct AButtonView: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.45), in: Capsule(style: .continuous))

            HUDButtonOrb(
                letter: "A",
                label: nil,
                fill: Color(red: 0.2, green: 0.72, blue: 0.3),
                icon: nil,
                fallbackSymbol: nil
            )
        }
    }
}

private struct HUDButtonOrb: View {
    let letter: String
    let label: String?
    let fill: Color
    let icon: NSImage?
    let fallbackSymbol: String?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [fill.opacity(0.94), fill.opacity(0.74), fill.opacity(0.38)],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 34
                        )
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.28), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 3)

                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 26, height: 26)
                } else if let fallbackSymbol {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                } else {
                    Text(letter)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 58, height: 58)

            if let label {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

private struct SceneMinimapView: View {
    let runtime: GameRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sceneTitle)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.7), Color(red: 0.07, green: 0.15, blue: 0.12).opacity(0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        .padding(10)

                    Path { path in
                        let insetBounds = geometry.frame(in: .local).insetBy(dx: 16, dy: 16)
                        let midX = insetBounds.midX
                        let midY = insetBounds.midY
                        path.move(to: CGPoint(x: insetBounds.minX, y: midY))
                        path.addLine(to: CGPoint(x: insetBounds.maxX, y: midY))
                        path.move(to: CGPoint(x: midX, y: insetBounds.minY))
                        path.addLine(to: CGPoint(x: midX, y: insetBounds.maxY))
                    }
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                    if let playerPoint = normalizedPlayerPoint {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.26, blue: 0.16))
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                            }
                            .position(
                                x: 16 + (playerPoint.x * (geometry.size.width - 32)),
                                y: 16 + (playerPoint.y * (geometry.size.height - 32))
                            )
                            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    }
                }
            }
        }
        .padding(12)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private extension SceneMinimapView {
    var sceneTitle: String {
        runtime.loadedScene?.manifest.title ?? runtime.loadedScene?.manifest.name ?? "Area Map"
    }

    var normalizedPlayerPoint: CGPoint? {
        guard
            let playerState = runtime.playerState,
            let collision = runtime.loadedScene?.collision
        else {
            return nil
        }

        let minX = CGFloat(collision.minimumBounds.x)
        let maxX = CGFloat(collision.maximumBounds.x)
        let minZ = CGFloat(collision.minimumBounds.z)
        let maxZ = CGFloat(collision.maximumBounds.z)
        let width = max(maxX - minX, 1)
        let depth = max(maxZ - minZ, 1)

        let normalizedX = ((CGFloat(playerState.position.x) - minX) / width).clamped(to: 0...1)
        let normalizedY = (1 - ((CGFloat(playerState.position.z) - minZ) / depth)).clamped(to: 0...1)
        return CGPoint(x: normalizedX, y: normalizedY)
    }
}

struct GameplayHUDArtLibrary {
    var heart: NSImage?
    var magic: NSImage?
    var rupee: NSImage?
    var bomb: NSImage?
    var arrow: NSImage?

    static let empty = GameplayHUDArtLibrary()

    func image(for item: GameplayHUDButtonItem) -> NSImage? {
        switch item {
        case .bomb:
            return bomb
        case .bow:
            return arrow
        default:
            return nil
        }
    }

    static func load(contentLoader: any ContentLoading) -> GameplayHUDArtLibrary {
        guard let object = try? contentLoader.loadObject(named: "gameplay_keep") else {
            return .empty
        }

        return GameplayHUDArtLibrary(
            heart: loadTexture(named: "gDropRecoveryHeartTex", from: object),
            magic: loadTexture(named: "gDropMagicSmallTex", from: object),
            rupee: loadTexture(named: "gRupeeGreenTex", from: object),
            bomb: loadTexture(named: "gUnusedBombIconTex", from: object),
            arrow: loadTexture(named: "gUnusedArrowIconTex", from: object)
        )
    }

    private static func loadTexture(
        named name: String,
        from object: LoadedObject
    ) -> NSImage? {
        guard
            let textureURL = object.textureAssetURLs[OOTAssetID.stableID(for: name)],
            let descriptor = object.manifest.textures.first(where: {
                textureName(for: $0.path) == name
            }),
            let cgImage = makeImage(
                binaryURL: textureURL,
                format: descriptor.format,
                width: descriptor.width,
                height: descriptor.height
            )
        else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: descriptor.width, height: descriptor.height))
    }

    private static func textureName(for path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().deletingPathExtension().lastPathComponent
    }

    private static func makeImage(
        binaryURL: URL,
        format: TextureFormat,
        width: Int,
        height: Int
    ) -> CGImage? {
        guard
            let provider = CGDataProvider(data: decodedPixelData(
                binaryURL: binaryURL,
                format: format,
                width: width,
                height: height
            ) as CFData),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func decodedPixelData(
        binaryURL: URL,
        format: TextureFormat,
        width: Int,
        height: Int
    ) -> Data {
        guard let data = try? Data(contentsOf: binaryURL) else {
            return Data()
        }

        switch format {
        case .rgba16, .rgba32:
            return data
        case .i4, .i8:
            return grayscalePixelData(data)
        case .ia4, .ia8, .ia16:
            return intensityAlphaPixelData(data)
        case .ci4, .ci8:
            return Data(repeating: 0, count: width * height * 4)
        }
    }

    private static func grayscalePixelData(_ data: Data) -> Data {
        var output = Data(capacity: data.count * 4)
        for byte in data {
            output.append(byte)
            output.append(byte)
            output.append(byte)
            output.append(255)
        }
        return output
    }

    private static func intensityAlphaPixelData(_ data: Data) -> Data {
        guard data.count.isMultiple(of: 2) else {
            return grayscalePixelData(data)
        }

        var output = Data(capacity: data.count * 2)
        var iterator = data.makeIterator()
        while let intensity = iterator.next(), let alpha = iterator.next() {
            output.append(intensity)
            output.append(intensity)
            output.append(intensity)
            output.append(alpha)
        }
        return output
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
