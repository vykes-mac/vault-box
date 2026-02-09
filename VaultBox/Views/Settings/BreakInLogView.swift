import SwiftUI
import SwiftData
import MapKit

struct BreakInLogView: View {
    @Query(sort: \BreakInAttempt.timestamp, order: .reverse) private var attempts: [BreakInAttempt]

    var body: some View {
        Group {
            if attempts.isEmpty {
                emptyState
            } else {
                List(attempts) { attempt in
                    NavigationLink {
                        BreakInDetailView(attempt: attempt)
                    } label: {
                        attemptRow(attempt)
                    }
                }
            }
        }
        .navigationTitle("Break-in Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func attemptRow(_ attempt: BreakInAttempt) -> some View {
        HStack(spacing: 12) {
            // Intruder photo
            if let photoData = attempt.intruderPhotoData,
               let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.vaultTextSecondary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(attempt.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("PIN: \(maskedPIN(attempt.attemptedPIN))")
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)

                    if attempt.latitude != nil {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.vaultAccent)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shield.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(Color.vaultTextSecondary)
            Text("No Break-in Attempts")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.vaultTextPrimary)
            Text("If someone tries to access your vault with the wrong PIN, it will be logged here.")
                .font(.body)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func maskedPIN(_ pin: String) -> String {
        guard pin.count > 1 else { return String(repeating: "\u{2022}", count: pin.count) }
        let chars = Array(pin)
        var masked = ""
        for (index, char) in chars.enumerated() {
            // Show every third character, mask the rest
            if index == chars.count - 2 {
                masked.append(char)
            } else {
                masked.append("\u{2022}")
            }
        }
        return masked
    }
}

// MARK: - Detail View

struct BreakInDetailView: View {
    let attempt: BreakInAttempt

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Intruder photo
                if let photoData = attempt.intruderPhotoData,
                   let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                        .fill(Color.vaultSurface)
                        .frame(height: 200)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.largeTitle)
                                Text("No photo captured")
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.vaultTextSecondary)
                        }
                }

                // Info
                VStack(alignment: .leading, spacing: 16) {
                    infoRow("Timestamp", value: attempt.timestamp.formatted(date: .long, time: .standard))
                    infoRow("Attempted PIN", value: maskedPIN(attempt.attemptedPIN))

                    if let lat = attempt.latitude, let lon = attempt.longitude {
                        infoRow("Location", value: String(format: "%.4f, %.4f", lat, lon))

                        // Map
                        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Marker("Break-in Attempt", coordinate: coordinate)
                                .tint(.red)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
                    }
                }
                .padding(.horizontal, Constants.standardPadding)
            }
            .padding(.vertical)
        }
        .navigationTitle("Attempt Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
            Text(value)
                .font(.body)
        }
    }

    private func maskedPIN(_ pin: String) -> String {
        guard pin.count > 1 else { return String(repeating: "\u{2022}", count: pin.count) }
        let chars = Array(pin)
        var masked = ""
        for (index, char) in chars.enumerated() {
            if index == chars.count - 2 {
                masked.append(char)
            } else {
                masked.append("\u{2022}")
            }
        }
        return masked
    }
}
