import SwiftUI

/// TF140: MUSIC as a proper frosted overlay, matching the Admin console's
/// visual language exactly (same .ultraThinMaterial + tint, same rounded
/// corners, same draggable title bar with a close button) instead of the
/// old full-screen Tools-menu presentation.
public struct MusicOverlayView: View {
    @EnvironmentObject var themeVM: ThemeViewModel
    @EnvironmentObject var appNav: AppNavigation
    @State private var dragOffset: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero

    public init() {}

    public var body: some View {
        let chrome = themeVM.chrome
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { appNav.studio = nil }

            VStack(spacing: 0) {
                HStack {
                    Text("🎵 MUSIC").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundColor(Color(hex: "#ff5fa8"))
                    Spacer()
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.25))
                    Button("✕") { appNav.studio = nil }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Color(hex: "#ff4466"))
                }
                .padding(12)
                .background(Color(hex: "#ff5fa8").opacity(0.06))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($liveDrag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            dragOffset.width += value.translation.width
                            dragOffset.height += value.translation.height
                        }
                )

                MusicPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: min(380, UIScreen.main.bounds.width - 24), height: min(560, UIScreen.main.bounds.height * 0.72))
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#ff5fa8").opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .padding(.leading, 16).padding(.top, 60)
            .offset(x: dragOffset.width + liveDrag.width, y: dragOffset.height + liveDrag.height)
        }
    }
}
