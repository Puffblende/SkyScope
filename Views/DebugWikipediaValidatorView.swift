import SwiftUI

struct DebugWikipediaValidatorView: View {
    @State private var testResults: [ValidationResult] = []
    @State private var isRunning = false
    @State private var progress = 0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Text("Progress: \(progress)/\(AircraftWikipediaMapper.allTypeCodesForDebug.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()

                if testResults.isEmpty && !isRunning {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Run validation to test all Wikipedia articles")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    List(testResults) { result in
                        HStack(spacing: 8) {
                            Image(systemName: result.statusIcon)
                                .foregroundStyle(result.statusColor)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.typecode)
                                    .font(.subheadline.bold())
                                Text(result.article)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .lineLimit(1)
                    }
                    .listStyle(.plain)
                }

                Button(action: runValidation) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text(isRunning ? "Running..." : "Start Validation")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .disabled(isRunning)
                .padding()
            }
            .navigationTitle("Wikipedia Validator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: clearResults) {
                        Image(systemName: "trash")
                    }
                    .disabled(testResults.isEmpty || isRunning)
                }
            }
        }
    }

    private func runValidation() {
        isRunning = true
        progress = 0
        testResults = []

        Task {
            for (index, typecode) in AircraftWikipediaMapper.allTypeCodesForDebug.enumerated() {
                let article = AircraftWikipediaMapper.articleTitle(for: typecode)
                let name = AircraftWikipediaMapper.displayName(for: typecode)
                let hasImage = await checkWikipediaArticle(article)

                let result = ValidationResult(
                    typecode: typecode,
                    name: name,
                    article: article,
                    hasImage: hasImage
                )

                await MainActor.run {
                    testResults.append(result)
                    progress = index + 1
                    print("[\(result.status)] \(typecode) → \(article) - \(name)")
                }
            }
            isRunning = false
        }
    }

    private func checkWikipediaArticle(_ articleTitle: String) async -> Bool? {
        let urlString = "https://en.wikipedia.org/w/api.php"
        guard var components = URLComponents(string: urlString) else { return nil }

        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "titles", value: articleTitle),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "pithumbsize", value: "600")
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }

            if (200..<300).contains(http.statusCode) {
                let decoder = JSONDecoder()
                let result = try decoder.decode(WikipediaResponse.self, from: data)

                if let query = result.query,
                   let pages = query.pages,
                   let page = pages.values.first {
                    // Check if article exists (has title)
                    if page.title != nil {
                        // Check if it has an image
                        return page.thumbnail?.source != nil
                    }
                }
            }
            return false
        } catch {
            return nil
        }
    }

    private func clearResults() {
        testResults = []
        progress = 0
    }

    struct ValidationResult: Identifiable {
        let id = UUID()
        let typecode: String
        let name: String
        let article: String
        let hasImage: Bool?

        var status: String {
            switch hasImage {
            case .some(true): return "✅"
            case .some(false): return "⚠️"
            case .none: return "❌"
            }
        }

        var statusIcon: String {
            switch hasImage {
            case .some(true): return "checkmark.circle.fill"
            case .some(false): return "exclamationmark.circle.fill"
            case .none: return "xmark.circle.fill"
            }
        }

        var statusColor: Color {
            switch hasImage {
            case .some(true): return .green
            case .some(false): return .orange
            case .none: return .red
            }
        }
    }
}

// MARK: - Extension for Debug Access

extension AircraftWikipediaMapper {
    static var allTypeCodesForDebug: [String] {
        Array(aircraftDatabase.keys).sorted()
    }
}

#Preview {
    DebugWikipediaValidatorView()
}
