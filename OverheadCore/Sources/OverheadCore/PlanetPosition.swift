import Foundation
import SatelliteKit

/// The azimuth/elevation, visual magnitude, and characteristic colour of one
/// planet at a given observer location and time.
public struct PlanetSnapshot: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let azimuthDegrees: Double
    public let elevationDegrees: Double
    /// Apparent visual magnitude (smaller = brighter; Venus ≈ −4.4, Saturn ≈ +0.5).
    public let magnitude: Double
    /// Earth–planet distance in AU at the time of the snapshot.
    public let distanceAU: Double
    public let colorR: Float
    public let colorG: Float
    public let colorB: Float
    public var isAboveHorizon: Bool { elevationDegrees > 0 }
}

/// Computes low-precision planetary positions using the simplified orbital
/// elements from Jean Meeus, *Astronomical Algorithms* 2nd ed., Chapter 33
/// (Table 33.a).  Typical accuracy: 1–2°, more than sufficient for placing
/// labelled dots in an AR sky view.
public enum PlanetPosition {

    /// Returns a snapshot for each of the five naked-eye planets that are
    /// currently computable (always all five — the caller filters by elevation).
    public static func snapshots(
        observer: ObserverLocation,
        at date: Date = Date()
    ) -> [PlanetSnapshot] {
        let T    = julianCenturies(date)
        let earth = helioXYZ(Planet.earth.elements(T))
        let site  = (observer.latitudeDegrees, observer.longitudeDegrees)

        return Planet.visible.map { planet in
            let elem = planet.elements(T)
            let xyz  = helioXYZ(elem)
            let (ra, dec, delta) = geocentric(planetXYZ: xyz, earthXYZ: earth, T: T)
            let look = azel(time: date, site: site, cele: (ra, dec))
            let r    = length(xyz)
            return PlanetSnapshot(
                name:             planet.name,
                azimuthDegrees:   look.azi,
                elevationDegrees: look.alt,
                magnitude:        planet.magnitude(r: r, delta: delta),
                distanceAU:       delta,
                colorR:           planet.color.r,
                colorG:           planet.color.g,
                colorB:           planet.color.b
            )
        }
    }

    // MARK: - Internal math

    private static func julianCenturies(_ date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        return (jd - 2451545.0) / 36525.0
    }

    private static func helioXYZ(_ e: Elements) -> (Double, Double, Double) {
        let i  = e.i.rad
        let bigOmega = e.bigOmega.rad
        let omega = (e.pomega - e.bigOmega).normDeg.rad   // argument of perihelion
        let M = (e.L - e.pomega).normDeg.rad
        let ec = e.e
        let E  = kepler(M: M, e: ec)
        let v  = 2 * atan2(sqrt(1 + ec) * sin(E / 2),
                           sqrt(1 - ec) * cos(E / 2))
        let r  = e.a * (1 - ec * cos(E))
        let u  = v + omega
        let x  = r * (cos(bigOmega) * cos(u) - sin(bigOmega) * sin(u) * cos(i))
        let y  = r * (sin(bigOmega) * cos(u) + cos(bigOmega) * sin(u) * cos(i))
        let z  = r * sin(u) * sin(i)
        return (x, y, z)
    }

    private static func geocentric(
        planetXYZ p: (Double, Double, Double),
        earthXYZ  e: (Double, Double, Double),
        T: Double
    ) -> (ra: Double, dec: Double, delta: Double) {
        let gx = p.0 - e.0, gy = p.1 - e.1, gz = p.2 - e.2
        let delta = length((gx, gy, gz))
        // Rotate ecliptic → equatorial using mean obliquity
        let eps = (23.439291111 - 0.013004167 * T).rad
        let x = gx
        let y = gy * cos(eps) - gz * sin(eps)
        let z = gy * sin(eps) + gz * cos(eps)
        var ra = atan2(y, x).deg
        if ra < 0 { ra += 360 }
        let dec = asin(max(-1, min(1, z / delta))).deg
        return (ra, dec, delta)
    }

