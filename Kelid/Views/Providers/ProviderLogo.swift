import SwiftUI

/// Renders a provider's official brand mark (template-tinted) at a given size,
/// falling back to its SF Symbol if the asset is unavailable.
struct ProviderLogo: View {
    let provider: AIProvider
    var size: CGFloat = 18

    var body: some View {
        Image(provider.logoAsset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
