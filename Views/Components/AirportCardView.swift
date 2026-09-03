import SwiftUI

struct AirportCardView: View {
    let icao: String

    @State private var detail: AirportDetail?
    @State private var isLoading = true
    @State private var showWikipedia = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading \(icao)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail {
                    contentView(detail)
                } else {
                    ContentUnavailableView(
                        "Airport Not Found",
                        systemImage: "airplane.departure",
                        description: Text("No data available for \(icao)")
                    )
                }
            }
            .navigationTitle(icao)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            detail = await AirportDetailService.shared.fetch(icao: icao)
            isLoading = false
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(_ detail: AirportDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Full name + ICAO
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.name)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail.icao)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // Photo — inset with rounded corners
                AsyncImage(url: detail.photoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        photoPlaceholder
                    case .empty:
                        if detail.photoURL != nil {
                            ZStack {
                                Color(.secondarySystemBackground)
                                ProgressView()
                            }
                        } else {
                            photoPlaceholder
                        }
                    @unknown default:
                        photoPlaceholder
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

                // METAR — always present; shows "not available" for airports without one
                metarBlock(detail.metar)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                // Wikipedia description (second paragraph of article intro)
                if let desc = detail.wikipediaDescription {
                    Text(desc)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                }

                // Wikipedia link
                if detail.wikipediaURL != nil {
                    Divider()
                        .padding(.horizontal, 20)
                    Button {
                        showWikipedia = true
                    } label: {
                        Label("Read on Wikipedia", systemImage: "globe")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showWikipedia) {
            if let url = detail.wikipediaURL {
                NavigationStack {
                    SafariView(url: url)
                        .navigationTitle(detail.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showWikipedia = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Subviews

    private func metarBlock(_ metar: MetarData?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let metar {
                HStack {
                    if let category = metar.flightCategory {
                        Text(category)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(categoryColor(category), in: Capsule())
                    }
                    Spacer()
                    if let time = metar.reportTime {
                        Text("\(time, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(metar.raw)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No weather data available for this airport.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var photoPlaceholder: some View {
        LinearGradient(
            colors: [.blue.opacity(0.5), .indigo.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "airplane.departure")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Helpers

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "VFR":  return .green
        case "MVFR": return .blue
        case "IFR":  return .red
        case "LIFR": return .purple
        default:     return .gray
        }
    }
}