    private static func kepler(M: Double, e: Double) -> Double {
        var E = M
        for _ in 0..<50 {
            let d = (M - E + e * sin(E)) / (1 - e * cos(E))
            E += d
            if abs(d) < 1e-10 { break }
        }
        return E
    }

    private static func length(_ v: (Double, Double, Double)) -> Double {
        sqrt(v.0*v.0 + v.1*v.1 + v.2*v.2)
    }
}

// MARK: - Orbital elements (Meeus Table 33.a, J2000.0 epoch)

private struct Elements {
    let L: Double       // mean longitude (°)
    let a: Double       // semi-major axis (AU)
    let e: Double       // eccentricity
    let i: Double       // inclination (°)
    let bigOmega: Double // longitude of ascending node (°)
    let pomega: Double  // longitude of perihelion (°)
}

private enum Planet: CaseIterable {
    case mercury, venus, earth, mars, jupiter, saturn

    static let visible: [Planet] = [.mercury, .venus, .mars, .jupiter, .saturn]

    var name: String {
        switch self {
        case .mercury: return "Mercury"
        case .venus:   return "Venus"
        case .earth:   return "Earth"
        case .mars:    return "Mars"
        case .jupiter: return "Jupiter"
        case .saturn:  return "Saturn"
        }
    }

    var color: (r: Float, g: Float, b: Float) {
        switch self {
        case .mercury: return (0.62, 0.62, 0.62)   // neutral grey
        case .venus:   return (1.00, 0.87, 0.42)   // warm golden-yellow
        case .earth:   return (0.40, 0.65, 1.00)
        case .mars:    return (0.95, 0.40, 0.15)   // strong red-orange
        case .jupiter: return (1.00, 0.76, 0.44)   // amber-cream
        case .saturn:  return (0.98, 0.84, 0.36)   // clearly golden
        }
    }

    func elements(_ T: Double) -> Elements {
        switch self {
        case .mercury:
            return Elements(
                L:         (252.250906 + 149474.0722491 * T).normDeg,
                a:          0.387098310,
                e:          0.20563175  +   0.000020407 * T,
                i:          7.004986    -   0.0059516   * T,
                bigOmega:  (48.330893  -    0.1254230   * T).normDeg,
                pomega:    (77.456119  +    0.1588643   * T).normDeg)
        case .venus:
            return Elements(
                L:         (181.979801 +  58519.2130302 * T).normDeg,
                a:          0.723329820,
                e:          0.00677192  -  0.000047765  * T,
                i:          3.394662    -  0.0008568    * T,
                bigOmega:  (76.679920  -   0.2780134    * T).normDeg,
                pomega:   (131.563703  +   0.0048746    * T).normDeg)
        case .earth:
            return Elements(
                L:         (100.466457 +  36000.7698278 * T).normDeg,
                a:          1.000001018,
                e:          0.01670863  -  0.000042037  * T,
                i:          0.0,
                bigOmega:   0.0,
                pomega:   (102.937348  +   0.3225557    * T).normDeg)
        case .mars:
            return Elements(
                L:         (355.433000 +  19141.6964471 * T).normDeg,
                a:          1.523679342,
                e:          0.09340065  +  0.000090484  * T,
                i:          1.849726    -  0.0081477    * T,
                bigOmega:  (49.558093  -   0.2949846    * T).normDeg,
                pomega:   (336.060234  +   0.4438898    * T).normDeg)
        case .jupiter:
            return Elements(
                L:          (34.351519 +   3036.3027748 * T).normDeg,
                a:           5.202603209 + 0.0000001913 * T,
                e:           0.04849793  + 0.000163225  * T,
                i:           1.303267    - 0.0054965    * T,
                bigOmega:  (100.464407  +  0.1767232    * T).normDeg,
                pomega:     (14.331207  +  0.2155209    * T).normDeg)
        case .saturn:
            return Elements(
                L:          (50.077444  +  1223.5110686 * T).normDeg,
                a:           9.554909192 - 0.0000021390 * T,
                e:           0.05554814  - 0.000346641  * T,
                i:           2.488879    - 0.0037362    * T,
                bigOmega:  (113.665503  -  0.2566722    * T).normDeg,
                pomega:     (93.057237  +  0.5665415    * T).normDeg)
        }
    }

