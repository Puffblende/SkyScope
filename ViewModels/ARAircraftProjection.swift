import ARKit
import CoreGraphics
import CoreLocation
import Foundation
import simd
import UIKit

struct ARAircraftScreenProjection: Identifiable {
    let id: String
    let aircraft: Aircraft
    let screenPoint: CGPoint
    let clampedPoint: CGPoint
    let isClamped: Bool
    let distanceMeters: CLLocationDistance
    let relativeAltitudeMeters: Double
    let bearingDegrees: Double
    let elevationDegrees: Double
    let opacity: Double
    let scale: CGFloat
}

enum ARAircraftProjection {
    static let maxDisplayedAircraft = 24

    static func eligibleAircraft(
        from aircraft: [Aircraft],
        userLocation: CLLocation,
        radiusMeters: CLLocationDistance,
        now: Date = .now
    ) -> [(aircraft: Aircraft, distance: CLLocationDistance)] {
        aircraft
            .compactMap { aircraft -> (aircraft: Aircraft, distance: CLLocationDistance)? in
                guard !aircraft.onGround,
                      aircraft.altitudeMeters != nil,
                      isValidCoordinate(aircraft.coordinate) else {
                    return nil
                }

                let interpolated = aircraft.interpolated(by: now.timeIntervalSince(aircraft.lastUpdate))
                let distance = interpolated.distance(to: userLocation.coordinate)
                guard distance <= radiusMeters else { return nil }
                return (interpolated, distance)
            }
            .sorted { $0.distance < $1.distance }
            .prefix(maxDisplayedAircraft)
            .map { $0 }
    }

    static func screenProjections(
        for aircraft: [Aircraft],
        userLocation: CLLocation,
        camera: ARCamera,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation,
        radiusMeters: CLLocationDistance,
        now: Date = .now
    ) -> [ARAircraftScreenProjection] {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return [] }

        return eligibleAircraft(
            from: aircraft,
            userLocation: userLocation,
            radiusMeters: radiusMeters,
            now: now
        )
        .compactMap { item in
            screenProjection(
                for: item.aircraft,
                distanceMeters: item.distance,
                userLocation: userLocation,
                camera: camera,
                viewportSize: viewportSize,
                orientation: orientation,
                radiusMeters: radiusMeters
            )
        }
    }

    private static func screenProjection(
        for aircraft: Aircraft,
        distanceMeters: CLLocationDistance,
        userLocation: CLLocation,
        camera: ARCamera,
        viewportSize: CGSize,
        orientation: UIInterfaceOrientation,
        radiusMeters: CLLocationDistance
    ) -> ARAircraftScreenProjection? {
        guard let altitudeMeters = aircraft.altitudeMeters else { return nil }

        let offsets = northEastOffsets(
            from: userLocation.coordinate,
            to: aircraft.coordinate
        )
        let referenceAltitude = userLocation.verticalAccuracy >= 0 ? userLocation.altitude : 0
        let relativeAltitude = altitudeMeters - referenceAltitude
        let realWorldVector = SIMD3<Float>(
            Float(offsets.east),
            Float(relativeAltitude),
            Float(-offsets.north)
        )

        let length = simd_length(realWorldVector)
        guard length > 1 else { return nil }

        let direction = realWorldVector / length
        let cameraForward = -SIMD3<Float>(
            camera.transform.columns.2.x,
            camera.transform.columns.2.y,
            camera.transform.columns.2.z
        )
        guard simd_dot(simd_normalize(cameraForward), direction) > 0.02 else { return nil }

        let cameraPosition = SIMD3<Float>(
            camera.transform.columns.3.x,
            camera.transform.columns.3.y,
            camera.transform.columns.3.z
        )
        let projectedWorldPosition = cameraPosition + direction * 100
        let projected = camera.projectPoint(
            projectedWorldPosition,
            orientation: orientation,
            viewportSize: viewportSize
        )
        guard projected.x.isFinite, projected.y.isFinite else { return nil }
        guard isWithinExtendedViewport(projected, viewportSize: viewportSize) else { return nil }

        let cardSize = CGSize(width: 266, height: 150)
        let clamped = CGPoint(
            x: min(max(projected.x, cardSize.width / 2 + 12), viewportSize.width - cardSize.width / 2 - 12),
            y: min(max(projected.y, cardSize.height / 2 + 82), viewportSize.height - cardSize.height / 2 - 44)
        )
        let isClamped = abs(clamped.x - projected.x) > 0.5 || abs(clamped.y - projected.y) > 0.5
        let distanceRatio = min(max(distanceMeters / max(radiusMeters, 1), 0), 1)

        return ARAircraftScreenProjection(
            id: aircraft.id,
            aircraft: aircraft,
            screenPoint: projected,
            clampedPoint: clamped,
            isClamped: isClamped,
            distanceMeters: distanceMeters,
            relativeAltitudeMeters: relativeAltitude,
            bearingDegrees: bearing(from: userLocation.coordinate, to: aircraft.coordinate),
            elevationDegrees: atan2(relativeAltitude, max(distanceMeters, 1)) * 180 / .pi,
            opacity: isClamped ? 0.72 : 1,
            scale: 1.06 - CGFloat(distanceRatio) * 0.18
        )
    }

    private static func northEastOffsets(
        from origin: CLLocationCoordinate2D,
        to target: CLLocationCoordinate2D
    ) -> (north: Double, east: Double) {
        let metersPerDegreeLatitude = 111_320.0
        let meanLatitudeRadians = ((origin.latitude + target.latitude) / 2) * .pi / 180
        let north = (target.latitude - origin.latitude) * metersPerDegreeLatitude
        let east = (target.longitude - origin.longitude) * metersPerDegreeLatitude * cos(meanLatitudeRadians)
        return (north, east)
    }

    private static func bearing(
        from origin: CLLocationCoordinate2D,
        to target: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let deltaLongitude = (target.longitude - origin.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func isValidCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
        && coordinate.latitude.isFinite
        && coordinate.longitude.isFinite
    }

    private static func isWithinExtendedViewport(_ point: CGPoint, viewportSize: CGSize) -> Bool {
        let horizontalInset = viewportSize.width * 0.35
        let verticalInset = viewportSize.height * 0.35
        return point.x >= -horizontalInset
        && point.x <= viewportSize.width + horizontalInset
        && point.y >= -verticalInset
        && point.y <= viewportSize.height + verticalInset
    }
}
