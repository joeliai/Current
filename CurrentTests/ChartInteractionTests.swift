@testable import Current
import UIKit
import XCTest

@MainActor
final class ChartInteractionTests: XCTestCase {
    func testChartDoesNotVetoAncestorScrollGesture() {
        let scrollView = UIScrollView()
        let chart = PowerChartView()
        scrollView.addSubview(chart)
        XCTAssertTrue(
            chart.gestureRecognizerShouldBegin(scrollView.panGestureRecognizer),
            "The hit-tested chart must not reject the scroll view's pan."
        )
    }

    func testChartDelegateOnlyAcceptsHorizontalPanning() {
        let delegate = ChartScrubGestureDelegate()
        XCTAssertTrue(delegate.gestureRecognizerShouldBegin(VelocityPan(CGPoint(x: 120, y: 5))))
        XCTAssertFalse(delegate.gestureRecognizerShouldBegin(VelocityPan(CGPoint(x: 5, y: 120))))
        XCTAssertFalse(delegate.gestureRecognizerShouldBegin(VelocityPan(CGPoint(x: 50, y: 50))))
        XCTAssertFalse(delegate.gestureRecognizerShouldBegin(VelocityPan(.zero)))
    }

    func testWindowSwitchAndCursorPreserveGeometryAndClearSelection() throws {
        let chart = PowerChartView(frame: CGRect(x: 0, y: 0, width: 350, height: 176))
        let session = fixture()
        chart.layoutIfNeeded()
        chart.set(session: session, window: .recent)
        XCTAssertGreaterThan(chart.layer.sublayers?.first?.bounds.width ?? 0, 300)
        let line = try XCTUnwrap(chart.layer.sublayers?.first?.sublayers?.compactMap { $0 as? CAShapeLayer }
            .first { $0.lineWidth == 2.5 })
        let path = try XCTUnwrap(line.path)
        var selected: ChargingSample?
        chart.onScrub = { selected = $0 }
        chart.accessibilityIncrement()
        XCTAssertNotNil(selected)
        chart.set(session: session, window: .session)
        XCTAssertNil(selected)
        chart.set(session: session, window: .recent)
        // CAShapeLayer copies its path; geometry, not object identity, is the contract.
        XCTAssertEqual(line.path, path)
        XCTAssertFalse(chart.layer.animationKeys()?.contains("window") ?? false)
        chart.accessibilityIncrement()
        XCTAssertNotNil(selected)
        XCTAssertEqual(line.path, path, "Moving the cursor must not change the curve.")
    }

    func testNewDataAndResizingInvalidateCachedGeometry() throws {
        let chart = PowerChartView(frame: CGRect(x: 0, y: 0, width: 350, height: 176))
        var session = fixture()
        chart.layoutIfNeeded()
        chart.set(session: session, window: .session)
        let line = try XCTUnwrap(chart.layer.sublayers?.first?.sublayers?.compactMap { $0 as? CAShapeLayer }
            .first { $0.lineWidth == 2.5 })
        let before = try XCTUnwrap(line.path)
        session.samples.append(ChargingSample(
            timestamp: session.lastSampleAt.addingTimeInterval(2), powerWatts: 30
        ))
        chart.set(session: session, window: .session)
        XCTAssertFalse(line.path === before)
        let narrower = try XCTUnwrap(line.path)
        chart.frame.size.width = 650
        chart.setNeedsLayout()
        chart.layoutIfNeeded()
        XCTAssertFalse(line.path === narrower)
    }

    func testSessionDetailLabelsTheMeasurementWithoutDemoMode() {
        let controller = SessionDetailViewController(session: fixture())
        controller.loadViewIfNeeded()
        controller.render()
        let descendants = flattened(controller.view)
        XCTAssertTrue(descendants
            .contains { $0.accessibilityLabel == "Measurement" && $0.accessibilityValue == "USB input" })
        XCTAssertTrue(descendants.contains { $0.accessibilityIdentifier == "sessionAverage" })
    }

    func testRenderedCurveIsAttachedForVisualReview() {
        let chart = PowerChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
        chart.setNeedsLayout()
        chart.layoutIfNeeded()
        chart.set(session: fixture(), window: .session)
        chart.layer.displayIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: chart.bounds.size)
        let image = renderer.image {
            UIColor.systemBackground.setFill()
            $0.fill(chart.bounds)
            chart.layer.render(in: $0.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Cached-Curve-With-Test-Fixture"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fixture() -> ChargingSession {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return ChargingSession(
            startedAt: start, powerMeasurement: .usbInput,
            samples: (0 ... 300).map {
                ChargingSample(timestamp: start.addingTimeInterval(Double($0 * 2)), powerWatts: Double($0 % 20))
            }
        )
    }

    private func flattened(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(flattened)
    }
}

private final class VelocityPan: UIPanGestureRecognizer {
    private let vector: CGPoint

    init(_ vector: CGPoint) {
        self.vector = vector
        super.init(target: nil, action: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func velocity(in _: UIView?) -> CGPoint {
        vector
    }
}
