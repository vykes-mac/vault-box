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
