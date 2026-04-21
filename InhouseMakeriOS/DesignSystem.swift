import SwiftUI
import UIKit

enum AppPalette {
    static let bgPrimary = Color(hex: 0x0D1117)
    static let bgSecondary = Color(hex: 0x161B22)
    static let bgTertiary = Color(hex: 0x21262D)
    static let bgCard = Color(hex: 0x1C2128)
    static let bgElevated = Color(hex: 0x2D333B)

    static let textPrimary = Color(hex: 0xF0F6FC)
    static let textSecondary = Color(hex: 0x8B949E)
    static let textMuted = Color(hex: 0x6E7681)

    static let accentBlue = Color(hex: 0x4A9FFF)
    static let accentRed = Color(hex: 0xF85149)
    static let accentGreen = Color(hex: 0x3FB950)
    static let accentPurple = Color(hex: 0xA371F7)
    static let accentGold = Color(hex: 0xF0B232)
    static let accentOrange = Color(hex: 0xF0883E)

    static let teamBlue = Color(hex: 0x3B82F6)
    static let teamRed = Color(hex: 0xEF4444)
    static let border = Color(hex: 0x30363D)
}

enum AppTypography {
    static func heading(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum AppCorner {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppPalette.bgPrimary.ignoresSafeArea())
            .foregroundStyle(AppPalette.textPrimary)
    }
}

struct AppPanelModifier: ViewModifier {
    let background: Color
    let radius: CGFloat
    let stroke: Color
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(stroke, lineWidth: lineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func appBackground() -> some View {
        modifier(AppBackground())
    }

    func appPanel(
        background: Color = AppPalette.bgCard,
        radius: CGFloat = AppCorner.md,
        stroke: Color = AppPalette.border,
        lineWidth: CGFloat = 1
    ) -> some View {
        modifier(AppPanelModifier(background: background, radius: radius, stroke: stroke, lineWidth: lineWidth))
    }

    func appNavigationBarStyle(_ displayMode: NavigationBarItem.TitleDisplayMode = .inline) -> some View {
        navigationBarTitleDisplayMode(displayMode)
            .toolbarBackground(AppPalette.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(AppPalette.accentBlue)
    }
}

enum BottomActionSheetActionRole {
    case regular
    case destructive
    case cancel
}

struct BottomActionSheetAction: Identifiable {
    let id: String
    let title: String
    var role: BottomActionSheetActionRole = .regular
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    init(
        id: String,
        title: String,
        role: BottomActionSheetActionRole = .regular,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }
}

struct BottomSheetHeader: View {
    let title: String
    var titleAccessibilityIdentifier: String? = nil
    var closeAccessibilityIdentifier: String? = nil
    var showsCloseButton = true
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(AppTypography.heading(18, weight: .semibold))
                .foregroundStyle(AppPalette.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(titleAccessibilityIdentifier ?? "")

            HStack {
                Spacer()
                if showsCloseButton, let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppPalette.textMuted)
                            .frame(width: 28, height: 28)
                            .background(AppPalette.bgTertiary.opacity(0.92))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("시트 닫기")
                    .accessibilityIdentifier(closeAccessibilityIdentifier ?? "")
                }
            }
        }
        .frame(height: 32)
    }
}

struct BottomActionSheet: View {
    let title: String?
    let message: String?
    let accessibilityIdentifier: String?
    let actions: [BottomActionSheetAction]
    let onDismiss: () -> Void

    @GestureState private var dragOffset: CGFloat = 0

    init(
        title: String? = nil,
        message: String? = nil,
        accessibilityIdentifier: String? = nil,
        actions: [BottomActionSheetAction],
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.accessibilityIdentifier = accessibilityIdentifier
        self.actions = actions
        self.onDismiss = onDismiss
    }

    private var primaryActions: [BottomActionSheetAction] {
        actions.filter { $0.role != .cancel }
    }

    private var cancelAction: BottomActionSheetAction? {
        actions.first { $0.role == .cancel }
    }

    private var showsHeader: Bool {
        title != nil || message != nil
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)

