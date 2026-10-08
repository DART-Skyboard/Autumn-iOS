import StoreKit
import SwiftUI

// MARK: — SupportSubscriptionService
// Two ways to support early-alpha development, both $4.99:
//   • Monthly (auto-renewable subscription, in the "Autumn Support" group)
//   • One-time (consumable) — can be given more than once
// Product IDs must match App Store Connect (app "Autumn AI", com.dartmeadow.autumn):
//   com.dartmeadow.autumn.support.monthly
//   com.dartmeadow.autumn.support.donation
// Purchases go through the user's Apple ID only — nothing about the purchase touches Autumn's knowledge base or
// the user's profile data. Works signed in or not.

@MainActor
public final class SupportSubscriptionService: ObservableObject {
    public static let shared = SupportSubscriptionService()

    public var monthlyID: String = "com.dartmeadow.autumn.support.monthly"
    public var donationID: String = "com.dartmeadow.autumn.support.donation"
    /// Kept for source compatibility with the single-product version.
    public var productID: String {
        get { monthlyID }
        set { monthlyID = newValue }
    }

    @Published public var monthly: Product?
    @Published public var donation: Product?
    @Published public var isSubscribed = false
    @Published public var isPurchasing = false
    @Published public var error: String?
    @Published public var transactionID: String?
    @Published public var donationCount: Int = UserDefaults.standard.integer(forKey: "autumn_support_donation_count")
    @Published public var didLoad = false

    public var product: Product? { monthly }
    public var isSupporter: Bool { isSubscribed || donationCount > 0 }

    private var updateListenerTask: Task<Void, Error>?
    private let countedKey = "autumn_support_counted_tx"

    public init() {
        updateListenerTask = listenForTransactions()
        Task { await loadProducts(); await checkSubscriptionStatus() }
    }

    deinit { updateListenerTask?.cancel() }

    // MARK: — Load products from App Store
    public func loadProducts() async {
        do {
            let products = try await Product.products(for: [monthlyID, donationID])
            monthly = products.first { $0.id == monthlyID }
            donation = products.first { $0.id == donationID }
            didLoad = true
        } catch {
            self.error = "Could not load support options: \(error.localizedDescription)"
            didLoad = true
        }
    }

    // MARK: — Purchase
    public func purchaseMonthly() async { await purchase(monthly) }
    public func purchaseDonation() async { await purchase(donation) }
    /// Source compatibility.
    public func purchase() async { await purchase(monthly) }

    private func purchase(_ product: Product?) async {
        guard let product else {
            self.error = "That option isn't available from the App Store right now."
            return
        }
        error = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                apply(transaction)
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

    /// Record a verified transaction (subscription active, or one more one-time gift — each transaction counted once).
    private func apply(_ transaction: Transaction) {
        if transaction.productID == monthlyID {
            isSubscribed = transaction.revocationDate == nil
            transactionID = String(transaction.id)
        } else if transaction.productID == donationID, transaction.revocationDate == nil {
            var seen = Set(UserDefaults.standard.stringArray(forKey: countedKey) ?? [])
            let id = String(transaction.id)
            if !seen.contains(id) {
                seen.insert(id)
                UserDefaults.standard.set(Array(seen.suffix(500)), forKey: countedKey)
                donationCount += 1
                UserDefaults.standard.set(donationCount, forKey: "autumn_support_donation_count")
            }
            transactionID = id
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
        var active = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result), transaction.productID == monthlyID {
                active = true
                transactionID = String(transaction.id)
            }
        }
        isSubscribed = active
    }

