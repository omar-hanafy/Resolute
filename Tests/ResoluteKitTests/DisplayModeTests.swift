import Testing
@testable import ResoluteKit

@Suite struct DisplayModeTests {
    @Test func hiDPIModeReportsScaleAndFlags() {
        let mode = DisplayMode(
            modeID: 54, width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234,
            refreshRate: 120, ioFlags: 0x0200_0007
        )
        #expect(mode.scale == 2)
        #expect(mode.isHiDPI)
        #expect(mode.isDefault)
        #expect(mode.isNative)
        #expect(mode.sizeText == "1728 × 1117")
        #expect(mode.pixelSizeText == "3456 × 2234")
        #expect(mode.id == 54)
    }

    @Test func lowResolutionModeIsNotHiDPI() {
        let mode = DisplayMode(
            modeID: 126, width: 3456, height: 2234, pixelWidth: 3456, pixelHeight: 2234,
            refreshRate: 120, ioFlags: 0x0200_0003
        )
        #expect(mode.scale == 1)
        #expect(!mode.isHiDPI)
        #expect(!mode.isDefault)
        #expect(mode.isNative)
    }

    @Test(arguments: [
        (120.0, "120 Hz"), (59.94, "59.94 Hz"), (47.95, "47.95 Hz"),
        (59.900001, "59.9 Hz"), (0.0, ""),
    ])
    func formatsRefreshRates(hertz: Double, expected: String) {
        #expect(RefreshRate.format(hertz) == expected)
    }

    @Test func refreshKeysIgnoreFloatingPointNoise() {
        #expect(RefreshRate.key(59.940000244) == RefreshRate.key(59.94))
        #expect(RefreshRate.key(60) != RefreshRate.key(59.94))
    }

    @Test func displayFindsItsCurrentMode() {
        let display = TestData.fullHD(currentModeID: 2)
        #expect(display.currentMode?.refreshRate == 50)
        #expect(display.hiddenModeCount == 2)
        #expect(TestData.fullHD(currentModeID: 999).currentMode == nil)
    }

    @Test func errorsNameCoreGraphicsCodes() {
        let error = ResoluteError.coreGraphics(code: 1001, operation: "apply the display mode")
        #expect(error.errorDescription == "CoreGraphics could not apply the display mode: illegal argument (1001).")
    }

    @Test func capturedFixtureLoads() throws {
        let capture = try CapturedDisplay.load()
        #expect(capture.systemModes.count == 132)
        #expect(capture.records.count == 132)
        #expect(capture.records.allSatisfy { $0.count == 0xD4 })
        #expect(capture.display().currentMode?.sizeText == "1728 × 1117")
    }
}
