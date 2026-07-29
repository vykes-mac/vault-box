import Foundation

enum SmartAlbumType: String, CaseIterable, Identifiable {
    case people = "People"
    case documents = "Documents"
    case receipts = "Receipts"
    case idsAndCards = "IDs & Cards"
    case contracts = "Contracts"
    case screenshots = "Screenshots"
    case qrCodes = "QR Codes"
    case animals = "Animals"
    case plants = "Plants"
    case buildings = "Buildings"
    case landmarks = "Landmarks"
    case food = "Food"
    case vehicles = "Vehicles"
    case nature = "Nature"
    case beach = "Beach"
    case sunset = "Sunset"
    case sports = "Sports"
    case night = "Night"
    case water = "Water"
    case celebration = "Celebration"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .people: String(localized: "People")
        case .documents: String(localized: "Documents")
        case .receipts: String(localized: "Receipts")
        case .idsAndCards: String(localized: "IDs & Cards")
        case .contracts: String(localized: "Contracts")
        case .screenshots: String(localized: "Screenshots")
        case .qrCodes: String(localized: "QR Codes")
        case .animals: String(localized: "Animals")
        case .plants: String(localized: "Plants")
        case .buildings: String(localized: "Buildings")
        case .landmarks: String(localized: "Landmarks")
        case .food: String(localized: "Food")
        case .vehicles: String(localized: "Vehicles")
        case .nature: String(localized: "Nature")
        case .beach: String(localized: "Beach")
        case .sunset: String(localized: "Sunset")
        case .sports: String(localized: "Sports")
        case .night: String(localized: "Night")
        case .water: String(localized: "Water")
        case .celebration: String(localized: "Celebration")
        }
    }

    static func localizedDisplayName(forTag tag: String) -> String {
        allCases.first(where: { $0.tag == tag })?.displayName ?? tag.capitalized
    }

    var tag: String {
        switch self {
        case .people: "people"
        case .documents: "document"
        case .receipts: "receipt"
        case .idsAndCards: "idcard"
        case .contracts: "contract"
        case .screenshots: "screenshot"
        case .qrCodes: "qrcode"
        case .animals: "animals"
        case .plants: "plants"
        case .buildings: "buildings"
        case .landmarks: "landmarks"
        case .food: "food"
        case .vehicles: "vehicles"
        case .nature: "nature"
        case .beach: "beach"
        case .sunset: "sunset"
        case .sports: "sports"
        case .night: "night"
        case .water: "water"
        case .celebration: "celebration"
        }
    }

    var systemImage: String {
        switch self {
        case .people: "person.2.fill"
        case .documents: "doc.text.fill"
        case .receipts: "receipt.fill"
        case .idsAndCards: "person.text.rectangle.fill"
        case .contracts: "doc.text.magnifyingglass"
        case .screenshots: "rectangle.dashed"
        case .qrCodes: "qrcode"
        case .animals: "pawprint.fill"
        case .plants: "leaf.fill"
        case .buildings: "building.2.fill"
        case .landmarks: "building.columns.fill"
        case .food: "fork.knife"
        case .vehicles: "car.fill"
        case .nature: "mountain.2.fill"
        case .beach: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .sports: "figure.run"
        case .night: "moon.stars.fill"
        case .water: "drop.fill"
        case .celebration: "sparkles"
        }
    }
}
