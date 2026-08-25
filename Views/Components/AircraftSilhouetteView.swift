import SwiftUI

struct AircraftSilhouetteView: View {
    let aircraftType: String?
    @Environment(\.dismiss) var dismiss
    @State private var imageURL: URL?
    @State private var isLoading = false

    private var category: String {
        guard let type = aircraftType?.uppercased() else { return "Unknown" }
        return AircraftWikipediaMapper.articleTitle(for: type)
    }

    private var displayName: String {
        guard let type = aircraftType?.uppercased() else { return "Unknown" }
        return AircraftWikipediaMapper.displayName(for: type)
    }

    private var noPhotoView: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No photo available")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(height: 250)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(height: 250)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 300)
                            case .failure:
                                noPhotoView
                            @unknown default:
                                noPhotoView
                            }
                        }
                    } else if isLoading {
                        ProgressView()
                            .frame(height: 250)
                    } else {
                        noPhotoView
                    }

                    VStack(spacing: 2) {
                        Text(displayName)
                            .font(.headline)
                        Text("© Wikipedia / CC BY-SA")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Spacer()
            }
            .navigationTitle("Aircraft Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadImage()
            }
        }
    }

    private func loadImage() async {
        guard let type = aircraftType?.uppercased() else { return }

        isLoading = true

        // Try Commons search for specific aircraft that have no Wikipedia image
        if let searchTerm = AircraftWikipediaMapper.commonsSearchTerm(for: type) {
            if let url = await fetchCommonsImage(searchTerm: searchTerm) {
                imageURL = url
                isLoading = false
                return
            }
        }

        // Otherwise try Wikipedia API (English → German fallback)
        let article = AircraftWikipediaMapper.articleTitle(for: type)
        if let url = await fetchWikipediaImage(articleTitle: article) {
            imageURL = url
        }

        isLoading = false
    }

    private func fetchWikipediaImage(articleTitle: String) async -> URL? {
        if let url = await fetchFromWikipedia(articleTitle: articleTitle, language: "en") {
            return url
        }
        return await fetchFromWikipedia(articleTitle: articleTitle, language: "de")
    }

    private func fetchCommonsImage(searchTerm: String) async -> URL? {
        let searchURLString = "https://commons.wikimedia.org/w/api.php"
        guard var searchComponents = URLComponents(string: searchURLString) else { return nil }

        searchComponents.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: searchTerm),
            URLQueryItem(name: "srnamespace", value: "6"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "srlimit", value: "1")
        ]

        guard let searchURL = searchComponents.url else { return nil }

        do {
            let (searchData, searchResponse) = try await URLSession.shared.data(from: searchURL)
            guard let searchHTTP = searchResponse as? HTTPURLResponse, (200..<300).contains(searchHTTP.statusCode) else {
                return nil
            }

            let decoder = JSONDecoder()
            let searchResult = try decoder.decode(CommonsSearchResponse.self, from: searchData)

            guard let firstResult = searchResult.query?.search?.first else { return nil }

            // Extract filename from "File:SomeName.jpg" format
            let filename = firstResult.title.replacingOccurrences(of: "File:", with: "")

            // Get image info to get the actual image URL
            var infoComponents = URLComponents(string: searchURLString)
            infoComponents?.queryItems = [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "titles", value: "File:\(filename)"),
                URLQueryItem(name: "prop", value: "imageinfo"),
                URLQueryItem(name: "iiprop", value: "url"),
                URLQueryItem(name: "format", value: "json")
            ]

            guard let infoURL = infoComponents?.url else { return nil }

            let (infoData, infoResponse) = try await URLSession.shared.data(from: infoURL)
            guard let infoHTTP = infoResponse as? HTTPURLResponse, (200..<300).contains(infoHTTP.statusCode) else {
                return nil
            }

            let infoResult = try decoder.decode(CommonsImageInfoResponse.self, from: infoData)

            if let pages = infoResult.query?.pages,
               let page = pages.values.first,
               let imageinfo = page.imageinfo?.first,
               let imageURL = imageinfo.url {
                return URL(string: imageURL)
            }

            return nil
        } catch {
            return nil
        }
    }

    private func fetchFromWikipedia(articleTitle: String, language: String) async -> URL? {
        let urlString = "https://\(language).wikipedia.org/w/api.php"
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
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(WikipediaResponse.self, from: data)

            if let query = result.query,
               let pages = query.pages,
               let page = pages.values.first,
               let imageInfo = page.thumbnail,
               let imageURLString = imageInfo.source {
                return URL(string: imageURLString)
            }
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - Wikipedia Mapper

enum AircraftWikipediaMapper {
    static let commonsSearchTerms: [String: String] = [
        "BE40": "Beechjet 400",
        "C25A": "Cessna CitationJet CJ1",
        "C25B": "Cessna CitationJet CJ1",
        "FA8X": "Dassault Falcon 8X",
        "SU95": "Sukhoi Superjet 100",
    ]

    static let aircraftDatabase: [String: (name: String, article: String)] = [
        // NARROW BODY
        "B736": ("Boeing 737-600", "Boeing_737_Next_Generation"),
        "B737": ("Boeing 737-700", "Boeing_737_Next_Generation"),
        "B738": ("Boeing 737-800", "Boeing_737_Next_Generation"),
        "B739": ("Boeing 737-900", "Boeing_737_Next_Generation"),
        "B38M": ("Boeing 737 MAX 8", "Boeing_737_MAX"),
        "B39M": ("Boeing 737 MAX 9", "Boeing_737_MAX"),
        "B3XM": ("Boeing 737 MAX 10", "Boeing_737_MAX"),
        "B712": ("Boeing 717", "Boeing_717"),
        "A318": ("Airbus A318", "Airbus_A318"),
        "A319": ("Airbus A319", "Airbus_A319"),
        "A320": ("Airbus A320", "Airbus_A320_family"),
        "A20N": ("Airbus A320", "Airbus_A320_family"),
        "A321": ("Airbus A321", "Airbus_A321"),
        "A21N": ("Airbus A321", "Airbus_A321"),
        "A220": ("Airbus A220-100", "Airbus_A220"),
        "BCS1": ("Airbus A220-100", "Airbus_A220"),
        "BCS3": ("Airbus A220-300", "Airbus_A220"),

        // WIDE BODY
        "B741": ("Boeing 747", "Boeing_747"),
        "B742": ("Boeing 747", "Boeing_747"),
        "B743": ("Boeing 747", "Boeing_747"),
        "B744": ("Boeing 747", "Boeing_747"),
        "B748": ("Boeing 747-8", "Boeing_747-8"),
        "B752": ("Boeing 757", "Boeing_757"),
        "B753": ("Boeing 757", "Boeing_757"),
        "B762": ("Boeing 767", "Boeing_767"),
        "B763": ("Boeing 767", "Boeing_767"),
        "B764": ("Boeing 767", "Boeing_767"),
        "B772": ("Boeing 777", "Boeing_777"),
        "B773": ("Boeing 777", "Boeing_777"),
        "B77L": ("Boeing 777", "Boeing_777"),
        "B77W": ("Boeing 777", "Boeing_777"),
        "B778": ("Boeing 777X", "Boeing_777X"),
        "B779": ("Boeing 777X", "Boeing_777X"),
        "B788": ("Boeing 787-8 Dreamliner", "Boeing_787_Dreamliner"),
        "B789": ("Boeing 787-9 Dreamliner", "Boeing_787_Dreamliner"),
        "B78X": ("Boeing 787-10 Dreamliner", "Boeing_787_Dreamliner"),
        "A332": ("Airbus A330", "Airbus_A330"),
        "A333": ("Airbus A330", "Airbus_A330"),
        "A338": ("Airbus A330neo", "Airbus_A330neo"),
        "A339": ("Airbus A330neo", "Airbus_A330neo"),
        "A342": ("Airbus A340", "Airbus_A340"),
        "A343": ("Airbus A340", "Airbus_A340"),
        "A345": ("Airbus A340", "Airbus_A340"),
        "A346": ("Airbus A340", "Airbus_A340"),
        "A359": ("Airbus A350-900", "Airbus_A350"),
        "A35K": ("Airbus A350-1000", "Airbus_A350"),
        "A388": ("Airbus A380", "Airbus_A380"),
        "MD11": ("McDonnell Douglas MD-11", "McDonnell_Douglas_MD-11"),
        "MD82": ("McDonnell Douglas MD-80", "McDonnell_Douglas_MD-80"),
        "MD83": ("McDonnell Douglas MD-80", "McDonnell_Douglas_MD-80"),
        "DC10": ("McDonnell Douglas DC-10", "McDonnell_Douglas_DC-10"),
        "IL76": ("Ilyushin Il-76", "Ilyushin_Il-76"),
        "A124": ("Antonov An-124", "Antonov_An-124_Ruslan"),

        // REGIONAL JET
        "E170": ("Embraer 170", "Embraer_E-Jet_family"),
        "E175": ("Embraer 175", "Embraer_E-Jet_family"),
        "E75L": ("Embraer 175", "Embraer_E-Jet_family"),
        "E190": ("Embraer 190", "Embraer_E-Jet_family"),
        "E195": ("Embraer 195", "Embraer_E-Jet_family"),
        "E295": ("Embraer 195", "Embraer_E-Jet_family"),
        "CRJ2": ("Bombardier CRJ200", "Bombardier_CRJ100/200"),
        "CRJ7": ("Bombardier CRJ700", "Bombardier_CRJ700_series"),
        "CRJ9": ("Bombardier CRJ900", "Bombardier_CRJ"),
        "B461": ("BAe 146", "British_Aerospace_146"),
        "B462": ("BAe 146", "British_Aerospace_146"),
        "B463": ("BAe 146", "British_Aerospace_146"),
        "RJ85": ("Avro RJ85", "British_Aerospace_146"),
        "RJ1H": ("Avro RJ85", "British_Aerospace_146"),
        "F70": ("Fokker 70", "Fokker_70"),
        "F100": ("Fokker 100", "Fokker_100"),
        "SU95": ("Sukhoi Superjet 100", "Sukhoi_Superjet_100"),
        "AN24": ("Antonov An-24", "Antonov_An-24"),

        // TURBOPROP
        "AT43": ("ATR 42", "ATR_42"),
        "AT45": ("ATR 42", "ATR_42"),
        "AT72": ("ATR 72", "ATR_72"),
        "AT73": ("ATR 72", "ATR_72"),
        "AT75": ("ATR 72", "ATR_72"),
        "AT76": ("ATR 72", "ATR_72"),
        "DH8A": ("Dash 8-100/200", "De_Havilland_Canada_Dash_8"),
        "DH8B": ("Dash 8-100/200", "De_Havilland_Canada_Dash_8"),
        "DH8C": ("Dash 8-300/400", "De_Havilland_Canada_Dash_8"),
        "DH8D": ("Dash 8-300/400", "De_Havilland_Canada_Dash_8"),
        "SB34": ("Saab 340", "Saab_340"),
        "SB20": ("Saab 2000", "Saab_2000"),
        "BE20": ("Beechcraft King Air 200", "Beechcraft_Super_King_Air"),
        "BE9L": ("Beechcraft King Air 90", "Beechcraft_King_Air"),
        "C208": ("Cessna 208 Caravan", "Cessna_208_Caravan"),
        "P180": ("Piaggio Avanti", "Piaggio_P.180_Avanti"),
        "JS41": ("BAe Jetstream 41", "British_Aerospace_Jetstream"),
        "BE19": ("Beechcraft 1900", "Beechcraft_1900"),
        "SW4": ("Swearingen Metroliner", "Fairchild_Swearingen_Metroliner"),

        // BUSINESS JET
        "LJ35": ("Learjet 35", "Learjet_35"),
        "LJ45": ("Learjet 45", "Learjet_45"),
        "LJ60": ("Learjet 60", "Learjet_60"),
        "CL30": ("Bombardier Challenger 300", "Bombardier_Challenger_300"),
        "CL35": ("Bombardier Challenger 350", "Bombardier_Challenger_300"),
        "CL60": ("Bombardier Challenger 600", "Bombardier_Challenger_600_series"),
        "GL5T": ("Bombardier Global Express", "Bombardier_Global_Express"),
        "GLEX": ("Bombardier Global Express", "Bombardier_Global_Express"),
        "G650": ("Gulfstream G650", "Gulfstream_G650/G700/G800"),
        "GLF6": ("Gulfstream G650", "Gulfstream_G650/G700/G800"),
        "GLF5": ("Gulfstream V", "Gulfstream_V"),
        "GLF4": ("Gulfstream IV", "Gulfstream_IV"),
        "E50P": ("Embraer Phenom 100", "Embraer_Phenom_100"),
        "E55P": ("Embraer Phenom 300", "Embraer_Phenom_300"),
        "PC24": ("Pilatus PC-24", "Pilatus_PC-24"),
        "C25A": ("Cessna Citation CJ", "Cessna_CitationJet"),
        "C25B": ("Cessna Citation CJ", "Cessna_CitationJet"),
        "C56X": ("Cessna Citation Excel", "Cessna_Citation_Excel"),
        "C680": ("Cessna Citation Sovereign", "Cessna_Citation_Sovereign"),
        "C750": ("Cessna Citation X", "Cessna_Citation_X"),
        "F2TH": ("Dassault Falcon 2000", "Dassault_Falcon_2000"),
        "FA7X": ("Dassault Falcon 7X", "Dassault_Falcon_7X"),
        "FA8X": ("Dassault Falcon 8X", "Dassault_Falcon_8X"),
        "F900": ("Dassault Falcon 900", "Dassault_Falcon_900"),
        "HA4T": ("Hawker 400", "Hawker_400"),
        "H25B": ("Hawker 750", "Hawker_800"),
        "BE40": ("Beechjet 400", "Beechjet_400"),

        // GENERAL AVIATION
        "C172": ("Cessna 172 Skyhawk", "Cessna_172"),
        "C182": ("Cessna 182 Skylane", "Cessna_182_Skylane"),
        "C152": ("Cessna 152", "Cessna_152"),
        "C210": ("Cessna 210 Centurion", "Cessna_210_Centurion"),
        "C310": ("Cessna 310", "Cessna_310"),
        "C414": ("Cessna 414", "Cessna_414"),
        "PA28": ("Piper Cherokee", "Piper_PA-28_Cherokee"),
        "PA32": ("Piper Cherokee Six", "Piper_PA-32_Cherokee_Six"),
        "PA34": ("Piper Seneca", "Piper_PA-34_Seneca"),
        "PA44": ("Piper Seminole", "Piper_PA-44_Seminole"),
        "PA46": ("Piper Malibu", "Piper_PA-46"),
        "SR20": ("Cirrus SR20", "Cirrus_SR20"),
        "SR22": ("Cirrus SR22", "Cirrus_SR22"),
        "SF50": ("Cirrus Vision Jet", "Cirrus_Vision_SF50"),
        "PC12": ("Pilatus PC-12", "Pilatus_PC-12"),
        "TBM8": ("Daher TBM 900", "SOCATA_TBM"),
        "TBM9": ("Daher TBM 900", "SOCATA_TBM"),
        "DA20": ("Diamond DA20", "Diamond_DA20_Katana"),
        "DA40": ("Diamond DA40", "Diamond_DA40_Diamond_Star"),
        "DA42": ("Diamond DA42", "Diamond_DA42_Twin_Star"),
        "DA62": ("Diamond DA62", "Diamond_DA62"),
        "M20P": ("Mooney M20", "Mooney_M20"),
        "M20T": ("Mooney M20", "Mooney_M20"),
        "BE33": ("Beechcraft Bonanza", "Beechcraft_Bonanza"),
        "BE35": ("Beechcraft Bonanza", "Beechcraft_Bonanza"),
        "BE58": ("Beechcraft Baron", "Beechcraft_Baron"),
        "DR40": ("Robin DR400", "Robin_DR400"),
        "TB20": ("Socata TB20 Trinidad", "SOCATA_TB_family"),
        "TB21": ("Socata TB20 Trinidad", "SOCATA_TB_family"),

        // HELICOPTER
        "EC45": ("Airbus H145", "Eurocopter_EC145"),
        "H145": ("Airbus H145", "Eurocopter_EC145"),
        "EC35": ("Airbus H135", "Eurocopter_EC135"),
        "H135": ("Airbus H135", "Eurocopter_EC135"),
        "EC20": ("Airbus H120", "Eurocopter_EC120_Colibri"),
        "H120": ("Airbus H120", "Eurocopter_EC120_Colibri"),
        "AS32": ("Airbus H125", "Eurocopter_AS350_Écureuil"),
        "H125": ("Airbus H125", "Eurocopter_AS350_Écureuil"),
        "EC55": ("Airbus H155", "Eurocopter_EC155"),
        "H155": ("Airbus H155", "Eurocopter_EC155"),
        "EC75": ("Airbus H175", "Airbus_Helicopters_H175"),
        "H175": ("Airbus H175", "Airbus_Helicopters_H175"),
        "R22": ("Robinson R22", "Robinson_R22"),
        "R44": ("Robinson R44", "Robinson_R44"),
        "R66": ("Robinson R66", "Robinson_R66"),
        "S76": ("Sikorsky S-76", "Sikorsky_S-76"),
        "S92": ("Sikorsky S-92", "Sikorsky_S-92"),
        "B06": ("Bell 206 JetRanger", "Bell_206"),
        "B407": ("Bell 407", "Bell_407"),
        "B429": ("Bell 429", "Bell_429_GlobalRanger"),
        "H47": ("Mil Mi-17", "Mil_Mi-17"),
    ]

    static func articleTitle(for typecode: String) -> String {
        let upper = typecode.uppercased()
        return aircraftDatabase[upper]?.article ?? "Aircraft"
    }

    static func displayName(for typecode: String) -> String {
        let upper = typecode.uppercased()
        return aircraftDatabase[upper]?.name ?? upper
    }

    static func commonsSearchTerm(for typecode: String) -> String? {
        let upper = typecode.uppercased()
        return commonsSearchTerms[upper]
    }
}

// MARK: - Wikipedia API Response Models

struct WikipediaResponse: Decodable {
    let query: WikipediaQuery?

    enum CodingKeys: String, CodingKey {
        case query
    }
}

struct WikipediaQuery: Decodable {
    let pages: [String: WikipediaPage]?

    enum CodingKeys: String, CodingKey {
        case pages
    }
}

struct WikipediaPage: Decodable {
    let title: String?
    let thumbnail: WikipediaImage?

    enum CodingKeys: String, CodingKey {
        case title
        case thumbnail
    }
}

struct WikipediaImage: Decodable {
    let source: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case source
        case width
        case height
    }
}

// MARK: - Wikimedia Commons API Response Models

struct CommonsSearchResponse: Decodable {
    let query: CommonsQuery?
}

struct CommonsQuery: Decodable {
    let search: [CommonsSearchResult]?
}

struct CommonsSearchResult: Decodable {
    let title: String
}

struct CommonsImageInfoResponse: Decodable {
    let query: CommonsImageInfoQuery?
}

struct CommonsImageInfoQuery: Decodable {
    let pages: [String: CommonsImagePage]?
}

struct CommonsImagePage: Decodable {
    let imageinfo: [CommonsImageInfo]?
}

struct CommonsImageInfo: Decodable {
    let url: String?
}

#Preview {
    AircraftSilhouetteView(aircraftType: "A320")
}