    /// Simplified apparent magnitude — ignores phase angle for outer planets,
    /// which introduces < 0.3 mag error at typical oppositions.
    func magnitude(r: Double, delta: Double) -> Double {
        let H: Double
        switch self {
        case .mercury: H = -0.36
        case .venus:   H = -4.40
        case .earth:   H =  0.00
        case .mars:    H = -1.52
        case .jupiter: H = -9.40
        case .saturn:  H = -8.88
        }
        return H + 5 * log10(r * delta)
    }
}

// MARK: - Moon

/// Position, distance, and phase of the Moon at a given observer location and time.
public struct MoonSnapshot: Sendable, Identifiable {
    public var id: String { "Moon" }
    public let azimuthDegrees: Double
    public let elevationDegrees: Double
    /// Earth–Moon distance in kilometres.
    public let distanceKm: Double
    /// Illuminated fraction 0 (new) … 1 (full).
    public let illuminationFraction: Double
    /// True while the Moon is between new and full (RA increasing east of Sun).
    public let isWaxing: Bool
    public var isAboveHorizon: Bool { elevationDegrees > 0 }

    public var phaseName: String {
        let k = illuminationFraction
        if k < 0.02 { return "New Moon" }
        if k > 0.98 { return "Full Moon" }
        if k < 0.48 { return isWaxing ? "Waxing Crescent" : "Waning Crescent" }
        if k < 0.52 { return isWaxing ? "First Quarter"   : "Third Quarter" }
        return isWaxing ? "Waxing Gibbous" : "Waning Gibbous"
    }
}

/// Computes the Moon's position using SatelliteKit's built-in `lunarGeo` / `lunarCel`
/// formulae (Simpson NASA/GSFC ephemeris, ~1° accuracy).
public enum MoonPosition {
    public static func snapshot(
        observer: ObserverLocation,
        at date: Date = Date()
    ) -> MoonSnapshot {
        let jd   = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let site = (observer.latitudeDegrees, observer.longitudeDegrees)

        let (moonDec, moonRA) = lunarGeo(julianDays: jd)
        let (sunDec,  sunRA)  = solarGeo(julianDays: jd)

        let look = azel(time: date, site: site, cele: (moonRA, moonDec))

        // Distance: magnitude of the ECI position vector (components in km)
        let vec     = lunarCel(julianDays: jd)
        let distKm  = (vec.x * vec.x + vec.y * vec.y + vec.z * vec.z).squareRoot()

        // Illumination fraction from the Sun–Moon elongation
        let dRA  = (moonRA - sunRA) * .pi / 180
        let mDec = moonDec * .pi / 180
        let sDec = sunDec  * .pi / 180
        let cosE = sin(sDec) * sin(mDec) + cos(sDec) * cos(mDec) * cos(dRA)
        let illumination = (1 - cosE) / 2   // 0 at new moon, 1 at full moon

        return MoonSnapshot(
            azimuthDegrees:      look.azi,
            elevationDegrees:    look.alt,
            distanceKm:          distKm,
            illuminationFraction: max(0, min(1, illumination)),
            isWaxing:            sin(dRA) > 0
        )
    }
}

// MARK: - Angle helpers

private extension Double {
    var rad: Double { self * .pi / 180 }
    var deg: Double { self * 180 / .pi }
    var normDeg: Double {
        var v = truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }
}
