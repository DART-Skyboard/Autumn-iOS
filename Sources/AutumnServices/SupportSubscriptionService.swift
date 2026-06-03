import StoreKit
import SwiftUI

// MARK: — SupportSubscriptionService
// $4.99/month "Support Development" auto-renewable subscription
// Product IDs must match what you create in App Store Connect:
//   Autumn:  com.dartmeadow.autumn.support.monthly
//   ArcLake: DART-Meadow-LLC.Cotharticren.support.monthly

@MainActor
public final class SupportSubscriptionService: ObservableObject {
    public static let shared = SupportSubscriptionService()

    // Set this to the correct product ID for each app
    public var productID: String = "com.dartmeadow.autumn.support.monthly"

    @Published public var product: Product?
    @Published public var isSubscribed = false
    @Published public var isPurchasing = false
    @Published public var error: String?
    @Published public var transactionID: String?

    private var updateListenerTask: Task<Void, Error>?

    public init() {
        updateListenerTask = listenForTransactions()
        Task { await loadProducts(); await checkSubscriptionStatus() }
    }

    deinit { updateListenerTask?.cancel() }

    // MARK: — Load product from App Store
    public func loadProducts() async {
        do {
            let products = try await Product.products(for: [productID])
            product = products.first
        } catch {
            self.error = "Could not load subscription: \(error.localizedDescription)"
        }
    }

    // MARK: — Purchase
    public func purchase() async {
        guard let product else {
            self.error = "Subscription not available"
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                isSubscribed = true
                transactionID = String(transaction.id)
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                self.error = "Purchase pending approval"
            @unknown default:
                break
            }
        } catch {
            self.error = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: — Restore purchases
    public func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            self.error = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: — Check current subscription status
    public func checkSubscriptionStatus() async {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == productID {
                isSubscribed = true
                transactionID = String(transaction.id)
                return
            }
        }
        isSubscribed = false
    }

    // MARK: — Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? await MainActor.run(body: {
                    return try self.checkVerified(result)
                }) {
                    await MainActor.run {
                        if transaction.productID == self.productID {
                            self.isSubscribed = transaction.revocationDate == nil
                        }
                    }
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }
}

// MARK: — Support Sheet UI
// Drop-in sheet for both apps — call .sheet(isPresented:) { SupportSheet() }
public public struct SupportSheet: View {
    @StateObject private var store = SupportSubscriptionService.shared
    @Environment(\.dismiss) var dismiss
    public var accentColor: Color = Color(red:0.0, green:0.85, blue:1.0)
    public var appName: String = "Autumn"
    public init(accentColor: Color = Color(red:0.0,green:0.85,blue:1.0), appName: String = "Autumn") {
        self.accentColor = accentColor
        self.appName = appName
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red:0.012,green:0.020,blue:0.042),
                         Color(red:0.025,green:0.010,blue:0.055)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Capsule().fill(Color.white.opacity(0.15))
                        .frame(width:40, height:4)
                        .padding(.top, 14)