                contentStack(geometry: geometry)
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .updating($dragOffset) { value, state, _ in
                                if value.translation.height > 0 {
                                    state = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 120 {
                                    dismiss()
                                }
                            }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func contentStack(geometry: GeometryProxy) -> some View {
        let stack = VStack(spacing: 12) {
            primaryActionSection

            if let cancelAction {
                actionRow(cancelAction, standalone: true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: min(geometry.size.height - 20, 420), alignment: .bottom)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)

        if let accessibilityIdentifier {
            stack
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            stack
        }
    }

    private var primaryActionSection: some View {
        VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, showsHeader ? 14 : 12)

            if showsHeader {
                VStack(spacing: 6) {
                    if let title {
                        Text(title)
                            .font(AppTypography.body(13, weight: .semibold))
                            .foregroundStyle(AppPalette.textPrimary)
                    }
                    if let message {
                        Text(message)
                            .font(AppTypography.body(12))
                            .foregroundStyle(AppPalette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ForEach(Array(primaryActions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        Rectangle()
                            .fill(AppPalette.border.opacity(0.9))
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                    }
                    actionRow(action, standalone: false)
                }
            }
        }
        .background(AppPalette.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func actionRow(_ action: BottomActionSheetAction, standalone: Bool) -> some View {
        let button = Button {
            dismiss()
            Task { @MainActor in
                action.action()
            }
        } label: {
            Text(action.title)
                .font(AppTypography.body(16, weight: action.role == .cancel ? .semibold : .regular))
                .foregroundStyle(titleColor(for: action.role))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if let accessibilityIdentifier = action.accessibilityIdentifier {
            button
                .background(standalone ? AppPalette.bgCard : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: standalone ? 18 : 0, style: .continuous))
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
                .background(standalone ? AppPalette.bgCard : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: standalone ? 18 : 0, style: .continuous))
        }
    }

    private func titleColor(for role: BottomActionSheetActionRole) -> Color {
        switch role {
        case .regular, .cancel:
            return AppPalette.textPrimary
        case .destructive:
            return AppPalette.accentRed
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            onDismiss()
        }
    }
}

struct StatusBarView: View {
    var body: some View {
        EmptyView()
    }
}

struct NavHeaderView: View {
    let title: String
    var showBack: Bool = true
    var rightSystemImage: String? = "ellipsis"
    var onBack: (() -> Void)?
    var onRightTap: (() -> Void)?

    var body: some View {
        HStack {
            headerButton(systemName: "chevron.left", isVisible: showBack, action: onBack)
            Spacer()
            Text(title)
                .font(AppTypography.heading(17, weight: .semibold))
                .foregroundStyle(AppPalette.textPrimary)
            Spacer()
            headerButton(systemName: rightSystemImage, isVisible: rightSystemImage != nil, action: onRightTap)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(AppPalette.bgPrimary)
    }

    @ViewBuilder
    private func headerButton(systemName: String?, isVisible: Bool, action: (() -> Void)?) -> some View {
        Group {
            if isVisible, let systemName {
                Button(action: { action?() }) {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)
                        .frame(width: 24, height: 24)
                }
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
    }
}

struct TabHeaderAction: Identifiable {
    let id: String
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    init(
        id: String? = nil,
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.id = id ?? accessibilityLabel
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}

struct TabNavigationHeader: View {
    let title: String
    var subtitle: String? = nil
    var leadingAction: TabHeaderAction? = nil
    var trailingAction: TabHeaderAction? = nil

    private var titleSpacing: CGFloat {
        subtitle == nil ? 0 : 2
    }

    private var headerHeight: CGFloat {
        subtitle == nil ? 38 : 44
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    headerActionSlot(leadingAction)
                    Spacer(minLength: 0)
                    headerActionSlot(trailingAction)
                }

                VStack(spacing: titleSpacing) {
                    Text(title)
                        .font(AppTypography.heading(18, weight: .semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.body(10))
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            .frame(height: headerHeight)
            .padding(.horizontal, 18)
            .padding(.top, 0)
            .padding(.bottom, 4)

            Rectangle()
                .fill(Color.white.opacity(0.018))
                .frame(height: 0.5)
                .padding(.horizontal, 18)
        }
        .background(AppPalette.bgPrimary)
    }

    @ViewBuilder
    private func headerActionSlot(_ action: TabHeaderAction?) -> some View {
        if let action {
            Button(action: action.action) {
                Image(systemName: action.systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(AppPalette.bgSecondary.opacity(0.78))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.045), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.accessibilityLabel)
            .frame(width: 42, height: 34, alignment: .center)
        } else {
            Color.clear
                .frame(width: 42, height: 34)
        }
    }
}

struct TabRootScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var leadingAction: TabHeaderAction? = nil
    var trailingAction: TabHeaderAction? = nil
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        leadingAction: TabHeaderAction? = nil,
        trailingAction: TabHeaderAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leadingAction = leadingAction
        self.trailingAction = trailingAction
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                TabNavigationHeader(
                    title: title,
                    subtitle: subtitle,
                    leadingAction: leadingAction,
                    trailingAction: trailingAction
                )
            }
    }
}

enum AppNavigationAppearance {
    static func apply() {
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithOpaqueBackground()
        navigationBarAppearance.backgroundColor = UIColor(hex: 0x0D1117)
        navigationBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(hex: 0xF0F6FC),
        ]
        navigationBarAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(hex: 0xF0F6FC),
        ]
        navigationBarAppearance.shadowColor = .clear

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = navigationBarAppearance
        navigationBar.scrollEdgeAppearance = navigationBarAppearance
        navigationBar.compactAppearance = navigationBarAppearance
        navigationBar.compactScrollEdgeAppearance = navigationBarAppearance
        navigationBar.tintColor = UIColor(hex: 0x4A9FFF)
        navigationBar.prefersLargeTitles = false

        let barButtonItem = UIBarButtonItem.appearance()
        barButtonItem.tintColor = UIColor(hex: 0x4A9FFF)
    }
}

struct SectionHeaderView: View {
    let title: String
    var trailing: String = "더보기"
    var showsTrailing: Bool = true
    var onTap: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(AppTypography.heading(16, weight: .bold))
                .foregroundStyle(AppPalette.textPrimary)
            Spacer()
            if showsTrailing, let onTap {
                Button(action: onTap) {
                    Text(trailing)
                        .font(AppTypography.body(13))
                        .foregroundStyle(AppPalette.textMuted)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 68, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PlayerCardView: View {
    let name: String
    let subtitle: String
    let powerScore: Int
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AppPalette.bgElevated)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppTypography.body(14, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)
                Text(subtitle)
                    .font(AppTypography.body(11))
                    .foregroundStyle(AppPalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(powerScore)")
                    .font(AppTypography.heading(18, weight: .bold))
                    .foregroundStyle(isHighlighted ? AppPalette.accentGold : AppPalette.accentBlue)
                Text("파워")
                    .font(AppTypography.body(10))
                    .foregroundStyle(AppPalette.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(AppPalette.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppCorner.sm))
    }
}

struct MatchCardView: View {
    let title: String
    let dateText: String
    let isWin: Bool
    let blueSummary: String
    let redSummary: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dateText)
                    .font(AppTypography.body(12))
                    .foregroundStyle(AppPalette.textMuted)
                Spacer()
                Text(isWin ? "승리" : "패배")
                    .font(AppTypography.body(11, weight: .semibold))
                    .foregroundStyle(AppPalette.bgPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isWin ? AppPalette.accentGreen : AppPalette.accentRed)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Text(blueSummary)
                    .font(AppTypography.heading(14, weight: .semibold))
                    .foregroundStyle(AppPalette.teamBlue)
                Text("vs")
                    .font(AppTypography.heading(13, weight: .bold))
                    .foregroundStyle(AppPalette.textSecondary)
                Text(redSummary)
                    .font(AppTypography.heading(14, weight: .semibold))
                    .foregroundStyle(AppPalette.teamRed)
            }
            .frame(maxWidth: .infinity)

            Text("\(title) · \(detail)")
                .font(AppTypography.body(11))
                .foregroundStyle(AppPalette.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppPalette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AppCorner.md))
    }
}

