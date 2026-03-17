import Foundation
import SwiftUI
import OOTCore
import OOTDataModel
import OOTRender

struct DirectorCommentarySidebarView: View {
    let runtime: GameRuntime

    @State
    private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controlsSection

            if let activeAnnotation = runtime.activeDirectorCommentaryAnnotation {
                InspectorSection("Active Now") {
                    DirectorCommentaryAnnotationCard(
                        annotation: activeAnnotation,
                        isSelected: runtime.selectedDirectorCommentaryAnnotationID == activeAnnotation.id
                    )
                    .onTapGesture {
                        runtime.selectDirectorCommentaryAnnotation(id: activeAnnotation.id)
                    }
                }
            }

            InspectorSection("Browse") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search annotations", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Text("\(filteredAnnotations.count) annotations")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredAnnotations) { annotation in
                            DirectorCommentaryAnnotationCard(
                                annotation: annotation,
                                isSelected: runtime.selectedDirectorCommentaryAnnotationID == annotation.id
                            )
                            .onTapGesture {
                                runtime.selectDirectorCommentaryAnnotation(id: annotation.id)
                            }
                        }
                    }
                }
            }

            if let selectedAnnotation = runtime.selectedDirectorCommentaryAnnotation {
                InspectorSection("Details") {
                    DirectorCommentaryDetailView(annotation: selectedAnnotation)
                }
            }
        }
    }
}

private extension DirectorCommentarySidebarView {
    var controlsSection: some View {
        InspectorSection("Mode") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Director's Commentary",
                    isOn: Binding(
                        get: { runtime.isDirectorCommentaryEnabled },
                        set: { runtime.setDirectorCommentaryEnabled($0) }
                    )
                )

                Toggle(
                    "Annotation dots",
                    isOn: Binding(
                        get: { runtime.directorCommentaryShowsWorldMarkers },
                        set: { runtime.directorCommentaryShowsWorldMarkers = $0 }
                    )
                )
                .disabled(runtime.isDirectorCommentaryEnabled == false)

                if runtime.isDirectorCommentaryEnabled {
                    Text("Viewport overlays will follow scene, actor, and mechanic triggers as you play.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Commentary stays browseable here even when the in-game overlay is off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var filteredAnnotations: [DirectorCommentaryAnnotation] {
        let normalizedQuery = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase

        guard normalizedQuery.isEmpty == false else {
            return runtime.directorCommentaryAnnotations
        }

        return runtime.directorCommentaryAnnotations.filter { annotation in
            annotationSearchText(for: annotation).localizedLowercase.contains(normalizedQuery)
        }
    }

    func annotationSearchText(for annotation: DirectorCommentaryAnnotation) -> String {
        [
            annotation.title,
            annotation.summary,
            annotation.tags.joined(separator: " "),
            annotation.bodyMarkdown,
        ].joined(separator: "\n")
    }
}

private struct DirectorCommentaryAnnotationCard: View {
    let annotation: DirectorCommentaryAnnotation
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(kindLabel)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(kindColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(kindColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(annotation.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(annotation.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if annotation.tags.isEmpty == false {
                Text(annotation.tags.joined(separator: "  •  "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? kindColor.opacity(0.14) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? kindColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension DirectorCommentaryAnnotationCard {
    var kindLabel: String {
        annotation.kind.rawValue.uppercased()
    }

    var kindColor: Color {
        switch annotation.kind {
        case .scene:
            return Color(red: 0.16, green: 0.52, blue: 0.74)
        case .actor:
            return Color(red: 0.66, green: 0.31, blue: 0.12)
        case .mechanic:
            return Color(red: 0.33, green: 0.54, blue: 0.28)
        }
    }
}

private struct DirectorCommentaryDetailView: View {
    let annotation: DirectorCommentaryAnnotation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(renderedMarkdown)
                .font(.callout)
                .textSelection(.enabled)

            if annotation.sourceLinks.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(annotation.sourceLinks) { sourceLink in
                        if let url = URL(string: sourceLink.url) {
                            Link(sourceLink.title, destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
}

private extension DirectorCommentaryDetailView {
    var renderedMarkdown: AttributedString {
        if let parsed = try? AttributedString(
            markdown: annotation.bodyMarkdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full
            )
        ) {
            return parsed
        }

        return AttributedString(annotation.bodyMarkdown)
    }
}

struct DirectorCommentaryOverlayCard: View {
    let annotation: DirectorCommentaryAnnotation
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Director's Commentary")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(annotation.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button("Open") {
                    onOpenDetails()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
            }

            Text(annotation.summary)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.86))

            Text(markdownPreview)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(5)
        }
        .padding(16)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}

private extension DirectorCommentaryOverlayCard {
    var markdownPreview: String {
        annotation.bodyMarkdown
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DirectorCommentaryWorldMarkerOverlay: View {
    let runtime: GameRuntime
    let sceneBounds: SceneBounds
    let cameraConfiguration: GameplayCameraConfiguration?

    var body: some View {
        GeometryReader { geometry in
            if let cameraConfiguration {
                ZStack {
                    ForEach(projectedMarkers(in: geometry.size, configuration: cameraConfiguration)) { marker in
                        Button {
                            runtime.selectDirectorCommentaryAnnotation(id: marker.annotationID)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                                    .font(.title3)
                                    .foregroundStyle(.yellow)
                                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)

                                Text(marker.title)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .position(x: marker.point.x, y: marker.point.y)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(runtime.isDirectorCommentaryEnabled && runtime.directorCommentaryShowsWorldMarkers)
    }

    private func projectedMarkers(
        in viewportSize: CGSize,
        configuration: GameplayCameraConfiguration
    ) -> [ProjectedDirectorCommentaryMarker] {
        runtime.directorCommentaryVisibleWorldMarkers.compactMap { marker in
            guard let projection = GameplayCameraProjector.project(
                worldPoint: marker.position.simd + SIMD3<Float>(0, 36, 0),
                sceneBounds: sceneBounds,
                configuration: configuration,
                viewportSize: viewportSize
            ) else {
                return nil
            }

            return ProjectedDirectorCommentaryMarker(
                id: marker.id,
                annotationID: marker.annotationID,
                title: marker.title,
                point: CGPoint(
                    x: CGFloat(projection.viewportPoint.x),
                    y: CGFloat(projection.viewportPoint.y)
                )
            )
        }
    }
}

private struct ProjectedDirectorCommentaryMarker: Identifiable {
    let id: String
    let annotationID: String
    let title: String
    let point: CGPoint
}
