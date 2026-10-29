import ResoluteDesign

/// Every scene the gallery knows: the design system's components, then the app's screens.
/// Each feature owner adds its scenes in its own `Scenes/Gallery+….swift` file, so no two
/// owners edit the same file.
@MainActor
enum AppGallery {
    static var scenes: [GalleryScene] {
        DesignCatalog.scenes.map(GalleryScene.init)
            + shellScenes
            + panelScenes
            + trialScenes
            + windowScenes
            + displayScenes
            + customResolutionScenes
            + presetAndHistoryScenes
            + settingsScenes
            + onboardingScenes
            + sharpScalingScenes
            + integrationScenes
    }
}
