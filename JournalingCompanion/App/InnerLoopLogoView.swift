import SwiftUI

struct InnerLoopLogoSymbol: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = size * 0.067

            ZStack {
                ReflectionSpiral()
                    .stroke(
                        AppBrand.logoGreen,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: size, height: size)

                Circle()
                    .fill(AppBrand.logoInk)
                    .frame(width: size * 0.14, height: size * 0.14)
                    .offset(x: size * 0.04, y: size * 0.03)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct InnerLoopAppIconPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppBrand.logoBackgroundGradient)

            InnerLoopLogoSymbol()
                .padding(28)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ReflectionSpiral: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + width * x, y: rect.minY + height * (1 - y))
        }

        var path = Path()
        path.move(to: point(0.31, 0.55))
        path.addCurve(
            to: point(0.69, 0.29),
            control1: point(0.31, 0.37),
            control2: point(0.49, 0.23)
        )
        path.addCurve(
            to: point(0.88, 0.55),
            control1: point(0.82, 0.33),
            control2: point(0.88, 0.43)
        )
        path.addCurve(
            to: point(0.51, 0.82),
            control1: point(0.88, 0.73),
            control2: point(0.69, 0.86)
        )
        path.addCurve(
            to: point(0.18, 0.41),
            control1: point(0.27, 0.78),
            control2: point(0.15, 0.61)
        )
        path.addCurve(
            to: point(0.46, 0.08),
            control1: point(0.20, 0.24),
            control2: point(0.31, 0.12)
        )

        return path
    }
}

extension AppBrand {
    static let logoGreen = Color(red: 0.184, green: 0.435, blue: 0.400)
    static let logoInk = Color(red: 0.141, green: 0.231, blue: 0.212)
    static let logoCream = Color(red: 0.969, green: 0.949, blue: 0.902)
    static let logoMist = Color(red: 0.910, green: 0.941, blue: 0.922)

    static var logoBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [logoCream, logoMist],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