                    // ── Hero ──────────────────────────────────────
                    VStack(spacing:12) {
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.1))
                                .frame(width:80, height:80)
                            Circle()
                                .stroke(accentColor.opacity(0.35), lineWidth:1.5)
                                .frame(width:80, height:80)
                            Image(systemName: "heart.fill")
                                .font(.system(size:32))
                                .foregroundStyle(LinearGradient(
                                    colors: [accentColor, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                        }
                        Text("Support \(appName)")
                            .font(.custom("Orbitron-Bold", size:20))
                            .foregroundColor(.white)
                        Text("Help keep \(appName) in active development")
                            .font(.system(size:12, design:.monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }

                    // ── Price card ────────────────────────────────
                    VStack(spacing:16) {
                        // Subscription price
                        if let product = store.product {
                            VStack(spacing:6) {
                                Text(product.displayPrice)
                                    .font(.system(size:36, weight:.bold, design:.monospaced))
                                    .foregroundColor(accentColor)
                                Text("per month")
                                    .font(.system(size:11, design:.monospaced))
                                    .foregroundColor(.white.opacity(0.35))
                                Text(product.description)
                                    .font(.system(size:11))
                                    .foregroundColor(.white.opacity(0.5))
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            Text("$4.99 / month")
                                .font(.system(size:36, weight:.bold, design:.monospaced))
                                .foregroundColor(accentColor)
                        }

                        // What you get
                        VStack(alignment:.leading, spacing:10) {
                            supportPerk("Active development of new features", icon:"wrench.and.screwdriver.fill")
                            supportPerk("LEATR · BRPN · mc³ research",         icon:"atom")
                            supportPerk("iOS app improvements & bug fixes",    icon:"iphone")
                            supportPerk("Web app parity & sync updates",       icon:"globe")
                            supportPerk("Supporter badge in your profile",     icon:"star.fill")
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius:12))
                        .overlay(RoundedRectangle(cornerRadius:12)
                            .stroke(accentColor.opacity(0.12), lineWidth:0.7))
                    }

                    // ── Action buttons ────────────────────────────
                    VStack(spacing:10) {
                        if store.isSubscribed {
                            // Already subscribed
                            HStack(spacing:10) {
                                Image(systemName:"checkmark.seal.fill")
                                    .foregroundColor(accentColor)
                                Text("Subscribed — Thank you!")
                                    .font(.system(size:13, weight:.semibold, design:.monospaced))
                                    .foregroundColor(accentColor)
                            }
                            .frame(maxWidth:.infinity).frame(height:52)
                            .background(accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius:12))
                            .overlay(RoundedRectangle(cornerRadius:12)
                                .stroke(accentColor.opacity(0.3), lineWidth:1))

                        } else {
                            // Subscribe button
                            Button {
                                Task { await store.purchase() }
                            } label: {
                                ZStack {
                                    if store.isPurchasing {
                                        ProgressView().tint(.black)
                                    } else {
                                        HStack(spacing:8) {
                                            Image(systemName:"applelogo")
                                                .font(.system(size:14))
                                            Text("Subscribe with Apple Pay")
                                                .font(.system(size:14, weight:.semibold, design:.monospaced))
                                        }
                                        .foregroundColor(.black)
                                    }
                                }
                                .frame(maxWidth:.infinity).frame(height:52)
                                .background(store.isPurchasing ? accentColor.opacity(0.5) : accentColor)
                                .clipShape(RoundedRectangle(cornerRadius:12))
                            }
                            .disabled(store.isPurchasing || store.product == nil)
                        }

                        // Restore
                        Button {
                            Task { await store.restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                                .font(.system(size:11, design:.monospaced))
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }

                    if let err = store.error {
                        Text(err)
                            .font(.system(size:10, design:.monospaced))
                            .foregroundColor(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    // Legal
                    VStack(spacing:6) {
                        Text("Subscription auto-renews monthly. Cancel anytime in Settings → Apple ID → Subscriptions.")
                            .font(.system(size:9))
                            .foregroundColor(.white.opacity(0.2))
                            .multilineTextAlignment(.center)
                        HStack(spacing:16) {
                            Link("Privacy Policy",
                                 destination: URL(string:"https://dartmeadow.com/privacy")!)
                            Link("Terms of Use",
                                 destination: URL(string:"https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        }
                        .font(.system(size:9, design:.monospaced))
                        .foregroundColor(accentColor.opacity(0.4))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
            }
        }
        .presentationDetents([.large])
        .onAppear { Task { await store.loadProducts() } }
    }

    private func supportPerk(_ text: String, icon: String) -> some View {
        HStack(spacing:12) {
            Image(systemName: icon)
                .font(.system(size:12))
                .foregroundColor(accentColor)
                .frame(width:20)
            Text(text)
                .font(.system(size:11, design:.monospaced))
                .foregroundColor(.white.opacity(0.65))
            Spacer()
        }
    }
}