struct FilterChipView: View {
    let title: String
    let tint: Color
    var isSelected: Bool = false

    private var titleWeight: Font.Weight {
        isSelected ? .semibold : .regular
    }

    private var titleColor: Color {
        isSelected ? .white : tint
    }

    private var chipFillColor: Color {
        isSelected ? tint : AppPalette.bgTertiary
    }

    private var chipBorderColor: Color {
        isSelected ? .clear : AppPalette.border
    }

    var body: some View {
        Text(title)
            .font(AppTypography.body(11, weight: titleWeight))
            .foregroundStyle(titleColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(chipBackground)
    }

    private var chipBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        return shape
            .fill(chipFillColor)
            .overlay(
                shape.stroke(chipBorderColor, lineWidth: 1)
            )
    }
}

struct AppTabBar: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    private let previousOuterBottomPadding: CGFloat = 8
    private let outerBottomPadding: CGFloat = 4

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 7)
        .background(tabBarBackground)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, outerBottomPadding)
        .onAppear {
            debugTabBarLayout(
                "bottomInsetAdjusted old=\(Int(previousOuterBottomPadding)) new=\(Int(outerBottomPadding))"
            )
        }
    }

    private func debugTabBarLayout(_ message: String) {
        #if DEBUG
        print("[TabBarLayoutDebug] \(message)")
        #endif
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button(action: {
            guard !isSelected else { return }
            onSelect(tab)
        }) {
            AppTabBarItemContent(tab: tab, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private var tabBarBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return shape
            .fill(AppPalette.bgSecondary.opacity(0.94))
            .overlay {
                shape.fill(tabBarHighlightGradient)
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private var tabBarHighlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.02),
                Color.white.opacity(0.008)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct AppTabBarItemContent: View {
    let tab: AppTab
    let isSelected: Bool

    private var iconWeight: Font.Weight {
        isSelected ? .semibold : .medium
    }

    private var iconColor: Color {
        isSelected ? AppPalette.accentBlue : AppPalette.textMuted
    }

    private var titleWeight: Font.Weight {
        isSelected ? .semibold : .medium
    }

    private var titleColor: Color {
        isSelected ? AppPalette.textPrimary : AppPalette.textSecondary
    }

    private var capsuleFill: Color {
        isSelected ? AppPalette.bgTertiary.opacity(0.9) : .clear
    }

    private var capsuleStroke: Color {
        isSelected ? Color.white.opacity(0.04) : .clear
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: tab.iconName)
                .font(.system(size: 17, weight: iconWeight))
                .foregroundStyle(iconColor)
                .frame(height: 20)

            Text(tab.title)
                .font(AppTypography.body(10, weight: titleWeight))
                .foregroundStyle(titleColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(selectionBackground)
        .contentShape(Rectangle())
    }

    private var selectionBackground: some View {
        let shape = Capsule(style: .continuous)
        return shape
            .fill(capsuleFill)
            .overlay(
                shape.stroke(capsuleStroke, lineWidth: 1)
            )
    }
}

struct TeamColumnView: View {
    let title: String
    let tint: Color
    let background: Color
    let players: [TeamBalanceRow]

    var body: some View {
        VStack(spacing: 0) {
            titleView

            VStack(spacing: 1) {
                ForEach(players) { player in
                    TeamColumnPlayerRow(player: player, tint: tint, background: background)
                }
            }
            .background(background)
        }
        .overlay(columnBorder)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var titleView: some View {
        Text(title)
            .font(AppTypography.heading(12, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(tint)
    }

    private var columnBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(AppPalette.border, lineWidth: 1)
    }
}

private struct TeamColumnPlayerRow: View {
    let player: TeamBalanceRow
    let tint: Color
    let background: Color

    private var rowBackground: Color {
        player.isHighlighted ? tint.opacity(0.14) : background.opacity(0.96)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(player.roleLabel)
                .font(AppTypography.body(9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, alignment: .leading)

            HStack(spacing: 4) {
                Text(player.name)
                    .font(AppTypography.body(12, weight: .semibold))
                    .foregroundStyle(AppPalette.textPrimary)

                if player.isOffRole {
                    offRoleBadge
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(player.score)")
                .font(AppTypography.heading(13, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(rowBackground)
    }

    private var offRoleBadge: some View {
        Text("OFF")
            .font(AppTypography.body(8, weight: .bold))
            .foregroundStyle(AppPalette.bgPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(AppPalette.accentOrange)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct TeamBalanceRow: Identifiable, Hashable {
    let id: String
    let roleLabel: String
    let name: String
    let score: Int
    let isOffRole: Bool
    let isHighlighted: Bool
}

struct LaneComparisonBarView: View {
    let label: String
    let leftValue: Int
    let rightValue: Int
    let leftColor: Color
    let rightColor: Color

    private var leftWidthRatio: CGFloat {
        max(0.18, min(0.94, CGFloat(leftValue) / 100))
    }

    private var rightWidthRatio: CGFloat {
        max(0.18, min(0.94, CGFloat(rightValue) / 100))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(leftValue)")
                .font(AppTypography.body(11, weight: .bold))
                .foregroundStyle(leftColor)
                .frame(width: 28, alignment: .trailing)

            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let leftWidth = totalWidth * 0.47 * leftWidthRatio
                let rightWidth = totalWidth * 0.47 * rightWidthRatio
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(AppPalette.bgSecondary)
                    HStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(leftColor)
                            .frame(width: leftWidth)
                        Spacer()
                        RoundedRectangle(cornerRadius: 7)
                            .fill(rightColor)
                            .frame(width: rightWidth)
                    }
                    Text(label)
                        .font(AppTypography.body(9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppPalette.bgPrimary.opacity(0.92))
                        .clipShape(Capsule())
                }
            }
            .frame(height: 18)

            Text("\(rightValue)")
                .font(AppTypography.body(11, weight: .bold))
                .foregroundStyle(rightColor)
                .frame(width: 28, alignment: .leading)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = AppPalette.accentBlue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body(14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: AppCorner.md)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppCorner.md))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.body(14, weight: .semibold))
            .foregroundStyle(AppPalette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(AppPalette.bgTertiary.opacity(configuration.isPressed ? 0.9 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: AppCorner.md)
                    .stroke(AppPalette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppCorner.md))
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(AppTypography.heading(18, weight: .bold))
            Text(message)
                .font(AppTypography.body(13))
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle) { action?() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingStateView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppPalette.accentBlue)
            Text(title)
                .font(AppTypography.body(13))
                .foregroundStyle(AppPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let error: UserFacingError
    let retry: () -> Void
    var secondaryAction: ErrorStateAction? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(error.title)
                .font(AppTypography.heading(18, weight: .bold))
            Text(error.message)
                .font(AppTypography.body(13))
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") { retry() }
                .buttonStyle(PrimaryButtonStyle())
            if let secondaryAction {
                Button(secondaryAction.title) { secondaryAction.action() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateAction {
    let title: String
    let action: () -> Void
}

struct ToastBanner: View {
    let message: String
    let tint: Color

    var body: some View {
        Text(message)
            .font(AppTypography.body(12))
            .foregroundStyle(tint)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ScreenScaffold<Content: View>: View {
    let title: String
    var showBack: Bool = true
    var rightSystemImage: String? = nil
    var rightAccessibilityLabel: String? = nil
    var rightAccessibilityIdentifier: String? = nil
    var onBack: () -> Void
    var onRightTap: (() -> Void)?
    let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(title)
        .toolbar {
            if let rightSystemImage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { onRightTap?() }) {
                        Image(systemName: rightSystemImage)
                    }
                    .accessibilityLabel(rightAccessibilityLabel ?? rightToolbarAccessibilityLabel(for: rightSystemImage))
                    .accessibilityIdentifier(rightAccessibilityIdentifier ?? "")
                }
            }
        }
        .appNavigationBarStyle(.inline)
    }

    private func rightToolbarAccessibilityLabel(for systemImage: String) -> String {
        switch systemImage {
        case "ellipsis", "ellipsis.circle":
            return "더보기"
        default:
            return "도구"
        }
    }
}

@ViewBuilder
func screenScaffold<Content: View>(
    title: String,
    onBack: @escaping () -> Void,
    rightSystemImage: String? = nil,
    rightAccessibilityLabel: String? = nil,
    rightAccessibilityIdentifier: String? = nil,
    onRightTap: (() -> Void)? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
    ScreenScaffold(
        title: title,
        rightSystemImage: rightSystemImage,
        rightAccessibilityLabel: rightAccessibilityLabel,
        rightAccessibilityIdentifier: rightAccessibilityIdentifier,
        onBack: onBack,
        onRightTap: onRightTap,
        content: content()
    )
}

@ViewBuilder
func actionBanner(_ state: AsyncActionState) -> some View {
    switch state {
    case .idle:
        EmptyView()
    case let .inProgress(message):
        ToastBanner(message: message, tint: AppPalette.accentBlue)
            .padding(16)
    case let .success(message):
        ToastBanner(message: message, tint: AppPalette.accentGreen)
            .padding(16)
    case let .failure(message):
        ToastBanner(message: message, tint: AppPalette.accentRed)
            .padding(16)
    }
}

extension AppTab {
    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .match: return "shield.lefthalf.filled"
        case .recruit: return "megaphone.fill"
        case .history: return "scroll.fill"
        case .profile: return "person.crop.circle"
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex & 0xFF0000) >> 16) / 255,
            green: Double((hex & 0x00FF00) >> 8) / 255,
            blue: Double(hex & 0x0000FF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex & 0xFF0000) >> 16) / 255,
            green: CGFloat((hex & 0x00FF00) >> 8) / 255,
            blue: CGFloat(hex & 0x0000FF) / 255,
            alpha: alpha
        )
    }
}

extension Date {
    var shortDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: self)
    }

    var dottedDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: self)
    }
}
