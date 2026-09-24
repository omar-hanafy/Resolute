import Foundation

/// A fresh temporary directory. Its name contains a space and a single quote, so every
/// test that writes files also checks path quoting.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "Resolute Tests 'quoted' \(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func hexData(_ hex: String) -> Data {
    Data(TestData.bytes(hex: hex.replacingOccurrences(of: " ", with: "")))
}

/// The override RDM wrote on the development Mac for a 5120×2160 monitor, byte for byte.
let rdmOverrideXML = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>DisplayProductName</key>
	<string></string>
	<key>scale-resolutions</key>
	<array>
		<data>
		AAAUAAAACHA=
		</data>
		<data>
		AAAUAAAACHAAAAALAKAAAA==
		</data>
	</array>
	<key>target-default-ppmm</key>
	<real>10.01</real>
</dict>
</plist>
"""
