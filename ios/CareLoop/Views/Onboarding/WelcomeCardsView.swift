import SwiftUI

// Swipeable onboarding cards shown when the user has no circles yet.
// Dismissed automatically once they create or join a circle.
struct WelcomeCardsView: View {
    let onCreateCircle: () -> Void
    let onJoinCircle:   () -> Void

    @State private var page = 0

    private let teal  = Color(red: 0.16, green: 0.80, blue: 0.72)
    private let blue  = Color(red: 0.13, green: 0.56, blue: 0.87)
    private let rose  = Color(red: 0.85, green: 0.30, blue: 0.50)
    private let dark  = Color(red: 0.09, green: 0.13, blue: 0.22)
    private let mid   = Color(red: 0.43, green: 0.50, blue: 0.60)

    private var isLast: Bool { page == cards.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Swipeable card stack
            TabView(selection: $page) {
                ForEach(cards.indices, id: \.self) { idx in
                    OnboardingCard(card: cards[idx])
                        .padding(.horizontal, 4)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 380)
            .animation(.easeInOut(duration: 0.3), value: page)

            // Dot indicator
            dotIndicator
                .padding(.top, 16)

            // Navigation row
            navigationRow
                .padding(.top, 20)

            // CTA — visible on last card only
            if isLast {
                ctaButtons
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isLast)
    }

    // MARK: – Dot indicator

    private var dotIndicator: some View {
        HStack(spacing: 7) {
            ForEach(cards.indices, id: \.self) { idx in
                Capsule()
                    .fill(idx == page
                          ? cards[page].accentColor
                          : Color(red: 0.82, green: 0.87, blue: 0.94))
                    .frame(width: idx == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
            }
        }
    }

    // MARK: – Navigation row

    private var navigationRow: some View {
        HStack {
            // Back
            if page > 0 {
                Button {
                    withAnimation { page -= 1 }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(mid)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 60, height: 1)
            }

            Spacer()

            // Step label
            Text("\(page + 1) of \(cards.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(mid)

            Spacer()

            // Next / Done
            if !isLast {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    HStack(spacing: 5) {
                        Text("Next")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(cards[page].accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 60, height: 1)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: – CTA buttons

    private var ctaButtons: some View {
        VStack(spacing: 12) {
            Button(action: onCreateCircle) {
                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                    Text("Start my family circle")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer()
                }
                .padding(.vertical, 17)
                .background(
                    LinearGradient(colors: [teal, blue],
                                   startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome-start-circle-button")

            Button(action: onJoinCircle) {
                HStack {
                    Spacer()
                    Image(systemName: "envelope.open.fill")
                    Text("I was invited by family")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(red: 0.82, green: 0.88, blue: 0.96), lineWidth: 1.5))
                .foregroundStyle(blue)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome-join-circle-button")
        }
    }

    // MARK: – Card data

    private var cards: [CardModel] {[
        CardModel(
            icon: "heart.circle.fill",
            gradientColors: [teal, blue],
            title: "You're not doing this alone.",
            body: "CareLoop helps your whole family pull together — so everyone knows how they can help, nothing gets forgotten, and your loved one feels the love.",
            accentColor: teal
        ),
        CardModel(
            icon: "house.and.flag.fill",
            gradientColors: [blue, Color(red: 0.08, green: 0.40, blue: 0.75)],
            title: "A home for your family's care",
            body: "Create a Circle — a cosy, private space just for your family. Name it after your loved one, and everyone you invite joins in one place.",
            accentColor: blue
        ),
        CardModel(
            icon: "person.2.fill",
            gradientColors: [teal, blue],
            title: "Get everyone involved",
            body: "Invite siblings, partners, neighbours — whoever helps out. When everyone can see what needs doing, it's easier to pitch in without being asked.",
            accentColor: teal
        ),
        CardModel(
            icon: "checklist",
            gradientColors: [blue, teal],
            title: "Never wonder who's doing what",
            body: "Add things like \"Pick up Mum's prescription\" or \"Tuesday physio\". Choose who's doing it and when — everyone gets a gentle reminder so nothing slips.",
            accentColor: blue
        ),
        CardModel(
            icon: "heart.text.square.fill",
            gradientColors: [rose, Color(red: 0.95, green: 0.55, blue: 0.30)],
            title: "Let them feel the care too",
            body: "Invite your parent or loved one so they can see all the care happening around them — and get gentle reminders for their own tasks, like a walk or a doctor's call.",
            accentColor: rose
        ),
    ]}
}

// MARK: – Card model

private struct CardModel {
    let icon:           String
    let gradientColors: [Color]
    let title:          String
    let body:           String
    let accentColor:    Color
}

// MARK: – Single card view

private struct OnboardingCard: View {
    let card: CardModel

    private let dark = Color(red: 0.09, green: 0.13, blue: 0.22)
    private let mid  = Color(red: 0.43, green: 0.50, blue: 0.60)

    var body: some View {
        VStack(spacing: 0) {
            // Icon area
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(
                        colors: card.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 160)

                Image(systemName: card.icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .symbolRenderingMode(.hierarchical)
            }

            // Text content
            VStack(alignment: .leading, spacing: 12) {
                Text(card.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(dark)
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.body)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(mid)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(red: 0.13, green: 0.22, blue: 0.45).opacity(0.08), radius: 16, x: 0, y: 4)
    }
}