    // MARK: — Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? await MainActor.run(body: {
                    return try self.checkVerified(result)
                }) {
                    await MainActor.run { self.apply(transaction) }
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
public struct SupportSheet: View {
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
                VStack(spacing: 22) {
                    HStack {
                        Capsule().fill(Color.white.opacity(0.15)).frame(width:40, height:4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                    // ── Hero ──────────────────────────────────────
                    VStack(spacing:12) {
                        ZStack {
                            Circle().fill(accentColor.opacity(0.1)).frame(width:80, height:80)
                            Circle().stroke(accentColor.opacity(0.35), lineWidth:1.5).frame(width:80, height:80)
                            Image(systemName: "heart.fill")
                                .font(.system(size:32))
                                .foregroundStyle(LinearGradient(colors: [accentColor, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        Text("Support \(appName)")
                            .font(.custom("Orbitron-Bold", size:20))
                            .foregroundColor(.white)
                        Text("Help fund early-alpha development")
                            .font(.system(size:12, design:.monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                        if store.isSupporter {
                            HStack(spacing: 8) {
                                Image(systemName:"checkmark.seal.fill").foregroundColor(accentColor)
                                Text(supporterLine)
                                    .font(.system(size:12, weight:.semibold, design:.monospaced))
                                    .foregroundColor(accentColor)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(accentColor.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accentColor.opacity(0.3), lineWidth: 1))
                        }
                    }

                    // ── Perks ─────────────────────────────────────
                    VStack(alignment:.leading, spacing:10) {
                        supportPerk("Active development of new features", icon:"wrench.and.screwdriver.fill")
                        supportPerk("LEATR · BRPN · mc³ research",         icon:"atom")
                        supportPerk("iOS app improvements & bug fixes",    icon:"iphone")
                        supportPerk("Web app parity & sync updates",       icon:"globe")
                        supportPerk("Supporter badge",                     icon:"star.fill")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).stroke(accentColor.opacity(0.12), lineWidth:0.7))

                    // ── Two ways to give ──────────────────────────
                    VStack(spacing: 12) {
                        optionCard(
                            title: "Monthly Supporter",
                            price: store.monthly?.displayPrice ?? "$4.99",
                            unit: "per month · cancel anytime",
                            button: store.isSubscribed ? "Subscribed — Thank you!" : "Subscribe",
                            enabled: store.monthly != nil && !store.isSubscribed,
                            filled: !store.isSubscribed
                        ) { Task { await store.purchaseMonthly() } }

                        optionCard(
                            title: "One-Time Support",
                            price: store.donation?.displayPrice ?? "$4.99",
                            unit: "one time · give again anytime",
                            button: "Give once",
                            enabled: store.donation != nil,
                            filled: false
                        ) { Task { await store.purchaseDonation() } }
                    }

                    if store.didLoad && store.monthly == nil && store.donation == nil {
                        Text("Support options aren't available from the App Store right now. Try again in a bit.")
                            .font(.system(size:10, design:.monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.system(size:11, design:.monospaced))
                            .foregroundColor(.white.opacity(0.4))
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
                        Text("Monthly support auto-renews each month until cancelled in Settings → Apple ID → Subscriptions. The one-time option is a single charge. Supporting never changes what Autumn does with your data.")
                            .font(.system(size:9))
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                        HStack(spacing:16) {
                            Link("Privacy Policy", destination: URL(string:"https://dartmeadow.com/privacy")!)
                            Link("Terms of Use", destination: URL(string:"https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        }
                        .font(.system(size:9, design:.monospaced))
                        .foregroundColor(accentColor.opacity(0.5))
                    }
                    .padding(.horizontal, 20)

                    Button("Close") { dismiss() }
                        .font(.system(size:12, design:.monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.large])
        .onAppear { Task { await store.loadProducts(); await store.checkSubscriptionStatus() } }
    }

    private var supporterLine: String {
        var parts: [String] = []
        if store.isSubscribed { parts.append("Monthly supporter") }
        if store.donationCount > 0 { parts.append("Gave \(store.donationCount)× — thank you") }
        return parts.joined(separator: " · ")
    }

    private func optionCard(title: String, price: String, unit: String, button: String,
                            enabled: Bool, filled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size:13, weight:.semibold, design:.monospaced))
                .foregroundColor(.white.opacity(0.85))
            Text(price)
                .font(.system(size:32, weight:.bold, design:.monospaced))
                .foregroundColor(accentColor)
            Text(unit)
                .font(.system(size:10, design:.monospaced))
                .foregroundColor(.white.opacity(0.4))
            Button(action: action) {
                ZStack {
                    if store.isPurchasing {
                        ProgressView().tint(filled ? .black : accentColor)
                    } else {
                        Text(button)
                            .font(.system(size:14, weight:.semibold, design:.monospaced))
                            .foregroundColor(filled ? .black : accentColor)
                    }
                }
                .frame(maxWidth:.infinity).frame(height:48)
                .background(filled ? accentColor.opacity(enabled ? 1 : 0.4) : accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius:12))
                .overlay(RoundedRectangle(cornerRadius:12).stroke(accentColor.opacity(filled ? 0 : 0.5), lineWidth:1))
            }
            .disabled(store.isPurchasing || !enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius:14))
        .overlay(RoundedRectangle(cornerRadius:14).stroke(accentColor.opacity(0.18), lineWidth:0.8))
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
